# Releasing Apnivaas 1.4.1 on Google Play: step by step

The file to upload is **`dist/APNIVAAS-1.4.1-b15.aab`** (version 1.4.1, version code 15, signed with the upload key).
If build 14 (1.4.0) was never uploaded, upload this one instead; Play only needs the newest. If a draft
release with build 14 is open in Production, remove build 14 from it and add build 15.
Do the steps in order. Each one says where to click.

---

## Before you start (5 minutes)
1. **Check the website is updated.** Open https://hostelpro-three.vercel.app/legal/privacy and confirm it says
   **1 November 2026**. Vercel deploys about 2 minutes after the GitHub push. If the page still shows an older date,
   open vercel.com → project → Deployments and wait for the newest deployment to turn green.
2. **Razorpay:** dashboard.razorpay.com → Settings → Webhooks → open the Apnivaas webhook → make sure
   **payment.captured** and **order.paid** are both ticked → Save.
3. **Keep the reviewer logins ready**: one owner account and one tenant account that work, with their email or phone and password.
   You enter them in step B2. Never put passwords in a document or a screenshot.

---

## A. Upload the new version
1. Go to **play.google.com/console** → choose the **ShaReshi Tech** account → open **Apnivaas**.
2. Left menu: **Test and release → Production** (or **Testing → Internal testing** if you want to try it with
   your own phone first, which is recommended). Click **Create new release**.
3. **App bundles → Upload** → choose `dist/APNIVAAS-1.4.1-b15.aab`. Wait for "1.4.1 (15)" to appear.
4. **Release name:** `1.4.1 (15)`.
5. **Release notes** (paste under `<en-IN>`):
   ```
   • English, Hindi, Telugu, Tamil, Malayalam and Kannada, switchable on the sign-in screen
   • Sign in with Google, Facebook or Truecaller
   • Owners drop the PG's exact pin on a satellite map; tenants open it in Google Maps
   • Tenants browse PGs and see whether beds are available before asking to join
   • Back buttons on every sign-up step, and an update reminder when a new version is out
   ```
6. Click **Next**. Read the warnings. Warnings in yellow are fine; red errors must be fixed. Then **Save**.
   Don't send it for review yet. Finish section B first.

---

## B. App content (left menu → **Policy and programs → App content**)
Open each item below and press **Save** in each one.

1. **Privacy policy:** `https://hostelpro-three.vercel.app/legal/privacy`
2. **App access:** choose "All or some functionality is restricted" → **Add instructions**:
   - Name: `Owner login`, with the owner username and password, and the note "Sign in with email or phone and password on the first screen."
   - Add another set for the **tenant** login.
3. **Ads:** No, the app does not contain ads.
4. **Content rating:** open the questionnaire. Nothing changed, so submit it again if Play asks.
5. **Target audience and content:** **18 and over**. The Terms say sign-up is for adults.
6. **Data safety** (the most important part). Click **Manage**, go through the form and set exactly this:

   | Section | Data type | Collected? | Shared? | Required or optional | Why (purposes) |
   |---|---|---|---|---|---|
   | **Location** | **Precise location** | Yes | No | Optional | App functionality. The PG's map pin, and tenant "PGs near you", used once and not stored |
   | Location | Approximate location | Yes | No | Optional | App functionality |
   | **Personal info** | Name, Email address, Phone number, Address, User IDs | Yes | No | Required (name, phone); optional (address) | App functionality, Account management |
   | Personal info | Other info (date of birth, gender, emergency contact) | Yes | No | Optional | App functionality |
   | **Financial info** | Payment info (owner's UPI ID, UTR numbers) | Yes | No | Optional | App functionality |
   | Financial info | Purchase history (plans, rent payments) | Yes | No | Required | App functionality |
   | **Photos and videos** | Photos (profile photo, PG photos) | Yes | No | Optional | App functionality |
   | **Files and docs** | Files and docs (ID document images) | Yes | No | Optional | App functionality, Fraud prevention |
   | **App activity** | Other user-generated content (reviews, complaints, requests) | Yes | No | Optional | App functionality |
   | **Device or other IDs** | Device or other IDs (push notification token) | Yes | No | Required | App functionality |

   Then answer:
   - "Is all of the user data collected by your app encrypted in transit?" **Yes**
   - "Do you provide a way for users to request that their data is deleted?" **Yes**, with the URL
     `https://hostelpro-three.vercel.app/legal/account-deletion`
   - "Biometric": do **not** tick it. The fingerprint check happens on the phone and nothing is collected.

   Press **Next** until **Submit**. The full list, with reasons, is in `docs/data-safety.md` §3.8.
7. **Financial features:** declare that the app lets tenants pay rent to their PG owner, through Razorpay and
   through the tenant's own UPI app. It offers no loans, no credit and no crypto.
8. **Government apps, News, Health, COVID-19:** answer **No** or "not applicable" to each.
9. **Permissions:** the app uses **foreground** location only (no background location), the camera and biometric, and no SMS
   or call-log access. If Play asks about a location foreground service, the answer is **No**; it was removed.

---

## C. Store listing (left menu: **Grow users → Store presence → Main store listing**)
1. Keep the name **Apnivaas** and the short and full descriptions. Add one line about "create your account
   and pay rent by UPI" if you like.
2. **Phone screenshots:** replace them with new ones of the redesigned app, at least 4: sign-in, owner home,
   tenant home and payments. Take them on your phone with build 15 installed. Use portrait, 1080×1920 or larger.
3. **Save**.

---

## D. Send for review
1. Left menu: **Publishing overview** (or **Dashboard**) → **Send changes for review** → confirm.
2. Review usually takes **1–3 days**. You get an email when it's approved.
3. When it's approved, go to Production → your release → **Rollout**: start at **20%**, watch for crashes for a day
   (Quality → Android vitals), then raise it to **100%**.

---

## E. After it is live
- Install it from the Play Store on a phone that does **not** have the test APK; uninstall the test APK first.
  Check Google sign-in. It works because the Play signing key's fingerprint is registered with Google.
- **Facebook** signs in through the Facebook app on the phone, so test it on a phone that has it.
- **Truecaller is in 1.4.1.** It works once Truecaller has approved the app in its developer console
  (developer.truecaller.com → your app) with package `com.nivorasr.app` and the SHA-1 fingerprints of
  BOTH keys: the upload key and the Play app signing key (Play Console → Test and release → Setup →
  App signing). Until then the button answers "Truecaller could not sign you in".
- **Update popup.** From 1.4.1 on, an older build shows "Update available" when Play has a newer
  version and opens the Play Store app. Builds 12–14 do not have it; they learn by Play's own updates.

## If something goes wrong
- **"Version code 15 has already been used"**: ask me for a new build with the next number.
- **Data safety rejected**: Play's email names the field. Compare it with the table above and `docs/data-safety.md`.
- **App access rejected**: the reviewer couldn't sign in. Check that the login you gave works on a fresh phone.
