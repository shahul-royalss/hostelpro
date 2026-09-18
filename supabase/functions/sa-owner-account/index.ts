/**
 * POST /functions/v1/sa-owner-account
 *
 * What the Super Admin can do to an OWNER's login once the account exists. Two actions on one
 * function, the shape warden-student-credentials already uses for residents:
 *
 *   { "action": "reset-password", "hostelId": "<uuid>" }
 *   { "action": "set-email",      "hostelId": "<uuid>", "email": "owner@example.com" }
 *
 * ═══ WHY THE BODY NAMES A HOSTEL AND NEVER A USER ═══
 *
 * The console is looking at a hostel when the Super Admin taps "reset the owner's password", and
 * the owner is whoever hostels.owner_user_id says, read here with the service client. A body that
 * carried a user id would make this endpoint "set the password of any account on the platform"
 * for whoever holds a Super Admin session — another super admin, a warden, a resident — and every
 * check below would then be defending that primitive instead of never offering it.
 *
 * The resolved account must still be an active, non-deleted `owner` row. owner_user_id is a
 * foreign key to users, not to owners, so a hostel whose owner row was demoted, deactivated or
 * pointed at a super_admin is refused rather than acted on.
 *
 * ═══ WHO IS ALLOWED ═══
 *
 * requireCaller(req, "super_admin"): the role comes from public.users, and the second factor is
 * enforced there (aal2, or the audited no-factor grace arm). Then requireVerifiedEmail(), the gate
 * sa-create-owner applies, because reset-password hands a working credential to whoever is
 * holding the phone.
 *
 * ═══ THE TOKENS A NEW PASSWORD DOES NOT CANCEL ═══
 *
 * Both actions are how the Super Admin takes a login back from somebody who should not have it,
 * and neither a new password nor an ended session stops a token that is already out:
 * /auth/v1/verify needs only the token. An address change the account started (PUT /auth/v1/user
 * needs nothing but an owner access token and the anon key that ships in the APK) would move the
 * login to its new address afterwards, and a recovery or magic link mailed earlier would still
 * sign its holder in. Both actions cancel every such token (app.clear_pending_login_tokens).
 *
 * ═══ RESET, NOT REVEAL ═══
 *
 * Same decision as for residents: a password is minted, shown once in this response and stored
 * nowhere — not in a table, not in a log line, not in the audit meta. must_change_password goes
 * true in public.users (the authority) and app_metadata (the mirror), so the owner replaces it at
 * their next sign-in, and their existing sessions are ended.
 *
 * ═══ THE ADDRESS IS THE LOGIN ═══
 *
 * Owners sign in with their email, so set-email moves the login, not a contact field. It is one
 * RPC, public.svc_set_owner_login_email, because it has to be one transaction:
 *
 *   · auth.users.email and auth.identities, with email_confirmed_at stamped — what GoTrue's
 *     email_confirm: true does. "Confirm email" is ON for this project, so an unconfirmed address
 *     could not sign in at all. The stamp records that the Super Admin typed the address, nothing
 *     more.
 *   · public.users.email. app.users_update_guard nulls email_verified_at on any address change,
 *     for every writer, so the owner still has to prove the new mailbox is theirs.
 *   · the pending tokens above. GoTrue's admin API changes the address and leaves them redeemable.
 *   · every session. GoTrue ends none on an address change.
 *
 * All of it lands or none of it does. There is no rollback to attempt from here, and no success
 * response can go out over sessions that survived.
 *
 * ═══ DEPLOY ═══
 *   Apply db/migrations/2026-09-16-sa-hostel-controls.sql first: both actions call RPCs it adds.
 *   supabase functions deploy sa-owner-account     (verify_jwt ON — see docs/edge-functions.md)
 */
import { audit } from "../_shared/audit.ts";
import { requireCaller, type Caller } from "../_shared/caller.ts";
import { dbError } from "../_shared/errors.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { generatePassword } from "../_shared/password.ts";
import { enforceRateLimit } from "../_shared/ratelimit.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireVerifiedEmail } from "../_shared/verification.ts";
import { isStudentLoginEmail, Validator } from "../_shared/validate.ts";

/** A hostel id and an address. Nothing on this path is larger than a few hundred bytes. */
const MAX_BODY_BYTES = 16 * 1024;

const EMAIL_TAKEN = "That email address already belongs to another account.";

/** The owner this call is about, resolved from the hostel and never from the body. */
interface Target {
  hostelId: string;
  hostelName: string;
  userId: string;
  fullName: string;
  /** auth.users.email — THE LOGIN, and what the owner types on the sign-in screen. */
  authEmail: string;
  /** Carried so must_change_password is merged into the mirror rather than written over it. */
  appMetadata: Record<string, unknown>;
}

function emailFieldError(status: number, message: string): HttpError {
  return new HttpError(status, message, { fieldErrors: { email: [message] } });
}

function errText(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (e && typeof e === "object" && "message" in e) return String((e as { message: unknown }).message);
  return String(e);
}

/**
 * Enough of an address to tell two apart in the trail, not enough to mail anybody:
 * "asha.rao@example.com" -> "a***@example.com".
 */
function maskEmail(address: string): string {
  const at = address.lastIndexOf("@");
  if (at < 1) return "***";
  return address.slice(0, 1) + "***" + address.slice(at);
}

/**
 * Hostel -> owner row -> GoTrue user, refusing anything that is not a live owner.
 *
 * No enumeration concern shapes the messages here, unlike the warden path: the only caller is the
 * Super Admin, who can already list every hostel on the platform. So "no such hostel" and "no
 * usable owner" are told apart, because the console can act on the difference.
 */
async function loadTarget(hostelId: string): Promise<Target> {
  const admin = serviceClient();

  const { data: hostelRow, error: hostelError } = await admin
    .from("hostels")
    .select("id, name, owner_user_id")
    .eq("id", hostelId)
    .maybeSingle();
  if (hostelError) {
    console.error("[nivora] hostel lookup failed:", hostelError.message);
    throw new HttpError(500, "Could not load that hostel. Please try again.");
  }
  const hostel = hostelRow as { id: string; name: string; owner_user_id: string | null } | null;
  if (!hostel) throw new HttpError(404, "That hostel does not exist.");
  if (!hostel.owner_user_id) throw new HttpError(409, hostel.name + " has no owner account.");

  const { data: profileRow, error: profileError } = await admin
    .from("users")
    .select("id, role, status, full_name, deleted_at")
    .eq("id", hostel.owner_user_id)
    .maybeSingle();
  if (profileError) {
    console.error("[nivora] owner profile lookup failed:", profileError.message);
    throw new HttpError(500, "Could not load that owner. Please try again.");
  }
  const profile = profileRow as
    | { id: string; role: string; status: string; full_name: string; deleted_at: string | null }
    | null;

  // THE ROLE GATE. Exactly `owner`. This is what stops a hostel row from becoming a way to reset a
  // super admin's password, whatever owner_user_id has been made to point at.
  if (!profile || profile.role !== "owner") {
    throw new HttpError(409, hostel.name + " has no owner account that can be changed here.");
  }
  if (profile.deleted_at || profile.status !== "active") {
    throw new HttpError(409, "The owner account for " + hostel.name + " is inactive. Reactivate it before changing its login.");
  }

  const { data: authData, error: authError } = await admin.auth.admin.getUserById(profile.id);
  if (authError || !authData?.user?.email) {
    console.error("[nivora] owner auth lookup failed:", authError?.message ?? "no email on the account");
    throw new HttpError(500, "Could not read that owner's login. Please try again.");
  }

  return {
    hostelId: hostel.id,
    hostelName: hostel.name,
    userId: profile.id,
    fullName: profile.full_name,
    authEmail: authData.user.email,
    appMetadata: (authData.user.app_metadata ?? {}) as Record<string, unknown>,
  };
}

/**
 * End every session the owner holds, after a password reset.
 *
 * GoTrue already does this itself on a password change (measured 2026-09-01, see
 * warden-student-credentials), so this is the backstop that makes the property ours, and a
 * `sessionsEnded` that stops being 0 in the trail is the sign GoTrue changed. Best-effort for
 * that reason: the credential in the response is valid either way. `null` means "could not
 * tell", kept distinct from 0. (set-email ends sessions inside its own transaction instead.)
 */
async function revokeSessions(userId: string): Promise<number | null> {
  try {
    const { data, error } = await serviceClient().rpc("svc_revoke_user_sessions", { p_user_id: userId });
    if (error) {
      console.error("[nivora] session revocation failed (non-fatal):", error.message);
      return null;
    }
    return typeof data === "number" ? data : null;
  } catch (e) {
    console.error("[nivora] session revocation failed:", errText(e));
    return null;
  }
}

/**
 * Cancel the owner's pending address-change, recovery and magic-link tokens. true when there was
 * something to cancel; null when the call failed, which the caller decides how to treat.
 */
async function clearPendingTokens(userId: string): Promise<boolean | null> {
  try {
    const { data, error } = await serviceClient().rpc("svc_clear_owner_login_tokens", { p_user_id: userId });
    if (error) {
      console.error("[nivora] pending token clear failed:", error.message);
      return null;
    }
    return data === true;
  } catch (e) {
    console.error("[nivora] pending token clear failed:", errText(e));
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION 1 — MINT A NEW TEMPORARY PASSWORD
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The order is warden-student-credentials' and for the same reason: no failure may leave the
 * owner holding a password nobody knows.
 *
 *   1. must_change_password. If this fails nothing has moved and the old password still works.
 *   2. pending tokens, FAILING CLOSED. A reset that leaves an intruder's address change
 *      redeemable has not taken the login back, and nothing irreversible has happened yet.
 *   3. the password. From here the old one is dead, so nothing after it may throw.
 *   4. the sessions, then the tokens once more. An intruder's session that outlived step 2 by a
 *      few milliseconds could have started a new change; once the sessions are gone it cannot
 *      start another. Best-effort, and both results go in the trail.
 */
async function resetPassword(caller: Caller, target: Target): Promise<Response> {
  const admin = serviceClient();
  const password = generatePassword();

  // `role = owner` again, in the write itself: a role that changed between loadTarget() and this
  // line matches no row, and the reset stops before a password exists.
  const { data: flagged, error: flagError } = await admin
    .from("users")
    .update({ must_change_password: true })
    .eq("id", target.userId)
    .eq("role", "owner")
    .select("id");
  if (flagError) throw dbError(flagError, "Could not reset that password. Please try again.");
  if (!flagged?.length) {
    throw new HttpError(409, "That owner account changed while this was being saved. Reload and try again.");
  }

  const tokensCleared = await clearPendingTokens(target.userId);
  if (tokensCleared === null) {
    // The flag is true and nothing else moved: the owner is asked to choose a new password at their
    // next sign-in with the one they already have. Harmless, and the Super Admin can retry.
    throw new HttpError(500, "Could not reset that password. Please try again.");
  }

  const { error: authError } = await admin.auth.admin.updateUserById(target.userId, {
    password,
    app_metadata: { ...target.appMetadata, must_change_password: true },
  });
  if (authError) {
    console.error("[nivora] owner password reset failed:", authError.message);
    throw new HttpError(400, "Could not reset that password. Please try again.");
  }

  // ── Nothing below may fail the request. The Super Admin holds the only copy. ──

  const sessionsEnded = await revokeSessions(target.userId);
  const tokensClearedAfter = await clearPendingTokens(target.userId);

  await audit("sa.owner.password_reset", caller, {
    targetType: "user",
    targetId: target.userId,
    hostelId: target.hostelId,
    // No password and no address: WHO reset WHOSE login and WHEN is the whole row.
    meta: {
      sessionsEnded,
      pendingTokensCleared: tokensCleared,
      pendingTokensClearedAfter: tokensClearedAfter,
      surface: "edge_function",
    },
  });

  return ok(
    { ownerName: target.fullName, loginId: target.authEmail, password },
    "New password for " + target.fullName,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION 2 — MOVE THE LOGIN TO A NEW ADDRESS
// ─────────────────────────────────────────────────────────────────────────────

async function setEmail(caller: Caller, target: Target, email: string): Promise<Response> {
  const admin = serviceClient();

  // Saving the address the owner already has writes nothing, so it does not cost them their
  // verified status or their sessions. The RPC makes the same check under its row lock.
  if (target.authEmail.trim().toLowerCase() === email) {
    return ok({ ownerName: target.fullName, loginId: target.authEmail }, "That is already " + target.fullName + "'s login address");
  }

  // The friendly refusal, which puts the message under the box. It is NOT the authority: the RPC
  // checks both tables again inside its transaction, and users_email_key and GoTrue's
  // users_email_partial_key still get their say. `.eq` and not `.ilike`, because every path that
  // writes an address lowercases it, and a LIKE pattern would turn `_` in a real address into a
  // wildcard that matches somebody else's.
  const { data: clash, error: clashError } = await admin
    .from("users")
    .select("id")
    .eq("email", email)
    .neq("id", target.userId)
    .limit(1);
  if (clashError) {
    console.error("[nivora] email clash check failed:", clashError.message);
    throw new HttpError(500, "Could not check that email address. Please try again.");
  }
  if (clash?.length) throw emailFieldError(409, EMAIL_TAKEN);

  const { data, error } = await admin.rpc("svc_set_owner_login_email", {
    p_user_id: target.userId,
    p_email: email,
  });
  if (error) {
    // 23505 is raised by the RPC's own clash check and by either unique index, whichever is first.
    if (error.code === "23505") throw emailFieldError(409, EMAIL_TAKEN);
    // HINT 'email' marks a refusal of the address itself, which belongs under the box.
    if (error.code === "P0001" && error.hint === "email") throw emailFieldError(409, error.message);
    // Any other P0001 is about the account (demoted or deactivated since loadTarget()).
    if (error.code === "P0001") throw new HttpError(409, error.message);
    throw dbError(error, "Could not change that email address. Please try again.");
  }

  const result = (data ?? {}) as {
    loginEmail?: string;
    changed?: boolean;
    verificationCleared?: boolean;
    sessionsEnded?: number;
    pendingTokensCleared?: boolean;
  };
  const loginId = typeof result.loginEmail === "string" && result.loginEmail ? result.loginEmail : email;

  if (result.changed !== true) {
    return ok({ ownerName: target.fullName, loginId }, "That is already " + target.fullName + "'s login address");
  }

  // ── The transaction has committed: address, tokens and sessions all moved. ──

  await audit("sa.owner.email_change", caller, {
    targetType: "user",
    targetId: target.userId,
    hostelId: target.hostelId,
    // Masked, both of them: enough to see that the login moved and roughly where, not a copy of the
    // owner's mailbox in a table the whole trail can be read out of.
    meta: {
      from: maskEmail(target.authEmail),
      to: maskEmail(loginId),
      verificationCleared: result.verificationCleared === true,
      sessionsEnded: typeof result.sessionsEnded === "number" ? result.sessionsEnded : null,
      pendingTokensCleared: result.pendingTokensCleared === true,
      surface: "edge_function",
    },
  });

  return ok({ ownerName: target.fullName, loginId }, target.fullName + " now signs in with " + loginId);
}

// ─────────────────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const caller = await requireCaller(req, "super_admin");
    requireVerifiedEmail(caller);

    const body = await readJsonBody(req, MAX_BODY_BYTES);
    const action = typeof body["action"] === "string" ? body["action"] : "";
    if (action !== "reset-password" && action !== "set-email") return fail("Unknown action.", 400);

    const v = new Validator(body);
    const hostelId = v.uuid("hostelId", "Pick a hostel.");
    const email = action === "set-email" ? v.email("email", { max: 200 }) : "";
    v.done();
    // The phone-mapping namespace is not a mail domain and nobody may claim an address in it: it
    // would take the login id belonging to some resident's phone number, permanently.
    if (action === "set-email" && isStudentLoginEmail(email)) {
      throw emailFieldError(409, "Enter a real email address");
    }

    // One budget for both actions, per Super Admin, durable and fail-closed. Spent before the
    // lookups so a looping client cannot use this endpoint to make the database do work for free.
    await enforceRateLimit("sa:owner-account:" + caller.id);

    const target = await loadTarget(hostelId);
    return action === "reset-password"
      ? await resetPassword(caller, target)
      : await setEmail(caller, target, email);
  } catch (e) {
    return toResponse(e);
  }
});
