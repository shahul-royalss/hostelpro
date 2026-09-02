# Rent paid inside the app — Razorpay, with the secret never on the device

How a resident pays rent from the Flutter app: what runs, where each secret lives, the exact
commands to deploy it, and the one dashboard setting that decides whether any of it works.

**The product requirement this is built around:** *nothing goes to a browser; everything happens
in the application.* There is no WebView, no `url_launcher`, no "open in browser" fallback on this
path. `razorpay_flutter` opens Razorpay's own **native** checkout activity, and the server-side
work happens in Supabase Edge Functions the app calls with `functions.invoke()`. A function is a
server, not a browser — which is also how `RAZORPAY_KEY_SECRET` stays off the phone.

Companion documents, not duplicates of this one:

| Document | Covers |
| --- | --- |
| `docs/payments.md` | The **web** payment path, the database design, and §7 reconciliation. Still authoritative for both. |
| `docs/edge-functions.md` | The Edge Function deploy runbook in general — CLI setup, linking, the service-role key. |
| `db/migrations/2026-08-24-payments.sql` | `payment_intents` and the `rz_*` functions. The source of truth for the money rules. |

---

## 1. The pieces

| File | Runs where | Holds |
| --- | --- | --- |
| `supabase/functions/razorpay-order/index.ts` | Supabase Edge (Deno) | `RAZORPAY_KEY_SECRET`. **No service-role key.** |
| `supabase/functions/razorpay-webhook/index.ts` | Supabase Edge (Deno) | `RAZORPAY_WEBHOOK_SECRET` + the service-role key |
| `supabase/functions/_shared/razorpay.ts` | Supabase Edge (Deno) | Key handling, HMAC verification, the Orders API call |
| `nivora_app/lib/data/models/checkout.dart` | Phone | `CheckoutOrder`, `CheckoutOutcome` — no secret of any kind |
| `nivora_app/lib/data/repositories/checkout_repository.dart` | Phone | The Edge Function call, and the refusal-to-sentence mapping |
| `nivora_app/lib/features/payments/pay_rent.dart` | Phone | The native checkout wrapper and the **ledger wait** that confirms it |
| `nivora_app/lib/features/student/rent_payment_controller.dart` | Phone | The eight-state payment machine |
| `nivora_app/lib/features/student/pay_rent_sheet.dart` | Phone | What the resident actually sees |
| `nivora_app/test/payment_test.dart` | CI | 18 tests — no network, no device, no Razorpay account |

Nothing new was added to the database. `payment_intents`, `rz_open_intent`, `rz_record_capture`,
`rz_credit_fee` and `rz_mark_failed` already existed for the web path and are reused unchanged —
which is the point. **One set of money rules, two clients.**

### Which tables and RPCs each piece touches

| Screen / object | Reads | Writes |
| --- | --- | --- |
| `pay_rent_sheet.dart` | `razorpay-order` (Edge Function), then `public.payment_intents` (SELECT) | nothing — the app has **no** write path to `payment_intents` |
| `rent_payment_controller.dart` | `payment_intents` via `PaymentRepository.watchSettlement` | invalidates the rent-ledger providers after a verdict, so every screen re-reads the real figure |
| `razorpay-order` | `public.students`, `public.fee_payments`, `public.payment_intents`, `st_hostel_contacts()` — all **as the caller**, under their own RLS | `rz_open_intent(p_order_id, p_amount_paise)` as the caller |
| `razorpay-webhook` | — | `rz_record_capture()`, `rz_credit_fee()`, `rz_mark_failed()`, `audit_event()` — all as `service_role` |

---

## 2. The money path

```
  PHONE                        EDGE FUNCTION                RAZORPAY            DATABASE
  -----                        -------------                --------            --------
  tap "Pay rent"
    |
    | invoke('razorpay-order')     auth.getUser(jwt) ---------------------->  who?
    | NO BODY AT ALL               read own students row ------------------>  RLS
    |                              read own fee_payments ------------------>  RLS
    |                              amount = what is owed
    |                                      |
    |                                      |-- POST /v1/orders ---->  order_XYZ
    |                                      |   (key SECRET, here only)
    |                                      |
    |                                      '-- rz_open_intent(order, amount) ->  RE-DERIVES the
    |                                                                            amount and REFUSES
    |                                                                            if it differs
    | <-- { order_id, amount_paise, key_id (publishable), prefill }
    |
  Razorpay.open()  ---->  NATIVE checkout sheet  ---->  resident pays
    |
    | <-- onPaymentSuccess(payment_id)     <- NOT A RECEIPT. Nothing is credited here.
    |
    |  state = "Payment received - confirming"
    |
    |  poll payment_intents every 2s ------------------------------------>  RLS: own rows only
                                                       ^
                                   Razorpay --> razorpay-webhook --> HMAC verify
                                   (asynchronous,       |             rz_record_capture()
                                    usually 1-3s)       '-----------> rz_credit_fee()
                                                                       -> wd_record_payment()
                                                                       -> fee_payments credited
    |
    | <-- credited_at is set  ->  "Rent updated"
```

### The two properties this whole design exists for

**1. The client never names the amount.** `CheckoutRepository.open()` sends **no request
body** — not an amount, not a student id, not a month. The Edge Function derives all three from the
JWT and the caller's own ledger, and then `rz_open_intent()` derives the amount a *second* time
inside the database and raises `P0001` unless the two agree exactly. Two independent derivations
have to agree before an intent row exists. A tampered client, or a bug in the function, produces a
refusal — never a ₹1 order for a ₹9,000 room.

**2. The app never decides a payment succeeded.** Razorpay's success callback fires on the device,
before the webhook has been delivered. `rent_payment_controller.dart` moves to
`RentPaymentConfirming` on that callback and **nothing** can move it to `RentPaymentCredited`
except reading `payment_intents.credited_at` back from the server. Verifying the checkout signature
on the phone would be theatre: the secret it is signed with is not on the device, and could not
safely be.

---

## 3. The secrets

Three values. Only one of them may ever reach a phone.

| Name | Secret? | Where it lives | Where it must never be |
| --- | --- | --- | --- |
| `RAZORPAY_KEY_ID` | no — publishable | Supabase function secret; returned to the app per-order | (safe anywhere) |
| `RAZORPAY_KEY_SECRET` | **yes** | Supabase function secret **only** | any file under `nivora_app/`, any `--dart-define`, any APK |
| `RAZORPAY_WEBHOOK_SECRET` | **yes** | Supabase function secret **only** | same |

`RAZORPAY_KEY_SECRET` for this project is in `.env.local` at the repo root, under that name. Read it
from there when you run the command below and let it go no further — not into a ticket, a chat, a
commit, or a second file.

> An APK is a zip file anyone can download and unpack. A secret compiled into one is a **published**
> secret. That is why the order is created by a function and not by the app: the app cannot call
> Razorpay's Orders API at all, because it does not have — and must not have — the credential to.

### Set them

```bash
cd "C:/Users/shahu/OneDrive/Documents/pg management system"

npx supabase secrets set RAZORPAY_KEY_ID=rzp_test_TTZjgz6pssJVJs
npx supabase secrets set RAZORPAY_KEY_SECRET=<the value of RAZORPAY_KEY_SECRET in .env.local>
npx supabase secrets set RAZORPAY_WEBHOOK_SECRET=<the string you type into the Razorpay dashboard in section 5>
```

The webhook function also needs the service-role key. If you have already followed
`docs/edge-functions.md` §4.1 it is set; if not:

```bash
npx supabase secrets set NIVORA_SERVICE_ROLE_KEY=<service_role key from Dashboard > Project Settings > API keys>
```

`NIVORA_` and not `SUPABASE_` because the CLI reserves the `SUPABASE_` prefix for values the
platform injects itself. `_shared/supabase.ts` reads `NIVORA_SERVICE_ROLE_KEY` first and falls back
to the platform-injected `SUPABASE_SERVICE_ROLE_KEY`.

Check what is set — this prints **names and digests only**, never values:

```bash
npx supabase secrets list
```

Shell history keeps what you type. On bash, with `HISTCONTROL=ignorespace`, prefixing the command
with a single space keeps it out of `~/.bash_history`. If you use `--env-file` instead, delete the
file afterwards: `.gitignore` covers `.env*` at any depth, but a file is one `git add -f` away from
being in the history forever.

Secrets take effect on the **next invocation**. You do not need to redeploy after setting them.

---

## 4. Deploy

```bash
cd "C:/Users/shahu/OneDrive/Documents/pg management system"

npx supabase functions deploy razorpay-order
npx supabase functions deploy razorpay-webhook --no-verify-jwt
```

**`--no-verify-jwt` goes on the webhook and on nothing else.** Razorpay's servers do not hold a
Supabase JWT. With the platform gate on, every delivery is rejected at the gateway before the
function runs: the resident pays, the fee ledger never moves, and the logs show nothing because the
code never executed. The flag weakens nothing — the function authenticates its caller by verifying
Razorpay's HMAC signature over the raw body, which is strictly stronger than a shared bearer token
because it also proves the body was not altered.

`razorpay-order` keeps JWT verification **on**, but that is not what authorises it. The anon key is
itself a structurally valid project JWT and sails through platform verification; `auth.getUser()`
inside the function is what turns "a valid token" into "a specific person", and an anon-key call
fails it with a 401.

If the project is not linked yet, `docs/edge-functions.md` §3 has the one-time setup. Short version:
`npx supabase login`, then `npx supabase link --project-ref nimxvgzscbanhtvgnjll`.

---

## 5. The Razorpay dashboard webhook

**Razorpay Dashboard → Settings → Webhooks → Add New Webhook**

| Field | Value |
| --- | --- |
| **Webhook URL** | `https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-webhook` |
| **Secret** | a long random string you choose — this is `RAZORPAY_WEBHOOK_SECRET` from §3 |
| **Active Events** | `payment.captured` **and** `payment.failed` — nothing else |

The secret is **not** the API key secret. Using the key secret here makes every delivery fail its
signature check, and the symptom is identical to having no webhook at all: money taken, rent never
credited.

Other events are answered `200 {"outcome":"ignored"}` and discarded, so subscribing to more than
these two costs nothing but noise. Subscribing to *fewer* costs you the feature.

> **Without a working webhook, no payment is ever credited.** Razorpay charges the resident, the app
> shows "Payment received - confirming" until it gives up, and `fee_payments` stays unpaid. This is
> the single most important thing on this page.

### Which webhook — read this before registering anything

There are now **two** endpoints that do this job:

| Endpoint | Serves | Deployed on |
| --- | --- | --- |
| `https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-webhook` | the Flutter app | Supabase Edge |
| `https://<your-domain>/api/webhooks/razorpay` | the Next.js web portal | Vercel |

They are equivalent. Both verify the same HMAC, both call the same `rz_record_capture()` and
`rz_credit_fee()`, and either one settles a payment regardless of which client started it — because
settlement is a property of the database, not of which HTTP server received the callback.
**Register exactly one.**

Registering both is *not dangerous* — the unique index on `payment_intents.razorpay_payment_id`
makes a double credit impossible, so the second delivery returns `duplicate` and does nothing — but
it doubles every delivery and makes `public.audit_log` read as though each payment happened twice.
That is a bad property for the one table people consult when money is missing.

**Choose the Edge Function** if the Flutter app is the product and the web portal may come and go:
it lives in the same project as the database and does not depend on a Vercel deployment existing.
**Choose the Vercel route** if the web portal is already live with a working webhook and you would
rather not touch a settled configuration.

---

## 6. What the app sends and gets back

**Request** — `POST /functions/v1/razorpay-order`, `Authorization: Bearer <the resident's access
token>`, and **no body**. `supabase_flutter`'s functions client attaches the token automatically.

**Success** (`200`):

```jsonc
{
  "ok": true,
  "data": {
    "order_id":      "order_QkP2xRZ7bT4nQe",
    "key_id":        "rzp_test_TTZjgz6pssJVJs",  // PUBLISHABLE. The only Razorpay credential sent.
    "amount_paise":  620000,                     // the server's figure. Display, and hand back unchanged.
    "amount_rupees": 6200,
    "currency":      "INR",
    "period_month":  "2026-08",                  // chosen by the server clock
    "hostel_name":   "Sunrise Residency",
    "student_name":  "Rohan Deshmukh",
    "test_mode":     true,                       // true on a rzp_test_ key; shown to the resident
    "prefill":       { "name": "...", "email": "...", "contact": "..." }
  }
}
```

**Refusals** — each carries a sentence written for the resident, which the app shows verbatim:

| Status | Meaning |
| --- | --- |
| `401` | Not signed in, or an anon-key call. |
| `404` | No `students` row for this account — "Contact your warden." |
| `409` | Nothing to pay this month, or the remainder is under ₹1. |
| `502` | Razorpay refused the order, or could not be reached. |
| `503` | `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` not set — "You can still pay at the warden desk." |

The key id comes back **from the server**, per order, rather than being compiled into the app. That
is deliberate: it is read from the same environment as the secret that signed the order, so a test
order can never be opened with a live key or the reverse. (`Env.razorpayKeyId` exists in
`nivora_app/lib/core/config/env.dart` as a build-time hook and is **not used** by this path.)

### Order reuse

Dismissing the sheet and tapping Pay again does not mint a new order. `razorpay-order` looks for an
unpaid intent for the same resident, the same month and the same amount created in the last 15
minutes, and offers that order again. This keeps `payment_intents` honest — abandoned rows look like
failed payments to whoever is reconciling — and keeps the 10-attempts-per-hour floor inside
`rz_open_intent` from being burned by a fidgety thumb.

---

## 7. What the resident sees, and why it is worded that way

`RentPaymentState` has eight cases. Three exist purely because the honest answers really are
different from one another, and rounding them to "Paid" or "Failed" would be a lie:

| State | Heading on screen | True statement |
| --- | --- | --- |
| `RentPaymentConfirming` | **Payment received — confirming** ("...waiting for your hostel record to update... Please do not pay again.") | The money left. The server has not confirmed. |
| `RentPaymentReceived` | **Payment received** ("It has not appeared on your rent ledger yet... Do not pay again.") | `captured_at` set, `credited_at` **null**. Real, and it can last. |
| `RentPaymentCredited` | **Rent updated** ("...added to your rent record.") | `credited_at` set. **The only state allowed to say the rent is settled.** |
| `RentPaymentUnconfirmed` | **Still confirming** ("...your hostel record has not caught up yet... Please do not pay again.") | 40s elapsed with no verdict. **Not an error, and never drawn as one.** |

`captured` is deliberately not "Paid". At that moment Razorpay has the money and the rent ledger has
not been credited — and `rz_credit_fee()` runs through every guard the warden's desk runs through,
one of which (hard rule §4.4, expired subscription) can legitimately refuse. Money taken and not yet
on the ledger is a real state, and the resident deserves the real sentence. A resident shown "Paid"
and then asked for rent again stops believing the app about money, which is the only thing they
opened it for.

`RentPaymentUnconfirmed` is the state that matters most on a bad day. The payment is almost
certainly fine; the webhook is simply slower than the forty seconds anyone will watch a spinner for.
Telling someone "failed" there is how you get paid twice.

---

## 8. Verify it works

Nothing in this section needs a service-role key, so it is safe to run from a laptop.

```bash
# 1. Are both deployed?
npx supabase functions list

# 2. razorpay-order must refuse an anonymous caller - 401, NOT 500.
curl -i -X POST "https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-order"

# 3. ...and must refuse the anon key too. The anon key is a valid project JWT with no
#    user behind it; auth.getUser() is what rejects it.
curl -i -X POST "https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-order" \
  -H "Authorization: Bearer <ANON-KEY>"

# 4. THE ONE THAT MATTERS. An unsigned webhook must be refused with 401.
#    If this returns 200, stop and fix it: anyone can mark any rent as paid with curl.
curl -i -X POST "https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-webhook" \
  -H "Content-Type: application/json" \
  -d '{"event":"payment.captured","payload":{"payment":{"entity":{"id":"pay_fake000000","order_id":"order_fake00000","amount":100,"currency":"INR"}}}}'

# 5. A wrong signature must also be 401 - not 400, not 500.
curl -i -X POST "https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/razorpay-webhook" \
  -H "Content-Type: application/json" \
  -H "X-Razorpay-Signature: 0000000000000000000000000000000000000000000000000000000000000000" \
  -d '{"event":"payment.captured"}'
```

A `401` in steps 4 and 5, plus a `payment.webhook.rejected` row in `public.audit_log` with
`reason: "bad_signature"`, is the check that actually proves the perimeter is closed.

Then, end to end, on a device with a **test** key:

1. Sign in as a student who owes rent this month.
2. Tap **Pay rent**. The native Razorpay sheet must open — **not** a browser, not a WebView. If a
   browser opens, something on this path is wrong and the product requirement is violated.
3. Pay with a Razorpay test instrument (card `4111 1111 1111 1111`, any future expiry, any CVV, and
   the test gateway's OTP; or the test UPI success flow).
4. The sheet closes → "Payment received — confirming" → within a few seconds "Rent updated".
5. Confirm it landed for real, not just on screen:

```sql
select status, amount_paise, razorpay_payment_id, captured_at, credited_at
  from public.payment_intents
 where razorpay_order_id = 'order_...';

-- and the ledger the warden sees:
select period_month, amount_due, amount_paid, status, notes
  from public.fee_payments
 where student_id = '...' and period_month = to_char(current_date, 'YYYY-MM');
```

`credited_at` set **and** `fee_payments.notes` reading `Paid online · Razorpay pay_...` is the
proof. Anything less and the app was telling the truth when it said "confirming".

Logs: **Dashboard → Edge Functions → `razorpay-webhook` → Logs**. The CLI has no `functions logs`
subcommand, so the dashboard is the way.

---

## 9. When it goes wrong

| Symptom | Cause | Fix |
| --- | --- | --- |
| Every delivery 401s, nothing is credited | Deployed without `--no-verify-jwt` | Redeploy the webhook with the flag |
| Every delivery 401s, `bad_signature` in `audit_log` | Dashboard secret ≠ `RAZORPAY_WEBHOOK_SECRET`, or the API key secret was pasted into the dashboard | Re-set both to the same freshly chosen string |
| Every delivery 503 | `RAZORPAY_WEBHOOK_SECRET` not set | `npx supabase secrets set ...`; no redeploy needed |
| Pay button says "not set up yet" | `RAZORPAY_KEY_ID` or `RAZORPAY_KEY_SECRET` not set | §3 |
| Sheet opens then dies on a **release** build only | R8 stripped Razorpay's reflective classes | Already handled — `nivora_app/android/app/proguard-rules.pro` keeps `com.razorpay.**`. If you edit that file, do not remove that block. |
| App always ends at "we stopped waiting" | The webhook is not reaching the server at all | Steps 4–5 above, then the dashboard's own webhook delivery log |
| `captured` rows with `credited_at` null | `rz_credit_fee` was refused — usually an expired subscription (§4.4) | `docs/payments.md` §7. Renew, then re-deliver the event from the Razorpay dashboard; it re-enters as `duplicate` and the credit is retried |

The reconciliation query — money Razorpay took that the ledger has not been credited with — is the
one to run when anyone says a payment is missing:

```sql
select id, student_id, period_month, amount_paise, razorpay_payment_id, captured_at
  from public.payment_intents
 where status = 'captured' and credited_at is null
 order by created_at;
```

It has a partial index behind it and should always return zero rows.

---

## 10. What is NOT done here

Stated plainly so nobody assumes otherwise:

- **Nothing is deployed.** Every command above is written down and none of it has been run against
  the live project. The functions exist as source only.
- **No live payment has been made end to end.** The state machine is verified by 18 tests in
  `nivora_app/test/payment_test.dart` using a fake repository and a fake checkout — no network, no
  device, no Razorpay account. The `razorpay_flutter` plugin's own behaviour on a real handset (the
  native sheet, and the resync-after-activity-death path) is **unverified** and needs a device.
- **The Deno functions have not been type-checked.** `deno check` was not run — there is no Deno
  toolchain on this machine. They are consistent with the four functions already in that directory
  and with `_shared/`, but that is an argument, not a verification.
- **Refunds are out of scope.** There is no refund path in the app, the database, or either webhook.
  A refund is issued from the Razorpay dashboard and the fee ledger is corrected by the warden.
- **Partial payments are out of scope.** The order is always for the full outstanding balance of the
  current month. A resident who wants to pay half of it pays at the warden desk.
- **Only the current month can be paid.** `rz_open_intent()` takes the period from the database
  clock. Arrears from previous months are not payable in the app.
