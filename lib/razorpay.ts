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

/* ───────────────────────── checkout signature ───────────────────────── */

/**
 * Verify the signature Checkout hands the BROWSER when a payment succeeds.
 *
 * This is a DIFFERENT HMAC from verifyWebhookSignature() above, and the two must
 * never be swapped for one another:
 *
 *                 keyed with              hashes
 *   webhook       RAZORPAY_WEBHOOK_SECRET the raw request body, byte for byte
 *   checkout      RAZORPAY_KEY_SECRET     `${order_id}|${payment_id}`, nothing else
 *
 * Feeding a checkout triple to the webhook verifier (or a raw body to this one)
 * fails every time, which at least is loud. The dangerous version of that mistake
 * is noticing the failure and "fixing" it by loosening a check.
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT. A valid signature proves the browser's
 * success callback really came from Razorpay for an order this merchant opened —
 * it is not a `fetch()` someone wrote in a console. It does NOT prove the money
 * settled, and it is NOT what credits a fee: a client can simply close the tab
 * before this ever runs, and the callback is forgeable in exactly the way that
 * matters least (an attacker who wants free rent does not need to forge it, they
 * need the webhook, which they cannot forge). Settlement stays where it belongs,
 * in app/api/webhooks/razorpay/route.ts. See docs/payments.md §3.
 *
 * The compare is crypto.timingSafeEqual over the digest bytes, for the same
 * reason the webhook's is — a `===` on hex leaks the matching prefix length.
 *
 * Returns false for a missing, malformed or wrong signature. Throws only when the
 * key secret is absent, because that is a deployment fault and answering "not
 * verified" would be indistinguishable from a forgery in the audit trail.
 */
export function verifyCheckoutSignature(input: {
  orderId: string;
  paymentId: string;
  signature: string;
}): boolean {
  const secret = env("RAZORPAY_KEY_SECRET");
  if (!secret) {
    throw new RazorpayNotConfiguredError(
      "RAZORPAY_KEY_SECRET is not set — refusing to report a checkout callback as verified.",
    );
  }

  const { orderId, paymentId, signature } = input;
  if (typeof orderId !== "string" || typeof paymentId !== "string" || typeof signature !== "string") {
    return false;
  }

  const candidate = signature.trim();
  // Lowercase hex of a SHA-256 HMAC: exactly 64 hex characters. Rejecting anything
  // else keeps Buffer.from() from silently truncating garbage into a short buffer.
  if (!/^[0-9a-fA-F]{64}$/.test(candidate)) return false;

  // The payload is the two ids joined by a literal pipe, in this order. Razorpay
  // signs `order_id|payment_id` — reversing them verifies nothing and matches
  // nothing, so the ids are named rather than positional at the call site.
  const expected = createHmac("sha256", secret).update(`${orderId}|${paymentId}`, "utf8").digest();
  const received = Buffer.from(candidate, "hex");
  if (received.length !== expected.length) return false;
  return timingSafeEqual(received, expected);
}

/* ───────────────────────── id shapes ───────────────────────── */

/**
 * Razorpay ids: a fixed prefix plus base62. These strings become predicates on
 * indexed columns and get echoed into audit metadata, so they are shape-checked
 * everywhere they enter — including on the webhook, where the HMAC has already
 * proved origin. A signed body is authentic, not necessarily well-formed.
 *
 * Defined here, once, because all three entry points (order creation, the
 * checkout verifier, the webhook) need the same answer and three private copies
 * are three chances to drift.
 */
export const ORDER_ID_RE = /^order_[A-Za-z0-9]{6,30}$/;
export const PAYMENT_ID_RE = /^pay_[A-Za-z0-9]{6,30}$/;

/**
 * A refund id, `rfnd_` + base62. This one carries more weight than the other two:
 * it is the IDEMPOTENCY KEY for a ledger REVERSAL. The unique index
 * payment_refunds_refund_key is built on it, so a malformed value reaching the
 * database would either fail the write or claim a row that is not the refund being
 * described. Kept here beside the other two so the Next.js and Deno copies cannot
 * disagree about what a refund id looks like.
 */
export const REFUND_ID_RE = /^rfnd_[A-Za-z0-9]{6,30}$/;

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
