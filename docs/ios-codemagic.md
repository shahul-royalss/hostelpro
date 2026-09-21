# iOS: building on Codemagic and testing through TestFlight

The iOS app is built in the cloud by Codemagic from [`codemagic.yaml`](../codemagic.yaml) and
uploaded to TestFlight. This page is the one-time setup, then what a normal build looks like.

## Why it works this way

**An iOS build needs a Mac.** Xcode compiles and signs iOS apps and runs only on macOS. The build
machine for this repository is Windows, and `flutter build ipa` refuses to run there. Codemagic
rents the Mac by the minute.

**An .ipa cannot simply be sent to someone.** This is the part that differs most from Android. An
APK installs on any phone that allows it. An iPhone installs only apps Apple has signed for a known
route:

| Route | How a tester installs | Limits |
|---|---|---|
| **TestFlight** (used here) | An email invite, then Apple's TestFlight app, then Install | Up to 10,000 external testers. The first build for external testers gets a short Beta App Review |
| Ad Hoc | You collect each tester's device UDID first, then build an .ipa signed for exactly those devices | 100 devices per device type per year; every new tester means a rebuild |

A free Apple ID only installs to a phone plugged into your own Mac, and the app stops opening after
seven days. That is not a way to reach testers.

TestFlight is the iOS equivalent of the Play closed test.

## One-time setup

Do these in order. Steps 1 to 3 are on Apple's side and need the account holder; nothing in the
repository can do them.

### 1. Join the Apple Developer Program

[developer.apple.com/programs](https://developer.apple.com/programs/) → Enroll, with the Apple ID
that should own the app. It is a yearly fee. Enrolment can take a day or two to be approved.

### 2. Create the app in App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → Apps → **+** → New App.

- **Platform:** iOS
- **Name:** Nivora
- **Bundle ID:** `com.nivorasr.app`. If it is not in the list, register it first at
  developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs,
  explicit, exactly `com.nivorasr.app`. It must match `PRODUCT_BUNDLE_IDENTIFIER` in
  `nivora_app/ios/Runner.xcodeproj/project.pbxproj` and the Android `applicationId`.
- **SKU:** anything unique to you, for example `nivora-ios`.

Afterwards, App Information shows the app's numeric **Apple ID**. Keep it for step 5.

### 3. Create an App Store Connect API key

App Store Connect → Users and Access → **Integrations** → App Store Connect API → **+**.

- **Name:** anything, for example `Codemagic`
- **Access:** **App Manager**

Download the `.p8` file. **Apple lets you download it once.** Note the **Issuer ID** and the **Key
ID** shown on the same page.

The `.p8` is a secret. It goes into Codemagic's integration settings in the next step and nowhere
else: not into this repository, not into chat, not into a screenshot.

### 4. Connect Codemagic

1. [codemagic.io](https://codemagic.io) → sign in with the GitHub account that owns
   `shahul-royalss/hostelpro`, and add that repository as an app.
2. Team settings → Integrations → **Developer Portal** → Connect. Enter the Issuer ID, the Key ID,
   and upload the `.p8`.
3. Name the key exactly **`Nivora App Store Connect`**. `codemagic.yaml` refers to it by that name,
   character for character, and a build fails at the signing step if the two differ.

Codemagic creates the distribution certificate and the provisioning profile itself, through that
key, on the first build. There is nothing to export from a Mac.

### 5. Optional: give Codemagic the app's Apple ID

In the Codemagic app → Environment variables, add `APP_STORE_APPLE_ID` with the numeric Apple ID
from step 2. Without it, builds are numbered from Codemagic's own counter, which works. With it,
the build also asks TestFlight for its latest number and goes one above, which keeps working even
if the app is ever removed from Codemagic and added again.

## Running a build

Codemagic → the app → **Start new build** → branch `main` → one of two workflows:

- **iOS to TestFlight** uploads to TestFlight, and testers install from an invite.
- **iOS ad hoc .ipa (share the file)** produces an .ipa to download and send yourself. It installs
  only on iPhones registered in advance; see [Sharing the .ipa file](#sharing-the-ipa-file-ad-hoc).
- **iOS unsigned .ipa (sideload, no Apple account)** needs no paid account and runs on Codemagic's
  free plan. Each person has to sign and install it themselves; see
  [No paid Apple account](#no-paid-apple-account).

The first two run exactly the same build steps and differ only in how the app is signed and where it
goes. The third skips signing.

Builds never start on their own. Every build spends macOS minutes, and a docs commit should not.

The five steps, and what failure in each one usually means:

| Step | If it fails |
|---|---|
| Flutter version and packages | A package cannot be resolved. Check `pubspec.lock` is committed and current |
| Apply code signing | The integration name does not match, the API key lacks App Manager, or the bundle ID is not registered |
| Install CocoaPods | The first real test of the committed `ios/Podfile`. Only Razorpay goes through CocoaPods (see below), so a failure here is almost always the `razorpay-pod` pin. The log names the line |
| Build the .ipa | An Xcode compile or signing error. The full log is kept as an artifact under `/tmp/xcodebuild_logs/` |
| Report Razorpay's privacy-sensitive API use | Never fails. It prints what Razorpay's binaries call; read it on the first build (see [Privacy manifest](#privacy-manifest-the-one-thing-the-first-upload-decides)) |

**Two lines to look for in the first build log.** Search it for `PERMISSION_CAMERA`: it must have
resolved to `1`, or the camera will not work on the phone (see the camera item below). And read the
output of the last step.

A successful build uploads to TestFlight. Apple then **processes** it, usually within half an hour,
and emails the account holder when it is ready.

## Getting it onto testers' iPhones

**Internal testers** are people on your App Store Connect team (Users and Access). They can install
as soon as processing finishes, with no review. Up to 100.

**External testers** are anyone else, by email address, up to 10,000:

1. App Store Connect → the app → TestFlight → **External Testing** → create a group.
2. Add the build to the group. The first build goes through a short Beta App Review, usually about a
   day. It asks for a demo login, so give it the same accounts the Play reviewers get
   ([`play-console-submission.md`](play-console-submission.md), App access). Later builds usually go
   straight through.
3. Add testers by email. Each gets an invitation, installs the TestFlight app from the App Store,
   and taps Install.

A TestFlight build expires 90 days after upload. Upload a new one before then.


## Sharing the .ipa file (ad hoc)

For sending a file instead of an invitation. It works, with one condition Apple does not waive:
**the .ipa installs only on iPhones registered in your Apple Developer account before it is
built.** Up to 100 iPhones a year. On any other iPhone it refuses to install, and no build setting
changes that.

### 1. Get each person's UDID

The UDID is the iPhone's device identifier. It is not the serial number, and Settings does not
show it.

- **With a cable, the first-party way:** connect the iPhone to a Windows PC running Apple's Apple
  Devices app (or iTunes), open the device, and click the serial number until it changes to the
  UDID. On a Mac, Finder does the same.
- Websites can read it by having the person install a configuration profile on their phone. They
  work, but it means asking someone to install a profile from a third party, so prefer the cable
  where you can.

### 2. Register the phones

developer.apple.com → Certificates, Identifiers & Profiles → **Devices** → **+**. One entry per
iPhone: a name you will recognise, and its UDID. Each registration counts against the 100 for the
membership year, even if you delete it later.

### 3. Build

Codemagic → Start new build → workflow **iOS ad hoc .ipa (share the file)**. Nothing is uploaded
to Apple. When it finishes, the .ipa is listed under the build's **Artifacts**; download it.

### 4. Get it onto the phones

Tapping an .ipa on an iPhone does not install it. Use one of these:

- **An install link.** Upload the .ipa to an ad hoc distribution service. Diawi is the common one,
  and Firebase App Distribution also accepts iOS ad hoc builds (this app already has a Firebase
  project). The person opens the link **in Safari** and taps Install. Either way you are handing the
  app file to that service.
- **A Mac and a cable.** In Finder, select the iPhone and drag the .ipa onto it, or use Apple
  Configurator.

### Adding someone later

Register their UDID, build again, and send the new .ipa. The old file keeps working on the phones
it was built for. If the newly registered phone still refuses to install, Codemagic reused an ad
hoc profile made before that phone was added: delete the ad hoc profile for `com.nivorasr.app`
under **Profiles** in the Developer portal and build once more, so a fresh one includes every
device.

### How long it keeps working

Until its provisioning profile expires, a year after it was made, or until the distribution
certificate is revoked. Then build and send again.

### Ad hoc or TestFlight

| | Ad hoc: a file | TestFlight: an invitation |
|---|---|---|
| Device IDs collected first | Yes, for every phone | No |
| How many people | 100 iPhones a year | 10,000 |
| When someone new joins | Register, rebuild, resend | Add their email address |
| Apple review | None | The first build for external testers, about a day |
| How long a build lasts | A year | 90 days |

Ad hoc suits a handful of phones you know in advance: your own, and a few owners you work with. For
more than that, TestFlight is less work for you and for them.

## No paid Apple account

**Without the Apple Developer Program, no .ipa installs on an iPhone the normal way.** Tapping it
does nothing, and there is no free signing that lets you send one file to many people. That is
Apple's gate, not a build setting. There are two free routes that do work.

Codemagic's free plan includes 500 macOS minutes a month, and an iOS build takes roughly 15 to 25
of them, so building costs nothing on either route.

### Option 1, recommended: the web app on the Home Screen

The website, `https://hostelpro-three.vercel.app`, is already set up to install on an iPhone: its
manifest opens it full screen, and it carries Apple's home-screen tags and a 180×180 home-screen
icon. It has every role: owner, manager, warden, resident and super admin. Same accounts, same
data, same Supabase backend as the app.

On the iPhone, in **Safari** (Chrome on iPhone cannot do this):

1. Open `https://hostelpro-three.vercel.app` and sign in.
2. Tap **Share**, then **Add to Home Screen**, then **Add**.
3. A NIVORA icon appears on the Home Screen. It opens full screen, without Safari's address bar.

Free for any number of people, with no expiry and no device IDs. A change reaches everyone the
moment the website is deployed, and nobody installs an update.

Be clear with yourself about what it is: the website's own interface, not the Flutter app. It looks
and behaves like the website, and rent is paid through Razorpay's web checkout.

### Option 2: send an unsigned .ipa, and each person sideloads it

This is the only free way to put the actual Flutter app on someone else's iPhone. Run the
**iOS unsigned .ipa (sideload, no Apple account)** workflow and download the .ipa from the build's
Artifacts. Each person then installs it themselves:

1. On **their own computer** (Windows or Mac), install a sideloading tool: Sideloadly or AltStore.
2. Connect the iPhone by cable, open the tool, and give it the .ipa.
3. Sign in with **their own** Apple ID when the tool asks. The tool uses it to sign the app for
   that one phone. This is a free Apple ID, not a developer account.
4. On the iPhone: Settings → General → **VPN & Device Management** → tap their Apple ID →
   **Trust**.
5. On iOS 16 and later, also turn on Settings → Privacy & Security → **Developer Mode**, and restart
   when asked. Apps signed this way will not open without it.

The limits come from Apple's free signing, and they are why this is a stopgap:

- **The app stops opening 7 days after it was signed.** They repeat the install to renew it. AltStore
  can renew automatically, but only while its helper runs on their computer on the same Wi-Fi.
- A free Apple ID can have at most **3** sideloaded apps active on a device.
- Every person needs a computer and has to do all of the above themselves.

One caution to pass on: these tools ask for the person's Apple ID password to do the signing.
Someone uneasy about typing their main Apple ID into a third-party tool can create a second, free
Apple ID just for this.

### Which to use

For real users, residents and wardens who open the app every day, use **Option 1**. Asking them to
reinstall through a computer every week will not last. Option 2 suits you testing the actual app on
your own iPhone, or one or two people who are comfortable with it. When the app earns enough to pay
for the Apple Developer Program, TestFlight replaces both.

## What was fixed so the first build does not break on a phone

Found by reading each native plugin's own source against this project before any iOS build
existed. Every change has a comment at the site saying why it is there.

| Failure it prevents | Fix | Where |
|---|---|---|
| **The app is killed** when a resident saves a receipt | `NSPhotoLibraryAddUsageDescription` | `ios/Runner/Info.plist` |
| Flutter's logo on the home screen, and an App Review rejection | The 15 placeholder icons replaced by the Nivora master, `public/brand/logo-square-1024.png` (1024×1024, RGB, no alpha) | `ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| Every TestFlight build held at "Missing Compliance" until answered by hand | `ITSAppUsesNonExemptEncryption` = false | `Info.plist` |
| No UPI app tiles (GPay, PhonePe, Paytm) in checkout | `LSApplicationQueriesSchemes`, Razorpay's own list of 23 | `Info.plist` |
| The verification link landing on "That page has moved" | `FlutterDeepLinkingEnabled` = false | `Info.plist` |
| A notification arriving while the app is open never showing | Notification center delegate set before `super` | `ios/Runner/AppDelegate.swift` |
| Razorpay's plugin failing to compile against an old SDK | `pod 'razorpay-pod', '~> 1.5.8'` | `ios/Podfile` |
| The camera-denied message sending iPhone users to an Android screen | iOS wording, naming the iOS 18 path and the older one | `lib/data/capture.dart` |
| A white flash on every cold start | Launch screen ground `#EEF0F8`, the same as Android's | `ios/Runner/Base.lproj/LaunchScreen.storyboard` |

**The receipt crash is the one that mattered most.** The receipt is shared as a PNG, so iOS offers
"Save Image" in the share sheet, and the receipt screen tells residents to "save it to your phone
from the same menu". Saving writes to Photos, which needs its own usage string, separate from the
one for reading the library. Without it iOS ends the process.

### The camera depends on Info.plist, not on the Podfile

This is easy to get wrong, and an earlier version of this page did.

Flutter 3.47.1 builds iOS plugins with **Swift Package Manager** by default, and
`Runner.xcodeproj` is already wired for it. Every plugin in this app ships a `Package.swift` except
`razorpay_flutter`, so everything except Razorpay builds through SPM, and the Podfile exists only
for Razorpay.

Under SPM, `permission_handler_apple` switches a permission on by itself when the matching
`NS*UsageDescription` key is in `Info.plist`. `NSCameraUsageDescription` is there, so **the camera
works because of Info.plist.** Do not remove that key.

Under CocoaPods it is the other way round: nothing reads Info.plist, every permission is compiled
out unless a `PERMISSION_*` macro turns it on, and the camera check answers "permanently denied"
without ever showing a dialog. The Podfile's `PERMISSION_CAMERA=1` block is the fallback for that
case, if SPM is ever turned off. On today's build it does nothing.

Two ways the SPM detection can silently fail, both from the plugin's README:

- **An Archive started from the Xcode window.** Xcode.app builds run with `/` as their working
  directory, discovery finds no Info.plist, and every permission is compiled out. Command-line
  builds are fine, and `codemagic.yaml` uses `flutter build ipa`. To archive from Xcode anyway, set
  `PERMISSION_HANDLER_INFO_PLIST` to the absolute path of `ios/Runner/Info.plist` and clear
  DerivedData first.
- **Stale caches.** The package manifest is not re-evaluated when Info.plist changes. Irrelevant on
  Codemagic, where every build starts clean; on a Mac, clear DerivedData after editing usage keys.

`codemagic.yaml` sets `PERMISSION_HANDLER_VERBOSE=1`, so the build log prints the Info.plist it
found and the macros it resolved. **Search the log for `PERMISSION_CAMERA` on the first build.**

### Already correct before this work

- `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` in Info.plist. Without them iOS
  terminates the app the moment a picker opens, and under SPM the camera key is also what switches
  the camera permission on.
- The `com.nivorasr.app` URL scheme, which the email verification link returns on.
- Share sheets on iPad. `UIActivityViewController` needs a popover anchor there, and share_plus
  13.3.0 handles it.

## Privacy manifest: the one thing the first upload decides

Apple refuses an upload (`ITMS-91053`) when a binary calls a "required reason" API, such as
`UserDefaults` or file timestamps, without a declared reason. Flutter's engine and every plugin
here ship their own `PrivacyInfo.xcprivacy`, and so does `RazorpayStandard`. But
`Razorpay.framework` and `RazorpayCore.framework` ship none, and whether they call such an API
cannot be read from source, because they arrive as compiled binaries.

So the app has no privacy manifest of its own yet, deliberately. Adding one means editing
`project.pbxproj` by hand, which a Windows machine cannot validate, and a malformed project file
breaks every build. The first build answers the question instead:

1. The last Codemagic step prints, for each Razorpay framework, which required-reason symbols it
   uses and whether it ships a manifest.
2. If Apple accepts the upload, nothing more is needed.
3. If Apple emails `ITMS-91053`, the email names the exact API categories. Add an app-level
   `ios/Runner/PrivacyInfo.xcprivacy` declaring each one (`UserDefaults` CA92.1, `SystemBootTime`
   35F9.1, `FileTimestamp` C617.1, `DiskSpace` E174.1 are the reasons that fit this app), and add it
   to the Runner target's Copy Bundle Resources. On a Mac: Xcode, File, New, File, App Privacy,
   target Runner.

## Push notifications on iOS: off, and verified to stay off safely

Firebase is configured for Android only; there is no `GoogleService-Info.plist` in the iOS app.
This was checked against the native source, not assumed:

- `firebase_core` 4.14.0 calls `FirebaseApp.configure()` only after confirming the config file
  exists, and its own comment says the guard is there because `configure()` would otherwise crash.
  With no file, Dart receives an ordinary exception, and `lib/core/notify/push_service.dart`
  catches it and turns push off.
- `firebase_messaging` 16.6.0's launch-time setup is safe with no Firebase app. Expect a harmless
  "default Firebase app has not yet been configured" line in the device log on each launch.
- The AppDelegate change above does not upset it: firebase_messaging sees a delegate that already
  forwards to plugins and chains onto it rather than replacing it.

App Store Connect may email an `ITMS-90078` "Missing Push Notification Entitlement" warning. It
does not block the upload. Ignore it until push is turned on.

**Turning push on for iOS later**, in this order:

1. In Firebase project `nivorapg`, the same one `android/app/google-services.json` and the
   `push-send` service account use, add an iOS app with bundle ID `com.nivorasr.app`. A different
   project makes `push-send` treat every iOS token as dead (`SENDER_ID_MISMATCH`) and delete it.
2. Add its `GoogleService-Info.plist` to the Runner target.
3. Apple Developer, Keys: create a key with APNs, and upload it to Firebase, Cloud Messaging, for
   the iOS app.
4. Enable Push Notifications on the `com.nivorasr.app` App ID **first**, then add the Push
   Notifications capability and the remote-notification background mode to the Runner target.
   Adding the entitlement before the App ID allows it makes Codemagic's signing fail.
5. Two changes in `push_service.dart`, which only matter once push is on:
   - On iOS, `getToken()` throws if the APNs token has not arrived yet, and today that one throw
     skips attaching every listener for the session. Attach the `onTokenRefresh` and `onMessage`
     listeners before registering the token, and wait for `getAPNSToken()` before `getToken()`.
   - Make foreground banners deterministic: on iOS call
     `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)` and let
     iOS draw the banner, instead of also drawing a local notification. Today both plugins answer
     iOS for the same notification, and which answer wins can only be seen on a device.

## Before an App Store release

None of this is needed for TestFlight. All of it is needed before submitting to the App Store.

- **App Privacy** in App Store Connect: declare the same data as the Play Data safety form
  ([`data-safety.md`](data-safety.md)): contact info, user content (photos), identifiers (user ID,
  device ID) and purchases, all linked to the user, none used for tracking. Add the privacy policy
  URL.
- **The in-app privacy policy says Razorpay's checkout runs inside the app "on Android".** It runs
  inside the app on iOS too, and probes UPI apps once the schemes above are listed. The policy text
  is versioned and consent-gated, so correcting it means a new legal version, not a quiet edit.
- **App Review sign-in:** the same accounts the Play reviewers get, including the owner's two-step
  setup key. Keep the Demo PG email-verification exemption in place until review is approved.

## Known issues, deliberately not fixed here

- **The Pay button can stay on "Opening…".** `razorpay_flutter`'s `open()` is declared `async void`,
  so an error from the native side escapes the try/catch in `pay_rent.dart`, the result never
  completes, and the button stays disabled until the screen is rebuilt. It happens only if the
  native plugin fails to register, and on Android too. The fix is to run `open()` inside
  `runZonedGuarded`. It is left for its own change because it is the payment path.
- **Android has the same deep-link double delivery.** The manifest does not set
  `flutter_deeplinking_enabled` to false either, so the verification link also reaches the router
  there. Left alone while the Android release is in its closed test.
- **The launch image is a transparent 1×1 placeholder.** Flutter prints a warning about it at build
  time. It is harmless: the launch screen shows the matched ground colour.

## First TestFlight install: what to check on a real iPhone

Everything above was concluded from source. These confirm it on a device.

1. The home-screen icon is the Nivora mark, and a cold start shows no white flash.
2. As a warden, register a resident and tap **Take photo**. The camera permission dialog must
   appear. If it does not, `PERMISSION_CAMERA` did not resolve; check the build log. Tap
   **Don't Allow** once: the message must name Settings, Apps, Nivora, Camera.
3. As a resident, open a receipt, **Share**, **Save Image**. A Photos permission prompt appears
   and the app stays open.
4. On a hostel with Razorpay linked, tap **Pay**: installed UPI apps appear as tiles.
5. Tap an email verification link in Mail. Nivora opens, and it does not show "That page has
   moved".
6. On an iPad, share a receipt: the share sheet opens as a popover.
