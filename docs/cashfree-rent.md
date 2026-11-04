# Cashfree rent gateway (2026-11-04)

Tenants pay their monthly rent in the app through **Cashfree Payments**. The payment is confirmed
automatically by Cashfree's server-side API, and **Cashfree Easy Split** settles the full amount to
the PG owner's own UPI ID. Apnivaas's commission is zero, so no rent lands in an Apnivaas bank
account.

Razorpay remains only for the PGs of owner Rukesh Akanambattu (`hostels.rent_gateway = 'razorpay'`)
and for owners' Apnivaas plan payments.

The Cashfree API shapes were read from the official reference on 2026-11-04:

- [Create Order](https://www.cashfree.com/docs/api-reference/payments/latest/orders/create-order.md)
- [Get Order](https://www.cashfree.com/docs/api-reference/payments/latest/orders/get-order.md)
- [Get Payments for an Order](https://www.cashfree.com/docs/api-reference/payments/latest/payments/get-payments-for-an-order.md)
- [Create Vendor](https://www.cashfree.com/docs/api-reference/payments/latest/easy-split/create-vendor.md)
- [Update Vendor](https://www.cashfree.com/docs/api-reference/payments/latest/easy-split/update-vendor-details.md)
- [Get Vendor](https://www.cashfree.com/docs/api-reference/payments/latest/easy-split/get-vendor-all-details.md)
- [Split After Payment](https://www.cashfree.com/docs/api-reference/payments/latest/easy-split/split-after-payment.md)
- [Split and Settlement by Order](https://www.cashfree.com/docs/api-reference/payments/latest/easy-split/get-split-and-settlement-details-by-orderid.md)
- [Create Refund](https://www.cashfree.com/docs/api-reference/payments/latest/refunds/create-refund.md)
- [Webhook signatures](https://www.cashfree.com/docs/payments/online/webhooks/signature-verification.md)
- [Settlement webhooks](https://www.cashfree.com/docs/payments/split/webhooks.md)
- [Flutter SDK](https://www.cashfree.com/docs/payments/online/mobile/flutter.md)

## Flow

1. **Owner onboarding** (`cashfree-vendor`, the owner's second factor is required):
   - The owner enters their legal name, PAN, UPI ID, account-holder name, email, mobile, and GSTIN if they have one.
   - The function validates these against Cashfree's own rules and calls `POST /easy-split/vendors`, or `PATCH` if the vendor already exists. The vendor id is `apvo_<owner uuid>`.
   - It reads the vendor back and stores Cashfree's status. The PAN goes to Cashfree only; Apnivaas keeps its last 4 characters.
   - Checkout stays closed until Cashfree reports **ACTIVE**. The worker re-reads pending vendors every 5 minutes.
2. **Tenant checkout** (`cashfree-order` `create`):
   - The function derives the tenant, month, amount and vendor on the server, and `cf_reserve_payment` derives them again in the database.
   - It calls `POST /orders` with `payment_methods: "upi"`, `notify_url` set to the webhook, and a 30-minute expiry, then stores the payment session.
   - The app opens Cashfree's checkout through `flutter_cashfree_pg_sdk`, where the tenant picks PhonePe, Google Pay, Paytm, BHIM or any UPI app.
   - One open order is allowed per tenant per month. An older order is reconciled with Cashfree before a new one is made.
3. **Confirmation** (`cashfree-webhook`, `cashfree-order` `status`, `cashfree-worker`):
   - The webhook signature is checked over the raw body: `Base64(HMAC-SHA256(x-webhook-timestamp + rawBody, client secret))`.
   - The event is recorded once in `payment_webhook_events`, keyed on the idempotency header or the body hash.
   - The order and its payments are re-read with `GET /orders/{id}` and `GET /orders/{id}/payments`.
   - `svc_cf_apply_payment` requires `PAID` status, INR, and the exact amount in paise, then in one transaction:
     - marks the payment SUCCESS;
     - credits the rent ledger through `wd_record_payment`, never by more than is owed;
     - issues a receipt number;
     - notifies the tenant and the owner.
   - A later failure on the same order never undoes a success.
4. **Easy Split** (`cashfree-worker`, every minute through pg_cron):
   - A payment is claimed 150 seconds after success, because Cashfree asks for at least 2 minutes.
   - It calls `POST /easy-split/orders/{id}/split` with `amount` set to what was paid minus any refund, `disable_split: true`, and the payment's own `x-idempotency-key`.
   - A "not synced" answer or a 5xx is retried with backoff, up to 8 attempts.
   - "Already processed" counts as done only if the split recon lists the owner's vendor. Anything else marks the payment SETTLEMENT_FAILED and audits it.
5. **Settlement**:
   - `GET /easy-split/orders/{id}` links each payment to its settlement.
   - `VENDOR_SETTLEMENT_INITIATED`, `_SUCCESS`, `_FAILED` and `_REVERSED` webhooks update `owner_settlements` and the payment, setting it to SETTLEMENT_PENDING, SETTLED (with the UTR) or SETTLEMENT_FAILED.
   - A failed settlement never fails the payment.
6. **Refunds** (`cashfree-refund`):
   - Only the owner of that PG or the Super Admin may refund, with their second factor.
   - A refund can be full or partial, with at most one in flight per payment, and never more than is left.
   - It calls `POST /orders/{id}/refunds`. Once the split exists, `refund_splits` takes the amount back from the owner's vendor.
   - The rent ledger is reversed only when Cashfree reports SUCCESS, through the webhook or the worker's `GET` refund check.

### States

- **Payment:** INITIATED, PENDING, SUCCESS, FAILED, CANCELLED, REFUNDED.
- **Settlement:** NOT_STARTED, SPLIT_PENDING, SPLIT_CREATED, SETTLEMENT_PENDING, SETTLED, SETTLEMENT_FAILED.

## Database (`db/migrations/2026-11-04-cashfree-rent.sql`)

**Tables:**

- `hostels.rent_gateway`
- `owner_payment_accounts`
- `rent_payments`: integer paise, `rent_payments_one_open` unique per tenant and month
- `payment_webhook_events`: unique on provider and event id
- `owner_settlements`: unique on settlement and payment, nulls not distinct
- `rent_refunds`: one open refund per payment

**Access rules:**

- Row-level security lets owners, tenants and the Super Admin read only their own rows.
- Column grants keep the checkout session, the split internals and the raw provider answers on the server.
- Every write goes through SECURITY DEFINER `svc_cf_*` functions, which only the service role may call.

**Tests:** `2026-11-04-cashfree-rent.test.sql` runs on live inside a rolled-back transaction and covers 9 sections.

## Endpoints

| Function | Auth | Purpose |
|---|---|---|
| `cashfree-order` | tenant JWT | `create` an order, check an order's `status` (re-read from Cashfree) |
| `cashfree-webhook` | Cashfree signature (`--no-verify-jwt`) | payment, refund and settlement events |
| `cashfree-worker` | anon JWT (pg_cron `app.cashfree_tick()` every minute) | splits, reconciliation, vendor status, settlement recon, refund status |
| `cashfree-vendor` | owner JWT, second factor | `get`, `refresh` and `submit` the owner's vendor |
| `cashfree-refund` | owner or Super Admin JWT, second factor | full or partial refund |
| `razorpay-order` | tenant JWT | now refuses PGs whose `rent_gateway` is not `razorpay` |

## Cashfree dashboard (sandbox first)

1. Create a Cashfree merchant account at merchant.cashfree.com. In **Test** mode, go to **Developers → API Keys** and generate the App ID and Secret Key.
2. Set the Supabase secrets yourself, so they never pass through chat:

   ```bash
   npx supabase secrets set --project-ref nimxvgzscbanhtvgnjll CASHFREE_APP_ID=<test app id> CASHFREE_SECRET_KEY=<test secret> CASHFREE_ENVIRONMENT=sandbox
   ```

3. In **Developers → Webhooks**, add `https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/cashfree-webhook` with these events:
   - Payment: success, failed, user dropped
   - Refund status
   - Easy Split vendor settlement: initiated, success, failed, reversed

   Payment events also arrive through each order's `notify_url`.
4. Turn on Easy Split. In sandbox, call `POST /simulate/easy-split/enable` or use the dashboard; no request to Cashfree is needed.
5. For sandbox testing, use the documented test vendor details (UPI `success@upi`, PAN `BIAPA2934N`). A sandbox vendor becomes ACTIVE after about 10 minutes.

## Production activation (outside the code)

- **Merchant account:** Cashfree's merchant KYC and website/app review must pass, and the account must be live.
- **Easy Split:** it must be activated on the production merchant account. It is a marketplace product and needs Cashfree's approval for the rent-collection use case.
- **Vendor settlement to UPI:** settlement to a UPI ID must be enabled for vendors, and each owner's vendor must pass Cashfree's verification (KYC, PAN). An owner whose vendor is not ACTIVE cannot take online rent.
- **Credentials:** set the production App ID and Secret and `CASHFREE_ENVIRONMENT=production`. No code change is needed.
- **Production webhook:** register the same URL in Live mode.
- **Settlement schedule:** choose the cycle with Cashfree; `CASHFREE_SCHEDULE_OPTION` is optional.
