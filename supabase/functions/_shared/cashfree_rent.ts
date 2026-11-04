/**
 * The one way a rent payment's state changes: read the order and its payments back from
 * Cashfree's API, then hand that answer to the database (svc_cf_apply_payment), which checks the
 * order status, currency and exact amount itself. Webhooks, the order-status poll and the worker
 * all come through here, so a frontend callback, a redirect or a forged webhook body can never
 * mark rent paid.
 */
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  CashfreeApiError,
  type CashfreeConfig,
  decisivePayment,
  getOrder,
  getOrderPayments,
  rupeesToPaise,
} from "./cashfree.ts";
import { projectUrl } from "./supabase.ts";

export const WEBHOOK_PATH = "/functions/v1/cashfree-webhook";

export function webhookUrl(): string {
  return `${projectUrl().replace(/\/+$/, "")}${WEBHOOK_PATH}`;
}

export type ReconcileOutcome =
  | "success"
  | "already"
  | "failed"
  | "cancelled"
  | "pending"
  | "unchanged"
  | "ignored"
  | "closed"
  | "not_found";

/** Brings one apv_ order in line with Cashfree. Throws on an API or database failure. */
export async function reconcileOrder(cfg: CashfreeConfig, db: SupabaseClient, orderId: string): Promise<ReconcileOutcome> {
  let order;
  try {
    order = await getOrder(cfg, orderId);
  } catch (e) {
    if (e instanceof CashfreeApiError && e.status === 404) {
      // Cashfree never created it (the create call failed after the row was reserved).
      const { error } = await db.rpc("svc_cf_abandon_order", { p_order_id: orderId, p_reason: "Order not found at Cashfree" });
      if (error) throw new Error(`abandon ${orderId}: ${error.message}`);
      return "not_found";
    }
    throw e;
  }
  const payments = await getOrderPayments(cfg, orderId);
  const p = decisivePayment(payments);

  let outcome: ReconcileOutcome = "unchanged";
  if (p) {
    const { data, error } = await db.rpc("svc_cf_apply_payment", {
      p_order_id: orderId,
      p_order_status: order.order_status ?? null,
      p_cf_payment_id: p.cf_payment_id == null ? null : String(p.cf_payment_id),
      p_payment_status: p.payment_status ?? null,
      p_amount_paise: rupeesToPaise(p.payment_amount ?? null),
      p_currency: p.payment_currency ?? null,
      p_method: p.payment_group === "upi" ? "upi" : (p.payment_group ?? null),
      p_bank_reference: p.bank_reference ?? null,
      p_payment_time: p.payment_completion_time ?? p.payment_time ?? null,
      p_message: p.payment_message ?? null,
    });
    if (error) throw new Error(`apply ${orderId}: ${error.message}`);
    outcome = ((data as { outcome?: string } | null)?.outcome ?? "unchanged") as ReconcileOutcome;
  }

  // An order that can no longer be paid, without a success, frees the tenant to start again.
  if (outcome !== "success" && outcome !== "already" && (order.order_status === "EXPIRED" || order.order_status === "TERMINATED")) {
    const { error } = await db.rpc("svc_cf_close_unpaid", { p_order_id: orderId, p_order_status: order.order_status });
    if (error) throw new Error(`close ${orderId}: ${error.message}`);
    return "closed";
  }
  return outcome;
}
