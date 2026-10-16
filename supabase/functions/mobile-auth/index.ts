/**
 * POST /functions/v1/mobile-auth
 *
 * The phone's sign-in and second-factor endpoint. Three actions on one function:
 *
 *   { "action": "signin", "identifier": "<resolved login address>", "password": "..." }
 *   { "action": "mfa",    "factorId": "<uuid>", "code": "123456" }
 *   { "action": "google", "idToken": "<Google ID token>", "nonce": "<raw nonce>" }
 *
 * The third is "Continue with Google" (2026-10-17). See the GOOGLE section below; it needs the
 * GOOGLE_WEB_CLIENT_ID secret and db/migrations/2026-10-17-google-sign-in.sql on the database.
 *
 * ═══ WHY THIS EXISTS ═══
 *
 * The Flutter client used to call GoTrue directly — `supabase.auth.signInWithPassword()` —
 * which is a straight POST to /auth/v1/token?grant_type=password. An audit measured that path
 * twice, independently: TWELVE consecutive wrong-password POSTs for a real account all
 * returned HTTP 400 invalid_credentials. No 429. No lockout. Observed back-off DECREASING
 * between attempts (1.37s → 0.53s). And because nothing on that path writes to
 * public.audit_log, zero `auth.login.failed` rows existed, so
 * app.detect_suspicious_activity() — which raises an alert at five failures in fifteen
 * minutes — never saw an attack that was in progress.
 *
 * The web app has been throttled since day one (lib/actions/auth.ts:44-53, lib/actions/mfa.ts)
 * because a browser talks to a server action, and the server action holds the limiter. The
 * phone had no equivalent server between it and GoTrue. This is that server.
 *
 * The same gap applied to TOTP verification, where the search space is 10^6 on a 30-second
 * rotation — unthrottled, that is minutes of work.
 *
 * ═══ WHAT IT ACTUALLY CLOSES, AND WHAT IT DOES NOT ═══
 *
 * CLOSED: the app's own path. Every sign-in and every code check the Apnivaas app performs now
 * spends a durable Postgres counter first and lands in the audit trail either way.
 *
 * NOT CLOSED BY THIS FILE: /auth/v1/token is still a public endpoint, and the anon key that
 * reaches it ships inside the APK where anyone with `unzip` can read it. An Edge Function
 * cannot make GoTrue's own endpoint stop answering. That half is closed by the two GoTrue
 * auth hooks in db/migrations/2026-08-31-auth-bruteforce.sql, which run INSIDE the token
 * endpoint on every attempt including the direct ones — they are written and granted, and
 * they do nothing at all until someone enables them in the dashboard. Until that toggle is
 * flipped, this function protects the app and the direct endpoint remains as it was measured.
 * Saying otherwise would be the same mistake as the client-side delay this work rejected.
 *
 * ═══ NO CLIENT-SIDE ANYTHING ═══
 *
 * Nothing here trusts the caller. The rate-limit verdict, the credential check, the audit
 * write and the 429 are all decided server-side; the phone is told the outcome and renders it.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy mobile-auth        (verify_jwt stays ON — see below)
 *
 * verify_jwt = true. Sign-in is called with no session, so the Authorization header carries
 * the ANON key, which is a JWT the gateway accepts. That is the intended use of the anon key
 * and it gates nothing on its own; the real gate is the limiter below. The MFA action is
 * called with the caller's own aal1 token and is verified properly by requireSession().
 */
import { createRemoteJWKSet, errors as joseErrors, jwtVerify, type JWTPayload } from "npm:jose@5.9.6";
import { audit, auditSystem, hashIdentifier } from "../_shared/audit.ts";
import { clientIp, clientUserAgent, requireSession } from "../_shared/caller.ts";
import { HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { consumeRateLimit, LIMITS, reportOnce, throttled } from "../_shared/ratelimit.ts";
import { anonKey, projectUrl, serviceClient } from "../_shared/supabase.ts";

/**
 * ONE sentence for "no such account" and "wrong password" alike.
 *
 * This app's population is young residents whose PHONE NUMBER is their login id. A message
 * that distinguished the two would let anyone confirm which numbers live in which PG.
 */
const GENERIC_LOGIN_ERROR = "Incorrect email/phone or password.";
const GENERIC_MFA_ERROR = "That code is not right. Codes change every 30 seconds — try the current one.";

/** A body this small never legitimately approaches even 8 KB. */
const MAX_BODY_BYTES = 8 * 1024;

/** GoTrue is one hop away; if it has not answered in ten seconds it is not going to. */
const GOTRUE_TIMEOUT_MS = 10_000;

interface GoTrueSession {
  access_token: string;
  refresh_token: string;
  expires_at?: number;
}

interface GoTrueCall {
  status: number;
  body: Record<string, unknown>;
}

/**
 * A raw GoTrue call. The supabase-js client is deliberately NOT used for these requests:
 * signing in through it would install the resulting session on a client inside a warm isolate,
 * and an isolate serves many people one after another. Tokens minted here are values that go
 * straight into a response body and are never held anywhere.
 */
async function gotrue(path: string, init: { body: unknown; bearer?: string }): Promise<GoTrueCall> {
  const res = await fetch(`${projectUrl()}/auth/v1/${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anonKey(),
      Authorization: `Bearer ${init.bearer ?? anonKey()}`,
    },
    body: JSON.stringify(init.body),
    signal: AbortSignal.timeout(GOTRUE_TIMEOUT_MS),
  });
  let body: Record<string, unknown> = {};
  try {
    const parsed = await res.json();
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) body = parsed as Record<string, unknown>;
  } catch {
    /* an empty or non-JSON body is handled by the status check at every call site */
  }
  return { status: res.status, body };
}

function sessionFrom(body: Record<string, unknown>): GoTrueSession | null {
  const access = body["access_token"];
  const refresh = body["refresh_token"];
  if (typeof access !== "string" || !access || typeof refresh !== "string" || !refresh) return null;
  return {
    access_token: access,
    refresh_token: refresh,
    expires_at: typeof body["expires_at"] === "number" ? body["expires_at"] : undefined,
  };
}

/**
 * Throw away a session this function minted but is not going to hand over.
 *
 * The password was correct, so GoTrue issued real tokens; if the profile row then says the
 * account is inactive, those tokens must not simply be dropped on the floor still valid.
 */
async function revoke(accessToken: string): Promise<void> {
  try {
    await gotrue("logout?scope=global", { body: {}, bearer: accessToken });
  } catch (e) {
    console.error(
      "[apnivaas] could not revoke a session we declined to return:",
      e instanceof Error ? e.message : String(e),
    );
  }
}

/** What the phone is handed on success. Deliberately just the session. */
function grant(session: GoTrueSession): Response {
  return ok({
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresAt: session.expires_at ?? null,
  });
}

/**
 * The same 429 for both actions, so one decoder on the client covers both.
 *
 * `retryAfterSeconds` is in the body AND in a Retry-After header. The body is what the Dart
 * client reads to say "wait 3 minutes" in words; the header is what anything else in the
 * chain understands.
 */
function tooManyAttempts(waitSeconds: number): HttpError {
  const minutes = Math.ceil(waitSeconds / 60);
  return throttled(
    `Too many attempts. Please wait ${minutes} minute${minutes === 1 ? "" : "s"} and try again.`,
    waitSeconds,
  );
}

/** "We could not ask the question", never "the answer was no". */
function unavailable(message: string): HttpError {
  return new HttpError(503, message, { extra: { retryAfterSeconds: 60 }, headers: { "Retry-After": "60" } });
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// SIGN IN
// ═══════════════════════════════════════════════════════════════════════════════════════════

const SIGNIN_UNAVAILABLE =
  "Sign-in is temporarily unavailable. This is not a problem with your password. Please try again in a minute.";

/**
 * The identifier arrives ALREADY RESOLVED — the Dart client runs resolveLoginEmail() and sends
 * the address, exactly as it did when it called GoTrue itself.
 *
 * That is on purpose, and it is the decision here most likely to be questioned. Porting the
 * phone→email mapping into this file would create a third copy of a rule that already exists
 * twice (Dart resolveLoginEmail, TS resolveLoginEmail) and already differs between those two
 * for input that is neither a phone nor an email. A third copy that drifted would not fail
 * loudly: it would map a real resident onto an address that does not exist and answer
 * "incorrect password" forever. Taking the resolved address verbatim means this function
 * CANNOT change who is able to sign in — the rule it depends on is the same object that was
 * already deciding.
 *
 * It also makes the limiter key stable: "+91 98765 43210" and "9876543210" have already
 * collapsed to one address before they arrive, so they cannot buy two budgets.
 */
async function signIn(req: Request, body: Record<string, unknown>): Promise<Response> {
  const ip = clientIp(req);
  const userAgent = clientUserAgent(req);

  const rawIdentifier = body["identifier"];
  const rawPassword = body["password"];
  // No fieldErrors on this path. WHICH of the two fields was malformed is information, and a
  // sign-in form gets one answer: the generic one.
  if (typeof rawIdentifier !== "string" || typeof rawPassword !== "string") {
    throw new HttpError(400, GENERIC_LOGIN_ERROR);
  }
  const identifier = rawIdentifier.trim().toLowerCase();
  if (!identifier || identifier.length > 200 || !rawPassword || rawPassword.length > 1024) {
    throw new HttpError(400, GENERIC_LOGIN_ERROR);
  }

  const idHash = await hashIdentifier(identifier);

  // BY IP **AND** BY IDENTIFIER — both, and both always spent.
  //
  // By identifier alone, a botnet spreads one account's guesses across a thousand addresses.
  // By IP alone, one host sprays a thousand accounts with the season's favourite password and
  // never trips a per-account counter. Neither key covers the other's attack.
  //
  // Both are consumed before either verdict is read, so a request that trips the IP limit
  // still counts against the identifier it was aimed at, and no timing difference reveals
  // which of the two tripped.
  //
  // ── NO SHARED "unknown" BUCKET ────────────────────────────────────────────────────────────
  //
  // `ip ?? "unknown"` used to funnel every request with no resolvable address into ONE counter
  // called login:ip:unknown. That is not a rate limit, it is a global kill switch: the moment
  // the gateway stops forwarding the header — or forwards one this code cannot parse — the
  // twenty-first sign-in ANYWHERE in the product is refused, and the message blames the user
  // for trying too often.
  //
  // With no address there is nothing to key an IP budget on, so no IP budget is spent. The
  // per-identifier budget below is untouched and is the one that actually protects an account.
  const ipKey = ip ? `login:ip:${ip}` : null;
  const [ipWait, idWait] = await Promise.all([
    ipKey
      ? consumeRateLimit(ipKey, LIMITS.loginPerIp, { unavailableMessage: SIGNIN_UNAVAILABLE })
      : Promise.resolve(0),
    consumeRateLimit(`login:id:${idHash}`, LIMITS.loginPerIdentifier, { unavailableMessage: SIGNIN_UNAVAILABLE }),
  ]);
  const wait = Math.max(ipWait, idWait);
  if (wait > 0) {
    // A throttle is its own event in the trail: detect_suspicious_activity() raises
    // `auth.rate_limited` the moment it sees this action. Written at most once per window per
    // identifier, so an attacker who keeps hammering after the 429 cannot turn the audit log
    // into a second denial of service — see reportOnce().
    if (await reportOnce(`login:${idHash}`, LIMITS.loginPerIdentifier.windowSeconds)) {
      await auditSystem("auth.login.rate_limited", { targetType: "identifier", targetId: idHash, ip, userAgent });
    }
    throw tooManyAttempts(wait);
  }

  const call = await gotrue("token?grant_type=password", { body: { email: identifier, password: rawPassword } });
  const session = sessionFrom(call.body);
  if (call.status !== 200 || !session) {
    const errorCode = String(call.body["error_code"] ?? call.body["error"] ?? "");
    const description = String(call.body["msg"] ?? call.body["error_description"] ?? call.body["message"] ?? "");

    // A CAPTCHA rejection is not a credential verdict. Telling someone their password is wrong
    // while the project is refusing EVERY password grant would send them off to reset a
    // password that was never the problem. This project has had captcha protection on and
    // failing exactly that way; if it is ever switched back on, this line keeps the message
    // honest instead of blaming the user.
    if (/captcha/i.test(errorCode) || /captcha/i.test(description)) {
      console.error("[apnivaas] GoTrue refused the password grant for CAPTCHA — sign-in is down for every client.");
      throw unavailable(SIGNIN_UNAVAILABLE);
    }

    // GoTrue's own limiter underneath ours, or — once the operator enables it — the
    // password_verification_attempt hook refusing inside the token endpoint. Both mean "wait",
    // never "wrong password", and the hook's rejection text is matched here on purpose so the
    // app renders a throttle rather than blaming the user's password for it.
    if (call.status === 429 || /too many attempts/i.test(description)) {
      if (await reportOnce(`login:${idHash}`, LIMITS.loginPerIdentifier.windowSeconds)) {
        await auditSystem("auth.login.rate_limited", { targetType: "identifier", targetId: idHash, ip, userAgent });
      }
      throw tooManyAttempts(60);
    }

    if (call.status >= 500) {
      console.error(`[apnivaas] GoTrue ${call.status} on password grant: ${description.slice(0, 200)}`);
      throw unavailable(SIGNIN_UNAVAILABLE);
    }

    // THE ROW THAT WAS MISSING. With actor_user_id NULL, app.detect_suspicious_activity()
    // counts these BY IP and raises `auth.bruteforce` at five in fifteen minutes. No user
    // lookup happens here on purpose — resolving the identifier to an id would turn the audit
    // trail into a record of which accounts exist.
    await auditSystem("auth.login.failed", {
      targetType: "identifier",
      targetId: idHash,
      ip,
      userAgent,
      meta: { status: call.status, surface: "mobile" },
    });
    throw new HttpError(400, GENERIC_LOGIN_ERROR);
  }

  // The password was right. public.users is the authority on whether the account may be used —
  // read with the service client, so RLS cannot hide the row that says "no".
  const userId = String((call.body["user"] as Record<string, unknown> | undefined)?.["id"] ?? "");
  const { data, error } = await serviceClient()
    .from("users")
    .select("id, role, hostel_id, status, deleted_at")
    .eq("id", userId)
    .maybeSingle();

  if (error) {
    console.error("[apnivaas] profile lookup failed after a valid password:", error.message);
    await revoke(session.access_token);
    throw unavailable(SIGNIN_UNAVAILABLE);
  }

  const profile = data as
    | { id: string; role: string; hostel_id: string | null; status: string; deleted_at: string | null }
    | null;
  if (!profile || profile.deleted_at || profile.status !== "active") {
    await revoke(session.access_token);
    await auditSystem("auth.login.failed", {
      targetType: "identifier",
      targetId: idHash,
      ip,
      userAgent,
      meta: { reason: profile ? "inactive" : "no-profile", surface: "mobile" },
    });
    // The password was correct, so naming the real reason leaks nothing to the person who just
    // typed it — and it is the only message that tells them what to do next.
    throw new HttpError(
      403,
      profile
        ? "This account has been deactivated. Contact your hostel owner."
        : "Your account isn't set up yet. Contact your administrator.",
    );
  }

  await auditSystem("auth.login.success", {
    targetType: "user",
    targetId: profile.id,
    hostelId: profile.hostel_id,
    ip,
    userAgent,
    meta: { role: profile.role, surface: "mobile" },
  });

  return grant(session);
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// SECOND FACTOR
// ═══════════════════════════════════════════════════════════════════════════════════════════

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MFA_UNAVAILABLE = "Verification is temporarily unavailable. Please try again in a minute.";

/**
 * A six-digit TOTP is a 10^6 space on a thirty-second rotation. Unthrottled, a script walks a
 * meaningful fraction of it inside one window. LIMITS.mfaVerifyPerUser is 6 per ten minutes —
 * the same number the web app uses — which puts a sweep out of reach of anything patient.
 *
 * Unlike sign-in, the caller here is KNOWN: they already passed the first factor, so the audit
 * row carries a real actor and detect_suspicious_activity() counts `auth.mfa.failed` per
 * account (three in ten minutes → alert).
 */
async function verifyMfa(req: Request, body: Record<string, unknown>): Promise<Response> {
  // requireSession, not requireCaller: the second factor is owed BEFORE the forced first-login
  // password change, so most people legitimately reaching this line still hold
  // must_change_password = true. See the note on requireSession().
  const { caller } = await requireSession(req);

  const factorId = String(body["factorId"] ?? "");
  const code = String(body["code"] ?? "").trim();
  // Format is checked before any budget is spent, exactly as lib/actions/mfa.ts does. A
  // malformed code cannot authenticate, so charging for it would only help an attacker spend
  // a real user's allowance on their behalf.
  if (!UUID_RE.test(factorId) || !/^\d{6}$/.test(code)) {
    throw new HttpError(400, "Enter the 6-digit code from your authenticator app.");
  }

  // Same shape as the sign-in path above, and for the same two reasons: no shared "unknown"
  // bucket, and the per-USER budget is the one that protects a factor. Six codes per ten
  // minutes per user is 10^6 / 6 attempts to guess a TOTP — the IP key here only stops one host
  // farming many accounts, so it can afford to be loose enough for a hostel behind one router.
  const mfaIpKey = caller.ip ? `mfa:ip:${caller.ip}` : null;
  const [ipWait, userWait] = await Promise.all([
    mfaIpKey
      ? consumeRateLimit(mfaIpKey, LIMITS.mfaVerifyPerIp, { unavailableMessage: MFA_UNAVAILABLE })
      : Promise.resolve(0),
    consumeRateLimit(`mfa:user:${caller.id}`, LIMITS.mfaVerifyPerUser, { unavailableMessage: MFA_UNAVAILABLE }),
  ]);
  const wait = Math.max(ipWait, userWait);
  if (wait > 0) {
    if (await reportOnce(`mfa:${caller.id}`, LIMITS.mfaVerifyPerUser.windowSeconds)) {
      await audit("auth.mfa.rate_limited", caller, {
        targetType: "user",
        targetId: caller.id,
        meta: { surface: "mobile" },
      });
    }
    throw tooManyAttempts(wait);
  }

  // GoTrue binds a factor to the bearer token's user, so a caller cannot challenge someone
  // else's factor by quoting its id.
  const challenge = await gotrue(`factors/${factorId}/challenge`, { body: {}, bearer: caller.jwt });
  const challengeId = challenge.body["id"];
  if (challenge.status !== 200 || typeof challengeId !== "string") {
    if (challenge.status >= 500) throw unavailable(MFA_UNAVAILABLE);
    throw new HttpError(400, GENERIC_MFA_ERROR);
  }

  const verified = await gotrue(`factors/${factorId}/verify`, {
    body: { challenge_id: challengeId, code },
    bearer: caller.jwt,
  });
  const session = sessionFrom(verified.body);
  if (verified.status !== 200 || !session) {
    if (verified.status >= 500) throw unavailable(MFA_UNAVAILABLE);
    if (verified.status === 429) throw tooManyAttempts(60);
    await audit("auth.mfa.failed", caller, {
      targetType: "user",
      targetId: caller.id,
      meta: { phase: "login", surface: "mobile" },
    });
    throw new HttpError(400, GENERIC_MFA_ERROR);
  }

  await audit("auth.mfa.verified", caller, {
    targetType: "user",
    targetId: caller.id,
    meta: { surface: "mobile" },
  });
  return grant(session);
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// GOOGLE
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// The phone gets an ID token from Android's own Google account sheet (Credential Manager — no
// browser) and sends it here with the raw nonce it hashed into the request. This function:
//
//   1. spends the IP budget, before the token is even parsed;
//   2. verifies the token itself — Google's signature, issuer, audience (our Web client ID),
//      expiry, email_verified, and that the token's nonce is sha256(raw nonce);
//   3. spends the per-address budget, the SAME bucket a password sign-in for that address uses;
//   4. looks the account up (public.login_account_for_email) and refuses — with a sentence that
//      says what to do — no account, staff and super admin, deactivated, not set up;
//   5. only then hands the same token to GoTrue's id_token grant, which links the Google
//      identity to the account by address and mints the session.
//
// Why verify here when GoTrue verifies too: step 4 must not run on an unverified claim. Answering
// "no account uses x@y" for a forged token would be an enumeration oracle; for a real one it is
// telling the owner of x@y about their own address. And this project has "Allow new users to sign
// up" ON, so a token for an unknown address must never reach GoTrue, which would create an account.
//
// Why the database still has its own guard: GoTrue's id_token grant and its browser redirect are
// public, so "staff never use Google" is enforced again by the trigger in
// db/migrations/2026-10-17-google-sign-in.sql, where the link is written. Step 4 is what gives
// the app a sentence instead of GoTrue's "Database error".
//
// New people (no account yet) are refused here on purpose: self sign-up is 1.3.0 work, and it
// will create the account through the server, never by turning public sign-up on.

const GOOGLE_UNAVAILABLE =
  "Google sign-in is temporarily unavailable. Please try again in a minute, or sign in with your password.";
const GOOGLE_NOT_ON =
  "Google sign-in isn't switched on yet. Sign in with your phone number or email and password.";
const GOOGLE_FAILED = "Google sign-in didn't go through. Please try again.";
const GOOGLE_STAFF =
  "Staff and administrator accounts sign in with the login they were given, not with Google.";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];
const STAFF_ROLES = new Set(["super_admin", "manager", "warden"]);

/**
 * Google's signing keys, fetched once per warm isolate. jose refetches when a token names a key
 * it has not seen (Google rotates them every few days). A fetch that fails is a 503, never a
 * rejection: the token was not judged.
 */
const googleKeys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"), {
  timeoutDuration: 5_000,
  cooldownDuration: 30_000,
});

/** The Web client ID(s) a token may be addressed to. Comma-separated, like the dashboard field. */
function googleClientIds(): string[] {
  return (Deno.env.get("GOOGLE_WEB_CLIENT_ID") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

interface LoginAccount {
  user_id: string;
  role: string | null;
  status: string | null;
  deleted_at: string | null;
}

async function signInWithGoogle(req: Request, body: Record<string, unknown>): Promise<Response> {
  const ip = clientIp(req);
  const userAgent = clientUserAgent(req);
  const failed = (reason: string, targetId: string | null, extra: Record<string, unknown> = {}) =>
    auditSystem("auth.login.failed", {
      targetType: "identifier",
      targetId,
      ip,
      userAgent,
      meta: { reason, method: "google", surface: "mobile", ...extra },
    });

  const clientIds = googleClientIds();
  if (clientIds.length === 0) throw unavailable(GOOGLE_NOT_ON);

  const idToken = body["idToken"];
  const nonce = body["nonce"];
  if (
    typeof idToken !== "string" || idToken.length < 20 || idToken.length > 4096 ||
    typeof nonce !== "string" || nonce.length < 16 || nonce.length > 256
  ) {
    throw new HttpError(400, GOOGLE_FAILED);
  }

  // 1. The IP budget, before any work. Same key and same numbers as the password path, and the
  //    same rule about a missing address: no shared "unknown" bucket.
  if (ip) {
    const ipWait = await consumeRateLimit(`login:ip:${ip}`, LIMITS.loginPerIp, {
      unavailableMessage: GOOGLE_UNAVAILABLE,
    });
    if (ipWait > 0) throw tooManyAttempts(ipWait);
  }

  // 2. The token.
  let claims: JWTPayload;
  try {
    ({ payload: claims } = await jwtVerify(idToken, googleKeys, {
      issuer: GOOGLE_ISSUERS,
      audience: clientIds,
      algorithms: ["RS256"],
      clockTolerance: 60,
    }));
  } catch (e) {
    // A JOSE error is a verdict on the token. Anything else (a network failure fetching the
    // keys, a timeout) means nobody judged it.
    if (!(e instanceof joseErrors.JOSEError) || e instanceof joseErrors.JWKSTimeout) {
      console.error("[apnivaas] could not check a Google token:", e instanceof Error ? e.message : String(e));
      throw unavailable(GOOGLE_UNAVAILABLE);
    }
    await failed("bad-token", null, { code: e.code });
    throw new HttpError(400, GOOGLE_FAILED);
  }

  const email = typeof claims["email"] === "string" ? claims["email"].trim().toLowerCase() : "";
  const emailVerified = claims["email_verified"] === true || claims["email_verified"] === "true";
  if (!email || !emailVerified) {
    await failed(email ? "unverified-email" : "no-email", email ? await hashIdentifier(email) : null);
    throw new HttpError(400, GOOGLE_FAILED);
  }
  if (claims["nonce"] !== await sha256Hex(nonce)) {
    await failed("nonce", await hashIdentifier(email));
    throw new HttpError(400, GOOGLE_FAILED);
  }

  // 3. The address's own budget — shared with password sign-ins for the same address, so
  //    switching method does not buy a second allowance.
  const idHash = await hashIdentifier(email);
  const idWait = await consumeRateLimit(`login:id:${idHash}`, LIMITS.loginPerIdentifier, {
    unavailableMessage: GOOGLE_UNAVAILABLE,
  });
  if (idWait > 0) {
    if (await reportOnce(`login:${idHash}`, LIMITS.loginPerIdentifier.windowSeconds)) {
      await auditSystem("auth.login.rate_limited", { targetType: "identifier", targetId: idHash, ip, userAgent });
    }
    throw tooManyAttempts(idWait);
  }

  // 4. The account. Google has proved the caller owns `email`, so every sentence below may name
  //    what is true about it.
  const { data: rows, error: lookupError } = await serviceClient().rpc("login_account_for_email", {
    p_email: email,
  });
  if (lookupError) {
    console.error("[apnivaas] account lookup failed for a verified Google token:", lookupError.message);
    throw unavailable(GOOGLE_UNAVAILABLE);
  }
  const accounts = (Array.isArray(rows) ? rows : []) as LoginAccount[];

  if (accounts.length === 0) {
    await failed("no-account", idHash);
    throw new HttpError(
      403,
      `No account uses ${email} yet. Sign in with your phone number or email and password, ` +
        "or ask your PG to add this address to your account.",
    );
  }
  if (accounts.length > 1) {
    console.error("[apnivaas] two auth users share a login address; GoTrue would refuse to link");
    await failed("duplicate-account", idHash);
    throw new HttpError(403, "This address is on more than one account. Contact your administrator.");
  }

  const account = accounts[0];
  if (!account.role) {
    await failed("no-profile", idHash);
    throw new HttpError(403, "Your account isn't set up yet. Contact your administrator.");
  }
  if (STAFF_ROLES.has(account.role)) {
    await failed("staff-refused", idHash, { role: account.role });
    throw new HttpError(403, GOOGLE_STAFF);
  }
  if (account.deleted_at || account.status !== "active") {
    await failed("inactive", idHash);
    throw new HttpError(403, "This account has been deactivated. Contact your hostel owner.");
  }

  // 5. GoTrue: the same token, the same raw nonce. It checks both again and links the identity.
  const call = await gotrue("token?grant_type=id_token", {
    body: { provider: "google", id_token: idToken, nonce },
  });
  const session = sessionFrom(call.body);
  if (call.status !== 200 || !session) {
    const errorCode = String(call.body["error_code"] ?? call.body["error"] ?? "");
    const description = String(call.body["msg"] ?? call.body["error_description"] ?? call.body["message"] ?? "");
    if (call.status === 429) throw tooManyAttempts(60);
    if (/provider_disabled/i.test(errorCode) || /not enabled|disabled/i.test(description)) {
      console.error(`[apnivaas] GoTrue has Google switched off: ${description.slice(0, 200)}`);
      throw unavailable(GOOGLE_NOT_ON);
    }
    if (call.status >= 500) {
      console.error(`[apnivaas] GoTrue ${call.status} on the Google grant: ${description.slice(0, 200)}`);
      throw unavailable(GOOGLE_UNAVAILABLE);
    }
    // We accepted the token and GoTrue did not: the dashboard's Client IDs and our secret
    // disagree, most likely. Logged for the operator; the user is told to try again.
    console.error(`[apnivaas] GoTrue refused a Google token mobile-auth accepted: ${call.status} ${errorCode} ${description.slice(0, 200)}`);
    await failed("gotrue-refused", idHash, { status: call.status });
    throw new HttpError(400, GOOGLE_FAILED);
  }

  const userId = String((call.body["user"] as Record<string, unknown> | undefined)?.["id"] ?? "");
  if (userId !== account.user_id) {
    // Cannot happen while addresses are unique; if it ever does, nobody gets a session for an
    // account this function did not check.
    console.error("[apnivaas] GoTrue signed a Google token into a different account than the lookup named");
    await revoke(session.access_token);
    throw unavailable(GOOGLE_UNAVAILABLE);
  }

  await auditSystem("auth.login.success", {
    targetType: "user",
    targetId: account.user_id,
    ip,
    userAgent,
    meta: { role: account.role, method: "google", surface: "mobile" },
  });
  return grant(session);
}

// ═══════════════════════════════════════════════════════════════════════════════════════════

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  try {
    const body = await readJsonBody(req, MAX_BODY_BYTES);
    switch (body["action"]) {
      case "signin":
        return await signIn(req, body);
      case "mfa":
        return await verifyMfa(req, body);
      case "google":
        return await signInWithGoogle(req, body);
      default:
        throw new HttpError(400, "Could not read the request.");
    }
  } catch (err) {
    return toResponse(err);
  }
});
