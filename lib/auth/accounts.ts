import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { generatePassword } from "@/lib/auth/password";
import { normalizePhone, STUDENT_LOGIN_DOMAIN, studentLoginEmail } from "@/lib/utils";
import type { UserRole } from "@/lib/roles";

/**
 * Account helpers — the ONLY place we touch Supabase Auth admin APIs.
 * Callers MUST authorise first (requireRole / assertRole) — these helpers trust the caller.
 *
 * Every created account:
 *   • gets a generated password (returned once, never stored in plaintext)
 *   • has must_change_password = true (enforced by middleware → /change-password)
 *   • carries role + hostel_id in app_metadata (read by middleware, cannot be edited by the user)
 */

export interface CreatedAccount {
  userId: string;
  loginId: string; // what the user types on the login screen (email or phone)
  password: string; // temporary password — show once
}

interface CreateAuthUserArgs {
  role: UserRole;
  email: string; // students: their real address, or studentLoginEmail(phone) when they gave none
  fullName: string;
  phone?: string | null;
  hostelId?: string | null;
  /**
   * What to say when GoTrue reports the address is taken. Defaults to the staff sentence.
   * A student's is passed in, because it has to name what the warden actually typed — the
   * phone number or the email — and only the caller knows which produced this login.
   */
  duplicateMessage?: string;
}

async function createAuthUser({ role, email, fullName, phone, hostelId, duplicateMessage }: CreateAuthUserArgs) {
  const admin = createAdminClient();
  const password = generatePassword();
  const { data, error } = await admin.auth.admin.createUser({
    email: email.toLowerCase(),
    password,
    // NOT a proof of ownership — see the long note on the same line in
    // supabase/functions/_shared/accounts.ts. The project has "Confirm email" ON, so GoTrue
    // would refuse the temporary password to an unconfirmed user; this flag only keeps that
    // password working. Whether the person actually reads the address is recorded in
    // public.users.email_verified_at, which starts null and is written only by the
    // email-verification Edge Function.
    email_confirm: true,
    phone_confirm: false,
    user_metadata: { full_name: fullName, phone: phone ?? null },
    app_metadata: { role, hostel_id: hostelId ?? null, must_change_password: true },
  });
  if (error || !data.user) {
    if (error?.message?.toLowerCase().includes("already been registered") || error?.status === 422) {
      throw new Error(duplicateMessage ?? "An account with this email already exists.");
    }
    throw new Error(error?.message ?? "Could not create the account.");
  }
  return { userId: data.user.id, password };
}

/** Roll back an auth user if the profile/DB step fails afterwards. */
export async function deleteAuthUser(userId: string) {
  const admin = createAdminClient();
  await admin.auth.admin.deleteUser(userId).catch(() => {});
}

/**
 * Create a staff/owner account (owner | manager | warden) + its public.users row.
 * The role-limit trigger (1 manager / 1 warden per hostel) fires on the insert and
 * surfaces a friendly message; on failure the auth user is deleted again.
 */
export async function createStaffAccount(args: {
  role: Extract<UserRole, "owner" | "manager" | "warden">;
  fullName: string;
  email: string;
  phone?: string | null;
  hostelId?: string | null; // owner: null at creation (set by sa_create_hostel_with_subscription)
  createdBy: string;
}): Promise<CreatedAccount> {
  const admin = createAdminClient();
  const email = args.email.trim().toLowerCase();
  const phone = args.phone ? normalizePhone(args.phone) : null;
  const { userId, password } = await createAuthUser({
    role: args.role,
    email,
    fullName: args.fullName,
    phone,
    hostelId: args.hostelId ?? null,
  });

  const { error } = await admin.from("users").insert({
    id: userId,
    role: args.role,
    full_name: args.fullName.trim(),
    email,
    phone,
    hostel_id: args.hostelId ?? null,
    status: "active",
    must_change_password: true,
    created_by: args.createdBy,
  });
  if (error) {
    await deleteAuthUser(userId);
    throw new Error(error.message);
  }
  return { userId, loginId: email, password };
}

/**
 * Create the auth user for a student.
 *
 * LOGIN = the resident's own email when the warden collected one, otherwise their phone
 * number mapped through studentLoginEmail(). Email is optional and stays optional — a hostel
 * resident may genuinely not have one, which is why the phone mapping exists at all — but when
 * it is present it is the login, not an alternative to it. resolveLoginEmail() in lib/utils.ts
 * already resolves both forms of what is typed on the sign-in screen, and the Flutter client
 * holds a byte-identical copy; keep all three in step.
 *
 * This mirrors supabase/functions/warden-register-student/index.ts, which is the path the
 * mobile app takes. The two MUST agree: a resident registered on the web and one registered on
 * a phone have to end up with the same kind of login, or "what do I type?" has two answers.
 *
 * The public.users + students rows are created by the wd_register_student RPC (called by the
 * warden's server action, RLS-checked). Returns the temp password.
 */
export async function createStudentAuthUser(args: {
  fullName: string;
  phone: string;
  hostelId: string;
  /** The resident's real address, already validated. Empty / undefined means they gave none. */
  email?: string | null;
}): Promise<CreatedAccount> {
  const phone = normalizePhone(args.phone);
  if (phone.length < 10) throw new Error("Enter a valid 10-digit phone number.");
  const email = args.email?.trim().toLowerCase() || null;
  // Nobody may claim an address inside the phone-mapping namespace: it would mint the login id
  // belonging to another resident's number and block them from ever being registered.
  if (email && email.endsWith(`@${STUDENT_LOGIN_DOMAIN}`)) throw new Error("Enter a real email address");
  const { userId, password } = await createAuthUser({
    role: "student",
    email: email ?? studentLoginEmail(phone),
    fullName: args.fullName,
    phone,
    hostelId: args.hostelId,
    duplicateMessage: email
      ? "A student with this email address already has an account."
      : "A student with this phone number already has an account.",
  });
  return { userId, loginId: email ?? phone, password };
}

/** Regenerate a temporary password (SA → owner, Owner → manager/warden). Shown once. */
export async function regeneratePassword(userId: string): Promise<string> {
  const admin = createAdminClient();
  const password = generatePassword();
  const { data: existing } = await admin.auth.admin.getUserById(userId);
  const meta = (existing?.user?.app_metadata ?? {}) as Record<string, unknown>;
  const { error } = await admin.auth.admin.updateUserById(userId, {
    password,
    app_metadata: { ...meta, must_change_password: true },
  });
  if (error) throw new Error(error.message);
  await admin.from("users").update({ must_change_password: true }).eq("id", userId);
  return password;
}

/** Keep app_metadata in sync after a user changes their own password. */
export async function clearMustChangePassword(userId: string) {
  const admin = createAdminClient();
  const { data: existing } = await admin.auth.admin.getUserById(userId);
  const meta = (existing?.user?.app_metadata ?? {}) as Record<string, unknown>;
  await admin.auth.admin.updateUserById(userId, {
    app_metadata: { ...meta, must_change_password: false },
  });
  await admin.from("users").update({ must_change_password: false }).eq("id", userId);
}

/** Activate / deactivate an account (frees role slot; blocks login via users.status). */
export async function setAccountStatus(userId: string, status: "active" | "inactive") {
  const admin = createAdminClient();
  const { error } = await admin.from("users").update({ status }).eq("id", userId);
  if (error) throw new Error(error.message);
  // Ban at the auth layer too so the session can't be reused
  await admin.auth.admin.updateUserById(userId, {
    ban_duration: status === "inactive" ? "876000h" : "none",
  });
}

/** Sync hostel_id into app_metadata (e.g. after sa_create_hostel_with_subscription). */
export async function syncHostelMetadata(userId: string, hostelId: string) {
  const admin = createAdminClient();
  const { data: existing } = await admin.auth.admin.getUserById(userId);
  const meta = (existing?.user?.app_metadata ?? {}) as Record<string, unknown>;
  await admin.auth.admin.updateUserById(userId, { app_metadata: { ...meta, hostel_id: hostelId } });
}
