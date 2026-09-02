/**
 * POST /functions/v1/razorpay-webhook — the only thing in the mobile stack that can mark rent
 * as paid, and the only thing that can mark it unpaid again.
 *
 * ═══ WHAT IT HANDLES ═══
 *   payment.captured   claim the order, credit public.fee_payments.
 *   payment.failed     record the failure. Never touches fee_payments.
 *   refund.created     record an INTENTION. Never touches fee_payments.
 *   refund.processed   the money has actually left — REDUCE fee_payments.amount_paid.
 *   refund.failed      record that the instruction died. Never touches fee_payments.
 *   payment.refunded   a summary of the above; noted in the audit trail, moves nothing.
 *   payment.dispute.*  chargebacks; routed to the reconciliation queue, moves nothing.
 * Everything else is answered 200 {"outcome":"ignored"}.
 *
 * ═══ THE SIGNATURE IS THE ENTIRE PERIMETER ═══
 * Razorpay is not signed in and never will be, so this endpoint has to be reachable with no
 * session at all. That makes the HMAC check the whole of the security boundary: an unverified
 * webhook is a curl command that settles anybody's rent for free. Concretely —
 *
 *   1. The RAW body is read with req.text() and the HMAC is computed over those exact bytes.
 *      Nothing is re-serialised, because a JSON round trip changes the bytes and the thing
 *      verified must be the thing acted on.
 *   2. crypto.subtle.verify, not `===` on hex — see _shared/razorpay.ts for why a string
 *      compare here is a working forgery oracle.
 *   3. Only then is the body parsed, and only then does anything touch the database.
 *
 * An unverifiable delivery is treated as HOSTILE, not as "probably fine": with no
 * RAZORPAY_WEBHOOK_SECRET set, this refuses every delivery with a 503 rather than assuming
 * good faith.
 *
 * ═══ SERVICE ROLE ═══
 * public.payment_intents has no INSERT/UPDATE policy for any human role — that is the point of
 * it — so the settlement RPCs are granted to service_role alone. This function is the only
 * part of the mobile payment feature that holds that credential; razorpay-order deliberately
 * does not.
 *
 * ═══ DEPLOY — READ THIS OR EVERY DELIVERY 401s ═══
 *   supabase functions deploy razorpay-webhook --no-verify-jwt
 *
 * Without --no-verify-jwt the platform demands a project JWT before this code ever runs.
 * Razorpay does not send one, so every delivery would be rejected at the gateway, the student
 * would pay, and the fee ledger would never move. The flag does NOT weaken anything: the
 * signature check above is this function's own and cannot be skipped by it.
 *
 * ═══ ONE ENDPOINT, NOT TWO ═══
 * app/api/webhooks/razorpay/route.ts does the same job for the Next.js deployment. Register
 * exactly ONE of the two URLs on the Razorpay dashboard. Registering both is not dangerous —
 * the unique index on payment_intents.razorpay_payment_id makes a double credit impossible —
 * but it doubles every delivery and makes the audit trail read as if each payment happened
 * twice. See docs/razorpay-in-app.md §"Which webhook".
 */
import { serviceClient } from "../_shared/supabase.ts";
import {
  ORDER_ID_RE,
  PAYMENT_ID_RE,
  REFUND_ID_RE,
  verifyWebhookSignature,
  webhookSecret,
} from "../_shared/razorpay.ts";

/** A Razorpay event is a few hundred bytes. Anything larger is not one. */
const MAX_BODY_BYTES = 64 * 1024;

/** 200 with a minimal body. Razorpay only reads the status code. */
function done(outcome: string): Response {
  return new Response(JSON.stringify({ outcome }), {
    status: 200,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

/** Non-2xx makes Razorpay retry with backoff — use it only for OUR faults. */
function retryable(outcome: string): Response {
  return new Response(JSON.stringify({ outcome }), {
    status: 500,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function refuse(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

interface PaymentEntity {
  id?: unknown;
  order_id?: unknown;
  amount?: unknown;
  currency?: unknown;
  method?: unknown;
  error_description?: unknown;
  error_reason?: unknown;
}

interface CaptureResult {
  outcome: "captured" | "duplicate";
  intent_id: string;
  hostel_id: string;
  student_id: string;
  period_month: string;
  amount_paise: number;
  already_credited: boolean;
}

interface RefundEntity {
  id?: unknown;
  payment_id?: unknown;
  amount?: unknown;
  currency?: unknown;
  status?: unknown;
  speed_processed?: unknown;
  error_description?: unknown;
}

interface RefundRecordResult {
  outcome: "recorded" | "advanced" | "duplicate" | "conflict";
  refund_row_id: string;
  intent_id: string;
  hostel_id: string;
  student_id: string;
  period_month: string;
  amount_paise: number;
  status: "pending" | "processed" | "failed";
  already_reversed: boolean;
}

/**
 * ═══ WHICH REFUND EVENT IS ALLOWED TO MOVE MONEY ═══
 *
 * Razorpay emits all three of these for one refund, and NOT reliably in this order on the wire.
 * They mean different things and the difference is the whole feature:
 *
 *   refund.created    An INTENTION. The refund exists as an instruction; nothing has left the
 *                     merchant account. It can still fail — an instant refund to a closed card
 *                     falls back, or fails outright. Reversing a resident's ledger here would
 *                     mark rent unpaid for money that may never reach them, which is a worse
 *                     lie than the bug this replaces. Recorded as 'pending'. Ledger untouched.
 *   refund.processed  THE MONEY HAS LEFT. This, and only this, reduces fee_payments.
 *   refund.failed     The instruction died. The ledger was never moved, so there is nothing to
 *                     undo — and if this arrives for a refund already processed, that is a
 *                     contradiction for a human, never an instruction to re-credit rent.
 *
 * The state is taken from the EVENT NAME, not from entity.status: the event name is what
 * Razorpay is asserting on this particular delivery.
 */
const REFUND_STATE: Record<string, "pending" | "processed" | "failed"> = {
  "refund.created": "pending",
  "refund.processed": "processed",
  "refund.failed": "failed",
};

/**
 * Raises from rz_record_refund / rz_reverse_fee that are VERDICTS, not outages. Retrying cannot
 * change any of them, so they take a 200 and become a human's problem rather than letting
 * Razorpay hammer the endpoint until it disables the webhook. Same policy as the capture path.
 */
const PERMANENT_REFUND_ERROR =
  /Unknown Razorpay payment|never captured|Refunds exceed|does not match the recorded refund|Unknown refund|Refund amount must be|No fee record for|exceeds the/i;

/**
 * Best-effort audit. public.audit_event() swallows its own failures by design, and a failure to
 * write a log line must never be the reason a payment is not credited.
 */
async function auditSystem(
  action: string,
  opts: { targetType?: string; targetId?: string; hostelId?: string; meta?: Record<string, unknown> } = {},
): Promise<void> {
  try {
    await serviceClient().rpc("audit_event", {
      p_action: action,
      p_target_type: opts.targetType ?? null,
      p_target_id: opts.targetId ?? null,
      p_hostel_id: opts.hostelId ?? null,
      p_meta: opts.meta ?? {},
    });
  } catch (e) {
    console.error("[payments] audit failed:", e instanceof Error ? e.message : String(e));
  }
}

/**
 * The refund path, in the same two-step shape as the capture path.
 *
 * STEP 1 rz_record_refund writes the refund down. STEP 2 rz_reverse_fee takes it off the fee
 * ledger. Two transactions, deliberately, for the reason the capture/credit split exists: the
 * ledger move can legitimately be refused (§4.4, hostel not writable, or a month whose total a
 * warden has since corrected), and if that refusal rolled back the record that Razorpay gave the
 * money away, the app would forget a real refund. Split, the refund stays recorded and only the
 * reversal is outstanding — the reconciliation queue (payment_refunds_unreversed_idx), which is
 * a state a person can fix, rather than a fact that is gone.
 *
 * IDEMPOTENCY is the database's, not this function's: a unique index on razorpay_refund_id, and
 * a reversal that claims under `reversed_at is null`. A replayed refund.processed therefore
 * comes back 'duplicate' / 'already_reversed' and moves fee_payments zero further rupees.
 */
async function handleRefund(
  db: ReturnType<typeof serviceClient>,
  state: "pending" | "processed" | "failed",
  refund: RefundEntity,
): Promise<Response> {
  const refundId = str(refund.id);
  const paymentId = str(refund.payment_id);

  if (!refundId || !REFUND_ID_RE.test(refundId)) return done("ignored_no_refund");
  if (!paymentId || !PAYMENT_ID_RE.test(paymentId)) return done("ignored_no_payment");

  // The amount is the whole point: a resident who overpaid ₹500 gets ₹500 back, not ₹9,500.
  // Integer paise or nothing — money is never a float on this path.
  const amountPaise = typeof refund.amount === "number" ? refund.amount : Number.NaN;
  if (!Number.isInteger(amountPaise) || amountPaise <= 0) return done("ignored_bad_amount");
  if (str(refund.currency) !== "INR") return done("ignored_currency");

  // ── Step 1. Record it.
  const { data: recordData, error: recordError } = await db.rpc("rz_record_refund", {
    p_payment_id: paymentId,
    p_refund_id: refundId,
    p_amount_paise: amountPaise,
    p_status: state,
    p_reason: str(refund.error_description),
    p_speed: str(refund.speed_processed),
  });

  if (recordError) {
    const message = recordError.message ?? "";
    const permanent = PERMANENT_REFUND_ERROR.test(message);
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: paymentId,
      meta: {
        refundId, amountPaise, stage: "refund_record", permanent, source: "edge",
        reason: message.slice(0, 180),
      },
    });
    if (!permanent) {
      console.error("[payments] refund could not be recorded:", message);
      return retryable("refund_error");
    }
    return done("refund_rejected");
  }

  const record = recordData as RefundRecordResult;

  // AUDIT. Money leaving is exactly the event a PG owner will one day need explained, and the
  // trail has to distinguish "a refund was instructed" from "the money went".
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
        meta: {
          refundId, paymentId, period: record.period_month,
          amountPaise: record.amount_paise, source: "edge",
        },
      },
    );
  }

  // refund.failed for a refund we have already processed and reversed. The money left; a later
  // "it failed" does not put it back, and this endpoint will not silently re-credit rent on the
  // strength of a contradiction. A person decides.
  if (record.outcome === "conflict") {
    await auditSystem("payment.reconcile.required", {
      targetType: "student",
      targetId: record.student_id,
      hostelId: record.hostel_id,
      meta: { refundId, paymentId, stage: "refund_conflict", event: state, source: "edge" },
    });
    return done("refund_conflict");
  }

  // Only processed money moves a ledger.
  if (record.status !== "processed") return done(`refund_${record.status}`);

  // ── Step 2. Reverse it. Attempted on a DUPLICATE delivery too: if an earlier delivery
  // recorded the refund but the reversal failed, this is what repairs it.
  const { data: reverseData, error: reverseError } = await db.rpc("rz_reverse_fee", {
    p_refund_row_id: record.refund_row_id,
  });

  if (reverseError) {
    // The refund is recorded and will not be recorded twice. Only the ledger movement is
    // missing, and the row now sits in the reconciliation queue.
    const message = reverseError.message ?? "";
    const permanent = PERMANENT_REFUND_ERROR.test(message);
    console.error("[payments] refunded but not reversed:", message);
    await auditSystem("payment.reconcile.required", {
      targetType: "student",
      targetId: record.student_id,
      hostelId: record.hostel_id,
      meta: {
        refundId, paymentId, stage: "refund_reverse", permanent, source: "edge",
        reason: message.slice(0, 180),
      },
    });
    // Retryable only when retrying could help. "Refund exceeds what is recorded for that month"
    // cannot be fixed by Razorpay sending it again — it needs the warden desk.
    if (!permanent) return retryable("reverse_error");
    return done("reverse_rejected");
  }

  const reverse = reverseData as {
    outcome: string;
    amount?: number;
    fee_status?: string;
    period_month?: string;
  };

  if (reverse.outcome === "reversed") {
    await auditSystem("payment.refund.reversed", {
      targetType: "student",
      targetId: record.student_id,
      hostelId: record.hostel_id,
      meta: {
        refundId, paymentId, period: record.period_month,
        amount: reverse.amount, feeStatus: reverse.fee_status, source: "edge",
      },
    });
  } else if (reverse.outcome === "not_credited") {
    // Razorpay took the money and gave it back, but our ledger never went up in the first place
    // — the capture is itself unreconciled. There is nothing to take down, and inventing a debit
    // would be worse than saying so.
    await auditSystem("payment.reconcile.required", {
      targetType: "student",
      targetId: record.student_id,
      hostelId: record.hostel_id,
      meta: { refundId, paymentId, stage: "refund_uncredited", source: "edge" },
    });
  }

  return done(`refund_${reverse.outcome}`);
}

Deno.serve(async (req: Request): Promise<Response> => {
  // No OPTIONS/CORS handling: this endpoint is called by Razorpay's servers, not by a browser,
  // and advertising it to cross-origin JavaScript would serve no one but a prober.
  if (req.method !== "POST") return refuse(405, "Method not allowed.");

  // ── 0. Refuse to be an unverifiable endpoint ───────────────────────────────
  // Without the secret there is no way to tell Razorpay from an attacker, and "assume it's
  // genuine" is how rent gets marked paid with curl. Fail closed.
  if (!webhookSecret()) {
    await auditSystem("payment.webhook.rejected", { meta: { reason: "webhook_secret_missing" } });
    return refuse(503, "Webhook is not configured.");
  }

  const declared = Number.parseInt(req.headers.get("content-length") ?? "", 10);
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    return refuse(413, "Payload too large.");
  }

  // ── 1. The RAW bytes. Never JSON.stringify(await req.json()). ──────────────
  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return refuse(400, "Unreadable body.");
  }
  if (raw.length > MAX_BODY_BYTES) return refuse(413, "Payload too large.");

  // ── 2. Signature, over those exact bytes ───────────────────────────────────
  let verified = false;
  try {
    verified = await verifyWebhookSignature(raw, req.headers.get("x-razorpay-signature"));
  } catch {
    return refuse(503, "Webhook is not configured.");
  }
  if (!verified) {
    // Deliberately vague to the caller, loud in the trail: a stream of these is what the Super
    // Admin security console turns into an alert.
    await auditSystem("payment.webhook.rejected", {
      meta: { reason: "bad_signature", bytes: raw.length, source: "edge" },
    });
    return refuse(401, "Invalid signature.");
  }

  // ── 3. Only now is any of this treated as data ─────────────────────────────
  let event: {
    event?: unknown;
    payload?: { payment?: { entity?: PaymentEntity }; refund?: { entity?: RefundEntity } };
  };
  try {
    event = JSON.parse(raw);
  } catch {
    return refuse(400, "Malformed payload.");
  }

  const kind = str(event.event);
  const db = serviceClient();

  /* ── refund.created | refund.processed | refund.failed ────────────────────
   * A refunded payment must stop counting as paid. See REFUND_STATE above for why only
   * refund.processed is allowed to move the ledger. */
  const refundState = kind ? REFUND_STATE[kind] : undefined;
  if (refundState) return await handleRefund(db, refundState, event.payload?.refund?.entity ?? {});

  /* ── payment.refunded ─────────────────────────────────────────────────────
   * A payment-level SUMMARY ("this payment is now fully refunded"), not a refund. It carries
   * the payment entity and no refund id, so it cannot be made idempotent on its own — and the
   * money it describes always also arrives as refund.processed, which is handled above and IS
   * idempotent. Acting on both would reverse the same rupees twice. Noted, never actioned. */
  if (kind === "payment.refunded") {
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: str(event.payload?.payment?.entity?.id) ?? undefined,
      meta: { stage: "refund_summary", source: "edge", note: "payment.refunded seen; ledger moves on refund.processed" },
    });
    return done("refund_summary_noted");
  }

  /* ── payment.dispute.* ────────────────────────────────────────────────────
   * A chargeback is money HELD, and on a lost dispute money genuinely leaves — but the dispute
   * entity has a different shape (disp_… id, its own fee, no refund id), and a dispute.created
   * is an intention in exactly the way refund.created is. Guessing a payload shape on the money
   * path is worse than routing it loudly to a person, so this is recorded in the owner's
   * reconciliation queue and deliberately moves nothing. */
  if (kind && kind.startsWith("payment.dispute.")) {
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: str(event.payload?.payment?.entity?.id) ?? undefined,
      meta: { stage: "dispute", event: kind, source: "edge" },
    });
    return done("dispute_noted");
  }

  const entity = event.payload?.payment?.entity ?? {};
  const paymentId = str(entity.id);
  const orderId = str(entity.order_id);

  // Ids are shape-checked even though the signature already proved origin: a signed body is
  // authentic, not necessarily well-formed, and these strings become predicates on indexed
  // columns.
  if (kind !== "payment.captured" && kind !== "payment.failed") return done("ignored");
  if (!orderId || !ORDER_ID_RE.test(orderId)) return done("ignored_no_order");
  if (!paymentId || !PAYMENT_ID_RE.test(paymentId)) return done("ignored_no_payment");

  /* ── payment.failed ──────────────────────────────────────────────────────
   * Never touches fee_payments. rz_mark_failed refuses to overwrite a row that already carries
   * a payment id, so a late failure event cannot un-settle a capture that already landed. */
  if (kind === "payment.failed") {
    const { error } = await db.rpc("rz_mark_failed", {
      p_order_id: orderId,
      p_reason: str(entity.error_description) ?? str(entity.error_reason),
    });
    if (error) {
      console.error("[payments] could not record a failed payment:", error.message);
      return retryable("failed_record_error");
    }
    await auditSystem("payment.failed", {
      targetType: "payment",
      targetId: paymentId,
      meta: { orderId, source: "edge" },
    });
    return done("failed_recorded");
  }

  /* ── payment.captured ─────────────────────────────────────────────────── */
  const amountPaise = typeof entity.amount === "number" ? entity.amount : Number.NaN;
  if (!Number.isInteger(amountPaise) || amountPaise <= 0) return done("ignored_bad_amount");
  if (str(entity.currency) !== "INR") return done("ignored_currency");

  // Step 1 — record that the money was taken. Idempotent in the DATABASE: the unique index on
  // razorpay_payment_id plus a claim predicate of `razorpay_payment_id is null` mean a retried
  // delivery updates zero rows and comes back 'duplicate' instead of crediting twice.
  const { data: captureData, error: captureError } = await db.rpc("rz_record_capture", {
    p_order_id: orderId,
    p_payment_id: paymentId,
    p_amount_paise: amountPaise,
    p_method: str(entity.method),
  });

  if (captureError) {
    const message = captureError.message ?? "";
    // P0001 raises from rz_record_capture are VERDICTS, not outages: an order we have no row
    // for, or an amount that disagrees with the one the server set. Retrying cannot change
    // either, so take the 200 and make it a human's problem rather than letting Razorpay hammer
    // the endpoint until it disables it.
    const permanent =
      /Unknown Razorpay order|already settled by a different payment|does not match the order/i
        .test(message);
    await auditSystem("payment.reconcile.required", {
      targetType: "payment",
      targetId: paymentId,
      meta: { orderId, amountPaise, stage: "capture", permanent, source: "edge", reason: message.slice(0, 180) },
    });
    if (!permanent) {
      console.error("[payments] capture could not be recorded:", message);
      return retryable("capture_error");
    }
    return done("capture_rejected");
  }

  const capture = captureData as CaptureResult;

  if (capture.outcome === "captured") {
    await auditSystem("payment.captured", {
      targetType: "student",
      targetId: capture.student_id,
      hostelId: capture.hostel_id,
      meta: { orderId, paymentId, period: capture.period_month, amountPaise: capture.amount_paise, source: "edge" },
    });
  }

  // Step 2 — put it on the fee ledger, in its own transaction.
  //
  // Separate on purpose. rz_credit_fee() calls the warden's own wd_record_payment() with every
  // one of its guards intact, and one of those guards (§4.4, hostel writable) can legitimately
  // refuse. If that happened inside the capture transaction, the refusal would roll back the
  // record that Razorpay took the money — the app would forget a real payment because a
  // subscription lapsed. Split, the money stays recorded and only the credit is outstanding,
  // which is a reconcilable state rather than a lost one.
  //
  // Attempted on a DUPLICATE delivery too: if an earlier delivery recorded the capture but the
  // credit failed, this is what repairs it.
  const { data: creditData, error: creditError } = await db.rpc("rz_credit_fee", {
    p_intent_id: capture.intent_id,
  });

  if (creditError) {
    // The money is recorded and will not be recorded twice. Only the ledger entry is missing,
    // and the row is now in the reconciliation queue (docs/payments.md §7).
    console.error("[payments] captured but not credited:", creditError.message);
    await auditSystem("payment.reconcile.required", {
      targetType: "student",
      targetId: capture.student_id,
      hostelId: capture.hostel_id,
      meta: { orderId, paymentId, stage: "credit", source: "edge", reason: (creditError.message ?? "").slice(0, 180) },
    });
    // Retryable: a later delivery re-enters at rz_record_capture, gets 'duplicate', and tries
    // the credit again. If the tenant renews, it heals by itself.
    return retryable("credit_error");
  }

  const credit = creditData as { outcome: string; amount?: number; fee_status?: string };
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
        source: "edge",
      },
    });
  }
  return done(credit.outcome);
});
