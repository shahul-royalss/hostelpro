# Play Console submission pack — NIVORA

Everything that has to be typed, pasted or ticked in Play Console, with the reasoning behind each
answer. **Every answer here was derived from the code**, not assumed: `db/schema.sql`,
`db/migrations/2026-08-24-payments.sql`, `lib/storage.ts`, `package.json`, `app/`, and the verified
artifact report in [`play-technical-compliance.md`](./play-technical-compliance.md).

Where another document disagrees with this one, check which was derived more recently. For the Data
safety answers that is [`data-safety.md`](./data-safety.md) (§2). §10 records corrections to older
documents.

> **Revised 24 August 2026: the app now takes payments.** Student rent can be paid in-app through
> Razorpay (`db/migrations/2026-08-24-payments.sql`, [`payments.md`](./payments.md)). That changes
> the store listing (§1), four Data safety rows (§2), one content-rating answer (§3) and the
> reasoning behind the Financial features declaration (§5). The legal pages that contradicted it
> were corrected on 2026-09-02 (§7.1).
>
> **Revised 2026-09-13: the legal text those answers need is live on the web.** The Data safety
> answers changed on 2026-09-13 (§2.4) rely on legal version 2026-09-13, which is recorded in
> production's `public.legal_versions`. Commit `4fd41ef` reached `origin/main` at 20:44 IST that
> day, and at 20:53 IST the live privacy and account-deletion pages both carried version
> 2026-09-13. The in-app copy reaches users with versionCode 5, so submit those answers together
> with versionCode 5. See §7.1 and §9 step 1.
>
> **Revised 2026-09-14: a new Play Console app, package `com.nivorasr.app`.** Until 2026-09-13 this
> pack was written for a Console app locked to `com.srnivora.app`. That listing is abandoned.
> Nothing was ever released from it, and the builds made for it (versionCodes 1–4, the last verified
> one being versionCode 4) will not be uploaded. The code now builds `com.nivorasr.app`
> (`nivora_app/android/app/build.gradle.kts:60`, `:109`) at `1.0.0+5` (`nivora_app/pubspec.yaml:19`),
> so the upload is versionCode 5, release name "1.0.0 (5)". Every Console task is done again on the
> new app (§9). The answers themselves do not change.

> **Not legal advice.** The Data safety form is a legal declaration by the developer. Read §2 before
> ticking anything; a wrong answer there is a policy violation, not a typo.

**Contents:** [Store listing](#1-store-listing-copy) · [Data safety](#2-data-safety-form) ·
[Content rating](#3-content-rating-questionnaire) · [Target audience](#4-target-audience-and-content)
· [Declarations](#5-the-declarations) · [App access](#6-app-access--the-one-that-blocks-review-for-this-app)
· [URLs](#7-required-urls) · [Closed testing](#8-the-closed-testing-requirement) ·
[Checklist](#9-release-checklist)

**The Data safety answers are also published on their own**, in the shape Console asks for them, at
[`data-safety.md`](./data-safety.md). Use that one at the keyboard; §2 here is where the reasoning
lives.

---

## 1. Store listing copy

### 1.1 The listing to upload now

**Revised 2026-09-13.** The listing for `com.nivorasr.app` (until 2026-09-13, `com.srnivora.app`) does not use the copy or the images this
section used to carry. Those were written for the web-app wrapper (a TWA, package `app.nivora.twa`),
which is retired. They are kept in §1.2 as a record of what the older answers in this file were
reasoning about. Do not paste from §1.2.

| What | Where | Checked 2026-09-13 |
|---|---|---|
| App name | `Nivora`, typed when the new app is created in Console (§9 step 11; [`play-console-submission.md`](./play-console-submission.md)) | Same as `app_name` in `nivora_app/android/app/src/main/res/values/strings.xml` |
| Short description | `dist/store-listing/short-description.txt` | 77 / 80 characters |
| Full description | `dist/store-listing/full-description.txt` | 3,827 / 4,000 characters. Has a NOTIFICATIONS section, so do not paste it until a push notification has been seen arriving on a real phone |
| Full description without push | `dist/store-listing/full-description-without-push.txt` | 3,572 / 4,000 characters. The same text with the NOTIFICATIONS section removed. **Paste this one for now**: push delivery to a real phone has not been proven yet |

The same three text files are tracked in git under `docs/store-listing/`, and matched the
`dist/store-listing/` copies byte for byte on 2026-09-13. `dist/` itself is ignored by git, so the
images below exist only on the build machine, except the icon, `public/store/icon-512.png`, which is
tracked. Counts were taken with the command in §1.2.

#### Listing assets

| Asset | Spec | Status |
|---|---|---|
| App icon | 512×512 PNG, 32-bit | `public/store/icon-512.png` ✔ 512×512, RGBA |
| Feature graphic | 1024×500 PNG, no alpha | `dist/NIVORA-feature-graphic.png` ✔ 1024×500, RGB (a byte-identical copy, same SHA-256, sits in `dist/store-listing/`) |
| Phone screenshots | min 2, 320–3840 px per side, max 2:1 | `dist/store-listing/phone-{resident,warden,manager,owner}.png` — 4 at 1080×1920, RGB ✔ |
| 10-inch tablet screenshots | 1080–7680 px per side, 16:9 or 9:16 | `dist/store-listing/tablet10-{resident,warden,manager,owner}.png` — 4 at 1440×2560, RGB ✔ |

Dimensions and colour type were read from each file's PNG header on 2026-09-13.
`node scripts/store-assets.mjs --check` still verifies the icon (`scripts/store-assets.mjs:1455`), but
it does not look at `dist/`; the feature graphic and screenshots it checks in `public/store/` belong
to the retired listing ([`store-assets.md`](./store-assets.md)).

**Phone and 10-inch tablet screenshots both exist, so fill in both slots.** This section used to say
tablet screenshots were not present and that the listing should not claim tablet support. That was
true of the TWA's image set, not of this one.

**Check any listing edit against what the Android app actually does.** Residents have no leave
feature and cannot attach a photo to a complaint; wardens cannot edit the mess menu (only managers
can); and managers do not see notices. The retired copy in §1.2 claims some of these.

Also required in the listing form: an **app category** (Business, or Productivity — Business is the
better fit for a property-management tool), a **support email address**, and optionally a website
and phone number. The support email is public once the listing is live, so use a real, monitored
address, not a personal one.

### 1.2 Retired: the web-app (TWA) listing

> **Retired 2026-09-13. Do not paste anything from this subsection.** It was written for the TWA,
> package `app.nivora.twa`, under the title `NIVORA: PG & Hostel Manager`, and went with the
> `public/store/` screenshots. It offers residents leave requests and complaint photos, which the
> Android app does not have, and its ABOUT ONLINE PAYMENT paragraph predates the 2026-09-13
> correction to User payment info in §2.4.

Character counts below were **re-measured** on 24 August 2026 by counting the actual strings with
`String.prototype.length`, not estimated. All three are pure ASCII, so nothing double-counts against
a UTF-16 limit.

> **The previous counts in this section were wrong, and it is worth knowing why.** They were
> measured when the product was called HostelPro. `HostelPro` is 9 characters and `NIVORA` is 6, so
> every count fell by 3 per occurrence at the rename and nobody re-ran them: the app name was
> recorded as 30/30 when it is 27, and the full description as 3,995 when it was 3,971. **Re-count
> after any rename.** A stale count is harmless in the direction it happened to fall this time and
> a rejected paste in the other.

#### App name — limit 30

```
NIVORA: PG & Hostel Manager
```

**27 / 30 characters** — three to spare. If Console objects for any reason, the shorter fallback:

```
NIVORA - PG Management
```

**22 / 30 characters.**

The bare `NIVORA` (6 characters) is also available, but it wastes the strongest ranking surface in
the whole listing — nobody searches for "NIVORA"; they search for "hostel management app" and
"PG management".

#### Short description — limit 80

Now that residents can pay from the app, the short description should say so: it is the single
strongest differentiator against every other PG-management listing, and it is the line a store
visitor actually reads.

```
Rooms, beds, fees, complaints, mess menu - and rent paid from the app.
```

**70 / 80 characters.**

Alternative, if the emphasis should be on the operator rather than the feature list:

```
Run your PG: beds, fees, complaints, mess menus - and rent paid online.
```

**71 / 80 characters.**

Note the ASCII hyphen rather than an en dash. Play accepts Unicode, but the short description is
rendered in a lot of surfaces at a lot of font sizes and a plain hyphen never surprises anyone.

#### Full description — limit 4000

**3,837 / 4,000 characters.** 163 characters of headroom. Re-count before pasting if anything is
edited:

```sh
node -e "console.log(require('fs').readFileSync(process.argv[1],'utf8').replace(/\r\n/g,'\n').replace(/\n+$/,'').length)" desc.txt
```

```
NIVORA is a complete management system for paying-guest accommodations and hostels. Rooms and beds, monthly fees, online rent payment, complaints, leave requests, the visitor register and the mess menu all live in one place, so the owner, the manager, the warden and the resident are finally looking at the same information.

Built for how a PG actually runs. The owner sees the whole property. The manager runs the money and the kitchen. The warden runs the floor. The resident sees only their own room, fees and requests - nobody is handed a spreadsheet they were not meant to see.

ROOMS AND BEDS
- Lay out floors, rooms and beds once, then allocate residents to a specific bed
- Live occupancy: which beds are free, which are taken, and by whom
- Move a resident between beds, or vacate them and free the bed the same moment

FEES AND RENT PAYMENT
- A monthly ledger per resident: amount due, amount paid, paid or partial or unpaid
- Residents pay this month's rent from their phone by UPI, card, net banking or wallet
- The amount comes from their own ledger, so it is exactly what is outstanding
- The ledger updates itself once payment is confirmed
- Wardens still record cash, UPI or bank transfers taken at the desk
- Attach a receipt image or PDF to any payment
- See at a glance who has not paid this month, and for how many months

COMPLAINTS
- Residents raise complaints under food, cleaning, maintenance, wi-fi, roommate or other
- Attach a photo so the warden sees the problem before walking over
- Track each one from open to in progress to resolved, with a resolution note

LEAVE REQUESTS
- Pending leave requests wait on the warden's desk and are approved or rejected with one tap
- The resident is notified of the outcome

VISITOR REGISTER
- The warden sees at a glance who is still in the building, and signs them out

MESS MENU
- Publish a weekly menu for breakfast, lunch, snacks and dinner, on every resident's home screen

NOTICES AND TASKS
- Post announcements to everyone, or only to staff, or only to residents
- Assign tasks to staff and track them to done

EXPENSES, REVENUE AND REPORTS
- Record groceries, staff costs, electricity, water and maintenance
- Track income from fees, mess and other sources, with charts of where the month went

BUILT FOR PRIVACY
Residents' phone numbers, guardian contacts, addresses and ID documents are some of the most sensitive data a small business holds. NIVORA treats them that way.
- Every property is isolated at the database level; one hostel's staff can never read another's records
- Photos, ID documents and receipts sit in private storage behind links that expire in minutes
- Encrypted in transit, two-factor authentication available, every privileged action audited
- No advertising, no advertising identifier, no analytics or tracking SDKs of any kind

ABOUT ONLINE PAYMENT
Rent is collected by Razorpay, a licensed Indian payment gateway. Card numbers and UPI IDs are entered on Razorpay's own secure screen and are never seen or stored by NIVORA, which keeps only the amount, the date, the Razorpay reference and the method. NIVORA holds no balance and sells no digital goods in the app.

HOW ACCOUNTS WORK - PLEASE READ BEFORE INSTALLING
NIVORA has no public sign-up, and this is deliberate. You cannot create an account by downloading the app. A hostel owner is set up by the NIVORA administrator; the owner creates the manager and warden accounts; the warden registers residents. Residents then sign in with the phone number their warden registered.

If your hostel does not use NIVORA yet, there is nothing for you to sign in to. Ask your hostel owner or warden first.

REQUIREMENTS
An internet connection, and an account created for you by your hostel. Updates arrive through Google Play.

Want NIVORA at your property? Get in touch through the website.
```

**Why the "HOW ACCOUNTS WORK" section is not optional.** An app that cannot be signed into is the
classic one-star review and the classic policy complaint. Saying plainly, in the listing, that there
is no public sign-up sets the expectation before the install and gives a reviewer the context for
§6. It is also the honest answer to "minimum functionality": NIVORA is a real product with a
gated audience, not a broken app.

**What replaced "WHAT THIS APP DOES NOT DO", and why it had to go.** The previous listing carried a
paragraph beginning *"It does not process payments… Money is never taken, held or moved through this
app."* **That is no longer true**, and shipping it would have been a false statement in the store
listing itself — the kind a reviewer can disprove by tapping one button, and the kind that reads as
deliberate rather than stale.

The replacement, "ABOUT ONLINE PAYMENT", does the same job honestly and answers the three questions
a reviewer will actually have:

- **Who takes the money** — Razorpay, a licensed Indian gateway, named out loud. The listing and the
  privacy policy must name the same processor (§7.1).
- **What NIVORA can see** — the amount, the date, the reference and the method. Not the card, not
  the UPI ID. This is the plain-language version of the Data safety answer in §2.4, and it is the
  sentence that stops "your app takes card payments" becoming a review thread.
- **That nothing digital is being sold** — which is the whole basis for not using Google Play
  Billing (§5). One clause in the listing pre-empts the single most likely rejection question.

The reassurance the old paragraph was really there to give survives, one section higher: the FEES
AND RENT PAYMENT list still says wardens record cash, UPI and bank transfers taken at the desk, so
nobody reads "online payment" as "you must now pay through an app".

The listing assets table and the category and support-email note that used to close this section
now live in §1.1, with the current files.

---

## 2. Data safety form

The highest-risk section in the entire submission. Everything below was read out of `db/schema.sql`,
`db/migrations/2026-08-24-payments.sql` and `lib/storage.ts`, and for the Android app out of
`nivora_app/` (its `pubspec.yaml`, manifest, payment screen and push service).

> **The answer sheet in Console order is [`data-safety.md`](./data-safety.md), and where the two
> disagree, it wins.** It is the one to have open while ticking. It was last re-derived from the
> code on 2026-09-13, and it reasons in full about rows this section only summarises, such as the
> refund table and push notifications (its §3.5). This section is the reasoning behind the payment
> and ID answers. If you change an answer, change it in both.
>
> **Three answers changed on 2026-09-13:** User payment info and Installed apps are now Yes, and App
> interactions gains App functionality as a purpose (§2.4). They rely on legal version 2026-09-13,
> which was live on the web by 20:53 IST on 2026-09-13 and reaches the app with versionCode 5, so
> submit them together with versionCode 5, after re-checking that the live policy still carries
> that text (§7.1).

### 2.1 First, the three definitions that decide every answer

Get these wrong and every row is wrong.

**"Collected"** means transmitted off the user's device. All of this app's data lives on a server, so
anything a user types or uploads is collected. There is no on-device-only data to exclude.

That includes data an SDK inside the app sends to its own vendor.
[Play's Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469)
counts user data "transmitted off device from your app by libraries and/or SDKs used in your app" as
collected, whether it goes to the developer or to a third-party server. This is why the Razorpay SDK
in the Android app changes three rows (§2.4).

**"Shared" does NOT mean "leaves your building."** Play defines sharing as transferring data to a
**third party** — someone who uses it for their own purposes. It explicitly **excludes transfers to a
service provider** that processes data on your behalf, on your instructions.

> **Supabase, Vercel, Razorpay and Google are service providers, not third parties.** Supabase and
> Vercel host the database, the auth system, the private storage buckets and the application.
> Razorpay collects a rent payment against an order NIVORA created, and reports the result back.
> Google, through Firebase Cloud Messaging, receives each phone's registration token and each
> notification's title and body in order to deliver it
> (`supabase/functions/push-send/index.ts:169-176`). All four process data solely to run NIVORA,
> under NIVORA's instructions. Per Play's definition this is **not sharing**, and the answer to "Is
> this data shared?" is **No** for every single row in the table below.

This trips people up because it feels dishonest to answer "not shared" when the data plainly sits on
Supabase's servers. It is not dishonest — it is the answer the form is asking for. Ticking "shared"
would tell users that NIVORA passes their residents' phone numbers and ID scans to outside
parties for those parties' own use. That is false, it would contradict the privacy policy, and it
invites a review question that cannot be answered from the schema. The place to disclose Supabase and
Vercel is the **privacy policy**, as named sub-processors — which is exactly what
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §7 does.

**Razorpay is the new one, and it is the one a reviewer may push on.** The full argument —
including the counter-argument that Razorpay is a regulated entity with statutory duties of its
own — is in [`data-safety.md`](./data-safety.md) §4. The short version: a service provider having
its own legal obligations does not make it a third party; the Play question is about a recipient
using the data for **its own commercial purposes**, which Razorpay does not. Answering "No" is only
safe because the privacy policy names it, which it has done since 2026-09-02 (§7.1). The sentences
about what its checkout handles inside the Android app are in legal version 2026-09-13. They have
been live on the web since 2026-09-13 and reach the app with versionCode 5 (§7.1).

Collected and shared are separate questions. What the Android app's Razorpay SDK sends to Razorpay
is collected (see "Collected" above), and it is still not shared, for the same service-provider
reason.

GitHub holds source code only and never resident data, so it is not a recipient at all.

**"Processed ephemerally"** means held in memory for the request and never written down. **Nothing in
NIVORA is ephemeral** — it is a record-keeping product; persistence is the point. Answer **No**
everywhere, including for `audit_log.ip`. Nulling IP at 90 days is retention, not ephemerality.

### 2.2 The table

Purposes use Play's own vocabulary: *App functionality*, *Account management*, *Fraud prevention,
security and compliance*. **Analytics, Advertising or marketing, Personalization and Developer
communications are never selected** — verified on both clients. The web app's `package.json` has
**34** production dependencies and contains no analytics, telemetry, error-reporting,
session-replay or ad SDK. The Android app, which is what the form describes, declares no analytics,
crash-reporting or ad package in `nivora_app/pubspec.yaml` (its Firebase packages are `firebase_core`
and `firebase_messaging`, lines 85-86), and `nivora_app/pubspec.lock` resolves none. Its manifest
removes the advertising-ID permission explicitly
(`nivora_app/android/app/src/main/AndroidManifest.xml:53`), and the permission dump and AD_ID check
of the versionCode 4 artifacts found no AD_ID (technical report §2). Those artifacts were built for
the abandoned `com.srnivora.app` listing. The upload is now versionCode 5, and both checks have to be
run on it. Any rebuild needs them run again.

The count moved from 31 to 34 with the payment feature. In the web app, the one that matters,
`razorpay`, is a **server-side API client**: `lib/razorpay.ts` opens with `import "server-only"`, so
importing it from a client component is a build error and it can never reach the browser. Razorpay
Checkout — the part that does run in a browser — is not a dependency at all; it is fetched from
`checkout.razorpay.com` on the tap that starts a payment, and only on `/student` (§2.9).

**The Android app is different, and on 2026-09-13 that changed three rows.** It bundles Razorpay's
native Android Checkout SDK (`razorpay_flutter` at `nivora_app/pubspec.yaml:67`; the versionCode 4
AAB's dex holds `com/razorpay` classes and its manifest declares `com.razorpay.CheckoutActivity`) and
opens it in-process from
`nivora_app/lib/features/payments/pay_rent.dart`. It is not a web iframe. While a payment is open,
that SDK handles the card or UPI details the payer types and detects which UPI apps are installed.
Under the definition in §2.1 that data is collected by the app, even though none of it reaches
NIVORA's servers. The SDK is a payment SDK, not an analytics one, so the purposes excluded above stay
excluded.

**Push notifications, added 2026-09-12, changed one more row.** The app registers the phone's
Firebase Cloud Messaging token in `public.push_devices`
(`nivora_app/lib/core/notify/push_service.dart:195-200`), and `supabase/functions/push-send/index.ts`
sends it to Google with each notification's title and body. The token is a device identifier held
to deliver notifications, so **Device or other IDs** gains **App functionality** as a purpose
([`data-safety.md`](./data-safety.md) §3.5). Push starts only behind the consent gate, once the
person has agreed to the Terms and Privacy Policy: on launch for someone who agreed earlier, or the
moment someone agrees (`nivora_app/lib/features/legal/consent_gate.dart:93-95` and `:166`). That is
when Android 13 and later shows the system notification-permission dialog, and a refusal still
registers the token: `start()` calls `_askPermission()` and then `_registerToken()` whatever the
answer (`push_service.dart:117-118`; the reason is in the comment at `:180-182`). Delivery to a
real phone has not been proven yet.

| Play data type | Collected | Shared | Ephemeral | Required / optional | Purpose | Where it lives in the code |
|---|---|---|---|---|---|---|
| **Personal info › Name** | **Yes** | No | No | **Required** | App functionality, Account management | `students.full_name` (NOT NULL), `users.full_name` (NOT NULL), `students.guardian_name`, `visitors.visitor_name` (NOT NULL). **Also leaves the app**: sent to Razorpay Checkout as `prefill.name` (§2.9) |
| **Personal info › Email address** | **Yes** | No | No | Optional | App functionality, Account management | `users.email`, `students.email` (both nullable). Staff sign in by email; **students sign in by phone**, mapped to a synthetic email in Supabase Auth. **Also leaves the app** as `prefill.email` (§2.9) |
| **Personal info › Phone number** | **Yes** | No | No | **Required** | App functionality, Account management | `students.phone` (NOT NULL — it is the student's login identifier), `students.guardian_phone`, `users.phone`, `visitors.visitor_phone`. **Also leaves the app** as `prefill.contact` (§2.9) |
| **Personal info › Address** | **Yes** | No | No | Optional | App functionality | `students.permanent_address` (nullable), `hostels.address` |
| **Personal info › User IDs** | **Yes** | No | No | **Required** | App functionality, Account management, Fraud prevention & security | Supabase Auth `uid`, `users.id`, `students.id`, `hostel_id`, role. Plus `payment_intents.razorpay_order_id` and `razorpay_payment_id` — Razorpay's own transaction identifiers, stored on our side |
| **Personal info › Other info** | **Yes** | No | No | Optional | App functionality | `students.id_proof_type` — the *kind* of government ID a resident holds. See §2.3 |
| Personal info › Race and ethnicity | No | — | — | — | — | No such column exists |
| Personal info › Political or religious beliefs | No | — | — | — | — | No such column exists |
| Personal info › Sexual orientation | No | — | — | — | — | No such column exists |
| **Financial info › Purchase history** | **Yes** | No | No | **Required** | App functionality, **Fraud prevention, security and compliance** | `fee_payments` (`amount_due`, `amount_paid`, `status`, `paid_on`, `mode`, `notes`), `students.monthly_fee`, **every column of `public.payment_intents`** (§2.4) and every column of `public.payment_refunds` (`db/migrations/2026-09-02-payment-refunds.sql`, listed in [`data-safety.md`](./data-safety.md) §3.1). Fraud prevention is a genuine second purpose: `razorpay_payment_id` is held under a unique index precisely so one payment can never credit twice |
| **Financial info › User payment info** | **Yes** | No | No | Optional | App functionality, Fraud prevention, security and compliance | **Changed 2026-09-13; this row used to say "Do not tick".** On Android, Razorpay's Checkout SDK runs inside the app and handles the card and UPI details the payer types, and Play counts what an SDK sends off the device as collected (§2.1). Optional because paying online is optional. NIVORA stores none of it. See §2.4 |
| Financial info › Credit score | No | — | — | — | — | No such column exists |
| Financial info › Other financial info | No | — | — | — | — | Outstanding balances are disclosed under Purchase history |
| **Photos and videos › Photos** | **Yes** | No | No | Optional | App functionality | `students.photo_url`, `students.id_proof_url` — in the Android app a warden adds a new resident's photo and ID proof at registration, from the camera or the photo picker (`nivora_app/lib/features/warden/actions/register_student_sheet.dart:116-117`, `:324-339`). `fee_payments`/`expenses` receipts. `complaints.photo_url` (web only: the Android resident app has no photo field, `nivora_app/lib/features/student/raise_complaint_sheet.dart:28-30`) is written only by the web app (`lib/actions/student.ts:63`): the Android resident app has no complaint photo field (`nivora_app/lib/features/student/raise_complaint_sheet.dart:28-30`) and files a complaint without one (`:78-84`). Buckets `student-docs`, `complaint-photos`, `receipts` — all **private** |
| Photos and videos › Videos | No | — | — | — | — | `lib/storage.ts` `ALLOWED` permits only `image/jpeg`, `image/png`, `image/webp`, `application/pdf`. No video type is accepted |
| **Files and docs** | **Yes** | No | No | Optional | App functionality | Same buckets: `application/pdf` is accepted for `student-docs` and `receipts`, so an ID proof or a receipt uploaded as a PDF is a document, not a photo. See §2.3 |
| **App activity › App interactions** | **Yes** | No | No | **Required** | App functionality, Fraud prevention, security and compliance | `audit_log` (`action`, `target_type`, `target_id`, `actor_user_id`, `at`), `security_alerts`. Now includes ten payment events — `payment.order.created`, `payment.captured`, `payment.credited`, `payment.failed`, `payment.webhook.rejected`, `payment.reconcile.required`, and the four refund events `payment.refund.pending`, `payment.refund.processed`, `payment.refund.failed`, `payment.refund.reversed` (`lib/audit.ts:38-49`). **App functionality added 2026-09-13**, alongside the existing purpose, for the checkout interactions the in-app Razorpay SDK handles to complete a payment (§2.4) |
| **App activity › Other user-generated content** | **Yes** | No | No | Optional | App functionality | `complaints.title`/`description`/`resolution_note`, `complaint_events.note`, `leaves.decision_note` (a warden's approve or reject note, written from the Android warden app, `nivora_app/lib/features/warden/data/warden_repository.dart:484-491`), `announcements.body`, `tasks.description`, `fee_payments.notes`, `expenses.note`, `visitors.relation`. `leaves.reason` (web only: residents cannot file leave in the Android app, where wardens read and decide it, `nivora_app/lib/features/warden/data/warden_repository.dart:452-499`) is typed only on the web, where residents file leave (`app/student/leave/page.tsx`, `lib/actions/student.ts:86`); the Android app has no resident leave feature, and its only `leaves` access is the warden's list and decision (`warden_repository.dart:452-499`) |
| App activity › In-app search history | No | — | — | — | — | Not recorded |
| **App activity › Installed apps** | **Yes** | No | No | Optional | App functionality | **Changed 2026-09-13; this row used to say No** on the grounds that the manifest has no `QUERY_ALL_PACKAGES`, which is still true. Razorpay's SDK detects installed UPI apps to offer them at checkout, through the `upi` intent declared in `<queries>` in `nivora_app/android/app/src/main/AndroidManifest.xml`. See §2.4 |
| **Device or other IDs** | **Yes** | No | No | **Required** | App functionality, Fraud prevention, security and compliance | **`public.push_devices.token`, the Firebase Cloud Messaging registration token, since 2026-09-12** (App functionality; see the push paragraph above). `audit_log.ip`, `audit_log.user_agent`, `security_alerts.ip`, plus Vercel access logs (Fraud prevention). In the web app, Razorpay Checkout runs its own device/session telemetry inside its iframe; on Android the SDK runs in-process, so any device data it sends during a payment is collected by the app and belongs on this row (§2.9). See §2.5 |
| Location (approximate / precise) | **No** | — | — | — | — | No location permission in the manifest; IP is **never** used for geolocation anywhere in the code. See §2.5 |
| Messages (email / SMS / in-app) | **No** | — | — | — | — | See §2.6 |
| Health and fitness | **No** | — | — | — | — | See §2.7 |
| **App info and performance › Crash logs** | **No** | — | — | — | — | No crash reporter of any kind. Android Vitals data is collected by Google Play itself, not by the developer, and does not need declaring |
| App info and performance › Diagnostics | No | — | — | — | — | No telemetry SDK |
| Audio files | No | — | — | — | — | No audio MIME type accepted |
| Calendar | No | — | — | — | — | No calendar access |
| Contacts | No | — | — | — | — | No `READ_CONTACTS`; guardian and visitor phone numbers are typed in by staff, not read from the device address book |
| Web browsing history | No | — | — | — | — | Not recorded |

### 2.3 Government ID — read this before answering

**Play's Data safety form has no "Government ID" data type.** There is no box to tick. That is a gap
in the form, not permission to stay quiet, and NIVORA holds exactly this kind of document:
`students.id_proof_type` plus a scan at `students.id_proof_url` in the private `student-docs` bucket.
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §4.4 calls it "the highest-value
data in the system", and it is right.

Declare it in three places:

1. **Photos** — an ID scanned as JPEG/PNG/WEBP.
2. **Files and docs** — the same ID uploaded as a PDF. Both paths are open in `lib/storage.ts`, so
   both types must be ticked. Most people tick only Photos and miss this.
3. **Personal info › Other info** — `id_proof_type` is a structured personal attribute (which
   government ID a person holds) that is neither a photo nor a file.

Then say so explicitly in the privacy policy, in plain words: *this app stores identity documents.*
The Data safety form's vocabulary is too coarse for it; the policy is where the honest sentence goes.

Two live recommendations from the retention document, both of which reduce this exposure and neither
of which requires a schema change:

- Prefer a non-Aadhaar ID, or a **masked** Aadhaar. `id_proof_type` is an unconstrained `text`
  column, so nothing currently stops a warden uploading a full Aadhaar copy, which UIDAI guidance
  restricts.
- Consider storing **only the type and last four digits** and leaving `id_proof_url` null. That
  removes the single highest-consequence asset in the product, and the schema already supports it.

### 2.4 Financial info — the answer that matters most, now that money moves

**This section was rewritten on 24 August 2026, and corrected again on 2026-09-13.** Before 24 August
it said there was "no payment gateway, no PSP integration and no webhook anywhere in the codebase".
**There now is all three.** The 24 August rewrite still answered User payment info **No**, because
Razorpay's card form ran in a web iframe the app could not see. That is true of the web app and not
of the Android app, where the form is Razorpay's native SDK running inside the app, so the answer is
now **Yes**. The storage facts below did not change. What changed is that not storing payment data
no longer means not collecting it. Getting it wrong in either direction is bad: claiming you store
card data invites scrutiny you do not need, and understating collection is a violation.

#### What is actually stored

`public.payment_intents` (`db/migrations/2026-08-24-payments.sql` §2), column for column:

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

**An amount, a currency, two Razorpay reference ids, and a method string.** Plus the existing
`fee_payments`, whose `mode` remains a three-value enum:

```sql
create type public.payment_mode as enum ('cash','upi','bank');
```

**What is not there, and cannot be:** no card number, no expiry, no CVV, no cardholder name, no UPI
VPA, no bank account or IFSC, no token, no vault reference. There is no column for any of them and
no code path that would have one to write. Two facts make that verifiable rather than asserted:

1. **Nothing else is even parsed.** `app/api/webhooks/razorpay/route.ts` reads, off a
   signature-verified delivery, the `event` name and seven fields from `payload.payment.entity`:
   `id`, `order_id`, `amount`, `currency`, `method`, `error_description`, `error_reason`. On refund
   events it also reads six from `payload.refund.entity`, none of them an instrument (`id`,
   `payment_id`, `amount`, `currency`, `error_description`, `speed_processed`; read at
   `route.ts:265-285`, and [`data-safety.md`](./data-safety.md) §3.1). Everything else Razorpay sends is
   discarded with the rest of the parsed object.
2. **Nothing can write the table from outside.** RLS is on with a **SELECT policy only**, plus
   `revoke insert, update, delete on public.payment_intents from anon, authenticated`. Every write
   goes through a `security definer` function, and the three settlement ones re-check
   `app.is_service_role()` in their own bodies.

`failure_reason` is the only free-text column, and the text is Razorpay's own, capped at 200
characters — "Payment failed due to insufficient funds", not anything a user typed.

#### The answers

**Financial info › User payment info → Yes. Collected, not shared, optional; purposes App
functionality and Fraud prevention, security and compliance.**

> **This used to say "No. Still do not tick it."** The reasoning was that the card and UPI fields
> belonged to Razorpay's document, rendered in an iframe on `checkout.razorpay.com` (hence the
> `frame-src` grant in `lib/security-headers.ts`), so the app never saw a keystroke and could not
> collect what it could not access. That describes the web app. The Android app opens Razorpay's
> native Checkout SDK in its own process (`nivora_app/lib/features/payments/pay_rent.dart`; the
> versionCode 4 AAB declares `com.razorpay.CheckoutActivity`), and Play counts data an SDK in the app sends off the device
> as collected by the app, whoever receives it (§2.1). Corrected 2026-09-13.

Play's "User payment info" is information about a user's financial accounts, such as a card number.
While a payment is open, the SDK handles exactly that: the card or UPI details the payer types, which
it sends to Razorpay. So:

- **Collected: Yes.** An SDK inside the app transmits it off the device.
- **Shared: No.** Razorpay is a service provider completing a payment NIVORA started (§2.1).
- **Optional.** A resident can pay the warden at the desk instead, and most hostels cannot take
  online payment at all (§5).
- **Purposes: App functionality** (taking the payment) **and Fraud prevention, security and
  compliance** (the checks a payment goes through).

**What did not change: NIVORA stores none of it.** The column list above has no field for a card, a
UPI ID or a bank account. That is worth saying in the privacy policy, but it is a storage fact, and
the Data safety question is about collection.

**Financial info › Purchase history → Yes, and it now covers more than the fee ledger.** A record of
transactions that occurred is exactly what `fee_payments` + `payment_intents` are. Add *Fraud
prevention, security and compliance* as a second purpose: `razorpay_payment_id` is stored under a
unique partial index specifically so the same payment can never credit twice.

**Other financial info stays No.** Play defines it as salary, debts and similar. An outstanding rent
balance is a transaction record, disclosed under Purchase history.

#### The other two rows the SDK changed

**App activity › Installed apps → Yes. Collected, not shared, optional; purpose App
functionality.** The SDK builds its list of UPI apps (GPay, PhonePe, Paytm) by resolving the `upi`
intent that `nivora_app/android/app/src/main/AndroidManifest.xml` declares in `<queries>`. The
earlier answer, No because there is no `QUERY_ALL_PACKAGES`, looked only at the app's own code and
missed the SDK. Optional for the same reason as above.

**App activity › App interactions → add App functionality** alongside the existing Fraud prevention
purpose, for the checkout interactions the SDK handles to complete a payment. The audit-log
reasoning for the existing purpose is unchanged.

#### When these answers change again

This heading used to read *When "User payment info" flips to Yes*, and named the trigger as a card,
UPI or bank field rendered by our own form. The trigger turned out to be an SDK inside the app, which
the Android build already had. These three answers now follow that SDK. If the Android app ever stops
bundling it, check them against whatever replaces it rather than flipping them back by default.

### 2.5 IP address and user agent

`audit_log` stores `ip` and `user_agent` on every privileged action, and `security_alerts.ip` on
every detection. Both are persisted, not ephemeral, and Vercel keeps its own access logs.

**Declare this under "Device or other IDs", purpose "Fraud prevention, security and compliance."**
The same row carries the FCM registration token for **App functionality** (§2.2), so the row
declares both purposes.
Google's guidance is that identifiers should be declared according to how they are actually used, and
an IP plus user-agent pair retained for 90 days is a device-linked identifier held for security. It
is required rather than optional, because a user cannot switch it off.

**Do not declare Location.** Google's guidance is specifically that IP must be declared as location
*where it is used to determine location*. Searched the codebase: it is not. IP is written to the
audit trail and used for rate limiting, and `lib/rate-limit.ts` hashes its keys so no clear IP is
even stored there. There is no geolocation lookup, no region inference and no location feature in the
product.

The 90-day nulling of `ip`/`user_agent`
([`logging-and-monitoring.md`](./logging-and-monitoring.md) §4) is good retention hygiene and worth
stating in the privacy policy, but it does **not** make the data ephemeral for Data safety purposes.
Ephemeral means never written down at all.

### 2.6 Messages — why "No", and when to reconsider

Complaints, resolution notes, announcements and leave reasons are text that moves between residents
and staff. Play's "Messages" category is aimed at messaging content — emails, SMS, chat. This is
threaded record-keeping on a work item, not a chat feature, and Play's own guidance puts content
users create into **App activity › Other user-generated content**, where the table declares it.

Recommendation: **Messages = No.** But it is a judgement call, not a fact, so record the reasoning
(this section) and know that ticking "Other in-app messages" as well is defensible and costs nothing
if the reviewer sees it differently.

**This is a different question from the content-rating one in §3**, where the answer *is* yes.
Content rating asks whether users can interact and exchange content — they can. Data safety asks
whether the app collects messaging content as a data type. Answering them differently is correct, not
inconsistent.

### 2.7 Health — why "No", with an honest caveat

The app has no health feature and no health column. `leaves.reason` is free text, and
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §4.1 flags that leave reasons
"routinely contain sensitive context" — a resident writing "hospital, mother's surgery" has put
health information into the system.

That does not make this a health app, and ticking "Health info" would misdescribe the product: the
app does not solicit, structure or process health data. **Answer No**, and mitigate at the source —
guidance to wardens not to record medical detail, and ideally a short hint under the reason field.
Incidental free-text content is a data-minimisation problem, not a Data safety declaration.

### 2.8 Security practices section

| Question | Answer | Evidence |
|---|---|---|
| Is all user data encrypted in transit? | **Yes** | TLS to Vercel and to Supabase throughout; HSTS and a nonce-based CSP set in `middleware.ts`; `nivora_app/android/app/src/main/AndroidManifest.xml` sets neither `usesCleartextTraffic` nor a `networkSecurityConfig`, so cleartext HTTP is blocked by the API-28+ default |
| Do you provide a way for users to request that their data be deleted? | **Yes** | The in-app "Delete my account and data" request and the deletion request URL in §7, backed by the erasure runbook in [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.3. Be aware of what you are claiming — see the caveat below |
| Has your app been independently reviewed against a global security standard? | **No** | `SECURITY.md` is a thorough internal review. It is not a third-party audit, and claiming otherwise in Console is a misrepresentation |
| Committed to follow the Play Families Policy? | **No** | Not a children's app — see §4 |

**The deletion caveat, stated plainly.** Deletion is a *request*, confirmed and then carried out,
not an instant erase ([`account-deletion.md`](./account-deletion.md) §1 explains why). There are two
ways to file one, and Play asks for both. **In the Android app**, "Delete my account and data" files
it: residents open it from the Profile tab (`nivora_app/lib/features/student/profile_screen.dart:160`),
staff by tapping their picture at the top left
(`nivora_app/lib/features/shell/staff_profile_sheet.dart:139`). A second tap within 30 days returns
the request already on file and files nothing new
(`nivora_app/lib/features/legal/account_deletion.dart:83-84`). **On the web**, anyone can ask through
`/legal/account-deletion`. Three things must be true before ticking Yes:

1. `/legal/account-deletion` is live, loads without error, names the app, and gives a working way to
   ask (a form or a monitored email address). Since legal version 2026-09-13 went live on
   2026-09-13, the page also describes the in-app route (§7.1).
2. Someone actually answers. The runbook at §6.3 of the retention document is marked
   **"written, not executed"** — it has never been run against production. Dry-run it on a Supabase
   branch before the first real request arrives, not after.
3. **The page tells the truth about payment records**, which now exist. See §2.10.

### 2.9 What actually leaves the app for Razorpay

More than nothing, so answer it honestly if asked.

| Sent | From | What it is |
|---|---|---|
| `amount`, `currency: "INR"` | `orders.create()` in `lib/actions/payments.ts` | The server's figure, derived from the student's own ledger. `createRentOrder()` takes no arguments — there is no amount for a client to name |
| `receipt: rent_<YYYY-MM>_<first 8 chars of student uuid>_<base36 timestamp>` | same | Deliberately no PII. A truncated UUID is a lookup key for us and meaningless to anyone else |
| `notes: { purpose: "hostel_rent", period }` | same | For a human reading the Razorpay dashboard. Nothing on the settlement path ever reads it back |
| `name` (the hostel's name), `description` (`"<Month YYYY> rent"`) | Checkout options, `components/payments/pay-rent-sheet.tsx` | Branding on the modal |
| `prefill: { name, email, contact }` | same, from `RentOrder.prefill` | **The student's own `full_name`, `email` and `phone`**, so they do not retype them |

So Razorpay receives the payer's name, email and phone. Under Play's definitions that is a transfer
to a **service provider** (§2.1) — it is **not** "shared" — and the place it gets disclosed is the
**privacy policy**, which names Razorpay as a sub-processor (§7.1).

That table is the web app's order. On Android, `supabase/functions/razorpay-order` sends the same
amount, receipt and notes (with `channel: "mobile"` added, `index.ts:281-291`), and for a hostel on
Route it adds a `transfers` entry. The web's `orders.create()` never sends `transfers`
(`lib/actions/payments.ts:128-138`); §5 explains why that is latent rather than live.

**Razorpay Checkout's own telemetry**, since a reviewer may notice it. In the **web app**, Checkout
runs device and session telemetry to `lumberjack.razorpay.com` during a payment. Two bounds:

- **It is not granted `connect-src` in our document.** `lib/security-headers.ts` allows only
  `https://api.razorpay.com`, with the comment "lumberjack telemetry deliberately NOT granted", so
  the loader Checkout draws in *our* page cannot reach it.
- **Inside its own iframe our CSP does not apply** — a cross-origin frame carries its own policy.
  That telemetry is Razorpay's, serving the payment's own fraud and operational purposes, and
  **NIVORA receives none of it.**

**Neither bound exists in the Android app.** There the order is created by
`supabase/functions/razorpay-order`, the same name, email and phone are passed as `prefill` by
`_openSheet` in `nivora_app/lib/features/payments/pay_rent.dart`, and Razorpay's native SDK runs
in-process: no CSP and no cross-origin frame. What it handles or sends while a payment is open is
collected by the app under Play's definition (§2.1), even though NIVORA receives none of it.

Declaration consequence, **corrected 2026-09-13**. This used to read "no new row", which was the web
app's answer. For the Android app the SDK accounts for **User payment info** and **Installed apps**
(both Yes) and for the added **App functionality** purpose on App interactions (§2.4). Device and
session data it sends stays under the existing *Device or other IDs* row. It is still **not shared**,
and **Analytics is still not a purpose**.

One more web-app bound worth knowing: the Razorpay CSP grants are **scoped to `/student`** —
`needsRazorpay()` in `lib/security-headers.ts` returns true only for `/student` and below. No other
page in the app, including every screen that renders resident PII, can load Checkout at all.

### 2.10 What deletion does to a payment record

Play's deletion question is answered **Yes** and stays Yes. But a deletion page that promises total
erasure and does not deliver is worse than one that is honest about the boundary, and payment
records are exactly where that boundary sits.

**Deleted with the resident.** `payment_intents.student_id` is
`references public.students(id) on delete cascade`, so deleting the student row takes their payment
intents with it — the same behaviour as `fee_payments`.

**Retained, with the person taken out.** Where the hostel's accounting duty means the ledger must
survive, the resolution is [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.4:
**anonymise instead of delete.** `payment_intents` takes that unusually well — look again at the
column list in §2.4 and note what is absent. **No name, no phone, no email, no address.** UUIDs,
money, dates, two Razorpay reference ids and a method label. Once `students` and `users` are
anonymised, the payment rows identify nobody.

**For how long: the same period as the rest of the fee ledger, which is kept indefinitely** — the
period the published policy states and [`data-retention-and-privacy.md`](./data-retention-and-privacy.md)
§5.2 records. The hostel's statutory accounting duty is why it is kept, and NIVORA does not shorten it.
Do not invent a shorter period for `payment_intents`; it is part of the same financial record as the
`fee_payments` row it credited, and splitting them leaves a credit with no evidence behind it.

**Abandoned attempts are marked, not removed.** `rz_expire_stale_intents()` moves a `created` row
that went nowhere to `expired` after a day ([`payments.md`](./payments.md) §7). It marks; it does
not delete, so an expired row is still a retained record on the schedule above.

**What NIVORA cannot reach.** Razorpay holds its own record of the transaction under its own
regulatory retention duty, and an erasure request to NIVORA cannot touch it. Say so on the deletion
page, next to the existing honest note about backups
([`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.5).

---

## 3. Content rating questionnaire

The rating is issued by IARC from a questionnaire; Google does not rate the app itself. Answer it
honestly — an inaccurate rating is grounds for removal.

**Category: "Utility, Productivity, Communication, or Other."** Not a game.

| Question | Answer | Reasoning |
|---|---|---|
| Violence — realistic, fantasy, or otherwise | No | None |
| Sexuality or nudity | No | None |
| Profanity or crude humour | No | None. Free-text fields could theoretically contain anything, but that is user conduct within one private tenant, not app content |
| Controlled substances — drugs, alcohol, tobacco | No | None |
| Gambling, real or simulated | No | None |
| Horror or fear themes | No | None |
| **Do users interact or exchange content or information?** | **Yes** | Complaints, resolution notes, notices and tasks flow between residents and staff, and wardens decide leave requests. Answer yes even though the content never leaves the tenant — the question is about capability, not reach |
| Can users share their current location with other users? | No | No location capability of any kind |
| Is unrestricted internet access provided (an open browser)? | No | The Android app is a Flutter build with no browser and no address bar. `nivora_app/pubspec.yaml` declares no WebView or `url_launcher` dependency, but `supabase_flutter` depends on `url_launcher`, so it is resolved transitively (`nivora_app/pubspec.lock:1191-1206`), and `url_launcher_android` 6.3.32 declares a non-exported `io.flutter.plugins.urllauncher.WebViewActivity` in its plugin manifest, which is merged into the app's. Nothing in `nivora_app/lib` calls `launchUrl`, so nothing opens it, and the answer stays No. This used to cite the TWA's `autoVerify` binding to `hostelpro-three.vercel.app`; the TWA is retired |
| **Can users purchase digital goods?** | **No** | Rent is a **real-world service** — a bed in a physical building for a calendar month — not a digital good. There is no Play Billing library and no digital product of any kind. If the questionnaire also asks about **real-world** purchases, that one is **Yes**: a resident can pay rent from the app. See §5, which explains why Play requires this to sit outside Play Billing |
| Does the app share personal information with third parties? | No | Service providers only — Supabase, Vercel, Razorpay and Google (Firebase Cloud Messaging). See §2.1 for why a payment processor is not a third party under this question |
| Is this a news app? | No | — |

**Expected outcome: Everyone / PEGI 3 / IARC "3+"**, most likely with a mild social-interaction note
because of the "users interact" answer. That note is normal for a business app and costs nothing.

Do not be tempted to answer "no" to the interaction question to avoid the descriptor. It is the one
answer on this questionnaire a reviewer can trivially verify by opening the complaints screen.

---

## 4. Target audience and content

### 4.1 The answer

**Target age group: 18 and over. Select nothing below 18.**

**"Could your app unintentionally appeal to children?" → No.** It is a property-administration tool.
There is nothing in it — no characters, no games, no bright cartoon styling, no child-oriented
content — that would draw a child in. The store listing itself says you cannot sign up.

Consequence: NIVORA is **not** in the Designed for Families programme, is not subject to the Play
Families Policy, and the "Committed to follow Families Policy" answer in §2.8 is No.

### 4.2 The part that deserves honesty rather than a shrug

**Some residents of some hostels will be under 18.** PG and hostel residents in India routinely
include school and junior-college students.
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §3 says this outright and does not
soften it. Pretending otherwise in this document would be worse than useless.

So why is "18 and over" still the right answer? Because Play's question is about **who the app is
designed and marketed for**, not about who might conceivably end up holding a phone with it
installed. NIVORA is sold to hostel operators; its users are owners, managers, wardens and
residents of a business's premises; and a minor resident reaches it only because an adult member of
staff created an account for them. Selecting an under-18 age group would pull the app into the
Families programme and its content, ads and data requirements — a programme built for children's
media, which this is not, and which NIVORA would fail on paperwork it has no reason to produce.

What the honest position does require:

1. **The app cannot detect a minor.** There is no `date_of_birth` and no age column anywhere in
   `db/schema.sql` — verified. It cannot apply an age gate because it does not know.
2. **The privacy policy must not claim the service is adults-only.** It is not. Claiming so would be
   a false statement that the schema contradicts.
3. **The India-specific duty falls on the hostel operator, not on Play.** DPDP §9 requires verifiable
   parental consent before processing a child's data, and prohibits tracking, behavioural monitoring
   and targeted advertising directed at children. The **prohibitions are satisfied by construction**:
   no ads, no ad ID, no analytics, no tracking SDK, no behavioural profiling — verified in
   `package.json`, `nivora_app/pubspec.lock` and the Android manifest (§2.2). The **consent duty**
   cannot be discharged by the product, because the product cannot tell who it applies to. It must
   be a written obligation in the
   tenant contract, handled in the hostel's own registration paperwork.
4. **Record the decision.** §3 of the retention document asks for a dated choice between "keep age
   out of the system and handle consent out of band" and "add a minor flag". The current de facto
   answer is the first. Write it down with today's date so it is a decision and not a drift.

None of this changes the Play answer. All of it changes what has to be true before a real tenant is
onboarded.

---

## 5. The declarations

All of these live under **App content** in Play Console.

| Declaration | Answer | Evidence |
|---|---|---|
| **Ads** — does your app contain ads? | **No** | No ad SDK in `package.json` or `nivora_app/pubspec.lock`; the Android manifest removes `com.google.android.gms.permission.AD_ID` (§2.2), and the versionCode 4 permission dump and AD_ID check found none (technical report §2). Run both again on the versionCode 5 upload. The "Contains ads" badge will not appear on the listing |
| **In-app purchases** | **No** | The label describes **Google Play Billing** products. There is no Play Billing library (`nivora_app/pubspec.lock` resolves no billing or `in_app_purchase` package) and no Play product to sell. Rent is an external, real-world payment, which that badge does not describe — see below |
| **Government app** | **No** | A private commercial product. Not developed by or on behalf of any government |
| **Financial features** | **"My app doesn't provide any financial features."** | Still the right answer now that the app takes payments — but for a reason, not by default. See below; this is the one a reviewer probes |
| **Health** | **No health features** | No health data collection, no medical device integration, no health claims. The `leaves.reason` free-text caveat in §2.7 is a minimisation note, not a health feature |
| **News app** | **No** | — |
| **COVID-19 contact tracing / status** | **No** | — |
| **Data safety** | Completed per §2 | — |
| **Content ratings** | Completed per §3 | — |
| **Target audience and content** | Completed per §4 | — |
| **App access** | **Required — see §6** | The whole app is behind a login |
| Content guidelines + US export laws acknowledgements | Accept | Standard |

### Payments — the question a reviewer is most likely to ask

> *"Your app takes money and does not use Google Play Billing. Why is that allowed?"*

**Because hostel rent is a real-world service, and Play's Payments policy requires it to be paid
outside Play Billing rather than merely permitting it.**

Play's billing requirement applies to **digital goods and services consumed within the app**.
Payments for **physical goods and real-world services** must use an alternative payment method —
Play lists exactly this category: physical goods, one-to-one real-world services, transport, food
delivery, accommodation. Using Play Billing for rent would itself be the violation.

Hostel rent is as real-world as the category gets, and each of these is checkable in the code:

- **The thing bought is a bed in a physical building for a calendar month.** `payment_intents` binds
  every payment to a `student_id`, a bed-holding resident record, and a `period_month` matching
  `^\d{4}-(0[1-9]|1[0-2])$`.
- **It is consumed off-device.** Nothing in the app is unlocked, upgraded or enabled by paying — no
  code path gates any feature on `payment_intents.status` or `credited_at`. The only thing a
  successful payment changes is a row in `fee_payments`, which is a ledger entry.
- **The money is the hostel's, not NIVORA's.** The app collects what the resident already owes their
  landlord under a tenancy that exists outside the app. `rz_credit_fee()` credits the ledger by
  calling the warden's own `wd_record_payment()` — the same function used for a cash payment taken
  at the desk.

**The contrast, and say it plainly if asked.** An owner paying NIVORA a platform subscription
*would* be a digital service consumed in the app, and on Android that is Google Play Billing
territory. [`payments.md`](./payments.md) puts that flow explicitly out of scope — *"Owners paying
their platform subscription is a separate flow and is not built here"* — and `public.subscriptions`
is a record the NIVORA administrator maintains, with no in-app purchase path. **Keep it that way, or
bring in Play Billing when it changes.** An in-app "renew your NIVORA subscription" button charging
through Razorpay would be a Payments-policy violation on the day it shipped.

### Financial features — still "none", now for a reason

Play's Financial features declaration covers financial **products and services**: lending, banking
or e-money, insurance, investments, crypto, debt management, money management or planning, tax.
**None apply.** Select *"My app doesn't provide any financial features."*

The distinction is real rather than a technicality, and it survived the payment feature:

> NIVORA **collects a payment for its tenant's own service, through a licensed gateway.** It does
> not **offer a financial product.**

An e-commerce app taking card payments declares no financial feature either, for exactly this
reason. NIVORA issues no credit, holds no balance, offers no account, and moves no money between
people. What it does is create an order for what a resident owes, hand it to Razorpay, and record
what Razorpay reports.

**Where the rent settles today, verified 2026-09-13.** Two settlement paths exist in code, and the
database decides which one a hostel gets. `rz_open_intent` and the `razorpay-order` Edge Function
read the same three columns but not in the same order, so they disagree in one state, a linked
account plus an out-of-date DIRECT approval; `docs/data-safety.md` §4.1 has the exact conditions. In
outline:

- **Route.** A hostel with a linked account (`hostels.razorpay_account_id`, an `acc_...`) gets an
  order carrying `transfers: [{ account: <that account>, amount: <the whole sum>, on_hold: false }]`
  (`supabase/functions/_shared/razorpay.ts`). **No hostel has a linked account:** read-only SQL on
  2026-09-13 found `razorpay_account_id` null on all four hostels.
- **Direct.** A hostel whose `razorpay_direct_for_owner` equals its current `owner_user_id` gets an
  order with no `transfers`, so the rent settles to the merchant account whose API keys the app
  uses. **Exactly one hostel, Kushi Hostels, is approved.** The operator confirmed on 2026-09-13 that
  this merchant account is KYC'd to Kushi Hostels' owner. The approval names the owner, not the
  hostel: if the hostel changes hands, online payment stops rather than paying the previous owner.
  On Android the resident sees the "not set up" refusal below, because `razorpay-order` treats an
  approval naming a previous owner as no approval and refuses with HTTP 409
  (`supabase/functions/razorpay-order/index.ts:233-243`) before `rz_open_intent` is called (`:307`).
  `rz_open_intent`'s own message, "Online payment is paused for this hostel while its ownership
  change is reviewed", is what the web path shows. The same owner's other hostel is not approved.
- **Neither.** Every other hostel, including the demo PG a reviewer signs into, cannot take online
  payment at all. On Android, `razorpay-order` refuses with HTTP 409 and "Online payment is not set
  up for this hostel yet. Please pay your warden directly." before any Razorpay order is created
  (`index.ts:238-242`). The web's `createRentOrder` refuses too, with the same message from
  `rz_open_intent`, but only after it has already created a Razorpay order
  (`lib/actions/payments.ts:128`, then `rz_open_intent` at `:146`).

So the only rent that moves online today goes from Kushi Hostels' residents to an account KYC'd to
Kushi Hostels' owner. NIVORA takes no commission out of rent and holds no balance; its own revenue
is a subscription the owner pays, recorded separately and never through this gateway. The Payment
Aggregator question the earlier text raised does not arise as things stand.

**A latent defect in the web order path, not fixed.** `createRentOrder` creates the Razorpay order
before `rz_open_intent` checks the hostel, and its `orders.create()` never sends `transfers`
(`lib/actions/payments.ts:128-146`). With no hostel on Route, the only effect today is an unpaid
order left behind whenever it runs for a hostel that cannot take online payment. If a hostel were
given a linked account, a web payment would settle to the merchant account instead of that linked
account. It is tracked as a separate code fix, and must be fixed before any hostel goes on Route.

> **On 2026-09-13 (commit `2bad96b`) this paragraph was rewritten to say that "every hostel carries
> its own linked account"**, under a heading dated 2026-09-06. That described the code, not the data:
> Route is implemented (its migration arrived in `01b87cf` on 2026-09-06), but no hostel has a linked
> account, and the one hostel taking online payment does so through the direct path. Corrected the same
> day. The text before it, from `327b8e2` (2026-08-24), ran the other way (one merchant account, no
> Route, no transfers, "verified by grep") and warned that settling into NIVORA's account would be
> Payment Aggregator territory; it went stale when Route shipped on 2026-09-06.

**Answer one question before a second hostel takes online payment.** Route transfers leave the
merchant account whose keys the app uses, and today that account is KYC'd to Kushi Hostels' owner,
not to NIVORA. Giving another owner's hostel a linked account would therefore pass that owner's rent
through Kushi Hostels' owner's account on its way. Settle whose account the parent should be first.
If it becomes NIVORA's, and NIVORA then pays hostels, that is Payment Aggregator territory under the
RBI's PA/PG directions: a different product with a different licence, and a Financial features
answer that would have to be revisited alongside it.

**Revised 24 August 2026.** The previous version of this section said there was "no gateway, no PSP,
no webhook, no card vault, and exactly one outbound HTTP call in the entire codebase". That is no
longer true, and the paragraph it pointed at in the store listing has been replaced (§1). What
survives is the answer, not the reasoning that used to support it.

---

## 6. App access — the one that blocks review for this app

**Play Console → App content → App access → "All or some functionality is restricted."**

This is not optional and it is not a formality. NIVORA has **no public sign-up by design**: the
Super Admin creates Owners, the Owner creates Managers and Wardens, the Warden registers Students.
A Play reviewer who installs the app sees a login screen and can go no further. An app a reviewer
cannot get into is rejected — this is one of the most common rejection reasons for B2B products, and
it is entirely avoidable.

Provide, in Console:

1. **One instruction set per demo account, four in all:** **Warden**, **Resident**, **Manager** and
   **Owner** (Console allows up to five). They show different apps. The warden set covers
   registration, rooms, fees taken at the desk, complaints, leave requests and visitors; the resident
   set is the only place a reviewer sees rent and the payment screen (every set can reach "Delete my
   account and data": residents from Profile, staff by tapping their picture);
   the manager set covers expenses and the mess menu; the owner set covers the property dashboard and
   staff.
2. **Instructions in English**, covering the thing a reviewer will not guess: **residents sign in
   with a phone number, not an email address.** Say so explicitly, with the exact phone number to
   type.
3. **Credentials that keep working.** Play requires them to be valid at all times and reusable, and
   specifically requires that a reviewer is not blocked by a one-time code. Two consequences for this
   app:
   - The demo accounts must have `must_change_password = false`, or the reviewer hits the forced
     password-change screen and stops.
   - **Owner always needs two-step verification, and cannot be exempted without a new build.**
     `mfaRequiredRoles` at `nivora_app/lib/core/auth/auth_controller.dart:122` is a compile-time
     `const {superAdmin, owner}` with no runtime source, so changing `MFA_REQUIRED_ROLES` on Vercel
     or `app.mfa_required_roles()` in Postgres does **not** let an owner in without a code. Once a
     factor is enrolled, every sign-in asks for its code (`mfaGate` returns `codeOwed`,
     `auth_controller.dart:164`). So, **for the demo owner only**, the operator enrols the
     authenticator before submitting and pastes its **SETUP KEY** into the owner's instruction set;
     every reviewer adds that same key to their own authenticator app and can sign in again and
     again. The steps are Set 4 in
     [`play-console-submission.md`](./play-console-submission.md#app-access--what-to-enter-in-console).
     This was decided on 2026-09-13. It replaces the earlier advice to leave the demo owner with no
     factor for the reviewer to enrol, which would have locked out every reviewer after the first.
     The key protects only fabricated data. **For a real owner the rule stays: never hand over a
     TOTP seed.**
4. **A demo tenant with realistic data.** An empty hostel looks like a broken app.

### 6.1 The demo tenant that now exists

Built 2026-09-04 in the live project, deliberately as a **separate hostel** so a reviewer never sees
a real resident's name, phone, guardian details or ID proof. Re-read with read-only SQL on
2026-09-13:

| Role | Signs in with | Notes |
|---|---|---|
| Warden | `demo.warden@nivora.app` | No two-step verification for this role: after the intro screens and **Agree and continue**, the warden shell |
| Resident | phone `9000000001` | **A phone number, not an email** — the app maps it to a synthetic address internally |
| Manager | `demo.manager@nivora.app` | **Not created yet** (re-read 2026-09-14). The operator creates it from the demo owner's staff screen before submitting (Set 3; §9 step 7). The temporary trigger below spares it the email proof |
| Owner | `demo.owner@nivora.app` | Owns Demo PG. No factor enrolled yet; the operator enrols one before submitting and gives reviewers its setup key (§6 item 3, Set 4) |

Hostel **"Demo PG (Play review)"**: one resident, one open and one resolved complaint, and, from the
2026-09-13 seed (`db/migrations/2026-09-13-demo-pg-play-review-seed.sql`), four months of expenses,
a week's mess menu (28 meals), three notices in all, a pending and an approved leave, and two
visitors. **No Razorpay account is linked to it, on purpose.** The warden, resident and owner
accounts have `must_change_password = false`. None of them has signed in since 6 September, so sign
in to each one on a phone before submitting.

**A temporary exception for demo addresses, applied to production on 2026-09-13.** A new staff
account changes its temporary password on first sign-in. After that change, an account without a
proved email address is sent to a verify-email screen that cannot be dismissed
(`nivora_app/lib/features/auth/change_password_screen.dart:190-191`). The Edge Functions that create
accounts also refuse an unverified caller (`requireVerifiedEmail()`,
`supabase/functions/_shared/verification.ts:108`). Nobody reads mail sent to `demo.*@nivora.app`.
`db/migrations/2026-09-13-demo-review-skip-email-verification.sql` therefore adds the trigger
`users_zz_demo_review_email_verified`. Before insert, or on update of the email, it stamps
`public.users.email_verified_at` only when all of these hold:

- the row is in Demo PG (`d3300000-0000-4000-8000-000000000001`);
- the address is `demo.<name>@nivora.app`;
- the row is not already stamped;
- on an update, the address itself changed.

These conditions are in the migration at lines 21-25 and 42-55. It fires after `users_update_guard`
(lines 29-31; the trigger was present in production on a read-only check on 2026-09-14). A
rolled-back probe confirmed each case. The owner, warden and resident were verified on 2026-09-04.
The account it exists for is `demo.manager@nivora.app`, so that account neither hits the
verify-email screen nor is refused if it ever creates accounts. Every real hostel still owes the
proof. **It is temporary. Remove it after review** (§9 step 30):

```sql
drop trigger if exists users_zz_demo_review_email_verified on public.users;
drop function if exists app.demo_review_email_verified();
```

**The passwords are not in this file, and must not be** — see the rule below. They were handed over
separately and belong in the Console form and the team's private ops record.

### 6.2 The instructions to paste into the App access form

Use the four per-account instruction sets under
[App access — what to enter in Console](./play-console-submission.md#app-access--what-to-enter-in-console)
in `play-console-submission.md`: Set 1 Warden, Set 2 Resident, Set 3 Manager (once that account
exists) and Set 4 Owner, with the demo owner's setup key pasted in place of `SETUP KEY`. Add each as
its own instruction set in Console, with the username and password in Console's own fields and the
matching block in "Any other information". That file holds the only copy of the text.

**Do not put these credentials in this file, in the repository, or in any screenshot.** They go into
the Play Console App access form and into whatever private ops record the team keeps. Rotate them
after the review completes.

---

## 7. Required URLs

| Where | URL | Status |
|---|---|---|
| Store listing → Privacy policy | `https://hostelpro-three.vercel.app/legal/privacy` | **HTTP 200 ✔** since 24 Aug 2026. At 20:53 IST on 2026-09-13 it carried legal version 2026-09-13, the text the Data safety answers rely on, and no longer mentioned 2026-09-12 (§7.1) |
| App content → Data safety → data deletion | `https://hostelpro-three.vercel.app/legal/account-deletion` | **HTTP 200 ✔** since 24 Aug 2026. At 20:53 IST on 2026-09-13 it carried version 2026-09-13, including the in-app deletion route (§7.1). **The package it names is not live yet.** The page prints `ANDROID_PACKAGE` (`app/legal/account-deletion/page.tsx:142`), which the code sets to `com.nivorasr.app` (`lib/legal-config.ts:96`), but a signed-out GET on 2026-09-14 still found `com.srnivora.app`. Push the change and re-check before §9 step 18 |
| ~~Digital Asset Links~~ | `https://hostelpro-three.vercel.app/.well-known/assetlinks.json` | **Retired with the TWA.** The file still names `app.nivora.twa`, and `com.nivorasr.app` declares no `autoVerify` link, so nothing in this submission depends on it (§9 step 14) |

The 307-to-`/login` blocker recorded here on 21 August is **resolved**: `PUBLIC_PATHS` in
`lib/supabase/middleware.ts` now includes `/legal`, `app/legal/` exists with `privacy`,
`terms` and `account-deletion` routes, and all three are deployed. Re-verify any time with:

```sh
for u in /legal/privacy /legal/account-deletion /legal/terms; do
  curl -sS -o /dev/null -w "$u -> HTTP %{http_code}\n" "https://hostelpro-three.vercel.app$u"
done
```

### 7.1 RESOLVED (2026-09-02) — the legal pages predated payments

> **2026-09-13: a new gate, which the table below does not cover, now met on the web.** Legal
> version **2026-09-13** is in production's `public.legal_versions`, effective 2026-09-12 18:30 UTC.
> It says that on Android Razorpay's checkout runs inside the app and, while a payment is open, takes
> the card, UPI or netbanking details typed and checks which UPI apps are installed, and that card
> and UPI details go to Razorpay, never to NIVORA. It lists ten Android permissions, says Google
> receives the registration token and each notification's title and body through Firebase Cloud
> Messaging, and describes the in-app deletion route (`app/legal/privacy/page.tsx:215`, `:253`,
> `:260`, `:442`, `:447`, `:618`). The web pages carry it (`lib/legal-config.ts:80`) and are live:
> commit `4fd41ef`, which moved `LEGAL_VERSION` from 2026-09-12 to 2026-09-13, reached `origin/main`
> at 20:44 IST on 2026-09-13, and at 20:53 IST the deployed `/legal/privacy` said "currently
> 2026-09-13", carried the in-app checkout and UPI-app sentences, the ten permissions and the
> notification title-and-body row, and nowhere mentioned 2026-09-12. The in-app copy
> (`nivora_app/lib/features/legal/legal_documents.dart:46`) reaches users with versionCode 5.
> **Submit the User payment info, Installed apps and App interactions answers in §2 together with
> versionCode 5, and on that day check that the live policy still carries that text.** Before the
> deploy the live policy did not describe what those answers declare, which is exactly the
> contradiction this section warns about.
>
> **Status of the 2026-09-02 fixes: fixed and verified rendering locally.** All four
> contradictions in the table below have been corrected, and the pages additionally gained the
> consent record, the Google (email)
> sub-processor, the Singapore hosting region and the current retention periods. See
> [`legal-consent.md`](./legal-consent.md) for what was built and, in its §6, the list of operator
> details that still must be confirmed before the URL goes into Console.
>
> The retention dependency once noted here is closed: `app.apply_retention()` removes complaints and
> notices at 2 months, as the policy publishes ([`legal-consent.md`](./legal-consent.md) §7 item 1,
> resolved 2026-09-04).
>
> The original finding is kept below because it is the reasoning, and because it is the check to
> re-run whenever a feature changes what the app does with data.

#### The original finding

**A policy that does not match the Data safety form is itself a violation**, and Google fetches the
policy URL. Three of the four live legal pages currently state the opposite of what §2 declares,
because they were written before `payment_intents` shipped:

| Page | What it says today | Why that is now false |
|---|---|---|
| `/legal/privacy` | *"there is no payment processor, no messaging provider, no analytics vendor…"*, above a three-row sub-processor table | Razorpay is a fourth sub-processor and receives the payer's name, email and phone (§2.9) |
| `/legal/privacy` | Under **"What is never collected"**: *"No card, bank account or UPI handle. Fee payments happen offline… NIVORA never takes, holds or moves money."* | Payments no longer happen only offline. The card/UPI half is still true and worth keeping — the *reason* has changed from "we don't take payments" to "Razorpay's form collects them, not ours" |
| `/legal/account-deletion` | *"There is no advertising network, no analytics service, no payment processor and no email or SMS provider in the picture."* | Same. Its fee-retention table (name removed; the period read 8 years then, and has read "kept indefinitely", matching the privacy policy, since 2026-09-13) covers `payment_intents` by extension — but Razorpay's own retained record is not mentioned (§2.10) |
| `/legal/terms` §9 | Titled *"Payments are recorded, not processed"*; *"NIVORA is not a payment service."* | Rent can now be collected in-app |

**All four are now corrected** (2026-09-02) — see the status note at the head of this section. The
warning that produced them stands as a standing rule: **do not paste the privacy-policy URL into
Console while any claim on it contradicts the Data safety form.** A reviewer comparing the two finds
the contradiction in under a minute, and "our docs were stale" is not a defence that Play accepts
for a legal declaration.

Two further claims were found false during the fix and corrected at the same time, neither of which
was in the table above:

| Page | What it said | Why it was false |
|---|---|---|
| `/legal/privacy` | *"No email or SMS is sent. There is no messaging provider connected"* | The project sends email-verification and password-reset mail through Gmail SMTP. Google is now named as a sub-processor |
| `/legal/privacy` §9 | The hosting region *"is a configuration setting held by the operator… this page does not guess at it"* | The region is known and recorded in [`server-health.md`](./server-health.md): `ap-southeast-1`, Singapore. The page now states it |

### 7.2 What the privacy policy has to actually say

Drawn from [`data-retention-and-privacy.md`](./data-retention-and-privacy.md), with the payment
items marked:

- The data in the §2 table, in plain words, including **identity documents** (§2.3).
- That the hostel operator is the data fiduciary and NIVORA is the processor (retention doc §2).
- **Supabase, Vercel, Razorpay and Google named as sub-processors**, with what each does (retention
  doc §7, which now lists Razorpay and Google).
- What Razorpay receives (name, email, phone, amount, order id — §2.9) and what it does not send
  back. **On Android, say both halves together:** Razorpay's checkout runs inside the app and, while
  a payment is open, takes the card, UPI or netbanking details typed and checks which UPI apps are
  installed; and those details go to Razorpay, never to NIVORA. "Never reach NIVORA" on its own is
  true of NIVORA's servers but reads as a denial of the User payment info and Installed apps answers
  in §2.4. Legal version 2026-09-13 says both (§7.1).
- Google, through Firebase Cloud Messaging, receiving the registration token and each
  notification's title and body, and the ten Android permissions the app declares. Also in legal
  version 2026-09-13.
- Retention periods (retention doc §5.2), including the 90-day nulling of IP and user agent, and
  **the payment record kept as long as the fee ledger, which is indefinitely** (§2.10).
- How to request access, correction and erasure, and that the request goes to the hostel operator.
- That erased data disappears from backups when those backups age out rather than immediately
  (retention doc §6.5) — an honest limitation most policies quietly omit — and **NEW:** that
  Razorpay's own transaction record is outside NIVORA's reach for the same kind of reason.
- Contact details for a real, monitored address.

The account-deletion page must **load without error, name the app, and give a working way to ask** —
a form or a monitored email address. It already explains what is deleted and what is retained
(financial records survive for the statutory accounting period; the audit trail is held on a
separate legal basis), which is exactly right, and it names Razorpay's own record among what
deletion cannot reach ([`data-safety.md`](./data-safety.md) §8 row 3). In legal version 2026-09-13,
live since 2026-09-13 (§7.1), it also describes the in-app route. A page that
promises total erasure and then does not deliver is worse than one that is honest about the
boundary.

---

## 8. The closed testing requirement

### Does it apply?

**Yes, if the Play developer account is a personal account created on or after 13 November 2023** —
which any account registered for this app now will be.

**It runs on the new app.** Since 2026-09-14 the app is `com.nivorasr.app` (§9 step 11). The closed
test, its opted-in testers and its 14 days all belong to that app's closed testing track, on the
operator's personal account.

Requirement, in summary: run a **closed test with at least 12 testers, opted in continuously for at
least 14 days**, before you may apply for production access
([Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465)).

**It does not apply to organisation accounts.** Registering as an organisation requires a D-U-N-S
number and its own verification, which takes its own time — so this is a choice between two delays,
not a way to avoid one. If a registered business entity already has a D-U-N-S number, the
organisation route is usually faster overall and skips the 12-tester exercise entirely.

### What it means for the calendar

The 14 days is a floor, not the schedule. A realistic timeline:

| Stage | Realistic duration |
|---|---|
| Account registration + identity verification | 2–7 days (can be longer; start it first). Once per account, so none if the account is already verified |
| Console setup, listing, all declarations | 1–2 days |
| Recruit 12 testers and get all 12 opted in | 1–7 days — this is the step that actually slips |
| **Closed test running, all 12 continuously opted in** | **14 days minimum** |
| Apply for production; Google reviews the application | up to 7 days |
| First production release review | 1–7 days |

**Roughly four to six weeks from paying the $25 to a live listing**, assuming nothing is rejected.

Two traps specific to the 14 days:

- **The clock is continuous.** If a tester opts out, or you drop below 12 at any point, the count
  resets. Recruit 15 to hold 12.
- **Testers must be opted in via the closed-track opt-in link**, not merely told about the app.
  Installing is not the same as opting in.

### The trap specific to NIVORA

**Twelve testers need twelve working accounts, and this app has no sign-up.** A tester who installs
it sees a login screen and nothing else. Before the test starts:

1. Provision demo accounts across roles — a handful of residents, a warden, a manager, an owner — in
   a fabricated hostel, so testers see a real product rather than an empty one. **Demo PG (Play
   review)** (§6.1) is seeded for this, but it holds one resident and, until
   `demo.manager@nivora.app` is created, no manager, so twelve testers need more accounts than it
   has today.
2. Give every tester their sign-in details along with the opt-in link, and tell residents explicitly
   that they log in with a **phone number**.
3. Set `must_change_password = false` on the demo accounts. **Owners always need two-step
   verification on Android, and `MFA_REQUIRED_ROLES` cannot change that** (§6 item 3). A tester who
   is given the demo owner gets its setup key, exactly as in Set 4; no real owner's key is ever
   handed out. A tester who cannot get past a forced password change or a code prompt is a tester
   who stops using the app, and the production-access application asks about tester engagement.
4. The application form asks how you recruited testers and what feedback you got. Keep notes as the
   test runs; reconstructing them 14 days later produces the vague answer that gets the application
   sent back.

---

## 9. Release checklist

In order. Each step assumes the previous one is done, with one exception: the upload (step 13) and
the store listing, app content and testers (steps 15–23) can be done in either order —
[play-console-submission.md](play-console-submission.md) does the app content first. Console will not
roll the closed test out until all of them are complete.

**Before Play Console**

1. **Confirm legal version 2026-09-13 is live (§7.1), and that the deletion page names the new
   package.** Done on the web: `main` reached `origin/main` at 20:44 IST on 2026-09-13, and at
   20:53 IST both URLs returned HTTP 200 signed out and carried version 2026-09-13. The privacy page
   had the in-app Razorpay checkout and UPI-app detection, the ten Android permissions and Google's
   part in push. The deletion page had the in-app deletion route. The in-app copy arrives with
   versionCode 5 (step 13). **Not done yet: the package.** `/legal/account-deletion` prints
   `ANDROID_PACKAGE` (`app/legal/account-deletion/page.tsx:142`), which the code now sets to
   `com.nivorasr.app` (`lib/legal-config.ts:96`). A signed-out GET on 2026-09-14 still found
   `com.srnivora.app` on the live page. Push that change, then confirm the page names
   `com.nivorasr.app`. The legal version stays 2026-09-13, because neither the privacy policy nor the
   terms names the package. Re-check the live pages on the day you submit. The Data safety answers in
   step 18 declare what that text describes, and a privacy policy that contradicts the form is a
   violation on its own. Owner: whoever owns `app/legal/`.
2. **Back up the upload keystore.** Copy `C:\Users\shahu\.hostelpro-keys\` — the `.p12` *and*
   `keystore.properties`, which `nivora_app/android/app/build.gradle.kts:45` reads for local release
   builds — somewhere durable and private. It is outside the repository, so nothing else is backing
   it up.
3. ~~**Decide the `applicationId` permanently.**~~ Decided: `com.nivorasr.app`, the `namespace` and
   `applicationId` at `nivora_app/android/app/build.gradle.kts:60` and `:109`. The same string is the
   email-link scheme (`nivora_app/android/app/src/main/AndroidManifest.xml:142`,
   `nivora_app/lib/core/config/env.dart:40`) and the iOS bundle id
   (`nivora_app/ios/Runner.xcodeproj/project.pbxproj:386`). It becomes permanent for the new app the
   moment its first bundle is uploaded (step 13). Until 2026-09-13 this step said `com.srnivora.app`,
   the package of a Console app that is now abandoned. Nothing was released from that app, and
   nothing more goes to it. Before that, this step was about `app.nivora.twa`, the retired web-app
   (TWA) wrapper.
4. **Add the new email-link redirect in Supabase.** Under Supabase → Authentication → URL
   Configuration → Redirect URLs, add exactly `com.nivorasr.app://verify-email` and save. GoTrue does
   not refuse a redirect missing from that list. It silently sends the link to the Site URL instead
   (`nivora_app/lib/core/config/env.dart:73-84`), so without this entry a confirmation link never
   returns to the app. The old `com.srnivora.app://verify-email` entry can be removed.
5. **Check Firebase, and delete nothing of the new app's.** Firebase project `nivorapg` holds two
   Android apps. `com.nivorasr.app` is the app. `com.srnivora.app` is left over from the abandoned
   listing and may be deleted later. `nivora_app/android/app/google-services.json` (gitignored,
   `nivora_app/.gitignore:53`) has a client for each (`com.nivorasr.app` at line 12,
   `com.srnivora.app` at line 31), and the Google Services plugin uses the one matching the
   `applicationId`. `FCM_SERVICE_ACCOUNT` is project-level and needs no change.
6. **Install the versionCode 5 release build on a real phone and launch it.** `release.sh` stages
   `dist/NIVORA-1.0.0.apk` (arm64, 25,306,793 bytes) and `dist/NIVORA-1.0.0-universal.apk`
   (68,586,719 bytes) next to the AAB (`nivora_app/scripts/release.sh:420-422`). A
   different package installs as a separate app. On a phone that still has a `com.srnivora.app`
   build, uninstall that build first so you know which app you are testing. Confirm the splash
   screen and launcher icon look right, that sign-in works, and whether a push notification actually
   arrives. Delivery to a real phone is still unproven. Until a notification arrives, the listing
   uses `full-description-without-push.txt` (§1.1). The "no address bar" check that used to be part
   of this step applied only to the retired TWA.
7. **Finish the demo tenant (§6.1).** Demo PG exists and is seeded. Signed in as the demo owner,
   create `demo.manager@nivora.app` from the staff screen, then sign in to it once and set its
   password. A new staff account starts with `must_change_password = true`
   (`nivora_app/lib/features/auth/change_password_screen.dart:23`). After the change, an account
   without a proved email address is sent to a verify-email screen that cannot be dismissed
   (`:190-191`). The temporary trigger in §6.1 is what spares this one. Any other tester staff
   account escapes that screen only if it, too, is a `demo.<name>@nivora.app` address in Demo PG.
   Enrol the demo owner's authenticator and keep its setup key for Set 4 (§6 item 3). Then sign in
   to all four accounts on a phone with the passwords you will type into Console. Provision extra
   tester accounts for §8.
8. **Confirm the listing assets exist** — `public/store/icon-512.png`,
   `dist/NIVORA-feature-graphic.png`, and in `dist/store-listing/` four phone screenshots, four
   10-inch tablet screenshots and the description text (§1.1).
   `node scripts/store-assets.mjs --check` covers only the icon and the retired `public/store/` set.

**Play Console — account**

Both steps belong to the developer account, not to an app. If the new app is created in the account
that held the abandoned listing, the fee is already paid. Confirm that identity verification is
complete, then move on.

9. **Pay the US$25 registration fee.** One time, non-refundable, per Google account.
10. **Complete identity verification** immediately. Government ID, and a D-U-N-S number if registering
    as an organisation. This can take days and everything else waits on it. Decide personal vs
    organisation here, knowing what §8 says about the trade-off.

**Play Console — create the new app**

11. **Create a new app.** Do not use the abandoned one: it is locked to `com.srnivora.app` and cannot
    take a `com.nivorasr.app` bundle. Enter the name `Nivora`, a default language, app-or-game (app)
    and free-or-paid (free — and note that free→paid cannot be reversed later). Every step from here
    on is done on this new app. Nothing entered on the abandoned app carries over: store listing, App
    content, Data safety, App access, content rating and testers are all entered again, with the same
    answers.
12. **Accept Play App Signing.** Mandatory for new apps; do not opt for uploading your own app signing
    key. Play creates a new app signing key for this app, shown under Protected with Play → Play Store
    distribution → Go to Play app signing → App signing key section
    ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/9842756)).
    The abandoned app's signing key plays no part. The upload key is a different key, and it has not
    changed: its SHA-256 starts `24:23:97` and ends `FB:64:65`
    ([`play-technical-compliance.md`](./play-technical-compliance.md) §4; read from the versionCode 4
    AAB with `keytool -printcert -jarfile` on 2026-09-13). Read it again from the versionCode 5 AAB
    before uploading.
13. **Upload the versionCode 5 AAB** (`dist/NIVORA-1.0.0.aab`, which `nivora_app/scripts/release.sh`
    writes at line 422) to a **closed testing** track, release name "1.0.0 (5)". Not production:
    production access is exactly what the closed test earns. The file built at 15:47 IST on 2026-09-14 is
    66,228,186 bytes, with SHA-256 `ec552f06eb45d1f52daeeffdb2f69cfaa087bfab70c34a4f3acee90d491f186f`. **This upload fixes the new app's
    package for good.** So first run every artifact check in
    [`play-technical-compliance.md`](./play-technical-compliance.md) on these files: badging (which
    must show `com.nivorasr.app` and versionCode 5), permissions, AD_ID, 16 KB alignment, sizes and
    signing. The versionCode 4 files passed those checks on 2026-09-13 (AAB SHA-256
    `a85e26c1469c09f5d41a1913343ef9834afe3f44f1776439c379e67507a975ba`). They were built for the
    abandoned listing, and they are not uploaded. **If `dist/` has been rebuilt since, these numbers
    no longer apply: run the checks on the new files first.**
14. ~~**Add the app signing key fingerprint to `assetlinks.json`.**~~ **Retired with the TWA.** This
    step let the TWA prove it owned `hostelpro-three.vercel.app`, so it would open without an address
    bar. `com.nivorasr.app` is a native build and its manifest declares no `autoVerify` link, so it
    has nothing to prove there. `public/.well-known/assetlinks.json` still names `app.nivora.twa`.

**Play Console — store listing and content**

15. **Store listing:** on the new app, paste the text from `dist/store-listing/` (also tracked in
    `docs/store-listing/`), using `full-description-without-push.txt` until push is confirmed on a
    phone (step 6); upload `public/store/icon-512.png`, `dist/NIVORA-feature-graphic.png`, the four
    phone screenshots and the four 10-inch tablet screenshots (§1.1); and set the category (Business)
    and a monitored support email.
16. **Privacy policy URL:** paste `https://hostelpro-three.vercel.app/legal/privacy` after the step 1
    check confirms the deployed page still carries legal version 2026-09-13 and says that Razorpay's
    checkout runs inside the Android app, takes the card or UPI details typed and checks which UPI
    apps are installed. A 200 is necessary and not sufficient.
17. **App access (§6):** add the four per-account instruction sets from
    [App access — what to enter in Console](./play-console-submission.md#app-access--what-to-enter-in-console):
    Set 1 Warden, Set 2 Resident, Set 3 Manager (only once that account exists) and Set 4 Owner, with
    the demo owner's setup key in place of `SETUP KEY`. Type each username and password into
    Console's own fields. This step used to suggest giving a test card; the demo PG has no Razorpay
    settlement on purpose, and Set 2 explains the refusal a reviewer sees on tapping Pay. Never give
    a Super Admin account, and leave the pre-launch report's test credentials empty.
18. **Data safety (§2):** work from [`data-safety.md`](./data-safety.md), row by row, and submit it
    in the same release as versionCode 5, after the step 1 check. Take the extra minute on
    "shared" (§2.1 and §2.9), **Financial info** (§2.4 — Purchase history yes, **User payment info
    yes**, changed on 2026-09-13 from no), **Installed apps** (yes, for the same reason), **Device or
    other IDs** (the FCM registration token, App functionality) and the government-ID rows (§2.3).
    Where `data-safety.md` and §2 disagree, `data-safety.md` is the newer. Paste the deletion URL
    once step 1 has confirmed that the live page names `com.nivorasr.app`.
19. **Content rating (§3):** complete the IARC questionnaire. Answer **yes** to users interacting,
    and **no** to purchasing digital goods — rent is a real-world service (§5).
20. **Target audience and content (§4):** 18 and over; not appealing to children.
21. **All remaining declarations (§5):** ads no, IAP no, government app no, **financial features
    none**, health none, news no. Read the Payments section of §5 first so the reasoning behind
    "financial features: none" is in your head if Console or a reviewer asks.
22. **Clear every warning on the Dashboard.** Console will not let you apply for production while any
    required item is incomplete.

**The closed test — on the new app**

23. **Recruit 15 testers to hold 12.** Email list or Google Group. Send each the opt-in link *and*
    their sign-in details.
24. **Confirm all 12+ are opted in** to the new app's closed testing track, then start the 14-day clock. Check the count every few days —
    if it drops below 12, the clock restarts.
25. **Keep notes as it runs:** how testers were recruited, what they reported, what changed. The
    production-access application asks.

**Production**

26. **Apply for production access** on day 15 or later. Answer the three sections from the notes in
    step 25. Review takes up to seven days.
27. **Create the production release by promoting the tested one.** In the closed-testing track, open
    the versionCode 5 release ("1.0.0 (5)") and use **Promote release → Production**; nothing is
    uploaded again. Upload a new bundle only if the code changed during the test, and raise the number
    after `+` in `nivora_app/pubspec.yaml` first (6 or higher) — Play rejects a re-upload of the same
    `versionCode`, and a number that has already been uploaded is burned even if that submission was
    rejected. This step
    used to point at `android/app/build.gradle.kts`, which is the retired TWA's build. Until
    2026-09-14 it named versionCode 4, "1.0.0 (4)", which was built for the abandoned listing.
28. **Roll out at a staged percentage** — 20% is a sensible first step — and watch Android Vitals and
    crash reports before going to 100%.
29. **After rollout, install the Play-delivered build on a real device** and sign in with each role.
    If push notifications arrive, switch the listing to `full-description.txt`. This step used to
    point at a §10 verification block in
    [`play-technical-compliance.md`](./play-technical-compliance.md), which has no §10, and ended
    with a "no address bar" check that was retired with the TWA.
30. **After review, remove the temporary demo-account trigger (§6.1) and tidy the abandoned
    listing's leftovers.** Run
    `drop trigger if exists users_zz_demo_review_email_verified on public.users;` and
    `drop function if exists app.demo_review_email_verified();`
    (`db/migrations/2026-09-13-demo-review-skip-email-verification.sql:35-36`). Accounts it has
    already stamped stay verified. Rotate the demo credentials (§6.2). In Supabase, remove the old
    `com.srnivora.app://verify-email` redirect if step 4 left it. In Firebase project `nivorapg`, the
    `com.srnivora.app` Android app may be deleted. **Never delete `com.nivorasr.app` there: it is the
    app.**

**Standing**

31. **Every August, Play raises the target API floor.** Raise `targetSdk`, rebuild, re-upload — or
    the listing stops accepting updates. In `nivora_app/android/app/build.gradle.kts`, `targetSdk`
    follows `flutter.targetSdkVersion` (line 113) and `compileSdk` is pinned to 37 (line 75). The
    current floor is API 36 from 31 August 2026; assume API 37 from around August 2027.

---

## 10. Corrections to `docs/play-store.md`

> **Historical: TWA era.** `play-store.md` is the build guide for the retired Trusted Web Activity,
> package `app.nivora.twa`, and the table below corrects that document. Its TWA sections do not
> describe `com.nivorasr.app` (its Console-obligations section is kept current for it); for the
> current build, see
> [`play-technical-compliance.md`](./play-technical-compliance.md) and
> [`play-console-submission.md`](./play-console-submission.md). §10.1 is not TWA-era.

That document is a good build guide, and its Data safety table has errors. Recorded here rather than
edited there, because it is another author's file.

| In `play-store.md` | Actual, from `db/schema.sql` |
|---|---|
| `students.name` | `students.full_name` |
| `students.address` | `students.permanent_address` |
| `users.name` | `users.full_name` |
| Table omits `students.email`, `students.id_proof_type`, `students.monthly_fee` | All three exist and all three are personal data |
| Table omits the `visitors` table entirely | `visitors.visitor_name` (NOT NULL) and `visitors.visitor_phone` are **third-party personal data** — a visitor has no account, no notice and no relationship with the app. Both must be declared under Name and Phone number |
| Table omits `audit_log.ip` / `user_agent` | Declared here under **Device or other IDs** (§2.5) |
| Declares only "Photos and videos › Photos" | **"Files and docs" must also be ticked** — `lib/storage.ts` accepts `application/pdf` in `student-docs` and `receipts`, so an ID proof or receipt can be a PDF (§2.3) |
| Says "no `/privacy` route at all" | **Now stale.** `app/legal/{privacy,terms,account-deletion}` exist, `PUBLIC_PATHS` includes `/legal`, and all three return HTTP 200 signed out (§7) |
| AAB "937 KB" | Correct — 959,564 bytes = 937.1 KiB |

Everything else in that document — the signing model, the keystore handling, the Digital Asset Links
mechanics, the middleware trap — was independently re-verified and holds up.

### 10.1 Documents that payments made stale

Recorded here because they are other authors' files, and because a submission answer derived from a
stale document is how a wrong declaration gets made confidently.

Re-checked 2026-09-13. Four of the five rows this table used to carry are closed and were removed:
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) now has a `payment_intents` row
in §4.1 and lists Razorpay and Google among its §7 sub-processors; the legal pages were corrected on
2026-09-02 (§7.1); and `THREAT-MODEL.md` no longer claims a single outbound call. One remains:

| Document | What is now stale | Where the right answer is |
|---|---|---|
| `.env.example` | Declares `NEXT_PUBLIC_RAZORPAY_KEY_ID` (line 30) | `lib/razorpay.ts` reads **`RAZORPAY_KEY_ID`**, and [`payments.md`](./payments.md) §1 says explicitly that it must *not* be a `NEXT_PUBLIC_` variable. Following `.env.example` produces a permanently dead Pay button. Not a submission blocker; a setup trap |
