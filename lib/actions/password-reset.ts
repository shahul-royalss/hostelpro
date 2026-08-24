"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { resolveLoginEmail, sleep, STUDENT_LOGIN_DOMAIN } from "@/lib/utils";
import { ROLE_HOME, type UserRole } from "@/lib/roles";
import { changePasswordSchema, loginSchema } from "@/lib/validators/auth";
import { fail, ok, type ActionResult } from "@/lib/types";
import { getSessionUser, errorMessage } from "@/lib/permissions";
import { clearMustChangePassword } from "@/lib/auth/accounts";
import { getClientIp, rateLimit } from "@/lib/rate-limit";
import { audit, auditSystem, hashIdentifier } from "@/lib/audit";
import { clearResetTicket, resetTicketHolder } from "@/app/reset-password/ticket";

/**
 * Forgot-password (docs/password-reset.md). Two actions, and the interesting one is the first.
 *
 * THE SHAPE OF THE PROBLEM. Half this app's users have no email address. A student signs in
 * with a phone number that lib/utils maps to a synthetic address at a domain that does not
 * exist and can never receive mail - 9000000001@student.hostelpro.local. "We've sent you a
 * link" is a lie for them, and a lie that leaves them locked out while they wait for a mail
 * that is physically incapable of arriving. So the flow branches, and it branches on the SHAPE
 * OF WHAT WAS TYPED, never on what the database contains - see the enumeration note below.
 */

/* ───────────────────────── Limits ───────────────────────── */

/**
 * Deliberately local rather than added to LIMITS in lib/rate-limit.ts, which is outside this
 * change's paths. Move them there when convenient; the numbers, not the location, are the
 * decision.
 *
 * Sized against the delivery channel, not against a generic "feels about right": Supabase's
 * built-in SMTP allows a couple of messages an HOUR on the free plan (docs/password-reset.md
 * §4). A per-identifier budget larger than that would only queue mail that gets dropped, and
 * would hand an attacker a free mail-bomb aimed at a real person's inbox.
 */
const RESET_LIMITS = {
  /** Per email/phone typed into the form. */
  perIdentifier: { max: 3, windowSeconds: 3600 },
  /** Per source IP - catches a sweep across many identifiers that the per-identifier limit cannot see. */
  perIp: { max: 12, windowSeconds: 3600 },
  /** Attempts to SET the new password once a link has been opened. */
  perCompletion: { max: 5, windowSeconds: 900 },
} as const;

/**
 * Every branch of the request action returns on this clock, and on nothing else.
 *
 * CONSTANT TEXT IS NOT A CONSTANT RESPONSE, and this was measured rather than assumed. With the
 * send awaited, a real account came back in 2121 ms and an unknown one in 1170 ms against the
 * live project - because GoTrue actually hands the message to SMTP in the first case and
 * short-circuits in the second. Identical wording, and a 950 ms tell underneath it: exactly the
 * oracle the wording exists to deny, just moved into the stopwatch.
 *
 * So the send is ISSUED and then raced against this floor instead of being waited on (see
 * requestPasswordReset). The response leaves at the floor whether the mail took 20 ms or two
 * seconds, and whether there was a mailbox at all.
 */
const RESPONSE_FLOOR_MS = 900;

async function settle<T>(startedAt: number, value: T): Promise<T> {
  const elapsed = Date.now() - startedAt;
  if (elapsed < RESPONSE_FLOOR_MS) await sleep(RESPONSE_FLOOR_MS - elapsed);
  return value;
}

/* ───────────────────────── Request a reset ───────────────────────── */

export type ResetRequestOutcome =
  /** A real mailbox was addressed. Says nothing about whether an account exists behind it. */
  | { channel: "email"; sentTo: string }
  /** A student login. No mail was sent and none was claimed. */
  | { channel: "student" };

/** What the (deliberately un-awaited) send reports, if it reports in time. Audit-only. */
type SendOutcome = { status: number; message?: string };

export async function requestPasswordReset(
  _prev: ActionResult<ResetRequestOutcome> | null,
  formData: FormData,
): Promise<ActionResult<ResetRequestOutcome>> {
  const startedAt = Date.now();

  // The same field rule as the sign-in form, imported rather than restated so the two cannot drift.
  const parsed = loginSchema.shape.identifier.safeParse(formData.get("identifier"));
  if (!parsed.success) {
    return settle(startedAt, fail<ResetRequestOutcome>("Enter the email or phone number you sign in with."));
  }

  const identifier = parsed.data;
  const email = resolveLoginEmail(identifier);
  const idHash = hashIdentifier(email);
  const ip = await getClientIp();

  // Fail-closed, matching signIn(): when the limiter itself is unavailable this refuses rather
  // than waving everything through. An auth flow that degrades to "unlimited" under load is the
  // one you would actually want to knock over first.
  const [byIp, byId] = await Promise.all([
    rateLimit(`pwreset:ip:${ip}`, RESET_LIMITS.perIp.max, RESET_LIMITS.perIp.windowSeconds, true),
    rateLimit(`pwreset:id:${idHash}`, RESET_LIMITS.perIdentifier.max, RESET_LIMITS.perIdentifier.windowSeconds, true),
  ]);
  if (!byIp.allowed || !byId.allowed) {
    const wait = Math.max(byIp.retryAfterSeconds, byId.retryAfterSeconds);
    await auditSystem("auth.password.reset_rate_limited", { targetType: "identifier", targetId: idHash });
    // This message differs from the success message - but it varies with REQUEST VOLUME, never
    // with whether the account exists: the limiter is keyed on a hash computed identically for a
    // real address and a made-up one, and it is checked before anything looks the account up.
    const minutes = Math.max(1, Math.ceil(wait / 60));
    return settle(
      startedAt,
      fail<ResetRequestOutcome>(
        `Too many reset requests. Please wait ${minutes} minute${minutes === 1 ? "" : "s"} and try again.`,
      ),
    );
  }

  /**
   * THE BRANCH, and why it is safe to make it here.
   *
   * resolveLoginEmail() is a pure function of the typed string: a phone number becomes
   * <digits>@student.hostelpro.local, anything containing an @ is passed through. So this test
   * asks "did you type a phone number?" - something the person at the keyboard already knows -
   * and reads no table. A student who types their phone gets a truthful answer immediately; an
   * attacker learns only what they themselves typed.
   *
   * What is deliberately NOT done here: looking the student up to print their warden's name and
   * number. That lookup is the enumeration oracle this whole file exists to avoid - it would
   * turn the form into "is this phone number a resident, and of which hostel", about a
   * population of young people whose address is exactly the thing worth protecting. The copy
   * therefore names the ROLE to contact, which is true for every hostel, and no individual.
   */
  if (email.endsWith(`@${STUDENT_LOGIN_DOMAIN}`)) {
    await auditSystem("auth.password.reset_requested", {
      targetType: "identifier",
      targetId: idHash,
      meta: { channel: "student", mailed: false },
    });
    return settle(startedAt, ok<ResetRequestOutcome>({ channel: "student" }));
  }

  const supabase = await createClient();

  /**
   * Issued, not awaited. See RESPONSE_FLOOR_MS: how long GoTrue takes here is a direct function
   * of whether the mailbox exists, so nothing the caller can observe may depend on it.
   *
   * The request is on the wire before this function returns, which is what actually matters -
   * the mail is GoTrue's job from that point on. What can be lost if the platform freezes the
   * instance at once is the delivery status below, and that is telemetry, not the feature.
   */
  const send = supabase.auth
    .resetPasswordForEmail(email, {
      // Built from configuration, never from the Host header. A reset link is the one email in
      // this product that IS a credential; taking its origin from a request header would let
      // anyone who can reach the app with a forged Host mint links pointing at their own server
      // and collect the codes.
      redirectTo: `${appOrigin()}/reset-password/callback`,
    })
    .then(({ error }): SendOutcome => ({ status: error?.status ?? 200, message: error?.message }))
    .catch((): SendOutcome => ({ status: 0, message: "threw" }));

  // One promise, awaited twice on purpose: the race lets a fast send contribute its status, and
  // the second await guarantees a slow one still cannot stretch the response past the floor.
  const floor = settle<SendOutcome | "pending">(startedAt, "pending");
  const outcome = await Promise.race([send, floor]);
  await floor;

  await auditSystem("auth.password.reset_requested", {
    targetType: "identifier",
    targetId: idHash,
    // A status code and nothing else. A message could carry the address; a number cannot, and it
    // is still enough to see "every request is 429" when the SMTP quota runs out. "pending"
    // means the send outlived the floor, which is the normal case for a real delivery.
    meta: { channel: "email", status: outcome === "pending" ? "pending" : outcome.status },
  });

  if (process.env.NODE_ENV !== "production" && outcome !== "pending" && outcome.status !== 200) {
    console.error("[requestPasswordReset] supabase:", outcome.status, outcome.message);
  }

  /**
   * The ONE result the email branch ever returns, whatever happened behind it.
   *
   * NO USER ENUMERATION (checklist §3). The account may exist, may not exist, may be
   * deactivated; Supabase's SMTP may have accepted the message or answered 429. All of it ends
   * here, with the same text, the same `ok: true`, and the same elapsed time. The masked
   * address in the copy is echoed back from what the visitor TYPED, never read from the
   * database, so it discloses nothing they did not already know.
   */
  return settle(startedAt, ok<ResetRequestOutcome>({ channel: "email", sentTo: maskEmail(identifier) }));
}

/* ───────────────────────── Complete a reset ───────────────────────── */

const EXPIRED_LINK =
  "This reset link has expired or has already been used. Request a new one and open it on this device.";

/**
 * Set the new password using the recovery session created by /reset-password/callback.
 *
 * Authorised by TWO things, both required: a live session (who) and the signed recovery ticket
 * (how that session was obtained). See app/reset-password/ticket.ts for why the second one is
 * not optional.
 */
export async function completePasswordReset(_prev: ActionResult | null, formData: FormData): Promise<ActionResult> {
  const holder = await resetTicketHolder();
  if (!holder) return fail(EXPIRED_LINK);

  const user = await getSessionUser();
  if (!user || user.id !== holder) return fail(EXPIRED_LINK);

  const rl = await rateLimit(
    `pwreset:complete:${user.id}`,
    RESET_LIMITS.perCompletion.max,
    RESET_LIMITS.perCompletion.windowSeconds,
    true,
  );
  if (!rl.allowed) return fail("Too many attempts. Please wait a few minutes and try again.");

  /**
   * THE SAME POLICY AS THE REST OF THE APP, not a second copy of it.
   *
   * changePasswordSchema (lib/validators/auth.ts) is the app's password rule - length from
   * PASSWORD_MIN_LENGTH, at least one letter, at least one number, confirmation must match. Its
   * `currentPassword` field is optional and only constrains a value when one is present, which
   * is exactly the forced-change case this resembles, so it is reused verbatim rather than
   * restated. Supabase's own leaked-password check runs on top of it, in updateUser below.
   */
  const parsed = changePasswordSchema.safeParse({
    password: formData.get("password"),
    confirm: formData.get("confirm"),
  });
  if (!parsed.success) {
    return fail("Please fix the errors below.", parsed.error.flatten().fieldErrors);
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    return fail(
      /same password|different from the old/i.test(error.message)
        ? "Choose a password different from your previous one."
        : /weak|pwned|leaked|compromised/i.test(error.message)
          ? "That password is too weak or has appeared in a data breach - choose another."
          : errorMessage(error),
    );
  }

  // A forgotten password is very often a temporary one that was never changed, so the account
  // may still carry the forced-change flag. Clearing it here stops the user being bounced
  // straight out of the reset into /change-password to set the password they just set.
  await supabase.from("users").update({ must_change_password: false }).eq("id", user.id);
  try {
    await clearMustChangePassword(user.id);
  } catch {
    // Service role unavailable - the DB flag is cleared and middleware falls back to it.
  }

  await audit("auth.password.reset_completed", { targetType: "user", targetId: user.id, meta: { role: user.role } });

  /**
   * Revoke every OTHER session, exactly as changePassword() does.
   *
   * This branch needs it more than that one does. A reset is what someone does when they have
   * lost control of the password, which is precisely the case where a session an attacker is
   * already holding is most likely to exist. Rotating the credential without killing those
   * sessions would leave the attacker signed in and the owner reassured.
   */
  try {
    await supabase.auth.signOut({ scope: "others" });
  } catch {
    /* best effort - the password is already rotated */
  }

  await clearResetTicket();
  redirect(ROLE_HOME[user.role as UserRole]);
}

/* ───────────────────────── Helpers ───────────────────────── */

/**
 * The origin reset links point at. Configuration only, in priority order, and localhost is
 * refused in production so that a stale NEXT_PUBLIC_APP_URL cannot silently send every user a
 * link to their own machine.
 */
function appOrigin(): string {
  const candidates = [
    process.env.NEXT_PUBLIC_APP_URL,
    process.env.VERCEL_PROJECT_PRODUCTION_URL && `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`,
    process.env.VERCEL_URL && `https://${process.env.VERCEL_URL}`,
  ];
  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      const url = new URL(candidate);
      if (url.protocol !== "https:" && url.protocol !== "http:") continue;
      const isLocal = url.hostname === "localhost" || url.hostname === "127.0.0.1";
      if (isLocal && process.env.NODE_ENV === "production") continue;
      return url.origin;
    } catch {
      /* not a URL - try the next candidate */
    }
  }
  return "http://localhost:3000";
}

/** Echoes back what the visitor typed, partially hidden. Never reads the database. */
function maskEmail(identifier: string): string {
  const at = identifier.lastIndexOf("@");
  if (at <= 0) return identifier;
  const local = identifier.slice(0, at);
  const domain = identifier.slice(at + 1);
  const head = local.slice(0, Math.min(2, local.length));
  return `${head}${"•".repeat(Math.max(3, local.length - head.length))}@${domain}`;
}
