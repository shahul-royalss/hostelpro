# Play Console submission pack — HostelPro

Everything that has to be typed, pasted or ticked in Play Console, with the reasoning behind each
answer. **Every answer here was derived from the code**, not assumed: `db/schema.sql`,
`lib/storage.ts`, `package.json`, `app/`, and the verified artifact report in
[`play-technical-compliance.md`](./play-technical-compliance.md).

Where an existing document disagrees with this one, this one was checked more recently — see §10 for
the specific corrections.

> **Not legal advice.** The Data safety form is a legal declaration by the developer. Read §2 before
> ticking anything; a wrong answer there is a policy violation, not a typo.

**Contents:** [Store listing](#1-store-listing-copy) · [Data safety](#2-data-safety-form) ·
[Content rating](#3-content-rating-questionnaire) · [Target audience](#4-target-audience-and-content)
· [Declarations](#5-the-declarations) · [App access](#6-app-access--the-one-that-blocks-review-for-this-app)
· [URLs](#7-required-urls) · [Closed testing](#8-the-closed-testing-requirement) ·
[Checklist](#9-release-checklist)

---

## 1. Store listing copy

Character counts below were measured by counting the actual strings, not estimated. All three are
pure ASCII, so no character counts double against a UTF-16 limit.

### App name — limit 30

```
HostelPro: PG & Hostel Manager
```

**30 / 30 characters.** Exactly at the limit, which works but leaves no room. If Console rejects it
for any reason, use the safe alternative:

```
HostelPro - PG Management
```

**25 / 30 characters.**

The bare `HostelPro` (9 characters) is also available, but it wastes the strongest ranking surface in
the whole listing — nobody searches for "HostelPro"; they search for "hostel management app" and
"PG management".

### Short description — limit 80

```
Rooms, beds, fees, complaints, leaves and visitors - one app for your PG.
```

**73 / 80 characters.**

Alternative, if the emphasis should be on the operator rather than the feature list:

```
Manage your PG or hostel: beds, fees, complaints, leaves and visitor logs.
```

**74 / 80 characters.**

Note the ASCII hyphen rather than an en dash. Play accepts Unicode, but the short description is
rendered in a lot of surfaces at a lot of font sizes and a plain hyphen never surprises anyone.

### Full description — limit 4000

**3,995 / 4,000 characters.** Five characters of headroom — if anything is edited, re-count before
pasting.

```
HostelPro is a complete management system for paying-guest accommodations and hostels. Rooms and beds, monthly fees, complaints, leave requests, the visitor register and the mess menu all live in one place, so the owner, the manager, the warden and the resident are finally looking at the same information.

Built for how a PG actually runs. The owner sees the whole property. The manager runs the money and the kitchen. The warden runs the floor. The resident sees only their own room, their own fees and their own requests. Nobody has to be handed a spreadsheet they were not meant to see.

ROOMS AND BEDS
- Lay out floors, rooms and beds once, then allocate residents to a specific bed
- Live occupancy: which beds are free, which are taken, and by whom
- Move a resident between beds; room counts follow automatically
- Vacate a resident and the bed is released the same moment

FEES AND PAYMENTS
- A monthly ledger per resident: amount due, amount paid, paid or partial or unpaid
- Record cash, UPI or bank transfers with the date and an optional note
- Attach a receipt image or PDF to any payment
- See at a glance who has not paid this month, and for how many months

COMPLAINTS
- Residents raise complaints under food, cleaning, maintenance, wi-fi, roommate or other
- Attach a photo so the warden can see the problem before walking over
- Track every complaint from open to in progress to resolved, with a resolution note

LEAVE REQUESTS
- Residents request leave with dates and a reason
- The warden approves or rejects with a note, and the resident is notified in the app

VISITOR REGISTER
- Log a visitor's name, phone and relationship at check-in, and close it at check-out
- A searchable record of who came to the building, and who they came to see

MESS MENU
- Publish a weekly menu for breakfast, lunch, snacks and dinner
- Residents see today's menu on their home screen

NOTICES AND TASKS
- Post announcements to everyone, or only to staff, or only to residents
- Assign tasks to staff and track them from pending to done

EXPENSES, REVENUE AND REPORTS
- Record groceries, staff costs, electricity, water and maintenance against the property
- Track income from fees, mess and other sources
- Charts that show where the month actually went

BUILT FOR PRIVACY
Residents' details are some of the most sensitive data a small business holds: phone numbers, guardian contacts, home addresses and identity documents. HostelPro treats them that way.
- Every property is isolated at the database level, so one hostel's staff can never read another's records
- Photographs, identity documents and receipts are kept in private storage and served through short-lived links that expire in minutes
- All traffic is encrypted in transit
- Two-factor authentication is available, and can be made mandatory for privileged roles
- Every privileged action is written to an audit trail
- No advertising, no advertising identifier, no analytics or tracking SDKs of any kind

HOW ACCOUNTS WORK - PLEASE READ BEFORE INSTALLING
HostelPro has no public sign-up, and this is deliberate. You cannot create an account by downloading the app. A hostel owner is set up by the HostelPro administrator; the owner creates the manager and warden accounts; the warden registers residents. Residents then sign in with the phone number their warden registered.

If your hostel does not use HostelPro yet, there is nothing for you to sign in to. Ask your hostel owner or warden first.

WHAT THIS APP DOES NOT DO
It does not process payments. HostelPro records that a payment happened - the amount, the date, and whether it was cash, UPI or a bank transfer - so the ledger is accurate. Money is never taken, held or moved through this app or this company.

REQUIREMENTS
An internet connection, and an account created for you by your hostel. HostelPro is delivered as an installable web app, so you are always on the current version.

Questions, or want HostelPro at your property? Get in touch through the website.
```

**Why the "HOW ACCOUNTS WORK" section is not optional.** An app that cannot be signed into is the
classic one-star review and the classic policy complaint. Saying plainly, in the listing, that there
is no public sign-up sets the expectation before the install and gives a reviewer the context for
§6. It is also the honest answer to "minimum functionality": HostelPro is a real product with a
gated audience, not a broken app.

**Why "WHAT THIS APP DOES NOT DO" is in there.** Fee tracking reads like a payments feature at a
glance. Stating in the listing that no money moves through the app matches the Financial features
declaration in §5 and pre-empts the review question.

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

The highest-risk section in the entire submission. Everything below was read out of `db/schema.sql`
and `lib/storage.ts`.

### 2.1 First, the three definitions that decide every answer

Get these wrong and every row is wrong.

**"Collected"** means transmitted off the user's device. All of this app's data lives on a server, so
anything a user types or uploads is collected. There is no on-device-only data to exclude.

**"Shared" does NOT mean "leaves your building."** Play defines sharing as transferring data to a
**third party** — someone who uses it for their own purposes. It explicitly **excludes transfers to a
service provider** that processes data on your behalf, on your instructions.

> **Supabase and Vercel are service providers, not third parties.** They host the database, the auth
> system, the private storage buckets and the application. They process resident data solely to run
> HostelPro, under HostelPro's instructions. Per Play's definition this is **not sharing**, and the
> answer to "Is this data shared?" is **No** for every single row in the table below.

This trips people up because it feels dishonest to answer "not shared" when the data plainly sits on
Supabase's servers. It is not dishonest — it is the answer the form is asking for. Ticking "shared"
would tell users that HostelPro passes their residents' phone numbers and ID scans to outside
parties for those parties' own use. That is false, it would contradict the privacy policy, and it
invites a review question that cannot be answered from the schema. The place to disclose Supabase and
Vercel is the **privacy policy**, as named sub-processors — which is exactly what
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §7 does.

GitHub holds source code only and never resident data, so it is not a recipient at all.

**"Processed ephemerally"** means held in memory for the request and never written down. **Nothing in
HostelPro is ephemeral** — it is a record-keeping product; persistence is the point. Answer **No**
everywhere, including for `audit_log.ip`. Nulling IP at 90 days is retention, not ephemerality.

### 2.2 The table

Purposes use Play's own vocabulary: *App functionality*, *Account management*, *Fraud prevention,
security and compliance*. **Analytics, Advertising or marketing, Personalization and Developer
communications are never selected** — verified: `package.json` has 31 production dependencies and
contains no analytics, telemetry, error-reporting, session-replay or ad SDK, and the merged manifest
requests no advertising ID (see the technical report §4).

| Play data type | Collected | Shared | Ephemeral | Required / optional | Purpose | Where it lives in the code |
|---|---|---|---|---|---|---|
| **Personal info › Name** | **Yes** | No | No | **Required** | App functionality, Account management | `students.full_name` (NOT NULL), `users.full_name` (NOT NULL), `students.guardian_name`, `visitors.visitor_name` (NOT NULL) |
| **Personal info › Email address** | **Yes** | No | No | Optional | App functionality, Account management | `users.email`, `students.email` (both nullable). Staff sign in by email; **students sign in by phone**, mapped to a synthetic email in Supabase Auth |
| **Personal info › Phone number** | **Yes** | No | No | **Required** | App functionality, Account management | `students.phone` (NOT NULL — it is the student's login identifier), `students.guardian_phone`, `users.phone`, `visitors.visitor_phone` |
| **Personal info › Address** | **Yes** | No | No | Optional | App functionality | `students.permanent_address` (nullable), `hostels.address` |
| **Personal info › User IDs** | **Yes** | No | No | **Required** | App functionality, Account management, Fraud prevention & security | Supabase Auth `uid`, `users.id`, `students.id`, `hostel_id`, role |
| **Personal info › Other info** | **Yes** | No | No | Optional | App functionality | `students.id_proof_type` — the *kind* of government ID a resident holds. See §2.3 |
| Personal info › Race and ethnicity | No | — | — | — | — | No such column exists |
| Personal info › Political or religious beliefs | No | — | — | — | — | No such column exists |
| Personal info › Sexual orientation | No | — | — | — | — | No such column exists |
| **Financial info › Purchase history** | **Yes** | No | No | **Required** | App functionality | `fee_payments` (`amount_due`, `amount_paid`, `status`, `paid_on`, `mode`, `notes`), `students.monthly_fee` |
| **Financial info › User payment info** | **No** | — | — | — | — | **Do not tick.** See §2.4 — this is the single most consequential answer on the form |
| Financial info › Credit score | No | — | — | — | — | No such column exists |
| Financial info › Other financial info | No | — | — | — | — | Outstanding balances are disclosed under Purchase history |
| **Photos and videos › Photos** | **Yes** | No | No | Optional | App functionality | `students.photo_url`, `students.id_proof_url`, `complaints.photo_url`, `fee_payments`/`expenses` receipts. Buckets `student-docs`, `complaint-photos`, `receipts` — all **private** |
| Photos and videos › Videos | No | — | — | — | — | `lib/storage.ts` `ALLOWED` permits only `image/jpeg`, `image/png`, `image/webp`, `application/pdf`. No video type is accepted |
| **Files and docs** | **Yes** | No | No | Optional | App functionality | Same buckets: `application/pdf` is accepted for `student-docs` and `receipts`, so an ID proof or a receipt uploaded as a PDF is a document, not a photo. See §2.3 |
| **App activity › App interactions** | **Yes** | No | No | **Required** | Fraud prevention, security and compliance | `audit_log` (`action`, `target_type`, `target_id`, `actor_user_id`, `at`), `security_alerts` |
| **App activity › Other user-generated content** | **Yes** | No | No | Optional | App functionality | `complaints.title`/`description`/`resolution_note`, `complaint_events.note`, `leaves.reason`, `announcements.body`, `tasks.description`, `fee_payments.notes`, `expenses.note`, `visitors.relation` |
| App activity › In-app search history | No | — | — | — | — | Not recorded |
| App activity › Installed apps | No | — | — | — | — | The manifest cannot see other packages (no `QUERY_ALL_PACKAGES`) |
| **Device or other IDs** | **Yes** | No | No | **Required** | Fraud prevention, security and compliance | `audit_log.ip`, `audit_log.user_agent`, `security_alerts.ip`, plus Vercel access logs. See §2.5 |
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
in the form, not permission to stay quiet, and HostelPro holds exactly this kind of document:
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

### 2.4 "User payment info" — the answer that matters most

**Do not tick it.**

Play's "User payment info" means payment instruments: card numbers, bank account numbers, payment
credentials. HostelPro stores **none of these**. Checked column by column: `fee_payments` holds
`amount_due`, `amount_paid`, `status`, `paid_on`, a free-text `notes`, and `mode` — and `mode` is a
Postgres enum with exactly three values:

```sql
create type public.payment_mode as enum ('cash','upi','bank');
```

A three-value label recording how an offline payment was made. No UPI VPA, no account number, no
card, no token. There is no payment gateway, no PSP integration and no webhook anywhere in the
codebase — `THREAT-MODEL.md` §1 and §6D record exactly one outbound HTTP call in the whole
application, to the Supabase health URL.

Ticking "User payment info" would state that the app stores payment instruments. That triggers
scrutiny that cannot be satisfied from the schema, because there is nothing there to show. **Tick
"Purchase history" instead** — a record of transactions that occurred — which is what a rent ledger
actually is.

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
is a *request*: the resident asks the hostel operator, the operator asks HostelPro, and an
administrator runs the runbook. Play's requirement is that users can **request** deletion, and a
functional web request path satisfies it. Two things must be true before ticking Yes:

1. `/legal/account-deletion` is live, loads without error, names the app, and gives a working way to
   ask (a form or a monitored email address).
2. Someone actually answers. The runbook at §6.3 of the retention document is marked
   **"written, not executed"** — it has never been run against production. Dry-run it on a Supabase
   branch before the first real request arrives, not after.

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
| Can users purchase digital goods? | No | No billing library, no IAP |
| Does the app share personal information with third parties? | No | Sub-processors only — see §2.1 |
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

Consequence: HostelPro is **not** in the Designed for Families programme, is not subject to the Play
Families Policy, and the "Committed to follow Families Policy" answer in §2.8 is No.

### 4.2 The part that deserves honesty rather than a shrug

**Some residents of some hostels will be under 18.** PG and hostel residents in India routinely
include school and junior-college students.
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §3 says this outright and does not
soften it. Pretending otherwise in this document would be worse than useless.

So why is "18 and over" still the right answer? Because Play's question is about **who the app is
designed and marketed for**, not about who might conceivably end up holding a phone with it
installed. HostelPro is sold to hostel operators; its users are owners, managers, wardens and
residents of a business's premises; and a minor resident reaches it only because an adult member of
staff created an account for them. Selecting an under-18 age group would pull the app into the
Families programme and its content, ads and data requirements — a programme built for children's
media, which this is not, and which HostelPro would fail on paperwork it has no reason to produce.

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
| **In-app purchases** | **No** | No Play Billing library in the bundle's dependency metadata; no purchase flow anywhere in `app/` |
| **Government app** | **No** | A private commercial product. Not developed by or on behalf of any government |
| **Financial features** | **"My app doesn't provide any financial features."** | See below — be precise, this one matters |
| **Health** | **No health features** | No health data collection, no medical device integration, no health claims. The `leaves.reason` free-text caveat in §2.7 is a minimisation note, not a health feature |
| **News app** | **No** | — |
| **COVID-19 contact tracing / status** | **No** | — |
| **Data safety** | Completed per §2 | — |
| **Content ratings** | Completed per §3 | — |
| **Target audience and content** | Completed per §4 | — |
| **App access** | **Required — see §6** | The whole app is behind a login |
| Content guidelines + US export laws acknowledgements | Accept | Standard |

### Financial features — say it exactly right

Play's Financial features declaration lists things like lending, payments and money transfer,
digital-only banking, crypto exchange, insurance and stock trading. **None apply.** Select *"My app
doesn't provide any financial features."*

The distinction, and it is a real one rather than a technicality:

> HostelPro **records that a payment happened**. It does not **process** one.

A warden collects ₹8,000 in cash, or receives a UPI transfer to the hostel's own account, and then
opens HostelPro and types in what happened: the amount, the date, and which of the three modes it
was. The app is a ledger. It never initiates a transaction, never holds a balance, never touches a
payment instrument and never moves money — not for the hostel, not for HostelPro. There is no
gateway, no PSP, no webhook, no card vault, and exactly one outbound HTTP call in the entire codebase
(a Supabase health check).

Declaring a financial feature here would drag in India-specific financial-services verification that
HostelPro cannot satisfy and does not need. Declaring none is accurate today.

**This changes the day UPI collection is added.** If HostelPro ever takes payment in-app, this
declaration, the Data safety answer in §2.4, and the "WHAT THIS APP DOES NOT DO" paragraph in the
store listing all have to be revised together. Note it now so the future change is not made
piecemeal.

---

## 6. App access — the one that blocks review for this app

**Play Console → App content → App access → "All or some functionality is restricted."**

This is not optional and it is not a formality. HostelPro has **no public sign-up by design**: the
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

| Where | URL | Live status, checked 21 Aug 2026 |
|---|---|---|
| Store listing → Privacy policy | `https://hostelpro-three.vercel.app/legal/privacy` | **HTTP 307 → /login — FAILING** |
| App content → Data safety → data deletion | `https://hostelpro-three.vercel.app/legal/account-deletion` | **HTTP 307 → /login — FAILING** |
| Digital Asset Links (not entered in Console; must simply be reachable) | `https://hostelpro-three.vercel.app/.well-known/assetlinks.json` | HTTP 200 ✔, and `"linked": true` from Google's resolver ✔ |

> ### Blocker
>
> Both required URLs currently answer an anonymous request with `307 → /login`. Google fetches them
> signed-out; a login redirect is not a privacy policy, and it is a rejection.
>
> The middleware source is already correct — `PUBLIC_PATHS` in `lib/supabase/middleware.ts` includes
> `/legal` — but **the change is uncommitted and therefore not deployed**
> (`git diff HEAD --stat` shows 11 uncommitted lines in that file), and `app/legal/` does not exist in
> the tree yet. Full diagnosis in [`play-technical-compliance.md`](./play-technical-compliance.md)
> §8.1.
>
> **Do not paste either URL into Console until this returns 200 signed out:**
>
> ```sh
> for u in /legal/privacy /legal/account-deletion; do
>   curl -sS -o /dev/null -w "$u -> HTTP %{http_code}\n" "https://hostelpro-three.vercel.app$u"
> done
> ```

What the privacy policy has to actually say, drawn from
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) — a policy that does not match the
Data safety form is itself a violation:

- The data in the §2 table, in plain words, including **identity documents** (§2.3).
- That the hostel operator is the data fiduciary and HostelPro is the processor (retention doc §2).
- **Supabase and Vercel named as sub-processors**, with what each does (retention doc §7).
- Retention periods (retention doc §5.2), including the 90-day nulling of IP and user agent.
- How to request access, correction and erasure, and that the request goes to the hostel operator.
- That erased data disappears from backups when those backups age out rather than immediately
  (retention doc §6.5) — an honest limitation most policies quietly omit.
- Contact details for a real, monitored address.

The account-deletion page must **load without error, name the app, and give a working way to ask** —
a form or a monitored email address. It also needs to explain what is deleted and what is retained
(financial records survive for the statutory accounting period; the audit trail is held on a separate
legal basis), because a page that promises total erasure and then does not deliver it is worse than
one that is honest about the boundary.

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

### The trap specific to HostelPro

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

1. **Fix the two failing URLs (§7).** Commit and deploy `lib/supabase/middleware.ts` together with
   the `/legal/privacy` and `/legal/account-deletion` pages. Verify signed out that both return
   **HTTP 200**. This is the top blocker.
2. **Back up the upload keystore.** Copy `C:\Users\shahu\.hostelpro-keys\` — the `.p12` *and*
   `keystore.properties` — somewhere durable and private. It is outside the repository, so nothing
   else is backing it up.
3. **Decide the `applicationId` permanently.** `app.hostelpro.twa` is what the artifact carries. To
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
    curl -sS "https://digitalassetlinks.googleapis.com/v1/assetlinks:check?source.web.site=https://hostelpro-three.vercel.app&relation=delegate_permission/common.handle_all_urls&target.android_app.package_name=app.hostelpro.twa&target.android_app.certificate.sha256_fingerprint=<the-new-one>"
    ```

    Expect `"linked": true`. Skip this and every Play-installed copy of the app runs with a visible
    address bar — and a TWA that cannot prove it owns its site is the thing Play's spam policy bans.
    Full explanation in [`play-technical-compliance.md`](./play-technical-compliance.md) §8.2.

**Play Console — store listing and content**

13. **Store listing:** paste the copy from §1, upload the icon, feature graphic and screenshots, set
    the category (Business) and a monitored support email.
14. **Privacy policy URL:** paste `https://hostelpro-three.vercel.app/legal/privacy` — only after
    step 1 verified 200.
15. **App access (§6):** provide demo credentials for Owner, Warden and Student, plus English
    instructions saying students sign in by **phone number**.
16. **Data safety (§2):** work through the table row by row. Take the extra minute on "shared" (§2.1),
    "User payment info" (§2.4) and the government-ID rows (§2.3). Paste the deletion URL.
17. **Content rating (§3):** complete the IARC questionnaire. Answer **yes** to users interacting.
18. **Target audience and content (§4):** 18 and over; not appealing to children.
19. **All remaining declarations (§5):** ads no, IAP no, government app no, **financial features
    none**, health none, news no.
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
| Says "no `/privacy` route at all" | Still true of `app/`, but `PUBLIC_PATHS` now includes `/legal` in the working tree — uncommitted, so production still redirects (§7) |
| AAB "937 KB" | Correct — 959,564 bytes = 937.1 KiB |

Everything else in that document — the signing model, the keystore handling, the Digital Asset Links
mechanics, the middleware trap — was independently re-verified and holds up.
