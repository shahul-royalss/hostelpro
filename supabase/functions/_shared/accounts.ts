/**
 * The ONLY place these functions touch the Supabase Auth admin API.
 *
 * Port of lib/auth/accounts.ts. Callers must have authorised the request first — like the web
 * helper, everything here trusts its arguments.
 *
 * Every account created here:
 *   - gets a generated password, returned once and never stored;
 *   - has must_change_password = true, in both public.users and app_metadata;
 *   - carries role + hostel_id in app_metadata as a convenience mirror. app_metadata is a
 *     MIRROR, never the authority: public.users is what RLS and requireCaller() read.
 */
import { HttpError } from "./http.ts";
import { generatePassword } from "./password.ts";
import { serviceClient } from "./supabase.ts";
import type { UserRole } from "./caller.ts";

export interface CreatedAccount {
  userId: string;
  /**
   * What the person types on the login screen. Staff: their email. Students: their email if
   * the warden collected one, otherwise their phone number. Read it, never re-derive it.
   */
  loginId: string;
  /** Temporary password — show once, never persist. */
  password: string;
}

/**
 * The outcome of an attempted rollback.
 *
 * This type is the whole point of the difference from the web version. lib/actions/super-admin.ts
 * calls `deleteAuthUser(id)`, which swallows its own error, so a rollback that itself fails is
 * indistinguishable from one that worked — and what is left behind is an auth user with no
 * public.users row and no hostel: a login that half exists, that nobody is told about, and that
 * blocks the email address from ever being used again. A clean failure is strictly better, so
 * the failure is reported instead of hidden.
 */
export interface RollbackResult {
  deleted: boolean;
  detail: string | null;
}

export async function deleteAuthUser(userId: string): Promise<RollbackResult> {
  try {
    const { error } = await serviceClient().auth.admin.deleteUser(userId);
    if (error) {
      console.error("[nivora] ROLLBACK FAILED for auth user " + userId + ": " + error.message);
      return { deleted: false, detail: error.message };
    }
    return { deleted: true, detail: null };
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    console.error("[nivora] ROLLBACK FAILED for auth user " + userId + ": " + detail);
    return { deleted: false, detail };
  }
}

/**
 * Fail the request, having already tried to undo the auth user.
 *
 * When the rollback worked the caller sees the original error and nothing was left behind.
 * When it did not, the response says so explicitly and carries the orphaned id, because
 * somebody now has to delete that account by hand and cannot do it without the id.
 */
export function rollbackAwareError(originalMessage: string, userId: string, rollback: RollbackResult): HttpError {
  if (rollback.deleted) return new HttpError(400, originalMessage);
  return new HttpError(
    500,
    originalMessage +
      " The half-created login could NOT be removed automatically — delete auth user " +
      userId +
      " in the Supabase dashboard before retrying, or the email address stays taken.",
    {
      extra: {
        rollback: { failed: true, orphanedAuthUserId: userId, detail: rollback.detail },
      },
    },
  );
}

interface CreateAuthUserArgs {
  role: UserRole;
  /** For students: their real email, or studentLoginEmail(phone) when they gave none. */
  email: string;
  fullName: string;
  phone?: string | null;
  hostelId?: string | null;
  /**
   * What to say when GoTrue reports the address is taken. The default is written for staff.
   * A student's is written by the caller, because the sentence has to name the thing the
   * warden actually typed — the phone number or the email address — and only the caller knows
   * which of the two produced this login.
   */
  duplicateMessage?: string;
}

async function createAuthUser(args: CreateAuthUserArgs): Promise<{ userId: string; password: string }> {
  const password = generatePassword();
  const { data, error } = await serviceClient().auth.admin.createUser({
    email: args.email.toLowerCase(),
    password,
    // `email_confirm: true` DOES NOT MEAN THE ADDRESS WAS PROVED, and it is deliberately still
    // here. The project has "Confirm email" ON (/auth/v1/settings reports
    // mailer_autoconfirm=false), so GoTrue refuses a password grant to a user whose
    // email_confirmed_at is null: creating accounts unconfirmed would not nag the new user, it
    // would make the temporary password unusable at the desk the warden is standing at, and it
    // would permanently lock out any resident whose only login id is the unreachable
    // <digits>@student.hostelpro.local address. So this flag now means exactly one thing —
    // "the temporary password works" — and the PROOF lives in public.users.email_verified_at,
    // which starts null here and is only ever written by the email-verification Edge Function
    // after GoTrue accepts a code the account holder read in their own inbox.
    // See supabase/functions/_shared/verification.ts.
    email_confirm: true,
    phone_confirm: false,
    user_metadata: { full_name: args.fullName, phone: args.phone ?? null },
    app_metadata: { role: args.role, hostel_id: args.hostelId ?? null, must_change_password: true },
  });
  if (error || !data?.user) {
    const message = error?.message ?? "";
    if (/already been registered|already registered/i.test(message) || error?.status === 422) {
      throw new HttpError(409, args.duplicateMessage ?? "An account with this email already exists.");
    }
    console.error("[nivora] createUser failed:", message);
    throw new HttpError(400, "Could not create the account.");
  }
  return { userId: data.user.id, password };
}

/**
 * Create an owner / manager / warden account: auth user, then the public.users row.
 *
 * The public.users insert is where the database's own rules fire — app.enforce_role_limits
 * (one active manager and one active warden per hostel) and the users_one_active_staff_per_hostel
 * unique index that settles the race the trigger's count(*) cannot. The service role bypasses
 * RLS but NOT triggers, so those still decide. If the insert loses, the auth user is rolled
 * back and the rollback's own outcome is reported.
 */
export async function createStaffAccount(args: {
  role: Extract<UserRole, "owner" | "manager" | "warden">;
  fullName: string;
  email: string;
  phone?: string | null;
  /** owner: null at creation — sa_create_hostel_with_subscription sets it. */
  hostelId?: string | null;
  createdBy: string;
}): Promise<CreatedAccount> {
  const email = args.email.trim().toLowerCase();
  const { userId, password } = await createAuthUser({
    role: args.role,
    email,
    fullName: args.fullName,
    phone: args.phone ?? null,
    hostelId: args.hostelId ?? null,
  });

  const { error } = await serviceClient().from("users").insert({
    id: userId,
    role: args.role,
    full_name: args.fullName.trim(),
    email,
    phone: args.phone ?? null,
    hostel_id: args.hostelId ?? null,
    status: "active",
    must_change_password: true,
    created_by: args.createdBy,
  });
  if (error) {
    const { dbError } = await import("./errors.ts");
    const friendly = dbError(error).message;
    throw rollbackAwareError(friendly, userId, await deleteAuthUser(userId));
  }
  return { userId, loginId: email, password };
}

/**
 * Create the auth user for a student. The public.users and public.students rows are created by
 * wd_register_student, called as the warden so the database re-checks the role and the
 * subscription gate itself.
 *
 * ── A STUDENT HAS EXACTLY ONE LOGIN ID ───────────────────────────────────────────────────
 * [loginEmail] is the resident's REAL email when the warden collected one and
 * studentLoginEmail(phone) when they did not. Both clients resolve what is typed on the
 * sign-in screen with the same pure function, so the id the resident is handed here is the
 * id that works: an email signs in as itself, a bare phone number is mapped to the synthetic
 * address. There is deliberately no third case where a student can use either — that would
 * need a phone→email lookup at sign-in, and a lookup on an unauthenticated endpoint is an
 * account-enumeration oracle over a population of young residents.
 *
 * [loginId] is therefore the email or the phone number, whichever [loginEmail] was built
 * from, and it is what StudentCredentialsDialog puts in front of the warden.
 */
export async function createStudentAuthUser(args: {
  fullName: string;
  /** Already normalised to 10 digits by Validator.phone10(). */
  phone: string;
  hostelId: string;
  loginEmail: string;
  /** What the resident types to sign in: the email, or the phone number. */
  loginId: string;
  duplicateMessage: string;
}): Promise<CreatedAccount> {
  const { userId, password } = await createAuthUser({
    role: "student",
    email: args.loginEmail,
    fullName: args.fullName,
    phone: args.phone,
    hostelId: args.hostelId,
    duplicateMessage: args.duplicateMessage,
  });
  return { userId, loginId: args.loginId, password };
}

/**
 * Mirror hostel_id into app_metadata after the hostel exists. Best-effort by design:
 * users.hostel_id, set by the RPC, is the source of truth, so a failure here is cosmetic.
 */
export async function syncHostelMetadata(userId: string, hostelId: string): Promise<void> {
  try {
    const { data } = await serviceClient().auth.admin.getUserById(userId);
    const meta = (data?.user?.app_metadata ?? {}) as Record<string, unknown>;
    await serviceClient().auth.admin.updateUserById(userId, { app_metadata: { ...meta, hostel_id: hostelId } });
  } catch (e) {
    console.error("[nivora] app_metadata hostel sync failed (non-fatal):", e instanceof Error ? e.message : String(e));
  }
}
