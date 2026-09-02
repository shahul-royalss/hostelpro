import { NextResponse } from "next/server";
import { auditSystem } from "@/lib/audit";
import { createAdminClient } from "@/lib/supabase/admin";
import {
  isWebhookConfigured,
  ORDER_ID_RE,
  PAYMENT_ID_RE,
  RazorpayNotConfiguredError,
  REFUND_ID_RE,
  verifyWebhookSignature,
} from "@/lib/razorpay";

/**
 * POST /api/webhooks/razorpay — the only thing in this application that can mark
 * rent as paid, and the only thing that can mark it unpaid again.
 *
 * WHAT IT HANDLES
 *   payment.captured   claim the order, credit public.fee_payments.
 *   payment.failed     record the failure. Never touches fee_payments.
 *   refund.created     record an INTENTION. Never touches fee_payments.
 *   refund.processed   the money has actually left — REDUCE fee_payments.amount_paid.
 *   refund.failed      record that the instruction died. Never touches fee_payments.
 *   payment.refunded   a summary of the above; noted in the audit trail, moves nothing.
 *   payment.dispute.*  chargebacks; routed to the reconciliation queue, moves nothing.
 * Everything else is answered 200 {"outcome":"ignored"}.
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

interface RazorpayRefundEntity {
  id?: unknown;
  payment_id?: unknown;
  amount?: unknown;
  currency?: unknown;
  status?: unknown;
  speed_processed?: unknown;
  error_description?: unknown;
}

interface RazorpayEvent {
  event?: unknown;
  payload?: {
    payment?: { entity?: RazorpayPaymentEntity };
    refund?: { entity?: RazorpayRefundEntity };
  };
}

/**
 * ═══ WHICH REFUND EVENT IS ALLOWED TO MOVE MONEY ═══
 *
 * Razorpay emits all three of these for one refund, and NOT reliably in this order
 * on the wire. They mean different things and the difference is the whole feature:
 *
 *   refund.created    An INTENTION. The refund exists as an instruction; nothing
 *                     has left the merchant account, and it can still fail — an
 *                     instant refund to a closed card falls back, or fails
 *                     outright. Reversing a resident's ledger here would mark rent
 *                     unpaid for money that may never reach them, which is a worse
 *                     lie than the bug this replaces. Recorded as 'pending'.
 *   refund.processed  THE MONEY HAS LEFT. This, and only this, reduces fee_payments.
 *   refund.failed     The instruction died. The ledger was never moved, so there is
 *                     nothing to undo — and if this arrives for a refund already
 *                     processed, that is a contradiction for a human, never an
 *                     instruction to re-credit rent.
 *
 * The state comes from the EVENT NAME, not entity.status: the event name is what
 * Razorpay is asserting on this particular delivery. This map and its Deno twin in
 * supabase/functions/razorpay-webhook/index.ts must stay identical.
 */
const REFUND_STATE: Record<string, "pending" | "processed" | "failed"> = {
  "refund.created": "pending",
  "refund.processed": "processed",
  "refund.failed": "failed",
};

/**
 * Raises from rz_record_refund / rz_reverse_fee that are VERDICTS, not outages.
 * Retrying cannot change any of them, so they take a 200 and become a human's
 * problem rather than letting Razorpay hammer the endpoint until it disables the
 * webhook. Same policy the capture path already applies.
 */
const PERMANENT_REFUND_ERROR =
  /Unknown Razorpay payment|never captured|Refunds exceed|does not match the recorded refund|Unknown refund|Refund amount must be|No fee record for|exceeds the/i;

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

/**
 * Refund step 1 — write the refund down. Does not touch fee_payments.
 *
 * Idempotent in the DATABASE, exactly as the capture is: a unique index on
 * payment_refunds.razorpay_refund_id means a retried delivery cannot create a
 * second row, and comes back 'duplicate' instead of reversing the ledger twice.
 */
async function recordRefund(input: {
  paymentId: string;
  refundId: string;
  amountPaise: number;
  state: "pending" | "processed" | "failed";
  reason: string | null;
  speed: string | null;
}) {
  const { data, error } = await createAdminClient().rpc("rz_record_refund", {
    p_payment_id: input.paymentId,
    p_refund_id: input.refundId,
    p_amount_paise: input.amountPaise,
    p_status: input.state,
    p_reason: input.reason,
    p_speed: input.speed,
  });
  if (error) throw error;
  return data as {
    outcome: "recorded" | "advanced" | "duplicate" | "conflict";
    refund_row_id: string;
    intent_id: string;
    hostel_id: string;
    student_id: string;
    period_month: string;
    amount_paise: number;
    status: "pending" | "processed" | "failed";
    already_reversed: boolean;
  };
}

/**
 * Refund step 2 — take the refunded money off the fee ledger, in its own
 * transaction.
 *
 * Separate for the reason recordCapture/creditFee are separate: the ledger move
 * can legitimately be refused — §4.4 hostel-writable, or a month whose total a
 * warden has since corrected below the refund — and if that refusal rolled back the
 * record that Razorpay gave the money away, the app would forget a real refund
 * because a subscription lapsed. Split, the refund stays recorded and only the
 * reversal is outstanding, which is the reconciliation queue
 * (payment_refunds_unreversed_idx) rather than a lost fact.
 *
 * rz_reverse_fee reduces fee_payments.amount_paid and lets the existing BEFORE
 * trigger app.fee_status_compute recompute `status`. It never sets status by hand,
 * never deletes the fee row, and never lets amount_paid go negative.
 */
async function reverseFee(refundRowId: string) {
  const { data, error } = await createAdminClient().rpc("rz_reverse_fee", {
    p_refund_row_id: refundRowId,
  });
  if (error) throw error;
  return data as {
    outcome: "reversed" | "already_reversed" | "not_processed" | "not_credited";
    amount?: number;
    fee_status?: string;
  };
}

/**
 * The refund path. Mirrors handleRefund() in the Deno function line for line — the
 * two deployments cannot share code, so the rules are restated rather than assumed.
 */
async function handleRefund(state: "pending" | "processed" | "failed", refund: RazorpayRefundEntity) {
  const refundId = str(refund.id);
  const paymentId = str(refund.payment_id);

  if (!refundId || !REFUND_ID_RE.test(refundId)) return done("ignored_no_refund");
  if (!paymentId || !PAYMENT_ID_RE.test(paymentId)) return done("ignored_no_payment");

  // The amount is the whole point: a resident who overpaid ₹500 gets ₹500 back, not
  // ₹9,500. Integer paise or nothing — money is never a float on this path.
  const amountPaise = typeof refund.amount === "number" ? refund.amount : Number.NaN;
  if (!Number.isInteger(amountPaise) || amountPaise <= 0) return done("ignored_bad_amount");
  if (str(refund.currency) !== "INR") return done("ignored_currency");

  let record: Awaited<ReturnType<typeof recordRefund>>;
  try {
    record = await recordRefund({
      paymentId,
      refundId,
      amountPaise,
      state,
      reason: str(refund.error_description),
      speed: str(refund.speed_processed),
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    const permanent = PERMANENT_REFUND_ERROR.test(message);
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: paymentId,
      meta: { refundId, amountPaise, stage: "refund_record", permanent, reason: message.slice(0, 180) },
    });
    if (!permanent) {
      console.error("[payments] refund could not be recorded:", message);
      return retryable("refund_error");
    }
    return done("refund_rejected");
  }

  // AUDIT. Money leaving is exactly the event a PG owner will one day need
  // explained, and the trail has to distinguish "a refund was instructed" from
  // "the money went".
  if (record.outcome === "recorded" || record.outcome === "advanced") {
    await auditSystem(
      record.status === "processed"
        ? "payment.refund.processed"
        : record.status === "failed"
          ? "payment.refund.failed"
          : "payment.refund.pending",
      {
        targetType: "student",
        targetId: record.student_id,
        hostelId: record.hostel_id,
        meta: { refundId, paymentId, period: record.period_month, amountPaise: record.amount_paise },
      },
    );
  }

  // refund.failed for a refund we have already processed and reversed. The money
  // left; a later "it failed" does not put it back, and this route will not
  // silently re-credit rent on the strength of a contradiction. A person decides.
  if (record.outcome === "conflict") {
    await auditSystem("payment.reconcile.required", {
      targetType: "student",
      targetId: record.student_id,
      hostelId: record.hostel_id,
      meta: { refundId, paymentId, stage: "refund_conflict", event: state },
    });
    return done("refund_conflict");
  }

  // Only processed money moves a ledger.
  if (record.status !== "processed") return done(`refund_${record.status}`);

  // Attempted on a DUPLICATE delivery too: if an earlier delivery recorded the
  // refund but the reversal failed, this is what repairs it.
  try {
    const reverse = await reverseFee(record.refund_row_id);
    if (reverse.outcome === "reversed") {
      await auditSystem("payment.refund.reversed", {
        targetType: "student",
        targetId: record.student_id,
        hostelId: record.hostel_id,
        meta: {
          refundId,
          paymentId,
          period: record.period_month,
          amount: reverse.amount,
          feeStatus: reverse.fee_status,
        },
      });
    } else if (reverse.outcome === "not_credited") {
      // Razorpay took the money and gave it back, but our ledger never went up in
      // the first place — the capture is itself unreconciled. There is nothing to
      // take down, and inventing a debit would be worse than saying so.
      await auditSystem("payment.reconcile.required", {
        targetType: "student",
        targetId: record.student_id,
        hostelId: record.hostel_id,
        meta: { refundId, paymentId, stage: "refund_uncredited" },
      });
    }
    return done(`refund_${reverse.outcome}`);
  } catch (e) {
    // The refund is recorded and will not be recorded twice. Only the ledger
    // movement is missing, and the row now sits in the reconciliation queue.
    const message = e instanceof Error ? e.message : String(e);
    const permanent = PERMANENT_REFUND_ERROR.test(message);
    console.error("[payments] refunded but not reversed:", message);
    await auditSystem("payment.reconcile.required", {
      targetType: "student",
      targetId: record.student_id,
      hostelId: record.hostel_id,
      meta: { refundId, paymentId, stage: "refund_reverse", permanent, reason: message.slice(0, 180) },
    });
    // Retryable only when retrying could help. "Refund exceeds what is recorded for
    // that month" cannot be fixed by Razorpay sending it again — it needs the desk.
    if (!permanent) return retryable("reverse_error");
    return done("reverse_rejected");
  }
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

  /* ── refund.created | refund.processed | refund.failed ────────────────────
   * A refunded payment must stop counting as paid. See REFUND_STATE above for
   * why only refund.processed is allowed to move the ledger. */
  const refundState = kind ? REFUND_STATE[kind] : undefined;
  if (refundState) return await handleRefund(refundState, event.payload?.refund?.entity ?? {});

  /* ── payment.refunded ─────────────────────────────────────────────────────
   * A payment-level SUMMARY ("this payment is now fully refunded"), not a refund.
   * It carries the payment entity and no refund id, so it cannot be made
   * idempotent on its own — and the money it describes always also arrives as
   * refund.processed, which is handled above and IS idempotent. Acting on both
   * would reverse the same rupees twice. Noted, never actioned. */
  if (kind === "payment.refunded") {
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: str(event.payload?.payment?.entity?.id),
      meta: { stage: "refund_summary", note: "payment.refunded seen; ledger moves on refund.processed" },
    });
    return done("refund_summary_noted");
  }

  /* ── payment.dispute.* ────────────────────────────────────────────────────
   * A chargeback is money HELD, and on a lost dispute money genuinely leaves —
   * but the dispute entity has a different shape (disp_… id, its own fee, no
   * refund id), and a dispute.created is an intention in exactly the way
   * refund.created is. Guessing a payload shape on the money path is worse than
   * routing it loudly to a person, so this goes in the owner's reconciliation
   * queue and deliberately moves nothing. */
  if (kind?.startsWith("payment.dispute.")) {
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: str(event.payload?.payment?.entity?.id),
      meta: { stage: "dispute", event: kind },
    });
    return done("dispute_noted");
  }

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
