# Play Console submission pack — NIVORA

Everything that has to be typed, pasted or ticked in Play Console, with the reasoning behind each
answer. **Every answer here was derived from the code**, not assumed: `db/schema.sql`,
`db/migrations/2026-08-24-payments.sql`, `lib/storage.ts`, `package.json`, `app/`, and the verified
artifact report in [`play-technical-compliance.md`](./play-technical-compliance.md).

Where an existing document disagrees with this one, this one was checked more recently — see §10 for
the specific corrections.

> **Revised 24 August 2026: the app now takes payments.** Student rent can be paid in-app through
> Razorpay (`db/migrations/2026-08-24-payments.sql`, [`payments.md`](./payments.md)). That changes
> the store listing (§1), four Data safety rows (§2), one content-rating answer (§3) and the
> reasoning behind the Financial features declaration (§5). It also **contradicts what the live
> legal pages currently say** — see §7.1, which is now the top blocker.

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

Character counts below were **re-measured** on 24 August 2026 by counting the actual strings with
`String.prototype.length`, not estimated. All three are pure ASCII, so nothing double-counts against
a UTF-16 limit.

> **The previous counts in this section were wrong, and it is worth knowing why.** They were
> measured when the product was called HostelPro. `HostelPro` is 9 characters and `NIVORA` is 6, so
> every count fell by 3 per occurrence at the rename and nobody re-ran them: the app name was
> recorded as 30/30 when it is 27, and the full description as 3,995 when it was 3,971. **Re-count
> after any rename.** A stale count is harmless in the direction it happened to fall this time and
> a rejected paste in the other.

### App name — limit 30

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

### Short description — limit 80

Now that residents can pay from the app, the short description should say so: it is the single
strongest differentiator against every other PG-management listing, and it is the line a store
visitor actually reads.

```
Rooms, beds, fees, complaints, leaves, visitors - and rent paid from the app.
```

**77 / 80 characters.**

Alternative, if the emphasis should be on the operator rather than the feature list:

```
Run your PG: beds, fees, complaints, leaves, visitors - and rent paid online.
```

**77 / 80 characters.**

Note the ASCII hyphen rather than an en dash. Play accepts Unicode, but the short description is
rendered in a lot of surfaces at a lot of font sizes and a plain hyphen never surprises anyone.

### Full description — limit 4000

**3,957 / 4,000 characters.** 43 characters of headroom. Re-count before pasting if anything is
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
- Residents request leave with dates and a reason
- The warden approves or rejects with a note, and the resident is notified in the app

VISITOR REGISTER
- Log a visitor's name, phone and relationship at check-in, close it at check-out
- A searchable record of who came to the building, and who they came to see

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
An internet connection, and an account created for you by your hostel. NIVORA is an installable web app, so you are always on the current version.

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

### Listing assets

| Asset | Spec | Status |
|---|---|---|
| App icon | 512×512 PNG, 32-bit | `public/store/icon-512.png` ✔ |
| Feature graphic | 1024×500 PNG, no alpha | `public/store/feature-graphic-1024x500.png` ✔ |
| Phone screenshots | min 2, 320–3840 px per side, max 2:1 | `public/store/screenshots/` — 4 at 1080×1920 ✔ |
| Tablet screenshots | Only if tablet support is listed | Not present — do not claim tablet support |

Regenerate with `node scripts/store-assets.mjs`; verify with `--check`.

Also required in the listing form: an **app category** (Business, or Productivity — Business is the
better fit for a property-management tool), a **support email address**, and optionally a website
and phone number. The support email is public once the listing is live, so use a real, monitored
address, not a personal one.

---

## 2. Data safety form

The highest-risk section in the entire submission. Everything below was read out of `db/schema.sql`,
`db/migrations/2026-08-24-payments.sql` and `lib/storage.ts`.

> **The answer sheet in Console order is [`data-safety.md`](./data-safety.md).** It is the one to
> have open while ticking. This section is the reasoning behind it, and the two must not drift —
> if you change an answer, change it in both.

### 2.1 First, the three definitions that decide every answer

Get these wrong and every row is wrong.

**"Collected"** means transmitted off the user's device. All of this app's data lives on a server, so
anything a user types or uploads is collected. There is no on-device-only data to exclude.

**"Shared" does NOT mean "leaves your building."** Play defines sharing as transferring data to a
**third party** — someone who uses it for their own purposes. It explicitly **excludes transfers to a
service provider** that processes data on your behalf, on your instructions.

> **Supabase, Vercel and Razorpay are service providers, not third parties.** Supabase and Vercel
> host the database, the auth system, the private storage buckets and the application. Razorpay
> collects a rent payment against an order NIVORA created, and reports the result back. All three
> process data solely to run NIVORA, under NIVORA's instructions. Per Play's definition this is
> **not sharing**, and the answer to "Is this data shared?" is **No** for every single row in the
> table below.

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
safe because the privacy policy names it — and **the policy does not name it yet** (§7.1).

GitHub holds source code only and never resident data, so it is not a recipient at all.

**"Processed ephemerally"** means held in memory for the request and never written down. **Nothing in
NIVORA is ephemeral** — it is a record-keeping product; persistence is the point. Answer **No**
everywhere, including for `audit_log.ip`. Nulling IP at 90 days is retention, not ephemerality.

### 2.2 The table

Purposes use Play's own vocabulary: *App functionality*, *Account management*, *Fraud prevention,
security and compliance*. **Analytics, Advertising or marketing, Personalization and Developer
communications are never selected** — verified: `package.json` has **34** production dependencies
and contains no analytics, telemetry, error-reporting, session-replay or ad SDK, and the merged
manifest requests no advertising ID (see the technical report §4).

The count moved from 31 to 34 with the payment feature. The one that matters, `razorpay`, is a
**server-side API client**: `lib/razorpay.ts` opens with `import "server-only"`, so importing it
from a client component is a build error and it can never reach the browser. Razorpay Checkout —
the part that does run in a browser — is not a dependency at all; it is fetched from
`checkout.razorpay.com` on the tap that starts a payment, and only on `/student` (§2.9).

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
| **Financial info › Purchase history** | **Yes** | No | No | **Required** | App functionality, **Fraud prevention, security and compliance** | `fee_payments` (`amount_due`, `amount_paid`, `status`, `paid_on`, `mode`, `notes`), `students.monthly_fee`, and **every column of `public.payment_intents`** (§2.4). Fraud prevention is a genuine second purpose: `razorpay_payment_id` is held under a unique index precisely so one payment can never credit twice |
| **Financial info › User payment info** | **No** | — | — | — | — | **Do not tick — and this is now a considered answer, not an obvious one.** See §2.4 |
| Financial info › Credit score | No | — | — | — | — | No such column exists |
| Financial info › Other financial info | No | — | — | — | — | Outstanding balances are disclosed under Purchase history |
| **Photos and videos › Photos** | **Yes** | No | No | Optional | App functionality | `students.photo_url`, `students.id_proof_url`, `complaints.photo_url`, `fee_payments`/`expenses` receipts. Buckets `student-docs`, `complaint-photos`, `receipts` — all **private** |
| Photos and videos › Videos | No | — | — | — | — | `lib/storage.ts` `ALLOWED` permits only `image/jpeg`, `image/png`, `image/webp`, `application/pdf`. No video type is accepted |
| **Files and docs** | **Yes** | No | No | Optional | App functionality | Same buckets: `application/pdf` is accepted for `student-docs` and `receipts`, so an ID proof or a receipt uploaded as a PDF is a document, not a photo. See §2.3 |
| **App activity › App interactions** | **Yes** | No | No | **Required** | Fraud prevention, security and compliance | `audit_log` (`action`, `target_type`, `target_id`, `actor_user_id`, `at`), `security_alerts`. Now includes six payment events — `payment.order.created`, `payment.captured`, `payment.credited`, `payment.failed`, `payment.webhook.rejected`, `payment.reconcile.required` (`lib/audit.ts`) |
| **App activity › Other user-generated content** | **Yes** | No | No | Optional | App functionality | `complaints.title`/`description`/`resolution_note`, `complaint_events.note`, `leaves.reason`, `announcements.body`, `tasks.description`, `fee_payments.notes`, `expenses.note`, `visitors.relation` |
| App activity › In-app search history | No | — | — | — | — | Not recorded |
| App activity › Installed apps | No | — | — | — | — | The manifest cannot see other packages (no `QUERY_ALL_PACKAGES`) |
| **Device or other IDs** | **Yes** | No | No | **Required** | Fraud prevention, security and compliance | `audit_log.ip`, `audit_log.user_agent`, `security_alerts.ip`, plus Vercel access logs. Razorpay Checkout also runs its own device/session telemetry inside its iframe during a payment (§2.9). See §2.5 |
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

**This section was rewritten on 24 August 2026.** It previously said there was "no payment gateway,
no PSP integration and no webhook anywhere in the codebase". **There now is all three**, and the
answer it reached is still correct — but only because of a distinction that has to be stated
precisely rather than assumed. Getting it wrong in either direction is bad: claiming you store card
data invites scrutiny you do not need, and understating collection is a violation.

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

1. **Nothing else is even parsed.** `app/api/webhooks/razorpay/route.ts` reads exactly seven fields
   off a signature-verified delivery — `event`, and from `payload.payment.entity`: `id`,
   `order_id`, `amount`, `currency`, `method`, `error_description`, `error_reason`. Everything else
   Razorpay sends is discarded with the rest of the parsed object.
2. **Nothing can write the table from outside.** RLS is on with a **SELECT policy only**, plus
   `revoke insert, update, delete on public.payment_intents from anon, authenticated`. Every write
   goes through a `security definer` function, and the three settlement ones re-check
   `app.is_service_role()` in their own bodies.

`failure_reason` is the only free-text column, and the text is Razorpay's own, capped at 200
characters — "Payment failed due to insufficient funds", not anything a user typed.

#### The two answers

**Financial info › User payment info → No. Still do not tick it.**

Play's "User payment info" means payment *instruments*. The card and UPI fields belong to
**Razorpay's document, not ours**: Checkout renders its form in an iframe on
`checkout.razorpay.com`, which is precisely why `lib/security-headers.ts` grants `frame-src` for
that origin and says so in its comment — keeping PCI scope off this application only works if the
card fields are Razorpay's. Our origin never sees a keystroke of it. **You cannot collect, and
therefore cannot declare, data your code has no access to.**

Do not tick it "to be safe" either. Ticking it states that the app stores payment instruments, which
triggers scrutiny that cannot be satisfied from the schema, because there is nothing there to show.

**Financial info › Purchase history → Yes, and it now covers more than the fee ledger.** A record of
transactions that occurred is exactly what `fee_payments` + `payment_intents` are. Add *Fraud
prevention, security and compliance* as a second purpose: `razorpay_payment_id` is stored under a
unique partial index specifically so the same payment can never credit twice.

**Other financial info stays No.** Play defines it as salary, debts and similar. An outstanding rent
balance is a transaction record, disclosed under Purchase history.

#### When "User payment info" flips to Yes

The day any card, UPI or bank field is rendered by **our** form, or a saved-card, token, mandate or
auto-debit flow is added. None exists today: there is no `customer`, `token`, `subscription` or
`mandate` call anywhere in `lib/`, and the only Razorpay API call in the entire codebase is
`razorpayClient().orders.create(...)` in `lib/actions/payments.ts`.

### 2.5 IP address and user agent

`audit_log` stores `ip` and `user_agent` on every privileged action, and `security_alerts.ip` on
every detection. Both are persisted, not ephemeral, and Vercel keeps its own access logs.

**Declare this under "Device or other IDs", purpose "Fraud prevention, security and compliance."**
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
| Is all user data encrypted in transit? | **Yes** | TLS to Vercel and to Supabase throughout; HSTS and a nonce-based CSP set in `middleware.ts`; the manifest sets no `usesCleartextTraffic`, so cleartext HTTP is blocked by the API-28+ default (technical report §4.1) |
| Do you provide a way for users to request that their data be deleted? | **Yes** | The deletion request URL in §7, backed by the erasure runbook in [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.3. Be aware of what you are claiming — see the caveat below |
| Has your app been independently reviewed against a global security standard? | **No** | `SECURITY.md` is a thorough internal review. It is not a third-party audit, and claiming otherwise in Console is a misrepresentation |
| Committed to follow the Play Families Policy? | **No** | Not a children's app — see §4 |

**The deletion caveat, stated plainly.** There is no self-service delete button in the app. Deletion
is a *request*: the resident asks the hostel operator, the operator asks NIVORA, and an
administrator runs the runbook. Play's requirement is that users can **request** deletion, and a
functional web request path satisfies it. Two things must be true before ticking Yes:

1. `/legal/account-deletion` is live, loads without error, names the app, and gives a working way to
   ask (a form or a monitored email address).
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
**privacy policy**, which does not name Razorpay yet (§7.1).

**Razorpay Checkout's own telemetry**, since a reviewer may notice it. Checkout runs device and
session telemetry to `lumberjack.razorpay.com` during a payment. Two bounds:

- **It is not granted `connect-src` in our document.** `lib/security-headers.ts` allows only
  `https://api.razorpay.com`, with the comment "lumberjack telemetry deliberately NOT granted", so
  the loader Checkout draws in *our* page cannot reach it.
- **Inside its own iframe our CSP does not apply** — a cross-origin frame carries its own policy.
  That telemetry is Razorpay's, serving the payment's own fraud and operational purposes, and
  **NIVORA receives none of it.**

Declaration consequence: **no new row, and do not add Analytics as a purpose.** It sits under the
existing *Device or other IDs / Fraud prevention, security and compliance* row.

One more bound worth knowing: the Razorpay CSP grants are **scoped to `/student`** —
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

**For how long: the same period as the rest of the fee ledger — the tenant's statutory accounting
duty, default 8 years** ([`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §5.2).
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
| **Do users interact or exchange content or information?** | **Yes** | Complaints, resolution notes, announcements, tasks and leave requests flow between residents and staff. Answer yes even though the content never leaves the tenant — the question is about capability, not reach |
| Can users share their current location with other users? | No | No location capability of any kind |
| Is unrestricted internet access provided (an open browser)? | No | The TWA is welded to `hostelpro-three.vercel.app` by the `autoVerify` intent filter; there is no address bar and no arbitrary browsing |
| **Can users purchase digital goods?** | **No** | Rent is a **real-world service** — a bed in a physical building for a calendar month — not a digital good. There is no Play Billing library and no digital product of any kind. If the questionnaire also asks about **real-world** purchases, that one is **Yes**: a resident can pay rent from the app. See §5, which explains why Play requires this to sit outside Play Billing |
| Does the app share personal information with third parties? | No | Service providers only — Supabase, Vercel and now Razorpay. See §2.1 for why a payment processor is not a third party under this question |
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
   `package.json` and in the merged manifest. The **consent duty** cannot be discharged by the
   product, because the product cannot tell who it applies to. It must be a written obligation in the
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
| **Ads** — does your app contain ads? | **No** | No ad SDK in `package.json`; no `com.google.android.gms.permission.AD_ID` in the merged manifest (technical report §4). The "Contains ads" badge will not appear on the listing |
| **In-app purchases** | **No** | The label describes **Google Play Billing** products. There is no Play Billing library in the bundle's dependency metadata and no Play product to sell. Rent is an external, real-world payment, which that badge does not describe — see below |
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

**The one thing that could change this answer**, and it is worth settling before a live key is
issued: there is a single `RAZORPAY_KEY_ID` for the whole application, so every hostel's rent is
collected into **one merchant account**. There is no Razorpay Route, no `transfers`, no split
settlement and no payout logic anywhere in the code — verified by grep across
`lib/actions/payments.ts`, `lib/razorpay.ts`, `app/api/webhooks/razorpay/route.ts` and
`components/payments/`.

If that account belongs to the **hostel operator**, NIVORA is software and nothing more, and this
declaration is correct. If it belongs to **NIVORA**, and NIVORA then pays the hostels, NIVORA is
handling other people's money — Payment Aggregator territory under the RBI's PA/PG directions,
which is a different product with a different licence, and a Financial features answer that would
have to be revisited alongside it. **Play is not the hardest part of that question; settle it
anyway.**

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

1. **A demo account for each role a reviewer needs to see.** At minimum an **Owner** and a
   **Student**, because they show two completely different apps. Adding a **Warden** is worth it —
   registration, fees, complaints, leaves and visitors all live there, and it is the most feature-rich
   view.
2. **Instructions in English**, covering the thing a reviewer will not guess: **students sign in with
   a phone number, not an email address.** Say so explicitly, with the exact phone number to type.
3. **Credentials that keep working.** Play requires them to be valid at all times and reusable, and
   specifically requires that a reviewer is not blocked by a one-time code. Two consequences for this
   app:
   - The demo accounts must have `must_change_password = false`, or the reviewer hits the forced
     password-change screen and stops.
   - The demo roles must **not** be in `MFA_REQUIRED_ROLES`, or the reviewer hits a TOTP prompt they
     cannot satisfy.
4. **A demo tenant with realistic data.** An empty hostel looks like a broken app. Seed one with
   rooms, residents, a few paid and unpaid months, an open complaint and a pending leave —
   `db/seed.ts` already builds a dataset of exactly this shape.

**Do not put these credentials in this file, in the repository, or in any screenshot.** They go into
the Play Console App access form and into whatever private ops record the team keeps. Rotate them
after the review completes.

---

## 7. Required URLs

| Where | URL | Live status, re-checked 24 Aug 2026 |
|---|---|---|
| Store listing → Privacy policy | `https://hostelpro-three.vercel.app/legal/privacy` | **HTTP 200 ✔** — reachability fixed; **content is not** (§7.1) |
| App content → Data safety → data deletion | `https://hostelpro-three.vercel.app/legal/account-deletion` | **HTTP 200 ✔** — reachability fixed; content partly stale (§7.1) |
| Digital Asset Links (not entered in Console; must simply be reachable) | `https://hostelpro-three.vercel.app/.well-known/assetlinks.json` | HTTP 200 ✔, and `"linked": true` from Google's resolver ✔ |

The 307-to-`/login` blocker recorded here on 21 August is **resolved**: `PUBLIC_PATHS` in
`lib/supabase/middleware.ts` now includes `/legal`, `app/legal/` exists with `privacy`,
`terms` and `account-deletion` routes, and all three are deployed. Re-verify any time with:

```sh
for u in /legal/privacy /legal/account-deletion /legal/terms; do
  curl -sS -o /dev/null -w "$u -> HTTP %{http_code}\n" "https://hostelpro-three.vercel.app$u"
done
```

### 7.1 The new blocker: the legal pages predate payments

**A policy that does not match the Data safety form is itself a violation**, and Google fetches the
policy URL. Three of the four live legal pages currently state the opposite of what §2 declares,
because they were written before `payment_intents` shipped:

| Page | What it says today | Why that is now false |
|---|---|---|
| `/legal/privacy` | *"there is no payment processor, no messaging provider, no analytics vendor…"*, above a three-row sub-processor table | Razorpay is a fourth sub-processor and receives the payer's name, email and phone (§2.9) |
| `/legal/privacy` | Under **"What is never collected"**: *"No card, bank account or UPI handle. Fee payments happen offline… NIVORA never takes, holds or moves money."* | Payments no longer happen only offline. The card/UPI half is still true and worth keeping — the *reason* has changed from "we don't take payments" to "Razorpay's form collects them, not ours" |
| `/legal/account-deletion` | *"There is no advertising network, no analytics service, no payment processor and no email or SMS provider in the picture."* | Same. Its fee-retention table (8 years, name removed) is **already correct** and covers `payment_intents` by extension — but Razorpay's own retained record is not mentioned (§2.10) |
| `/legal/terms` §9 | Titled *"Payments are recorded, not processed"*; *"NIVORA is not a payment service."* | Rent can now be collected in-app |

**Those four pages are outside this document's scope** — they belong to whoever owns `app/legal/`.
**Do not paste the privacy-policy URL into Console until they are fixed and deployed.** A reviewer
comparing the policy to the Data safety form finds the contradiction in under a minute, and "our
docs were stale" is not a defence that Play accepts for a legal declaration.

### 7.2 What the privacy policy has to actually say

Drawn from [`data-retention-and-privacy.md`](./data-retention-and-privacy.md), with the payment
items marked:

- The data in the §2 table, in plain words, including **identity documents** (§2.3).
- That the hostel operator is the data fiduciary and NIVORA is the processor (retention doc §2).
- **Supabase, Vercel and Razorpay named as sub-processors**, with what each does (retention doc §7 —
  **which does not list Razorpay yet either**, and still says "That is the complete list").
- **NEW:** what Razorpay receives (name, email, phone, amount, order id — §2.9) and what it does
  not send back. And the honest converse: **the card and UPI details go to Razorpay directly and
  never reach NIVORA at all**, which is a stronger privacy statement than the page makes today.
- Retention periods (retention doc §5.2), including the 90-day nulling of IP and user agent, and
  **the payment record on the same 8-year accounting clock as the fee ledger** (§2.10).
- How to request access, correction and erasure, and that the request goes to the hostel operator.
- That erased data disappears from backups when those backups age out rather than immediately
  (retention doc §6.5) — an honest limitation most policies quietly omit — and **NEW:** that
  Razorpay's own transaction record is outside NIVORA's reach for the same kind of reason.
- Contact details for a real, monitored address.

The account-deletion page must **load without error, name the app, and give a working way to ask** —
a form or a monitored email address. It already explains what is deleted and what is retained
(financial records survive for the statutory accounting period; the audit trail is held on a
separate legal basis), which is exactly right; it needs the two payment additions above. A page that
promises total erasure and then does not deliver is worse than one that is honest about the
boundary.

---

## 8. The closed testing requirement

### Does it apply?

**Yes, if the Play developer account is a personal account created on or after 13 November 2023** —
which any account registered for this app now will be.

Requirement:

> Run a **closed test with at least 12 testers, opted in continuously for at least 14 days**, before
> you may apply for production access.
> ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465))

**It does not apply to organisation accounts.** Registering as an organisation requires a D-U-N-S
number and its own verification, which takes its own time — so this is a choice between two delays,
not a way to avoid one. If a registered business entity already has a D-U-N-S number, the
organisation route is usually faster overall and skips the 12-tester exercise entirely.

### What it means for the calendar

The 14 days is a floor, not the schedule. A realistic timeline:

| Stage | Realistic duration |
|---|---|
| Account registration + identity verification | 2–7 days (can be longer; start it first) |
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

1. Create a **demo hostel** with `db/seed.ts` and provision accounts across roles — a handful of
   students, a warden, a manager, an owner — so testers see a real product rather than an empty one.
2. Give every tester their sign-in details along with the opt-in link, and tell students explicitly
   that they log in with a **phone number**.
3. Set `must_change_password = false` on the demo accounts, and keep the demo roles out of
   `MFA_REQUIRED_ROLES`. A tester who cannot get past a forced password change or a TOTP prompt is a
   tester who stops using the app, and the production-access application asks about tester
   engagement.
4. The application form asks how you recruited testers and what feedback you got. Keep notes as the
   test runs; reconstructing them 14 days later produces the vague answer that gets the application
   sent back.

---

## 9. Release checklist

In order. Each step assumes the previous one is done.

**Before Play Console**

1. **Bring the legal pages in line with the payment feature (§7.1).** ~~Fix the two failing URLs~~ —
   done: both return **HTTP 200** signed out, verified 24 Aug 2026. What remains is their
   **content**: `/legal/privacy` and `/legal/account-deletion` still say there is *"no payment
   processor"*, and `/legal/terms` §9 still says *"NIVORA is not a payment service."* **This is now
   the top blocker**, because a privacy policy that contradicts the Data safety form is a violation
   on its own. Owner: whoever owns `app/legal/`.
2. **Back up the upload keystore.** Copy `C:\Users\shahu\.hostelpro-keys\` — the `.p12` *and*
   `keystore.properties` — somewhere durable and private. It is outside the repository, so nothing
   else is backing it up.
3. **Decide the `applicationId` permanently.** `app.nivora.twa` is what the artifact carries. To
   change it to `app.hostelpro`, do it now, in `android/app/build.gradle.kts` (`namespace` *and*
   `applicationId`) and in `package_name` in `public/.well-known/assetlinks.json`, then rebuild.
   After the first upload it can never change.
4. **Install the APK on a real phone and launch it.** `adb install app-release.apk`. Confirm there is
   **no address bar**, the splash screen and launcher icon look right, and login works. The TWA has
   never been executed on a device — this is the one check no static analysis can replace.
5. **Build the demo tenant** (`db/seed.ts`) and provision the demo accounts for §6 and §8, with
   `must_change_password = false` and no MFA requirement on those roles.
6. **Confirm the listing assets exist** — `node scripts/store-assets.mjs --check`.

**Play Console — account**

7. **Pay the US$25 registration fee.** One time, non-refundable, per Google account.
8. **Complete identity verification** immediately. Government ID, and a D-U-N-S number if registering
   as an organisation. This can take days and everything else waits on it. Decide personal vs
   organisation here, knowing what §8 says about the trade-off.

**Play Console — create the app**

9. **Create the app.** Name, default language, app-or-game (app), free-or-paid (free — and note that
   free→paid cannot be reversed later).
10. **Accept Play App Signing.** Mandatory for new apps; do not opt for uploading your own app signing
    key.
11. **Upload `app-release.aab`** to a **closed testing** track. Not production — production access is
    exactly what the closed test earns.
12. **THE STEP EVERYONE FORGETS:** go to **Test and release → Setup → App integrity → App signing**,
    copy the **app signing key SHA-256 fingerprint**, add it as a **second** entry in
    `public/.well-known/assetlinks.json` alongside the existing upload-key fingerprint, and **deploy
    the site**. Then re-verify:

    ```sh
    curl -sS "https://digitalassetlinks.googleapis.com/v1/assetlinks:check?source.web.site=https://hostelpro-three.vercel.app&relation=delegate_permission/common.handle_all_urls&target.android_app.package_name=app.nivora.twa&target.android_app.certificate.sha256_fingerprint=<the-new-one>"
    ```

    Expect `"linked": true`. Skip this and every Play-installed copy of the app runs with a visible
    address bar — and a TWA that cannot prove it owns its site is the thing Play's spam policy bans.
    Full explanation in [`play-technical-compliance.md`](./play-technical-compliance.md) §8.2.

**Play Console — store listing and content**

13. **Store listing:** paste the copy from §1, upload the icon, feature graphic and screenshots, set
    the category (Business) and a monitored support email.
14. **Privacy policy URL:** paste `https://hostelpro-three.vercel.app/legal/privacy` — only after
    step 1, i.e. only once the page **names Razorpay and stops saying payments are offline-only**.
    A 200 is necessary and no longer sufficient.
15. **App access (§6):** provide demo credentials for Owner, Warden and Student, plus English
    instructions saying students sign in by **phone number**. If the demo tenant has Razorpay test
    keys configured, say so and give a test card — a reviewer who taps Pay and hits "Online payment
    isn't set up yet" has found a dead end you could have explained in one line.
16. **Data safety (§2):** work from [`data-safety.md`](./data-safety.md), row by row. Take the extra
    minute on "shared" (§2.1 and §2.9), **Financial info** (§2.4 — Purchase history yes, User
    payment info no) and the government-ID rows (§2.3). Paste the deletion URL.
17. **Content rating (§3):** complete the IARC questionnaire. Answer **yes** to users interacting,
    and **no** to purchasing digital goods — rent is a real-world service (§5).
18. **Target audience and content (§4):** 18 and over; not appealing to children.
19. **All remaining declarations (§5):** ads no, IAP no, government app no, **financial features
    none**, health none, news no. Read the Payments section of §5 first so the reasoning behind
    "financial features: none" is in your head if Console or a reviewer asks.
20. **Clear every warning on the Dashboard.** Console will not let you apply for production while any
    required item is incomplete.

**The closed test**

21. **Recruit 15 testers to hold 12.** Email list or Google Group. Send each the opt-in link *and*
    their sign-in details.
22. **Confirm all 12+ are opted in**, then start the 14-day clock. Check the count every few days —
    if it drops below 12, the clock restarts.
23. **Keep notes as it runs:** how testers were recruited, what they reported, what changed. The
    production-access application asks.

**Production**

24. **Apply for production access** on day 15 or later. Answer the three sections from the notes in
    step 23. Review takes up to seven days.
25. **Create the production release.** Bump `versionCode` in `android/app/build.gradle.kts` if the
    bundle is rebuilt for any reason — Play rejects a re-upload of the same `versionCode`, and a
    number that has already been uploaded is burned even if that submission was rejected.
26. **Roll out at a staged percentage** — 20% is a sensible first step — and watch Android Vitals and
    crash reports before going to 100%.
27. **After rollout, re-run the verification block** in
    [`play-technical-compliance.md`](./play-technical-compliance.md) §10 against a Play-installed
    build, on a real device, and confirm there is still no address bar.

**Standing**

28. **Every August, Play raises the target API floor.** Bump `compileSdk`/`targetSdk`, rebuild,
    re-upload — or the listing stops accepting updates. The current floor is API 36 from
    31 August 2026; assume API 37 from around August 2027.

---

## 10. Corrections to `docs/play-store.md`

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

| Document | What is now stale | Where the right answer is |
|---|---|---|
| [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §4.1 | The data inventory has no `payment_intents` row | §2.4 here lists every column; §2.10 gives the retention period (the fee ledger's own, default 8 years, per that document's §5.2 — so the **period** is settled, only the **inventory row** is missing) |
| [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §7 | Sub-processor table lists three, and asserts *"That is the complete list"* on the strength of "no payment provider, no webhooks" in `THREAT-MODEL.md` §1/§6D | Razorpay is a fourth. §2.9 here records exactly what it receives |
| `app/legal/privacy`, `app/legal/terms`, `app/legal/account-deletion` | Say there is no payment processor and that NIVORA never moves money | §7.1 — **blocking**, with the exact strings |
| `THREAT-MODEL.md` §1, §6D | *"Exactly one outbound HTTP call in the entire application"* | There are now three outbound destinations: the Supabase health URL, `api.razorpay.com` (order creation), and Razorpay's inbound webhook. [`payments.md`](./payments.md) §6 is the current perimeter description |
| `.env.example` | Declares `NEXT_PUBLIC_RAZORPAY_KEY_ID` | `lib/razorpay.ts` reads **`RAZORPAY_KEY_ID`**, and [`payments.md`](./payments.md) §1 says explicitly that it must *not* be a `NEXT_PUBLIC_` variable. Following `.env.example` produces a permanently dead Pay button. Not a submission blocker; a setup trap |
