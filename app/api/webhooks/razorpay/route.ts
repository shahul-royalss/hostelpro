import { NextResponse } from "next/server";
import { auditSystem } from "@/lib/audit";
import { createAdminClient } from "@/lib/supabase/admin";
import { isWebhookConfigured, RazorpayNotConfiguredError, verifyWebhookSignature } from "@/lib/razorpay";

/**
 * POST /api/webhooks/razorpay — the only thing in this application that can mark
 * rent as paid.
 *
 * Razorpay is not signed in and never will be, so this route has to be reachable
 * without a session. That makes the signature check the entire perimeter: an
 * unverified webhook is a curl command that settles anyone's rent for free.
 *
 *  1. The RAW body is read with `req.text()` and the HMAC is computed over those
 *     exact bytes. Nothing is re-serialised, because a JSON round trip changes
 *     the bytes and the thing verified must be the thing acted on.
 *  2. crypto.timingSafeEqual, not `===` — see lib/razorpay.ts for why.
 *  3. Only then is the body parsed, and only then does anything touch the database.
 *
 * The settlement helpers below are module-local and NOT exported. This file is a
 * route handler, not a `"use server"` module, so there is no action id for them
 * and no way to reach them except through a delivery that has already verified.
 *
 * SERVICE ROLE: public.payment_intents has no INSERT/UPDATE policy for any human
 * role — that is the point of it — so the two settlement RPCs are granted to
 * service_role alone. There is no unprivileged way to write this table, which is
 * exactly the property that makes the table trustworthy. This is the only file in
 * the payment feature that holds that credential; order creation deliberately does
 * not (see rz_open_intent in db/migrations/2026-08-24-payments.sql).
 *
 * MIDDLEWARE: this path must be listed in PUBLIC_PATHS in lib/supabase/middleware.ts
 * or every delivery is answered with a 307 to /login and no payment is ever
 * credited. Exempt from the SESSION gate only — the signature check above is not
 * middleware's and cannot be skipped by it.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** A Razorpay event is a few hundred bytes. Anything larger is not one. */
const MAX_BODY_BYTES = 64 * 1024;

/** Razorpay ids: `pay_` / `order_` + base62. */
const PAYMENT_ID_RE = /^pay_[A-Za-z0-9]{6,30}$/;
const ORDER_ID_RE = /^order_[A-Za-z0-9]{6,30}$/;

interface RazorpayPaymentEntity {
  id?: unknown;
  order_id?: unknown;
  amount?: unknown;
  currency?: unknown;
  method?: unknown;
  status?: unknown;
  error_description?: unknown;
  error_reason?: unknown;
}

interface RazorpayEvent {
  event?: unknown;
  payload?: { payment?: { entity?: RazorpayPaymentEntity } };
}

/** 200 with a minimal body. Razorpay only reads the status code. */
function done(outcome: string) {
  return NextResponse.json({ outcome }, { status: 200, headers: { "Cache-Control": "no-store" } });
}

/** Non-2xx makes Razorpay retry with backoff — use it only for OUR faults. */
function retryable(outcome: string) {
  return NextResponse.json({ outcome }, { status: 500, headers: { "Cache-Control": "no-store" } });
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

/**
 * Step 1 — record that the money was taken. Idempotent in the DATABASE: the
 * unique index on payment_intents.razorpay_payment_id plus a claim predicate of
 * `razorpay_payment_id is null` mean a retried delivery updates zero rows and
 * comes back as 'duplicate' instead of crediting a second time.
 */
async function recordCapture(entity: {
  paymentId: string;
  orderId: string;
  amountPaise: number;
  method: string | null;
}) {
  const { data, error } = await createAdminClient().rpc("rz_record_capture", {
    p_order_id: entity.orderId,
    p_payment_id: entity.paymentId,
    p_amount_paise: entity.amountPaise,
    p_method: entity.method,
  });
  if (error) throw error;
  return data as {
    outcome: "captured" | "duplicate";
    intent_id: string;
    hostel_id: string;
    student_id: string;
    period_month: string;
    amount_paise: number;
    already_credited: boolean;
  };
}

/**
 * Step 2 — put it on the fee ledger, in its own transaction.
 *
 * Separate on purpose. rz_credit_fee() calls the warden's own wd_record_payment()
 * with every one of its guards intact, and one of those guards (§4.4, hostel
 * writable) can legitimately refuse. If that happened inside the capture
 * transaction, the refusal would roll back the record that Razorpay took the
 * money — the app would forget a real payment because a subscription lapsed.
 * Split, the money stays recorded and only the credit is outstanding, which is a
 * reconcilable state rather than a lost one. See docs/payments.md §7.
 */
async function creditFee(intentId: string) {
  const { data, error } = await createAdminClient().rpc("rz_credit_fee", { p_intent_id: intentId });
  if (error) throw error;
  return data as { outcome: "credited" | "already_credited" | "not_captured"; amount?: number; fee_status?: string };
}

async function markFailed(orderId: string, reason: string | null) {
  const { error } = await createAdminClient().rpc("rz_mark_failed", {
    p_order_id: orderId,
    p_reason: reason,
  });
  if (error) throw error;
}

export async function POST(req: Request) {
  // ── 0. Refuse to be an unverifiable endpoint ──────────────────────────────
  // Without the secret there is no way to tell Razorpay from an attacker, and
  // "assume it's genuine" is how rent gets marked paid with curl. Fail closed.
  if (!isWebhookConfigured()) {
    await auditSystem("payment.webhook.rejected", { meta: { reason: "webhook_secret_missing" } });
    return NextResponse.json({ error: "Webhook is not configured." }, { status: 503 });
  }

  const declared = Number.parseInt(req.headers.get("content-length") ?? "", 10);
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large." }, { status: 413 });
  }

  // ── 1. The RAW bytes. Never JSON.stringify(await req.json()). ─────────────
  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return NextResponse.json({ error: "Unreadable body." }, { status: 400 });
  }
  if (raw.length > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large." }, { status: 413 });
  }

  // ── 2. Signature, over those exact bytes, compared in constant time ───────
  let verified = false;
  try {
    verified = verifyWebhookSignature(raw, req.headers.get("x-razorpay-signature"));
  } catch (e) {
    if (e instanceof RazorpayNotConfiguredError) {
      return NextResponse.json({ error: "Webhook is not configured." }, { status: 503 });
    }
    throw e;
  }
  if (!verified) {
    // Deliberately vague to the caller, loud in the trail. audit_log_detect on the
    // Super Admin security console is what turns a stream of these into an alert.
    await auditSystem("payment.webhook.rejected", { meta: { reason: "bad_signature", bytes: raw.length } });
    return NextResponse.json({ error: "Invalid signature." }, { status: 401 });
  }

  // ── 3. Only now is any of this treated as data ────────────────────────────
  let event: RazorpayEvent;
  try {
    event = JSON.parse(raw) as RazorpayEvent;
  } catch {
    return NextResponse.json({ error: "Malformed payload." }, { status: 400 });
  }

  const kind = str(event.event);
  const entity = event.payload?.payment?.entity ?? {};
  const paymentId = str(entity.id);
  const orderId = str(entity.order_id);

  // Ids are validated for SHAPE even though the signature already proved origin:
  // a signed body is authentic, not necessarily well-formed, and these strings
  // become predicates on indexed columns.
  if (kind !== "payment.captured" && kind !== "payment.failed") return done("ignored");
  if (!orderId || !ORDER_ID_RE.test(orderId)) return done("ignored_no_order");
  if (!paymentId || !PAYMENT_ID_RE.test(paymentId)) return done("ignored_no_payment");

  /* ── payment.failed ───────────────────────────────────────────────────── */
  if (kind === "payment.failed") {
    try {
      await markFailed(orderId, str(entity.error_description) ?? str(entity.error_reason));
      await auditSystem("payment.failed", { targetType: "payment", targetId: paymentId, meta: { orderId } });
      return done("failed_recorded");
    } catch (e) {
      console.error("[payments] could not record a failed payment:", e instanceof Error ? e.message : String(e));
      return retryable("failed_record_error");
    }
  }

  /* ── payment.captured ─────────────────────────────────────────────────── */
  const amountPaise = typeof entity.amount === "number" ? entity.amount : Number.NaN;
  if (!Number.isInteger(amountPaise) || amountPaise <= 0) return done("ignored_bad_amount");
  if (str(entity.currency) !== "INR") return done("ignored_currency");

  let capture: Awaited<ReturnType<typeof recordCapture>>;
  try {
    capture = await recordCapture({ paymentId, orderId, amountPaise, method: str(entity.method) });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    // P0001 raises from rz_record_capture are verdicts, not outages: an order we
    // have no row for, or an amount that disagrees with the one this server set.
    // Retrying cannot change either, so take the 200 and make it a human's problem
    // rather than letting Razorpay hammer the endpoint until it disables it.
    const permanent = /Unknown Razorpay order|already settled by a different payment|does not match the order/i.test(message);
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: paymentId,
      meta: { orderId, amountPaise, stage: "capture", permanent, reason: message.slice(0, 180) },
    });
    if (!permanent) {
      console.error("[payments] capture could not be recorded:", message);
      return retryable("capture_error");
    }
    return done("capture_rejected");
  }

  if (capture.outcome === "captured") {
    await auditSystem("payment.captured", {
      targetType: "student",
      targetId: capture.student_id,
      hostelId: capture.hostel_id,
      meta: { orderId, paymentId, period: capture.period_month, amountPaise: capture.amount_paise },
    });
  }

  // Always attempt the credit, including on a duplicate delivery: if a previous
  // delivery recorded the capture but the credit failed, this is what repairs it.
  try {
    const credit = await creditFee(capture.intent_id);
    if (credit.outcome === "credited") {
      await auditSystem("payment.credited", {
        targetType: "student",
        targetId: capture.student_id,
        hostelId: capture.hostel_id,
        meta: {
          orderId,
          paymentId,
          period: capture.period_month,
          amount: credit.amount,
          feeStatus: credit.fee_status,
        },
      });
    }
    return done(credit.outcome);
  } catch (e) {
    // The money is recorded and will not be recorded twice. Only the ledger entry
    // is missing, and the row is now in the reconciliation queue.
    const message = e instanceof Error ? e.message : String(e);
    console.error("[payments] captured but not credited:", message);
    await auditSystem("payment.reconcile.required", {
      targetType: "student",
      targetId: capture.student_id,
      hostelId: capture.hostel_id,
      meta: { orderId, paymentId, stage: "credit", reason: message.slice(0, 180) },
    });
    // Retryable: a later delivery re-enters at recordCapture(), gets 'duplicate',
    // and tries the credit again. If the tenant renews, it heals by itself.
    return retryable("credit_error");
  }
}
