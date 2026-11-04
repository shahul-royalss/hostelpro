// deno test supabase/functions/_shared/cashfree_test.ts
// Pure tests for the Cashfree module: no network, no secrets. Cashfree's HTTP answers are
// injected through the `fetcher` argument, shaped exactly as the API reference documents them.
import { assert, assertEquals, assertFalse, assertRejects } from "jsr:@std/assert@1";
import {
  CashfreeApiError,
  type CashfreeConfig,
  cashfreeConfig,
  createOrder,
  createRefund,
  decisivePayment,
  istIso,
  newOrderId,
  newRefundId,
  paiseToRupees,
  rupeesToPaise,
  splitAfterPayment,
  splitIsRetryable,
  tenDigitPhone,
  validateVendorInput,
  vendorIdFor,
  verifySignature,
} from "./cashfree.ts";

const CFG: CashfreeConfig = {
  appId: "TEST_APP",
  secret: "TEST_SECRET",
  apiVersion: "2025-01-01",
  baseUrl: "https://sandbox.cashfree.com/pg",
  environment: "sandbox",
};

async function sign(timestamp: string, body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp + body));
  return btoa(String.fromCharCode(...new Uint8Array(mac)));
}

Deno.test("config: missing keys fail closed; environment picks the host", () => {
  assertEquals(cashfreeConfig(() => undefined), null);
  const sandbox = cashfreeConfig((k) => ({ CASHFREE_APP_ID: "a", CASHFREE_SECRET_KEY: "s" } as Record<string, string>)[k]);
  assertEquals(sandbox?.baseUrl, "https://sandbox.cashfree.com/pg");
  const prod = cashfreeConfig((k) => ({ CASHFREE_APP_ID: "a", CASHFREE_SECRET_KEY: "s", CASHFREE_ENVIRONMENT: "production" } as Record<string, string>)[k]);
  assertEquals(prod?.baseUrl, "https://api.cashfree.com/pg");
  // A sandbox host in production mode is refused rather than half-working.
  const mixed = cashfreeConfig((k) => ({
    CASHFREE_APP_ID: "a", CASHFREE_SECRET_KEY: "s", CASHFREE_ENVIRONMENT: "production",
    CASHFREE_BASE_URL: "https://sandbox.cashfree.com/pg",
  } as Record<string, string>)[k]);
  assertEquals(mixed, null);
});

Deno.test("webhook signature: valid, tampered, wrong secret, missing headers", async () => {
  const body = '{"type":"PAYMENT_SUCCESS_WEBHOOK","data":{"order":{"order_id":"apv_2611_x"}}}';
  const ts = "1617695238078";
  const sig = await sign(ts, body, CFG.secret);
  assert(await verifySignature(body, ts, sig, CFG.secret));
  assertFalse(await verifySignature(body.replace("SUCCESS", "FAILED"), ts, sig, CFG.secret));
  assertFalse(await verifySignature(body, "1617695238079", sig, CFG.secret));
  assertFalse(await verifySignature(body, ts, sig, "OTHER_SECRET"));
  assertFalse(await verifySignature(body, null, sig, CFG.secret));
  assertFalse(await verifySignature(body, ts, null, CFG.secret));
});

Deno.test("money: paise and rupees", () => {
  assertEquals(paiseToRupees(500000), 5000);
  assertEquals(paiseToRupees(1015), 10.15);
  assertEquals(rupeesToPaise(10.15), 1015);
  assertEquals(rupeesToPaise("4999.99"), 499999);
  assert(Number.isNaN(rupeesToPaise(null)));
});

Deno.test("identifiers match the database checks", () => {
  const order = newOrderId("2026-11");
  assert(/^apv_[A-Za-z0-9_]{6,45}$/.test(order), order);
  assert(order.startsWith("apv_2611_"));
  assert(/^apvr_[A-Za-z0-9_]{6,45}$/.test(newRefundId()));
  assertEquals(vendorIdFor("1312e8e1-5216-4eac-b4a6-e276aeeddd1f"), "apvo_1312e8e152164eacb4a6e276aeeddd1f");
  assert(/^[A-Za-z0-9_]{3,50}$/.test(vendorIdFor("1312e8e1-5216-4eac-b4a6-e276aeeddd1f")));
});

Deno.test("phone and expiry formats", () => {
  assertEquals(tenDigitPhone("+91 98765 43210"), "9876543210");
  assertEquals(tenDigitPhone("09876543210"), "9876543210");
  assertEquals(tenDigitPhone("12345"), null);
  assertEquals(istIso(new Date("2026-11-04T10:00:00.000Z")), "2026-11-04T15:30:00+05:30");
});

Deno.test("vendor input: a valid owner, and each refusal", () => {
  const good = validateVendorInput({
    legal_name: "Rukesh A", email: "Owner@Example.com", phone: "+91 98765 43210", upi_vpa: "rukesh@okhdfcbank",
    pan: "abcde1234f",
  });
  assertEquals(good.value?.pan, "ABCDE1234F");
  assertEquals(good.value?.email, "owner@example.com");
  assertEquals(good.value?.beneficiaryName, "Rukesh A");
  assertEquals(good.value?.gstin, null);
  const bad = validateVendorInput({
    legal_name: "R@kesh!", email: "nope", phone: "123", upi_vpa: "no-at-sign", pan: "ABC123", gstin: "XYZ",
  });
  assertEquals(Object.keys(bad.errors ?? {}).sort(), ["beneficiary_name", "email", "gstin", "legal_name", "pan", "phone", "upi_vpa"]);
  // A hyphen is allowed only before the @ (Cashfree's VPA rule).
  assert(validateVendorInput({ legal_name: "A B", email: "a@b.co", phone: "9876543210", upi_vpa: "a-b@ok-bank", pan: "ABCDE1234F" }).errors?.upi_vpa);
  assert(validateVendorInput({ legal_name: "A B", email: "a@b.co", phone: "9876543210", upi_vpa: "a-b@okbank", pan: "ABCDE1234F" }).value);
});

Deno.test("the decisive payment: a success wins, else the latest attempt", () => {
  assertEquals(decisivePayment([]), null);
  assertEquals(decisivePayment([{ payment_status: "NOT_ATTEMPTED" }]), null);
  const p = decisivePayment([
    { cf_payment_id: 1, payment_status: "FAILED", payment_time: "2026-11-04T10:00:00+05:30" },
    { cf_payment_id: 2, payment_status: "SUCCESS", payment_time: "2026-11-04T09:00:00+05:30" },
    { cf_payment_id: 3, payment_status: "USER_DROPPED", payment_time: "2026-11-04T11:00:00+05:30" },
  ]);
  assertEquals(p?.cf_payment_id, 2);
  const latest = decisivePayment([
    { cf_payment_id: 1, payment_status: "FAILED", payment_time: "2026-11-04T10:00:00+05:30" },
    { cf_payment_id: 3, payment_status: "PENDING", payment_time: "2026-11-04T11:00:00+05:30" },
  ]);
  assertEquals(latest?.cf_payment_id, 3);
});

Deno.test("create order sends the documented request, UPI only, with an idempotency key", async () => {
  let seen: { url: string; init: RequestInit } | null = null;
  const order = await createOrder(CFG, {
    orderId: "apv_2611_abc123", amountPaise: 500000,
    customer: { id: "c0ffee", phone: "9876543210", name: "Tenant", email: "t@example.com" },
    notifyUrl: "https://x.supabase.co/functions/v1/cashfree-webhook", expiresAt: new Date("2026-11-04T10:00:00Z"),
    note: "Rent 2026-11", tags: { apv_period: "2026-11" },
  }, (url, init) => {
    seen = { url, init };
    return Promise.resolve(new Response(JSON.stringify({ order_id: "apv_2611_abc123", payment_session_id: "session_x", order_status: "ACTIVE" }), { status: 200 }));
  });
  assertEquals(order.payment_session_id, "session_x");
  const s = seen as unknown as { url: string; init: RequestInit };
  assertEquals(s.url, "https://sandbox.cashfree.com/pg/orders");
  const h = s.init.headers as Record<string, string>;
  assertEquals(h["x-client-id"], "TEST_APP");
  assertEquals(h["x-api-version"], "2025-01-01");
  assert(h["x-idempotency-key"]);
  const sent = JSON.parse(String(s.init.body));
  assertEquals(sent.order_amount, 5000);
  assertEquals(sent.order_currency, "INR");
  assertEquals(sent.order_meta.payment_methods, "upi");
  assertEquals(sent.customer_details.customer_phone, "9876543210");
});

Deno.test("split after payment: amount to the owner's vendor, idempotent, disable_split", async () => {
  let body: Record<string, unknown> = {};
  let key = "";
  await splitAfterPayment(CFG, "apv_2611_abc123", "apvo_x", 450000, "11111111-1111-4111-8111-111111111111", (url, init) => {
    assertEquals(url, "https://sandbox.cashfree.com/pg/easy-split/orders/apv_2611_abc123/split");
    body = JSON.parse(String(init.body));
    key = (init.headers as Record<string, string>)["x-idempotency-key"];
    return Promise.resolve(new Response('{"status":"OK","message":"Order split created"}', { status: 200 }));
  });
  assertEquals(key, "11111111-1111-4111-8111-111111111111");
  assertEquals(body.disable_split, true);
  assertEquals((body.split as Array<Record<string, unknown>>)[0], { vendor_id: "apvo_x", amount: 4500, tags: { purpose: "rent" } });
});

Deno.test("Cashfree errors keep their message; 'not synced' and 5xx retry, vendor errors do not", async () => {
  const err = await assertRejects(
    () => splitAfterPayment(CFG, "apv_x_123456", "apvo_x", 100, "k", () =>
      Promise.resolve(new Response('{"message":"Transaction is not synced, please retry after 2 mins","code":"api_request_failed","type":"invalid_request_error"}', { status: 400 }))),
    CashfreeApiError,
  );
  assert(splitIsRetryable(err as CashfreeApiError));
  assertFalse(splitIsRetryable(new CashfreeApiError(400, "vendor does not exist", "api_request_failed", null)));
  assert(splitIsRetryable(new CashfreeApiError(502, "bad gateway", null, null)));
});

Deno.test("refund after the split recovers the amount from the owner's vendor", async () => {
  let body: Record<string, unknown> = {};
  await createRefund(CFG, "apv_2611_abc123", "apvr_abcdef123456", 100000, "Overcharged", { vendorId: "apvo_x", amountPaise: 100000 }, (url, init) => {
    assertEquals(url, "https://sandbox.cashfree.com/pg/orders/apv_2611_abc123/refunds");
    body = JSON.parse(String(init.body));
    return Promise.resolve(new Response('{"refund_id":"apvr_abcdef123456","refund_status":"PENDING"}', { status: 200 }));
  });
  assertEquals(body.refund_amount, 1000);
  assertEquals(body.refund_splits, [{ vendor_id: "apvo_x", amount: 1000 }]);
  assertEquals(body.refund_speed, "STANDARD");
});
