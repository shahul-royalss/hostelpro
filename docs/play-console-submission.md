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

1. Play Console → your app → **Testing → Internal testing** (or the track you are releasing to) →
   **Create new release**.
2. Upload `dist/NIVORA-1.0.0.aab`. Wait for it to finish processing — the errors clear as soon as
   Console has parsed it, not when the upload bar fills.
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

Play Console → **Testing → Internal testing → Testers** tab:

1. **Create email list** → name it `Nivora internal testers`.
2. Add `codewithshahul@gmail.com` — the account that owns this Play Console. It is allowed to be
   its own tester, and it should be the first one.
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
| Financial features | Nivora takes rent through Razorpay for a **physical service** (accommodation), not digital goods — so Play's billing requirement does not apply | [data-safety.md §5](data-safety.md) |
| Government apps | No | — |
| Health | No | — |
| Data deletion | The in-app route and the web route both exist | [account-deletion.md](account-deletion.md) |

### App access — the text to paste into Console

Under **App access**, choose *All or some functionality is restricted*, add an instruction entry
per account, and put the passwords in Console's own password fields. Paste the block below into
**"Any other information required to access your app"**.

Verified against the live database on 2026-09-12: all three accounts exist, are `active`, have
`must_change_password = false` and a verified email, and hold no TOTP factor. `demo.owner` owns
`Demo PG (Play review)` through `hostels.owner_user_id`, so its null `users.hostel_id` is normal
for an owner and its dashboard is populated. None of the three has accepted legal version
`2026-09-12`, which is why the consent screen is described below rather than omitted.

**The passwords are deliberately not in this repository.** Set or confirm them before submitting,
and type them into Console yourself.

```text
Nivora is a private, invitation-only tool for PG and hostel operators in India. There is
no public sign-up — accounts are created by an administrator — so the app cannot be reviewed
without the credentials below.

The sign-in screen has ONE field labelled "Email or phone number". Staff type an email address;
residents type a phone number. There is no role selector: the role is determined by the account.

All three accounts belong to one demo property, "Demo PG (Play review)" (6 rooms, 1 resident).
Every resident, payment and complaint in it is fabricated. No real person's data appears.

--- 1. WARDEN — the fullest view, no 2-step verification ---
Username: demo.warden@nivora.app
Type the email address exactly as shown.
Covers: resident registration, room and bed allocation, rent collected at the desk and receipts,
complaints, leave requests, visitor log and the mess menu.

--- 2. RESIDENT — type the PHONE NUMBER, not an email ---
Username: 9000000001
Residents sign in with their 10-digit phone number. The app maps it to an internal address for
you; do not type an email for this account, as that will fail.
Covers: rent due and paid, receipts, UPI payment, raising a complaint, leave and notices.

--- 3. OWNER — requires 2-step verification, see below ---
Username: demo.owner@nivora.app
Covers: the property summary, staff accounts, expense statistics and tasks.

=== TWO-STEP VERIFICATION (this is the restricted access) ===
The Owner and Super Admin roles require TOTP two-factor authentication. Warden and Resident do
not, and can be reviewed with a password alone.

The owner account has no authenticator enrolled yet, so after the password it goes to a setup
screen showing a QR code and the same secret as text. Scan either with any authenticator app
(Google Authenticator, Authy, 1Password), tick "I have saved this", then enter the 6-digit code.
That account will ask for a code at each sign-in afterwards.

There is no bypass and no backdoor code: this is the same flow a real owner goes through, and
weakening it for review would misrepresent the app. If you prefer not to enrol an authenticator,
the Warden and Resident accounts above need no second factor and between them reach every screen
except the four Owner-only ones named above.

=== FIRST SCREEN AFTER SIGNING IN: ACCEPT THE TERMS ===
Each account shows a one-time "Terms of Use and Privacy Policy" screen on its first sign-in,
because both documents were updated on 12 September 2026. Tap Accept to continue into the app.
It appears once per account and cannot be skipped, as consent is recorded.

=== OTHER THINGS WORTH KNOWING ===
- On first launch the app shows a short intro carousel. Tap Skip to reach the sign-in screen.
- Sign-in is rate limited to 8 attempts per account per 15 minutes. A password typed wrongly
  several times produces a "please wait" message rather than a password error. Wait the stated
  time; the credentials are still correct.
- There is no biometric login, no QR-code entry, no location restriction and no membership or
  paid tier gating any screen.
- The app is India-specific: amounts are in Indian rupees and dates follow the Asia/Kolkata day.
```

**Do not hand Play a Super Admin account.** It is 2FA-gated like Owner and reaches every tenant on
the platform, including real hostels with real residents. Nothing in the review requires it.

---

### App access — give the reviewer a working login

Under **App access**, choose *All or some functionality is restricted* and add an instruction for
each role you want reviewed. A reviewer who is handed one account sees one fifth of the app.

Use the demo PG (`Demo PG (Play review)`), never a real owner's account, and say plainly in the
notes that the app is multi-tenant and that the credentials open a demo property with fabricated
residents.

**Two-factor authentication will block a reviewer.** Owner and Super Admin require a second factor;
the demo accounts you give Play must either not be in `MFA_REQUIRED_ROLES` or must be roles that do
not require it (warden, manager, student). Hand over warden and manager logins, and describe what
the owner screens contain rather than exposing an account that needs a TOTP the reviewer cannot
generate.

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

### 2. Firebase, if notifications are to actually arrive

Everything on both sides is built and deployed — the triggers, the daily rent-reminder job, the
`push-send` function, the device registry, the client. The only missing piece is the project
itself, which belongs to whoever owns this listing. Four steps, in
[edge-functions.md → push-send](edge-functions.md).

Until then the app builds, runs and asks for notification permission exactly as it will afterwards;
notifications are written and visible in the database, they simply do not reach a phone.

---

## Verifying the artifact before you upload it

`scripts/release.sh` refuses to produce anything that fails these, but the numbers are worth
reading with your own eyes once:

```bash
cd nivora_app && bash scripts/release.sh
```

It checks the upload key (`CN=HostelPro`, not a debug fallback), the launcher label (`Nivora` — it
once shipped as "mobile", the Flutter project name), that every ABI directory carries
`libflutter.so`, that the versionCode matches `pubspec.yaml`, and that no service-role key or
Razorpay secret is anywhere in the bundle, in either of the two encodings a Dart snapshot uses.
