# Round 3 spec (owner request, 2026-10-25)

This builds on round 2 (docs/self-signup-onboarding-spec.md and docs/self-signup-api.md), which is live. The security rules from round 2 still hold:
- every client value is attacker-controlled, so authorization lives on the server;
- no secrets go in the app;
- nothing opens a browser;
- the clay kit look is kept.

**Keep it lean.** SQL and Dart comments should be short. The usage budget is the binding constraint.

## R1. Create account (step 3) and the login screen
- **Create your account (Owner, Tenant, Staff):**
  - a manual form at the top: full name, phone, email, password with confirmation, and address (city and pincode for owners and tenants), then **Create account**;
  - below that, the divider "or continue with", then **round logo buttons** for Google, Facebook and Truecaller in a row (official-style glyphs drawn as clay-kit circles, 56dp, with semantics labels);
  - Facebook and Truecaller stay hidden until configured, exactly as today;
  - "I already have an account — Sign in" at the bottom.
- **The manual sign-up goes through a new mobile-auth action, `signup_password`:**
  - persona owner|tenant|staff, name, phone, email, password, plus optional address fields;
  - the server creates the auth user with email confirmation required (the existing email-verification flow proves the address);
  - it creates the profile through `svc_create_self_signup_profile` with source `self_email` (add it to the allowed sources);
  - it applies the round-2 rate limits;
  - it returns a session. The existing gates then run as usual: consent, then the email-verification hold for owners and staff.
- **Login screen:** remove the forest hero card ("Run your PG from your phone") completely. The screen is:
  1. the brand logo, medium size (about 96–120dp, sharp, from assets/brand), centred;
  2. "Apnivaas" under it in Outfit;
  3. the sign-in form, Google (the round button), and "New here? Create an account".

## R2. Tenant records start at check-in
- A tenant's dues, payment status, fee history and every per-month "paid / unpaid" view start at the tenant's **check-in date**. Use the roster row's joining date; for a join request accepted in round 2, the acceptance date.
- No month before check-in is shown as due or unpaid anywhere: tenant home and fees, warden fees/collections and history, owner money screens, reports and RPC aggregates.
- Fix this at the source, in the RPCs and queries that generate or aggregate dues, and add tests for a tenant who joined mid-period.
- The tenant's **Profile** gets a **Timeline**, from check-in to today: checked in, room assigned or changed, each due and each payment, complaints, check-out request and its outcome. It is read-only and built from existing records through one RPC.

## R3. Owner 2FA → phone biometric lock
- Owners are no longer forced to set up 2FA. Remove the owner-required MFA gate in the app, and any server-side "owner must have a factor" requirement if one exists. 2FA stays available as an optional setting in Security. Anyone who already enrolled keeps it.
- Add **biometric app lock** using `local_auth`, with fingerprint, face or device PIN as the fallback:
  - on by default for owners, optional for every other role, with a switch in Security;
  - it asks when the app opens and when it returns after more than 60 seconds in the background;
  - it is local only, so nothing biometric leaves the phone.
- Re-allow `USE_BIOMETRIC` in the manifest. The current `tools:node="remove"` exists only because of the old permission count.

## R4. Exact location with an in-app "turn on location" popup
- Use **precise** location (`ACCESS_FINE_LOCATION`) for two things:
  - the owner's PG pin, at onboarding and when editing the PG profile; this one is stored, as `hostels.latitude/longitude`;
  - the tenant's "PGs near you"; this one is used once and not stored.
- When location services are off, show the system **"Turn on location" resolution dialog** inside the app, through Google Play services `SettingsClient`, not a trip to Settings. Use a small platform channel or a maintained package. If the user declines, fall back to search.
- Take a single fix with a timeout. There is no background location and no stream.

## R5. PG profile ("Enhance your PG")
- **Owner → Property → PG profile:**
  - the PG name, a logo, up to 6 cover photos and a short description (up to 500 characters);
  - **amenities** as toggles: Wi-Fi, AC, food, laundry, power backup, parking, CCTV, housekeeping, attached bathroom, hot water, gym, study room;
  - house rules (already exists), the exact location pin, and the "listed" switch.
- Media goes in a storage bucket `pg-media`:
  - the owner writes `<hostel_id>/...`;
  - read access goes to any signed-in user, but only for listed hostels with an active or trial plan; staff of the hostel can always read;
  - files are JPEG, at most 1600px, compressed.
- **Ratings and reviews:**
  - a current tenant can rate their PG 1–5 with an optional comment (up to 300 characters), one review per tenant per PG, editable;
  - former tenants keep their review;
  - the owner can see reviews but cannot edit or delete them;
  - the average and count are computed on the server.
- **Find your PG**: the list rows show the logo, rating and top amenities. Tapping a row opens a **PG profile** page (covers carousel, amenities, rating and reviews, locality and city), then "Request to join". Owner contacts and the full address are still hidden until accepted.

## R6. Check-out flow
- The tenant taps **Request check-out** with a preferred date and an optional reason. The request goes to the wardens of the PG (and the owner can see it); the tenant can have only one pending request.
- The warden can **Accept**, which runs the existing vacate flow on the chosen date: it unlinks the account, frees the bed, and later dues stop. The warden can also **Decline**, with a note.
- The **owner home shows a "Check-outs" notice** (recent check-outs, plus pending requests). Notifications go to the tenant, the wardens and the owner.

## R7. Super Admin: sign-ups, demos, deletions
- **New sign-ups and demos**, one list:
  - each self-signed-up owner with their PG, phone, email and sign-up date;
  - the trial **start and end dates** and the plan status;
  - their demo request: slot, bed band, status;
  - filters: date range and status.
- The Super Admin can mark a demo confirmed, done or no-show (the RPC exists).
- **Deleted accounts**:
  - a list of accounts deleted by their owner (staff), by self-deletion requests, or by the Super Admin, showing who, role, PG, when, by whom and the reason;
  - the Super Admin can **permanently delete** an account, which erases the auth user, profile PII, photos and documents;
  - **payments, receipts, dues and audit records are retained** (anonymised to "Deleted user") for legal and accounting reasons. The legal text says so.

## R8. Staff self sign-up
- Persona **Staff** → create an account (manual form or Google, Facebook or Truecaller) → **Request to join a PG as staff**: search for a PG and pick it.
- The owner sees staff requests next to the join requests. **Accept** means choosing the role (Manager or Warden), which converts the account to that role, assigns it to the hostel through the existing staff-access model, and notifies the person. **Decline** takes a note.
- These staff accounts were created by sign-up, so their own Google, Facebook or Truecaller identity **may** sign in after conversion. Change `guard_external_identity` to allow it for manager and warden only when the account's `signup_source` is a self source.
  - Owner-created staff (source `admin`) are still refused, to prevent takeover through email auto-linking.
  - `super_admin` is always refused.
- The DB rule that sign-up never creates a staff role directly still holds. Only the owner's accept RPC converts an account. Until then the account carries `staff_applicant = true` and has no access.

## R9. UPI payments straight to the owner
- **Owner → Plan & billing, or Money → Payment settings**: add a UPI ID (VPA format check, e.g. `name@okhdfcbank`, `98xxxxxxx@ybl`, `@paytm`, `@ptyes`) and a payee name. It is stored per hostel. Only the owner writes it; tenants of that hostel read it.
- **Tenant → Pay rent → Pay with UPI app**:
  - open a UPI intent (`upi://pay?pa=&pn=&am=&cu=INR&tn=<PG> rent <month>&tr=<ref>`) using an Android intent, not a browser;
  - the money goes straight to the owner's UPI account;
  - after returning, the tenant enters the **UTR / transaction ID**, 12 digits for most apps.
  - This creates a **payment claim**: pending, with amount, UTR and month. Each UTR is unique per hostel.
- **Owner or warden confirms** the claim after checking their UPI app or bank. Confirming records the payment through the existing payment-recording path, so receipts and dues update. They can also reject it, with a note.
- The app never marks a UPI payment paid on the device's word: an intent result can be faked. Razorpay checkout stays available where the owner has it set up.

## R10. Legal
- Bump the legal version to **2026-10-26** to cover:
  - manual sign-up;
  - precise location (PG pin stored; the tenant's location used once, not stored);
  - the biometric lock (on-device only);
  - PG photos and reviews (public to signed-in users looking for PGs);
  - staff sign-up requests;
  - check-out requests;
  - UPI payments made directly to owners (UTR stored; Apnivaas does not hold that money);
  - retention of payment records after deletion.
- Update the permission sentence: fine location and biometric are added.
- Update `docs/data-safety.md`.
- The migration inserts the `legal_versions` row.

## Done means
- One concise migration, `2026-10-26-round3.sql`, with `.down.sql` and `.test.sql`, passing on live inside a rolled-back transaction:
  `npx -y supabase db query --linked --project-ref nimxvgzscbanhtvgnjll --file <file>`.
  That runs the file directly; never paste large SQL into a tool call.
- The Edge Function changes are deploy-ready.
- `flutter analyze` is clean and the full suite is green.
