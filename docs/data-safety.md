# Data safety — the answer sheet

**Copy this into Play Console → App content → Data safety.** One section per question Console asks,
with the code that justifies each answer.

Every answer here was read out of the source, not assumed. The files that decide it:
`db/schema.sql`, `db/migrations/2026-08-24-payments.sql`,
`db/migrations/2026-09-02-payment-refunds.sql`,
`db/migrations/2026-09-12-notifications-and-rent-due.sql`, `lib/storage.ts`,
`lib/actions/payments.ts`, `lib/razorpay.ts`, `app/api/webhooks/razorpay/route.ts`,
`components/payments/`, `supabase/functions/push-send/index.ts`,
`nivora_app/lib/core/notify/push_service.dart`, `package.json`, and for the Android payment path
`nivora_app/lib/features/payments/pay_rent.dart`, `nivora_app/android/app/src/main/AndroidManifest.xml`,
`supabase/functions/razorpay-order/index.ts`, `supabase/functions/_shared/razorpay.ts` and
`public.rz_open_intent`.

Companions: [`play-submission-pack.md`](./play-submission-pack.md) (the rest of the submission),
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) (the full inventory and the
retention periods), [`payments.md`](./payments.md) (how the money path works). Where the pack's
own Data safety table, its payment notes or its settlement section disagree with this sheet, this
sheet is the one to copy into Console. Treat the disagreement as a defect in the pack.

> **This form is a legal declaration.** An answer that is wrong in either direction is a policy
> violation: understating collection is a misrepresentation, and overstating it invites a review
> question you cannot answer from the schema. Read §1 before ticking anything.

**Last derived from the code:** 13 September 2026 — the day the answers were corrected for
Razorpay's native Android Checkout SDK, which runs inside the app's own process, and the settlement
facts in §4.1 were re-read from the production database, and push moved behind the consent gate
(before that, 12 September 2026, the day push notifications shipped and `push_devices` appeared;
and 24 August 2026, the day `payment_intents` shipped). Re-derive whenever the schema, `lib/storage.ts`, the push path, the
payment SDK, the production dependency list or any hostel's payout columns change. On 14 September
2026 the package and build references were updated for the new Play Console app, `com.nivorasr.app`,
whose upload is versionCode 6 (until 2026-09-13 the listing was `com.srnivora.app`). No answer
changed.

---

## 1. The four definitions that decide every row

**"Collected"** = transmitted off the user's device. Everything in this app lives on a server, so
anything a user types or uploads is collected. There is no on-device-only data to exclude.

**"Shared"** = transferred to a **third party** who uses it for their own purposes. Play explicitly
**excludes transfers to a service provider** processing on your behalf, on your instructions.
Supabase, Vercel, **Razorpay and Google** are service providers — Google because Firebase Cloud
Messaging receives the device token and the notification text in order to deliver a notification
NIVORA asked it to deliver. The answer to "Is this data shared?" is **No** on every row — see §4
for the Razorpay reasoning, which is the one a reviewer may probe, and §3.5 for Google's.

**"Processed ephemerally"** = held in memory for the request and never written down. **Nothing here
is ephemeral** — this is a record-keeping product; persistence is the point. Answer **No**
everywhere, including for `audit_log.ip`. Nulling IP at 90 days is retention, not ephemerality.

**"Collected by your app"** includes data that libraries and SDKs inside the app transmit off the
device, "irrespective of whether data is transmitted to you or a third-party server" (Play Console
Help, *Provide information for Google Play's Data safety section*,
support.google.com/googleplay/android-developer/answer/10787469). The recipient does not matter;
what matters is that code shipped in the app sent it. That is why §3.2 and §3.4 work through what
Razorpay's Android Checkout SDK does, instead of stopping at "it is not our form" — the Android app
opens that SDK inside its own process, so what it transmits is collected by the app.

---

## 2. The data-type table

Purposes use Play's own vocabulary. **Analytics, Advertising or marketing, Personalization and
Developer communications are never selected** — `package.json` has **34** production dependencies
and contains no analytics, telemetry, error-reporting, session-replay or ad SDK, and the Android
manifest removes the advertising-ID permission explicitly. That removal was checked on the versionCode 4
build artifacts by a check that also requires `INTERNET` as a positive control
(`docs/play-technical-compliance.md` §2). Those artifacts were built for the abandoned
`com.srnivora.app` listing. The upload is now versionCode 6 of `com.nivorasr.app`, and the check has
to be run on it.

`razorpay` (added with the payment feature) is a **server-side API client**. It never reaches the
browser: `lib/razorpay.ts` opens with `import "server-only"`, which makes importing it from a client
component a build error. **The Android app is different.** It depends on `razorpay_flutter`, which
bundles Razorpay's native Checkout SDK (`com.razorpay`, pinned to `checkout:1.6.41` in
`nivora_app/android/build.gradle.kts`) and runs it in the app's own process. It is still not an
analytics or ad SDK, but it does collect data in Play's sense, and four rows below declare it:
**User payment info** and **Installed apps** (both changed to Yes for it), **App interactions** (App
functionality added for it) and **Device or other IDs** (already Yes; its evidence names the SDK's
telemetry).

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
| **Financial info › Purchase history** | **Yes** | No | No | **Required** | App functionality, **Fraud prevention, security and compliance** | `fee_payments` (`amount_due`, `amount_paid`, `status`, `paid_on`, `mode`, `notes`), `students.monthly_fee`, and **all of `public.payment_intents` and `public.payment_refunds`** — see §3.1. Fraud prevention is a genuine second purpose here: `razorpay_payment_id` is stored under a unique index precisely so the same payment can never credit twice, and `razorpay_refund_id` under another so the same refund can never reverse the ledger twice |
| **Financial info › User payment info** | **Yes** | No | No | Optional | App functionality, **Fraud prevention, security and compliance** | **Tick it — this used to say "Do not tick", and that was wrong for Android.** The Razorpay Checkout SDK, opened in-process by `nivora_app/lib/features/payments/pay_rent.dart`, handles the card number, expiry, CVV or UPI ID the resident types and transmits it to Razorpay. Still no payment instrument reaches NIVORA's servers or database. Optional because rent can always be paid to the warden in cash. See §3.2 — the single most consequential answer on the form |
| Financial info › Credit score | No | — | — | — | — | No such column exists |
| Financial info › Other financial info | No | — | — | — | — | Play defines this as salary, debts and similar. An outstanding rent balance is a transaction record and is disclosed under Purchase history |
| **Photos and videos › Photos** | **Yes** | No | No | Optional | App functionality | `students.photo_url`, `students.id_proof_url` — in the Android app a warden adds a new resident's photo and ID proof at registration, from the camera or the photo picker (`nivora_app/lib/features/warden/actions/register_student_sheet.dart:116-117`, `:324-339`). `fee_payments`/`expenses` receipts. `complaints.photo_url` is not written by the Android app: the resident app has no complaint photo field (`nivora_app/lib/features/student/raise_complaint_sheet.dart:28-30`). Buckets `student-docs`, `complaint-photos`, `receipts` — all **private** |
| Photos and videos › Videos | No | — | — | — | — | `lib/storage.ts` `ALLOWED` permits only `image/jpeg`, `image/png`, `image/webp`, `application/pdf`. No video type is accepted |
| **Files and docs** | **Yes** | No | No | Optional | App functionality | Same buckets: `application/pdf` is accepted for `student-docs` and `receipts`, so an ID proof or a receipt uploaded as a PDF is a document, not a photo. See §6 |
| **App activity › App interactions** | **Yes** | No | No | **Required** | **App functionality**, Fraud prevention, security and compliance | App functionality added 2026-09-13: while a payment is open, the in-process Razorpay SDK reports its own checkout-session events to Razorpay in order to run the payment — §3.4. The existing security purpose rests on `audit_log` (`action`, `target_type`, `target_id`, `actor_user_id`, `at`), `security_alerts`. Now includes ten payment events — `payment.order.created`, `payment.captured`, `payment.credited`, `payment.failed`, `payment.webhook.rejected`, `payment.reconcile.required`, and the four refund events `payment.refund.pending`, `payment.refund.processed`, `payment.refund.failed`, `payment.refund.reversed` (`lib/audit.ts`) |
| **App activity › Other user-generated content** | **Yes** | No | No | Optional | App functionality | `complaints.title`/`description`/`resolution_note`, `complaint_events.note`, `leaves.decision_note` (a warden's approve or reject note, written from the Android warden app — `nivora_app/lib/features/warden/data/warden_repository.dart:484-491`), `announcements.body`, `tasks.description`, `fee_payments.notes`, `expenses.note`, `visitors.relation`. `leaves.reason` is not typed in the Android app, which has no resident leave feature; its only `leaves` access is the warden's list and decision (`warden_repository.dart:452-499`) |
| App activity › In-app search history | No | — | — | — | — | Not recorded |
| **App activity › Installed apps** | **Yes** | No | No | Optional | App functionality | **Changed from No on 2026-09-13.** The old reason — no `QUERY_ALL_PACKAGES` — was true but incomplete: `AndroidManifest.xml` declares a `<queries>` intent for the `upi:` scheme, and the Razorpay SDK resolves it to find which UPI apps (GPay, PhonePe, Paytm and so on) are installed, so it can offer them in the sheet. Visibility is limited to apps that handle `upi:`. Optional because it only happens when a resident opens a payment — §3.4 |
| **Device or other IDs** | **Yes** | No | No | **Required** | App functionality; fraud prevention, security and compliance | `audit_log.ip`, `audit_log.user_agent`, `security_alerts.ip`, plus Vercel access logs. **`public.push_devices.token` — the FCM registration token — since 2026-09-12; §3.5.** Razorpay Checkout additionally runs its own device and session telemetry during a payment — inside its iframe on the web, and inside the app's own process on Android — §3.4 |
| Location (approximate / precise) | **No** | — | — | — | — | No location permission in the manifest; IP is **never** used for geolocation anywhere in the code |
| Messages (email / SMS / in-app) | **No** | — | — | — | — | Work-item text, declared under Other user-generated content. Reasoning in the submission pack §2.6 |
| Health and fitness | **No** | — | — | — | — | No health feature and no health column. Reasoning in the submission pack §2.7 |
| **App info and performance › Crash logs** | **No** | — | — | — | — | No crash reporter of any kind. Android Vitals is collected by Google Play itself, not by the developer, and does not need declaring |
| App info and performance › Diagnostics | No | — | — | — | — | No telemetry SDK of NIVORA's. Razorpay's own checkout-session telemetry during a payment is declared under Device or other IDs and App interactions — §3.4 |
| Audio files | No | — | — | — | — | No audio MIME type accepted |
| Calendar | No | — | — | — | — | No calendar access |
| Contacts | No | — | — | — | — | No `READ_CONTACTS`; guardian and visitor phone numbers are typed in by staff, not read from the device address book |
| Web browsing history | No | — | — | — | — | Not recorded |

---

## 3. Payments — the section to get exactly right

The app now takes money. That bears on nine rows above and none of the others. Five because of what
NIVORA itself sends and stores: **Name**, **Email address** and **Phone number** (Checkout prefill,
§3.3), **User IDs** (`razorpay_order_id`, `razorpay_payment_id`) and **Purchase history** (§3.1).
Four because of what Razorpay's Android SDK does inside the app (§3.2, §3.4): **User payment info**
and **Installed apps** (changed to Yes), **App interactions** (App functionality added; its ten
payment audit events are NIVORA's own) and **Device or other IDs** (the SDK's telemetry, under an
answer that was already Yes). Being imprecise here in **either** direction is what causes a strike.

### 3.1 What `public.payment_intents` and `public.payment_refunds` actually store

Take `payment_intents` first. Its complete column list, from
`db/migrations/2026-08-24-payments.sql` §2:

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

1. **Nothing else is even parsed.** `app/api/webhooks/razorpay/route.ts` reads the event name and
   fields off two entities, and nothing else. From `payload.payment.entity`, **seven**: `id`,
   `order_id`, `amount`, `currency`, `method`, `error_description`, `error_reason`. From
   `payload.refund.entity`, on the refund events only, **six**: `id`, `payment_id`, `amount`,
   `currency`, `error_description`, `speed_processed`. `status` is declared on both interfaces and
   read from neither — a refund's state is taken from the event name, not from the body. Every
   other field Razorpay sends is discarded with the rest of the parsed object.
2. **Nothing can write the table from outside.** `payment_intents` has RLS on with a **SELECT policy
   only**, plus `revoke insert, update, delete on public.payment_intents from anon, authenticated`.
   Every write goes through a `security definer` function, and the three settlement ones re-check
   `app.is_service_role()` in their own bodies.

`failure_reason` is the one free-text column. It holds Razorpay's own `error_description` or
`error_reason`, truncated to 200 characters — provider-generated text such as "Payment failed due to
insufficient funds", not anything a user typed.

**The second financial table.** A refunded payment has to stop counting as paid, so
`db/migrations/2026-09-02-payment-refunds.sql` §2 adds a child row per refund. Its complete column
list:

```
id                  uuid
intent_id           uuid  -> payment_intents(id) on delete cascade
hostel_id           uuid  -> hostels(id)         on delete cascade
student_id          uuid  -> students(id)        on delete cascade
period_month        text  'YYYY-MM'
razorpay_refund_id  text  'rfnd_' + base62, unique index — the idempotency constraint
razorpay_payment_id text  'pay_'  + base62, the payment being refunded
amount_paise        bigint           Razorpay's figure, capped at what the payment captured
currency            text  check (currency = 'INR')
status              enum  'pending' | 'processed' | 'failed'
speed               text  'normal' | 'optimum' | 'instant'   display only
failure_reason      text  provider-generated, left(..., 200)
processed_at        timestamptz
reversed_at         timestamptz      null until fee_payments actually came down
reversed_amount     numeric(10,2)
created_at          timestamptz
updated_at          timestamptz
```

The same answer as above, for the same reason: an amount, a currency, two Razorpay reference ids, a
speed label and dates. **No card number, no expiry, no CVV, no cardholder name, no UPI VPA, no bank
account or IFSC, no token, no vault reference** — there is no column for any of them, and the
webhook does not parse one to write. It carries the same two guards as `payment_intents`: RLS with a
**SELECT policy only** plus `revoke insert, update, delete on public.payment_refunds from anon,
authenticated`, and both writing functions re-check `app.is_service_role()` in their own bodies. It
is **Purchase history**, exactly as `payment_intents` is.

### 3.2 "User payment info" — answer Yes, and know why

> **This section used to say the opposite** — "answer No", "do not tick it". That reasoning was
> built on the web app, where it holds, and was carried over to Android, where it does not. It was
> corrected on 2026-09-13. The reason is below; the answer is **Yes, not shared, optional**.

Play's **User payment info** means information about a user's financial accounts — card numbers,
bank account numbers, payment credentials. Two platforms, two different facts:

**On the web, NIVORA's code never touches it.** The card and UPI fields belong to **Razorpay's
document, not ours**. Checkout renders its form in an iframe on `checkout.razorpay.com`;
`lib/security-headers.ts` grants `frame-src` for exactly that reason, and its comment states the
point plainly — keeping PCI scope off this application only works if the card fields are Razorpay's.
Our origin never sees a keystroke of it. The Data safety form describes the Android app, so this
fact alone does not decide the answer; it is recorded because the privacy policy covers both.

**On Android, the checkout runs inside the app.** `nivora_app/lib/features/payments/pay_rent.dart`
creates a `Razorpay()` instance from `razorpay_flutter` and calls `razorpay.open(...)`. That opens
Razorpay's **native Android Checkout SDK** in the app's own process, not a web page in a frame. (The
versionCode 4 AAB carries it: its dex holds 318 `Lcom/razorpay/` type references, and its manifest
declares `com.razorpay.CheckoutActivity`.) While the sheet is open, the SDK renders
the card and UPI fields, handles what the resident types into them, and transmits it to Razorpay.
Play counts data an SDK transmits off the device as collected by the app, whoever receives it (§1).
So the Android app **collects User payment info**, and the old "you cannot collect data your code
has no access to" argument does not survive: the SDK is code the app ships.

What stays true, and is worth saying to a reviewer in the same breath:

- **NIVORA's own code still never reads it.** The success callback's payload is discarded unread
  (`razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (_) => ...)`), and the resident's balance is only
  ever reported from the server's ledger.
- **It never reaches NIVORA's servers or database.** §3.1 lists every column of both financial
  tables; none can hold an instrument, and the webhook parses none.
- **Its only recipient is Razorpay**, processing the payment NIVORA asked it to take — a service
  provider (§4). So **Shared is No**.

How to fill the row:

| Field | Answer | Why |
|---|---|---|
| Collected | **Yes** | The in-process SDK transmits the details the resident types |
| Shared | **No** | Razorpay is a service provider — §4 |
| Processed ephemerally | **No** | NIVORA cannot vouch for how Razorpay retains it, and Razorpay keeps its own transaction record under its own regulatory duty (§7.1). Do not claim ephemeral on a third party's behalf |
| Required or optional | **Optional** | Paying online is a choice; rent can always be paid at the desk in cash, and a hostel not set up for online payment (§4.1) never opens the SDK at all |
| Purposes | **App functionality**; **Fraud prevention, security and compliance** | The details exist to take the payment; Razorpay's own checks on them are fraud prevention and regulatory compliance |

**Keep Purchase history ticked as well.** User payment info covers the instrument the SDK handles
during the payment; Purchase history covers the record of the transaction that NIVORA stores in
`fee_payments`, `payment_intents` and `payment_refunds`. They are different data and both are true.

**What would change the evidence behind this answer** (the answer itself stays Yes): the day
NIVORA's own servers receive an instrument — a card, UPI or bank field rendered by our own form, or a
saved-card, token, mandate or auto-debit flow. Then the database would hold it and retention, PCI
scope and the privacy policy would all have to move. None of that exists today. There is no
`customer`, `token`, `subscription` or `mandate` call anywhere; the only Razorpay API calls in the
codebase create orders — `razorpayClient().orders.create(...)` in `lib/actions/payments.ts` for the
web, and the `POST https://api.razorpay.com/v1/orders` in `supabase/functions/_shared/razorpay.ts`
that the Android app reaches through `supabase/functions/razorpay-order/index.ts`.

### 3.3 What NIVORA does send to Razorpay

Answer this honestly if asked, because it is more than nothing:

| Sent | From | What it is |
|---|---|---|
| `amount`, `currency: "INR"` | `orders.create()` in `lib/actions/payments.ts` (web); `createOrder()` in `supabase/functions/_shared/razorpay.ts`, called by `razorpay-order` (Android) | The server's figure, derived from the student's own ledger |
| `transfers: [{ account, amount, currency, on_hold: false }]` — **Route hostels only** | `createOrder()` in `supabase/functions/_shared/razorpay.ts` (the Android order path; the web's `orders.create()` never sends `transfers`) | The hostel's linked-account id and the whole rent. Omitted entirely for a DIRECT hostel, and no hostel is on Route today. Because the web never sends it, a Route hostel paying on the web would settle to the wrong account — a latent defect, not fixed, §4.1 |
| `receipt: rent_<YYYY-MM>_<first 8 chars of student uuid>_<base36 timestamp>` | `lib/actions/payments.ts:133` (web); `supabase/functions/razorpay-order/index.ts:287` (Android) | Deliberately no PII — a truncated UUID is a lookup key for us and meaningless to anyone else |
| `notes: { purpose: "hostel_rent", period }` on the web; `notes: { purpose: "hostel_rent", period, channel: "mobile" }` on Android | `lib/actions/payments.ts:137` (web); `supabase/functions/razorpay-order/index.ts:290` (Android) | For a human reading the Razorpay dashboard. Nothing on the settlement path ever reads it back |
| `name` (the hostel's name), `description` (`"<Month YYYY> rent"` on the web, `"Rent · <period>"` on Android) | Checkout options in `components/payments/pay-rent-sheet.tsx` (web) and `razorpay.open()` in `nivora_app/lib/features/payments/pay_rent.dart` (Android) | Branding on the checkout |
| `prefill: { name, email, contact }` | same, from `RentOrder.prefill` (web) and `CheckoutOrder.prefillName` / `prefillEmail` / `prefillContact` (Android) | **The student's own `full_name`, `email` and `phone`**, so they do not have to retype them |

So Razorpay receives the payer's name, email and phone. That is a transfer **to a service
provider** — see §4 — and it belongs in the privacy policy as a named sub-processor, not in the
"Shared" column.

### 3.4 Razorpay Checkout's own telemetry and UPI app detection

Checkout runs its own device and session telemetry during a payment. How far that reaches depends
on the platform.

**On the web**, Checkout is a third-party script, and two facts bound it:

- **It is not granted `connect-src` in our document.** `lib/security-headers.ts` allows only
  `https://api.razorpay.com` to `connect-src`, with the comment "lumberjack telemetry deliberately
  NOT granted" — the lumberjack hosts being Checkout's own telemetry (`lib/security-headers.ts:38-40`).
  The loader Checkout draws in *our* page cannot reach them.
- **Inside its own iframe our CSP does not apply** — a cross-origin frame carries its own policy.
  Razorpay's telemetry from within its modal is Razorpay's, serving the payment's own fraud and
  operational purposes. **NIVORA receives none of it.**

The web Razorpay CSP grants are also **scoped to `/student`** (`needsRazorpay()` in
`lib/security-headers.ts` returns true only for `/student` and below). No other web page — including
every screen that renders resident PII — can load Checkout at all.

**On Android, neither bound exists.** There is no iframe and no CSP: the native Checkout SDK runs
in the app's own process, with the app's network access, from the moment `razorpay.open()` is
called until the sheet closes. Which hosts the native SDK (`com.razorpay:checkout:1.6.41`,
`nivora_app/android/build.gradle.kts:18`) reports to is not recorded anywhere in this repository;
the lumberjack hosts named above come from the web CSP and are not verified for Android. Previous
versions of this section reasoned only from the web and
concluded that no new row was needed. For the Android app that is wrong, because whatever the SDK
transmits is collected by the app (§1). Three things follow while a payment is open:

1. **Device and session telemetry.** The SDK's own device and session checks are declared under
   the existing **Device or other IDs** row (Fraud prevention, security and compliance), whose
   evidence column names them.
2. **Checkout interactions.** The SDK reports what happens in its sheet to Razorpay as part of
   running the payment. That is declared under **App activity › App interactions**, with **App
   functionality** added as a purpose alongside the existing Fraud prevention one.
3. **Which UPI apps are installed.** `nivora_app/android/app/src/main/AndroidManifest.xml` declares
   a `<queries>` block for `android.intent.action.VIEW` on the `upi:` scheme. Its comment gives the
   reason: from API 30 an app sees only the packages it declares, and Razorpay's checkout builds its
   "Pay using GPay / PhonePe / Paytm" list by resolving exactly that intent. The SDK therefore
   detects installed UPI apps in order to offer them. That is **App activity › Installed apps:
   collected, not shared, optional, App functionality**. NIVORA cannot inspect what the SDK sends
   about that list, and Play's rule turns on what the SDK transmits, not on what NIVORA receives, so
   it is declared rather than asserted away. Visibility is limited to apps that handle `upi:` — the
   app does not request `QUERY_ALL_PACKAGES`.

On both platforms, **NIVORA receives none of it** — no telemetry, no interaction events and no app
list reach NIVORA's servers. Razorpay is the only recipient, acting as a service provider (§4), so
none of these rows is Shared. **Do not add Analytics as a purpose** — NIVORA performs no analytics
and receives no analytics data, and Razorpay's processing serves the payment, not a product of
NIVORA's.

---

### 3.5 Notifications — the FCM registration token

Nivora sends push notifications: rent is due, the owner posted a notice, a payment arrived, a task
was assigned. That needs two things Play asks about.

**The token is a device identifier, and it is declared.** Firebase Cloud Messaging issues each
install a registration token; `public.push_devices` stores it against the signed-in user's id so
the server knows which phone to ring. It is collected, not shared, and its purpose is **App
functionality** — it serves no other purpose, and the only party it reaches is the one that issued
it. **Where it goes:** Google mints it on the device, `push_devices` holds it, and
`supabase/functions/push-send/index.ts` POSTs it straight back to Google at
`https://fcm.googleapis.com/v1/projects/<id>/messages:send`, carrying the `title` and `body` of the
notification being delivered. That Edge Function is the only thing in the codebase that reads
`push_devices.token`, so Google is the only recipient — a **service provider** on §4's test, the
same as Supabase and Razorpay, which is why `/legal/privacy` names it as a sub-processor for
notifications rather than putting this row in the Shared column. Note the second consequence:
notification text leaves the platform with the token and lands in the device tray, where it is
readable on a lock screen. Google's own disclosure guidance for FCM says the same
(firebase.google.com/docs/android/play-data-disclosure). That is why the **Device or other IDs**
row in §2 now carries App functionality alongside the security purpose.

**Deleting the account deletes the token.** `push_devices.user_id` is
`references public.users(id) on delete cascade`, and signing out unregisters the row explicitly.
A phone that has not checked in for 90 days is pruned by `app.send_rent_reminders()`.

**POST_NOTIFICATIONS is a runtime permission, not a data type.** Play's Data safety form has no box
for it. The manifest declares it (`nivora_app/android/app/src/main/AndroidManifest.xml:50`), and the
ask is the system dialog itself: there is no in-app rationale screen before it
(`AndroidManifest.xml:25-26`; `Permission.notification.request()` in `_askPermission`,
`nivora_app/lib/core/notify/push_service.dart:183-193`). The dialog appears only once the signed-in
person has agreed to the Terms of Use and Privacy Policy at the consent gate, not at sign-in. Push
starts from `initState` for someone who agreed on an earlier launch and from `_accept` for someone
agreeing now (`nivora_app/lib/features/legal/consent_gate.dart:93-95`, `:150-166`), and
`nivora_app/lib/main.dart:227-236` only stops it on sign-out. A refusal does not stop registration:
`start()` registers the token straight after asking (`push_service.dart:116-118`, `:180-182`), so the
token declaration above applies whatever the person answers. Delivery to a real phone has not yet
been proven; the declaration does not depend on it, because the token is registered and stored
whether or not a notification ever arrives. The permission is not tied to any of the answers above.

**Still no advertising id.** Firebase Cloud Messaging does not pull in
`play-services-ads-identifier` — Analytics does, and Analytics is deliberately not installed. The
manifest removes `com.google.android.gms.permission.AD_ID` explicitly with `tools:node="remove"`,
so a future dependency cannot merge one in silently, and the Advertising ID declaration in Console
is therefore **No**. Verify that on the BUILT artifact rather than on the source, with
`nivora_app/scripts/verify-adid.sh`. A missing AD_ID line proves nothing unless the same read also
finds a permission that is certainly there, so the script refuses to report clean unless it also
sees `android.permission.INTERNET` (`verify-adid.sh:27-29`, `:74-87`); its earlier version passed on
APK manifests it could not read (`verify-adid.sh:18-25`). On 2026-09-13 it reported all three
versionCode 4 artifacts clean, with `INTERNET` found. Run it again on any rebuild, the versionCode 6
upload included. A result from one build does not carry over to the next.

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
2. **What NIVORA's own code never touches, NIVORA does not pass on.** On the web the card number and
   the UPI ID are typed into Razorpay's own document. On Android they are typed into Razorpay's
   native SDK, which runs inside the app's process — so the app does collect them (§3.2) — but the
   SDK sends them to Razorpay and nowhere else, NIVORA's Dart code discards the success payload
   unread, and nothing reaches NIVORA's servers or database. There is no second recipient for the
   data to be "shared" with. *(This ground previously said the details "never enter NIVORA's
   process". That was true of the web and false of Android, and was corrected on 2026-09-13.)*

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
> Vercel, and say what it receives. It does — see §8 row 1.

### 4.1 Whose account the rent settles into — as it actually is on 2026-09-13

**Rent settles into the hostel owner's own Razorpay account, and NIVORA never holds it — on the one
path in use today.** The Android order path allows two ways to get there and refuses everything
else. The web order path does not choose between them at all. Today that moves no money wrongly but
can leave an unpaid live Razorpay order behind, and it would misroute rent the day a hostel gets a
linked account (below).

**The two paths.** `supabase/functions/razorpay-order/index.ts:217-243` reads
`hostels.razorpay_account_id`, `hostels.razorpay_direct_for_owner` and `hostels.owner_user_id`
before creating any order, and refuses with HTTP 409 unless DIRECT is valid or a linked account is
set. `public.rz_open_intent` reads the same three columns after the order exists, and checks them in
a different order (read with `pg_get_functiondef` on 2026-09-13). It first refuses any hostel whose
`razorpay_direct_for_owner` is set but no longer equals `owner_user_id` — "Online payment is paused
for this hostel while its ownership change is reviewed. Please pay your warden directly." — even when
a linked account is also set. Only then does it refuse a hostel with neither column set — "Online
payment is not set up for this hostel yet. Please pay your warden directly."

| Path | The Android order takes it when | `rz_open_intent` accepts it when | Where the rent settles | In use today |
|---|---|---|---|---|
| **DIRECT** | `razorpay_direct_for_owner` equals the current `owner_user_id` **and** `razorpay_account_id` is not set — a linked account wins (`index.ts:236`) | `razorpay_direct_for_owner` equals `owner_user_id` | The merchant account whose API keys the app uses. The order carries **no `transfers`**, which Razorpay treats as "settle to this merchant" | **Yes — exactly one hostel, Kushi Hostels** |
| **ROUTE** | `razorpay_account_id` is set (a Razorpay Route linked account, `acc_...`) | `razorpay_account_id` is set **and** `razorpay_direct_for_owner` is unset or equals `owner_user_id` | On Android, that linked account: the order carries `transfers: [{ account, amount: <the whole rent>, currency: "INR", on_hold: false }]` (`supabase/functions/_shared/razorpay.ts:233-244`). On the web, **not** that account — see below | **No — no hostel has a linked account** |

The two sides disagree in one state: a linked account plus an out-of-date DIRECT approval. The Edge
Function creates a ROUTE order and `rz_open_intent` then refuses it as paused, leaving a Razorpay
order with no intent row behind it, which `index.ts:303-306` accepts as the safe way to fail. No
hostel is in that state.

**The web order path does not follow this table — a latent defect, not fixed.** `createRentOrder()`
in `lib/actions/payments.ts:127-150` calls `razorpayClient().orders.create({ amount, currency,
receipt, notes })`, never with `transfers`, and only then calls `rz_open_intent`. Two consequences:

- **A ROUTE hostel paying at `/student` would settle into the DIRECT merchant account** — the one
  KYC'd to Kushi Hostels' owner — instead of its own linked account. `rz_open_intent` accepts a
  hostel with a linked account unless an out-of-date DIRECT approval pauses it, and it checks only
  the hostel's columns, never where the order sends the money.
- **The web has no payout check before an order is created.** A hostel with neither path gets a live
  Razorpay order minted before `rz_open_intent` refuses it. The HTTP 409 that stops this first is
  Android-only.

The first consequence is latent: nothing is affected while no hostel has a linked account. The
second can occur today wherever the web deployment has Razorpay keys (`lib/actions/payments.ts:85`).
No code in `app/`, `components/` or `lib/` reads the payout columns, and the web Pay button shows
whenever rent is owed (`components/payments/pay-rent-button.tsx:43`). So a resident of an
unconfigured hostel who taps Pay leaves an unpaid Razorpay order with no intent row behind it. No
money moves, because Checkout opens only after `createRentOrder()` succeeds
(`components/payments/pay-rent-sheet.tsx:232-246`). The fix belongs in `lib/actions/payments.ts` and
is flagged as a separate code task. Giving any hostel a linked account before it lands would send
that hostel's web rent into someone else's merchant account.

**What the production database says**, read with read-only SQL on 2026-09-13 against project
`nimxvgzscbanhtvgnjll`:

- There are **four** hostels. **None** has `razorpay_account_id` set, so Route is implemented and
  unused.
- **One**, Kushi Hostels, has `razorpay_direct_for_owner` set, and it equals that hostel's current
  `owner_user_id`.
- The other three, one of them **Demo PG (Play review)**, have neither column set, so **they cannot
  take an online payment at all**. On Android the Edge Function refuses the order with HTTP 409 —
  "Online payment is not set up for this hostel yet. Please pay your warden directly." — before any
  Razorpay order is created, and the checkout sheet never opens, because `payRent()` asks for the
  order before it opens the sheet (`nivora_app/lib/features/payments/pay_rent.dart:92-104`). Their
  residents pay at the desk, and a Play reviewer who taps Pay in the demo PG sees that message and
  never reaches Razorpay.

To re-check before a submission:

```sql
select name, razorpay_account_id,
       razorpay_direct_for_owner is not null            as direct_approved,
       razorpay_direct_for_owner = owner_user_id         as direct_matches_current_owner
from public.hostels order by name;
```

**Whose merchant account DIRECT pays into.** The database can show that Kushi Hostels is approved
for DIRECT; it cannot show whose name is on the merchant account. The operator confirmed on
2026-09-13 that the merchant account whose keys the app uses is KYC'd to **Kushi Hostels' owner**.
So the one hostel taking online rent today is paying into its own owner's account. That
confirmation is the load-bearing fact for this whole section, and it lives outside the code:
**approving DIRECT for any hostel whose owner is not the person that merchant account is KYC'd to
would put that hostel's rent in someone else's account**, and nothing in the code can detect it.
The code does close one version of that mistake: the approval is compared with the *current* owner,
so a hostel that changes hands stops taking online payment until it is re-approved.

What follows from all of this, enforced rather than intended:

- **NIVORA takes no commission.** On DIRECT the whole payment settles to the owner's merchant
  account; on ROUTE the transfer is the full sum. NIVORA's own revenue is a subscription the owner
  pays, recorded separately and never through this gateway.
- **NIVORA holds no balance.** There is no NIVORA-owned merchant account on the payment path, no
  `on_hold` transfer and no wallet. Razorpay settles on its normal cycle.
- **A hostel with neither path cannot take an online payment.** `rz_open_intent` refuses the intent
  on both platforms, and on Android the Edge Function also refuses the order before it exists — the
  same failure guarded from both sides, because rent landing somewhere it cannot lawfully be released
  from is unrecoverable. On the web only the database refuses, after a Razorpay order exists (above).

**So the Payment Aggregator question does not arise.** NIVORA is software: it creates an order for
what a resident owes, and Razorpay, an RBI-licensed aggregator, settles it to the owner's own
account. This is why the Financial features answer in §5 is "none".

> **This section went stale once, and its replacement described the code instead of the data.** The
> text added on 2026-08-24 (commit `327b8e2`) said one merchant account, no Route, no transfers. It
> went stale when Route was added on 2026-09-06 (`db/migrations/2026-09-06-route-linked-accounts.sql`).
> The replacement, written on 2026-09-13 (commit `2bad96b`) under the heading "settled 2026-09-06",
> said "each hostel carries its own linked account". That described the code, not the data: the
> same day the production database showed that no hostel has a linked account, and that the only
> hostel taking online payment does so on the DIRECT path. Any sentence elsewhere claiming every hostel
> carries its own linked account is false. The distinction matters because it is the difference
> between "software" and "handling other people's money".

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
| **Financial features** | **"My app doesn't provide any financial features."** | The list covers financial *products and services* — lending, banking or e-money, insurance, investments, crypto, debt management, money management or planning, tax. Accepting payment for the hostel's own service is none of them, exactly as an e-commerce app taking card payments is none of them. As §4.1 records from the database on 2026-09-13: exactly one hostel, Kushi Hostels, takes online rent, on the DIRECT path, into the merchant account the operator confirmed is KYC'd to Kushi Hostels' owner; no hostel has a Route linked account; every other hostel cannot take online payment at all. NIVORA takes no commission, holds no balance, issues no credit and moves no money between people. **Revisit if any of that changes** — a DIRECT approval for a hostel whose owner is not the KYC'd holder of that merchant account, a commission or hold on rent, any NIVORA-owned account on the payment path, or a Route linked account for any hostel while the web order path still omits `transfers` (§4.1) |
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
| Is all user data encrypted in transit? | **Yes** | TLS to Vercel and to Supabase throughout; HSTS and a nonce-based CSP in `middleware.ts`; the manifest sets no `usesCleartextTraffic`. The payment path adds no exception — on the web Checkout loads over HTTPS from `checkout.razorpay.com`, on Android the Razorpay SDK runs inside the app under that same manifest, and the webhook is HTTPS-only |
| Do you provide a way for users to request that their data be deleted? | **Yes** | `/legal/account-deletion` is live (HTTP 200 signed out, verified), backed by the erasure runbook in [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.3. Inside the app, **Delete my account and data** files a deletion request: residents open it from the Profile tab (`nivora_app/lib/features/student/profile_screen.dart:160`), staff by tapping their picture at the top left (`nivora_app/lib/features/shell/staff_profile_sheet.dart:139`), and a second request inside 30 days returns the first instead of filing another (`nivora_app/lib/features/legal/account_deletion.dart:34-37`). See §7.1 for what deletion does to payment records |
| Has your app been independently reviewed against a global security standard? | **No** | `SECURITY.md` is a thorough internal review. It is not a third-party audit, and claiming otherwise in Console is a misrepresentation |
| Committed to follow the Play Families Policy? | **No** | Not a children's app — submission pack §4 |

### 7.1 What deletion does to payment records — the answer that has to hold

A hostel has an accounting duty it cannot waive, so **payment records survive an erasure request.**
Play accepts that. What Play does not accept is a deletion page that promises total erasure and then
does not deliver it. Say the following, and make sure `/legal/account-deletion` says the same.

**Deleted with the resident.** `students`, `users`, and everything that cascades from them.
`payment_intents.student_id` is `references public.students(id) on delete cascade`, so **if the
student row is deleted, their payment intents go with it** — exactly like `fee_payments`.
`payment_refunds.student_id` carries the same clause, and `payment_refunds.intent_id` is
`references public.payment_intents(id) on delete cascade`, so a refund row leaves with the student
by either route.

**Retained, with the person taken out of it.** When the accounting duty means the ledger must
survive, the resolution is [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.4:
**anonymise instead of delete.** Both financial tables behave unusually well — go back to the two
column lists in §3.1 and notice what is absent from each. There is **no name, no phone, no email
and no address in either table at all.** Each is UUIDs, money, dates, two Razorpay reference ids
and one display-only label — `method` on the intent, `speed` on the refund. Once `students` and
`users` are anonymised per §6.4, neither the payment rows nor the refund rows carry anything that
identifies a person.

**For how long.** The same period as the rest of the fee ledger: **kept indefinitely**, as the
published policy and [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §5.2 say. The
hostel's statutory accounting duty is why the ledger is kept, and NIVORA does not shorten it.
Do not invent a shorter one for `payment_intents` or `payment_refunds` — the intent is part of the
same financial record as the `fee_payments` row it credited, and the refund is part of the same
record as the intent it reverses. Splitting them would leave a credit with no evidence behind it,
or a reversal with nothing on the ledger to show what it undid.

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

A Data safety form that contradicts the privacy policy is itself a violation. These six are
**blocking**, and **all six pass** against the pages deployed on 2026-09-13 from commit `4fd41ef`
(pushed 20:44 IST), which show legal version 2026-09-13. Row 6 was added that day, when §2 started
declaring User payment info and Installed apps. The version that says the same thing is in
production's `public.legal_versions` (effective 2026-09-12 18:30 UTC), is live on the web, was first
built into the app's own copy in versionCode 4 (never released), and reaches testers with
versionCode 6, which is published to the closed track. **This form went in together with
versionCode 6**, in the batch of 13 changes that also carried the store listing, the app category
and the rest of the App content declarations. The re-check itself stands for every submission after
this one: submit the form together with the build it describes, and re-run every row against the
live pages immediately before submitting. That is the complete list of blocking cross-checks.

| # | Must be true | Status |
|---|---|---|
| 1 | `/legal/privacy` names **Razorpay** as a sub-processor and says what it receives | **PASSING** on the page deployed 2026-09-13. The sub-processor table lists Razorpay against *"Your name, email and phone, so the payment can be attributed to you"*, and goes on to say that on Android its checkout runs inside the app and takes the card, UPI or netbanking details typed (`app/legal/privacy/page.tsx:440-442`). This row used to quote the 2026-09-12 wording, which that deploy replaced |
| 2 | `/legal/privacy` does not claim payments are offline-only | **PASSING** — §3 now reads *"This is still true now that rent can be paid inside the app"*, and says the card and UPI fields are typed into Razorpay's own checkout |
| 3 | `/legal/account-deletion` names the payment record among what is retained, and Razorpay among what cannot be reached | **PASSING** — the retention table carries *"Fee and payment records"* as kept indefinitely (since 2026-09-13; it said 8 years before, which contradicted the privacy policy), and that page's own "What deletion cannot reach" section names Razorpay's own record of the transaction |
| 4 | `/legal/terms` reflects that rent can now be collected in-app | **PASSING** — the payments section is now **§6, "Subscription and payments"**, and states that the payment is taken by Razorpay in Razorpay's own checkout. Note the renumbering: it was §9 |
| 5 | `/legal/privacy` discloses the **FCM device token** and names **Google** as the notification sub-processor | **PASSING** — the data inventory carries a "Notification device" row, §3 explains the token and the ten-permission list, and the Google row in the sub-processor table covers *"your device's registration token, plus the title and body of each notification"*. One timing phrase is out of date, though it is not a Data safety answer. The inventory row says the token is *"written when you sign in on a device"* (live, `app/legal/privacy/page.tsx:215`). The in-app copy says *"When you sign in on a phone"* (`nivora_app/lib/features/legal/legal_documents.dart:221`). Push actually starts only after agreement at the consent gate (§3.5). See the note under this table |
| 6 | `/legal/privacy` (and the in-app copy in `nivora_app/lib/features/legal/legal_documents.dart`) says that on Android **the Razorpay checkout runs inside the app**, **handles the card or UPI details the resident types** while a payment is open, and **checks which UPI apps are installed** so it can offer them — while NIVORA still never receives those details. This is what the §2 **User payment info** and **Installed apps** rows declare. The live sentence that the details "never reach NIVORA at all" (on deploy it becomes "go to Razorpay, never to NIVORA") stays true of NIVORA's servers, but it must sit next to the in-app handling, or it reads as a denial of what the form declares | **PASSING — both halves.** Legal version **2026-09-13** in `public.legal_versions` records this change for both documents. *Web half:* `app/legal/privacy/page.tsx:251-253` and `:442` carry it, and it has been live since commit `4fd41ef` was deployed on 2026-09-13; a signed-out GET found "which on Android runs inside the app" and "On Android its checkout runs inside the app". *In-app half:* `nivora_app/lib/features/legal/legal_documents.dart:257-260` and `:386-394` carry it, and the versionCode 4 `libapp.so` was checked on 2026-09-13 to contain "runs inside this app" and "which UPI apps are installed". The versionCode 6 `libapp.so` has not had that check yet, so run it on the uploaded artifact. Older builds do not contain the text, so the build uploaded with this form must be versionCode 6 |

The three pages behind those rows are **outside this document's scope** and belong to whoever owns
`app/legal/`. They agree with every answer on this form. Two sentences in the
privacy policy are still out of date against the Android app. Neither changes a Data safety answer,
and both are for that owner to correct:

- **When the token is registered.** `app/legal/privacy/page.tsx:215` (live) and `nivora_app/lib/features/legal/legal_documents.dart:221` tie registration to
  signing in. In fact push starts only once the person has agreed at the consent gate
  (`nivora_app/lib/features/legal/consent_gate.dart:93-95`, `:166`; §3.5).
- **What the camera is for.** `app/legal/privacy/page.tsx:262-263` (live) says the Android camera photographs *"an identity document, a receipt or a
  complaint"*. In the Android app residents cannot attach a photo to a complaint, and the camera is
  declared for a warden registering a resident
  (`nivora_app/android/app/src/main/AndroidManifest.xml:30-32`). The in-app copy already lists an
  identity document, a resident or a receipt (`legal_documents.dart:263-264`).

Re-check all three pages the next time either side changes, because Google fetches the
privacy-policy page, and a reviewer comparing it to this form finds a contradiction in under a
minute.

One more, non-blocking but worth closing:

7. `.env.example` declares `NEXT_PUBLIC_RAZORPAY_KEY_ID`, but `lib/razorpay.ts` reads
   `RAZORPAY_KEY_ID` and `docs/payments.md` §1 says explicitly that it must **not** be a
   `NEXT_PUBLIC_` variable. Anyone setting up from `.env.example` gets a permanently dead Pay button
   and the "Online payment isn't set up yet" message.

---

## 9. Ticking order in Console

**Steps 1 to 6 are done.** The form was filled in this order on the new `com.nivorasr.app` app and
submitted with the store listing, the app category and the rest of the App content declarations, as
one batch of 13 changes alongside the 1.0.0 (6) upload. The order below stands as the method for the
next submission, and step 7 is still ahead of the production release.

1. **Data collection and security** — confirm the app collects data; answer the four §7 questions.
2. **Data types** — work down §2 row by row. Slow down on the five rows NIVORA's own payment code
   bears on: **Name**, **Phone number** and **Email address** (all now also reach Razorpay as
   prefill), **Personal info › User IDs** (Razorpay's order and payment ids), and **Financial info ›
   Purchase history** (now includes `payment_intents` and
   `payment_refunds`). Then on the row push changed: **Device or other IDs** (the FCM registration
   token in `push_devices` — see §3.5).
3. **The four rows the Android Razorpay SDK bears on** — all ticked, all **not shared**; the first
   three changed on 2026-09-13:
   - **Financial info › User payment info** — **tick it**: optional; App functionality and Fraud
     prevention, security and compliance. This step used to say "leave it unticked"; re-read §3.2
     for why that changed.
   - **App activity › Installed apps** — **tick it**: optional; App functionality (UPI app
     detection, §3.4).
   - **App activity › App interactions** — already ticked; **add App functionality** alongside
     Fraud prevention, security and compliance (§3.4).
   - **Device or other IDs** — already ticked and unchanged; it also covers the SDK's own telemetry
     (§3.4).
4. **Shared** — **No** on every row, the four above included. Re-read §4 before deciding otherwise.
5. **Government ID** — three ticks, per §6.
6. **Deletion URL** — paste `https://hostelpro-three.vercel.app/legal/account-deletion`. First
   confirm that the live page names Android package `com.nivorasr.app`: it prints `ANDROID_PACKAGE`
   (`lib/legal-config.ts:96`). On 2026-09-14 the live page still showed `com.srnivora.app`, because
   the change had not been deployed. It names `com.nivorasr.app` now, re-checked with a signed-out
   GET on 2026-09-20. This form went in together with versionCode 6. Next time,
   submit the form together with the build it describes, after re-confirming §8 rows 1–6 against the
   live pages.
7. **Preview the store's Data safety section** before the production release. The closed-test
   release 1.0.0 (6) is already published to the closed track and production is Inactive, so this
   step is still ahead of the publication that puts the section in front of the public. It is what
   users read, and it is the artefact a policy complaint is measured against.
