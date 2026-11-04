/**
 * POST /functions/v1/cashfree-order
 *
 *   { "action": "create" }                 → a Cashfree order for exactly what the signed-in tenant
 *                                            owes this month: { order_id, payment_session_id, ... }
 *   { "action": "status", "order_id": … }  → that order's state, re-read from Cashfree first when
 *                                            it is still open (the screen after checkout polls this)
 *
 * ═══ NOTHING THE PHONE SENDS DECIDES MONEY ═══
 * There is no amount, tenant, owner, PG or vendor parameter. The tenant is the bearer token's
 * user; the month is today in Asia/Kolkata; the amount is their own outstanding balance; the
 * vendor is the CURRENT owner's verified Cashfree vendor. cf_reserve_payment derives all of that
 * again inside the database and refuses to reserve the order if this function disagrees.
 *
 * ═══ AND NOTHING THE PHONE SAYS MARKS IT PAID ═══
 * The SDK's "verify payment" callback only makes the app ask `status`; `status` re-reads the
 * order from Cashfree's API and applies it through the same database function the webhook uses.
 *
 * DEPLOY: supabase functions deploy cashfree-order   (verify_jwt stays ON; auth.getUser below is
 * the real authorisation).
 */
import { callerClient, serviceClient } from "../_shared/supabase.ts";
import { dbError } from "../_shared/errors.ts";
import { LIMITS, consumeRateLimit, throttled } from "../_shared/ratelimit.ts";
import { HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import {
  CF_NOT_CONFIGURED,
  CashfreeApiError,
  cashfreeConfig,
  createOrder,
  newOrderId,
  tenDigitPhone,
} from "../_shared/cashfree.ts";
import { reconcileOrder, webhookUrl } from "../_shared/cashfree_rent.ts";

const ORDER_LIFETIME_MS = 30 * 60 * 1000;
const ORDER_ID = /^apv_[A-Za-z0-9_]{6,45}$/;

function currentPeriodMonth(): string {
  return new Date().toLocaleDateString("en-CA", { timeZone: "Asia/Kolkata" }).slice(0, 7);
}

/** What is owed this month, in paise — the same arithmetic as razorpay-order and the database. */
function outstandingPaise(fee: { amount_due: unknown; amount_paid: unknown } | null, monthlyFee: number): number {
  const due = fee == null || fee.amount_due == null ? monthlyFee : Number(fee.amount_due);
  const paid = fee == null ? 0 : Number(fee.amount_paid ?? 0) || 0;
  if (!Number.isFinite(due) || due <= 0) return 0;
  return Math.round(Math.max(0, due - paid) * 100);
}

const STATUS_COLUMNS =
  "id, cashfree_order_id, period_month, amount_in_paise, payment_status, settlement_status, receipt_no, " +
  "failure_reason, payment_time, cashfree_payment_id, closed_at";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  try {
    if (req.method !== "POST") throw new HttpError(405, "Method not allowed.");
    const cfg = cashfreeConfig();
    if (!cfg) throw new HttpError(503, CF_NOT_CONFIGURED);

    const auth = req.headers.get("Authorization") ?? "";
    const jwt = auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
    if (!jwt) throw new HttpError(401, "Please sign in again.");
    const caller = callerClient(jwt);
    const { data: userData, error: userError } = await caller.auth.getUser(jwt);
    const user = userData?.user ?? null;
    if (userError || !user) throw new HttpError(401, "Please sign in again.");

    const body = await readJsonBody(req, 4 * 1024);
    const action = typeof body.action === "string" ? body.action : "create";

    // ── status: re-read from Cashfree, never from the phone ──────────────────────────────
    if (action === "status") {
      const orderId = typeof body.order_id === "string" ? body.order_id : "";
      if (!ORDER_ID.test(orderId)) throw new HttpError(400, "Invalid order.");
      // Under the caller's own RLS: a tenant can only ask about their own order.
      const { data: row, error } = await caller.from("rent_payments").select(STATUS_COLUMNS)
        .eq("cashfree_order_id", orderId).maybeSingle();
      if (error) throw dbError(error);
      if (!row) throw new HttpError(404, "Payment not found.");
      const r = row as unknown as Record<string, unknown>;
      if (r.payment_status !== "SUCCESS" && r.payment_status !== "REFUNDED" && r.closed_at == null) {
        try {
          await reconcileOrder(cfg, serviceClient(), orderId);
        } catch (e) {
          console.error("[cashfree-order] status reconcile:", e instanceof Error ? e.message : String(e));
        }
      }
      const { data: fresh, error: freshError } = await caller.from("rent_payments").select(STATUS_COLUMNS)
        .eq("cashfree_order_id", orderId).maybeSingle();
      if (freshError) throw dbError(freshError);
      return ok(fresh);
    }

    if (action !== "create") throw new HttpError(400, "Unknown action.");

    // ── create ───────────────────────────────────────────────────────────────────────────
    const { data: gateway, error: gatewayError } = await caller.rpc("st_rent_gateway");
    if (gatewayError) throw dbError(gatewayError);
    const g = gateway as { gateway?: string; ready?: boolean; message?: string } | null;
    if (g?.gateway === "razorpay") {
      throw new HttpError(409, "Your PG takes rent through its other payment option.", { extra: { code: "use_razorpay" } });
    }
    if (!g?.ready) throw new HttpError(409, g?.message ?? CF_NOT_CONFIGURED, { extra: { code: "not_ready" } });

    const { data: student, error: studentError } = await caller.from("students")
      .select("id, monthly_fee").eq("user_id", user.id).neq("status", "vacated").maybeSingle();
    if (studentError) throw dbError(studentError);
    if (!student) throw new HttpError(404, "Your student record could not be found. Contact your warden.");
    const period = currentPeriodMonth();
    const { data: fee, error: feeError } = await caller.from("fee_payments")
      .select("amount_due, amount_paid").eq("student_id", student.id).eq("period_month", period).maybeSingle();
    if (feeError) throw dbError(feeError);
    const amountPaise = outstandingPaise(fee, Number(student.monthly_fee) || 0);
    if (amountPaise < 100) throw new HttpError(409, "Your rent for this month is already settled.");

    const wait = await consumeRateLimit(`cforder:${user.id}`, LIMITS.paymentOrderPerUser, {
      unavailableMessage: "Online payment is briefly unavailable. Please try again in a minute.",
    });
    if (wait > 0) throw throttled("You have started several payments in the last hour. Try again shortly.", wait);

    const reserve = async () => {
      const orderId = newOrderId(period);
      const { data, error } = await caller.rpc("cf_reserve_payment", { p_order_id: orderId, p_amount_paise: amountPaise });
      if (error) throw dbError(error);
      return data as Record<string, unknown>;
    };

    let reserved = await reserve();
    if (reserved.outcome === "reconcile") {
      // An older order for this month may still be payable: settle what Cashfree says first.
      await reconcileOrder(cfg, serviceClient(), String(reserved.order_id));
      reserved = await reserve();
      if (reserved.outcome === "reconcile") {
        throw new HttpError(409, "Your last payment is still open. Finish it, or try again in a few minutes.");
      }
    }
    if (reserved.outcome === "reuse") {
      return ok({
        order_id: reserved.order_id,
        payment_session_id: reserved.payment_session_id,
        amount_paise: reserved.amount_paise,
        period_month: reserved.period_month,
        environment: cfg.environment,
      });
    }

    const orderId = String(reserved.order_id);
    const customer = (reserved.customer ?? {}) as Record<string, string | null>;
    const phone = tenDigitPhone(customer.phone);
    const db = serviceClient();
    if (!phone) {
      await db.rpc("svc_cf_abandon_order", { p_order_id: orderId, p_reason: "No valid phone on the tenant profile" });
      throw new HttpError(409, "Add a valid 10-digit mobile number to your profile, then try again.");
    }

    let created;
    try {
      created = await createOrder(cfg, {
        orderId,
        amountPaise,
        customer: { id: String(customer.id), phone, name: customer.name, email: customer.email },
        notifyUrl: webhookUrl(),
        expiresAt: new Date(Date.now() + ORDER_LIFETIME_MS),
        note: `Rent ${period}`,
        tags: { apv_period: period },
      });
    } catch (e) {
      await db.rpc("svc_cf_abandon_order", {
        p_order_id: orderId,
        p_reason: e instanceof CashfreeApiError ? `Cashfree: ${e.message}` : "Cashfree unreachable",
      });
      console.error("[cashfree-order] create:", e instanceof Error ? e.message : String(e));
      throw new HttpError(502, "Could not start the payment. Please try again.");
    }
    if (!created.payment_session_id) {
      await db.rpc("svc_cf_abandon_order", { p_order_id: orderId, p_reason: "No payment session in the answer" });
      throw new HttpError(502, "Could not start the payment. Please try again.");
    }

    const { error: attachError } = await db.rpc("svc_cf_attach_session", {
      p_order_id: orderId,
      p_cf_order_id: created.cf_order_id == null ? null : String(created.cf_order_id),
      p_session_id: created.payment_session_id,
      p_expires_at: created.order_expiry_time ?? new Date(Date.now() + ORDER_LIFETIME_MS).toISOString(),
    });
    if (attachError) throw dbError(attachError);

    return ok({
      order_id: orderId,
      payment_session_id: created.payment_session_id,
      amount_paise: amountPaise,
      period_month: period,
      hostel_name: reserved.hostel_name ?? null,
      environment: cfg.environment,
    });
  } catch (err) {
    return toResponse(err);
  }
});
