import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto";
import Razorpay from "razorpay";

/**
 * Razorpay wiring. SERVER ONLY — the `server-only` import above makes importing
 * this from a client component a build error, which is the mechanical guarantee
 * that RAZORPAY_KEY_SECRET and RAZORPAY_WEBHOOK_SECRET never reach a browser.
 *
 * Three environment values, none of them optional in production:
 *
 *   RAZORPAY_KEY_ID          public. Handed to the browser so Checkout can open.
 *   RAZORPAY_KEY_SECRET      secret. Signs API calls. Never leaves the server.
 *   RAZORPAY_WEBHOOK_SECRET  secret. HMAC key for the webhook signature. Set on
 *                            the Razorpay dashboard when the endpoint is added;
 *                            it is NOT the same value as the key secret.
 *
 * The key id is deliberately NOT exposed as NEXT_PUBLIC_*. A NEXT_PUBLIC value is
 * inlined into the client bundle at build time, which would bake a test key into
 * a production build (and vice versa) and put the merchant identity in every
 * page's JS whether or not the user can pay. It is read here and returned to the
 * browser by the order action, once, for the student who is actually paying.
 *
 * Nothing here throws at import time: the app must build and run with none of
 * these set. Callers get a clear, quotable message instead — see docs/payments.md.
 */

export class RazorpayNotConfiguredError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RazorpayNotConfiguredError";
  }
}

const NOT_CONFIGURED =
  "Online payment isn't set up yet. Ask the hostel to enable it, or pay at the warden desk.";

function env(name: "RAZORPAY_KEY_ID" | "RAZORPAY_KEY_SECRET" | "RAZORPAY_WEBHOOK_SECRET"): string | null {
  const raw = process.env[name];
  const value = typeof raw === "string" ? raw.trim() : "";
  return value.length > 0 ? value : null;
}

/** True when an order can actually be created. Cheap — call it before doing work. */
export function isRazorpayConfigured(): boolean {
  return env("RAZORPAY_KEY_ID") !== null && env("RAZORPAY_KEY_SECRET") !== null;
}

/** True when a webhook delivery can be verified. Independent of the API keys. */
export function isWebhookConfigured(): boolean {
  return env("RAZORPAY_WEBHOOK_SECRET") !== null;
}

/**
 * The publishable key id, for the browser. This is the ONLY Razorpay value that
 * is ever allowed to leave the server.
 */
export function razorpayKeyId(): string {
  const id = env("RAZORPAY_KEY_ID");
  if (!id) throw new RazorpayNotConfiguredError(NOT_CONFIGURED);
  return id;
}

/** Live keys start `rzp_live_`, test keys `rzp_test_`. Used only for a UI banner. */
export function isLiveKey(): boolean {
  return (env("RAZORPAY_KEY_ID") ?? "").startsWith("rzp_live_");
}

let client: Razorpay | null = null;

/** The API client. Constructed once per server instance, never per request. */
export function razorpayClient(): Razorpay {
  if (client) return client;
  const key_id = env("RAZORPAY_KEY_ID");
  const key_secret = env("RAZORPAY_KEY_SECRET");
  if (!key_id || !key_secret) {
    throw new RazorpayNotConfiguredError(NOT_CONFIGURED);
  }
  client = new Razorpay({ key_id, key_secret });
  return client;
}

/* ───────────────────────── webhook signature ───────────────────────── */

/**
 * Verify the `X-Razorpay-Signature` header against RAZORPAY_WEBHOOK_SECRET.
 *
 * `rawBody` MUST be the exact bytes that arrived — `await request.text()`, never
 * `JSON.stringify(await request.json())`. A round trip through the JSON parser
 * changes key order, whitespace and number formatting, so the digest would not
 * match a body Razorpay actually signed, and (worse, if someone "fixed" that by
 * loosening the check) the thing verified would no longer be the thing acted on.
 *
 * The comparison is `crypto.timingSafeEqual` over the raw digest bytes. A plain
 * `===` on hex strings returns as soon as two characters differ, which leaks the
 * length of the matching prefix — enough, over many attempts, to reconstruct a
 * valid signature one nibble at a time and mark rent as paid with curl.
 *
 * Returns false for a missing, malformed or wrong signature. Throws only when the
 * secret itself is absent, because that is a deployment fault, not a bad request.
 */
export function verifyWebhookSignature(rawBody: string, signatureHeader: string | null | undefined): boolean {
  const secret = env("RAZORPAY_WEBHOOK_SECRET");
  if (!secret) {
    throw new RazorpayNotConfiguredError(
      "RAZORPAY_WEBHOOK_SECRET is not set — refusing to accept an unverifiable payment webhook.",
    );
  }
  if (typeof signatureHeader !== "string") return false;

  const candidate = signatureHeader.trim();
  // Razorpay sends lowercase hex of a SHA-256 HMAC: exactly 64 hex characters.
  // Anything else cannot be a signature, and rejecting it here keeps Buffer.from
  // from silently truncating garbage into a short buffer.
  if (!/^[0-9a-fA-F]{64}$/.test(candidate)) return false;

  const expected = createHmac("sha256", secret).update(rawBody, "utf8").digest();
  const received = Buffer.from(candidate, "hex");
  if (received.length !== expected.length) return false;
  return timingSafeEqual(received, expected);
}

/* ───────────────────────── money ───────────────────────── */

/**
 * Rupees → paise. Razorpay works entirely in integer minor units, and so does
 * public.payment_intents.amount_paise; the only float in the whole path is the
 * numeric(10,2) coming out of Postgres, and it is converted here, once.
 */
export function toPaise(rupees: number): number {
  if (!Number.isFinite(rupees)) throw new Error("Invalid amount.");
  // (x * 100) alone gives 6849.999999999999 for some two-decimal values.
  return Math.round(Number(rupees.toFixed(2)) * 100);
}

/** Paise → rupees, for display. */
export function fromPaise(paise: number): number {
  return Math.round(paise) / 100;
}

/** Razorpay refuses orders below ₹1. */
export const MIN_ORDER_PAISE = 100;
