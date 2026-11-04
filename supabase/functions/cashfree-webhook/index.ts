/**
 * POST /functions/v1/cashfree-webhook — Cashfree's server-to-server notifications.
 *
 *   PAYMENT_SUCCESS_WEBHOOK / PAYMENT_FAILED_WEBHOOK / PAYMENT_USER_DROPPED_WEBHOOK
 *   REFUND_STATUS_WEBHOOK (and AUTO_REFUND_STATUS_WEBHOOK, recorded, not acted on)
 *   VENDOR_SETTLEMENT_INITIATED / _SUCCESS / _FAILED / _REVERSED
 *
 * ═══ THE ORDER OF OPERATIONS IS THE SECURITY ═══
 *   1. The signature is checked over the RAW body (Base64(HMAC-SHA256(timestamp + body, client
 *      secret))) before the body is parsed. A bad or missing signature is a 401 and nothing else.
 *   2. The event is recorded once (payment_webhook_events, unique on Cashfree's idempotency
 *      header, else the body's hash): an at-least-once redelivery is acknowledged and skipped.
 *   3. A payment or refund event is NOT believed: the order (or refund) is read back from
 *      Cashfree's API, and only that answer reaches the database, which checks the order status,
 *      currency and exact amount again. A settlement event is signed and carries no money of
 *      ours to credit, so it is applied as received.
 *   Any failure answers 500, so Cashfree retries; the ledger turns the retry into "retry", not a
 *   duplicate.
 *
 * DEPLOY: supabase functions deploy cashfree-webhook --no-verify-jwt   (Cashfree sends no JWT;
 * the signature is the authentication). URL to register in Cashfree → Developers → Webhooks:
 * https://<project>.supabase.co/functions/v1/cashfree-webhook
 */
import { serviceClient } from "../_shared/supabase.ts";
import { jsonResponse } from "../_shared/http.ts";
import { cashfreeConfig, getRefund, sha256Hex, verifySignature } from "../_shared/cashfree.ts";
import { reconcileOrder } from "../_shared/cashfree_rent.ts";

const MAX_BODY = 256 * 1024;

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : typeof v === "number" ? String(v) : null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return jsonResponse({ ok: false }, 405);
  const cfg = cashfreeConfig();
  // Not configured: 503, so Cashfree keeps the event and retries once the keys are in.
  if (!cfg) return jsonResponse({ ok: false, error: "not configured" }, 503);

  const raw = await req.text();
  if (raw.length > MAX_BODY) return jsonResponse({ ok: false }, 413);
  const valid = await verifySignature(
    raw,
    req.headers.get("x-webhook-timestamp"),
    req.headers.get("x-webhook-signature"),
    cfg.secret,
  );
  if (!valid) {
    console.warn("[cashfree-webhook] rejected: bad signature");
    return jsonResponse({ ok: false, error: "invalid signature" }, 401);
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(raw);
  } catch {
    return jsonResponse({ ok: false, error: "bad json" }, 400);
  }
  const type = str(event.type) ?? "UNKNOWN";
  const data = (event.data ?? {}) as Record<string, Record<string, unknown>>;
  const orderId = str(data.order?.order_id) ?? str(data.refund?.order_id);

  const hash = await sha256Hex(raw);
  const eventId = req.headers.get("x-idempotency-key") ?? req.headers.get("x-idempotency-header") ?? `sha256:${hash}`;
  const db = serviceClient();
  const { data: begun, error: beginError } = await db.rpc("svc_cf_webhook_begin", {
    p_event_id: eventId.slice(0, 200),
    p_type: type,
    p_order_id: orderId,
    p_hash: hash,
  });
  if (beginError) {
    console.error("[cashfree-webhook] ledger:", beginError.message);
    return jsonResponse({ ok: false }, 500);
  }
  const ledger = begun as { outcome: string; id: string };
  if (ledger.outcome === "duplicate") return jsonResponse({ ok: true, duplicate: true }, 200);

  let status: "processed" | "ignored" = "ignored";
  try {
    if (type.startsWith("PAYMENT_") && type !== "PAYMENT_CHARGES_WEBHOOK") {
      if (orderId && orderId.startsWith("apv_")) {
        await reconcileOrder(cfg, db, orderId);
        status = "processed";
      }
    } else if (type === "REFUND_STATUS_WEBHOOK") {
      const refundId = str(data.refund?.refund_id);
      if (orderId && refundId && refundId.startsWith("apvr_")) {
        // Read the refund back rather than trusting the body.
        const refund = await getRefund(cfg, orderId, refundId);
        const { error } = await db.rpc("svc_cf_refund_result", {
          p_refund_id: refundId,
          p_status: refund.refund_status ?? null,
          p_cf_refund_id: refund.cf_refund_id == null ? null : String(refund.cf_refund_id),
          p_response: refund,
          p_reason: refund.status_description ?? null,
        });
        if (error) throw new Error(`refund ${refundId}: ${error.message}`);
        status = "processed";
      }
    } else if (type.startsWith("VENDOR_SETTLEMENT_")) {
      const s = (data.settlement ?? {}) as Record<string, unknown>;
      const vendorId = str(s.vendor_id);
      const settlementId = str(s.settlement_id);
      if (vendorId && settlementId && vendorId.startsWith("apvo_")) {
        const settledOn = str(s.settled_on);
        const { error } = await db.rpc("svc_cf_settlement_event", {
          p_vendor_id: vendorId,
          p_settlement_id: settlementId,
          p_status: str(s.status) ?? type.replace("VENDOR_SETTLEMENT_", ""),
          p_amount: typeof s.settlement_amount === "number" ? s.settlement_amount : null,
          p_utr: str(s.utr),
          p_reason: str(s.reason),
          p_settled_on: settledOn && settledOn !== "null" ? settledOn : null,
          p_raw: s,
        });
        if (error) throw new Error(`settlement ${settlementId}: ${error.message}`);
        status = "processed";
      }
    }
    await db.rpc("svc_cf_webhook_end", { p_id: ledger.id, p_status: status, p_error: null });
    return jsonResponse({ ok: true }, 200);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error("[cashfree-webhook] failed:", type, message);
    await db.rpc("svc_cf_webhook_end", { p_id: ledger.id, p_status: "failed", p_error: message });
    return jsonResponse({ ok: false }, 500);
  }
});
