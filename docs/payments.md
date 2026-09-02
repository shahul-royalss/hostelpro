# Student rent payments (Razorpay)

How a resident pays their rent from the app, what stops that path being abused, and what an
operator has to do when something does not land.

**Scope.** Students paying rent, and nothing else. Owners paying their platform subscription is a
separate flow and is not built here. Nothing in this document creates, cancels or refunds a
payment on a student's behalf — the app records money that Razorpay reports it has taken, and that
is all it does.

Companion documents: [`../SECURITY.md`](../SECURITY.md) (controls and the audit that produced
them), [`access-control.md`](./access-control.md) (who may read what),
[`logging-and-monitoring.md`](./logging-and-monitoring.md) (the audit trail these events land in).

---

## 1. Configuration

Three values, none of them optional in production. **The app builds and runs with all three
absent** — the Pay button simply reports that online payment is not set up and the warden desk
still works — so nothing here blocks a deploy.

| Variable | Secret? | Where it comes from |
| --- | --- | --- |
| `RAZORPAY_KEY_ID` | no (publishable) | Razorpay Dashboard → Account & Settings → API Keys |
| `RAZORPAY_KEY_SECRET` | **yes** | shown once, at the moment the key is generated |
| `RAZORPAY_WEBHOOK_SECRET` | **yes** | you choose it when you add the webhook (below) |

Add them to `.env.local` for development and to the Vercel project's environment variables for
production. `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` are **server-only** — never prefix
either with `NEXT_PUBLIC_`.

`RAZORPAY_KEY_ID` is deliberately *not* a `NEXT_PUBLIC_` variable either, even though it is public
information. A `NEXT_PUBLIC_` value is inlined into the browser bundle at build time, which would
bake a test key into a production build (and the reverse), and would put the merchant identity into
every page's JavaScript whether or not the person looking at it can pay anything. It is read on the
server and handed to the one student who is actually opening a payment.

### The webhook

Razorpay Dashboard → Settings → Webhooks → **Add New Webhook**:

- **URL** — `https://<your-domain>/api/webhooks/razorpay`
- **Secret** — a long random string. This is `RAZORPAY_WEBHOOK_SECRET`. It is **not** the same
  value as the API key secret, and using the key secret here will make every delivery fail its
  signature check.
- **Active events** — `payment.captured` and `payment.failed`. Nothing else is read; other events
  are answered `200 {"outcome":"ignored"}` and discarded.

> **Without a working webhook, no payment is ever credited.** The student is charged by Razorpay,
> the app records nothing, and the fee ledger stays unpaid. This is the single most important
> thing to get right, and §7 tells you how to see when it is wrong.

---

## 2. Wiring that lives outside this feature's files

Four changes are needed in files the payment feature does not own. Until they are made, the
feature is inert or the CI gate fails.

**1. Middleware must let Razorpay through.** Every request is redirected to `/login` unless its
path is public, and Razorpay is not signed in and never will be. In
`lib/supabase/middleware.ts`, add to `PUBLIC_PATHS`:

```ts
"/api/webhooks/razorpay",
```

This exempts the route from the **session** gate only. It does not exempt it from anything else:
the HMAC signature check is the route's own, runs before any parsing, and cannot be reached past.

**2. The security scan needs the service-role use recorded.** `scripts/security-scan.mjs` blocks
any file touching the service-role client unless it is named in `ADMIN_ALLOWED` — deliberately, so
that adding one is a review decision. Add:

```js
// The Razorpay webhook. public.payment_intents has RLS on and NO insert/update policy for any
// human role — that absence is what makes the table trustworthy — so the settlement RPCs
// (rz_record_capture, rz_credit_fee) are granted to service_role alone. Razorpay is not signed
// in, so there is no user session to act as. Confined to this one file: order creation
// deliberately does NOT use the service role (see rz_open_intent).
"app/api/webhooks/razorpay/route.ts",
```

**3. `.env.example`** should gain the three variables above, so the next person setting up knows
they exist.

**4. Mount the button.** In `app/student/page.tsx`, inside the fee card:

```tsx
import { PayRentButton } from "@/components/payments/pay-rent-button";
// …
{fee && fee.remaining > 0 ? (
  <div className="mt-3">
    <PayRentButton amountDue={fee.remaining} period={period} />
  </div>
) : null}
```

Both props are display hints for the collapsed button. The sheet asks the server for the real
figure when it opens an order; passing a wrong number here changes a label and nothing else.
`PayRentButton` renders nothing when `amountDue <= 0`, so it is safe to place unconditionally.

---

## 3. The money path

```
  student taps Pay
        │
        ▼
  createRentOrder()                    lib/actions/payments.ts   (takes NO arguments)
        │  reads the student's own ledger, RLS-scoped
        │  amount = summariseFee(...).remaining
        ▼
  razorpay.orders.create({ amount })    server-side, key_secret never leaves
        │
        ▼
  rz_open_intent(order_id, amount)      SQL — RE-DERIVES the amount and refuses a mismatch
        │  → payment_intents row, status 'created'
        ▼
  Checkout modal                        checkout.razorpay.com, loaded on this tap and not before
        │
        │   ……… the student pays. The browser's success callback is advisory only. ………
        ▼
  POST /api/webhooks/razorpay           HMAC verified over the RAW body, timing-safe
        │
        ├── rz_record_capture()          claims the order EXACTLY ONCE  → 'captured'
        │
        └── rz_credit_fee()              → wd_record_payment() → public.fee_payments  → 'credited'
                                          (a second transaction — see §5)
        ▼
  the sheet polls getRentPaymentStatus() until the server says 'credited', then shows a receipt
```

Two facts about this diagram are the whole design:

- **The browser is never on the money path.** It taps a button and it reads a status. Everything
  between those two things happens on the server or in the database.
- **Checkout's success callback does not credit anything.** It only tells the sheet to start
  polling. If it were trusted, "mark my rent paid" would be a JavaScript call.

---

## 4. Why a student cannot pay ₹1 for a ₹6,000 room

The classic bypass is to let the client name the amount, the student or the period, and then trust
it. None of the three is ever accepted from a caller.

`createRentOrder()` **takes no parameters at all**. There is no `amount` to tamper with, no
`studentId` to swap, no `period` to backdate. The student is the session, the period is the current
month, and the amount is read from that student's own ledger — through the RLS client, using the
same `summariseFee()` that rendered the figure they were shown, so the number on screen and the
number charged cannot drift apart.

That figure is then derived **a second time, independently, inside the database**.
`public.rz_open_intent()` recomputes the outstanding balance from `students.monthly_fee` and
`public.fee_payments` under the caller's own identity, and refuses to write the row unless the
amount the order was built for still equals what it computes. Its parameter is not an instruction;
it is a claim being checked. So even a caller that reached the RPC directly — bypassing the server
action entirely — could only ever open an order for exactly what they owe.

And the figure is checked a **third** time on the way back in: `rz_record_capture()` compares the
amount Razorpay reports capturing against `payment_intents.amount_paise`, the number this server
committed to at order time. A mismatch credits nothing.

`rz_open_intent()` is the only way a `created` row is ever written, and it is safe to expose to
`authenticated` precisely because it derives every sensitive value itself. That is what keeps the
service-role key out of the order path altogether.

---

## 5. Why the same payment cannot credit twice

Razorpay retries a webhook until it gets a `2xx`, and can deliver the same event more than once
regardless. Idempotency here is a property of the **database**, not of an `if` statement someone
could later delete:

```sql
create unique index payment_intents_payment_key
  on public.payment_intents (razorpay_payment_id)
  where razorpay_payment_id is not null;
```

`rz_record_capture()` claims a row with `where razorpay_order_id = $1 and razorpay_payment_id is
null`. Two concurrent deliveries serialise on the row lock; the second re-evaluates that predicate
after the first commits, matches zero rows, and returns `duplicate` instead of crediting again.
`rz_credit_fee()` claims the credit the same way, with `where credited_at is null`.

### Why capture and credit are two transactions

`rz_credit_fee()` credits the ledger by calling `public.wd_record_payment()` — the warden desk's
own function, with **every one of its guards intact**: the student must exist, the caller must be
authorised for the hostel, `app.hostel_writable()` must hold (Hard rule §4.4), the student must not
be checked out, the amount must be finite and in range, the date must not be in the future. Nothing
is bypassed and nothing replaces them.

One of those guards can legitimately refuse. If a subscription lapsed between the order and the
capture, `hostel_writable()` is false. Had the credit shared a transaction with the capture, that
refusal would have rolled back *the record that Razorpay took the money* — the app would forget a
real payment because a subscription expired. Split in two, the capture stands, only the credit is
outstanding, and the row lands in the reconciliation queue in §7. A recoverable state instead of a
lost one.

The webhook then returns `500`, so Razorpay retries; the retry re-enters at `rz_record_capture()`,
gets `duplicate`, and attempts the credit again. If the tenant renews, it heals with no human
involved.

---

## 6. The rest of the perimeter

**The webhook signature is the entire perimeter.** The route has to be reachable without a session,
so an unverified delivery is a `curl` command that settles anyone's rent for free.

- The HMAC is computed over `await req.text()` — the **raw bytes**. Never
  `JSON.stringify(await req.json())`: a JSON round trip changes key order, whitespace and number
  formatting, so the digest would not match what Razorpay signed, and the thing verified would no
  longer be the thing acted on.
- The comparison is `crypto.timingSafeEqual`. A `===` on hex strings returns at the first differing
  character, which leaks the length of the matching prefix — enough, over many attempts, to
  reconstruct a valid signature.
- A missing `RAZORPAY_WEBHOOK_SECRET` makes the route answer `503`. It never falls back to
  "assume genuine".
- Rejected deliveries are recorded as `payment.webhook.rejected`, which the Super Admin security
  console's suspicious-activity detector can turn into an alert.

**Nobody can write `payment_intents` through PostgREST.** RLS is on; there is a `SELECT` policy and
no `INSERT`, `UPDATE` or `DELETE` policy at all, plus an explicit
`revoke insert, update, delete … from anon, authenticated`. This is the same shape
`public.security_alerts` uses, for the same reason: a row an attacker can edit is not evidence of
anything. Students read only their own rows (`student_id = app.current_student_id()`); the warden
and owner read their hostel's, because they are the people who reconcile a payment that did not
land.

**Rate limits.** Order creation is capped at 8 per user per 15 minutes
(`lib/rate-limit.ts`), with a floor of 10 intents per hour enforced inside `rz_open_intent()` in
case the RPC is ever reached another way. Status polling is capped at 120 per 5 minutes. An
unpaid order for the same period and amount, minted in the last 15 minutes, is offered again
rather than replaced, so dismissing the modal and retrying does not mint orders.

**Every state change is audited** (`lib/audit.ts`): `payment.order.created`, `payment.captured`,
`payment.credited`, `payment.failed`, `payment.webhook.rejected`, `payment.reconcile.required`.

---

## 7. Operating it

### Is anything stuck?

Money Razorpay captured that the fee ledger has not been credited with. **This should always be
empty.**

```sql
select i.id, i.created_at, i.captured_at, i.razorpay_payment_id,
       i.amount_paise / 100.0 as amount, i.period_month,
       s.full_name, h.name as hostel
from public.payment_intents i
join public.students s on s.id = i.student_id
join public.hostels  h on h.id = i.hostel_id
where i.status = 'captured' and i.credited_at is null
order by i.captured_at;
```

A row here means the capture was recorded but `wd_record_payment()` refused. The reason is in the
audit trail:

```sql
select at, action, meta from public.audit_log
where action = 'payment.reconcile.required'
order by at desc limit 50;
```

The usual cause is an expired subscription or a student checked out between order and capture. Fix
the cause, then replay the credit as the service role:

```sql
select public.rz_credit_fee('<intent id>');
```

It is idempotent — running it on an already-credited row returns `already_credited` and changes
nothing.

### Is the webhook working at all?

If students report being charged while the app shows them unpaid, and the query above is **empty**,
the deliveries are not arriving. Check Razorpay Dashboard → Webhooks → the endpoint's delivery log,
then confirm:

1. `/api/webhooks/razorpay` is in `PUBLIC_PATHS` (§2) — otherwise every delivery gets a `307` to
   `/login`;
2. `RAZORPAY_WEBHOOK_SECRET` in the environment matches the one on the dashboard — a mismatch
   shows up as a run of `payment.webhook.rejected` rows in the audit log;
3. the endpoint is subscribed to `payment.captured`.

### Housekeeping

Abandoned checkouts leave `created` rows behind. This is the sweeper for them:

```sql
select public.rz_expire_stale_intents();   -- default: older than 1 day
```

> **Do not run this yet, and do not schedule it.** The line below used to say that a late capture
> could still claim an expired order. It cannot. `rz_record_capture()` claims only
> `status in ('created','failed')`, so a genuine capture arriving against an `expired` row is
> refused — with the misleading message `Order already settled by a different payment.`, which the
> webhook classifies as permanent and answers `200`. The resident's money is taken and the fee
> ledger never moves. Reproduced against the live database in
> [`razorpay-money-path.md`](./razorpay-money-path.md) §9 F2, which also has the fix. Nothing
> schedules this function today (`cron.job` has three jobs, none of them this one), so the problem
> is latent — running it by hand is what creates it.

It never touches a row that already carries a payment id.

---

## 8. Testing

Use test keys (`rzp_test_…`). The sheet says **"Test mode — no real money will move."** whenever
the key id is not `rzp_live_`, so nobody has to guess which environment they are in.

Razorpay cannot reach `localhost`, so on a dev machine the webhook never arrives and every payment
stops at "Payment received — it can take a minute to show on your fee ledger". That is the correct
behaviour, not a bug. To test the full path locally, expose the port with a tunnel and point a test
webhook at `https://<tunnel>/api/webhooks/razorpay`.

Razorpay's test cards are in their documentation; card `4111 1111 1111 1111` with any future expiry
and any CVV succeeds, and test UPI id `success@razorpay` succeeds.

Worth exercising deliberately:

- **Replay.** Re-send the same `payment.captured` from the dashboard. The second delivery must
  answer `already_credited` and `fee_payments.amount_paid` must not move.
- **Forgery.** `POST` the same body with a wrong `X-Razorpay-Signature`. Must be `401`, and must
  leave a `payment.webhook.rejected` row.
- **Concurrent pay.** Have a warden record a cash payment while the Checkout modal is open, then
  complete it. `rz_record_capture()` must reject the amount mismatch rather than credit.

---

## 9. Deliberate limits

- **Current month only.** Arrears from earlier months are not payable online; the period is the
  database's current month and is not a parameter. Partial payments are: the amount is whatever is
  still outstanding.
- **The mode is recorded as `upi` or `bank`.** `public.payment_mode` is
  `('cash','upi','bank')` and the warden's fee ledger renders it through a
  `Record<PaymentMode, string>`, so a new enum value would show as `undefined` there until that map
  is updated. Razorpay's actual method (`card`, `netbanking`, `wallet`, …) is kept verbatim in
  `payment_intents.method` and in the fee note, so nothing is lost. Adding an `online` mode is a
  three-file change — the enum, `PAYMENT_MODES` in `lib/types.ts`, and `MODE_LABEL` in
  `components/warden/fees-view.tsx` — and should be done as one.
- **No refunds from the app.** Refund from the Razorpay dashboard, then adjust the fee row at the
  warden desk. An automated refund path would be a second way to move money and is not worth its
  risk here.
- **`Cross-Origin-Opener-Policy: same-origin` is unchanged.** Checkout's default modal runs in an
  iframe and does not need a popup. If a bank flow is ever seen failing to open a window, that
  header — not the CSP — is the thing to look at, and relaxing it to
  `same-origin-allow-popups` is a deliberate trade, not a config tweak.

---

## 10. What was opened in the CSP, and why

`lib/security-headers.ts` gained one third-party origin set. It is the only one in the policy, and
it exists because a hosted card form cannot be self-hosted: keeping PCI scope off this application
is the entire reason to use Checkout, and that only holds if the card fields belong to Razorpay's
document rather than ours.

| Directive | Added | Consequence of removing it |
| --- | --- | --- |
| `script-src` | `https://checkout.razorpay.com` | Nothing in a modern browser — `'strict-dynamic'` makes host allowlists inert and our nonce-carrying bundle injects the script, so trust propagates. Present for CSP2-era browsers, which ignore `'strict-dynamic'` and would otherwise show a silently dead Pay button. |
| `frame-src` | `https://api.razorpay.com`, `https://checkout.razorpay.com` | **The modal never opens.** There was no `frame-src` before, so it fell back to `default-src 'self'`. |
| `connect-src` | `https://api.razorpay.com`, `https://lumberjack.razorpay.com`, `https://lumberjack-cx.razorpay.com` | Checkout cannot poll payment state; it also retries its telemetry noisily when those hosts are blocked. |
| `img-src` | `https://*.razorpay.com` | Bank and wallet logos in the loader Checkout draws in *our* document before its iframe takes over. |
| `Permissions-Policy` | `payment=(self "https://api.razorpay.com")` | Was `payment=()`. Checkout's iframe asks for `allow="payment"` on the Payment Request API paths (Google Pay, UPI intent on Android); a top-level denial kills those methods before the iframe's own attribute is considered. Scoped to Razorpay's origin — not `*`. |

Not granted, deliberately: nothing was added to `default-src`, `style-src`, `frame-ancestors` or
`form-action`. `connect-src` remains `'self'` + Supabase + the three hosts above, so the
exfiltration surface the policy exists to close is unchanged for every origin except Razorpay's
own API. If Checkout is ever switched to the redirect (`callback_url`) flow, `form-action` will
have to be widened too — again, a decision, not a tweak.
