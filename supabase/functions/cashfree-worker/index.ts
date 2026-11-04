/**
 * POST /functions/v1/cashfree-worker — called every minute by pg_cron (app.cashfree_tick()).
 *
 * Each tick does a bounded amount of idempotent, server-verified work:
 *   1. SPLIT AFTER PAYMENT for payments that succeeded at least 150 s ago (Cashfree asks for two
 *      minutes), giving the owner's vendor everything paid less anything refunded, with the
 *      payment's own idempotency key so a retry can never split twice.
 *   2. RECONCILIATION of orders still open after three minutes: a webhook that never arrived is
 *      caught here by reading the order back from Cashfree.
 *   3. VENDOR STATUS for owners whose Cashfree vendor is still being verified.
 *   4. SETTLEMENT RECON for split payments: which settlement carries them, and its outcome.
 *   5. REFUND STATUS for refunds Cashfree has not finished.
 *
 * It reads no input that matters, so the anon key pg_cron sends is enough: a stranger calling it
 * only makes due work happen sooner, and a per-minute budget keeps even that small.
 *
 * DEPLOY: supabase functions deploy cashfree-worker   (verify_jwt ON; the anon key passes it)
 */
import { serviceClient } from "../_shared/supabase.ts";
import { consumeRateLimit } from "../_shared/ratelimit.ts";
import { jsonResponse } from "../_shared/http.ts";
import {
  CashfreeApiError,
  cashfreeConfig,
  getRefund,
  getSplitRecon,
  getVendor,
  splitAfterPayment,
  splitIsRetryable,
} from "../_shared/cashfree.ts";
import { reconcileOrder } from "../_shared/cashfree_rent.ts";

const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return jsonResponse({ ok: false }, 405);
  const cfg = cashfreeConfig();
  if (!cfg) return jsonResponse({ ok: true, skipped: "not_configured" }, 200);
  const wait = await consumeRateLimit("cfworker:tick", { max: 6, windowSeconds: 60 }, { unavailableMessage: "busy" })
    .catch(() => 0);
  if (wait > 0) return jsonResponse({ ok: true, skipped: "rate_limited" }, 200);

  const db = serviceClient();
  const report = { split: 0, splitRetry: 0, splitFailed: 0, reconciled: 0, vendors: 0, settlements: 0, refunds: 0, errors: 0 };
  const note = (where: string, e: unknown) => {
    report.errors++;
    console.error(`[cashfree-worker] ${where}:`, e instanceof Error ? e.message : String(e));
  };

  // ── 1. Split After Payment ──────────────────────────────────────────────────────────────
  const { data: due, error: dueError } = await db.rpc("svc_cf_split_claim", { p_limit: 20 });
  if (dueError) note("split claim", dueError.message);
  for (const s of (due ?? []) as Array<{ payment_id: string; order_id: string; vendor_id: string; amount_paise: number; idempotency_key: string }>) {
    try {
      if (s.amount_paise < 100) {
        await db.rpc("svc_cf_split_result", { p_payment_id: s.payment_id, p_outcome: "nothing", p_response: null, p_error: "Refunded before the split" });
        continue;
      }
      const res = await splitAfterPayment(cfg, s.order_id, s.vendor_id, s.amount_paise, s.idempotency_key);
      await db.rpc("svc_cf_split_result", { p_payment_id: s.payment_id, p_outcome: "created", p_response: res, p_error: null });
      report.split++;
    } catch (e) {
      if (e instanceof CashfreeApiError) {
        let outcome = splitIsRetryable(e) ? "retry" : "failed";
        if (e.status === 409 || /already processed/i.test(e.message)) {
          // "Already processed" after a lost answer: believe it only if the recon shows our vendor.
          try {
            const recon = await getSplitRecon(cfg, s.order_id);
            outcome = (recon.vendors ?? []).some((v) => v.vendor_id === s.vendor_id) ? "created" : "failed";
          } catch {
            outcome = "retry";
          }
        }
        await db.rpc("svc_cf_split_result", { p_payment_id: s.payment_id, p_outcome: outcome, p_response: e.body ?? null, p_error: e.message });
        if (outcome === "retry") report.splitRetry++;
        else if (outcome === "failed") report.splitFailed++;
        else report.split++;
      } else {
        note(`split ${s.order_id}`, e);
        await db.rpc("svc_cf_split_result", { p_payment_id: s.payment_id, p_outcome: "retry", p_response: null, p_error: String(e).slice(0, 300) });
      }
    }
  }

  // ── 2. Orders still open: catch a missed webhook ────────────────────────────────────────
  const { data: open } = await db.from("rent_payments").select("cashfree_order_id")
    .is("closed_at", null).lt("created_at", ago(3 * 60 * 1000))
    .or(`last_reconciled_at.is.null,last_reconciled_at.lt.${ago(5 * 60 * 1000)}`)
    .order("created_at", { ascending: true }).limit(15);
  for (const o of (open ?? []) as Array<{ cashfree_order_id: string }>) {
    try {
      await reconcileOrder(cfg, db, o.cashfree_order_id);
      report.reconciled++;
    } catch (e) {
      note(`reconcile ${o.cashfree_order_id}`, e);
    } finally {
      await db.from("rent_payments").update({ last_reconciled_at: new Date().toISOString() })
        .eq("cashfree_order_id", o.cashfree_order_id);
    }
  }

  // ── 3. Vendors still being verified ─────────────────────────────────────────────────────
  const { data: pending } = await db.from("owner_payment_accounts").select("cashfree_vendor_id")
    .eq("verification_status", "pending")
    .or(`last_checked_at.is.null,last_checked_at.lt.${ago(5 * 60 * 1000)}`).limit(10);
  for (const v of (pending ?? []) as Array<{ cashfree_vendor_id: string }>) {
    try {
      const vendor = await getVendor(cfg, v.cashfree_vendor_id);
      await db.rpc("svc_cf_vendor_status", { p_vendor_id: v.cashfree_vendor_id, p_vendor_status: vendor.status ?? null, p_response: vendor, p_error: null });
      report.vendors++;
    } catch (e) {
      await db.rpc("svc_cf_vendor_status", {
        p_vendor_id: v.cashfree_vendor_id,
        p_vendor_status: null,
        p_response: null,
        p_error: e instanceof Error ? e.message : String(e),
      });
      note(`vendor ${v.cashfree_vendor_id}`, e);
    }
  }

  // ── 4. Settlement recon for split payments ──────────────────────────────────────────────
  const { data: unsettled } = await db.from("rent_payments").select("cashfree_order_id, cashfree_vendor_id")
    .in("settlement_status", ["SPLIT_CREATED", "SETTLEMENT_PENDING"])
    .or(`last_reconciled_at.is.null,last_reconciled_at.lt.${ago(30 * 60 * 1000)}`).limit(15);
  for (const p of (unsettled ?? []) as Array<{ cashfree_order_id: string; cashfree_vendor_id: string }>) {
    try {
      const recon = await getSplitRecon(cfg, p.cashfree_order_id);
      const mine = (recon.vendors ?? []).filter((v) => v.vendor_id === p.cashfree_vendor_id);
      for (const v of mine.length ? mine : [{ vendor_id: p.cashfree_vendor_id, settlement_id: null }]) {
        await db.rpc("svc_cf_link_settlement", {
          p_order_id: p.cashfree_order_id,
          p_vendor_id: p.cashfree_vendor_id,
          p_settlement_id: v.settlement_id == null ? null : String(v.settlement_id),
          p_amount: (v as { settlement_amount?: number }).settlement_amount ?? null,
          p_eligibility: (v as { settlement_eligibility_date?: string | null }).settlement_eligibility_date ?? null,
        });
      }
      report.settlements++;
    } catch (e) {
      note(`settlement recon ${p.cashfree_order_id}`, e);
    }
  }

  // ── 5. Refunds Cashfree has not finished ────────────────────────────────────────────────
  const { data: refunds } = await db.from("rent_refunds")
    .select("refund_id, rent_payments!inner(cashfree_order_id)")
    .in("status", ["PENDING", "PENDING_APPROVAL", "ONHOLD"]).lt("updated_at", ago(10 * 60 * 1000)).limit(10);
  for (const r of (refunds ?? []) as unknown as Array<{ refund_id: string; rent_payments: { cashfree_order_id: string } }>) {
    try {
      const refund = await getRefund(cfg, r.rent_payments.cashfree_order_id, r.refund_id);
      await db.rpc("svc_cf_refund_result", {
        p_refund_id: r.refund_id,
        p_status: refund.refund_status ?? null,
        p_cf_refund_id: refund.cf_refund_id == null ? null : String(refund.cf_refund_id),
        p_response: refund,
        p_reason: refund.status_description ?? null,
      });
      report.refunds++;
    } catch (e) {
      note(`refund ${r.refund_id}`, e);
    }
  }

  return jsonResponse({ ok: true, ...report }, 200);
});
