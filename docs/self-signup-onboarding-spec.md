# Self sign-up, onboarding, join requests, plans — build spec (2026-10-24)

The owner asked for this on 2026-10-24. It supersedes the Phase B design in `docs/apnivaas-1.3-build-plan.md`
wherever the two disagree. The one deliberate exception is that **an owner's first PG goes live
immediately on a 1-month trial**, not after Super Admin approval. The plan's security machinery still applies:
read its Phase B section for guard patterns, the md5-guard convention and the `.test.sql` format.

Decisions taken with the owner:
- Plan payments go through **Razorpay**, with UPI shown first, and activate **automatically** once the server has verified them. A personal UPI ID
  cannot confirm a payment, so it is not used.
- Live database migrations and Edge Function deploys are approved, **after** each migration passes its test
  on live inside a rolled-back transaction.
- **Facebook and Truecaller**: build the server actions and the app's integration points now. The buttons stay
  hidden until the IDs exist. Do not add their native SDKs to this build. Google works today and is
  the path to test end to end.

## Non-negotiable rules
1. Self sign-up creates **owner or student (tenant) only** — never manager, warden or super_admin. This is
   enforced in the database (`users_self_signup_guard` trigger plus the service-role-only profile function),
   not only in the app or the Edge Function. Staff accounts are still created only by an owner or the
   Super Admin.
2. Every client value is attacker-controlled: persona, plan, amount, hostel id, file paths, coordinates.
   Amounts come from a server-side plan table. The persona is checked against an allowlist on the server.
3. No service-role key, Razorpay secret, Facebook app secret or Truecaller value in the app.
   Secrets are Edge Function secrets only.
4. Every RPC carries authorization, validation, `app.spend(...)`-style rate limits and an audit entry,
   in the repository's existing conventions (look at sibling RPCs and copy the patterns).
5. Nothing opens a browser. Google uses Credential Manager, payments use the Razorpay SDK sheet, and every
   other flow stays in the app.

## Flow 1 — first launch and personas
- Splash → **"Who are you?"** step screen (step 1 of a short progress indicator), with three cards side by side in the
  RentOk style (see `RolePicker.dc.html` in the design canvas): **Owner** ("I run a PG or hostel"), **Tenant**
  ("I stay in, or am looking for, a PG"), **Staff** ("My owner gave me a login").
- Owner or Tenant → **Create your account** (step 2): Continue with Google; Continue with Facebook and
  Continue with Truecaller (both hidden until configured); and **"I already have an account — Sign in"**, which
  goes to the existing login screen. Staff → login screen, with the line "Your owner creates staff accounts."
- The login screen keeps email-or-phone + password + Google, and gains "New here? Create an account" →
  persona screen. One login for every role; after sign-in the app routes by role, exactly as today.
- The persona chosen is remembered on device until the account exists, then forgotten. It is a hint for the
  request only, never stored as authority.

## Flow 2 — the server side of sign-up (Edge Function `mobile-auth`)
- Google: the existing action gains an optional `persona` (`owner` | `tenant`).
  - Existing account for the verified email: sign in, unchanged. Staff are still refused and inactive accounts are still refused.
  - No account and no persona: today's "no account" refusal, worded as "No account yet — create one".
  - No account with a valid persona: create the auth user with the admin API (email confirmed, because Google verified it, and a
    random unusable password). Create the profile through `svc_create_self_signup_profile` with role
    `owner` or `student`, source `self_google` and the name from the token. Then mint the session through the
    existing id_token grant, and audit.
  - Rate limits: use the existing `consumeRateLimit` keys, plus a sign-up-specific limit per IP and per email.
- Facebook (`action: "facebook"`, access token + optional persona):
  - Verify the token with the Graph API `debug_token`, using app access token `FACEBOOK_APP_ID|FACEBOOK_APP_SECRET`. Require `is_valid` and `app_id` to equal ours.
  - Fetch `/me?fields=id,name,email`. Find the user through `external_identities` (provider, subject), or by
    verified email following the same rules as Google. Otherwise sign up when a persona is given.
  - Mint a session without OIDC: admin `generateLink(type 'magiclink')`, then a server-side `verify` with the
    token hash. The emailed link is never sent.
  - Accounts with no email get a non-routable synthetic address (`fb-<id>@identity.apnivaas.invalid`).
  - The function answers 503 with "Facebook sign-in is not set up yet" while the secrets are missing.
- Truecaller (`action: "truecaller"`, authorization code + code verifier + optional persona):
  - Exchange the code at Truecaller's OAuth token endpoint using `TRUECALLER_CLIENT_ID` and PKCE. Read userinfo, which gives a verified phone and the name.
  - Sign in only through an existing `external_identities` link.
  - A phone that matches an existing account is **refused**: "An account already uses this number — sign in with your password". A typed phone was never verified, so matching it would let a mistyped number take over an account.
  - Otherwise sign up when a persona is given. The synthetic address is `tc-<sub>@identity.apnivaas.invalid`.
  - 503 while the secret is missing.
- Staff are refused on every external provider, as today (`app.guard_external_identity`). Extend that guard to
  allow the providers we add only for owner and student.
- `external_identities(provider, subject, user_id, created_at)`: unique on (provider, subject). Service role only;
  no client access.

## Flow 3 — owner onboarding
- After sign-up, an owner with no hostel sees **Tell us about your PG** (step 3):
  - PG name, property type (PG / Hostel / Co-living / Flats), for (Boys / Girls / Co-ed), address, locality, city, 6-digit pincode, floors, rooms and default beds per room;
  - optional "Use my current location" for the map pin. Ask for location permission in words first; coarse location is enough.
- `ow_create_first_hostel(...)`, owner only:
  - the caller's `signup_source` is a self source, and the caller owns no hostel;
  - spend limit, field validation and a uniqueness-of-pending guard against double taps;
  - creates the hostel, plus a `subscriptions` row: status **trial**, start today, end today + 30 days, amount 0, notes 'free trial';
  - binds the owner exactly as the existing Super Admin create path does (read `sa_create_hostel_with_subscription` live first);
  - notifies Super Admins ("New PG signed up: <name>, <city>") and audits.
  - If `subscription_status` has no `trial` value, add it in the migration and make every reader treat trial like active.
- Then a celebration sheet: **"Your first month is free"**, with the trial end date, and one button, "Start my free month".
- Then **Book a free demo**: name, phone, PG name and city are prefilled. Pick a day (next 14 days) and a time slot (10–18,
  hourly) and a bed band (1–20 / 21–50 / 51–100 / 100+). Submit through `ow_book_demo(...)`, which inserts into
  `demo_requests` with a spend limit and a one-open-request-per-owner rule. There is a "Skip for now" button. Book a demo is also reachable later from
  More. The Super Admin sees demo requests through an RPC; a full screen is optional.

## Flow 4 — tenant sign-up and joining a PG
- After sign-up, a tenant with no hostel sees **Your details** (step 3): full name, phone, gender, date of birth,
  an emergency contact name and phone, a **profile photo** (strongly encouraged and required before sending a join request)
  and an optional **ID document** (see Flow 7). Saved through `me_update_profile(...)`, own row only, and only the columns
  the existing guard allows.
- **Find your PG** (step 4):
  - "PGs near you" uses coarse location through `st_nearby_hostels(lat, lng)`; "Search by name or city" uses `st_search_hostels(q)`.
  - The rows show name, type, for, locality, city and distance. Full addresses and owner contacts are never returned.
  - Only hostels with an active or trial plan and `listed = true` appear.
  - Neither RPC stores the caller's location. Both have spend limits and a cap of 25 rows.
- **Request to join**: `st_request_join(hostel_id, message)`. The caller must be a student with no hostel, no non-vacated roster
  row and no other pending request. It notifies the owner and wardens of that hostel.
- Then a **Waiting** screen: "Waiting for <PG> to accept", with Cancel (`st_cancel_join_request`). It refreshes on resume and on
  push.
- The owner and wardens see **Join requests** with a badge: People tab, owner home attention list and notifications.
  - The card shows the requester's name, phone, photo and documents.
  - **Accept** calls `ow_decide_join_request(id, true)`. It creates the roster (`students`) row with the requester's details and
    `user_id`, with no room yet, and links `users.hostel_id` through a transaction-local guarded path like the plan's
    `app.link_student_account`, so a client can never set `hostel_id` directly. It notifies the tenant.
  - **Decline** takes an optional note and notifies the tenant, who can then request another PG.
- The warden fills the room, rent and other details later through the existing edit flows.
- **Leaving**: only the owner or warden removes a tenant, through the existing vacate flow. That flow must also clear the
  linked account's `users.hostel_id` so the tenant can request another PG. Verify the current behaviour and fix it in
  the migration if needed. A tenant cannot leave by themselves.

## Flow 5 — owner deletes a manager or warden
- The staff list and the staff detail screen get **Delete account** (owner only). A confirmation dialog explains that it is permanent.
- Edge Function action, either in `owner-create-staff` or a new `owner-staff-account`:
  - the caller owns the hostel the target works in, and the target's role is manager or warden;
  - reuse the existing account-erasure path (account deletion, `storage-erasure`) so foreign keys and history stay intact;
  - the profile is anonymised or tombstoned and the **auth user is deleted**, which frees the email and phone;
  - audit and rate-limit it.
- After this, signing in with the old login answers **"No account found"**, and the person can later sign up as an
  owner or tenant like anyone new.

## Flow 6 — profile photos for every role + headers
- Private storage bucket `avatars`. The path is `<uid>/<random>.jpg`, written by the user only.
  - `me_set_avatar(path)` checks the prefix and that the object exists, sets `users.avatar_path` and best-effort removes the old object.
  - Read access goes to: self; owner, manager and warden of the user's hostel; owner and wardens of a hostel with a pending join request from
    that user; and the Super Admin. Use a helper in the storage policy.
- The app picks from camera or gallery, crops square and compresses to at most 512 px JPEG. Avatars show in every header and
  roster row, with initials as the fallback.
- **Tenant, manager and warden homes get the top bar the owner has: avatar + notifications bell.** The avatar opens
  the profile sheet, which includes "Change photo"; the bell opens notifications or notices. Owner and Super Admin keep theirs and gain the photo.

## Flow 7 — identity documents (fraud prevention)
- Private bucket `identity-documents` and table `user_documents(id, user_id, kind, storage_path, created_at)`.
  - The kinds are aadhaar_masked, pan, driving_licence, voter_id, passport, college_or_work_id and other.
  - Each user uploads only their own documents.
  - Read access goes to: self; owner and warden of the user's hostel or of a hostel with a pending request from the user; and the Super Admin.
  - Delete: self, plus account erasure. Signed URLs live 60 seconds.
- The app says plainly: "Upload a **masked** Aadhaar (download it from the UIDAI site with only the last 4 digits
  showing) or another ID." The phone copy is never kept after upload.

## Flow 8 — plans and payment
- Plans live in a server table, `platform_plans`, which is the only source of amounts:
  - `monthly`: 1 month, ₹1,099;
  - `quarterly`: 3 months at ₹999 a month, ₹2,997;
  - `yearly`: 12 months at ₹959 a month, ₹11,508, **plus 1 month free**, so 13 months.
- Owner → More → **Plan & billing**: current status (Trial ends <date> / Active until <date> / Ended), three plan cards,
  and "Pay ₹X". The cards show the per-month price and the saving.
- New Edge Function `subscription-order`:
  - the caller owns the hostel and passes a plan id; the amount comes from the table;
  - creates a Razorpay order on the platform account with notes `{purpose:'subscription', hostel_id, plan}` and no transfers;
  - inserts a `subscription_payments` row (order id, hostel, plan, amount, status 'created') and returns the order id and key id.
- The app opens Razorpay checkout through the existing plugin, with UPI preferred.
- Activation is server-verified and idempotent through two paths:
  - (a) `subscription-order` action `verify`, called after checkout success, checks `razorpay_signature` (HMAC of order_id|payment_id) and fetches the payment, which must be captured or authorized and match the amount and order;
  - (b) `razorpay-webhook` handles `order.paid` and `payment.captured` with `notes.purpose = 'subscription'`.
  - Either path marks the payment paid once, keyed on payment id. It extends the hostel's plan: the new end is the later of the current end and today, plus the plan months (+1 for yearly). It sets the status to active and audits.
  - A client "success" with no verified signature activates nothing.
- When a trial or plan ends, the existing expiry behaviour applies. The app shows a "Your plan has ended — choose a plan" banner to the owner.

## Flow 9 — location
- Android `ACCESS_COARSE_LOCATION` only. Use the `geolocator` package (the only new dependency besides an image cropper, if one is needed).
- Ask in words first. On denial, use search.
- New `hostels` columns: `latitude` and `longitude` (numeric(9,6), nullable, range-checked), `locality`, `city`,
  `pincode`, `property_type`, `gender_policy` and `listed boolean default true`. Owners edit them in PG settings later; that is optional this round.

## Flow 10 — legal
- Legal version **2026-10-25**: privacy policy and terms, in the app, on the website (`app/legal/*`) and in `lib/legal-config.ts`, cover:
  - self sign-up and the providers;
  - profile photos and identity documents (who sees them, retention, deletion);
  - approximate location (used for the nearby search, not stored);
  - PG location;
  - Razorpay plan payments;
  - demo requests;
  - join requests.
- `db/migrations/2026-10-25-legal-version-signup.sql` inserts the row. It goes live **before** any build carrying the version.
- The permission count in the policy changes, because coarse location is added: update the sentence and `docs/data-safety.md`. The owner updates the Play Data safety form.

## Done means
- The migration has `.down.sql` and `.test.sql`, and the test passes on live inside a rolled-back transaction.
- The Edge Functions type-check (`deno check`) and have unit-testable helpers.
- The app has widget and unit tests for every new flow, plus the existing suite green, analyze clean, and no overflow at 1.4x on 360dp.
- Every new screen uses the clay kit (`lib/shared/clay/`) and matches the Phase A look.
