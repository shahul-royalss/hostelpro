# Play technical compliance — independent verification of the release artifact

**Artifact:** `dist/NIVORA-1.0.0.apk` and `dist/NIVORA-1.0.0.aab`
**Package:** `app.nivora.mobile` · versionCode 1 · versionName 1.0.0
**Verified:** 25 August 2026, on the build workstation.
**Method:** every claim below was read out of the artifact itself with `aapt2`, `apksigner`,
`unzip` and a direct ELF header parse. Nothing was taken on trust from the build guide.

> **This document replaced a version that described a completely different app.** The earlier
> revision verified the Trusted Web Activity build — package `app.nivora.twa`, 937 KB, one
> permission, zero native libraries. That artifact no longer exists: the product is a native
> Flutter client. A stale compliance document is worse than none, because it is consulted at
> exactly the moment when being wrong is most expensive. Everything below was re-measured.

---

## 0. Verdict first

| # | Requirement | Status |
|---|---|---|
| 1 | Target API level (API 36 required for new submissions from 31 Aug 2026) | **PASS** — `targetSdkVersion 36` |
| 2 | Permissions minimal and justified | **PASS** — 8 entries, every one traced to a source; see §2 |
| 3 | Signing key strength | **PASS** — RSA 2048, `CN=HostelPro, O=HostelPro, C=IN` |
| 4 | Signature schemes | **PASS** — AAB is JAR-signed (`META-INF/HOSTELPR.RSA`), which is what Play requires; APK is v2 |
| 5 | **16 KB page-size compatibility** (required from 1 Nov 2025) | **PASS** — 5 native libraries, all aligned ≥ 16 KB; see §3 |
| 6 | ABI coverage | **PASS** — `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| 7 | Artifact size | **PASS** — APK 66 MB, AAB 64 MB, far under the 200 MB base limit |
| 8 | Typeface available offline | **PASS** — Inter bundled; the app does not fetch fonts at runtime |
| 9 | No secrets in the shipped bundle | **PASS** — see §5 |

**No technical blockers in the artifact.** The remaining blockers are operational, not built into
the binary, and are listed in §6.

---

## 1. Target and compile SDK

```
$ aapt2 dump badging dist/NIVORA-1.0.0.apk | grep -E "package:|targetSdkVersion"
package: name='app.nivora.mobile' versionCode='1' versionName='1.0.0'
         compileSdkVersion='36' compileSdkVersionCodename='16'
targetSdkVersion:'36'
```

Google requires API 36 for new submissions from 31 August 2026. This targets 36 today, so the
deadline is not a future migration.

`minSdk` and `targetSdk` are inherited from `flutter.minSdkVersion` / `flutter.targetSdkVersion`
(`android/app/build.gradle.kts:62-63`) rather than pinned. That is deliberate — Flutter raises
them in step with its own support window — but it does mean **a Flutter SDK upgrade can change
the target level without anyone editing this project**. Re-check this table after any upgrade.

---

## 2. Permissions

```
$ aapt2 dump badging dist/NIVORA-1.0.0.apk | grep uses-permission
android.permission.INTERNET
android.permission.ACCESS_NETWORK_STATE
android.permission.WAKE_LOCK
android.permission.POST_NOTIFICATIONS
android.permission.NFC
com.google.android.c2dm.permission.RECEIVE
app.nivora.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
android.permission.READ_BASIC_PHONE_STATE
```

Eight entries. **Only two are declared by this project; the rest arrive through the manifest
merger from dependencies.** Each was traced to its origin in
`build/app/outputs/logs/manifest-merger-release-report.txt` rather than guessed at:

| Permission | Protection | Origin | Justified? |
|---|---|---|---|
| `INTERNET` | normal | **ours**, plus firebase_messaging, razorpay, firebase-installations | **Yes.** Every screen reads from Supabase. Worth knowing: the merger contributes this anyway, which is why the release build had network *before* it was added to our manifest — see the note in §7. |
| `ACCESS_NETWORK_STATE` | normal | **ours** | **Yes.** Lets the app distinguish "you are offline" from "the server is down" — two different messages to a warden standing in a corridor. |
| `WAKE_LOCK` | normal | firebase_messaging | **Yes.** Holds the CPU briefly while an FCM message is processed. |
| `POST_NOTIFICATIONS` | **runtime** (API 33+) | firebase_messaging | **Yes.** Rent reminders and complaint updates. This is the only entry that prompts the user, and the prompt is declinable without breaking the app. |
| `NFC` | normal | `com.razorpay:standard-core:1.7.18` | **Yes, and not ours to remove.** Razorpay Checkout supports contactless card reads. No runtime prompt. |
| `READ_BASIC_PHONE_STATE` | normal | `com.razorpay:core:1.0.18` | **Yes.** The API-33+ *reduced-scope* replacement for `READ_PHONE_STATE`; Razorpay uses it for carrier detection during UPI and OTP flows. It exposes no device identifier, so it needs **no** Play Console declaration — unlike `READ_PHONE_STATE`, which would. |
| `com.google.android.c2dm.permission.RECEIVE` | signature | firebase_messaging | **Yes.** Standard FCM delivery. |
| `app.nivora.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `signature` | androidx.core | **Yes.** Auto-generated when a non-exported runtime receiver is registered on API 33+. Namespaced to this app, signature-level, grants access to nothing. Not shown to users. |

**Specifically absent**, and each absence is load-bearing for the Data safety answers:

- no `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`
- no `CAMERA`, `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE`
- no `com.google.android.gms.permission.AD_ID` — there is no advertising ID to declare
- no `READ_PHONE_STATE` (the full-scope one), no `READ_CONTACTS`, no `QUERY_ALL_PACKAGES`

---

## 3. 16 KB page-size compatibility

Required for all apps targeting API 35+ from 1 November 2025. **The previous revision of this
document passed this requirement by having no native code at all.** That is no longer true — a
Flutter app ships the engine, so the requirement now has to be met rather than sidestepped.

Measured by parsing the ELF program headers of every `arm64-v8a` library and taking the smallest
`p_align` across its `PT_LOAD` segments:

| Library | min LOAD alignment | |
|---|---|---|
| `libapp.so` | 65536 (64 KB) | PASS |
| `libflutter.so` | 65536 (64 KB) | PASS |
| `libdartjni.so` | 16384 (16 KB) | PASS |
| `libdatastore_shared_counter.so` | 16384 (16 KB) | PASS |
| `libsqlite3.so` | 16384 (16 KB) | PASS |

All five clear the 16 KB threshold. **Re-run this after any Flutter or plugin upgrade** — a single
dependency built with a 4 KB-aligned toolchain fails the whole upload, and nothing else in the
build reports it.

---

## 4. Signing

```
$ apksigner verify --print-certs --verbose dist/NIVORA-1.0.0.apk
Verified using v2 scheme (APK Signature Scheme v2): true
Number of signers: 1
V2 Signer: certificate DN: CN=HostelPro, O=HostelPro, C=IN
V2 Signer: key algorithm: RSA
V2 Signer: key size (bits): 2048
V2 Signer: certificate SHA-256 digest:
  24239746895a546386f1874b1db5f5313d02da99dbe472f5451923581ffb6465
```

The AAB carries `META-INF/HOSTELPR.RSA` + `.SF` + `MANIFEST.MF` — JAR signing, which is the
correct and only scheme for a bundle. Play re-signs the delivered APKs with its own key.

**This is the check that matters most in the whole document.** Flutter's Gradle template falls
back to the *debug* key when release signing is misconfigured, and it does so silently — the
build succeeds and the artifact is rejected only at upload. `scripts/release.sh` refuses to stage
anything not signed with `CN=HostelPro` precisely because that failure is invisible otherwise.

**After the first upload**, add the SHA-256 of the *Play App Signing* key (Console → Setup → App
signing) anywhere the upload fingerprint is currently used. Google re-signs, so the certificate
that reaches a user's device is not the one above.

---

## 5. No secrets in the shipped bundle

An APK is a zip archive anyone can download and unpack, so this is not a theoretical concern.

Verified on the staged artifact:

- the Razorpay **key secret** appears nowhere under `nivora_app/`
- every JWT literal in the client decodes to `"role":"anon"` — the anon key is public by design
  and grants nothing without RLS; there is **no** `service_role` key
- the service-role key and the Razorpay secret live only as Supabase Edge Function secrets, set
  with `supabase secrets set` and never committed

`scripts/release.sh` re-checks all of this on every build and refuses to stage on a hit.

---

## 6. What still blocks the listing

Neither is inside the artifact.

**6.1 — The Edge Functions are not deployed.** `sa-create-owner`, `owner-create-staff`,
`warden-register-student`, `razorpay-order` and `razorpay-webhook` exist in `supabase/functions/`
and are invoked by the app, but deploying them needs a Supabase access token. Until
[`edge-functions.md`](./edge-functions.md) is followed, creating an owner and paying rent fail at
runtime regardless of how finished the screens look.

**6.2 — Privacy policy URL must be reachable without signing in.** Play fetches it anonymously.

**Note on `assetlinks.json`:** the previous revision listed it as a blocker. It was, for a Trusted
Web Activity, where Digital Asset Links is what stops the app opening in a browser chrome. This is
a native client and does not depend on it. It is required again only if App Links deep-linking is
added later.

---

## 7. One finding worth recording

The `INTERNET` permission was once believed to be missing from the release build, and adding it to
the main manifest was believed to have fixed an app that would not open. **Both beliefs were
wrong.** The manifest merger already contributed `INTERNET` from `firebase_messaging`,
`razorpay:standard-core` and `firebase-installations`, so the release build always had network.
The real cause was a routing bug that held the app on its splash screen forever — see the commit
"Fix the real reason the app would not open".

It is recorded here because the merger report is the tool that settles this class of question, and
because a permission you did not declare can still be in your app — which cuts both ways.
