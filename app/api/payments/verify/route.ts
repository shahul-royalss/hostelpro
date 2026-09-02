import { NextResponse } from "next/server";
import { audit } from "@/lib/audit";
import { getSessionUser, PermissionError, assertRole } from "@/lib/permissions";
import { rateLimit } from "@/lib/rate-limit";
import {
  isRazorpayConfigured,
  ORDER_ID_RE,
  PAYMENT_ID_RE,
  RazorpayNotConfiguredError,
  verifyCheckoutSignature,
} from "@/lib/razorpay";
import { createClient } from "@/lib/supabase/server";
import type { RentPaymentState } from "@/lib/actions/payments";

/**
 * POST /api/payments/verify — check that a Checkout success callback is genuine.
 *
 * WHAT THIS IS FOR, STATED PLAINLY, BECAUSE THE NAME INVITES THE WRONG ANSWER.
 * This endpoint does not mark anything paid. It cannot: it holds no service-role
 * credential, and `public.payment_intents` has RLS on with a SELECT policy and no
 * INSERT or UPDATE policy for any human role, so the session behind this request
 * has no write path to the payment table at all. Money is recorded by the signed
 * webhook in app/api/webhooks/razorpay/route.ts and by nothing else. See
 * docs/payments.md §3 and §5.
 *
 * So what does it buy? Checkout's `handler` fires in a browser, and a browser can
 * be told anything. Before this existed, the sheet moved to "confirming your
 * payment" on a callback it had not checked — a `fetch()` from a devtools console
 * produced the same screen as a real payment. Verifying the triple proves the
 * callback was produced by Razorpay for an order THIS merchant opened, which is
 * what earns the reassuring screen. It also gives an honest answer for the one
 * case that used to be silent: a callback that does not verify is not a slow
 * payment, and the student should not be told to wait for one.
 *
 * THE SIGNATURE IS NOT THE WEBHOOK'S. Checkout signs `order_id|payment_id` with
 * RAZORPAY_KEY_SECRET; the webhook signs the raw body with
 * RAZORPAY_WEBHOOK_SECRET. verifyCheckoutSignature() and verifyWebhookSignature()
 * are separate functions in lib/razorpay.ts for exactly that reason, and neither
 * will ever accept the other's input.
 *
 * Status codes, deliberately:
 *   401  not signed in
 *   403  signed in but not an active student (or MFA/password step outstanding)
 *   400  a field is missing, malformed, or the signature does not verify
 *   404  the order is not one of this student's own (RLS decides, not us)
 *   503  RAZORPAY_KEY_SECRET is absent — we cannot verify, and will not pretend to
 *   200  verified, plus wherever settlement has actually got to
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Three short ids. Anything bigger is not this request. */
const MAX_BODY_BYTES = 4 * 1024;

function json(body: Record<string, unknown>, status: number) {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

/**
 * Same-origin gate. A Server Action gets Next's Origin/Host check for free; a
 * route handler does not, so it is done here. Browsers send `Origin` on every
 * POST, so a mismatch is a cross-site submission. An absent Origin is not a
 * browser and therefore not a CSRF vector.
 *
 * Nothing here writes, so the worst a cross-site POST could do is burn a rate
 * limit and write an audit row — but a signature oracle that anyone's page can
 * reach is not a thing worth having either.
 */
function sameOrigin(req: Request): boolean {
  const origin = req.headers.get("origin");
  if (!origin) return true;
  try {
    return new URL(origin).host === new URL(req.url).host;
  } catch {
    return false;
  }
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export async function POST(req: Request) {
  if (!sameOrigin(req)) return json({ error: "Cross-origin request refused." }, 403);

  // ── Who is asking ─────────────────────────────────────────────────────────
  // Before the signature, so this cannot be used as an oracle by someone who is
  // not signed in, and so the rate limit has an identity to hang on.
  const user = await getSessionUser();
  if (!user) return json({ error: "You are signed out. Please sign in again." }, 401);
  try {
    // Re-applies the half-authenticated gates (inactive, password change owed,
    // MFA outstanding) exactly as the payment actions do.
    await assertRole("student");
  } catch (e) {
    if (e instanceof PermissionError) return json({ error: e.message }, 403);
    throw e;
  }

  const rl = await rateLimit(`payments:verify:${user.id}`, 30, 300);
  if (!rl.allowed) return json({ error: "Please wait a moment before trying again." }, 429);

  // ── The three fields ──────────────────────────────────────────────────────
  const declared = Number.parseInt(req.headers.get("content-length") ?? "", 10);
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return json({ error: "Payload too large." }, 413);
  }

  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return json({ error: "Unreadable body." }, 400);
  }
  if (raw.length > MAX_BODY_BYTES) return json({ error: "Payload too large." }, 413);

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not an object");
    body = parsed as Record<string, unknown>;
  } catch {
    return json({ error: "Malformed request." }, 400);
  }

  const orderId = str(body.razorpay_order_id);
  const paymentId = str(body.razorpay_payment_id);
  const signature = str(body.razorpay_signature);

  // Missing fields → 400. Shape is checked too: these become predicates on an
  // indexed column and metadata in the audit trail.
  if (!orderId || !paymentId || !signature) {
    return json({ error: "Missing payment details." }, 400);
  }
  if (!ORDER_ID_RE.test(orderId) || !PAYMENT_ID_RE.test(paymentId)) {
    return json({ error: "Missing payment details." }, 400);
  }

  // ── The signature ─────────────────────────────────────────────────────────
  let verified = false;
  try {
    verified = verifyCheckoutSignature({ orderId, paymentId, signature });
  } catch (e) {
    if (e instanceof RazorpayNotConfiguredError || !isRazorpayConfigured()) {
      // We cannot verify. Saying "not verified" would be indistinguishable from a
      // forgery in the trail, and saying "verified" would be a lie. Say neither.
      return json({ error: "Payment verification isn't available right now." }, 503);
    }
    throw e;
  }

  if (!verified) {
    // Same audit action the webhook uses for a delivery that fails its HMAC: the
    // Super Admin security console's detector is what turns a run of these into an
    // alert, and a forged success callback belongs in exactly that bucket. `source`
    // separates the two origins for anyone reading the trail.
    await audit("payment.webhook.rejected", {
      targetType: "payment",
      targetId: paymentId,
      hostelId: user.hostel_id,
      meta: { source: "checkout_callback", reason: "bad_signature", orderId },
    });
    return json({ error: "We couldn't confirm that payment. Nothing has been marked paid." }, 400);
  }

  // ── Verified. Report where settlement has actually got to. ────────────────
  // A read, and only a read. payment_intents_select scopes this to
  // student_id = app.current_student_id(), so a student who somehow held a valid
  // signature for someone else's order still gets a 404 here.
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payment_intents")
    .select("status, credited_at")
    .eq("razorpay_order_id", orderId)
    .maybeSingle();

  if (error) {
    // The signature verified; only our own read failed. The webhook is still the
    // thing that credits, so tell the client to go and poll rather than failing it.
    console.error("[payments] verified a callback but could not read the intent:", error.message);
    return json({ verified: true, state: "pending" satisfies RentPaymentState }, 200);
  }
  if (!data) return json({ error: "We couldn't find that payment." }, 404);

  const row = data as { status: "created" | "captured" | "failed" | "expired"; credited_at: string | null };
  const state: RentPaymentState = row.credited_at
    ? "credited"
    : row.status === "captured"
      ? "captured"
      : row.status === "failed"
        ? "failed"
        : "pending";

  return json({ verified: true, state }, 200);
}
