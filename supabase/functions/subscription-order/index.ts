/**
 * POST /functions/v1/subscription-order
 *
 * An OWNER pays for their PG's Apnivaas plan (docs/self-signup-onboarding-spec.md, Flow 8).
 * Two actions:
 *
 *   { "action": "create", "hostelId": "<uuid>", "planId": "monthly"|"quarterly"|"yearly" }
 *   { "action": "verify", "orderId": "order_…", "paymentId": "pay_…", "signature": "<hex>" }
 *
 * create: the caller must own the hostel (checked here AND again inside
 *   svc_open_subscription_order). The amount comes from public.platform_plans and nothing else;
 *   the client never sends one. The Razorpay order is created on the PLATFORM account with
 *   notes {purpose:'subscription', hostel_id, plan} and no transfers (this money is ours, unlike
 *   rent), then recorded as a subscription_payments row in status 'created'.
 * verify: after the checkout sheet reports success. The signature (HMAC of order_id|payment_id
 *   with the API secret) must verify, and Razorpay must confirm the payment is captured or
 *   authorized, for this order, for this amount. Only then does svc_activate_subscription_payment
 *   extend the plan. It is idempotent on the payment id, so the webhook (razorpay-webhook, the
 *   subscription branch) and this action can both arrive and the plan is extended once.
 *
 * SECRETS: RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET (the same platform account as razorpay-order).
 * Contract: docs/self-signup-api.md.
 */
import { audit } from "../_shared/audit.ts";
import { requireCaller } from "../_shared/caller.ts";
import { dbError } from "../_shared/errors.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { consumeRateLimit, LIMITS, throttled } from "../_shared/ratelimit.ts";
import {
  createOrder,
  fetchPayment,
  isConfigured,
  isLiveKey,
  keyId,
  ORDER_ID_RE,
  PAYMENT_ID_RE,
  RazorpayApiError,
  verifyCheckoutSignature,
} from "../_shared/razorpay.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { isReachableAddress } from "../_shared/verification.ts";

const MAX_BODY_BYTES = 4 * 1024;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PLAN_ID_RE = /^[a-z_]{3,20}$/;

export const PLAN_PAYMENTS_OFF = "Online plan payment isn't set up yet. Please try again later.";
export const PLAN_PAYMENTS_UNAVAILABLE = "Plan payment is temporarily unavailable. Please try again in a minute.";
export const NOT_CONFIRMED =
  "We could not confirm this payment. If money left your account, your plan will switch on automatically within a few minutes.";
export const STILL_PROCESSING =
  "Your payment is still processing. Your plan will switch on automatically once it completes.";

async function spend(key: string, limit: { max: number; windowSeconds: number }): Promise<void> {
  const wait = await consumeRateLimit(key, limit, { unavailableMessage: PLAN_PAYMENTS_UNAVAILABLE });
  if (wait > 0) {
    const minutes = Math.ceil(wait / 60);
    throw throttled(`Too many payment attempts. Please wait ${minutes} minute${minutes === 1 ? "" : "s"} and try again.`, wait);
  }
}

async function createSubscriptionOrder(req: Request, body: Record<string, unknown>): Promise<Response> {
  const caller = await requireCaller(req, "owner");
  const hostelId = typeof body["hostelId"] === "string" ? body["hostelId"] : "";
  const planId = typeof body["planId"] === "string" ? body["planId"] : "";
  if (!UUID_RE.test(hostelId)) throw new HttpError(400, "Hostel not found.");
  if (!PLAN_ID_RE.test(planId)) throw new HttpError(400, "Choose a plan.");
  if (!isConfigured()) throw new HttpError(503, PLAN_PAYMENTS_OFF, { extra: { code: "not_configured" } });

  // Spent before Razorpay is called, so looping this endpoint cannot mint orphaned orders.
  await spend(`suborder:${caller.id}`, LIMITS.subscriptionOrderPerUser);

  const db = serviceClient();
  const [{ data: hostel, error: hostelError }, { data: plan, error: planError }] = await Promise.all([
    db.from("hostels").select("id, name, status, owner_user_id").eq("id", hostelId).maybeSingle(),
    db.from("platform_plans").select("id, name, months, bonus_months, amount_paise").eq("id", planId).eq("active", true)
      .maybeSingle(),
  ]);
  if (hostelError || planError) {
    console.error("[payments] subscription lookup failed:", (hostelError ?? planError)?.message);
    throw new HttpError(503, PLAN_PAYMENTS_UNAVAILABLE);
  }
  // "Not yours" and "does not exist" read the same.
  if (!hostel || hostel.owner_user_id !== caller.id) throw new HttpError(404, "Hostel not found.");
  if (hostel.status === "suspended") throw new HttpError(403, "This hostel is suspended. Contact support.");
  if (!plan) throw new HttpError(400, "Choose a plan.");
  const amountPaise = Number(plan.amount_paise);

  let orderId: string;
  try {
    ({ id: orderId } = await createOrder({
      amountPaise,
      receipt: `sub_${plan.id}_${hostelId.slice(0, 8)}_${Date.now().toString(36)}`.slice(0, 40),
      notes: { purpose: "subscription", hostel_id: hostelId, plan: String(plan.id) },
      transferToAccount: null,
    }));
  } catch (e) {
    if (e instanceof RazorpayApiError) {
      console.error("[payments] subscription order refused:", e.message);
      throw new HttpError(503, PLAN_PAYMENTS_UNAVAILABLE);
    }
    throw e;
  }

  const { error: openError } = await db.rpc("svc_open_subscription_order", {
    p_actor: caller.id,
    p_hostel_id: hostelId,
    p_plan_id: plan.id,
    p_order_id: orderId,
    p_amount_paise: amountPaise,
  });
  if (openError) throw dbError(openError, PLAN_PAYMENTS_UNAVAILABLE);

  return ok({
    order_id: orderId,
    key_id: keyId(),
    amount_paise: amountPaise,
    amount_rupees: amountPaise / 100,
    currency: "INR",
    plan_id: plan.id,
    plan_name: plan.name,
    months: plan.months,
    bonus_months: plan.bonus_months,
    hostel_id: hostelId,
    hostel_name: hostel.name,
    test_mode: !isLiveKey(),
    prefill: {
      name: caller.fullName,
      email: isReachableAddress(caller.email) ? caller.email : null,
    },
  });
}

async function verifySubscriptionPayment(req: Request, body: Record<string, unknown>): Promise<Response> {
  const caller = await requireCaller(req, "owner");
  const orderId = typeof body["orderId"] === "string" ? body["orderId"] : "";
  const paymentId = typeof body["paymentId"] === "string" ? body["paymentId"] : "";
  if (!ORDER_ID_RE.test(orderId) || !PAYMENT_ID_RE.test(paymentId)) throw new HttpError(400, NOT_CONFIRMED);
  if (!isConfigured()) throw new HttpError(503, PLAN_PAYMENTS_OFF, { extra: { code: "not_configured" } });

  await spend(`subverify:${caller.id}`, LIMITS.subscriptionVerifyPerUser);

  const db = serviceClient();
  const { data: row, error } = await db
    .from("subscription_payments")
    .select("id, hostel_id, amount_paise, status, razorpay_payment_id, hostels!inner(owner_user_id)")
    .eq("razorpay_order_id", orderId)
    .maybeSingle();
  if (error) {
    console.error("[payments] subscription payment lookup failed:", error.message);
    throw new HttpError(503, PLAN_PAYMENTS_UNAVAILABLE);
  }
  const ownerId = (row as { hostels?: { owner_user_id?: string } } | null)?.hostels?.owner_user_id;
  if (!row || ownerId !== caller.id) throw new HttpError(404, "Payment not found.");

  if (!(await verifyCheckoutSignature(orderId, paymentId, body["signature"]))) {
    await audit("owner.subscription.verify_rejected", caller, {
      targetType: "subscription_payment",
      targetId: String(row.id),
      hostelId: String(row.hostel_id),
      meta: { reason: "bad_signature", orderId, surface: "edge_function" },
    });
    throw new HttpError(400, NOT_CONFIRMED);
  }

  let payment;
  try {
    payment = await fetchPayment(paymentId);
  } catch (e) {
    if (e instanceof RazorpayApiError && e.status === 400) throw new HttpError(400, NOT_CONFIRMED);
    console.error("[payments] could not fetch a subscription payment:", e instanceof Error ? e.message : String(e));
    throw new HttpError(503, PLAN_PAYMENTS_UNAVAILABLE);
  }
  if (payment.order_id !== orderId || payment.amount !== Number(row.amount_paise) || payment.currency !== "INR") {
    await audit("owner.subscription.verify_rejected", caller, {
      targetType: "subscription_payment",
      targetId: String(row.id),
      hostelId: String(row.hostel_id),
      meta: { reason: "payment_mismatch", orderId, paymentId, surface: "edge_function" },
    });
    throw new HttpError(400, NOT_CONFIRMED);
  }
  if (payment.status !== "captured" && payment.status !== "authorized") {
    throw new HttpError(409, payment.status === "failed" ? NOT_CONFIRMED : STILL_PROCESSING, {
      extra: { code: payment.status === "failed" ? "payment_failed" : "processing" },
    });
  }

  const { data, error: activateError } = await db.rpc("svc_activate_subscription_payment", {
    p_order_id: orderId,
    p_payment_id: paymentId,
    p_amount_paise: payment.amount,
    p_method: payment.method,
    p_via: "checkout",
  });
  if (activateError) throw dbError(activateError, PLAN_PAYMENTS_UNAVAILABLE);
  const result = (data ?? {}) as Record<string, unknown>;
  return ok({
    outcome: result["outcome"],
    hostel_id: result["hostel_id"],
    plan_id: result["plan_id"],
    period_start: result["period_start"],
    period_end: result["period_end"],
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);
  try {
    const body = await readJsonBody(req, MAX_BODY_BYTES);
    switch (body["action"]) {
      case "create":
        return await createSubscriptionOrder(req, body);
      case "verify":
        return await verifySubscriptionPayment(req, body);
      default:
        throw new HttpError(400, "Unknown action.");
    }
  } catch (err) {
    return toResponse(err);
  }
});
