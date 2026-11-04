/**
 * POST /functions/v1/cashfree-vendor — an owner's Cashfree Easy Split vendor (where their rent
 * is settled: their own UPI ID).
 *
 *   { "action": "get" }      → the owner's payment account, as stored (no provider internals)
 *   { "action": "refresh" }  → re-read the vendor's status from Cashfree, then "get"
 *   { "action": "submit", legal_name, email, phone, upi_vpa, beneficiary_name, pan, gstin? }
 *                            → create the vendor (or update it) at Cashfree, then store
 *                              Cashfree's answer
 *
 * ═══ VERIFIED MEANS CASHFREE SAID ACTIVE ═══
 * A well-formed UPI ID is not a verified one. The account is stored with Cashfree's own vendor
 * status, and rent checkout opens only once that status is ACTIVE (verification_status
 * 'verified'), which for a new or changed UPI ID comes after Cashfree checks it.
 *
 * ═══ CHANGING WHERE RENT GOES IS PRIVILEGED ═══
 * requireCaller('owner') applies the owner's second factor (an owner with a factor must be at
 * aal2), every submission is rate limited and audited, and a change puts the account back to
 * pending until Cashfree verifies the new details, so checkout pauses in between.
 *
 * The PAN goes to Cashfree (it is required for every vendor) and is never stored or logged here;
 * only its last four characters are kept, for the owner to recognise it.
 *
 * DEPLOY: supabase functions deploy cashfree-vendor   (verify_jwt ON)
 */
import { requireCaller } from "../_shared/caller.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { dbError } from "../_shared/errors.ts";
import { audit } from "../_shared/audit.ts";
import { consumeRateLimit, throttled } from "../_shared/ratelimit.ts";
import { HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import {
  CF_NOT_CONFIGURED,
  CashfreeApiError,
  type CfVendor,
  cashfreeConfig,
  createVendor,
  getVendor,
  updateVendor,
  validateVendorInput,
  vendorIdFor,
} from "../_shared/cashfree.ts";

const ACCOUNT_COLUMNS =
  "cashfree_vendor_id, legal_name, email, phone, upi_vpa, beneficiary_name, pan_last4, gstin, vendor_status, " +
  "verification_status, settlement_schedule_message, last_error, last_checked_at, activated_at, updated_at";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  try {
    if (req.method !== "POST") throw new HttpError(405, "Method not allowed.");
    const caller = await requireCaller(req, "owner");
    const body = await readJsonBody(req, 8 * 1024);
    const action = typeof body.action === "string" ? body.action : "get";
    const db = serviceClient();

    const read = async () => {
      const { data, error } = await db.from("owner_payment_accounts").select(ACCOUNT_COLUMNS)
        .eq("owner_id", caller.id).maybeSingle();
      if (error) throw dbError(error);
      return data as unknown as Record<string, unknown> | null;
    };

    if (action === "get") return ok({ account: await read(), configured: cashfreeConfig() != null });

    const cfg = cashfreeConfig();
    if (!cfg) throw new HttpError(503, "Cashfree is not connected yet. Please try again later.");
    const vendorId = vendorIdFor(caller.id);

    if (action === "refresh") {
      const existing = await read();
      if (existing) {
        try {
          const vendor = await getVendor(cfg, vendorId);
          await db.rpc("svc_cf_vendor_status", { p_vendor_id: vendorId, p_vendor_status: vendor.status ?? null, p_response: vendor, p_error: null });
        } catch (e) {
          console.error("[cashfree-vendor] refresh:", e instanceof Error ? e.message : String(e));
        }
      }
      return ok({ account: await read(), configured: true });
    }

    if (action !== "submit") throw new HttpError(400, "Unknown action.");

    const wait = await consumeRateLimit(`cfvendor:${caller.id}`, { max: 8, windowSeconds: 3600 }, {
      unavailableMessage: "Please try again in a minute.",
    });
    if (wait > 0) throw throttled("Too many changes in the last hour. Please try again later.", wait);

    const { value, errors } = validateVendorInput(body);
    if (!value) throw new HttpError(422, "Please correct the highlighted details.", { fieldErrors: errors });

    const existing = await read();
    let vendor: CfVendor;
    try {
      if (existing) {
        vendor = await updateVendor(cfg, vendorId, value);
      } else {
        try {
          vendor = await createVendor(cfg, vendorId, value, Number(Deno.env.get("CASHFREE_SCHEDULE_OPTION") ?? "") || null);
        } catch (e) {
          // Created on an earlier attempt whose answer was lost: update it instead.
          if (e instanceof CashfreeApiError && (e.status === 409 || /already exist/i.test(e.message))) {
            vendor = await updateVendor(cfg, vendorId, value);
          } else {
            throw e;
          }
        }
      }
    } catch (e) {
      if (e instanceof CashfreeApiError) {
        await audit("payment.cashfree.vendor_refused", caller, {
          targetType: "owner_payment_account",
          targetId: vendorId,
          meta: { status: e.status, code: e.code },
        });
        if (existing) {
          await db.rpc("svc_cf_vendor_status", { p_vendor_id: vendorId, p_vendor_status: null, p_response: null, p_error: e.message });
        }
        // Cashfree's own sentence ("kyc_details.pan_missing", "Invalid UPI") helps the owner fix it.
        throw new HttpError(e.status >= 500 ? 502 : 400, `Cashfree could not accept these details: ${e.message}`);
      }
      throw e;
    }

    // Read the vendor back so the stored status is Cashfree's, not the create call's echo.
    let status = vendor.status ?? null;
    let schedule = vendor.schedule_option ?? null;
    try {
      const fresh = await getVendor(cfg, vendorId);
      status = fresh.status ?? status;
      schedule = fresh.schedule_option ?? schedule;
      vendor = fresh;
    } catch {
      // The create/update answer stands; the worker re-reads pending vendors every few minutes.
    }

    const { error: saveError } = await db.rpc("svc_cf_vendor_save", {
      p_owner: caller.id,
      p_vendor_id: vendorId,
      p_legal_name: value.legalName,
      p_email: value.email,
      p_phone: value.phone,
      p_vpa: value.vpa,
      p_beneficiary: value.beneficiaryName,
      p_pan_last4: value.pan.slice(-4),
      p_gstin: value.gstin,
      p_vendor_status: status ?? "SUBMITTED",
      p_schedule: schedule?.schedule_id ?? null,
      p_schedule_message: schedule?.settlement_schedule_message ?? null,
      p_response: { ...vendor, kyc_details: undefined, related_docs: undefined },
    });
    if (saveError) throw dbError(saveError);

    await audit(existing ? "payment.cashfree.vendor_updated" : "payment.cashfree.vendor_created", caller, {
      targetType: "owner_payment_account",
      targetId: vendorId,
      meta: { vendor_status: status, upi_changed: existing ? existing.upi_vpa !== value.vpa : true },
    });
    return ok({ account: await read(), configured: true });
  } catch (err) {
    return toResponse(err);
  }
});

// Referenced so a reader of this file finds the sentence tenants see when checkout is closed.
void CF_NOT_CONFIGURED;
