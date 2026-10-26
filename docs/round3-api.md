# Round 3: API contract (2026-10-26)

The app builds round 3 (docs/round3-spec.md) from this file. Server side: `db/migrations/2026-10-26-round3.sql`,
`db/migrations/2026-10-26-legal-version-round3.sql` and the Edge Function `mobile-auth`.
Wire formats, error shapes and SQLSTATEs are unchanged from `docs/self-signup-api.md` §0:
- **show `message` (RPC) or `error` (Edge Function) verbatim**;
- `hint` names the field for a validation error;
- `P0001` refusal, `42501` not allowed, `22023` bad parameter, `23505` duplicate.

A rate-limit refusal is `P0001` with `hint = "Try again in about N seconds."`. Its message is listed per RPC as *(limit)*.
Every RPC is `supabase.rpc(name, params)` with the user's session; anon can call none of them.

---

## 1. Sign-up (R1, R8): `mobile-auth`

### 1.1 `{ "action": "signup_password", "persona": "owner"|"tenant"|"staff", "fullName", "phone", "email", "password", "city"?, "pincode"? }`
- Called before a session exists, with the anon key, like `signin`.
- Success: the same body as `signin` (`accessToken`, `refreshToken`, `expiresAt`). Install the session; the usual gates run next (consent, then the email-verification hold for owners and staff).
- What the server does:
  - creates the login and the profile with `signup_source = 'self_email'`, `email_verified_at = null`;
  - `staff` creates a **staff applicant**: `users.role = 'student'`, `users.staff_applicant = true`, no PG, no access;
  - `city`/`pincode` are stored on `users.city` / `users.pincode` (optional; the app asks owners and tenants for them).

| HTTP | code | error (verbatim) | when |
|---|---|---|---|
| 400 | | `Choose Owner, Tenant or Staff to create an account.` | persona missing or not on the list |
| 400 | | first field error; `fieldErrors` keyed `fullName`, `email`, `phone`, `password`, `city`, `pincode` | validation (below) |
| 409 | `email_in_use` | `An account already uses this email — sign in, or reset your password` | address taken |
| 409 | `phone_in_use` | `An account already uses this number — sign in with your password` | number taken |
| 429 | | `Too many attempts. Please wait N minute(s) and try again.` | limits below |
| 503 | | `Sign-up is temporarily unavailable. Please try again in a minute.` | outage |
| 503 | | `Your account was created. Please sign in with your email and password.` | account made, first session failed |

Field messages:
- `fullName`: `Enter a name between 2 and 80 characters.`
- `email`: `Enter a valid email address` (also for `@identity.apnivaas.invalid` and `@student.hostelpro.local`)
- `phone`: `Enter a valid 10-digit mobile number.`
- `city`: `Enter your city.`
- `pincode`: `Enter a valid 6-digit pincode.`
- `password`, same order and words as `password_policy.dart`:
  1. `That password is too long`
  2. `Use at least 8 characters`
  3. `Include at least one letter`
  4. `Include at least one number`
  5. `Include at least one capital letter`
  6. `Include at least one symbol, like ! or @`
- A password GoTrue refuses: `Choose a stronger password.`

Rate limits:
- the login IP and per-address keys (shared with `signin`);
- sign-up per IP: 30 an hour;
- sign-up per address: 3 a day.

### 1.2 Social sign-up as staff
- `google`, `facebook` and `truecaller` accept `"persona": "staff"` as well as `owner` and `tenant`.
- With no existing account, `staff` creates a staff applicant (source `self_google`, `self_facebook` or `self_truecaller`).
- An existing account ignores the persona, as before.

### 1.3 Who may use Google, Facebook or Truecaller
- Owners and tenants (staff applicants included) may.
- **Managers and wardens** may only when their account was self-created and converted by an owner (§6):
  - a `self_google`, `self_facebook` or `self_truecaller` source;
  - or `self_email` once the address is verified.
- Owner-created staff (`admin`) are refused with `staff_refused`.
- `super_admin` is always refused with `staff_refused`.
- The database enforces the same rule on `auth.identities` and `external_identities`.

### 1.4 Takeover protection (no app change)
- When Google (or Facebook, by address) matches a `self_email` account whose address was never verified, that account's password and sessions are removed before the sign-in completes.
- Google also marks the address verified.
- The person can set a password again with "Forgot password".

## 2. After sign-up: routing
- `public.users` now has `staff_applicant boolean`, `city`, `pincode`.
- Routing order: consent → (owner/staff) email verification → then:
  - `role = 'student' and staff_applicant` → the **staff applicant** screen (§6);
  - `role = 'student'` → the tenant flow;
  - `owner` → onboarding, as in round 2.

## 3. Tenant records from check-in (R2)

### 3.1 Behaviour changes (no new parameters)
- `rpc_fee_ledger(p_hostel_id, p_period_month)` leaves out residents whose `date_of_joining` is after that month.
- `rpc_hostel_stats` (collected, pending, paid and unpaid counts) inherits this.
- The check-in month itself is listed as due, at the full monthly fee.
- For a tenant accepted from a join request, `date_of_joining` is the acceptance date.

### 3.2 `rpc_student_fee_months(p_student_id uuid default null)` → rows `{period_month 'YYYY-MM', amount_due, amount_paid, status 'paid'|'partial'|'unpaid', paid_on, mode}`
- Newest first, from the check-in month to the current month (or the check-out month).
- `p_student_id = null` means the caller's own current roster row (tenant).
- Owners and wardens of the PG pass a resident's id.
- `amount_due = 0` means no rent is set yet.
- Error: `Resident not found.` (P0001), for no row or a row the caller may not read.

### 3.3 `st_timeline(p_student_id uuid default null)` → rows `{at timestamptz, kind, title, detail, amount, status, ref_id}`
- Newest first. Same callers and error as 3.2. Read-only.

| kind | title / detail | amount | status |
|---|---|---|---|
| `checked_in` | `Checked in` / room (only when there is no room history) | | |
| `room` | `Room assigned` / `Room 101, bed 2` (history starts 2026-10-26) | | |
| `due` | `Rent due for October 2026` | due | `paid`/`partial`/`unpaid` |
| `payment` | `Payment recorded` / `For October 2026 · UPI` | paid | fee status |
| `complaint` | complaint title / category | | complaint status |
| `checkout_request` | `Check-out requested` / `Preferred date 12 Nov 2026` | | request status |
| `checkout_decision` | `Check-out accepted` or `Check-out declined` / date or note | | |
| `checked_out` | `Checked out` | | |
| `upi_claim` | `UPI payment submitted` / `For October 2026 · UTR …` | claimed | claim status |

## 4. R3: two-factor
- No server change: the server never forced an owner to enrol a factor (no factor = allowed at aal1).
- An enrolled factor is still required (aal2), so optional 2FA keeps working.
- Remove only the app's owner-required gate. Biometric lock is app-only.

## 5. PG profile, photos, reviews, discovery (R5)

### 5.1 Storage: bucket `pg-media` (private, JPEG only, 2 MB max)
- Keys:
  - logo: `<hostel_id>/logo/<uuid v4 lowercase>.jpg`
  - covers: `<hostel_id>/cover/<uuid>.jpg`
- **Upload** (INSERT):
  - only the owner of that hostel, while it is writable;
  - a new random key every time (no overwrite, no delete policy);
  - at most 40 uploads a day per hostel.
- **Read**:
  - any signed-in account, for a listed PG whose plan is active or on trial;
  - the PG's owner, manager, wardens and residents, always.
- Use signed URLs (`createSignedUrl`), as for avatars.
- Files that are replaced or removed are deleted by the nightly erasure drain.
- Upload first, then save the keys with 5.2.

### 5.2 `ow_update_pg_profile(p_hostel_id, p_name, p_description, p_amenities text[], p_logo_path, p_cover_paths text[], p_listed boolean default null, p_latitude numeric default null, p_longitude numeric default null)` → `{hostel_id, name, description, amenities, logo_path, cover_paths, listed, latitude, longitude}`
- Owner only. It replaces name, description, amenities, logo and covers.
- Null keeps the current value for `p_listed` and for the pin (send both latitude and longitude, or neither).
- Rules are still set with `ow_update_hostel_rules`.
- Amenity keys: `wifi`, `ac`, `food`, `laundry`, `power_backup`, `parking`, `cctv`, `housekeeping`, `attached_bathroom`, `hot_water`, `gym`, `study_room`. Duplicates are dropped and the list is stored sorted.

| error | code / hint |
|---|---|
| `You can only edit your own PG.` | 42501 |
| `Subscription expired — hostel is read-only.` | 42501 |
| `Enter a PG name between 2 and 120 characters.` | hint `name` |
| `Keep the description under 500 characters.` | hint `description` |
| `Unknown amenity.` | hint `amenities` |
| `Upload the logo again.` | hint `logo` (bad key, or the file is not in the bucket) |
| `Add up to 6 cover photos.` / `Upload the cover photos again.` | hint `covers` |
| `Drop the pin on the map again.` | hint `location` |
| `Too many changes in a short time. Try again in a few minutes.` | *(limit)* 60 an hour |

### 5.3 Reviews
- **`st_save_review(p_rating integer, p_comment text default null)`** → `{review_id, hostel_id, rating, comment, updated_at}`
  - For a current tenant only. Creates or updates their one review of their current PG.
  - Errors:
    - `Only a current tenant can rate their PG.` (42501)
    - `Choose 1 to 5 stars.` (hint `rating`)
    - `Keep the review under 300 characters.` (hint `comment`)
    - *(limit)* `Too many changes in a short time. Try again in a few minutes.`
- **`st_my_review()`** → the same object for the current PG, or null.
- **`pg_review_list(p_hostel_id, p_limit default 20, p_offset default 0)`** → rows `{review_id, reviewer_name (first name only), rating, comment, created_at, updated_at, is_mine}`
  - Callers: the same people who can read the PG (5.1).
  - Error: `This PG is not available.`
- Owners can read reviews but cannot edit or delete them.
- Former tenants keep their review; only a current tenant can edit.
- The average and count are computed on the server.

### 5.4 Discovery (changed return shape, same parameters, errors and limits as round 2)
- `st_nearby_hostels(p_lat, p_lng)` and `st_search_hostels(p_query)` now also return:
  - `logo_path` (a pg-media key or null);
  - `rating_avg` (numeric, one decimal, or null);
  - `rating_count` (int);
  - `amenities` (text[]; show the first three).
- **`st_pg_profile(p_hostel_id)`** → `{hostel_id, name, property_type, gender_policy, locality, city, description, amenities, rules, logo_path, cover_paths, listed, rating_avg, rating_count, reviews: [up to 10 rows of pg_review_list]}`
  - Never includes owner contacts, address, pincode or the map pin.
  - Callers: anyone signed in, for a listed PG on an active or trial plan; the PG's own people, always.
  - Error: `This PG is not available.` (P0001)
  - "Request to join" stays `st_request_join`; staff applicants use §6.

## 6. Staff applicants (R8)
- **`stf_request_join(p_hostel_id, p_message text default null)`** → request object `{request_id, hostel_id, hostel_name, city, status, role_granted, message, decision_note, created_at, decided_at}`
  - For a staff applicant only. Search with `st_search_hostels` / `st_nearby_hostels`, which work for applicants.
  - The owner is notified (link `/owner/staff-requests`).
  - Errors:
    - `Only a staff sign-up account can ask to join a PG as staff.` (42501)
    - `Keep the message under 300 characters.` (hint `message`)
    - `This PG is not available.`
    - `You already have a pending request. Cancel it to ask another PG.`
    - *(limit)* `Too many requests today. Try again tomorrow.` (10 a day)
- **`stf_my_join_request()`** → the latest request object or null.
- **`stf_cancel_join_request()`** → the object. Error: `There is no pending request.`
- **`ow_staff_requests(p_hostel_id default null, p_status default 'pending')`** → rows `{request_id, hostel_id, hostel_name, user_id, full_name, phone, email, message, status, role_granted, created_at, decided_at, decision_note}`
  - Owner only; covers all their PGs when `p_hostel_id` is null.
  - `p_status = null` returns every status.
- **`ow_pending_staff_request_count()`** → int (owner).
- **`ow_decide_staff_request(p_request_id, p_accept boolean, p_role text default null, p_note text default null)`** → request object
  - Owner of that PG only (not wardens).
  - **Accept** with `p_role` `manager` or `warden`:
    - the account becomes that role with `staff_applicant = false`;
    - its PG is set and it gets `staff_hostel_access` (the existing multi-PG model; `owner_set_staff_hostels` works on it afterwards);
    - the person is notified.
  - **Decline**: the note is optional, and the person is notified.
  - Errors:
    - `Not allowed.` (42501, not an owner)
    - `Choose accept or decline.` (22023)
    - `This request is no longer available.`
    - `This request was already handled.`
    - `Keep the note under 300 characters.` (hint `note`)
    - `Choose Manager or Warden.` (22023, hint `role`)
    - `Subscription expired — hostel is read-only.`
    - `This person can no longer join: their account changed or was closed.`
    - `This PG already has 5 active wardens. Remove one from it first.` (or managers)
    - *(limit)* `Too many decisions in a short time. Try again in a few minutes.`
- After conversion the app should re-read `public.users` (or sign in again) and route to the staff shell.
- Staff applicants cannot use `st_request_join`: it fails with `Staff accounts ask to join a PG as staff.` (42501).

## 7. Check-out requests (R6)
Request object: `{request_id, hostel_id, student_id, preferred_date, reason, status 'pending'|'accepted'|'declined'|'cancelled'|'completed', checkout_date, decision_note, decided_at, completed_at, created_at}`.

- **`st_request_checkout(p_preferred_date date, p_reason text default null)`** → object
  - For a current tenant only.
  - The PG's wardens and owner are notified (links `/warden/checkouts`, `/owner/checkouts`).
  - Errors:
    - `Only a current tenant can request a check-out.` (42501)
    - `Choose a date from today up to 90 days ahead.` (hint `date`)
    - `Keep the reason under 300 characters.` (hint `reason`)
    - `You already have a check-out request.` (one pending or accepted at a time)
    - *(limit)* `Too many requests today. Try again tomorrow.`
- **`st_my_checkout_request()`** → the open request, or the latest one; null if none.
- **`st_cancel_checkout_request()`** → object (pending only). Error: `There is no pending check-out request.`
- **`wd_checkout_requests(p_hostel_id, p_status default null)`** → rows `{request_id, student_id, full_name, phone, room_number, bed_number, preferred_date, reason, status, checkout_date, decided_at, decision_note, completed_at, created_at}`
  - Callers: wardens and the owner of the PG.
  - Order: pending first, then accepted. Error: `Not allowed.`
- **`wd_decide_checkout_request(p_request_id, p_accept boolean, p_checkout_date date default null, p_note text default null)`** → object
  - Callers: a warden or the owner of the PG.
  - **Accept**:
    - the date defaults to the preferred date and must be between today −30 and today +90 days;
    - a date of today or earlier runs the existing vacate flow (`wd_vacate_student`) immediately, giving `completed`;
    - a later date gives `accepted`, and the vacate runs automatically at 00:05 IST on that date;
    - vacating unlinks a self-signed-up tenant's account, frees the bed and stops later dues.
  - **Decline**: the note is optional.
  - The tenant, the wardens and the owner are notified.
  - Errors:
    - `Choose accept or decline.`
    - `This request is no longer available.`
    - `This request was already handled.`
    - `Keep the note under 300 characters.`
    - `Choose a check-out date within 90 days.` (hint `date`)
    - `Subscription expired — hostel is read-only.` (immediate vacate only)
    - *(limit)* `Too many decisions in a short time. Try again in a few minutes.`
- **`ow_checkout_summary(p_hostel_id default null)`** → `{pending, scheduled, recent (residents checked out in 30 days), items: [{request_id, hostel_id, hostel_name, student_id, full_name, room_number, status, preferred_date, checkout_date, completed_at, created_at}] (up to 20: pending, accepted, completed in 30 days)}`
  - Owner only; covers all their PGs when `p_hostel_id` is null.
  - Errors: `Not allowed.` / `Hostel not found.`

## 8. Super Admin (R7)
- **`sa_signups(p_from date default null, p_to date default null, p_plan_status text default null, p_demo_status text default null, p_limit default 50, p_offset default 0)`** → rows `{user_id, full_name, phone, email, signup_source, signed_up_at, hostel_id, hostel_name, hostel_city, trial_start, trial_end, plan_status, plan_end, demo_id, demo_slot, demo_bed_band, demo_status, total_count}`
  - Lists self-signed-up owners, newest first. Dates are IST days, inclusive.
  - `plan_status`: `no_pg`, `trial`, `paid`, `manual` or `expired`.
  - `p_demo_status`: `none`, `requested`, `confirmed`, `done`, `no_show` or `cancelled`.
  - Mark a demo with the existing `sa_update_demo_request`.
  - Errors: `Not allowed.` / `Unknown plan status.` / `Unknown demo status.` (22023)
- **`sa_deleted_accounts(p_kind default null, p_from default null, p_to default null, p_limit default 50, p_offset default 0)`** → rows `{id, user_id, full_name, role, hostel_id, hostel_name, kind, reason, by_user_id, by_name, at, purged_at, can_purge, total_count}`
  - `kind`:
    - `owner_deleted_staff`
    - `self_request` (a pending "Request account deletion")
    - `self_deleted`
    - `sa_deleted`
    - `deleted` (another deactivation)
  - Names are kept as they were until a permanent delete, which turns them into `Deleted user`.
  - Self-deletion requests carry no reason; the reason is only in the notification sent at the time.
- **`sa_purge_account(p_user uuid, p_reason text)`** → `{user_id, role, purged: true}`
  - Erases:
    - the login (scrubbed, banned, its email and phone released);
    - profile PII;
    - photos and documents (queued for erasure);
    - roster PII (`Erased resident`);
    - complaints, leaves and visitors;
    - reviews and requests.
  - Keeps, pointing at `Deleted user`: fee payments, receipts, UPI claims, subscriptions and plan payments, and the audit trail (actor removed).
  - Errors:
    - `Not allowed.` (42501)
    - `Give a reason between 5 and 300 characters.` (hint `reason`)
    - `Account not found.`
    - `A Super Admin account cannot be deleted here.` (42501)
    - `This account was already permanently deleted.`
    - `This tenant is still checked in. Check them out of their PG first.`
    - `This owner still has residents in a PG. Check them out or suspend the PG first.`
    - *(limit)* `Too many deletions in a short time. Try again later.`

## 9. UPI payments (R9)
- **`ow_set_upi_settings(p_hostel_id, p_upi_vpa, p_payee_name)`** → `{hostel_id, upi_vpa, payee_name}`
  - Owner only. An empty VPA removes the settings.
  - The VPA is lower-cased and stripped of spaces, then must match `^[a-z0-9][a-z0-9._-]{1,254}@[a-z][a-z0-9.-]{1,63}$`.
  - Errors:
    - `You can only change your own PG.` (42501)
    - `Enter a valid UPI ID, like name@okhdfcbank.` (hint `upi_vpa`)
    - `Enter the payee name as your UPI app shows it.` (hint `payee_name`)
    - *(limit)* `Too many changes in a short time. Try again in a few minutes.`
- **`hostel_upi_settings(p_hostel_id default null)`** → `{hostel_id, hostel_name, upi_vpa, payee_name, updated_at}`, or null if not set up.
  - Callers: the owner, wardens and residents of the PG. Null means the caller's own PG.
  - Error: `Not allowed.`
- Pay with a UPI app:
  - Build `upi://pay?pa=<upi_vpa>&pn=<payee_name>&am=<amount>&cu=INR&tn=<PG name> rent <Month YYYY>&tr=<any short ref>` and launch it as an Android intent.
  - The result is never trusted. Then ask for the UTR.
- **`st_submit_payment_claim(p_amount numeric, p_period_month text 'YYYY-MM', p_utr text)`** → claim `{claim_id, hostel_id, student_id, period_month, amount, utr, upi_vpa, status 'pending'|'confirmed'|'rejected'|'cancelled', decision_note, decided_at, fee_payment_id, created_at}`
  - For a current tenant only. The UTR is uppercased and stripped of spaces.
  - The PG's wardens and owner are notified (links `/warden/payment-claims`, `/owner/payment-claims`).
  - Errors:
    - `Only a current tenant can report a payment.` (42501)
    - `This PG has not set up UPI payments yet.`
    - `Choose a month from your check-in month up to next month.` (hint `period_month`)
    - `Enter a valid amount.` (hint `amount`)
    - `Enter the UTR / transaction ID from your UPI app (usually 12 digits).` (hint `utr`)
    - `You have 5 payments waiting to be confirmed. Wait until they are checked.`
    - `This UTR has already been submitted.` (23505, hint `utr`; a UTR is unique per PG, apart from cancelled claims)
    - *(limit)* `Too many payments reported in a short time. Try again later.`
- **`st_my_payment_claims(p_limit default 20)`** → setof claim objects, newest first.
- **`st_cancel_payment_claim(p_claim_id)`** → claim (own pending only). Error: `This payment can no longer be cancelled.`
- **`wd_payment_claims(p_hostel_id, p_status default 'pending')`** → rows `{claim_id, student_id, full_name, room_number, period_month, amount, utr, upi_vpa, status, decision_note, decided_at, fee_payment_id, created_at}`
  - Callers: wardens and the owner of the PG.
  - `p_status = null` returns every status. Error: `Not allowed.`
- **`wd_decide_payment_claim(p_claim_id, p_confirm boolean, p_note text default null)`** → claim
  - Callers: a warden or the owner of the PG.
  - **Confirm** records the payment through `wd_record_payment` (mode `upi`, dated the day the claim was made, note `UPI UTR <utr>`), so dues and receipts update.
  - **Reject** needs a note.
  - The tenant is notified.
  - Errors:
    - `Choose confirm or reject.`
    - `This payment is no longer available.`
    - `This payment was already handled.`
    - `Keep the note under 300 characters.`
    - `Add a note saying why it was not found.` (hint `note`)
    - any `wd_record_payment` refusal, for example `That student has been checked out — no further payments can be recorded.`
    - *(limit)* `Too many decisions in a short time. Try again in a few minutes.`

## 10. Legal (R10)
- `legal_versions` gets a `2026-10-26` row (`2026-10-26-legal-version-round3.sql`).
- The consent gate asks for it once it is applied. The app's legal text and `docs/data-safety.md` must match it.

## 11. Notifications added
- `Check-out request`, `Check-out accepted`, `Check-out declined`, `Checked out`, `Check-out request declined`
- `New staff request`, `Staff request declined`, `Welcome to <PG>`
- `UPI payment to confirm`, `Payment confirmed`, `Payment not confirmed`

All are type `system`, except the last two, which are type `fee`. The `link` values are route hints the app may map.
