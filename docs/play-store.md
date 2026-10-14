# Play Console obligations for Apnivaas

> This file used to describe the web-wrapper (TWA) build. That build and its `android/` project
> were removed from the repository on 2026-10-14, and so were the sections about them. What is
> left is §5, the Play Console obligations, which apply to the native app.
>
> For the submission itself, use:
>
> - [`docs/play-submission-pack.md`](./play-submission-pack.md), the full submission pack
> - [`docs/data-safety.md`](./data-safety.md), the Data safety answers
> - [`docs/play-console-submission.md`](./play-console-submission.md), what to enter in each Console
>   field, including App access
> - [`docs/play-technical-compliance.md`](./play-technical-compliance.md), the checks on the built
>   artifact

## 5. What only you can do, in Play Console

Since 2026-09-13 Apnivaas is a **new app** in Play Console, package `com.nivorasr.app`
(`apnivaas_app/android/app/build.gradle.kts:60` and `:109`). The earlier listing, locked to
`com.srnivora.app`, is abandoned; nothing was released from it and nothing entered there carries
over. The store listing, App content, Data safety, App access, content rating, testers and the
closed test are all entered again on the new app. The answers themselves do not change.

### Account

- **US$25, one time, non-refundable**, to register a Google Play developer account. It is
  per Google account, not per app.
- Identity verification (a government ID and, for organisation accounts, a D-U-N-S number)
  now happens up front and can take days. Start it early.
- This developer account is a **personal** (individual) account, so Google additionally
  requires a **closed test with at least 12 testers opted in continuously for 14 days**
  before you may apply for production access. The new app needs its own closed test, and it is
  running: the Console app was created on 2026-09-19, the closed test release `1.0.0 (6)` passed
  review and is published, and 12 testers had opted in by 2026-09-20, so the 14 days end about
  2026-10-04, when **Apply for production** unlocks. Plan the calendar around it. Verify the
  current rule in Console before you commit — Google changes it.

### Privacy policy

Play requires a privacy policy URL for every app, publicly reachable, **not behind a
login**. The policy is `/legal/privacy` (`app/legal/privacy/page.tsx`), and the account deletion
page is `/legal/account-deletion` (`app/legal/account-deletion/page.tsx`). Both are public because
`/legal` is in `PUBLIC_PATHS` (`lib/supabase/middleware.ts:9-11`). This section used to say the repo
had no `/privacy` route at all.

The deletion page prints the Android package (`app/legal/account-deletion/page.tsx:142`) from
`ANDROID_PACKAGE`, which is `com.nivorasr.app` (`lib/legal-config.ts:96`). The live site changes only
when the website is pushed, so check that the page shows `com.nivorasr.app` before pasting its URL
into Console. The legal version did not change with the package, because neither the privacy policy
nor the terms names it.

**Version 2026-09-13 is live.** It is in production's `public.legal_versions` (effective
2026-09-12 18:30 UTC) and is `LEGAL_VERSION` in `lib/legal-config.ts:80`. Commit `4fd41ef` was
pushed at 20:44 IST on 2026-09-13, and signed-out GETs of both pages then returned 200 and showed
version 2026-09-13. The in-app copy (`apnivaas_app/lib/features/legal/legal_documents.dart`,
`kLegalVersion` at `:46`) reaches users with versionCode 6. Test both URLs with `curl` from a
signed-out client again before pasting them into Console.

The policy has to name what the Data safety form declares:

- names, phone numbers, addresses, ID-proof images, photographs and payment records of residents;
  that they are stored in Supabase (Postgres + private object storage) and served from Vercel; that
  hostel staff of the same tenant can see them; and retention
- **Razorpay**: on Android its checkout runs inside the app. While a payment is open it takes the
  card, UPI or netbanking details typed and checks which UPI apps are installed. Card and UPI details
  go to Razorpay, never to Apnivaas (`app/legal/privacy/page.tsx:251-253` and `:440-442`)
- **Google**, through Firebase Cloud Messaging, which delivers push: it receives the device's
  registration token and each notification's title and body (`:444-447`)
- the ten Android permissions (`:259-269`)
- how a person asks for deletion, including the in-app route (`:618-619`)

Two sentences on that page still disagree with the Android app as of 2026-09-13. Fixing them is a
job for whoever owns `app/legal/`. `:262-263` says the camera photographs "an identity document, a
receipt or a complaint". On Android only a warden uses it, to photograph a new resident and their ID
proof (`docs/play-technical-compliance.md` §2). `:215` says the push token is written when you sign
in, but push now starts behind the consent gate
(`apnivaas_app/lib/features/legal/consent_gate.dart:93-95` and `:166`).

### Data safety form

**This section no longer keeps its own table.** The copy that used to be here had drifted from
both the schema and the Android app: it marked every row required, and it had no rows for Device or
other IDs, Installed apps or App interactions. Answer the form from
[`docs/data-safety.md`](./data-safety.md) instead:

- **§2** is the data-type table: collected, shared, ephemeral, required or optional, purposes, and
  the code behind each row. It includes **Device or other IDs**, which covers the FCM registration
  token in `public.push_devices.token`. It also includes **App activity › App interactions**, whose
  existing purpose is Fraud prevention, security and compliance and which gains App functionality.
- **§3.2** explains why **Financial info › User payment info** is Yes: collected, not shared,
  optional, with App functionality and Fraud prevention, security and compliance as purposes.
- **§3.4** covers Razorpay Checkout running inside the app on Android. It is the reasoning for
  **App activity › Installed apps** = Yes (the SDK detects UPI apps through the manifest's `upi:`
  `<queries>` intent) and for the App functionality purpose on App interactions.
- **§3.5** covers the FCM registration token.

The 2026-09-13 privacy text is live; submit the answers that rely on it together with
versionCode 6, on the new app.

Security practices section:

- *Data is encrypted in transit* — **Yes**. TLS to Vercel and to Supabase; HSTS and a
  nonce-based CSP set in middleware for the web; the Android manifest sets no
  `usesCleartextTraffic`. Evidence in `docs/data-safety.md` §7.
- *Users can request that their data be deleted* — **Yes**, by two routes. This used to say there
  was no self-service deletion path in the app; commit `a3511d4` added one.
  - **In the app:** "Delete my account and data". Residents open it from the Profile tab
    (`apnivaas_app/lib/features/student/profile_screen.dart:160-163`). Staff open it by tapping their
    picture at the top left (`apnivaas_app/lib/features/shell/staff_profile_sheet.dart:139-144`). It
    files a request and deletes nothing itself, and a second request within 30 days returns the
    first one instead of filing another (`apnivaas_app/lib/features/legal/account_deletion.dart:34-37`).
  - **On the web:** `/legal/account-deletion`, the URL Play requires.

  `docs/data-safety.md` §7.1 says what deletion does to payment records.
- *Independent security review* — No. (`SECURITY.md` is an internal review, not a
  third-party audit; claiming otherwise in Console is a misrepresentation.)
- *Committed to Play Families Policy* — No. This is not a children's app.

### Other declarations

- **Content rating**: complete the IARC questionnaire. Apnivaas is a business/utility app
  with no violence, no gambling, no sexual content — expect Everyone / PEGI 3. Answer
  "yes" where it asks whether users can exchange content or communicate: complaints and
  notices move between residents and staff, even though they never leave the tenant. Residents
  have no leave feature in the Android app; wardens handle leave requests
  (`apnivaas_app/lib/features/warden/home/warden_home_screen.dart:208-212`).
- **Ads**: no. There is no ad SDK and no advertising ID.
- **Financial features**: no; the reasoning is in `docs/data-safety.md` §5. This used to say the
  app only records payments that happened elsewhere, which stopped being true when residents began
  paying rent in the app through Razorpay. Apnivaas takes no commission and holds no balance. The live
  database has four hostels and none has a `razorpay_account_id`. Only Kushi Hostels is approved
  for direct settlement (`razorpay_direct_for_owner` equals its `owner_user_id`), into a Razorpay
  merchant account owned by that hostel's owner.
  - **Android:** `razorpay-order` refuses every other hostel with a 409, "Online payment is not set
    up for this hostel yet. Please pay your warden directly.", before any Razorpay order is created
    (`supabase/functions/razorpay-order/index.ts:233-241`). That includes Demo PG, the hostel Play
    reviewers sign into.
  - **Web:** the order path (`lib/actions/payments.ts`, `createRentOrder`) makes no such check. It
    creates the Razorpay order (`:128`) before calling `rz_open_intent` (`:146`) and never sends
    transfers. That is a latent defect, flagged as a separate code task and not fixed.
- **Target API level**: `targetSdk = 36` satisfies the current requirement. Play raises the
  floor every August — expect to bump `compileSdk`/`targetSdk` and re-upload each year, or
  the listing stops accepting updates and eventually stops being served to new devices.
- **Store listing assets** — Play will not let you publish without them. This list used to say
  none of them existed; they do now:
  - app icon, 512×512 PNG with alpha → `public/store/icon-512.png` (512×512, RGBA). This used
    to point at `public/icons/icon-512.png`; the store icon is the one under `public/store/`
  - feature graphic, 1024×500 → `dist/store-listing/apnivaas-feature-graphic.png`
  - at least 2 phone screenshots (16:9 or 9:16, 320–3840 px on each side); tablet
    screenshots too if you list tablet support → four phone screenshots at 1080×1920,
    `dist/store-listing/apnivaas-phone-*.png` (owner, warden, manager, resident), and four
    10-inch tablet screenshots at 1440×2560, `dist/store-listing/apnivaas-tablet10-*.png`
  - short description ≤ 80 characters, full description ≤ 4000 → `dist/store-listing/`, with
    the text also tracked in `docs/store-listing/`. There are two full descriptions:
    `full-description.txt` mentions push and `full-description-without-push.txt` does not. **Use
    the without-push one** until push has been confirmed on a real phone
- **Minimum functionality / spam policy**: Play rejects apps that are bare webview
  wrappers. The submitted app is a native Flutter client: `apnivaas_app/pubspec.yaml` has no
  WebView or `url_launcher` dependency. The argument that used to be here, that a TWA is the
  sanctioned exception because Digital Asset Links proves site ownership, applied only to the
  retired TWA build.
