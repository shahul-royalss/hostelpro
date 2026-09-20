# Play Console — releasing Nivora as a new app

Everything Console will ask for on the new app, in the order to do it, plus the two things outside
Play that this release depends on.

**App name:** Nivora · **Package:** `com.nivorasr.app` · **Upload artifact:** `dist/NIVORA-1.0.0.aab`,
versionCode 6, release name `1.0.0 (6)`

> **This is a new Play Console app (2026-09-19).** Until 2026-09-13 this page drove a listing locked
> to `com.srnivora.app`. That listing is abandoned: nothing was ever released from it, and nothing
> entered there carries over. Every step below was done again on the new app, with the same answers,
> except the last one: applying for production, which waits on the closed test.
> What happened on the old listing is under [History](#history-the-abandoned-comsrnivoraapp-listing)
> at the end.

> **Where this has got to, 2026-09-20.** The app was created on 2026-09-19. Store listing, app
> category, every App content declaration and the Data safety form went in together as one batch of
> 13 changes, with **Countries and regions: India only**. The closed testing release `1.0.0 (6)`
> passed review and is published on the closed track, and 12 testers opted in on 2026-09-20, so the
> 14 continuous days end around 2026-10-04. Production is Inactive; nothing has been released to it.
> So Steps 1 to 3 below have all been carried out for this release, except the last part of Step 3,
> applying for production, which only unlocks when those 14 days are up. The steps stay written as
> instructions because the next release repeats them, and each one says whether it is finished.

The package is set in code: `namespace` and `applicationId` are `com.nivorasr.app`
(`nivora_app/android/app/build.gradle.kts:60` and `:109`), `MainActivity` lives in
`nivora_app/android/app/src/main/kotlin/com/nivorasr/app/`, and the upload is `version: 1.0.0+6`
(`nivora_app/pubspec.yaml:19`).

---

## Step 1 — create the app

**Done on 2026-09-19.** The steps stay here as the procedure, for whenever an app has to be created
again.

Play Console → **Home → Create app**.

- **App name:** `Nivora`. **Default language:** English (United States), the one language the
  release notes declare ([play-release-notes.md](play-release-notes.md)).
- Answer the remaining questions and accept the declarations yourself.

There is no package field on that form. A new app takes its package from the first bundle uploaded
to it, and from then on that package is the app's identity **permanently**. The versionCode 6 bundle
was that first upload, so this app is `com.nivorasr.app` for good. Checking the package before an
upload stays worth doing every time (see
[Verifying the artifact](#verifying-the-artifact-before-you-upload-it)).

## Step 2 — fill in what Console asks for

**Done on 2026-09-19.** All five went in together as one batch of 13 changes, along with
**Countries and regions: India only**. The list stays as the set of answers to give again, on the
next app or on any declaration Console reopens.

None of this carried over from the old listing. It can come before or after the upload in Step 3;
Console will not roll the closed test out until all of it is done:

1. **Store listing:** graphics and text from [store-assets.md §2](store-assets.md); app category
   **Business**.
2. **App content:** every row of [the table below](#app-content--every-row-and-the-answer-that-went-in),
   including Data safety from [data-safety.md](data-safety.md), Financial features *none*, and
   **App access** with its four instruction sets.
3. **Advertising ID:** No ([Warning 1](#warning-1--the-advertising-id-declaration)).
4. **Content rating:** the questionnaire again.
5. **Testers:** the email list ([Warning 2](#warning-2--no-testers-on-the-track)).

## Step 3 — the closed test, with versionCode 6

**Steps 1 to 5 are done**, and `1.0.0 (6)` is published on the closed track. Step 6, applying for
production, is the one that is left.

1. Play Console → the new app → **Test and release → Testing → Closed testing** → create a track →
   **Create new release**. Use **closed** testing, not internal. This is a personal developer
   account, so it needs 12 testers opted in for 14 continuous days **on a closed test of this app**
   before it can apply for production, and internal testing does not count toward that
   ([Warning 2](#warning-2--no-testers-on-the-track)). If you also want the quickest install on
   your own phone, create an Internal testing release afterwards and pick the same bundle with
   **Add from library**; do not upload it a second time.
2. Keep **Play App Signing** with a key Google generates. It creates a new app signing key for this
   app. The upload key is the same one as before: the certificate SHA-256 that starts `24:23:97` and
   ends `FB:64:65`, recorded in [play-technical-compliance.md](play-technical-compliance.md) §4.
3. Upload `dist/NIVORA-1.0.0.aab`: versionCode 6, 66,433,003 bytes, SHA-256
   `d1283f6b173eecf37d6ebbbb2d026e414d8e60b0dc7480a5505583075a888541`, built on 2026-09-16. Check it first (see
   [Verifying the artifact](#verifying-the-artifact-before-you-upload-it)). Wait for it to finish
   processing.
4. Release name `1.0.0 (6)`. Paste the release notes from [play-release-notes.md](play-release-notes.md).
5. **Save**, then **Review release**.
6. Once 12 testers have stayed opted in for 14 days, apply for production. `1.0.0 (6)` passed
   review and is published on the closed track, and the twelfth tester opted in on 2026-09-20, so
   the 14 days run out around 2026-10-04.

If Console reports that the release needs a bundle, that no existing users can upgrade, and that it
adds no bundles, those are one problem: the release has no processed bundle in it yet. They clear
once Console has parsed the upload, not when the upload bar fills.

---

## Warning 1 — the advertising ID declaration

> You must complete the advertising ID declaration before you can release an app that targets
> Android 13 (API 33).

**Answer: No, this app does not use an advertising ID.** It was answered that way on 2026-09-19, in
the App content batch. The answer has to be given again on any future app, and re-checked whenever
a dependency is added.

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

**It is cleared on this app's closed track:** the email list is ticked and the release is out to it.
The steps stay as the procedure for the next track and the next release.

Play Console → the new app → **Test and release → Testing → Closed testing** → your track →
**Testers** tab. The same steps work on Internal testing if you use that track as well:

1. Select the email list you already created — email lists belong to the developer account and can
   be ticked on any track — or **Create email list** → name it `Nivora testers`.
2. Add `codewithshahul@gmail.com` — the account that owns this Play Console. It is allowed to be
   its own tester, and it should be the first one. This is a personal account, so add at least 11
   more Google accounts: 12 have to opt in and stay opted in for the 14 days.
3. **Tick the checkbox next to the list.** This is the step that clears the warning, and it is the
   one people miss: *creating* a list does not *assign* it to the track. An unticked list leaves
   the warning in place looking exactly as if nothing had been added.
4. **Save.**

Then **Copy link** (it goes live on this tab once the release is rolled out), open it in a browser
signed in as that account, and accept the invitation. Only after accepting does Nivora appear in
the Play Store — and the phone must be signed into the Play Store with the *same* account. Give it
a few minutes to propagate before concluding it has failed. The link belongs to the new app, so
anyone who accepted an invitation to the old listing has to accept this one too.

Every tester must be a **Google account**. A non-Google address can be added to the list and can
never join, with no error shown.

**This developer account is a personal (individual) account**, so Google additionally requires
**12 testers opted in for 14 continuous days on closed testing** before you can apply for
production. Internal testing does not count toward it, and the new app's clock starts with its own
closed test. That clock is running: versionCode 6 is on the track and 12 testers opted in on
2026-09-20, so the 14 days end around 2026-10-04. It is the longest pole in this whole list, so on
the next release get the testers on the track the day the build lands.

---

## App content — every row, and the answer that went in

Every row here was answered on the new app on 2026-09-19, with the same answers as before, and
submitted with the rest of that batch. Each one blocks a production rollout, so the table stays as
the record of what was given and as the answer sheet for the next time Console asks.

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
| Data deletion | The in-app route and the web route both exist. The web page `/legal/account-deletion` prints the Android package from `ANDROID_PACKAGE`, now `com.nivorasr.app` (`lib/legal-config.ts:96`, shown at `app/legal/account-deletion/page.tsx:142`). The live site changes only when the website is pushed, so check that the page shows `com.nivorasr.app` before entering the URL on any submission. It did on 2026-09-20, re-checked signed out, and the URL is in the form | [account-deletion.md](account-deletion.md) |

The legal version stays 2026-09-13 (`lib/legal-config.ts:80`): neither the privacy policy nor the
terms names the package, so the package change did not touch them.

### App access — what to enter in Console

Play Console → **Policy → App content → App access** → *All or some functionality is restricted*.
Add **one instruction set per account** (Google allows up to five). Put each username and password in
Console's own fields, and paste the matching block below into that set's **"Any other information"**.
One short set per account is easier for a reviewer than one long block, and safer if the field has
an unstated length limit.

The four sets below went in on 2026-09-19. They stay here as the text to paste again on the next
release, and because a changed password or a changed account means editing them first.

**Before submitting, sign in to each account yourself** on a phone, with the exact password you will
type into Console. That is standing procedure for every submission, not a one-off. All four accounts
existed and were active on 2026-09-20; check them again rather than trusting a date written here.

What is true of the demo property, checked against the live database on 2026-09-13, with the trigger
re-checked on 2026-09-14 and the four logins confirmed active on 2026-09-20:

- Every account below belongs to **Demo PG (Play review)**. Everything in it is fabricated.
- It was seeded so a reviewer lands on populated screens
  (`db/migrations/2026-09-13-demo-pg-play-review-seed.sql`): four months of expenses, a week's mess
  menu, notices, a pending and an approved leave, and visitors.
- **No Razorpay account is linked to it, on purpose**, so nobody can move real money during review.
- **The manager account exists.** `demo.manager@nivora.app` was created from the demo owner's staff
  screen and is active, so nothing has to be created before submitting. The steps that made it are
  kept under Set 3, as the way to recreate it if it is ever lost.
- **Demo addresses in Demo PG do not owe an email proof, for now.** Migration
  `db/migrations/2026-09-13-demo-review-skip-email-verification.sql`, applied to production, adds
  the trigger `users_zz_demo_review_email_verified`. Before an insert, or an update of the email, it
  stamps `public.users.email_verified_at` only when the row is in Demo PG
  (`d3300000-0000-4000-8000-000000000001`), the address is `demo.<x>@nivora.app`, the row is not
  already stamped, and, on an update, the email actually changed. It fires after
  `users_update_guard`. A rolled-back probe proved each case. `demo.owner`, `demo.warden` and
  resident `9000000001` were already verified on 2026-09-04; `demo.warden` has since been
  deactivated, and the warden login is now `demo.warden1@nivora.app`. Real hostels still owe the
  proof.
- **The trigger is temporary.** Remove it after review:

  ```sql
  drop trigger if exists users_zz_demo_review_email_verified on public.users;
  drop function if exists app.demo_review_email_verified();
  ```

- The nightly retention job removes complaints and notices older than two months. Before any review
  after early November, re-seed them.

**The passwords are not in this repository.** Type them into Console yourself.

#### Set 1 — Warden

Username: `demo.warden1@nivora.app`

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

#### Set 3 — Manager

Username: `demo.manager@nivora.app`

**This account exists and is active.** The steps that made it are kept here as the way to recreate
it if it is ever lost or deactivated. They need the owner's authenticator, because the owner has to
get past two-step verification to reach the staff screen:

1. Sign in as `demo.owner@nivora.app`. On the owner's More screen, tap **Staff accounts**
   (`nivora_app/lib/features/owner/more/owner_more_screen.dart:71`), then **Add manager**.
2. Check that the sheet shows **Demo PG (Play review)** — the demo owner's only property, which the
   sheet displays rather than asks for — and the Manager role. Type any full name and the email
   `demo.manager@nivora.app` exactly, then tap **Create manager account**. The app calls
   `owner-create-staff`.
3. The dialog shows the email and a **Temporary password**, once. Copy it, tick **I have saved these
   credentials**, and tap **Done**.
4. Sign out, then sign in as `demo.manager@nivora.app` with the temporary password. The app makes you
   set a new password (`nivora_app/lib/core/router/router.dart:171`). Choose the one you will type
   into Console.

**The demo manager is exempt from email verification, because of the Demo PG trigger above.** After
a new staff account's first password change, the app opens a verify-email screen that cannot be
dismissed (`nivora_app/lib/features/auth/change_password_screen.dart:190-191`). It opens only while
`email_verified_at` is empty (`nivora_app/lib/core/auth/session.dart:126`), and nobody reads mail
sent to `nivora.app`. The trigger stamps that column when `owner-create-staff` inserts the manager's
row, so the screen never opens. For the same reason, `requireVerifiedEmail()`
(`supabase/functions/_shared/verification.ts:108`) will not refuse this account if it ever creates
accounts. If the verify-email screen does open, one of three things is wrong: the address is not
exactly `demo.<x>@nivora.app`, the account is not in Demo PG, or the trigger has been dropped. Fix
that before submitting.

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

**This account is already enrolled in two-step verification.** The setup screen only opens for an
account that has no second factor yet, so signing in as the owner will not show it again, and the
key cannot be read back out of the app. The key was captured at enrolment and is held outside this
repository. It is what goes in place of `SETUP KEY` in the block below, when that block is typed
into Console. It is never written into this file.

Google requires review logins to be reusable, and the owner role always asks for an authenticator
code, so the reviewer needs a key that works every time. If the enrolment ever has to be done again,
on this account or on a demo owner for a later release, that is:

1. Sign in to Nivora as the demo owner, on an account with no second factor yet. The app opens the
   two-step verification setup screen.
2. It shows a QR code and, under **SETUP KEY**, the same key as text with a Copy button. Copy the
   text key.
3. Add that key to your own authenticator app and tick **"I have saved this key"**. Under
   **"2. Enter the code it shows"**, type the 6-digit code and tap **"Turn on two-factor"**.
4. Keep the text key outside this repository, with the passwords. Put it in place of `SETUP KEY`
   when you paste the block below into Console, not in this file.

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

The confirmation link's custom scheme is the applicationId (`Env.emailLinkScheme`,
`nivora_app/lib/core/config/env.dart:40`, matched by the manifest filter at
`nivora_app/android/app/src/main/AndroidManifest.xml:142`), so it changed with the package. The
link now returns on:

```
com.nivorasr.app://verify-email
```

Supabase Dashboard → **Authentication → URL Configuration → Redirect URLs** → add exactly that
string. Until 2026-09-13 this step named `com.srnivora.app://verify-email`; that old entry can be
removed.

**GoTrue does not refuse an unlisted redirect — it silently substitutes the Site URL.** So a
missing entry does not look broken: the email arrives, the link works, and it opens a web page
instead of the app. Measured on this project on 2026-09-01; see
[email-verification.md](email-verification.md).

The demo manager does not depend on this entry (Set 3). Every real staff account does.

### 2. Push notifications: set up, not yet seen on a phone

Firebase is set up for push only; the backend stays Supabase. Project `nivorapg` holds two Android
apps:

| Firebase Android app | Status |
|---|---|
| `com.nivorasr.app` | **The app.** It matches `applicationId` (`nivora_app/android/app/build.gradle.kts:109`). Keep it; do not delete it |
| `com.srnivora.app` | Left over from the abandoned listing. Nothing uses it, and it may be deleted later |

Until 2026-09-13 this section called the `com.nivorasr.app` registration a typo never to be used.
That is reversed: it is now the app.

`nivora_app/android/app/google-services.json` sits on the build machine and is gitignored
(`nivora_app/.gitignore:53`). It has a client for each of the two packages, and the Google Services
plugin (applied at `nivora_app/android/app/build.gradle.kts:25-26` when that file exists) picks the
one matching `applicationId`, so the file needs no edit. The `FCM_SERVICE_ACCOUNT` secret in Supabase
is project-level and needs no change either: a `push-send` probe on 2026-09-13 answered
`claimed: 0`, not `not_configured`. Details are in
[edge-functions.md → push-send](edge-functions.md). **Do not create another Firebase project.**

What is not proven is delivery: nobody has yet seen a notification arrive on a real phone. Install
the build from the testing track, tap **Agree and continue**, allow notifications, then trigger one
(a notice to residents is the quickest). Until that works, keep the store listing on
`full-description-without-push.txt`.

---

## Verifying the artifact before you upload it

**Do not run `scripts/release.sh` for this.** It rebuilds, and it overwrites
`dist/NIVORA-1.0.0.aab` with a new, unmeasured file that still says versionCode 6. Check the files
that are already there. `nivora_app/scripts/release.sh:420-422` stages all three from one run:

| File | What it is | Bytes |
|---|---|---|
| `dist/NIVORA-1.0.0.aab` | The upload | 66,433,003 |
| `dist/NIVORA-1.0.0.apk` | arm64 APK, the one to hand round | 25,372,605 |
| `dist/NIVORA-1.0.0-universal.apk` | Universal APK, any CPU | 68,799,987 |

They were built on 2026-09-16.

```bash
sha256sum dist/NIVORA-1.0.0.aab
# must print d1283f6b173eecf37d6ebbbb2d026e414d8e60b0dc7480a5505583075a888541
BT="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)"
"$BT/aapt2.exe" dump badging dist/NIVORA-1.0.0.apk | head -1
# must start: package: name='com.nivorasr.app' versionCode='6' versionName='1.0.0'
cd nivora_app && bash scripts/verify-adid.sh
```

The package line matters more than usual. The first bundle uploaded to a new app fixes its package
permanently, and versionCode 6 was that bundle, so `com.nivorasr.app` is now locked in and every
later upload has to carry it. `aapt2` reads APKs rather than bundles, so the line
comes from the arm64 APK of the same `release.sh` run, not from the bundle itself; the build-tools
lookup is the one `release.sh:34` uses.

A matching hash means this is the versionCode 6 bundle. The measured checks in
[play-technical-compliance.md](play-technical-compliance.md) — ten permissions (the receiver one is
now `com.nivorasr.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`), no AD_ID, 16 KB alignment, signed
with the upload key — were measured on the versionCode 5 bundle on 2026-09-14, after first being
taken on versionCode 4 for the abandoned listing. They have not been re-run on versionCode 6, so
run them again on this bundle rather than reading those tables as if they described it. A different
hash means `dist/` was rebuilt, and every one of those checks has to be run again before upload.

When a rebuild *is* wanted — any code change, which also means raising the `+N` in
`nivora_app/pubspec.yaml` — `scripts/release.sh` refuses to stage anything that fails its own gates:
the upload key (`CN=HostelPro`, not a debug fallback), the launcher label (`Nivora` — it once
shipped as "mobile", the Flutter project name), `libflutter.so` in every ABI directory, a versionCode
matching `pubspec.yaml`, and no service-role key or Razorpay secret anywhere in the bundle, in
either of the two encodings a Dart snapshot uses. It does not check the package name.

---

## History: the abandoned `com.srnivora.app` listing

Until 2026-09-13 this page was about a different Console app, locked to the package
`com.srnivora.app`. Nothing was ever released from it, and it has been abandoned in favour of the new
app above.

- An early upload to it was refused because the bundle's package did not match the one that listing
  was locked to. The code was then moved to `com.srnivora.app` to fit.
- A release on it then showed three errors that were one problem: the release had no bundle in it.
  The note at the end of Step 3 comes from that.
- versionCodes 1 to 4 were built for it. The verified build was versionCode 4, AAB SHA-256
  `a85e26c1…a975ba`, checked in [play-technical-compliance.md](play-technical-compliance.md) on
  2026-09-13.
- On 2026-09-13 and 2026-09-14 the code, the email deep link, the Supabase redirect URL and the
  Firebase registration moved to `com.nivorasr.app`, and versionCode 5 was built for the new app.
  That build was never uploaded: versionCode 6, built on 2026-09-16, went up instead.
  Everything entered on the old listing is entered again there.
