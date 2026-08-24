/**
 * Razorpay wiring for NIVORA's Edge Functions.
 *
 * WHY THIS EXISTS SEPARATELY FROM lib/razorpay.ts. That file is the Next.js server's copy and
 * imports `server-only`, `node:crypto` and the `razorpay` npm SDK — none of which belong in a
 * Deno function. The RULES are identical and deliberately restated here, because the security
 * of the mobile money path now depends on this file rather than on that one:
 *
 *   RAZORPAY_KEY_ID          public. The merchant identity Checkout needs. Handed to the phone.
 *   RAZORPAY_KEY_SECRET      SECRET. Signs the Orders API call. Never leaves this function.
 *   RAZORPAY_WEBHOOK_SECRET  SECRET. The HMAC key the delivery signature is checked against.
 *                            You choose this value on the Razorpay dashboard when you add the
 *                            webhook; it is NOT the key secret and the two must not be shared.
 *
 * All three are Supabase FUNCTION SECRETS (`supabase secrets set`), which is what keeps the two
 * secret ones off the device. An APK is a zip file: anything compiled into it is published.
 * See docs/razorpay-in-app.md.
 *
 * Nothing here throws at module load. A deployment with no keys set must still boot and answer
 * "online payment isn't set up yet" — a function that crashes on import returns a 500 that
 * tells a student nothing and tells an operator less.
 */

/** Razorpay refuses an order below ₹1, so there is no point minting one. */
export const MIN_ORDER_PAISE = 100;

/** A Razorpay order id is `order_` + base62. Anchored — this string becomes a DB predicate. */
export const ORDER_ID_RE = /^order_[A-Za-z0-9]{6,30}$/;

/** A payment id is `pay_` + base62. Same reasoning. */
export const PAYMENT_ID_RE = /^pay_[A-Za-z0-9]{6,30}$/;

/** What a student is told when the merchant account was never configured. */
export const NOT_CONFIGURED =
  "Online payment isn't set up yet. You can still pay at the warden desk.";

function env(name: string): string | null {
  const raw = Deno.env.get(name);
  const value = typeof raw === "string" ? raw.trim() : "";
  return value.length > 0 ? value : null;
}

/** The publishable key id. The ONLY Razorpay credential allowed to reach a phone. */
export function keyId(): string | null {
  return env("RAZORPAY_KEY_ID");
}

/** The API secret. Read at the moment of use and never returned, logged or echoed. */
export function keySecret(): string | null {
  return env("RAZORPAY_KEY_SECRET");
}

export function webhookSecret(): string | null {
  return env("RAZORPAY_WEBHOOK_SECRET");
}

/** True when an order can actually be created. Cheap — check before doing any work. */
export function isConfigured(): boolean {
  return keyId() !== null && keySecret() !== null;
}

/** Live keys start `rzp_live_`. Used only to put "TEST MODE" on the sheet. */
export function isLiveKey(): boolean {
  return (keyId() ?? "").startsWith("rzp_live_");
}

/* ─────────────────────────────── money ─────────────────────────────── */

/**
 * Rupees → paise. Razorpay and public.payment_intents.amount_paise are both integer minor
 * units; the only float on the whole path is the `numeric(10,2)` PostgREST hands back, and it
 * is converted here, once.
 *
 * `x * 100` alone gives 6849.999999999999 for some perfectly ordinary two-decimal values, and
 * Math.round of that is still 6850 — but the toFixed(2) first makes it true for every value
 * rather than for the ones we happened to try.
 */
export function toPaise(rupees: number): number {
  if (!Number.isFinite(rupees)) throw new Error("Invalid amount.");
  return Math.round(Number(rupees.toFixed(2)) * 100);
}

/** Paise → rupees, for display only. */
export function fromPaise(paise: number): number {
  return Math.round(paise) / 100;
}

/* ─────────────────────────── webhook signature ─────────────────────────── */

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

/**
 * Verify `X-Razorpay-Signature` against RAZORPAY_WEBHOOK_SECRET.
 *
 * `rawBody` MUST be the exact bytes that arrived — `await req.text()`, never
 * `JSON.stringify(await req.json())`. A round trip through the JSON parser changes key order,
 * whitespace and number formatting, so the digest would not match the body Razorpay signed;
 * and if someone "fixed" that by loosening the check, the thing verified would no longer be
 * the thing acted on.
 *
 * The comparison is `crypto.subtle.verify`, not a string `===` on hex. `===` returns as soon
 * as two characters differ, which leaks the length of the matching prefix — enough, over many
 * attempts, to reconstruct a valid signature one nibble at a time and mark rent as paid with
 * curl. WebCrypto's verify compares the full digest without that early exit.
 *
 * Returns false for a missing, malformed or wrong signature. Throws only when the SECRET is
 * absent, because that is a deployment fault and must fail loudly, not look like a bad request.
 */
export async function verifyWebhookSignature(
  rawBody: string,
  signatureHeader: string | null | undefined,
): Promise<boolean> {
  const secret = webhookSecret();
  if (!secret) {
    throw new Error(
      "RAZORPAY_WEBHOOK_SECRET is not set — refusing to accept an unverifiable payment webhook.",
    );
  }
  if (typeof signatureHeader !== "string") return false;

  const candidate = signatureHeader.trim();
  // Razorpay sends the lowercase hex of a SHA-256 HMAC: exactly 64 hex characters. Anything
  // else cannot be a signature, and rejecting it here keeps hexToBytes from silently turning
  // garbage into a short buffer that then gets compared against a long one.
  if (!/^[0-9a-fA-F]{64}$/.test(candidate)) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return await crypto.subtle.verify(
    "HMAC",
    key,
    hexToBytes(candidate),
    encoder.encode(rawBody),
  );
}

/* ───────────────────────────── Orders API ───────────────────────────── */

export interface CreateOrderInput {
  amountPaise: number;
  /** ≤ 40 chars, unique-ish. Must carry no PII — it is printed on Razorpay's dashboard. */
  receipt: string;
  /** Echoed back on the webhook. FOR HUMANS ONLY — see the warning below. */
  notes: Record<string, string>;
}

export class RazorpayApiError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "RazorpayApiError";
    this.status = status;
  }
}

/**
 * Create an order. This is the one call that uses the key SECRET.
 *
 * NOTES ARE NOT A SOURCE OF TRUTH. They come back on the webhook, so a reader could be tempted
 * to settle from them. Nothing on the settlement path reads them and nothing ever should: they
 * are metadata attached to an order, and the amount that matters is the one the DATABASE wrote
 * into payment_intents.amount_paise at order time.
 *
 * The timeout is deliberate. Without it a hung TCP connection to Razorpay holds the function
 * (and the student's spinner) until the platform kills it, which reads as "the app froze".
 */
export async function createOrder(input: CreateOrderInput): Promise<{ id: string }> {
  const id = keyId();
  const secret = keySecret();
  if (!id || !secret) throw new Error(NOT_CONFIGURED);

  let response: Response;
  try {
    response = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        // btoa is safe here: Razorpay ids and secrets are ASCII by construction.
        Authorization: `Basic ${btoa(`${id}:${secret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: input.amountPaise,
        currency: "INR",
        receipt: input.receipt,
        notes: input.notes,
      }),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (e) {
    throw new RazorpayApiError(502, `Could not reach Razorpay: ${e instanceof Error ? e.name : "error"}`);
  }

  const text = await response.text();
  if (!response.ok) {
    // Razorpay's error bodies are safe to log (they describe OUR request, and the request
    // carried no secret in its body) but are not shown to the student.
    console.error("[payments] razorpay orders API said", response.status, text.slice(0, 400));
    throw new RazorpayApiError(502, `Razorpay refused the order (HTTP ${response.status}).`);
  }

  let parsed: { id?: unknown };
  try {
    parsed = JSON.parse(text) as { id?: unknown };
  } catch {
    throw new RazorpayApiError(502, "Razorpay returned something that is not an order.");
  }

  const orderId = typeof parsed.id === "string" ? parsed.id : "";
  // Shape-check before this string is handed to the phone AND used as a DB predicate.
  // rz_open_intent applies the same regex; failing here gives a better message.
  if (!ORDER_ID_RE.test(orderId)) {
    throw new RazorpayApiError(502, "Razorpay returned an unexpected order id.");
  }
  return { id: orderId };
}
