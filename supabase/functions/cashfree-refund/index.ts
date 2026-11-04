/**
 * POST /functions/v1/cashfree-refund  { "payment_id": uuid, "amount_paise": int, "note"?: string }
 *
 * Refunds a tenant's Cashfree rent payment, in full or in part. Only that PG's owner or the
 * Super Admin may, with their second factor (requireCaller), and svc_cf_request_refund re-checks
 * the caller against the payment, refuses more than is left to refund, and allows one refund in
 * flight per payment. Once the owner's split exists, the refund carries refund_splits so the
 * amount comes back out of the owner's vendor share, not the platform's.
 *
 * The rent ledger is reversed only when Cashfree reports the refund SUCCESS (here, or later via
 * REFUND_STATUS_WEBHOOK / the worker), never on the request alone.
 *
 * DEPLOY: supabase functions deploy cashfree-refund   (verify_jwt ON)
 */
import { requireCaller } from "../_shared/caller.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { dbError } from "../_shared/errors.ts";
import { audit } from "../_shared/audit.ts";
import { consumeRateLimit, throttled } from "../_shared/ratelimit.ts";
import { HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { CashfreeApiError, cashfreeConfig, createRefund, newRefundId } from "../_shared/cashfree.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  try {
    if (req.method !== "POST") throw new HttpError(405, "Method not allowed.");
    const caller = await requireCaller(req, "owner", "super_admin");
    const cfg = cashfreeConfig();
    if (!cfg) throw new HttpError(503, "Cashfree is not connected yet. Please try again later.");

    const body = await readJsonBody(req, 4 * 1024);
    const paymentId = typeof body.payment_id === "string" ? body.payment_id : "";
    const amountPaise = typeof body.amount_paise === "number" ? Math.round(body.amount_paise) : NaN;
    const note = typeof body.note === "string" ? body.note.trim().slice(0, 100) : null;
    if (!UUID.test(paymentId)) throw new HttpError(400, "Invalid payment.");
    if (!Number.isFinite(amountPaise) || amountPaise < 100) throw new HttpError(400, "A refund must be at least ₹1.");

    const wait = await consumeRateLimit(`cfrefund:${caller.id}`, { max: 20, windowSeconds: 3600 }, {
      unavailableMessage: "Please try again in a minute.",
    });
    if (wait > 0) throw throttled("Too many refunds in the last hour. Please try again later.", wait);

    const db = serviceClient();
    const refundId = newRefundId();
    const { data, error } = await db.rpc("svc_cf_request_refund", {
      p_payment_id: paymentId,
      p_actor: caller.id,
      p_amount_paise: amountPaise,
      p_note: note,
      p_refund_id: refundId,
    });
    if (error) throw dbError(error);
    const r = data as { order_id: string; vendor_id: string; split_status: string };

    let refund;
    try {
      refund = await createRefund(
        cfg,
        r.order_id,
        refundId,
        amountPaise,
        note,
        r.split_status === "CREATED" ? { vendorId: r.vendor_id, amountPaise } : null,
      );
    } catch (e) {
      const message = e instanceof CashfreeApiError ? e.message : "Cashfree did not answer.";
      await db.rpc("svc_cf_refund_result", {
        p_refund_id: refundId,
        p_status: "FAILED",
        p_cf_refund_id: null,
        p_response: e instanceof CashfreeApiError ? e.body : null,
        p_reason: message,
      });
      throw new HttpError(e instanceof CashfreeApiError && e.status < 500 ? 400 : 502, `Cashfree could not start the refund: ${message}`);
    }

    const { data: result, error: resultError } = await db.rpc("svc_cf_refund_result", {
      p_refund_id: refundId,
      p_status: refund.refund_status ?? "PENDING",
      p_cf_refund_id: refund.cf_refund_id == null ? null : String(refund.cf_refund_id),
      p_response: refund,
      p_reason: refund.status_description ?? null,
    });
    if (resultError) throw dbError(resultError);

    await audit("payment.cashfree.refund_sent", caller, {
      targetType: "rent_payment",
      targetId: paymentId,
      meta: { refund_id: refundId, amount_paise: amountPaise, status: refund.refund_status ?? null },
    });
    return ok({ refund_id: refundId, status: refund.refund_status ?? "PENDING", outcome: (result as { outcome?: string })?.outcome });
  } catch (err) {
    return toResponse(err);
  }
});
