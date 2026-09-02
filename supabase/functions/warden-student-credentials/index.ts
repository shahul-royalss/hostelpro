/**
 * POST /functions/v1/warden-student-credentials
 *
 * The two things a warden can do to a resident's LOGIN after the desk has closed. Two actions
 * on one function, the shape mobile-auth already uses:
 *
 *   { "action": "reset-password", "studentId": "<uuid>" }
 *   { "action": "set-email",      "studentId": "<uuid>", "email": "a@b.com" | null }
 *
 * ═══ WHY THIS IS A RESET AND NOT A REVEAL ═══
 *
 * The owner asked for the temporary password to be "saved in their student list". Asked which
 * of the two shapes they wanted, they chose REGENERATE ON DEMAND, and this endpoint is that
 * choice made real: it MINTS a new password and shows it once. Nothing on this path stores a
 * readable password — not on students, not in a side table, not in Storage, not in a
 * notification, not in the audit meta (public.audit_event() strips password-ish keys as a
 * second line of defence, and nothing here relies on that).
 *
 * A stored temporary password is not a convenience feature. It would let any warden, manager or
 * owner sign in AS a resident — every complaint, every fee row, every leave request under that
 * resident's name and indistinguishable from them — and it would put working credentials into
 * any database leak. It also contradicts the project's own security checklist: "passwords are
 * never encrypted for reversible storage." Regenerating costs the warden one tap and costs an
 * attacker everything.
 *
 * ═══ WHO IS ALLOWED, AND FOR WHICH HOSTEL ═══
 *
 * requireCaller(req, "warden") verifies the bearer token with GoTrue and reads the role from
 * public.users — never from the body, never from the JWT's app_metadata.
 *
 * WARDEN ONLY, deliberately, and narrower than "staff". The database already answers this
 * question: app.users_update_guard computes who administers a student account as
 * `old.role = 'student' and app.has_role_in(old.hostel_id, 'warden')`. Owners can READ every
 * resident and cannot rewrite their login row; managers cannot even read one (students_select
 * is scoped to warden + owner). An Edge Function holding the service role must not quietly
 * grant a power the policies withhold, so the set of callers here is the set the schema
 * already recognises.
 *
 * The hostel is NOT accepted from the client. A warden belongs to exactly one hostel, so
 * requireOwnHostel() takes users.hostel_id, and the target student is then loaded with BOTH
 * `id = studentId` AND `hostel_id = <that hostel>`. A warden pointing this at a resident of
 * another PG gets the same "not found" a nonexistent id gets — one message for both, so the
 * endpoint is not an oracle for which student ids exist on the platform.
 *
 * assertWritable() applies the subscription/suspension gate app.hostel_writable() would have
 * applied, because everything below runs with the service role and so escapes RLS.
 *
 * ═══ THE TWO PRIVILEGED WRITES ═══
 *
 * Both need the service role and neither can be done from a phone:
 *   · the password    — GoTrue's admin API, then app.revoke_user_sessions() as a backstop over
 *                       GoTrue's own session revocation (see resetPassword — measured);
 *   · the address     — app.set_student_login_email(), which moves auth.users,
 *                       auth.identities, public.users and public.students in ONE transaction.
 *                       Editing only the profile mirror would leave a screen that shows the
 *                       corrected address and an account that still answers to the old one.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy warden-student-credentials     (see docs/edge-functions.md)
 */
import { audit } from "../_shared/audit.ts";
import { requireCaller, type Caller } from "../_shared/caller.ts";
import { dbError } from "../_shared/errors.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { generatePassword } from "../_shared/password.ts";
import { enforceRateLimit } from "../_shared/ratelimit.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { assertWritable, requireOwnHostel, type HostelContext } from "../_shared/tenant.ts";
import { requireVerifiedEmail } from "../_shared/verification.ts";
import { isStudentLoginEmail, Validator } from "../_shared/validate.ts";

/** No files on this path. A few hundred bytes of JSON is the whole request. */
const MAX_BODY_BYTES = 16 * 1024;

/**
 * The resident this call is about, already proved to belong to the caller's hostel.
 */
interface Target {
  studentId: string;
  userId: string;
  fullName: string;
  phone: string;
  /** auth.users.email — THE LOGIN, which is not always the same as students.email. */
  authEmail: string;
}

/**
 * What the resident types on the sign-in screen.
 *
 * Read off the login address rather than off students.email, because those two are allowed to
 * differ and only one of them is the answer. A resident registered without an address has the
 * synthetic <digits>@student.hostelpro.local login and a NULL students.email; showing "null" or
 * showing the synthetic address would both be wrong, and the phone number is what actually
 * works. Byte-identical in spirit to StudentCredentials.loginId on the registration path, which
 * is what StudentCredentialsDialog reads.
 */
function loginIdFor(target: Target): string {
  return isStudentLoginEmail(target.authEmail) ? target.phone : target.authEmail;
}

/**
 * Load the resident, refusing anything that is not a live student of the caller's own hostel.
 *
 * ONE MESSAGE for "no such student", "another hostel's student" and "checked out". The first
 * two must be indistinguishable or this endpoint becomes an enumeration oracle; the third is
 * folded in because a warden acting on a resident they can see never hits it, so a distinct
 * sentence there would only serve someone probing ids they cannot see.
 */
async function loadTarget(studentId: string, hostel: HostelContext): Promise<Target> {
  const admin = serviceClient();
  const notFound = new HttpError(404, "That resident is not on your hostel's roster.");

  const { data, error } = await admin
    .from("students")
    .select("id, user_id, full_name, phone, status, deleted_at, hostel_id")
    .eq("id", studentId)
    // THE TENANT PREDICATE. Not decoration: the service client bypasses RLS, so this is the
    // only thing standing between a warden and another PG's resident.
    .eq("hostel_id", hostel.id)
    .maybeSingle();
  if (error) {
    console.error("[nivora] student lookup failed:", error.message);
    throw new HttpError(500, "Could not load that resident. Please try again.");
  }
  const row = data as
    | { id: string; user_id: string | null; full_name: string; phone: string; status: string; deleted_at: string | null }
    | null;
  if (!row || row.deleted_at || row.status === "vacated") throw notFound;

  if (!row.user_id) {
    // A real and different state: the row exists and is visible, it simply has no account
    // behind it. Registrations made before warden-register-student existed look like this.
    throw new HttpError(409, row.full_name + " has no app login yet, so there is nothing to change.");
  }

  // The profile row is checked too, and against the SAME hostel. students.hostel_id and
  // users.hostel_id are written together and a trigger refuses to move either, so a
  // disagreement means something is wrong that a credential change must not run on top of.
  const { data: profile, error: profileError } = await admin
    .from("users")
    .select("id, role, hostel_id, deleted_at")
    .eq("id", row.user_id)
    .maybeSingle();
  if (profileError) {
    console.error("[nivora] profile lookup failed:", profileError.message);
    throw new HttpError(500, "Could not load that resident. Please try again.");
  }
  const user = profile as { role: string; hostel_id: string | null; deleted_at: string | null } | null;
  if (!user || user.deleted_at || user.role !== "student" || user.hostel_id !== hostel.id) throw notFound;

  const { data: authData, error: authError } = await admin.auth.admin.getUserById(row.user_id);
  if (authError || !authData?.user?.email) {
    console.error("[nivora] auth lookup failed:", authError?.message ?? "no email on the account");
    throw new HttpError(500, "Could not read that resident's login. Please try again.");
  }

  return {
    studentId: row.id,
    userId: row.user_id,
    fullName: row.full_name,
    phone: row.phone,
    authEmail: authData.user.email,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION 1 — MINT A NEW TEMPORARY PASSWORD
// ─────────────────────────────────────────────────────────────────────────────

/**
 * ORDER MATTERS, and it is chosen so that no failure can leave a resident locked out.
 *
 *   1. must_change_password first. If THIS fails nothing has moved and the old password still
 *      works — an honest failure the warden can retry. Doing it after the password change would
 *      risk a resident holding a new password with no prompt to replace it, which is a weaker
 *      but silent outcome.
 *   2. the password itself. From here the old one is dead, so nothing after this point may
 *      throw: the warden is holding the only copy of the new one.
 *   3. the sessions. Best-effort — see below.
 */
async function resetPassword(caller: Caller, hostel: HostelContext, target: Target) {
  const admin = serviceClient();
  const password = generatePassword();

  const { error: flagError } = await admin
    .from("users")
    .update({ must_change_password: true })
    .eq("id", target.userId);
  if (flagError) throw dbError(flagError, "Could not reset that password. Please try again.");

  // app_metadata is a MIRROR, never the authority — public.users above is what requireCaller()
  // and RLS read. It is kept in step anyway because every account-creation path writes it and a
  // stale mirror is the kind of thing that is read by accident later.
  const { data: current } = await admin.auth.admin.getUserById(target.userId);
  const meta = (current?.user?.app_metadata ?? {}) as Record<string, unknown>;

  const { error: authError } = await admin.auth.admin.updateUserById(target.userId, {
    password,
    app_metadata: { ...meta, must_change_password: true },
  });
  if (authError) {
    console.error("[nivora] password reset failed:", authError.message);
    // The flag is now true and the password did not change. The resident will be asked to set a
    // new password on their next sign-in with their EXISTING one, which is harmless and honest.
    throw new HttpError(400, "Could not reset that password. Please try again.");
  }

  // ── Nothing below may fail the request. The warden holds the only copy. ──

  /*
   * A reset that leaves the old sessions running is not a reset — an intruder holding a
   * refresh token does not care that the password changed.
   *
   * MEASURED, NOT ASSUMED: on this project GoTrue already revokes the sessions itself. A live
   * session, then auth.admin.updateUserById({password}), took auth.sessions for that user from
   * 1 to 0, and the open session's next refresh answered "Invalid Refresh Token: Refresh Token
   * Not Found" (2026-09-01). So this call normally deletes nothing and reports 0.
   *
   * It is made anyway, because that revocation is GoTrue's behaviour and not ours: a platform
   * upgrade could drop it silently, and the failure mode is invisible — resets would keep
   * succeeding while leaving intruders signed in. `sessionsEnded` is therefore a tripwire as
   * much as a fact. It is audited on every reset, and a value that stops being 0 is the signal
   * that this backstop has become the only thing doing the job.
   *
   * Best-effort: the credential in the response is valid whether or not this succeeded, and
   * throwing here would tell the warden the reset failed when it did not. `null` in the trail
   * means "could not tell", which is different from 0 and worth being able to distinguish.
   */
  let sessionsEnded: number | null = null;
  try {
    const { data, error } = await admin.rpc("svc_revoke_user_sessions", { p_user_id: target.userId });
    if (error) throw error;
    sessionsEnded = typeof data === "number" ? data : null;
  } catch (e) {
    console.error("[nivora] session revocation failed (non-fatal):", e instanceof Error ? e.message : String(e));
  }

  await audit("warden.student.password_reset", caller, {
    targetType: "student",
    targetId: target.studentId,
    hostelId: hostel.id,
    // No password, no address. WHO reset WHOSE credential and WHEN is the whole point of the
    // row; the trail must not become a place to read a working login out of.
    meta: {
      userId: target.userId,
      loginKind: isStudentLoginEmail(target.authEmail) ? "phone" : "email",
      sessionsEnded,
      surface: "edge_function",
    },
  });

  return ok(
    {
      credentials: { name: target.fullName, loginId: loginIdFor(target), password },
      sessionsEnded,
    },
    "New password for " + target.fullName,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION 2 — CORRECT THE LOGIN ADDRESS
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The address is the login, so this is not an edit to a contact field.
 *
 * TWO CONSEQUENCES THE WARDEN IS TOLD ABOUT RATHER THAN SURPRISED BY:
 *
 *   (a) The login moves with it. A resident who gave no address signs in with their phone
 *       number, mapped to <digits>@student.hostelpro.local; setting an address makes that
 *       address the login and the phone number stops working. Clearing it puts the phone
 *       mapping back. There is deliberately no state where both work — resolving "which
 *       account owns this number?" at sign-in needs a lookup on an unauthenticated endpoint,
 *       which is an enumeration oracle over a population of young residents.
 *
 *   (b) app.users_update_guard nulls users.email_verified_at on ANY address change, which is
 *       correct — a warden typing an address is not proof the resident reads it — and means
 *       the resident owes a fresh confirmation. `verificationCleared` in the response is what
 *       the sheet says so out of.
 *
 * The work itself is one RPC because it has to be one TRANSACTION: auth.users, auth.identities,
 * public.users and public.students all move or none do. Four separate writes from here could
 * fail between any two of them and leave a resident whose profile shows one address and whose
 * account answers to another.
 */
async function setEmail(caller: Caller, hostel: HostelContext, target: Target, email: string | null) {
  const admin = serviceClient();

  const { data, error } = await admin.rpc("svc_set_student_login_email", {
    p_user_id: target.userId,
    p_email: email,
  });
  if (error) {
    const mapped = dbError(error, "Could not change that email address.");
    // Every refusal the function raises is about the address that was typed, so it belongs
    // under the box rather than in a banner over the sheet.
    throw new HttpError(mapped.status, mapped.message, { fieldErrors: { email: [mapped.message] } });
  }

  const result = (data ?? {}) as {
    loginEmail?: string;
    changed?: boolean;
    verificationCleared?: boolean;
    phoneLogin?: boolean;
  };
  const loginEmail = result.loginEmail ?? "";
  const phoneLogin = result.phoneLogin === true;
  const changed = result.changed === true;
  const loginId = phoneLogin ? target.phone : loginEmail;

  // Only a real change is worth a row. Pressing Save on an unchanged address writes nothing to
  // the database (the RPC returns early), and a trail full of no-op entries is a trail nobody
  // reads the real entries out of.
  if (changed) {
    await audit("warden.student.email_changed", caller, {
      targetType: "student",
      targetId: target.studentId,
      hostelId: hostel.id,
      // The addresses themselves are NOT recorded. What changed and in which direction is what
      // an owner reading this needs; the resident's mailbox is not the audit log's business,
      // and public.users already holds the current value for anyone entitled to see it.
      meta: {
        userId: target.userId,
        from: isStudentLoginEmail(target.authEmail) ? "phone" : "email",
        to: phoneLogin ? "phone" : "email",
        verificationCleared: result.verificationCleared === true,
        surface: "edge_function",
      },
    });
  }

  return ok(
    {
      loginId,
      changed,
      phoneLogin,
      verificationCleared: result.verificationCleared === true,
    },
    changed
      ? phoneLogin
        ? target.fullName + " now signs in with their phone number"
        : target.fullName + " now signs in with " + loginEmail
      : "That is already their login address",
  );
}

// ─────────────────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const caller = await requireCaller(req, "warden");
    // Same gate as warden-register-student and for the same reason: this endpoint hands a
    // working password across a desk, so the account doing the handing over has to have proved
    // it is reachable first.
    requireVerifiedEmail(caller);

    const body = await readJsonBody(req, MAX_BODY_BYTES);
    const action = typeof body["action"] === "string" ? body["action"] : "";

    const hostel = await requireOwnHostel(caller);
    assertWritable(hostel);

    // One budget for both actions. A warden who has spent it is a warden doing something
    // unusual with resident credentials, whichever of the two they are doing.
    await enforceRateLimit("warden:credentials:" + caller.id);

    switch (action) {
      case "reset-password": {
        const v = new Validator(body);
        const studentId = v.uuid("studentId", "Pick a resident.");
        v.done();
        return await resetPassword(caller, hostel, await loadTarget(studentId, hostel));
      }

      case "set-email": {
        const v = new Validator(body);
        const studentId = v.uuid("studentId", "Pick a resident.");
        // Optional, and a missing/blank value MEANS something here: remove the address and put
        // the phone mapping back. That is why it is optionalEmail() and not email().
        const email = v.optionalEmail("email", 160);
        // The phone-mapping namespace is not a real mail domain and nobody may claim an address
        // in it. Typing one would mint the login id belonging to some other resident's phone
        // number and lock them out of registration for good. The RPC refuses it too; catching
        // it here is what puts the message under the box the warden typed in.
        if (email && isStudentLoginEmail(email)) v.reject("email", "Enter a real email address");
        v.done();
        return await setEmail(caller, hostel, await loadTarget(studentId, hostel), email);
      }

      default:
        return fail("Unknown action.", 400);
    }
  } catch (e) {
    return toResponse(e);
  }
});
