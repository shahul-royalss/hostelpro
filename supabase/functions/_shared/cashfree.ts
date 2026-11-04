/**
 * Cashfree Payment Gateway for rent: orders, payments, Easy Split vendors, Split After Payment,
 * split/settlement recon, refunds, and webhook signatures.
 *
 * Every endpoint, header and field here was read from Cashfree's official API reference on
 * 2026-11-04 (docs/cashfree-rent.md lists each page). Nothing is guessed: where the docs are
 * silent this module does less, not more.
 *
 * ═══ SECRETS ═══
 *   CASHFREE_APP_ID and CASHFREE_SECRET_KEY are Edge Function secrets and are used only in this
 *   process. No response body ever carries them. Cashfree signs Payment Gateway webhooks with the
 *   same CLIENT SECRET (there is no separate webhook secret), so CASHFREE_SECRET_KEY is also what
 *   verifySignature() uses.
 *
 *   CASHFREE_ENVIRONMENT is 'sandbox' (default) or 'production', and picks the host; production
 *   keys are configured by changing secrets only, never code.
 */

export const CF_NOT_CONFIGURED =
  "Online rent payment is not available right now. Please pay your PG directly.";

export interface CashfreeConfig {
  appId: string;
  secret: string;
  apiVersion: string;
  baseUrl: string;
  environment: "sandbox" | "production";
}

const HOSTS = {
  sandbox: "https://sandbox.cashfree.com/pg",
  production: "https://api.cashfree.com/pg",
} as const;

/** Null when the merchant account was never configured: callers fail closed. */
export function cashfreeConfig(env: (k: string) => string | undefined = (k) => Deno.env.get(k)): CashfreeConfig | null {
  const appId = (env("CASHFREE_APP_ID") ?? "").trim();
  const secret = (env("CASHFREE_SECRET_KEY") ?? "").trim();
  if (!appId || !secret) return null;
  const environment = (env("CASHFREE_ENVIRONMENT") ?? "sandbox").trim().toLowerCase() === "production"
    ? "production"
    : "sandbox";
  // An explicit base URL may only point at one of Cashfree's two documented hosts.
  const configured = (env("CASHFREE_BASE_URL") ?? "").trim().replace(/\/+$/, "");
  const baseUrl = configured === HOSTS.sandbox || configured === HOSTS.production ? configured : HOSTS[environment];
  if (baseUrl !== HOSTS[environment]) return null; // a sandbox host with production mode (or the reverse)
  const apiVersion = (env("CASHFREE_API_VERSION") ?? "2025-01-01").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(apiVersion)) return null;
  return { appId, secret, apiVersion, baseUrl, environment };
}

export class CashfreeApiError extends Error {
  readonly status: number;
  readonly code: string | null;
  readonly body: unknown;
  constructor(status: number, message: string, code: string | null, body: unknown) {
    super(message);
    this.name = "CashfreeApiError";
    this.status = status;
    this.code = code;
    this.body = body;
  }
}

type Fetcher = (input: string, init: RequestInit) => Promise<Response>;

/** One documented call. 2xx returns the parsed body; anything else throws CashfreeApiError. */
export async function cfRequest<T>(
  cfg: CashfreeConfig,
  method: "GET" | "POST" | "PATCH",
  path: string,
  opts: { body?: unknown; idempotencyKey?: string; timeoutMs?: number; fetcher?: Fetcher } = {},
): Promise<T> {
  const headers: Record<string, string> = {
    "x-client-id": cfg.appId,
    "x-client-secret": cfg.secret,
    "x-api-version": cfg.apiVersion,
    "x-request-id": crypto.randomUUID(),
    "Accept": "application/json",
  };
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  if (opts.idempotencyKey) headers["x-idempotency-key"] = opts.idempotencyKey;

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), opts.timeoutMs ?? 15000);
  let res: Response;
  try {
    res = await (opts.fetcher ?? fetch)(`${cfg.baseUrl}${path}`, {
      method,
      headers,
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
      signal: ctl.signal,
    });
  } catch (e) {
    throw new CashfreeApiError(504, "Cashfree did not answer in time.", "timeout", String(e));
  } finally {
    clearTimeout(timer);
  }
  const text = await res.text();
  let parsed: unknown = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = text.slice(0, 500);
  }
  if (!res.ok) {
    const b = (parsed ?? {}) as { message?: unknown; code?: unknown };
    const message = typeof b.message === "string" && b.message ? b.message : `Cashfree answered ${res.status}.`;
    throw new CashfreeApiError(res.status, message, typeof b.code === "string" ? b.code : null, parsed);
  }
  return parsed as T;
}

// ─── Money ──────────────────────────────────────────────────────────────────────────────────
/** Cashfree amounts are rupees with up to two decimals; the database keeps integer paise. */
export function paiseToRupees(paise: number): number {
  return Math.round(paise) / 100;
}
export function rupeesToPaise(rupees: number | string | null | undefined): number {
  const n = typeof rupees === "string" ? Number(rupees) : rupees ?? NaN;
  return Number.isFinite(n) ? Math.round((n as number) * 100) : NaN;
}

// ─── Identifiers ────────────────────────────────────────────────────────────────────────────
function randomAlnum(n: number): string {
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  const bytes = crypto.getRandomValues(new Uint8Array(n));
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
}
/** apv_<YYMM>_<random>: matches rent_payments' check ^apv_[A-Za-z0-9_]{6,45}$. */
export function newOrderId(periodMonth: string): string {
  return `apv_${periodMonth.replace("-", "").slice(2)}_${randomAlnum(20)}`;
}
export function newRefundId(): string {
  return `apvr_${randomAlnum(24)}`;
}
/** One vendor per owner, derived from the owner's id so a retry can never create a second. */
export function vendorIdFor(ownerId: string): string {
  return `apvo_${ownerId.replace(/-/g, "").toLowerCase()}`;
}

// ─── Orders and payments ────────────────────────────────────────────────────────────────────
export interface CfOrder {
  cf_order_id?: string | number;
  order_id: string;
  order_amount?: number;
  order_currency?: string;
  order_status?: string;
  payment_session_id?: string;
  order_expiry_time?: string;
}

export interface CfPayment {
  cf_payment_id?: string | number;
  order_id?: string;
  payment_status?: string;
  payment_amount?: number;
  payment_currency?: string;
  payment_message?: string;
  payment_time?: string;
  payment_completion_time?: string;
  bank_reference?: string;
  payment_group?: string;
  is_captured?: boolean;
}

export interface CreateOrderInput {
  orderId: string;
  amountPaise: number;
  customer: { id: string; phone: string; name?: string | null; email?: string | null };
  notifyUrl: string;
  expiresAt: Date;
  note: string;
  tags: Record<string, string>;
}

/** India-local ISO-8601 with offset, as Cashfree's order_expiry_time expects. */
export function istIso(d: Date): string {
  const ist = new Date(d.getTime() + 5.5 * 3600 * 1000);
  return ist.toISOString().replace(/\.\d{3}Z$/, "+05:30");
}

/** Ten-digit Indian mobile from whatever the profile holds ("+91 98…", "098…"). */
export function tenDigitPhone(raw: string | null | undefined): string | null {
  const digits = (raw ?? "").replace(/\D/g, "");
  const last10 = digits.slice(-10);
  return /^[6-9]\d{9}$/.test(last10) ? last10 : null;
}

export function createOrder(cfg: CashfreeConfig, input: CreateOrderInput, fetcher?: Fetcher): Promise<CfOrder> {
  const email = input.customer.email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.customer.email)
    ? input.customer.email
    : undefined;
  return cfRequest<CfOrder>(cfg, "POST", "/orders", {
    idempotencyKey: crypto.randomUUID(),
    fetcher,
    body: {
      order_id: input.orderId,
      order_amount: paiseToRupees(input.amountPaise),
      order_currency: "INR",
      customer_details: {
        customer_id: input.customer.id,
        customer_phone: input.customer.phone,
        ...(input.customer.name ? { customer_name: input.customer.name.slice(0, 100) } : {}),
        ...(email ? { customer_email: email } : {}),
      },
      order_meta: { notify_url: input.notifyUrl, payment_methods: "upi" },
      order_expiry_time: istIso(input.expiresAt),
      order_note: input.note.slice(0, 200),
      order_tags: input.tags,
    },
  });
}

export function getOrder(cfg: CashfreeConfig, orderId: string, fetcher?: Fetcher): Promise<CfOrder> {
  return cfRequest<CfOrder>(cfg, "GET", `/orders/${encodeURIComponent(orderId)}`, { fetcher });
}

export function getOrderPayments(cfg: CashfreeConfig, orderId: string, fetcher?: Fetcher): Promise<CfPayment[]> {
  return cfRequest<CfPayment[]>(cfg, "GET", `/orders/${encodeURIComponent(orderId)}/payments`, { fetcher });
}

/**
 * The attempt that decides the order: a SUCCESS if there is one (an order is PAID by exactly one
 * successful transaction), otherwise the most recent attempt. Null when nothing was attempted.
 */
export function decisivePayment(payments: CfPayment[] | null | undefined): CfPayment | null {
  const list = (Array.isArray(payments) ? payments : []).filter((p) => p && p.payment_status !== "NOT_ATTEMPTED");
  const success = list.find((p) => p.payment_status === "SUCCESS");
  if (success) return success;
  const time = (p: CfPayment) => Date.parse(p.payment_completion_time ?? p.payment_time ?? "") || 0;
  return list.sort((a, b) => time(b) - time(a))[0] ?? null;
}

// ─── Easy Split vendors ─────────────────────────────────────────────────────────────────────
export interface CfVendor {
  vendor_id?: string;
  status?: string;
  name?: string;
  upi?: unknown;
  schedule_option?: { schedule_id?: number; settlement_schedule_message?: string } | null;
}

export interface VendorInput {
  legalName: string;
  email: string;
  phone: string;
  vpa: string;
  beneficiaryName: string;
  pan: string;
  gstin: string | null;
}

/** Cashfree's own rules for vendor fields (Create Vendor reference), checked before sending. */
export function validateVendorInput(body: Record<string, unknown>): { value?: VendorInput; errors?: Record<string, string[]> } {
  const s = (k: string) => (typeof body[k] === "string" ? (body[k] as string).trim() : "");
  const errors: Record<string, string[]> = {};
  const nameOk = (v: string) => /^[A-Za-z0-9 .\/&-]{2,100}$/.test(v) && /[A-Za-z]/.test(v);
  const legalName = s("legal_name").replace(/\s+/g, " ");
  const beneficiaryName = (s("beneficiary_name") || legalName).replace(/\s+/g, " ");
  const email = s("email").toLowerCase();
  const phone = tenDigitPhone(s("phone"));
  const vpa = s("upi_vpa");
  const pan = s("pan").toUpperCase();
  const gstin = s("gstin").toUpperCase();
  if (!nameOk(legalName)) errors.legal_name = ["Enter your name as on PAN (letters, spaces, . / - & only)."];
  if (!nameOk(beneficiaryName)) errors.beneficiary_name = ["Enter the name on the UPI account."];
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || email.length > 254) errors.email = ["Enter a valid email address."];
  if (!phone) errors.phone = ["Enter a 10-digit Indian mobile number."];
  // Cashfree: letters, digits, . - @ _ ; at most 100; a hyphen only before the @.
  const vpaParts = vpa.split("@");
  if (
    vpa.length > 100 || vpaParts.length !== 2 || !/^[A-Za-z0-9._-]{2,}$/.test(vpaParts[0]) ||
    !/^[A-Za-z0-9._]{2,}$/.test(vpaParts[1])
  ) errors.upi_vpa = ["Enter your UPI ID, like name@okhdfcbank."];
  if (!/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(pan)) errors.pan = ["Enter your 10-character PAN, like ABCDE1234F."];
  if (gstin && !/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/.test(gstin)) errors.gstin = ["That GSTIN does not look right."];
  if (Object.keys(errors).length) return { errors };
  return { value: { legalName, email, phone: phone!, vpa, beneficiaryName, pan, gstin: gstin || null } };
}

function vendorBody(v: VendorInput) {
  return {
    status: "ACTIVE",
    name: v.legalName,
    email: v.email,
    phone: v.phone,
    upi: { vpa: v.vpa, account_holder: v.beneficiaryName },
    kyc_details: { pan: v.pan, ...(v.gstin ? { gst: v.gstin } : {}) },
  };
}

export function createVendor(cfg: CashfreeConfig, vendorId: string, v: VendorInput, scheduleOption: number | null, fetcher?: Fetcher): Promise<CfVendor> {
  return cfRequest<CfVendor>(cfg, "POST", "/easy-split/vendors", {
    idempotencyKey: crypto.randomUUID(),
    fetcher,
    body: {
      vendor_id: vendorId,
      ...vendorBody(v),
      verify_account: true,
      dashboard_access: false,
      ...(scheduleOption ? { schedule_option: scheduleOption } : {}),
    },
  });
}

export function updateVendor(cfg: CashfreeConfig, vendorId: string, v: VendorInput, fetcher?: Fetcher): Promise<CfVendor> {
  return cfRequest<CfVendor>(cfg, "PATCH", `/easy-split/vendors/${encodeURIComponent(vendorId)}`, {
    idempotencyKey: crypto.randomUUID(),
    fetcher,
    body: { ...vendorBody(v), verify_account: true },
  });
}

export function getVendor(cfg: CashfreeConfig, vendorId: string, fetcher?: Fetcher): Promise<CfVendor> {
  return cfRequest<CfVendor>(cfg, "GET", `/easy-split/vendors/${encodeURIComponent(vendorId)}`, { fetcher });
}

// ─── Split After Payment and recon ──────────────────────────────────────────────────────────
export function splitAfterPayment(
  cfg: CashfreeConfig,
  orderId: string,
  vendorId: string,
  amountPaise: number,
  idempotencyKey: string,
  fetcher?: Fetcher,
): Promise<{ status?: string; message?: string }> {
  return cfRequest(cfg, "POST", `/easy-split/orders/${encodeURIComponent(orderId)}/split`, {
    idempotencyKey,
    fetcher,
    body: {
      split: [{ vendor_id: vendorId, amount: paiseToRupees(amountPaise), tags: { purpose: "rent" } }],
      disable_split: true,
    },
  });
}

export interface CfSplitRecon {
  settlement?: { cf_settlement_id?: number; transfer_utr?: string | null } | null;
  vendors?: Array<{ vendor_id?: string; settlement_id?: number | string | null; settlement_amount?: number; settlement_eligibility_date?: string | null }>;
}

export function getSplitRecon(cfg: CashfreeConfig, orderId: string, fetcher?: Fetcher): Promise<CfSplitRecon> {
  return cfRequest<CfSplitRecon>(cfg, "GET", `/easy-split/orders/${encodeURIComponent(orderId)}`, { fetcher });
}

/** Whether a split error is worth retrying: not synced yet, rate limits, timeouts, 5xx. */
export function splitIsRetryable(e: CashfreeApiError): boolean {
  return e.status >= 500 || e.status === 429 || /not synced|retry after/i.test(e.message);
}

// ─── Refunds ────────────────────────────────────────────────────────────────────────────────
export interface CfRefund {
  cf_refund_id?: string | number;
  refund_id?: string;
  order_id?: string;
  refund_amount?: number;
  refund_status?: string;
  status_description?: string;
}

export function createRefund(
  cfg: CashfreeConfig,
  orderId: string,
  refundId: string,
  amountPaise: number,
  note: string | null,
  vendorSplit: { vendorId: string; amountPaise: number } | null,
  fetcher?: Fetcher,
): Promise<CfRefund> {
  return cfRequest<CfRefund>(cfg, "POST", `/orders/${encodeURIComponent(orderId)}/refunds`, {
    idempotencyKey: crypto.randomUUID(),
    fetcher,
    body: {
      refund_amount: paiseToRupees(amountPaise),
      refund_id: refundId,
      refund_speed: "STANDARD",
      ...(note ? { refund_note: note.slice(0, 100) } : {}),
      ...(vendorSplit
        ? { refund_splits: [{ vendor_id: vendorSplit.vendorId, amount: paiseToRupees(vendorSplit.amountPaise) }] }
        : {}),
    },
  });
}

export function getRefund(cfg: CashfreeConfig, orderId: string, refundId: string, fetcher?: Fetcher): Promise<CfRefund> {
  return cfRequest<CfRefund>(
    cfg,
    "GET",
    `/orders/${encodeURIComponent(orderId)}/refunds/${encodeURIComponent(refundId)}`,
    { fetcher },
  );
}

// ─── Webhooks ───────────────────────────────────────────────────────────────────────────────
function toBase64(bytes: ArrayBuffer): string {
  let bin = "";
  for (const b of new Uint8Array(bytes)) bin += String.fromCharCode(b);
  return btoa(bin);
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * Cashfree: expectedSignature = Base64(HMAC-SHA256(timestamp + rawBody, clientSecret)), from the
 * x-webhook-timestamp and x-webhook-signature headers, over the RAW body exactly as received.
 */
export async function verifySignature(
  rawBody: string,
  timestamp: string | null,
  signature: string | null,
  secret: string,
): Promise<boolean> {
  if (!timestamp || !signature || !secret) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp + rawBody));
  return constantTimeEqual(toBase64(mac), signature.trim());
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
