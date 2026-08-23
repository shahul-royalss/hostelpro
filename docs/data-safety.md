# Data safety — the answer sheet

**Copy this into Play Console → App content → Data safety.** One section per question Console asks,
with the code that justifies each answer.

Every answer here was read out of the source, not assumed. The files that decide it:
`db/schema.sql`, `db/migrations/2026-08-24-payments.sql`, `lib/storage.ts`,
`lib/actions/payments.ts`, `lib/razorpay.ts`, `app/api/webhooks/razorpay/route.ts`,
`components/payments/`, `package.json`.

Companions: [`play-submission-pack.md`](./play-submission-pack.md) (the rest of the submission),
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) (the full inventory and the
retention periods), [`payments.md`](./payments.md) (how the money path works).

> **This form is a legal declaration.** An answer that is wrong in either direction is a policy
> violation: understating collection is a misrepresentation, and overstating it invites a review
> question you cannot answer from the schema. Read §1 before ticking anything.

**Last derived from the code:** 24 August 2026 — the day `payment_intents` shipped. Re-derive
whenever the schema, `lib/storage.ts` or the production dependency list changes.

---

## 1. The four definitions that decide every row

**"Collected"** = transmitted off the user's device. Everything in this app lives on a server, so
anything a user types or uploads is collected. There is no on-device-only data to exclude.

**"Shared"** = transferred to a **third party** who uses it for their own purposes. Play explicitly
**excludes transfers to a service provider** processing on your behalf, on your instructions.
Supabase, Vercel **and Razorpay** are service providers. The answer to "Is this data shared?" is
**No** on every row — see §4 for the Razorpay reasoning, which is the one a reviewer may probe.

**"Processed ephemerally"** = held in memory for the request and never written down. **Nothing here
is ephemeral** — this is a record-keeping product; persistence is the point. Answer **No**
everywhere, including for `audit_log.ip`. Nulling IP at 90 days is retention, not ephemerality.

**"Collected by your app"** includes data collected by third-party SDKs and embedded flows inside
it. That is why §3.4 works through what Razorpay Checkout does, instead of stopping at "it is not
our form".

---

## 2. The data-type table

Purposes use Play's own vocabulary. **Analytics, Advertising or marketing, Personalization and
Developer communications are never selected** — `package.json` has **34** production dependencies
and contains no analytics, telemetry, error-reporting, session-replay or ad SDK, and the merged
manifest requests no advertising ID.

`razorpay` (added with the payment feature) is a **server-side API client**. It never reaches the
browser: `lib/razorpay.ts` opens with `import "server-only"`, which makes importing it from a client
component a build error.

| Play data type | Collected | Shared | Ephemeral | Required / optional | Purpose | Where it lives in the code |
|---|---|---|---|---|---|---|
| **Personal info › Name** | **Yes** | No | No | **Required** | App functionality, Account management | `students.full_name` (NOT NULL), `users.full_name` (NOT NULL), `students.guardian_name`, `visitors.visitor_name` (NOT NULL). Also sent to Razorpay as Checkout `prefill.name` — §3.3 |
| **Personal info › Email address** | **Yes** | No | No | Optional | App functionality, Account management | `users.email`, `students.email` (both nullable). Staff sign in by email; **students sign in by phone**, mapped to a synthetic email in Supabase Auth. Also `prefill.email` — §3.3 |
| **Personal info › Phone number** | **Yes** | No | No | **Required** | App functionality, Account management | `students.phone` (NOT NULL — it is the student's login identifier), `students.guardian_phone`, `users.phone`, `visitors.visitor_phone`. Also `prefill.contact` — §3.3 |
| **Personal info › Address** | **Yes** | No | No | Optional | App functionality | `students.permanent_address` (nullable), `hostels.address` |
| **Personal info › User IDs** | **Yes** | No | No | **Required** | App functionality, Account management, Fraud prevention & security | Supabase Auth `uid`, `users.id`, `students.id`, `hostel_id`, role. Plus `payment_intents.razorpay_order_id` and `razorpay_payment_id` — Razorpay's own transaction identifiers |
| **Personal info › Other info** | **Yes** | No | No | Optional | App functionality | `students.id_proof_type` — the *kind* of government ID a resident holds. See §6 |
| Personal info › Race and ethnicity | No | — | — | — | — | No such column exists |
| Personal info › Political or religious beliefs | No | — | — | — | — | No such column exists |
| Personal info › Sexual orientation | No | — | — | — | — | No such column exists |
| **Financial info › Purchase history** | **Yes** | No | No | **Required** | App functionality, **Fraud prevention, security and compliance** | `fee_payments` (`amount_due`, `amount_paid`, `status`, `paid_on`, `mode`, `notes`), `students.monthly_fee`, and **all of `public.payment_intents`** — see §3.1. Fraud prevention is a genuine second purpose here: `razorpay_payment_id` is stored under a unique index precisely so the same payment can never credit twice |
| **Financial info › User payment info** | **No** | — | — | — | — | **Do not tick.** No payment instrument reaches this server or this database. See §3.2 — the single most consequential answer on the form |
| Financial info › Credit score | No | — | — | — | — | No such column exists |
| Financial info › Other financial info | No | — | — | — | — | Play defines this as salary, debts and similar. An outstanding rent balance is a transaction record and is disclosed under Purchase history |
| **Photos and videos › Photos** | **Yes** | No | No | Optional | App functionality | `students.photo_url`, `students.id_proof_url`, `complaints.photo_url`, `fee_payments`/`expenses` receipts. Buckets `student-docs`, `complaint-photos`, `receipts` — all **private** |
| Photos and videos › Videos | No | — | — | — | — | `lib/storage.ts` `ALLOWED` permits only `image/jpeg`, `image/png`, `image/webp`, `application/pdf`. No video type is accepted |
| **Files and docs** | **Yes** | No | No | Optional | App functionality | Same buckets: `application/pdf` is accepted for `student-docs` and `receipts`, so an ID proof or a receipt uploaded as a PDF is a document, not a photo. See §6 |
| **App activity › App interactions** | **Yes** | No | No | **Required** | Fraud prevention, security and compliance | `audit_log` (`action`, `target_type`, `target_id`, `actor_user_id`, `at`), `security_alerts`. Now includes six payment events — `payment.order.created`, `payment.captured`, `payment.credited`, `payment.failed`, `payment.webhook.rejected`, `payment.reconcile.required` (`lib/audit.ts`) |
| **App activity › Other user-generated content** | **Yes** | No | No | Optional | App functionality | `complaints.title`/`description`/`resolution_note`, `complaint_events.note`, `leaves.reason`, `announcements.body`, `tasks.description`, `fee_payments.notes`, `expenses.note`, `visitors.relation` |
| App activity › In-app search history | No | — | — | — | — | Not recorded |
| App activity › Installed apps | No | — | — | — | — | The manifest cannot see other packages (no `QUERY_ALL_PACKAGES`) |
| **Device or other IDs** | **Yes** | No | No | **Required** | Fraud prevention, security and compliance | `audit_log.ip`, `audit_log.user_agent`, `security_alerts.ip`, plus Vercel access logs. Razorpay Checkout additionally runs its own device/session telemetry inside its iframe during a payment — §3.4 |
| Location (approximate / precise) | **No** | — | — | — | — | No location permission in the manifest; IP is **never** used for geolocation anywhere in the code |
| Messages (email / SMS / in-app) | **No** | — | — | — | — | Work-item text, declared under Other user-generated content. Reasoning in the submission pack §2.6 |
| Health and fitness | **No** | — | — | — | — | No health feature and no health column. Reasoning in the submission pack §2.7 |
| **App info and performance › Crash logs** | **No** | — | — | — | — | No crash reporter of any kind. Android Vitals is collected by Google Play itself, not by the developer, and does not need declaring |
| App info and performance › Diagnostics | No | — | — | — | — | No telemetry SDK |
| Audio files | No | — | — | — | — | No audio MIME type accepted |
| Calendar | No | — | — | — | — | No calendar access |
| Contacts | No | — | — | — | — | No `READ_CONTACTS`; guardian and visitor phone numbers are typed in by staff, not read from the device address book |
| Web browsing history | No | — | — | — | — | Not recorded |

---

## 3. Payments — the section to get exactly right

The app now takes money. That changes four rows above and none of the others, and being imprecise
here in **either** direction is what causes a strike.

### 3.1 What `public.payment_intents` actually stores

The complete column list, from `db/migrations/2026-08-24-payments.sql` §2:

```
id                  uuid
hostel_id           uuid  -> hostels(id)   on delete cascade
student_id          uuid  -> students(id)  on delete cascade
period_month        text  'YYYY-MM'
amount_paise        bigint           integer minor units; money is never a float on this path
currency            text  check (currency = 'INR')
razorpay_order_id   text  'order_' + base62
razorpay_payment_id text  'pay_'   + base62, null until capture
method              text  'upi' | 'card' | 'netbanking' | 'wallet' ...   display only
status              enum  'created' | 'captured' | 'failed' | 'expired'
failure_reason      text  provider-generated, left(..., 200)
captured_at         timestamptz
credited_at         timestamptz
created_by          uuid  -> users(id)
created_at          timestamptz
updated_at          timestamptz
```

So: **an amount, a currency, two Razorpay reference ids, and a method label.** That is a record of a
transaction that happened. It is **Purchase history**.

**What is not there, and cannot be:** no card number, no expiry, no CVV, no cardholder name, no UPI
VPA, no bank account or IFSC, no token, no vault reference. There is no column for any of them and
no code path that would have one to write.

Two independent facts back this up, and both are worth quoting to a reviewer:

1. **Nothing else is even parsed.** `app/api/webhooks/razorpay/route.ts` reads exactly seven fields
   off a verified delivery — `event`, and from `payload.payment.entity`: `id`, `order_id`, `amount`,
   `currency`, `method`, `error_description`, `error_reason`. Every other field Razorpay sends is
   discarded with the rest of the parsed object.
2. **Nothing can write the table from outside.** `payment_intents` has RLS on with a **SELECT policy
   only**, plus `revoke insert, update, delete on public.payment_intents from anon, authenticated`.
   Every write goes through a `security definer` function, and the three settlement ones re-check
   `app.is_service_role()` in their own bodies.

`failure_reason` is the one free-text column. It holds Razorpay's own `error_description` or
`error_reason`, truncated to 200 characters — provider-generated text such as "Payment failed due to
insufficient funds", not anything a user typed.

### 3.2 "User payment info" — answer No, and know why

Play's **User payment info** means payment instruments: card numbers, bank account numbers, payment
credentials. **NIVORA collects none of them, at any layer.**

The card and UPI fields belong to **Razorpay's document, not ours**. Checkout renders its form in an
iframe on `checkout.razorpay.com`; `lib/security-headers.ts` grants `frame-src` for exactly that
reason, and its comment states the point plainly — keeping PCI scope off this application only works
if the card fields are Razorpay's. Our origin never sees a keystroke of it. You cannot collect, and
therefore cannot declare, data your code has no access to.

**Do not tick it out of caution.** Ticking it states that the app stores payment instruments, which
invites scrutiny that cannot be satisfied from the schema, because there is nothing there to show.
**Tick Purchase history instead** — a record of transactions that occurred, which is exactly what
`fee_payments` plus `payment_intents` are.

**When this flips to Yes:** the day any card, UPI or bank field is rendered by our own form, or a
saved-card, token, mandate or auto-debit flow is added. None of that exists today — there is no
`customer`, `token`, `subscription` or `mandate` call anywhere in `lib/`, and the only Razorpay API
call in the whole codebase is `razorpayClient().orders.create(...)` in `lib/actions/payments.ts`.

### 3.3 What NIVORA does send to Razorpay

Answer this honestly if asked, because it is more than nothing:

| Sent | From | What it is |
|---|---|---|
| `amount`, `currency: "INR"` | `orders.create()` in `lib/actions/payments.ts` | The server's figure, derived from the student's own ledger |
| `receipt: rent_<YYYY-MM>_<first 8 chars of student uuid>_<base36 timestamp>` | same | Deliberately no PII — a truncated UUID is a lookup key for us and meaningless to anyone else |
| `notes: { purpose: "hostel_rent", period }` | same | For a human reading the Razorpay dashboard. Nothing on the settlement path ever reads it back |
| `name` (the hostel's name), `description` (`"<Month YYYY> rent"`) | Checkout options in `components/payments/pay-rent-sheet.tsx` | Branding on the modal |
| `prefill: { name, email, contact }` | same, from `RentOrder.prefill` | **The student's own `full_name`, `email` and `phone`**, so they do not have to retype them |

So Razorpay receives the payer's name, email and phone. That is a transfer **to a service
provider** — see §4 — and it belongs in the privacy policy as a named sub-processor, not in the
"Shared" column.

### 3.4 Razorpay Checkout's own telemetry

Checkout is a third-party script and it does run its own device and session telemetry during a
payment (`lumberjack.razorpay.com`). Two facts bound it:

- **It is not granted `connect-src` in our document.** `lib/security-headers.ts` allows only
  `https://api.razorpay.com` to `connect-src`, with the comment "lumberjack telemetry deliberately
  NOT granted". The loader Checkout draws in *our* page cannot reach it.
- **Inside its own iframe our CSP does not apply** — a cross-origin frame carries its own policy.
  Razorpay's telemetry from within its modal is Razorpay's, serving the payment's own fraud and
  operational purposes. **NIVORA receives none of it.**

Declaration consequence: no new row is needed. It sits under the existing **Device or other IDs /
Fraud prevention, security and compliance** row, whose evidence column names it. **Do not add
Analytics as a purpose** — NIVORA performs no analytics and receives no analytics data.

One more bound worth knowing: the Razorpay CSP grants are **scoped to `/student`**
(`needsRazorpay()` in `lib/security-headers.ts` returns true only for `/student` and below). No
other page in the app — including every screen that renders resident PII — can load Checkout at all.

---

## 4. Razorpay: service provider, not third party

Play distinguishes **"shared with third parties"** from **"handled by a service provider"**. Tick
the wrong one and you have either misled users or invited a question you cannot close.

**Razorpay is a service provider. Answer "No" to shared.** Two independent grounds, either
sufficient on its own:

1. **What we send, we send on our instruction.** Razorpay processes the amount, the order and the
   payer's prefill details in order to collect a payment *NIVORA asked it to collect*, against an
   order *NIVORA created*, and reports the result back. That is processing on the developer's
   behalf, on the developer's instructions — Play's own definition of a service provider. A payment
   processor is the textbook case; GDPR and CCPA reach the same conclusion about a merchant's PSP.
2. **What we never held, we cannot share.** The card number and the UPI ID are typed into Razorpay's
   own document. They never enter NIVORA's process, memory or database. "Sharing" presupposes
   possession.

**The counter-argument, stated so nobody is ambushed by it:** Razorpay is a regulated entity with
statutory duties of its own — KYC, transaction-record retention, fraud and AML obligations it cannot
be instructed out of. Does that make it a third party using data for its own purposes?

**No, and here is why:** a service provider having its own legal obligations is normal and does not
convert it into a third party. Supabase is subject to legal process too. Play's question is about a
recipient that uses the data **for its own commercial purposes** — advertising, resale, its own
product. Razorpay does not, for this data, and the answer stays No.

**What makes answering No safe is the privacy policy.** Play's position is that service-provider
transfers are disclosed in the policy, not in the Shared column. So:

> **Blocking:** `/legal/privacy` must name **Razorpay** as a sub-processor, alongside Supabase and
> Vercel, and say what it receives. As of this writing it does not — see §8.

### 4.1 One fact to establish before the first live key

There is exactly **one** `RAZORPAY_KEY_ID` for the whole application, so every hostel's rent is
collected into **one merchant account**. There is no Razorpay Route, no `transfers`, no split
settlement and no payout logic anywhere in the code — verified by grep across
`lib/actions/payments.ts`, `lib/razorpay.ts`, `app/api/webhooks/razorpay/route.ts` and
`components/payments/`.

**Whose merchant account it is decides a compliance question of which Play is not even the hardest
part.** If the money settles into the *hostel operator's* own Razorpay account, NIVORA is software
and nothing more. If it settles into *NIVORA's* account and NIVORA then pays the hostels, NIVORA is
handling other people's money — Payment Aggregator territory under the RBI's PA/PG directions, and a
different product with a different licence.

**This is not a Data safety answer.** It is the thing to settle before the first live key is issued,
and it is why the Financial features wording in §5 is hedged the way it is.

---

## 5. Payments and the Play Payments policy

The question a reviewer is most likely to ask: *"Your app takes money and does not use Google Play
Billing. Why is that allowed?"*

**Because hostel rent is a real-world service, and Play's Payments policy requires it to be paid
outside Play Billing rather than merely permitting it.**

Play's billing requirement applies to **digital goods and services consumed within the app**.
Payments for **physical goods and real-world services** must use an alternative payment method —
Play lists exactly this category: physical goods, one-to-one real-world services, transport, food
delivery, and accommodation.

Hostel rent is as real-world as the category gets:

- The thing bought is **a bed in a physical building for a calendar month**. `payment_intents` binds
  every payment to a `student_id`, a bed-holding resident record, and a `period_month`.
- It is **consumed off-device**. Nothing in the app is unlocked, upgraded or enabled by paying —
  verified: no code path gates a feature on `payment_intents.status` or `credited_at`. The only
  thing a successful payment changes is a row in `fee_payments`, which is a ledger entry.
- **The money is the hostel's, not NIVORA's.** The app is collecting what the resident already owes
  their landlord under a tenancy that exists outside the app.

**The contrast, and state it plainly if asked:** an owner paying NIVORA a platform subscription
*would* be a digital service consumed in the app, and on Android that is Google Play Billing
territory. `docs/payments.md` puts that flow explicitly out of scope — *"Owners paying their
platform subscription is a separate flow and is not built here"* — and `public.subscriptions` is a
record the NIVORA administrator maintains, with no in-app purchase path. **Keep it that way, or
bring in Play Billing when it changes.** An in-app "renew your NIVORA subscription" button that
charged through Razorpay would be a Payments-policy violation on the day it shipped.

Consequences for the declarations — all unchanged from before payments existed, but now for
articulable reasons rather than by default:

| Console question | Answer | Reason |
|---|---|---|
| **In-app purchases** | **No** | The label reflects Google Play Billing products. There is no Play Billing library in the bundle and no Play product to sell. Rent is an external real-world payment, which that badge does not describe |
| **Financial features** | **"My app doesn't provide any financial features."** | The list covers financial *products and services* — lending, banking or e-money, insurance, investments, crypto, debt management, money management or planning, tax. Accepting payment for the hostel's own service is none of them, exactly as an e-commerce app taking card payments is none of them. NIVORA issues no credit, holds no balance and moves no money between people. **Revisit if §4.1 resolves toward NIVORA holding funds** |
| **Content rating › "Can users purchase digital goods?"** | **No** | Rent is a real-world service, not a digital good. If the questionnaire separately asks about real-world purchases, answer **that** one Yes — it is trivially verifiable by opening the fee card |

---

## 6. Government ID — no box exists, declare it anyway

**Play's Data safety form has no "Government ID" data type.** That is a gap in the form, not
permission to stay quiet, and NIVORA holds exactly this: `students.id_proof_type` plus a scan at
`students.id_proof_url` in the private `student-docs` bucket.
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §4.4 calls it "the highest-value
data in the system".

Declare it in three places:

1. **Photos** — an ID scanned as JPEG/PNG/WEBP.
2. **Files and docs** — the same ID uploaded as a PDF. Both paths are open in `lib/storage.ts`, so
   both types must be ticked. Most people tick only Photos and miss this.
3. **Personal info › Other info** — `id_proof_type` is a structured personal attribute that is
   neither a photo nor a file.

Then say it in plain words in the privacy policy: *this app stores identity documents.*

---

## 7. Security practices section

| Question | Answer | Evidence |
|---|---|---|
| Is all user data encrypted in transit? | **Yes** | TLS to Vercel and to Supabase throughout; HSTS and a nonce-based CSP in `middleware.ts`; the manifest sets no `usesCleartextTraffic`. The payment path adds no exception — Checkout loads over HTTPS from `checkout.razorpay.com` and the webhook is HTTPS-only |
| Do you provide a way for users to request that their data be deleted? | **Yes** | `/legal/account-deletion` is live (HTTP 200 signed out, verified), backed by the erasure runbook in [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.3. See §7.1 for what deletion does to payment records |
| Has your app been independently reviewed against a global security standard? | **No** | `SECURITY.md` is a thorough internal review. It is not a third-party audit, and claiming otherwise in Console is a misrepresentation |
| Committed to follow the Play Families Policy? | **No** | Not a children's app — submission pack §4 |

### 7.1 What deletion does to payment records — the answer that has to hold

A hostel has an accounting duty it cannot waive, so **payment records survive an erasure request.**
Play accepts that. What Play does not accept is a deletion page that promises total erasure and then
does not deliver it. Say the following, and make sure `/legal/account-deletion` says the same.

**Deleted with the resident.** `students`, `users`, and everything that cascades from them.
`payment_intents.student_id` is `references public.students(id) on delete cascade`, so **if the
student row is deleted, their payment intents go with it** — exactly like `fee_payments`.

**Retained, with the person taken out of it.** When the accounting duty means the ledger must
survive, the resolution is [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.4:
**anonymise instead of delete.** Here `payment_intents` behaves unusually well — go back to the
column list in §3.1 and notice what is absent. There is **no name, no phone, no email and no address
in the table at all.** It is UUIDs, money, dates, two Razorpay reference ids and a method label.
Once `students` and `users` are anonymised per §6.4, the payment rows carry nothing that identifies
a person.

**For how long.** The same period as the rest of the fee ledger: **the tenant's statutory accounting
duty, default 8 years** ([`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §5.2).
Do not invent a shorter one for `payment_intents` — it is part of the same financial record as the
`fee_payments` row it credited, and splitting them would leave a credit with no evidence behind it.

**Abandoned attempts are marked, not removed.** `rz_expire_stale_intents()` moves a `created` row
that never went anywhere to `expired` after a day (`docs/payments.md` §7). It **marks**; it does not
delete. An expired row is still a retained record on the schedule above.

**What NIVORA cannot reach, and must say so.** Razorpay keeps its own record of the transaction
under its own regulatory retention duty. An erasure request to NIVORA cannot delete it. This is the
same honest boundary as backups in
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.5, and it belongs on the
deletion page next to them.

---

## 8. Cross-checks before you submit

A Data safety form that contradicts the privacy policy is itself a violation. These four are
**blocking**, and three of them currently **fail**, because the legal pages were written before
payments shipped.

| # | Must be true | Status |
|---|---|---|
| 1 | `/legal/privacy` names **Razorpay** as a sub-processor and says what it receives | **FAILING** — the page says *"there is no payment processor"* and lists three providers (`app/legal/privacy/page.tsx`) |
| 2 | `/legal/privacy` does not claim payments are offline-only | **FAILING** — *"Fee payments happen offline"* and *"NIVORA never takes, holds or moves money"*, under "What is never collected" |
| 3 | `/legal/account-deletion` names the payment record among what is retained, and Razorpay among what cannot be reached | **PARTIAL** — it already covers fee records and the 8-year duty, but repeats *"no payment processor"* |
| 4 | `/legal/terms` §9 reflects that rent can now be collected in-app | **FAILING** — the section is titled "Payments are recorded, not processed" and states *"NIVORA is not a payment service"* |

Those four pages are **outside this document's scope** and belong to whoever owns `app/legal/`. Do
not paste the privacy-policy URL into Console until they are fixed: Google fetches that page, and a
reviewer comparing it to this form finds the contradiction in under a minute.

Two more, non-blocking but worth closing:

5. [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §4.1's inventory does not list
   `payment_intents`, and its §7 sub-processor table still says *"That is the complete list"* with
   Razorpay absent. The retention **period** is settled (§7.1 above); the **inventory row** is not
   yet written.
6. `.env.example` declares `NEXT_PUBLIC_RAZORPAY_KEY_ID`, but `lib/razorpay.ts` reads
   `RAZORPAY_KEY_ID` and `docs/payments.md` §1 says explicitly that it must **not** be a
   `NEXT_PUBLIC_` variable. Anyone setting up from `.env.example` gets a permanently dead Pay button
   and the "Online payment isn't set up yet" message.

---

## 9. Ticking order in Console

1. **Data collection and security** — confirm the app collects data; answer the four §7 questions.
2. **Data types** — work down §2 row by row. Slow down on the four rows payments changed: **Name**,
   **Phone number** and **Email address** (all now also reach Razorpay as prefill), and **Financial
   info › Purchase history** (now includes `payment_intents`).
3. **User payment info** — leave it **unticked**. Re-read §3.2 before deciding otherwise.
4. **Shared** — **No** on every row. Re-read §4 before deciding otherwise.
5. **Government ID** — three ticks, per §6.
6. **Deletion URL** — paste `https://hostelpro-three.vercel.app/legal/account-deletion`, but only
   after §8 rows 1–4 are fixed and deployed.
7. **Preview the store's Data safety section** before publishing. It is what users read, and it is
   the artefact a policy complaint is measured against.
