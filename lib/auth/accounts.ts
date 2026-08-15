import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";
import { generatePassword } from "@/lib/auth/password";
import { normalizePhone, studentLoginEmail } from "@/lib/utils";
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
  email: string; // for students: studentLoginEmail(phone)
  fullName: string;
  phone?: string | null;
  hostelId?: string | null;
}

async function createAuthUser({ role, email, fullName, phone, hostelId }: CreateAuthUserArgs) {
  const admin = createAdminClient();
  const password = generatePassword();
  const { data, error } = await admin.auth.admin.createUser({
    email: email.toLowerCase(),
    password,
    email_confirm: true,
    phone_confirm: false,
    user_metadata: { full_name: fullName, phone: phone ?? null },
    app_metadata: { role, hostel_id: hostelId ?? null, must_change_password: true },
  });
  if (error || !data.user) {
    if (error?.message?.toLowerCase().includes("already been registered") || error?.status === 422) {
      throw new Error(
        role === "student"
          ? "A student with this phone number already has an account."
          : "An account with this email already exists.",
      );
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
 * Create the auth user for a student (login = phone number).
 * The public.users + students rows are created by the wd_register_student RPC
 * (called by the warden's server action, RLS-checked). Returns the temp password.
 */
export async function createStudentAuthUser(args: {
  fullName: string;
  phone: string;
  hostelId: string;
}): Promise<CreatedAccount> {
  const phone = normalizePhone(args.phone);
  if (phone.length < 10) throw new Error("Enter a valid 10-digit phone number.");
  const { userId, password } = await createAuthUser({
    role: "student",
    email: studentLoginEmail(phone),
    fullName: args.fullName,
    phone,
    hostelId: args.hostelId,
  });
  return { userId, loginId: phone, password };
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
