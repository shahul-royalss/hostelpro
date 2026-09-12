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

Play Console → **Testing → Internal testing → Testers** → create an email list → add the addresses
that should get it (your own Google account first) → Save. Then share the opt-in link Console
gives you; a tester has to accept it once before the app appears for them.

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
