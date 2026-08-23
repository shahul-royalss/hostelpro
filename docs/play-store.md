# Shipping NIVORA to Google Play

NIVORA is a PWA. To put it on Play it is wrapped in a **Trusted Web Activity** (TWA):
a native Android shell whose only job is to launch Chrome full-screen, with no URL bar,
pointed at `https://hostelpro-three.vercel.app/`. There is no second codebase — every
screen, every RLS policy and every deploy is the one you already ship to the web.

Chrome only drops the URL bar if the site proves it owns the app. That proof is
`/.well-known/assetlinks.json`, and it is live and verified against Google's own API — see
[Digital Asset Links](#4-digital-asset-links). One thing there still needs your hand after
the first upload: Play re-signs the app with **its** key, whose fingerprint has to be added
to the same file.

---

## 1. What is in the repository

```
android/                                the Gradle project
  build.gradle.kts                      AGP 8.13.2
  settings.gradle.kts
  gradle.properties                     no machine-specific values - see §2
  gradlew / gradlew.bat / gradle/        Gradle 9.1.0 wrapper
  keystore.properties.example           template for the signing config
  app/
    build.gradle.kts                    applicationId, signing, R8, Java toolchain
    proguard-rules.pro
    src/main/AndroidManifest.xml         the TWA declaration
    src/main/java/app/hostelpro/twa/     LauncherActivity, DelegationService
    src/main/res/                        icons, splash, colours, strings
public/.well-known/assetlinks.json      the site half of the app<->site proof
```

| | |
|---|---|
| applicationId | `app.nivora.twa` |
| versionCode / versionName | `1` / `1.0.0` |
| minSdk | 23 (Android 6.0) |
| targetSdk / compileSdk | 36 (Android 16) |
| TWA library | `com.google.androidbrowserhelper:androidbrowserhelper:2.7.3` (wraps `androidx.browser.trusted`) |
| Signed AAB | `android/app/build/outputs/bundle/release/app-release.aab` — 937 KB |
| Signed APK (sideload/testing) | `android/app/build/outputs/apk/release/app-release.apk` — 644 KB |

`applicationId` is **permanent** once the first build reaches Play — it is the app's
identity in the store and cannot be changed afterwards, only replaced by a brand-new
listing. If you would rather not carry the implementation detail "twa" in it forever,
change it to `app.hostelpro` in `android/app/build.gradle.kts` (`namespace` *and*
`applicationId`) **before** the first upload, and update `package_name` in
`public/.well-known/assetlinks.json` to match.

The wrapper matches `app/manifest.ts`: same name, same `#F6F4EF` theme and background
colour, same `start_url`, same portrait lock, same icon art (`public/icons/icon.svg`
transcribed to a vector so the adaptive launcher icon is sharp at every density).

### What the app is allowed to do

`INTERNET`, and nothing else. No notification permission (the PWA registers no service
worker, so there is no web push to delegate), no storage, no location, no analytics SDK,
no ad ID. The whole APK is one 652 KB dex of Google's TWA support library plus two
subclasses that are empty on purpose — everything the user touches runs inside Chrome's
sandbox, on the origin you already control.

---

## 2. Building it again

**Prerequisites on this workstation** (all already in place):

- Android SDK at `C:\Users\shahu\AppData\Local\Android\Sdk` with platform `android-36`
  and build-tools 36.x. Gradle finds it via `local.properties` or `ANDROID_HOME`; if it
  complains, `export ANDROID_HOME=C:/Users/shahu/AppData/Local/Android/Sdk`.
- A **JDK 21**. The `java` on PATH here is 26, and AGP cannot use it: it shells out to
  `jlink` to build android.jar's system-module image and JDK 26's jlink fails that
  transform outright (`Execution failed for JdkImageTransform`). Rather than making you
  remember a `JAVA_HOME`, `app/build.gradle.kts` declares a Java toolchain of 21 and
  `~/.gradle/gradle.properties` points Gradle at the JDK 21 bundled with Android Studio:

  ```
  org.gradle.java.installations.paths=C:/Program Files/Android/Android Studio/jbr
  ```

  Confirm Gradle can see it with `./gradlew -q javaToolchains`.
- **TLS.** Norton Antivirus terminates every outbound HTTPS connection on this machine
  and re-signs it as `CN=Norton Web/Mail Shield Root`. `curl` and Node cope because they
  read the Windows certificate store (this is the same problem the README documents for
  `NODE_EXTRA_CA_CERTS`); the JVM does not, so Gradle's downloads fail — and Gradle
  reports the failure as *"could not resolve plugin artifact ... not found"*, which sends
  you hunting for a version that does not exist. `~/.gradle/gradle.properties` therefore
  also carries:

  ```
  systemProp.javax.net.ssl.trustStore=C:/Users/shahu/.gradle/norton-aware-cacerts.p12
  systemProp.javax.net.ssl.trustStoreType=pkcs12
  ```

  That store is the JBR's `cacerts` plus the current Norton root. Norton regenerates its
  root periodically; when builds start failing with "not found" again, rebuild it (the
  recipe is in the comments of that same file). Use **forward slashes** — a `.properties`
  file treats `\` as an escape character and will silently mangle a Windows path.

**Build:**

```sh
cd android
./gradlew bundleRelease      # -> app/build/outputs/bundle/release/app-release.aab  (upload this)
./gradlew assembleRelease    # -> app/build/outputs/apk/release/app-release.apk     (sideload this)
```

Play takes the **`.aab`**. The `.apk` is only for testing on a device you can reach with
`adb install`.

**Every upload needs a higher `versionCode`.** Play rejects a re-upload of the same one.
Bump `versionCode` (and usually `versionName`) in `android/app/build.gradle.kts` for each
release.

### Verifying a build

```sh
# who signed the bundle
keytool -printcert -jarfile app/build/outputs/bundle/release/app-release.aab

# full signature check on the APK
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --print-certs \
  app/build/outputs/apk/release/app-release.apk

# what the manifest actually says
"$ANDROID_HOME/build-tools/36.0.0/aapt2" dump badging \
  app/build/outputs/apk/release/app-release.apk
```

The SHA-256 printed by those commands **must** equal the fingerprint in
`public/.well-known/assetlinks.json`. If they diverge, the TWA silently degrades to a
Custom Tab with a visible address bar — the app still works, it just stops looking like an
app. That mismatch is the single most common TWA failure, so treat it as a release check.

If the signing material cannot be found the build **fails before writing anything**:

```
Release signing material not found - refusing to build an unsigned release.
```

That is deliberate. An unsigned `.aab` sitting at the expected path looks exactly like a
good build until Play rejects it hours later.

---

## 3. The signing key

```
C:\Users\shahu\.hostelpro-keys\
  hostelpro-upload.p12       PKCS#12, alias "hostelpro-upload", RSA 2048, valid to 2095-01-30
  keystore.properties        storeFile / storeType / keyAlias / storePassword / keyPassword
```

Both files are **outside the repository on purpose**. A keystore inside the working tree
is one `git add -A` away from being public forever, and one `git clean -xdf` away from
being gone forever. `android/.gitignore` and the root `.gitignore` also block
`keystore.properties`, `*.jks`, `*.p12` and `*.keystore` as a second line of defence, but
the safest copy is the one that never exists in the tree.

`android/app/build.gradle.kts` resolves the signing material in this order, first hit wins:

1. environment variables — `HOSTELPRO_KEYSTORE_FILE`, `HOSTELPRO_KEYSTORE_PASSWORD`,
   `HOSTELPRO_KEY_ALIAS`, `HOSTELPRO_KEY_PASSWORD`, `HOSTELPRO_KEYSTORE_TYPE`.
   **This is what CI should use** — GitHub Actions secrets, with the keystore itself
   restored from a base64 secret into a temp path.
2. the file named by `HOSTELPRO_KEYSTORE_PROPERTIES`
3. `~/.hostelpro-keys/keystore.properties` (the local default)

### Back it up now, before the first upload

**Copy `C:\Users\shahu\.hostelpro-keys\` somewhere durable and private today.** A password
manager attachment, an encrypted archive in another cloud account — anywhere that survives
this laptop dying. It is not in the repo, so nothing else is backing it up.

What losing it costs depends on a choice you make at upload time:

- **Play App Signing enabled** (the default, and what you should do). Google generates and
  holds the real *app signing key*; your `hostelpro-upload.p12` is only the *upload key*
  that authenticates you to Play. Lose it and you are not dead: you can request an upload
  key reset through Play Console support. But the reset issues a **new key with a new
  SHA-256**, so you must regenerate and redeploy `assetlinks.json` or every installed copy
  of the app loses its verification and grows a URL bar.
- **Play App Signing declined**, i.e. you upload your own app signing key. Then this file
  *is* the app's identity. Lose it and no one — not you, not Google — can ever publish an
  update to this listing again. The only remedy is a new listing with a new package name,
  and every existing user has to find and install it manually.

Leaking it is the mirror image: anyone holding the keystore and its password can sign a
package that Android accepts as an in-place update to NIVORA.

To create a replacement (new key = new fingerprint = `assetlinks.json` must be updated):

```sh
keytool -genkeypair \
  -keystore C:/Users/shahu/.hostelpro-keys/hostelpro-upload.p12 -storetype PKCS12 \
  -alias hostelpro-upload -keyalg RSA -keysize 2048 -validity 25000 \
  -dname "CN=NIVORA, O=NIVORA, C=IN"
```

Play requires the certificate to stay valid past 22 October 2033; `-validity 25000` (about
68 years) clears that with room to spare. The DN is not shown to users — under Play App
Signing it is not even the certificate users' devices see — so `O=NIVORA` is fine, but
change it to your registered entity name if you prefer.

---

## 4. Digital Asset Links

`public/.well-known/assetlinks.json` exists and carries the real fingerprint of the key
above:

```json
[{ "relation": ["delegate_permission/common.handle_all_urls"],
   "target": { "namespace": "android_app",
               "package_name": "app.nivora.twa",
               "sha256_cert_fingerprints": ["24:23:97:...:64:65"] } }]
```

Next.js serves anything under `public/` from the site root, so the file lands at
`https://hostelpro-three.vercel.app/.well-known/assetlinks.json`. That is not enough on its
own: middleware runs on every path it is not explicitly told to skip, and it was answering
this URL with `307 -> /login?next=%2F.well-known%2Fassetlinks.json`. Google's crawler and
Chrome both fetch it anonymously, so a redirect to a login page is not a statement file —
verification just fails, silently, and the app grows a URL bar with no error anywhere to
explain it.

`middleware.ts` therefore excludes `.well-known/` from its matcher, alongside `icons/` and
`manifest.webmanifest`:

```
"/((?!_next/static/|_next/image/|favicon\\.ico$|icons/|\\.well-known/|manifest\\.webmanifest$|robots\\.txt$).*)",
```

That is a path **prefix**, not the extension pattern the comment in that file warns
against, so it cannot swallow an application route: nothing lives under `/.well-known/`,
and RFC 8615 reserves the prefix for exactly this kind of public metadata.

### Verified live

```sh
$ curl -sSI https://hostelpro-three.vercel.app/.well-known/assetlinks.json
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8

$ curl -sS "https://digitalassetlinks.googleapis.com/v1/statements:list\
?source.web.site=https://hostelpro-three.vercel.app\
&relation=delegate_permission/common.handle_all_urls"
{ "statements": [ { "source": { "web": { "site": "https://hostelpro-three.vercel.app." } },
    "relation": "delegate_permission/common.handle_all_urls",
    "target": { "androidApp": { "packageName": "app.nivora.twa",
      "certificate": { "sha256Fingerprint": "24:23:97:...:64:65" } } } } ] }
```

Google resolves the statement and reports no errors, with the package name and fingerprint
matching the signed build. Re-run both commands after any deploy that touches middleware or
the matcher — this is exactly the kind of thing that breaks without anyone noticing.

On a device, install the APK and launch it: **no address bar means verification passed.**
An address bar means it failed — check the fingerprint first.

### One more fingerprint, after the first upload

If you accept Play App Signing (you should), the app your users install is signed by
**Google's** key, not by `hostelpro-upload.p12`. The fingerprint currently in the file only
covers builds you install yourself over `adb`.

So, immediately after the first successful upload:

1. Play Console → your app → **Test and release → Setup → App integrity → App signing**.
2. Copy the **"App signing key certificate" SHA-256 certificate fingerprint**.
3. Add it as a second entry in the `sha256_cert_fingerprints` array — keep the upload-key
   one, so sideloaded test builds keep verifying too.
4. Redeploy the site *before* promoting the release to any track real users can install
   from.

---

## 5. What only you can do, in Play Console

### Account

- **US$25, one time, non-refundable**, to register a Google Play developer account. It is
  per Google account, not per app.
- Identity verification (a government ID and, for organisation accounts, a D-U-N-S number)
  now happens up front and can take days. Start it early.
- If you register as an **individual** rather than an organisation, Google additionally
  requires a **closed test with at least 12 testers opted in continuously for 14 days**
  before you may apply for production access. Plan the calendar around it. Verify the
  current rule in Console before you commit — Google changes it.

### Privacy policy — a hard blocker today

Play requires a privacy policy URL for every app, publicly reachable, **not behind a
login**. This repo has no `/privacy` route at all, so one has to be written and shipped.

Note the same trap as `assetlinks.json`: a new `app/privacy/page.tsx` would be redirected
to `/login` by middleware unless `/privacy` is added to `PUBLIC_PATHS` in
`lib/supabase/middleware.ts`. Test the URL with `curl` from a signed-out client before
pasting it into Console.

The policy has to name what §5 below declares: names, phone numbers, addresses, ID-proof
images, photographs and payment records of residents; that they are stored in Supabase
(Postgres + private object storage) and served from Vercel; that hostel staff of the same
tenant can see them; retention; and how a person asks for deletion.

### Data safety form

Answer it from the schema, not from memory. `db/schema.sql` is the source of truth. For
every row below: **collected = yes, shared with third parties = no** (Supabase and Vercel
are processors, not recipients), **processed ephemerally = no**, **required = yes**,
**purpose = App functionality** (add *Account management* for the identity rows).

| Play category | Data type | Where it comes from |
|---|---|---|
| Personal info | Name | `students.name`, `students.guardian_name`, `users.name` |
| Personal info | Email address | login identity in Supabase Auth |
| Personal info | Phone number | `students.phone`, `students.guardian_phone` |
| Personal info | Address | `students.address` |
| Personal info | User IDs | Supabase auth uid, role, hostel id |
| Photos and videos | Photos | `students.photo_url`, `students.id_proof_url`, `fee_payments.receipt_url` — resident photographs, **ID-proof scans** and payment receipts, in a private bucket |
| Financial info | Purchase history | `fee_payments` — amount, date, and a `cash`/`upi`/`bank` mode label |
| App activity | Other user-generated content | complaint text, complaint events, leave requests, notices |

**Do not tick "User payment info."** That type means card or bank account numbers, and the
app stores none: `payment_mode` is a three-value enum recording how an offline payment was
made. Ticking it invites a review question you cannot answer with the schema.

Security practices section:

- *Data is encrypted in transit* — **Yes**. TLS to Vercel, TLS to Supabase, HSTS and a
  nonce-based CSP set in middleware.
- *Users can request that their data be deleted* — answer honestly. There is currently **no
  self-service deletion path** in the app; deletion happens when a hostel owner deletes the
  record. Play separately requires apps with accounts to publish a **web URL where a user
  can request account and data deletion**. NIVORA has no public sign-up (accounts are
  provisioned by an owner or manager), which is a mitigating argument, but you will still
  need that URL and a stated process. Build it into the privacy policy page.
- *Independent security review* — No. (`SECURITY.md` is an internal review, not a
  third-party audit; claiming otherwise in Console is a misrepresentation.)
- *Committed to Play Families Policy* — No. This is not a children's app.

### Other declarations

- **Content rating**: complete the IARC questionnaire. NIVORA is a business/utility app
  with no violence, no gambling, no sexual content — expect Everyone / PEGI 3. Answer
  "yes" where it asks whether users can exchange content or communicate: complaints,
  notices and leave requests move between residents and staff, even though they never leave
  the tenant.
- **Ads**: no. There is no ad SDK and no advertising ID.
- **Financial features**: no. The app records payments that happened elsewhere; it does not
  take, hold or move money.
- **Target API level**: `targetSdk = 36` satisfies the current requirement. Play raises the
  floor every August — expect to bump `compileSdk`/`targetSdk` and re-upload each year, or
  the listing stops accepting updates and eventually stops being served to new devices.
- **Store listing assets** — none of these exist yet and Play will not let you publish
  without them:
  - app icon, 512×512 PNG with alpha → `public/icons/icon-512.png` is exactly this
  - feature graphic, 1024×500 → must be designed
  - at least 2 phone screenshots (16:9 or 9:16, 320–3840 px on each side); tablet
    screenshots too if you list tablet support
  - short description ≤ 80 characters, full description ≤ 4000
- **Minimum functionality / spam policy**: Play rejects apps that are bare webview
  wrappers. A TWA is the sanctioned exception *because* it proves ownership of the site
  through Digital Asset Links and runs in a real browser. Which is another reason §4 is not
  optional — an unverified TWA looks to a reviewer exactly like the thing the policy bans.

---

## 6. Known gaps

Things this setup does **not** do, so nobody discovers them at review time:

- **The TWA has never been run.** There is no emulator image and no attached device on this
  machine (`emulator -list-avds` is empty, `adb devices` shows none), so the build was
  verified statically — signature, merged manifest, packaged resources — and the site side
  of §4 was verified against Google's live API, but the two have never been put together.
  First real test: `adb install app-release.apk` on a phone, launch it, confirm there is no
  address bar and that the splash screen and launcher icon look right.
- **No offline support.** The PWA registers no service worker, so with no network the app
  shows Chrome's offline page. Not a Play blocker, but it is what a reviewer on a bad
  connection will see.
- **No web push.** Same reason. If a service worker is ever added, notification delegation
  needs `POST_NOTIFICATIONS` in the manifest and the runtime permission request; the
  `DelegationService` that Chrome binds to is already in place.
- **`assetlinks.json` carries one fingerprint.** The upload key only. See the end of §4.
- **No CI job builds the Android app.** `.github/workflows/security.yml` covers the web
  app. Wiring the AAB into CI means putting the keystore in secrets — worth doing only
  once releases are frequent enough to be worth the exposure.
