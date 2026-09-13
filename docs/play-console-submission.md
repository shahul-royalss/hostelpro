# Play Console — getting this release accepted

Everything Console is currently complaining about, in the order it will stop complaining, plus the
things it has not complained about yet but will.

**App name:** Nivora · **Package:** `com.srnivora.app` · **Upload artifact:** `dist/NIVORA-<v>.aab`

---

## The three errors are one problem

> **Error** You need to upload an APK or Android App Bundle for this app.
> **Error** You can't rollout this release because it doesn't allow any existing users to upgrade to the newly added app bundles.
> **Error** This release does not add or remove any app bundles.

All three say the same thing from three angles: **the release has no bundle in it**. The second one
reads like a version problem and is not — with no bundle there is nothing for anyone to upgrade
*to*, so Console phrases the emptiness as an upgrade failure.

The earlier upload was rejected for a different reason —

> Your APK or Android App Bundle needs to have the package name com.srnivora.app

— and that is now fixed at the source: `applicationId` and `namespace` are `com.srnivora.app`, the
Kotlin package moved with them, and the email-verification deep link uses the same string as its
custom scheme.

**Do this:**

1. Play Console → your app → **Test and release → Testing → Closed testing** → create a track, or
   open the one you have → **Create new release**. Use **closed** testing, not internal: a personal
   developer account needs 12 testers opted in for 14 continuous days **on a closed test** before it
   can apply for production, and internal testing does not count toward that (Warning 2). If you also
   want the quickest install on your own phone, create an Internal testing release afterwards and
   pick the same bundle with **Add from library**; do not upload it a second time.
2. Upload `dist/NIVORA-1.0.0.aab` — versionCode 4, SHA-256
   `a85e26c1469c09f5d41a1913343ef9834afe3f44f1776439c379e67507a975ba` (check it first; see "Verifying the artifact before you upload it" below). Wait for it to
   finish processing — the errors clear as soon as Console has parsed it, not when the upload bar
   fills.
3. Paste the release notes from [play-release-notes.md](play-release-notes.md).
4. **Save**, then **Review release**.

An `applicationId` cannot be changed after the first accepted upload. `com.srnivora.app` is what
this listing is now, permanently.

---

## Warning 1 — the advertising ID declaration

> You must complete the advertising ID declaration before you can release an app that targets
> Android 13 (API 33).

**Answer: No, this app does not use an advertising ID.**

Play Console → **Policy → App content → Advertising ID** → *No* → Save.

That answer is true and is enforced in the manifest rather than merely believed:

```xml
<uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove" />
```

It is removed **explicitly** rather than just left out, because a dependency's own manifest can
merge one in — that is exactly how apps end up with an ad id they never asked for. Firebase Cloud
Messaging does not pull in `play-services-ads-identifier`; Firebase **Analytics** does, and
Analytics is deliberately not installed.

**Verify it on the built artifact, not on the source** — that is the whole point of removing it
explicitly:

```bash
cd nivora_app && bash scripts/verify-adid.sh
```

If that ever prints a line, the declaration in Console is wrong and must change with it.

---

## Warning 2 — no testers on the track

> This release will not be available to any users because you haven't specified any testers.

This is a **warning, not an error** — the release will roll out. It will simply reach nobody, and
the track will look broken when it is actually empty.

Play Console → **Test and release → Testing → Closed testing** → your track → **Testers** tab. The
same steps work on Internal testing if you use that track as well:

1. Select the email list you already created — email lists belong to the developer account and can
   be ticked on any track — or **Create email list** → name it `Nivora testers`.
2. Add `codewithshahul@gmail.com` — the account that owns this Play Console. It is allowed to be
   its own tester, and it should be the first one. On a personal account, add at least 11 more
   Google accounts: 12 have to opt in and stay opted in for the 14 days.
3. **Tick the checkbox next to the list.** This is the step that clears the warning, and it is the
   one people miss: *creating* a list does not *assign* it to the track. An unticked list leaves
   the warning in place looking exactly as if nothing had been added.
4. **Save.**

Then **Copy link** (it goes live on this tab once the release is rolled out), open it in a browser
signed in as that account, and accept the invitation. Only after accepting does Nivora appear in
the Play Store — and the phone must be signed into the Play Store with the *same* account. Give it
a few minutes to propagate before concluding it has failed.

Every tester must be a **Google account**. A non-Google address can be added to the list and can
never join, with no error shown.

**If this developer account is a personal (individual) account**, Google additionally requires
**12 testers opted in for 14 continuous days on closed testing** before you can apply for
production. Internal testing does not count toward it. Start that clock now if production is the
goal — it is the longest pole in this whole list.

---

## App content — what Console will ask for next

These are not warnings yet because you have not reached them. Each one blocks a production rollout.

| Section | Answer | Source |
|---|---|---|
| Privacy policy | The hosted policy URL | `lib/legal-config.ts` |
| Data safety | Every question, already answered | [data-safety.md](data-safety.md) |
| App access | **Provide credentials** — every screen worth reviewing is behind a login, and a reviewer who cannot sign in fails the app | see below |
| Ads | No ads | — |
| Content rating | Fill in the questionnaire (it is free and instant) | — |
| Target audience | 18+; this is an operational tool for PG owners and residents | — |
| News app | No | — |
| Financial features | **"My app doesn't provide any financial features."** Rent for accommodation is paid to the hostel through Razorpay; Nivora offers no loans, banking, investment, crypto or money transfer, and holds no balance. Separately, because rent pays for a **physical service**, Play's billing requirement does not apply | [data-safety.md §5](data-safety.md) |
| Government apps | No | — |
| Health | No | — |
| Data deletion | The in-app route and the web route both exist | [account-deletion.md](account-deletion.md) |

### App access — what to enter in Console

Play Console → **Policy → App content → App access** → *All or some functionality is restricted*.
Add **one instruction set per account** (Google allows up to five). Put each username and password in
Console's own fields, and paste the matching block below into that set's **"Any other information"**.
One short set per account is easier for a reviewer than one long block, and safer if the field has
an unstated length limit.

**Before submitting, sign in to each account yourself** on a phone, with the exact password you will
type into Console. None of the demo accounts had signed in since 6 September at the time of writing.

What is true of the demo property, checked against the live database on 2026-09-13:

- Every account below belongs to **Demo PG (Play review)**. Everything in it is fabricated.
- It was seeded so a reviewer lands on populated screens
  (`db/migrations/2026-09-13-demo-pg-play-review-seed.sql`): four months of expenses, a week's mess
  menu, notices, a pending and an approved leave, and visitors.
- **No Razorpay account is linked to it, on purpose**, so nobody can move real money during review.
- **It has no manager account yet.** Create `demo.manager@nivora.app` in Demo PG (active, email
  confirmed, no forced password change) before submitting, then add set 3.
- The nightly retention job removes complaints and notices older than two months. Before any review
  after early November, re-seed them.

**The passwords are not in this repository.** Type them into Console yourself.

#### Set 1 — Warden

Username: `demo.warden@nivora.app`

```text
Nivora is invitation-only software for PG and hostel operators in India. Accounts are created by an
administrator, so there is no sign-up. Sign in with the email above in the single "Email or phone
number" field. On first launch, tap Skip on the intro screens. After signing in, tap "Agree and
continue" on the one-time Terms and Privacy screen. Android may ask to allow notifications; either
answer is fine.

This warden account covers: registering a resident, rooms and beds (including editing the floor
plan), recording rent paid at the desk with a receipt, complaints, leave requests, the visitor log
and notices. All data belongs to a fabricated demo hostel.

Sign-in allows 8 attempts per account per 15 minutes. After that the app asks you to wait, rather
than reporting a wrong password.
```

#### Set 2 — Resident

Username: `9000000001` (a phone number, not an email)

```text
Nivora is invitation-only software for PG and hostel operators in India. Residents are registered
by their hostel, so there is no sign-up. Type the 10-digit phone number above into the single "Email
or phone number" field; do not type an email for this account. On first launch, tap Skip on the
intro screens. After signing in, tap "Agree and continue" on the one-time Terms and Privacy screen.
Android may ask to allow notifications; either answer is fine.

This resident account covers: rent due and paid, receipts, the payment screen, raising a complaint,
notices, today's mess menu, and Profile, which includes "Delete my account and data".

Online payment is switched off for this demo hostel on purpose, so that no real money can move.
Tapping Pay shows "Online payment is not set up for this hostel yet. Please pay your warden
directly." That is the message a real resident sees in the same situation.

If "Delete my account and data" already shows "Request sent", an earlier review filed one. Requests
are de-duplicated for 30 days.
```

#### Set 3 — Manager (after you create the account)

Username: `demo.manager@nivora.app`

```text
Nivora is invitation-only software for PG and hostel operators in India. Staff accounts are created
by the hostel owner, so there is no sign-up. Sign in with the email above in the single "Email or
phone number" field. On first launch, tap Skip on the intro screens. After signing in, tap "Agree
and continue" on the one-time Terms and Privacy screen. Android may ask to allow notifications;
either answer is fine.

This manager account covers: recording monthly and day-to-day expenses, the expense charts, the
tasks the owner assigns, and editing the mess menu. All data belongs to a fabricated demo hostel.
```

#### Set 4 — Owner (two-step verification)

Username: `demo.owner@nivora.app`

**Prepare this account first.** Google requires review logins to be reusable, and the owner role
always asks for an authenticator code, so the reviewer needs a key that works every time:

1. Sign in to Nivora as `demo.owner@nivora.app`. The app opens the two-step verification setup screen.
2. It shows a QR code and, under **SETUP KEY**, the same key as text with a Copy button. Copy the
   text key.
3. Add that key to your own authenticator app and tick **"I have saved this key"**. Under
   **"2. Enter the code it shows"**, type the 6-digit code and tap **"Turn on two-factor"**.
4. Paste the text key into the block below, in place of `SETUP KEY`.

This key protects only the demo owner account, which holds fabricated data. **Never do this for a
real owner.**

```text
Nivora is invitation-only software for PG and hostel operators in India. Owner accounts are created
by the platform administrator, so there is no sign-up. Sign in with the email above in the single
"Email or phone number" field. On first launch, tap Skip on the intro screens.

This account uses two-step verification. Add this setup key to any authenticator app (Google
Authenticator, Microsoft Authenticator, Authy): SETUP KEY
After the password, enter the 6-digit code the authenticator shows. The key never changes, so it
works for every reviewer.

After signing in, tap "Agree and continue" on the one-time Terms and Privacy screen. Android may ask
to allow notifications; either answer is fine.

This owner account covers: the property dashboard (occupancy, rent collected, pending fees,
complaints), staff accounts, expense charts month by month, tasks for managers, and notices. All
data belongs to a fabricated demo hostel.
```

**Do not hand Play a Super Admin account.** It reaches every hostel on the platform, including real
residents. Nothing in the review needs it.

**Pre-launch report:** leave its test-account credentials empty (Test and release → Testing →
Pre-launch report → Settings). The robot shares the sign-in rate limit with human reviewers, and
must never be given the owner account.

---

## Two things outside Play that this release depends on

### 1. The Supabase redirect URL (do this before anyone verifies an email)

The confirmation link's custom scheme is the applicationId, so it changed with the package:

```
com.srnivora.app://verify-email
```

Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs** → add exactly that.

**GoTrue does not refuse an unlisted redirect — it silently substitutes the Site URL.** So a
missing entry does not look broken: the email arrives, the link works, and it opens a web page
instead of the app. Measured on this project on 2026-09-01; see
[email-verification.md](email-verification.md).

### 2. Push notifications: set up, not yet seen on a phone

Firebase is set up for push only; the backend stays Supabase. Project `nivorapg` holds the Android
app `com.srnivora.app`. Its `google-services.json` sits in `nivora_app/android/app/` on the build
machine and is gitignored. The `FCM_SERVICE_ACCOUNT` secret is set in Supabase: a `push-send` probe on
2026-09-13 answered `claimed: 0`, not `not_configured`. versionCode 4 carries the matching
`google_app_id`. Details are in [edge-functions.md → push-send](edge-functions.md). **Do not create
another Firebase project**, and never use the `com.nivorasr.app` registration in the same project;
it was a typo.

What is not proven is delivery: nobody has yet seen a notification arrive on a real phone. Install
the build from the testing track, tap **Agree and continue**, allow notifications, then trigger one
(a notice to residents is the quickest). Until that works, keep the store listing on
`full-description-without-push.txt`.

---

## Verifying the artifact before you upload it

**Do not run `scripts/release.sh` for this.** It rebuilds, and it overwrites
`dist/NIVORA-1.0.0.aab` with a new, unmeasured file that still says versionCode 4. Check the file
that is already there:

```bash
sha256sum dist/NIVORA-1.0.0.aab
# must print a85e26c1469c09f5d41a1913343ef9834afe3f44f1776439c379e67507a975ba
cd nivora_app && bash scripts/verify-adid.sh
```

A matching hash means this is the exact bundle measured in
[play-technical-compliance.md](play-technical-compliance.md) on 2026-09-13: versionCode 4, ten
permissions, no AD_ID, 16 KB alignment, signed with the upload key. A different hash means `dist/`
was rebuilt, and every one of those checks has to be run again before upload.

When a rebuild *is* wanted — any code change, which also means raising the `+N` in
`nivora_app/pubspec.yaml` — `scripts/release.sh` refuses to stage anything that fails its own gates:
the upload key (`CN=HostelPro`, not a debug fallback), the launcher label (`Nivora` — it once
shipped as "mobile", the Flutter project name), `libflutter.so` in every ABI directory, a versionCode
matching `pubspec.yaml`, and no service-role key or Razorpay secret anywhere in the bundle, in
either of the two encodings a Dart snapshot uses.
