/**
 * Per-caller rate limiting, on the same durable counters the web app uses.
 *
 * public.rate_limit() is a fixed-window counter in Postgres (app.rate_limits). It is granted
 * to service_role only — an Edge Function isolate is short-lived and there may be many of
 * them, so an in-memory counter would reset on every cold start and limit nothing.
 *
 * Keys are hashed before they leave here, exactly as lib/rate-limit.ts does, so the limiter
 * table never becomes a list of user ids.
 *
 * FAIL CLOSED. The web app lets ordinary actions through when the limiter is unavailable;
 * these endpoints do not, because every one of them either mints a credential or checks one.
 * A limiter that opens under load is no limiter on the path that matters most.
 *
 * ── WHY A FIXED WINDOW AND NOT ESCALATING BACK-OFF ───────────────────────────────────────
 *
 * The brief allowed either "exponential backoff with a ceiling" or "a window that expires".
 * This is the second, and the choice is not arbitrary:
 *
 *   1. Escalation needs state the fixed-window primitive does not carry (how many windows in
 *      a row were exhausted), so it would mean a SECOND limiter with different semantics
 *      sitting beside this one. Two limiters is how a policy starts disagreeing with itself.
 *   2. A per-identifier lockout is attacker-triggerable: anyone who knows a resident's phone
 *      number can spend that account's budget and lock the real person out. Escalation makes
 *      that weapon stronger the longer it is held. A window that expires on its own bounds the
 *      damage at one window — 15 minutes, worst case — and needs no operator to undo.
 *   3. The grind an expiring window does not stop is covered by DETECTION rather than by a
 *      longer lockout: every failure below lands in public.audit_log, and
 *      app.detect_suspicious_activity() raises an `auth.bruteforce` alert at 5 failures in 15
 *      minutes, which the Super Admin and the hostel Owner actually see. Throttle the burst;
 *      alert on the grind.
 */
import { HttpError } from "./http.ts";
import { serviceClient } from "./supabase.ts";

export interface RateLimitSpec {
  readonly max: number;
  readonly windowSeconds: number;
}

/**
 * The SAME numbers as LIMITS in lib/rate-limit.ts, deliberately.
 *
 * A mobile client that throttled more loosely than the browser would simply become the door
 * an attacker walks through, and one policy expressed twice with different numbers is a policy
 * nobody can reason about. If these change, change lib/rate-limit.ts in the same commit.
 */
export const LIMITS = {
  accountCreatePerUser: { max: 20, windowSeconds: 3600 },
  /**
   * PER IP, and this number is about India rather than about security theory.
   *
   * It was 20 per 5 minutes. On carrier-grade NAT — which is how most of Jio and Airtel's
   * mobile subscribers reach the internet — thousands of unrelated people egress from one
   * address. A PG with forty residents all on the same network is one address too. At 20 the
   * honest failure arrives long before the malicious one: twenty-one residents sign in after a
   * power cut and the twenty-first is told "Too many attempts. Please wait 5 minutes."
   *
   * 240 per 5 minutes is still a hard ceiling on a single host spraying passwords, and it no
   * longer punishes a building for sharing a router. The real defence against guessing ONE
   * account was never this key anyway — it is loginPerIdentifier below, which is per-account
   * and stays deliberately tight at 8 per 15 minutes.
   */
  loginPerIp: { max: 240, windowSeconds: 300 },
  loginPerIdentifier: { max: 8, windowSeconds: 900 },
  mfaVerifyPerUser: { max: 6, windowSeconds: 600 },
  /** Same CGNAT reasoning as loginPerIp. The per-user budget above is the real guard on a TOTP. */
  mfaVerifyPerIp: { max: 240, windowSeconds: 300 },

  /**
   * ORDER CREATION, per student per hour.
   *
   * rz_open_intent already refuses an eleventh intent in an hour — but it is called at step 6
   * of razorpay-order, and createOrder() is step 5. So the floor was checked AFTER a real order
   * already existed in the merchant account. Looping the endpoint minted unlimited orphaned
   * live orders: no intent row will ever claim them, they sit in the owner's dashboard, and
   * Razorpay's own per-merchant API limits eventually throttle the WHOLE account — at which
   * point residents of every hostel tap Pay and are told payments are unavailable.
   *
   * Six, not ten. The database floor stays at ten and this sits under it deliberately, so the
   * refusal comes from here — before Razorpay is ever called — and the DB floor becomes the
   * backstop it was written to be rather than the only line.
   *
   * A student paying rent legitimately opens one order, maybe two if the first sheet is
   * dismissed. Six an hour is already generous for the honest case.
   */
  paymentOrderPerUser: { max: 6, windowSeconds: 3600 },
} as const satisfies Record<string, RateLimitSpec>;

/** Mirrors LIMITS.accountCreatePerUser in lib/rate-limit.ts. */
export const ACCOUNT_CREATE_LIMIT: RateLimitSpec = LIMITS.accountCreatePerUser;

async function hashKey(key: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 48);
}

/**
 * Spend one unit of `key`'s budget and report how long the caller must wait.
 *
 * Returns 0 when the request is allowed, otherwise the seconds remaining in the current
 * window. Throws HttpError(503) — never returns — when the limiter itself cannot be reached,
 * because "we could not count this attempt" must not read as "this attempt was fine".
 *
 * The caller decides what to do with a non-zero result (audit it, word it, combine it with a
 * second key) which is why this returns instead of throwing: the login path checks two keys
 * and must write exactly one audit row for the pair.
 */
export async function consumeRateLimit(
  key: string,
  limit: RateLimitSpec,
  opts: { unavailableMessage?: string } = {},
): Promise<number> {
  try {
    const { data, error } = await serviceClient()
      .rpc("rate_limit", { p_key: await hashKey(key), p_max: limit.max, p_window_seconds: limit.windowSeconds })
      .maybeSingle();
    if (error || !data) throw error ?? new Error("rate_limit: no data");
    const row = data as { allowed: boolean; retry_after_seconds: number };
    if (row.allowed) return 0;
    // A window that has just rolled can legitimately report 0 seconds left; never hand the
    // caller a refusal with "wait 0 seconds".
    return Math.max(1, Number(row.retry_after_seconds) || limit.windowSeconds);
  } catch (e) {
    console.error("[nivora] rate limiter unavailable:", e instanceof Error ? e.message : String(e));
    throw new HttpError(
      503,
      opts.unavailableMessage ?? "This is temporarily unavailable. Please try again in a minute.",
      { extra: { retryAfterSeconds: 60 }, headers: { "Retry-After": "60" } },
    );
  }
}

/**
 * "Is this the first time in `windowSeconds` that `key` has had something to say?"
 *
 * Used to keep the audit trail from becoming the attacker's second weapon. A throttled request
 * is still a request, and a host that keeps hammering after the 429 would otherwise write one
 * `auth.login.rate_limited` row per attempt — thousands of rows on a free-plan database,
 * describing a single event that app.raise_security_alert() has already deduplicated down to
 * one alert per hour. This spends a budget of exactly 1 per window on the same durable
 * counter, so a sustained attack leaves ONE row per key per window instead of one per packet.
 *
 * Fails OPEN, unlike everything else in this file, and the asymmetry is deliberate: the cost
 * of guessing wrong here is a duplicate log line, not an unchecked password guess.
 */
export async function reportOnce(key: string, windowSeconds: number): Promise<boolean> {
  try {
    return (await consumeRateLimit(`report:${key}`, { max: 1, windowSeconds })) === 0;
  } catch {
    return true;
  }
}

/** The 429 every throttled endpoint returns, so the wording and the wire format match. */
export function throttled(message: string, retryAfterSeconds: number): HttpError {
  return new HttpError(429, message, {
    extra: { retryAfterSeconds },
    headers: { "Retry-After": String(retryAfterSeconds) },
  });
}

export async function enforceRateLimit(
  key: string,
  limit: RateLimitSpec = ACCOUNT_CREATE_LIMIT,
): Promise<void> {
  const wait = await consumeRateLimit(key, limit, {
    unavailableMessage: "Account creation is temporarily unavailable. Please try again in a minute.",
  });
  if (wait > 0) throw throttled(`Too many account operations in a short time. Try again in ${wait}s.`, wait);
}
