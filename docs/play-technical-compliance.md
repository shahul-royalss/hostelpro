# Play technical compliance — independent verification of the release artifact

**Artifact:** `dist/NIVORA-1.0.0.apk`, `dist/NIVORA-1.0.0-universal.apk` and `dist/NIVORA-1.0.0.aab`
**Package:** `com.srnivora.app` · versionCode 4 · versionName 1.0.0 · release name `1.0.0 (4)` · compileSdk 37 · targetSdk 36
**Verified:** 4 September 2026 against the versionCode 1 artifacts (then compiled against SDK 36);
permissions verified again on 12 September 2026 against the rebuilt versionCode 1 artifact, compiled
against SDK 37 after commit `ad64557` pinned `compileSdk = 37` that day; re-audited 13 September 2026
against the versionCode 3 artifacts; and **re-measured 13 September 2026 against the versionCode 4
artifacts, which are the upload**, built by `scripts/release.sh` at 20:21 IST from the source committed
as `4fd41ef` (two comment-only edits, to `AndroidManifest.xml` and `proguard-rules.pro`, landed after
the build copied the tree; neither changes the binary).
**Which build the numbers belong to:** the badging (§1), the permission dump, merge origins and AD_ID
check (§2), the 16 KB alignment table (§3), the signer digest (§4) and the sizes in verdict row 7 are
**versionCode 4's**. The `apksigner` block in §4 is still the versionCode 1 output, kept for its
format; the versionCode 4 certificate was read separately and is the same key. **Any rebuild
invalidates every number here:** `libapp.so` is the AOT-compiled Dart code, so even a Dart-only change
produces a different artifact that has to be measured again.
**Method:** every artifact claim below was read out of the artifact itself with `aapt2`, `apksigner`,
`unzip` and a direct ELF header parse. The permission origins in §2 come from the dependencies' own
manifests. Nothing was taken on trust from the build guide.

> **This document replaced a version that described a completely different app.** The earlier
> revision verified the Trusted Web Activity build — package `app.nivora.twa`, 937 KB, one
> permission, zero native libraries. That artifact no longer exists: the product is a native
> Flutter client. A stale compliance document is worse than none, because it is consulted at
> exactly the moment when being wrong is most expensive. Everything below was re-measured.

---

## 0. Verdict first

| # | Requirement | Status |
|---|---|---|
| 1 | Target API level (API 36 required for new submissions from 31 Aug 2026) | **PASS** on versionCode 4 — `targetSdkVersion 36` (§1) |
| 2 | Permissions minimal and justified | **Verified 2026-09-12** on versionCode 1, and **dumped again 2026-09-13** on versionCode 3 and on versionCode 4 — the same 10 entries each time. Each entry's origin is read from the versionCode 4 build's manifest-merger report (§2). No AD_ID in any of the three versionCode 4 artifacts, shown by a check that can actually read an APK manifest (§2 explains why the earlier "clean" was not evidence). See §2 |
| 3 | Signing key strength | **PASS** — RSA 2048, `CN=HostelPro, O=HostelPro, C=IN` (the §4 `apksigner` block is the versionCode 1 output; the versionCode 4 bundle's certificate digest, read on 2026-09-13, is the same key) |
| 4 | Signature schemes | **PASS** — AAB is JAR-signed (`keytool -printcert -jarfile` reads the upload certificate out of the versionCode 4 bundle), which is what Play requires; APK is v2, and the signature gate in `release.sh` passed on both versionCode 4 APKs |
| 5 | **16 KB page-size compatibility** (required for apps targeting API 35+; from 1 Feb 2027 an update without it cannot be released) | **PASS on versionCode 4** — 12 native libraries, the same four in each of `arm64-v8a`, `armeabi-v7a` and `x86_64`, every `PT_LOAD` segment aligned ≥ 16 KB, measured on the versionCode 4 bundle; see §3 |
| 6 | ABI coverage | **PASS** — the AAB carries `arm64-v8a`, `armeabi-v7a` and `x86_64`, and Play splits it per device. The APK handed round directly is arm64-only by design; `NIVORA-<v>-universal.apk` is the one that installs anywhere |
| 7 | Artifact size | **PASS** — measured on the versionCode 4 artifacts: arm64 APK 25.3 MB (25,306,793 bytes), universal APK 68.6 MB (68,586,719), AAB 66.2 MB (66,228,048), all far under the 200 MB base limit. What a phone downloads from Play is the per-device split of the AAB, not the whole bundle |
| 8 | Typeface available offline | **PASS** — Inter bundled; the app does not fetch fonts at runtime |
| 9 | No secrets in the shipped bundle | **PASS** — see §5 |

**No technical blockers in the versionCode 4 artifacts, which are the upload.** A rebuild of any
kind needs §1–§4 and row 7 measured again. The remaining blockers are operational, not built into
the binary, and are listed in §6.

---

## 1. Target and compile SDK

```
$ aapt2 dump badging dist/NIVORA-1.0.0.apk | grep -E "package:|targetSdkVersion"
package: name='com.srnivora.app' versionCode='4' versionName='1.0.0'
         platformBuildVersionName='17' platformBuildVersionCode='37'
         compileSdkVersion='37' compileSdkVersionCodename='17'
targetSdkVersion:'36'
```

That is the versionCode 4 build, dumped on 2026-09-13 with build-tools 37.0.0 (the `package:` line
is wrapped here for width). versionCode 3 printed the same values apart from the version code. An
earlier revision showed `versionCode='1'` and `compileSdkVersion='36'`; compileSdk
is now 37, for the reason given below.

Google requires API 36 for new submissions from 31 August 2026. This targets 36 today, so the
deadline is not a future migration.

`minSdk` and `targetSdk` are inherited from `flutter.minSdkVersion` / `flutter.targetSdkVersion`
(`nivora_app/android/app/build.gradle.kts:112-113`) rather than pinned. That is deliberate — Flutter raises
them in step with its own support window — but it does mean **a Flutter SDK upgrade can change
the target level without anyone editing this project**. Re-check this table after any upgrade.

`compileSdk` is the exception. It is pinned to 37 at `nivora_app/android/app/build.gradle.kts:75`,
one above `flutter.compileSdkVersion`, because `permission_handler_android` refuses to compile
against anything lower. Compiling against 37 is not targeting 37: Play measures `targetSdk`, which
stays at Flutter's 36. The pin comes out once Flutter's own value reaches 37.

---

## 2. Permissions

Verified against `dist/NIVORA-1.0.0.apk` **as built on 2026-09-12** (package `com.srnivora.app`,
versionCode 1, targetSdk 36, compileSdk 37), dumped again on 2026-09-13 from both versionCode 3
APKs, and dumped once more from the versionCode 4 universal APK that evening. All of them list the
same ten permissions in the same order. The block below is in the format
build-tools 37.0.0 actually prints. An earlier revision showed a simplified one-name-per-line list
instead:

```
$ aapt2 dump permissions dist/NIVORA-1.0.0.apk
package: com.srnivora.app
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
uses-permission: name='android.permission.CAMERA'
uses-permission: name='android.permission.WAKE_LOCK'
uses-permission: name='android.permission.VIBRATE'
uses-permission: name='android.permission.NFC'
uses-permission: name='com.google.android.c2dm.permission.RECEIVE'
permission: com.srnivora.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='com.srnivora.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
uses-permission: name='android.permission.READ_BASIC_PHONE_STATE'
```

The `permission:` line is the app *defining* its own receiver permission; the `uses-permission:`
line after it is the app using it. Ten permissions used. **Only four are declared by this project**
(`nivora_app/android/app/src/main/AndroidManifest.xml:10`, `:12`, `:50`, `:51`); **the rest arrive
through the manifest merger from dependencies**, and three of our four are declared by dependencies
as well.

The Origin column is read from the manifest-merger report of the versionCode 4 build
(`/c/nivora-work/app/build/app/outputs/logs/manifest-merger-release-report.txt`, written 20:21 IST on
2026-09-13). For each entry it lists every source the merger `ADDED` or `MERGED`. "Ours" is the
`ADDED` line from our own manifest; the libraries after it declare the same permission. An earlier
pass rebuilt this column from the dependencies' own manifests because that build's report had already
been deleted, and the report shows that pass missed several Google Play services and Firebase
transport libraries.

| Permission | Protection | Origin | Justified? |
|---|---|---|---|
| `INTERNET` | normal | **ours**, plus the `firebase_messaging` plugin, `com.razorpay:standard-core:1.7.18`, `com.razorpay:core:1.0.18`, `com.google.firebase:firebase-installations:19.1.2`, `com.google.android.gms:play-services-cloud-messaging:17.4.0`, `com.google.android.gms:play-services-maps:17.0.0` and `com.google.android.datatransport:transport-backend-cct:3.1.9` | **Yes.** Every screen reads from Supabase. Worth knowing: the merger contributes this anyway, which is why the release build had network *before* it was added to our manifest — see the note in §7. |
| `ACCESS_NETWORK_STATE` | normal | **ours**, plus the `firebase_messaging` plugin, `firebase-messaging:25.1.2`, `firebase-installations:19.1.2`, `play-services-cloud-messaging:17.4.0`, `play-services-maps:17.0.0`, `transport-backend-cct:3.1.9`, `transport-runtime:3.1.9` and `com.razorpay:core:1.0.18` | **Yes.** Lets the app distinguish "you are offline" from "the server is down" — two different messages to a warden standing in a corridor. |
| `NFC` | normal | `com.razorpay:standard-core:1.7.18` | **Yes, and not ours to remove.** Razorpay Checkout supports contactless card reads. No runtime prompt. |
| `READ_BASIC_PHONE_STATE` | normal | `com.razorpay:core:1.0.18` | **Yes.** The API-33+ *reduced-scope* replacement for `READ_PHONE_STATE`; Razorpay uses it for carrier detection during UPI and OTP flows. It exposes no device identifier, so it needs **no** Play Console declaration — unlike `READ_PHONE_STATE`, which would. |
| `com.srnivora.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `signature` | `androidx.core:core:1.18.0` | **Yes.** Auto-generated when a non-exported runtime receiver is registered on API 33+. Namespaced to this app, signature-level, grants access to nothing. Not shown to users. |
| `POST_NOTIFICATIONS` | dangerous | **ours**, plus `firebase-messaging`, the `firebase_messaging` plugin and `flutter_local_notifications` | **Yes.** Rent reminders, notices, "payment received", a task assigned. Runtime permission from Android 13: without it the app can hold a valid FCM token, the server can send a perfectly good message, and NOTHING APPEARS — silently. **Asked for behind the consent gate, not at sign-in and not on first launch.** Push starts in `lib/features/legal/consent_gate.dart`: from `initState` for someone who agreed on an earlier launch (`:93-95`), and from `_accept` for someone agreeing now (`:166`). `lib/core/notify/push_service.dart` then shows the system dialog itself, with no in-app rationale screen (`_askPermission`, `:183-193`), and a refusal still registers the token (`:117-118`). `lib/main.dart` only stops push, on sign-out (`:236`). Delivery to a real phone is not yet proven. |
| `CAMERA` | dangerous | **ours** | **Yes.** A warden photographs a new resident and their ID proof at registration (`lib/features/warden/actions/register_student_sheet.dart`). This row used to add that a resident photographs a complaint; the resident Android app cannot attach a photo to a complaint, so that part of the justification was wrong and is gone. Declaring it is what makes it mandatory — `ACTION_IMAGE_CAPTURE` throws `SecurityException` for an app that declares CAMERA without holding it. `lib/data/capture.dart` requests it first. `<uses-feature android:required="false"/>` keeps the app installable on a device with no camera. |
| `WAKE_LOCK` | normal | `:firebase_messaging`, `com.google.firebase:firebase-messaging:25.1.2` and `com.google.android.gms:play-services-cloud-messaging:17.4.0` | **Yes, and not ours to remove.** Wakes the device long enough to hand off an incoming push. No runtime prompt. |
| `VIBRATE` | normal | `:flutter_local_notifications` | **Yes.** The notification channel is `Importance.high`, which vibrates. No runtime prompt. |
| `com.google.android.c2dm.permission.RECEIVE` | signature-ish | `com.google.firebase:firebase-messaging:25.1.2`, plus `com.google.android.gms:play-services-cloud-messaging:17.4.0` | **Yes.** The permission that lets FCM deliver to this app at all. Google-namespaced, not user-visible. |

**Specifically absent**, and each absence is load-bearing for the Data safety answers:

- no `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`
- no `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` — the gallery goes through Android's photo
  picker, which returns one chosen image and needs no permission at all. Asking for the media
  library would trigger Play's Photo and Video Permissions declaration for a capability this app
  does not use
- no `READ_CONTACTS` — nothing in Nivora reads a contact
- no `com.google.android.gms.permission.AD_ID` — there is no advertising ID to declare, and since
  2026-09-12 it is removed EXPLICITLY (`tools:node="remove"`) rather than merely left out, because
  a dependency's manifest can merge one in and its presence would contradict the Data safety form
- no `READ_PHONE_STATE` (the full-scope one)
- no `QUERY_ALL_PACKAGES`. Razorpay's UPI-app detection works through the manifest's `<queries>`
  block for the `upi` scheme instead (`nivora_app/android/app/src/main/AndroidManifest.xml:156` and
  `:178`). That detection is why Data safety answers Installed apps = Yes (`docs/data-safety.md` §3.4)

### How this table was checked, and how to check it again

The AD_ID absence in particular is a claim about the **merged** manifest, not about our source —
which is the whole reason it is removed with `tools:node="remove"` rather than simply left out. It
was verified on the built artifacts, all three of them, on 2026-09-13: on versionCode 3, and again on
the versionCode 4 files, with the same result:

```bash
cd nivora_app && bash scripts/verify-adid.sh
#   clean: NIVORA-1.0.0-universal.apk (manifest readable: INTERNET found, AD_ID not found)
#   clean: NIVORA-1.0.0.apk (manifest readable: INTERNET found, AD_ID not found)
#   clean: NIVORA-1.0.0.aab (manifest readable: INTERNET found, AD_ID not found)
```

**The "clean" this section used to show proved nothing for the two APKs.** Until 2026-09-13 the
script searched for the permission as UTF-8 bytes only. An AAB's protobuf manifest stores strings as
UTF-8, but an APK's compiled binary XML stores them as UTF-16, so on an APK the search could never
match and "clean" was printed whatever the manifest said. The audit caught it with a positive
control: `android.permission.CAMERA`, which `aapt2` lists as present, was invisible to the old search
in both APKs. The script now searches both encodings and will not print "clean" unless it also finds
`android.permission.INTERNET` in the same file; when it cannot, it prints `CANNOT READ` and exits
non-zero. AD_ID was genuinely absent before the fix as well (the `aapt2` dump above does not list
it), but the script's old output was not the evidence for that.

To re-attribute any entry after a dependency changes, read the merge-blame report of the build in
question. It names the exact AAR and line that contributed each permission, which is how `NFC` and
`READ_BASIC_PHONE_STATE` were first pinned on Razorpay. The report is not in the repository tree.
When the repo is inside OneDrive, `scripts/release.sh` builds in `$NIVORA_WORK_DIR`, default
`/c/nivora-work`, and deletes that tree at the start of every run
(`nivora_app/scripts/release.sh:62-68`). So the report only ever describes the last build, and has
to be read before the next one starts. The versionCode 4 origins in the table above were read from
it on 2026-09-13, before any further build:

```bash
grep -A2 "permission.NFC" \
  /c/nivora-work/app/build/app/intermediates/manifest_merge_blame_file/release/processReleaseMainManifest/manifest-merger-blame-release-report.txt
```

**A permission dump is only ever true of one artifact.** An earlier version of this section was
carried forward across a package-name change and described a build that no longer existed. If the
dependency list moves, re-run the dump before signing anything off.

---

## 3. 16 KB page-size compatibility

Google's page-size guide (`developer.android.com/guide/practices/page-sizes`, last updated
2026-09-11) says that all apps targeting Android 15 (API level 35) and higher must support 16 KB
memory page sizes on 64-bit devices on Google Play, and that starting February 1, 2027, updates that
do not support 16 KB page sizes cannot be released. This section used to say the requirement applied
"from 1 November 2025"; the guide no longer words it that way, so this section now uses the guide's
own wording and date. **An earlier revision of this document passed the requirement by having no
native code at all.** That is no longer true — a Flutter app ships the engine, so the requirement has
to be met rather than sidestepped.

Measured on 2026-09-13 by parsing, with Python, the ELF program headers of every library in all
three ABIs of `dist/NIVORA-1.0.0.aab` and taking the smallest `p_align` across each library's
`PT_LOAD` segments. **These are the versionCode 4 bundle's figures**, measured after the 20:21 build.
versionCode 3 gave identical values, but its `libapp.so` is a different file, so its figures were not
carried over; they were measured again. The guide's threshold is `2**14` (16384, `0x4000`); a `LOAD`
segment at `2**13` or lower fails:

| Library | min LOAD alignment | |
|---|---|---|
| `arm64-v8a/libapp.so` | 65536 (64 KB) | PASS |
| `arm64-v8a/libdartjni.so` | 16384 (16 KB) | PASS |
| `arm64-v8a/libdatastore_shared_counter.so` | 16384 (16 KB) | PASS |
| `arm64-v8a/libflutter.so` | 65536 (64 KB) | PASS |
| `armeabi-v7a/libapp.so` | 16384 (16 KB) | PASS |
| `armeabi-v7a/libdartjni.so` | 16384 (16 KB) | PASS |
| `armeabi-v7a/libdatastore_shared_counter.so` | 16384 (16 KB) | PASS |
| `armeabi-v7a/libflutter.so` | 65536 (64 KB) | PASS |
| `x86_64/libapp.so` | 65536 (64 KB) | PASS |
| `x86_64/libdartjni.so` | 16384 (16 KB) | PASS |
| `x86_64/libdatastore_shared_counter.so` | 16384 (16 KB) | PASS |
| `x86_64/libflutter.so` | 65536 (64 KB) | PASS |

All twelve clear the 16 KB threshold. The previous table listed the four `arm64-v8a` libraries only.
The requirement is written for 64-bit devices, so `x86_64` counts as much as `arm64-v8a`, and the
32-bit `armeabi-v7a` set is measured as well because it ships in the same bundle. Inside the AAB the
libraries are stored compressed, which is normal for a bundle; the APKs `bundletool` builds from it
store them uncompressed with 16 KB zip alignment, which is the packaging half of the same
requirement.

(`libsqlite3.so` appeared in the 25 August measurement and is
no longer in the build; a dependency stopped bundling it. Re-listing rather than re-stating the
old table is the point of this section.) **Re-run this after any Flutter or plugin upgrade** — a single
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

That block was printed for the versionCode 1 APK. For the versionCode 4 upload, on 2026-09-13,
`keytool -printcert -jarfile dist/NIVORA-1.0.0.aab` printed the certificate SHA-256
`24:23:97:46:89:5A:54:63:86:F1:87:4B:1D:B5:F5:31:3D:02:DA:99:DB:E4:72:F5:45:19:23:58:1F:FB:64:65`,
the same key as the digest above, and the signature gate in `scripts/release.sh` passed on both
versionCode 4 APKs. A signature is a fact about one file: repeat this on any rebuild.

The AAB carries `META-INF/HOSTELPR.RSA` + `.SF` + `MANIFEST.MF` — JAR signing, which is the
correct and only scheme for a bundle. Play re-signs the delivered APKs with its own key.

**This is the check that matters most in the whole document.** Flutter's Gradle template falls
back to the *debug* key when release signing is misconfigured, and it does so silently — the
build succeeds and the artifact is rejected only at upload. `scripts/release.sh` refuses to stage
anything not signed with `CN=HostelPro` precisely because that failure is invisible otherwise.

**After the first upload**, add the SHA-256 of the *Play App Signing* key anywhere the upload
fingerprint is currently used. In Play Console it is under **Protected with Play → Play Store
distribution → Go to Play app signing**, in the **App signing key** section — the path Google's help
page (`support.google.com/googleplay/android-developer/answer/9842756`) gives as of 2026-09-13. This
used to say Console → Setup → App signing, which no longer matches that page. Google re-signs, so the certificate
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

**6.1 — CLEARED. The Edge Functions are deployed.** On 2026-09-13 all eleven are ACTIVE on project
`nimxvgzscbanhtvgnjll`: `sa-create-owner`, `owner-create-staff`, `warden-register-student`,
`razorpay-order`, `razorpay-webhook`, `mobile-auth`, `email-verification`, `complaint-photo`,
`warden-student-credentials`, `storage-erasure` and `push-send` (`push-send` deployed on 2026-09-11). `razorpay-webhook` is the only one with
`verify_jwt: false`, which is correct — Razorpay cannot present a Supabase JWT, so that function
authenticates the caller by HMAC over the raw body instead. Rent has since been paid end to end
with live keys.

**6.2 — Privacy policy URL must be reachable without signing in.** Play fetches it anonymously.
The policy is `/legal/privacy` (`app/legal/privacy/page.tsx`), public because `/legal` is in
`PUBLIC_PATHS` (`lib/supabase/middleware.ts:9-11`). Its version 2026-09-13 text went live on
2026-09-13: commit `4fd41ef` was pushed at 20:44 IST, and signed-out GETs of `/legal/privacy`,
`/legal/account-deletion` and `/legal/terms` then returned 200 and showed version 2026-09-13. The
in-app copy reaches users with versionCode 4, so the Data safety answers that rely on that text go in
together with versionCode 4.

**Note on `assetlinks.json`:** the previous revision listed it as a blocker. It was, for a Trusted
Web Activity, where Digital Asset Links is what stops the app opening in a browser chrome. This is
a native client and does not depend on it. It is required again only if App Links deep-linking is
added later.

---

## 7. One finding worth recording

The `INTERNET` permission was once believed to be missing from the release build, and adding it to
the main manifest was believed to have fixed an app that would not open. **Both beliefs were
wrong.** Seven dependencies already declare `INTERNET`, among them `com.razorpay:standard-core`,
`com.razorpay:core` and the `firebase_messaging` plugin (§2). So the release build always had network. (An earlier
revision said `INTERNET` had come from the Firebase packages "until those were removed". Firebase was
not removed: `firebase_core` and `firebase_messaging` are dependencies at
`nivora_app/pubspec.yaml:85-86`, and the `WAKE_LOCK` and `com.google.android.c2dm.permission.RECEIVE`
rows in §2 come from it.)
The real cause was a routing bug that held the app on its splash screen forever — see the commit
"Fix the real reason the app would not open".

It is recorded here because the merger report is the tool that settles this class of question, and
because a permission you did not declare can still be in your app — which cuts both ways.
