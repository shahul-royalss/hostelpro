/**
 * EMAIL VERIFICATION — the gate, and the one place that turns GoTrue's record into our proof.
 *
 * ═══ THE DECISION THIS FILE IMPLEMENTS ═══
 *
 * Every account-creation path passes `email_confirm: true`, so `auth.users.email_confirmed_at`
 * is stamped for every account this project has ever had. That flag records that somebody TYPED
 * an address, never that the person who owns it answered.
 *
 * The obvious fix — stop auto-confirming — is the wrong one here, and the reason is measurable:
 *
 *     GET /auth/v1/settings  ->  {"mailer_autoconfirm": false, ...}   (re-checked 2026-09-01)
 *
 * "Confirm email" is ON at the project level, so GoTrue refuses a password grant to a user
 * whose email_confirmed_at is null. An unconfirmed account cannot sign in AT ALL. That turns a
 * nag into a lockout:
 *
 *   · the hostel desk breaks — a warden registers a resident standing in front of them and can
 *     no longer hand over a working login;
 *   · a typo'd address becomes unrecoverable, and the person who could fix it may themselves be
 *     locked out behind the same rule;
 *   · a resident registered without an email has the login <digits>@student.hostelpro.local,
 *     which no mail server accepts — a proof that can never be produced.
 *
 * So creation still confirms at GoTrue (that flag now means only "the temporary password
 * works"), and the PROOF lives in `public.users.email_verified_at`, which starts NULL for every
 * account that has ever existed. The account can sign in and run the PG; what it cannot do
 * until it verifies is MINT ANOTHER ACCOUNT — see requireVerifiedEmail() and its three call
 * sites. That is the one action where an unproved address turns into credentials in a
 * stranger's inbox, which is why it is the action that is gated.
 *
 * ═══ 2026-09-01: A LINK, NOT A CODE — AND WHY THAT CHANGED THIS FILE ═══
 *
 * This file used to SEND the proof as well as check it: signInWithOtp() here, verifyOtp() here,
 * a durable per-user send counter here. That put an Edge Function in the sending path —
 * app -> this function -> GoTrue -> mail — and the owner's failure screenshot ("The Nivora
 * server did not answer") was the phone's 15s deadline expiring on exactly that hop, while this
 * free-tier NANO instance had PostgREST and Auth flipping to Unhealthy at ~72% RAM.
 *
 * A confirmation LINK is composed and sent by GoTrue itself, so the app now calls /auth/v1/otp
 * directly and the path is app -> GoTrue -> mail. One fewer hop, and the hop removed is the
 * component that keeps failing. Nothing in this file sends anything any more.
 *
 * What it does instead is turn GoTrue's own record of the click into our column. That work is
 * in public.email_link_proof() — a SECURITY DEFINER read of auth.flow_state.auth_code_issued_at
 * and auth.audit_log_entries, both written by GoTrue inside the transaction that matched the
 * single-use token it emailed. The full argument, including why an auth-schema trigger and a
 * hand-rolled token table were both rejected, is in
 * db/migrations/2026-09-01-email-link-verification.sql; the two tables it names there were
 * MEASURED WRONG against a real click and replaced by
 * db/migrations/2026-09-02-email-link-proof-pkce.sql, which is what runs today.
 *
 * ═══ 2026-09-01: THE LINK NOW OPENS THE APP, AND THIS FILE DID NOT HAVE TO CHANGE ═══
 *
 * The redirect became a custom scheme (app.nivora.mobile://verify-email) so that the link opens
 * Nivora and signs the person in, which is what the owner asked for. Nothing here moved, and
 * that is worth saying rather than assuming: both arms of email_link_proof() are written by
 * GoTrue's /auth/v1/verify handler BEFORE the 303, and the redirect target does not participate
 * in either. A deep link adds a later code exchange on top; it takes nothing away. Verified
 * against three real clicks on this project (2026-09-01) — see docs/email-verification.md §6.
 *
 * ═══ WHAT WAS GIVEN UP, SAID PLAINLY ═══
 *
 * The durable per-user send counter (app.rate_limits, service-role only) is gone, because the
 * client now talks to GoTrue and cannot be made to spend a counter it does not hold. What is
 * left standing in its place:
 *
 *   · GoTrue's SMTP_MAX_FREQUENCY — 60s minimum between mails to one user, server-side;
 *   · GOTRUE_RATE_LIMIT_EMAIL_SENT — 30/hour, project-wide;
 *   · the app's own cooldown, which is courtesy and stops a user tapping into an error.
 *
 * And the thing the counter was NOT protecting, which is worth stating so nobody mourns it:
 * /auth/v1/otp is a public endpoint and the anon key is published inside the APK. Anyone who
 * wanted to make this project send mail could always call it directly. The Edge Function
 * constrained OUR app, not an attacker.
 */
import { audit } from "./audit.ts";
import type { Caller } from "./caller.ts";
import { HttpError } from "./http.ts";
import { serviceClient } from "./supabase.ts";

/** Mirrors STUDENT_LOGIN_DOMAIN in validate.ts and app.email_is_reachable() in the database. */
const STUDENT_LOGIN_DOMAIN = "student.hostelpro.local";

/** Can this address actually receive mail? Mirrors app.email_is_reachable() in Postgres. */
export function isReachableAddress(email: string | null | undefined): boolean {
  const e = (email ?? "").trim().toLowerCase();
  return e.length > 0 && !e.endsWith("@" + STUDENT_LOGIN_DOMAIN);
}

/**
 * THE GATE. Refuses a caller who has a real address and has not proved it.
 *
 * UNCHANGED BY THE MOVE TO LINKS, deliberately. This is the security boundary: it reads
 * `public.users.email_verified_at` from the profile row requireCaller() already resolved with
 * the service client, and it is called by sa-create-owner, owner-create-staff and
 * warden-register-student before any of them mints an account. How the proof was earned is not
 * its business; that it exists, is.
 *
 * A resident whose only login id is the synthetic phone address passes, because there is
 * nothing they could ever do to prove it; that exemption is carved by ADDRESS and not by role,
 * so a student registered WITH a real email is held to the same rule as an owner.
 *
 * The SENTENCE changed, because it has to describe an action the user can actually take. It
 * used to say "enter the 6-digit code"; there is no code and no field to type it into any more,
 * and an instruction that names a control which does not exist is worse than no instruction.
 */
export function requireVerifiedEmail(caller: Caller): void {
  if (!isReachableAddress(caller.email)) return;
  if (caller.emailVerifiedAt) return;
  throw new HttpError(
    403,
    "Verify your email address before creating accounts. Open Nivora, tap the banner at the top " +
      "of your home screen, and open the confirmation link we email to " +
      (caller.email ?? "your address") + ". Come back to Nivora afterwards and it will update.",
  );
}

export interface ConfirmResult {
  verified: boolean;
  verifiedAt: string | null;
}

/**
 * Has this caller opened the link? If so, record it.
 *
 * Called on every `status` request from a caller who is not already verified — which the app
 * issues when the verification screen opens and each time the app returns to the foreground,
 * because the user leaves to a browser and comes back. It is deliberately cheap: one RPC, and
 * only for accounts that still owe a proof.
 *
 * ── FAILURE IS SILENT, AND THAT IS THE RIGHT DIRECTION ──
 *
 * A failed probe returns "not verified yet" rather than throwing. This instance drops requests
 * on its own schedule; a resume-time check that turned a dropped RPC into an error banner would
 * put a red message on the home screen of someone who has done nothing wrong and whose next
 * resume will very likely succeed. The cost of being wrong this way is one more tap; the cost
 * of the other way is a screen that accuses the user of a fault that is ours.
 *
 * Nothing here decides anything the user could not decide by lying to us: the RPC reads GoTrue's
 * tables, and app.users_update_guard refuses the write below from every role but service_role.
 */
export async function confirmEmailFromLink(caller: Caller): Promise<ConfirmResult> {
  const email = (caller.email ?? "").trim().toLowerCase();

  if (caller.emailVerifiedAt) {
    return { verified: true, verifiedAt: caller.emailVerifiedAt };
  }
  if (!isReachableAddress(email)) {
    // Nothing to prove and nothing that could ever prove it.
    return { verified: false, verifiedAt: null };
  }

  const db = serviceClient();

  const { data, error } = await db.rpc("email_link_proof", { p_user: caller.id });
  if (error) {
    console.error("[nivora] email_link_proof failed: " + error.message);
    return { verified: false, verifiedAt: null };
  }
  const provenAt = typeof data === "string" && data.length > 0 ? data : null;
  if (!provenAt) return { verified: false, verifiedAt: null };

  // Guarded on `email` so an address change that landed between the click and this write cannot
  // have a proof earned for the old address stamped onto the new one. The database enforces the
  // same thing from the other side — users_update_guard nulls the column and stamps
  // email_verification_reset_at on any change, and email_link_proof() will not look past that
  // stamp — so this is the second of two locks, not the only one.
  const verifiedAt = new Date().toISOString();
  const { error: writeError } = await db
    .from("users")
    .update({ email_verified_at: verifiedAt })
    .eq("id", caller.id)
    .eq("email", email);

  if (writeError) {
    console.error("[nivora] link was opened but the proof could not be recorded: " + writeError.message);
    return { verified: false, verifiedAt: null };
  }

  await audit("auth.email.verified", caller, {
    targetType: "user",
    targetId: caller.id,
    meta: { surface: "edge_function", method: "link", provenAt },
  });

  return { verified: true, verifiedAt };
}
