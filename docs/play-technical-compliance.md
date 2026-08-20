# Play technical compliance — independent verification of the release artifact

**Artifact:** `android/app/build/outputs/bundle/release/app-release.aab`
**Verified:** 21 August 2026, on the build workstation.
**Method:** every claim below was read out of the `.aab` itself with `aapt2`, `keytool` and
`apksigner`, or fetched live over the network. Nothing here was taken from
[`play-store.md`](./play-store.md) — that document is a build guide written by the person who made
the artifact, and the point of this one is to check it from the outside.

Companion: [`play-submission-pack.md`](./play-submission-pack.md) — the Console answers.

---

## 0. Verdict first

| # | Requirement | Status |
|---|---|---|
| 1 | Target API level for new submissions (API 36 from 31 Aug 2026) | **PASS** — `targetSdkVersion 36` |
| 2 | Permissions minimal and justified | **PASS** — one real permission (`INTERNET`) |
| 3 | Signing key strength and certificate validity | **PASS** — RSA 2048, valid to 2095-01-30 |
| 4 | Upload-key fingerprint matches live `assetlinks.json` | **PASS** — verified against Google's own API |
| 5 | Signature schemes | **PASS** — AAB is JAR-signed (correct); APK carries v1+v2+v3 |
| 6 | 16 KB page-size compatibility (from 1 Nov 2025) | **PASS** — zero native libraries |
| 7 | Artifact size | **PASS** — 937 KB |
| 8 | **Privacy policy URL reachable without signing in** | **FAIL — BLOCKER, see §8.1** |
| 9 | **`assetlinks.json` covers the Play app-signing key** | **FAIL — BLOCKER after first upload, see §8.2** |

Two blockers. Neither is inside the `.aab`; both will stop the listing anyway.

---

## 1. Tool environment

```
$ "$ANDROID_HOME/build-tools/37.0.0/aapt2.exe" version
Android Asset Packaging Tool (aapt) 2.20-15087165
```

`ANDROID_HOME=C:/Users/shahu/AppData/Local/Android/Sdk`; build-tools 35.0.0, 36.0.0, 36.1.0 and
37.0.0 are installed and 37.0.0 was used throughout. `keytool` is **not on `PATH`** — the `java` on
`PATH` is JDK 26 at `C:/Program Files/Common Files/Oracle/Java/javapath/java`, and that shim
directory has no `keytool`. The working one is the JBR bundled with Android Studio:

```
C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe
```

**`bundletool` is not installed on this machine** and was not downloaded. Everything below was
obtained without it — see §2 for how the bundle's manifest was read.

---

## 2. Reading a manifest out of an `.aab`

`aapt2` cannot open a bundle directly:

```
$ aapt2 dump xmltree app-release.aab --file base/manifest/AndroidManifest.xml
app-release.aab: error: could not identify format of APK.
```

Inside an `.aab` the manifest is **protobuf**, not binary XML, so it has to be repackaged as a
proto-format APK and converted. `zip` is not installed here; `jar` from the JBR does the job:

```sh
unzip -q app-release.aab -d raw
mkdir protoapk && cd raw/base
cp manifest/AndroidManifest.xml resources.pb ../../protoapk/ && cp -r res ../../protoapk/
cd ../../protoapk && jar --create --file ../proto.apk -M .
aapt2 convert --output-format binary -o ../binary.apk ../proto.apk
aapt2 dump badging ../binary.apk
```

Every figure in §3 and §4 comes from that converted copy of the **bundle's own** manifest, so it is
the bundle being measured and not the side-built APK. The APK was then checked separately (§5) and
agrees on every value.

---

## 3. Identity

```
$ aapt2 dump badging binary.apk
package: name='app.hostelpro.twa' versionCode='1' versionName='1.0.0'
  platformBuildVersionName='16' platformBuildVersionCode='36'
  compileSdkVersion='36' compileSdkVersionCodename='16'
minSdkVersion:'23'
targetSdkVersion:'36'
application-label:'HostelPro'
application: label='HostelPro' icon='res/mipmap-anydpi-v26/ic_launcher.xml'
launchable-activity: name='app.hostelpro.twa.LauncherActivity'  label='HostelPro' icon=''
```

| Field | Value |
|---|---|
| `applicationId` | `app.hostelpro.twa` |
| `versionCode` | `1` |
| `versionName` | `1.0.0` |
| `minSdkVersion` | `23` (Android 6.0) |
| `targetSdkVersion` | `36` (Android 16) |
| `compileSdkVersion` | `36` |
| Launcher activity | `app.hostelpro.twa.LauncherActivity` |
| AAB size | **959,564 bytes = 937.1 KiB** |
| AAB SHA-256 | `2b7fba39e3b1192d238a33aba1bc7728b513b5b7d0e505d6644e715b70c2dfa2` |

```
$ stat -c "%s bytes" app-release.aab
959564 bytes
$ sha256sum app-release.aab
2b7fba39e3b1192d238a33aba1bc7728b513b5b7d0e505d6644e715b70c2dfa2 *app-release.aab
```

`applicationId` is permanent once the first build reaches Play. If `app.hostelpro` is wanted instead
of `app.hostelpro.twa`, it must change **before** the first upload, in
`android/app/build.gradle.kts` (`namespace` *and* `applicationId`) and in `package_name` in
`public/.well-known/assetlinks.json`. After the first upload it cannot be changed at all.

### 3.1 targetSdk against Play's current floor — the headline check

Google Play's rule as of today:

> New apps and app updates must target **Android 16 (API level 36)** or higher to be submitted to
> Google Play — **from 31 August 2026**. An extension to 1 November 2026 can be requested.
> ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/11926878))

**This artifact targets API 36. It passes — plainly, and with no extension needed.**

Worth stating precisely, because the timing is unusually tight: **today is 21 August 2026 and the
deadline is 31 August 2026, ten days away.** An artifact built at `targetSdk 35` would be accepted
this week and rejected next week, and a first submission realistically lands on the far side of that
line once the closed-testing calendar in the submission pack is taken into account. This build is on
the right side of it either way, which is the single most valuable thing to be able to say about it.

`minSdkVersion 23` is a floor imposed by `androidbrowserhelper:2.7.3`, not by Play. Play sets no
minimum `minSdk`, so this is a device-reach decision rather than a compliance one.

---

## 4. Permissions

```
$ aapt2 dump permissions binary.apk
package: app.hostelpro.twa
uses-permission: name='android.permission.INTERNET'
permission: app.hostelpro.twa.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='app.hostelpro.twa.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

That is the complete list from the merged manifest of the bundle. Two entries, one of which is not
really a permission at all.

| Permission | Protection | Justified? |
|---|---|---|
| `android.permission.INTERNET` | normal | **Yes.** The app is a Trusted Web Activity; without network access it renders nothing. No runtime prompt, and nothing to disclose to users. |
| `app.hostelpro.twa.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `signature` (`protectionLevel=0x2`) | **Yes.** Auto-generated by `androidx.core` when it registers a non-exported runtime receiver on API 33+. It is namespaced to this app, `signature`-level so only a package signed with the same key can hold it, and it grants access to nothing outside the app. Not shown to users; nothing to declare in Data safety. |

**Nothing else is requested.** Specifically absent, and each absence is load-bearing for the Data
safety answers in the submission pack:

- no `ACCESS_NETWORK_STATE`
- no `POST_NOTIFICATIONS` (no service worker, so there is no web push to delegate)
- no `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`
- no `CAMERA`, no `READ_MEDIA_IMAGES`, no `READ_EXTERNAL_STORAGE` — uploads go through Chrome's file
  picker, which needs no app permission
- no `com.google.android.gms.permission.AD_ID` — so there is no advertising ID to declare
- no `READ_PHONE_STATE`, no `GET_ACCOUNTS`, no `QUERY_ALL_PACKAGES`

`QUERY_ALL_PACKAGES` deserves a note because it is a Play *policy-restricted* permission that TWA
projects sometimes pick up by accident. This one instead declares a narrow `<queries>` element for
`https` VIEW intents, which is the correct, non-restricted way for a TWA to find a browser:

```
E: queries
    E: intent
        E: action   android:name="android.intent.action.VIEW"
        E: category android:name="android.intent.category.BROWSABLE"
        E: data     android:scheme="https"
```

**No policy-restricted or sensitive permission is present, so no permissions declaration form is
required in Console.**

### 4.1 Other manifest facts worth knowing before review

Read from the same converted manifest (`aapt2 dump xmltree`):

- `android:allowBackup=false` and `android:fullBackupContent=false` — no cloud backup of app data.
  Correct for a TWA: there is nothing on-device worth backing up, and it keeps session state out of
  Google's backup.
- `LauncherActivity` is `exported=true` with `launchMode=2` (`singleTask`) and an `autoVerify=true`
  App Links filter for `https://hostelpro-three.vercel.app`. Exported is required — it is the
  launcher — and the deep-link filter is the whole reason the Digital Asset Links check in §6
  matters.
- `DelegationService` is `exported=true` with the
  `android.support.customtabs.trusted.TRUSTED_WEB_ACTIVITY_SERVICE` filter. Required: Chrome binds to
  it across process boundaries. It is Google's own `TrustedWebActivityService` subclass and exposes
  no app logic.
- `ManageDataLauncherActivity` is `exported=false`; both `ContentProvider`s (`FileProvider`,
  `androidx.startup.InitializationProvider`) are `exported=false`.
- `androidx.profileinstaller.ProfileInstallReceiver` is `exported=true` but guarded by
  `android:permission="android.permission.DUMP"` — a signature/privileged permission, so only the
  shell and system can reach it. Standard AndroidX baseline-profile plumbing.
- Screen orientation is pinned `portrait`, matching `orientation: "portrait"` in `app/manifest.ts`.
- No `usesCleartextTraffic` attribute and no network security config, so the API-28+ default applies:
  **cleartext HTTP is blocked.**

---

## 5. Signing

### 5.1 The certificate in the bundle

```
$ keytool -printcert -jarfile app-release.aab
Signer #1:

Certificate #1:
Owner: CN=HostelPro, O=HostelPro, C=IN
Issuer: CN=HostelPro, O=HostelPro, C=IN
Serial number: c1bd66270325e985
Valid from: Thu Aug 20 22:04:39 IST 2026 until: Sun Jan 30 22:04:39 IST 2095
Certificate fingerprints:
	 SHA1:   DA:61:61:66:77:D2:59:8C:42:EF:E1:4C:72:80:E5:9C:48:EB:D2:77
	 SHA256: 24:23:97:46:89:5A:54:63:86:F1:87:4B:1D:B5:F5:31:3D:02:DA:99:DB:E4:72:F5:45:19:23:58:1F:FB:64:65
Signature algorithm name: SHA384withRSA
Subject Public Key Algorithm: 2048-bit RSA key
Version: 3
```

| Check | Result |
|---|---|
| Key algorithm / size | RSA 2048 — meets Play's 2048-bit minimum |
| Signature algorithm | SHA384withRSA |
| Validity end | 2095-01-30 — clears Play's "must remain valid past 22 Oct 2033" rule by ~62 years |
| Self-signed | Yes — normal and expected for an Android upload key |

### 5.2 Signature schemes — and a correction worth making

The bundle's `META-INF` contains exactly three entries:

```
$ unzip -l app-release.aab | grep META-INF
    39132  META-INF/HOSTELPR.SF
     1217  META-INF/HOSTELPR.RSA
    39083  META-INF/MANIFEST.MF
```

That is **JAR signing (v1) and only v1** — and that is correct, not a defect. `apksigner` refuses the
file outright, which is the clearest possible demonstration that an `.aab` is not an APK:

```
$ apksigner verify app-release.aab
Exception in thread "main" com.android.apksig.apk.ApkFormatException: Missing AndroidManifest.xml
```

**APK Signature Schemes v2/v3 are APK-only.** They live in a signing block between the file entries
and the central directory of an APK; an app bundle has no such block and never will. The
`enableV2Signing`/`enableV3Signing` flags in `android/app/build.gradle.kts` are real, but they apply
to APKs — the one `assembleRelease` writes locally, and the split APKs Play generates from the
bundle. So "is the bundle signed v1/v2/v3" has a precise answer: **the bundle is JAR-signed; the APKs
derived from it are v1+v2+v3.** Verified on the side-built APK from the same build:

```
$ apksigner verify -v --print-certs app-release.apk
Verifies
Verified using v1 scheme (JAR signing): true
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Verified using v3.1 scheme (APK Signature Scheme v3.1): false
Verified using v3.2 scheme (APK Signature Scheme v3.2): false
Verified using v4 scheme (APK Signature Scheme v4): false
Number of signers: 1
V3.0 Signer: certificate DN: CN=HostelPro, O=HostelPro, C=IN
V3.0 Signer: certificate SHA-256 digest: 24239746895a546386f1874b1db5f5313d02da99dbe472f5451923581ffb6465
V3.0 Signer: certificate SHA-1 digest: da61616677d2598c42efe14c7280e59c48ebd277
V3.0 Signer: key algorithm: RSA
V3.0 Signer: key size (bits): 2048
```

Same certificate digest as the bundle, so the two artifacts come from one build and one key. v3.1 and
v3.2 are absent because no key rotation has ever been performed — expected for a first release. v4 is
absent because it is an incremental-install optimisation Gradle does not emit by default; it is not a
Play requirement.

`apksigner` also prints roughly thirty `WARNING: ... not protected by signature` lines for
`META-INF/*.version` marker files that AndroidX libraries ship. They are informational, appear in
essentially every AndroidX app, and are not a Play issue.

### 5.3 One thing this key is not

Under Play App Signing — **mandatory for every new app since August 2021**, and unavoidable because
new apps must ship as bundles — the key above is the **upload key**, not the app signing key. Google
generates and holds the real signing key and re-signs every APK it serves. That is §8.2, and it is a
blocker.

---

## 6. Digital Asset Links

The file in the repository and the file on the live site are byte-identical, and both carry the
fingerprint from §5.1:

```
$ curl -sS -w "\nHTTP %{http_code} | content-type: %{content_type}\n" \
    https://hostelpro-three.vercel.app/.well-known/assetlinks.json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "app.hostelpro.twa",
      "sha256_cert_fingerprints": [
        "24:23:97:46:89:5A:54:63:86:F1:87:4B:1D:B5:F5:31:3D:02:DA:99:DB:E4:72:F5:45:19:23:58:1F:FB:64:65"
      ]
    }
  }
]

HTTP 200 | content-type: application/json; charset=utf-8
```

The fingerprint in the file, character for character, equals the one `keytool` printed from the
bundle and the digest `apksigner` printed from the APK. **Match confirmed.**

Google's own resolver agrees:

```
$ curl -sS "https://digitalassetlinks.googleapis.com/v1/assetlinks:check\
?source.web.site=https://hostelpro-three.vercel.app\
&relation=delegate_permission/common.handle_all_urls\
&target.android_app.package_name=app.hostelpro.twa\
&target.android_app.certificate.sha256_fingerprint=24:23:...:64:65"
{
  "linked": true,
  "maxAge": "3599.425251133s"
}
```

`"linked": true`, no error string. The statement resolves, the package name matches and the
certificate matches. **For a build installed over `adb`, the TWA will verify and run with no address
bar.** For a build installed from Play, see §8.2.

---

## 7. 16 KB page-size compatibility

Since 1 November 2025, new submissions targeting Android 15+ devices must support 16 KB memory pages.
The requirement only bites on native code
([Android Developers Blog](https://android-developers.googleblog.com/2025/05/prepare-play-apps-for-devices-with-16kb-page-size.html)).

```
$ unzip -l app-release.aab | grep -c "\.so$"
0
$ aapt2 dump badging app-release.apk | grep native-code
(no output)
```

**Zero native libraries.** The bundle is one `classes.dex` plus resources; the only `uses-feature` is
the implied `android.hardware.faketouch` that every app gets. There is no `.so` to be misaligned, so
this requirement is satisfied by construction and needs no action.

Also checked while in there: `dependenciesInfo { includeInApk = false; includeInBundle = true }` means
`BUNDLE-METADATA/com.android.tools.build.libraries/dependencies.pb` (5,083 bytes) is present, which is
what Play's SDK scanner reads. Omitting it from the bundle triggers a Console warning; it is present.

---

## 8. Blockers

### 8.1 BLOCKER — the privacy policy URL redirects to the login page

Play requires a privacy policy URL that is publicly reachable, **not behind a sign-in**. Right now it
is behind a sign-in. Checked live, signed out:

```
$ curl -sS -o /dev/null -w "HTTP %{http_code}  (redirect: %{redirect_url})\n" \
    https://hostelpro-three.vercel.app/legal/privacy
HTTP 307  (redirect: https://hostelpro-three.vercel.app/login?next=%2Flegal%2Fprivacy)

$ ... /legal/account-deletion
HTTP 307  (redirect: https://hostelpro-three.vercel.app/login?next=%2Flegal%2Faccount-deletion)
```

Both required URLs answer an anonymous request with `307 -> /login`. A reviewer, and Google's
automated crawler, will see exactly this. It is a rejection.

The cause is **not** the middleware source — that is already correct locally:

```
$ grep -n "PUBLIC_PATHS" -A 8 lib/supabase/middleware.ts
9:const PUBLIC_PATHS = [
10-  "/login",
11-  "/legal",
...
```

It is that **the change is not committed, and therefore not deployed**:

```
$ git diff HEAD --stat -- lib/supabase/middleware.ts
 lib/supabase/middleware.ts | 12 +++++++++++-
 1 file changed, 11 insertions(+), 1 deletion(-)
```

Eleven uncommitted lines in the working tree, and production is still running the version without
`/legal`. Proof that it is the middleware and not merely a missing page: if `/legal` were public in
the deployed build, a route that does not exist yet would return **404**, not a redirect to `/login`.

**Fix:** commit and deploy `lib/supabase/middleware.ts` together with the `/legal/privacy` and
`/legal/account-deletion` pages, then re-run the two `curl` commands above **signed out** and confirm
`HTTP 200`. Do not paste either URL into Play Console until that check passes. Note that `app/legal/`
does not exist in the tree at the time of writing — those pages are still outstanding.

### 8.2 BLOCKER (the moment the first upload succeeds) — `assetlinks.json` covers only the upload key

`sha256_cert_fingerprints` has exactly one entry, and it is the upload key from §5.1. Under Play App
Signing — mandatory for this app — the copy users install is signed by **Google's** app signing key,
whose fingerprint is different and is not knowable until after the first successful upload.

The consequence is quiet and easy to miss, because nothing errors. The app installs, launches and
works. It just does it **inside a Custom Tab with a visible address bar**, because Chrome could not
verify the origin. Every internal build installed over `adb` keeps looking perfect, so local testing
cannot catch this.

There is a second consequence that matters more at review time: Play's spam policy rejects bare
webview wrappers, and a TWA is the sanctioned exception *precisely because* Digital Asset Links proves
the publisher owns the site. An unverified TWA looks, to a reviewer, like the thing that policy bans.

**Fix, in order, immediately after the first upload and before promoting to any track real users can
install from:**

1. Play Console → Test and release → Setup → **App integrity** → App signing.
2. Copy the **"App signing key certificate" SHA-256 certificate fingerprint**.
3. Add it as a **second** element of `sha256_cert_fingerprints` in
   `public/.well-known/assetlinks.json`. Keep the upload-key entry — sideloaded builds need it.
4. Deploy the site.
5. Re-run the `assetlinks:check` call from §6 with the new fingerprint and confirm `"linked": true`.
6. Only then promote the release.

---

## 9. Non-blocking observations

| Observation | Why it is worth knowing | Action |
|---|---|---|
| `versionCode = 1` | Correct for a first upload, but Play rejects a re-upload of the same `versionCode`. A submission that has already been *uploaded* burns the number even if it is later rejected. | Bump `versionCode` in `android/app/build.gradle.kts` for every upload, without exception. |
| The TWA has never been executed | No emulator image and no attached device on this workstation, so this is a static verification only. Everything above is what the bytes say; none of it is what a phone did. | Before the closed test: `adb install app-release.apk` on a real device, launch, and confirm **no address bar**. That one observation validates §5, §6 and §8.2 at once. |
| No service worker, so no offline support | With no network the app shows Chrome's offline page. Not a Play requirement, but it is what a reviewer on a poor connection sees, and "the app didn't work" is a common rejection reason. | Consider a minimal offline fallback before submitting. |
| `version-control-info.textproto` says `NO_SUPPORTED_VCS_FOUND` | The bundle carries no git commit stamp, so a future artifact cannot be traced back to a revision. | Cosmetic. Fixable by building from within the git work tree with AGP's VCS info enabled. |
| Certificate DN is `CN=HostelPro, O=HostelPro, C=IN` | Not user-visible, and under Play App Signing not even the certificate devices see. | Fine as is; change to the registered entity name only if preferred. |
| Upload keystore lives at `C:\Users\shahu\.hostelpro-keys\` | Outside the repo, correctly. It is therefore also backed up by nothing. | Copy it somewhere durable and private **before** the first upload. Losing it after Play App Signing is recoverable through an upload-key reset — but the reset issues a new fingerprint, which means redeploying `assetlinks.json` again. |

---

## 10. Reproducing this report

```sh
export ANDROID_HOME=C:/Users/shahu/AppData/Local/Android/Sdk
A="$ANDROID_HOME/build-tools/37.0.0"
KT="C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe"
cd android/app/build/outputs

# identity, size, integrity
stat -c "%s bytes" bundle/release/app-release.aab
sha256sum bundle/release/app-release.aab

# who signed the bundle
"$KT" -printcert -jarfile bundle/release/app-release.aab

# signature schemes (APK only — see §5.2)
"$A/apksigner.bat" verify -v --print-certs apk/release/app-release.apk

# the bundle's own manifest (see §2 for the conversion)
"$A/aapt2.exe" dump badging     binary.apk
"$A/aapt2.exe" dump permissions binary.apk
"$A/aapt2.exe" dump xmltree     binary.apk --file AndroidManifest.xml

# native code present?
unzip -l bundle/release/app-release.aab | grep -c "\.so$"

# the site half
curl -sS https://hostelpro-three.vercel.app/.well-known/assetlinks.json
curl -sS "https://digitalassetlinks.googleapis.com/v1/assetlinks:check?source.web.site=https://hostelpro-three.vercel.app&relation=delegate_permission/common.handle_all_urls&target.android_app.package_name=app.hostelpro.twa&target.android_app.certificate.sha256_fingerprint=<sha256>"

# the two URLs Play will fetch anonymously — must be 200, not 307
for u in /legal/privacy /legal/account-deletion; do
  curl -sS -o /dev/null -w "$u -> HTTP %{http_code}\n" "https://hostelpro-three.vercel.app$u"
done
```

Re-run that last block after **any** deploy that touches `middleware.ts` or its matcher. It is exactly
the kind of thing that breaks without anyone noticing.
