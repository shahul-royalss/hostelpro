# Releasing Apnivaas 1.3.0 on Google Play: step by step

The file to upload is **`dist/APNIVAAS-1.3.0-b12.aab`** (version 1.3.0, version code 12, signed with the upload key).
Do the steps in order. Each one says where to click.

---

## Before you start (5 minutes)
1. **Check the website is updated.** Open https://hostelpro-three.vercel.app/legal/privacy and confirm it says
   **26 October 2026**. Vercel deploys about 2 minutes after the GitHub push. If the page still shows an older date,
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
3. **App bundles → Upload** → choose `dist/APNIVAAS-1.3.0-b12.aab`. Wait for "1.3.0 (12)" to appear.
4. **Release name:** `1.3.0 (12)`.
5. **Release notes** (paste under `<en-IN>`):
   ```
   • A fresh new design for owners, managers, wardens and tenants
   • Create your account in the app — owners set up their PG with a free first month
   • Tenants find a PG nearby and send a join request; owners accept in one tap
   • Pay rent straight to your owner's UPI ID, or through Razorpay
   • Check-out requests, rent history from your check-in date, and an app lock
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
   tenant home and payments. Take them on your phone with build 12 installed. Use portrait, 1080×1920 or larger.
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
- **Oct 30 or later (Facebook and Truecaller):** when Facebook is published and Truecaller approves the app,
  I add their sign-in code to the app and you upload the next version the same way, as version code 13.

## If something goes wrong
- **"Version code 12 has already been used"**: ask me for a new build with the next number.
- **Data safety rejected**: Play's email names the field. Compare it with the table above and `docs/data-safety.md`.
- **App access rejected**: the reviewer couldn't sign in. Check that the login you gave works on a fresh phone.
