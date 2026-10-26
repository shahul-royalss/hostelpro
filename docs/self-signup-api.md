# Self sign-up, onboarding, join requests and plans: API contract (2026-10-25)

The app builds the 1.3.0 sign-up round from this file and `docs/self-signup-onboarding-spec.md`, and from nothing else.
The server side is `db/migrations/2026-10-25-self-signup-onboarding.sql` (RPCs, tables, storage) and the Edge Functions
`mobile-auth`, `subscription-order`, `owner-staff-account` and `razorpay-webhook`.

Every value the app sends is checked again on the server. The app never sends an amount, a role, a `hostel_id` to link, or a
storage path outside the caller's own folder. If it did, the server would refuse it.

---

## 0. Wire formats

### 0.1 RPCs (PostgREST, `supabase.rpc(name, params)`)
- They are called with the signed-in user's session. Parameter names are exactly the `p_*` names below.
- Errors arrive as `PostgrestException`:
  - **`message` is the user-facing sentence, so show it verbatim.**
  - `code` is the SQLSTATE: `P0001` is a validation or business refusal, `42501` means not allowed, `22023` is a bad parameter and `23505` is a duplicate.
  - `hint`: a validation error names the field in it, for example `name`, `pincode` or `slot_start`, so the app can put the message under that field. A rate-limit
    refusal (`app.spend`) has `hint = "Try again in about N seconds."`.
- `Not signed in.` (`42501`) means the session is missing or the profile is gone. The app routes to sign-in.

### 0.2 Edge Functions (`supabase.functions.invoke(name, body: {...})`, POST, JSON)
- Success: `{ "ok": true, "data": { ... }, "message"?: "..." }`.
- Failure: `{ "ok": false, "error": "<user-facing sentence>", "code"?: "<machine code>", "retryAfterSeconds"?: n }`.
  **Show `error` verbatim.** Branch on `code` when it is present, never on the wording.
- HTTP status: 400 invalid, 401 session expired, 403 refused, 404 not found, 409 conflict, 429 throttled
  (with `retryAfterSeconds` and a `Retry-After` header), 503 unavailable or not configured.
- `mobile-auth` is called before there is a session, with the anon key as the bearer, exactly as `signin` and `google` are today.
  Every other function is called with the user's access token.
- A 403 whose `error` contains `subscription`, `suspended`, `read-only` or `expired` is a billing refusal (existing convention).

Machine codes used in this round: `no_account`, `staff_refused`, `inactive`, `phone_in_use`, `not_configured`,
`already_linked`, `processing`, `payment_failed`.

---

## 1. `mobile-auth`: sign-in and sign-up (Flow 2)

Every success, sign-in or sign-up, returns the same body as today's `signin` and `google`:

```json
{ "ok": true, "data": { "accessToken": "...", "refreshToken": "...", "expiresAt": 1761400000 } }
```

The app installs the session with `supabase.auth.setSession(refreshToken)`. The session is aal1. An owner with a TOTP factor then takes
the existing `mfa` step, unchanged. After that the app routes by role, exactly as today.

`persona` is optional on all three provider actions. Allowed values are `"owner"` and `"tenant"`. Leave it out (or send `null`) to mean sign in only.
Send it only from the **Create your account** screen. Any other value is refused with
400 `Choose Owner or Tenant to create an account.` The persona is a hint for this one request. The server maps it to the role
(`owner` → owner, `tenant` → student). The database refuses every other role for a self-created account.

### 1.1 `{ "action": "google", "idToken": "<Google ID token>", "nonce": "<raw nonce>", "persona"?: "owner"|"tenant" }`
Credential Manager flow as today. `idToken` is 20–4096 characters and `nonce` is the raw nonce, 16–256 characters (the request asks Google for its SHA-256).
- An account already exists for the verified email: sign in, unchanged.
- There is no account and no persona: refused with `no_account`, and the app routes to the "Who are you?" screen.
- There is no account and a persona was sent: the account is created (email confirmed, no usable password, name from Google, no phone), then signed in.
  `users.signup_source = 'self_google'` and `email_verified_at` is set, because Google verified the address.

| HTTP | code | error (verbatim) | when |
|---|---|---|---|
| 400 | | `Google sign-in didn't go through. Please try again.` | bad, expired or unverified token, nonce mismatch |
| 400 | | `Choose Owner or Tenant to create an account.` | persona not on the allowlist |
| 403 | `no_account` | `No account yet — create one` | no account and no persona |
| 403 | `staff_refused` | `Staff and administrator accounts sign in with the login they were given, not with Google.` | manager, warden or super_admin |
| 403 | `inactive` | `This account has been deactivated. Contact your hostel owner.` | inactive or deleted |
| 403 | | `This address is on more than one account. Contact your administrator.` | data problem |
| 403 | | `Your account isn't set up yet. Contact your administrator.` | login without profile |
| 429 | | `Too many attempts. Please wait N minute(s) and try again.` | any limit below |
| 503 | | `Google sign-in isn't switched on yet. Sign in with your phone number or email and password.` | secret or provider off |
| 503 | | `Google sign-in is temporarily unavailable. Please try again in a minute, or sign in with your password.` | outage |
| 503 | | `Sign-up is temporarily unavailable. Please try again in a minute.` | account creation failed |

### 1.2 `{ "action": "facebook", "accessToken": "<Facebook user access token>", "persona"?: ... }`
The button stays hidden until the Facebook app ID exists. Do not add the Facebook SDK in this build. The server checks the token with Graph
`debug_token`: it must be valid and its `app_id` must be ours. It then reads `/me?fields=id,name,email`.

Resolution order:
1. The Facebook id is already linked: sign in.
2. Facebook returned an email that belongs to an account: the same refusals as Google apply (staff, inactive). Otherwise the id is linked and the account signs in.
3. Otherwise, with a persona, a new account is created with Facebook's email, or `fb-<id>@identity.apnivaas.invalid` when Facebook returns no email.
   An `@identity.apnivaas.invalid` address can never receive mail and is never shown as a contact.

Errors, in addition to the 403/429 rows above (with "Facebook" in place of "Google" in the staff sentence):

| HTTP | code | error |
|---|---|---|
| 503 | `not_configured` | `Facebook sign-in is not set up yet` |
| 400 | | `Facebook sign-in didn't go through. Please try again.` |
| 409 | `already_linked` | `This account is already linked to a different Facebook profile. Sign in with your password.` |
| 403 | | `This sign-in can't be used with this account.` |
| 503 | | `Facebook sign-in is temporarily unavailable. Please try again in a minute.` |

### 1.3 `{ "action": "truecaller", "code": "<authorization code>", "codeVerifier": "<PKCE verifier>", "persona"?: ... }`
The button stays hidden until the Truecaller client ID exists. Do not add the Truecaller SDK in this build. `codeVerifier` is 43–128 characters of
`[A-Za-z0-9-._~]`, and `code` is up to 2048 of the same characters.

Resolution order:
1. The Truecaller `sub` is already linked: sign in.
2. The verified phone is already on any account: **refused** (409 `phone_in_use`). It is never matched to that account.
3. Otherwise, with a persona, a new account is created: `tc-<sub>@identity.apnivaas.invalid`, the verified phone, and the Truecaller name.

| HTTP | code | error |
|---|---|---|
| 503 | `not_configured` | `Truecaller sign-in is not set up yet` |
| 400 | | `Truecaller sign-in didn't go through. Please try again.` |
| 409 | `phone_in_use` | `An account already uses this number — sign in with your password` |
| 503 | | `Truecaller sign-in is temporarily unavailable. Please try again in a minute.` |
| 403 | `no_account` / `staff_refused` / `inactive` | as in 1.1, with "Truecaller" in the staff sentence |

### 1.4 Rate limits (`mobile-auth`)
| key | limit | spent by |
|---|---|---|
| per IP | 240 per 5 min | every google, facebook or truecaller attempt (shared with password sign-in) |
| per identity (email, or provider id) | 8 per 15 min | every attempt (shared with password sign-in for the same email) |
| sign-up per IP | 30 per hour | only when an account is about to be created |
| sign-up per identity | 3 per day | only when an account is about to be created |

---

## 2. After sign-up: routing
- **Owner:** call `ow_plan_status` for each owned hostel, as today. An owner who owns no hostel and whose `users.hostel_id` is null goes to
  **Tell us about your PG**, which calls `ow_create_first_hostel`. Only self-signed-up owners can use that call. An owner created by the Super Admin who has no PG
  gets `Your PG is added by the platform administrator for this account.`
- **Tenant (role student):** when `users.hostel_id` is null, the app shows **Your details**, then **Find your PG**, then **Waiting**. On launch and on resume,
  it calls `st_my_join_request` to decide which.
- **Staff:** login screen only, with the line "Your owner creates staff accounts."

---

## 3. Profile, photo, documents (Flows 4, 6, 7). Any signed-in role.

### `me_update_profile(p_full_name text, p_phone text, p_gender text, p_date_of_birth date, p_emergency_contact_name text, p_emergency_contact_phone text)` → jsonb
- Updates the caller's own row only. Every parameter defaults to null, and **null means "leave unchanged"**.
- `p_gender` takes `male`, `female` or `other`. Phones are 10-digit Indian mobiles; `+91` and spaces are accepted.
- Returns `{full_name, phone, gender, date_of_birth, emergency_contact_name, emergency_contact_phone, avatar_path}`.
- Errors (P0001; `hint` names the field):
  - `Enter your full name (2 to 80 characters).`
  - `Enter a valid 10-digit mobile number.`
  - `Choose male, female or other.`
  - `Enter a valid date of birth.`
  - `Enter the emergency contact's name (2 to 80 characters).`
  - `Enter a valid 10-digit number for the emergency contact.`
  - `The emergency contact needs a different number from yours.`
- Limit: 30 an hour, `Too many profile changes. Try again in a while.`

### Avatars: bucket `avatars` (private)
1. Make a square JPEG of at most 512 px. The bucket accepts only `image/jpeg`, at most 1 MB.
2. Upload it to **`<auth uid>/avatar/<random uuid v4, lowercase>.jpg`** with `upsert: false`. Any other path is refused by the storage policy.
   You can upload at most 30 objects a day per bucket. There is no UPDATE or DELETE from the client: a key is never reused.
3. Call `me_set_avatar(p_path text)` → `{avatar_path}`. Passing `p_path = null` removes the photo. The old file is erased by the server.
   - `That photo could not be used. Please try again.` means the path shape or owner is wrong.
   - `The photo did not finish uploading. Please try again.` means the object is missing.
   - Limit: 20 an hour, `Too many photo changes. Try again in a while.`
4. To display a photo: `storage.from('avatars').createSignedUrl(avatar_path, 60)`. `avatar_path` is on `public.users`. Reads are allowed for:
   - the user themselves;
   - the Super Admin;
   - the owner of the user's PG, or of any PG a staff member has access to;
   - the warden of the user's PG;
   - a manager of the PG, for staff and owner photos only;
   - the owner and wardens of a PG the user has a **pending** join request with.

   When the signed URL is refused, show initials.

### Identity documents: bucket `identity-documents` (private)
1. Upload **`<auth uid>/document/<random uuid v4>.<jpg|png|webp|pdf>`**. The bucket accepts `image/jpeg`, `image/png`, `image/webp` and `application/pdf`, at most 5 MB, with `upsert: false`.
   Delete the phone copy after upload.
2. Call `me_add_document(p_kind text, p_path text)` → `{id, kind, storage_path, created_at}`. `p_kind` is one of
   `aadhaar_masked`, `pan`, `driving_licence`, `voter_id`, `passport`, `college_or_work_id` or `other`.
   - `Choose the type of document.` (`hint` = `kind`)
   - `That file could not be used. Please try again.`
   - `The file did not finish uploading. Please try again.`
   - `You can keep up to 10 documents. Delete one first.`
   - Limit: 20 a day, `Too many uploads today. Try again tomorrow.`
3. To list your own documents: `from('user_documents').select('id, kind, storage_path, created_at').order('created_at', desc)`. RLS lets you read your own rows,
   and the rows of anyone the avatar rules above allow for documents. Those rules are stricter: wardens see residents only, and managers see none.
4. `me_delete_document(p_document_id uuid)` → `{id, deleted: true}`. Only your own documents. The file is erased by the server.
   - `That document is no longer there.`
   - Limit: 30 an hour, `Too many changes. Try again in a while.`
5. To view a document: `createSignedUrl(storage_path, 60)`. **Signed URLs live 60 seconds.**

Copy for the screen: "Upload a **masked** Aadhaar (download it from the UIDAI site with only the last 4 digits showing) or another ID."

### `me_delete_account()` → `{deleted: true}`
- Only for a self-signed-up account that has no PG: an owner with no hostel, or a tenant who is not linked and has no live roster row. It deletes the login.
- Errors:
  - `Your account is part of a PG, so its deletion goes through your PG. Use "Request account deletion".` The app then shows the existing deletion request flow.
  - `Your account is still linked to records in a PG. Ask the PG owner to remove you, then try again.`
- Limit: 3 a day, `Please wait a while before trying again.`

---

## 4. Owner onboarding (Flow 3)

### `ow_create_first_hostel(p_name text, p_property_type text, p_gender_policy text, p_address text, p_locality text, p_city text, p_pincode text, p_floors integer, p_rooms integer, p_beds_per_room integer, p_latitude numeric default null, p_longitude numeric default null)` → `{hostel_id, name, trial_start, trial_end}`
- Who may call: a self-signed-up owner with no hostel, past the MFA gate if a factor is enrolled.
- It creates the PG, a **trial** plan from today to today + 30 days, links the owner, notifies the Super Admins, and audits.
- Values:
  - `p_property_type`: `pg`, `hostel`, `co_living` or `flats`.
  - `p_gender_policy`: `boys`, `girls` or `coed`.
  - `p_pincode`: 6 digits, not starting with 0.
  - `p_floors`: 1–50. `p_rooms`: 1–500. `p_beds_per_room`: 1–20.
  - Latitude and longitude are optional and come together. They must be inside India; coarse accuracy is enough.
- Errors (`hint` names the field for the validation ones):
  - `Only an owner account can add a PG here.` (42501)
  - `Your PG is added by the platform administrator for this account.`
  - `Verify your email address before adding a PG.` This applies only to an owner whose real address is unverified (Facebook with an email). Show the existing verify-email banner.
  - `Enter the PG name (2 to 120 characters).`
  - `Choose PG, Hostel, Co-living or Flats.`
  - `Choose Boys, Girls or Co-ed.`
  - `Enter the full address (5 to 500 characters).`
  - `Enter the locality (2 to 120 characters).`
  - `Enter the city (2 to 80 characters).`
  - `Enter a valid 6-digit pincode.`
  - `Floors must be between 1 and 50.`
  - `Rooms must be between 1 and 500.`
  - `Beds per room must be between 1 and 20.`
  - `That map pin is outside India. Try again or skip it.`
  - `Your PG is already set up.` This also covers a double tap: the app treats it as success and refreshes.
- Limit: 5 a day, `Too many attempts. Try again tomorrow.`
- Then show the celebration sheet: "Your first month is free", with `trial_end`.

### Book a demo
- **`ow_book_demo(p_name text, p_phone text, p_pg_name text, p_city text, p_bed_band text, p_slot_start timestamptz)`** → `{id, slot_start, status: 'requested'}`. Owner only.
  - `p_bed_band` is one of `1-20`, `21-50`, `51-100` or `100+`.
  - `p_slot_start` is an exact hour from 10:00 to 18:00 **Asia/Kolkata**, within the next 14 days and at least 2 hours from now. Send ISO-8601 with `+05:30`.
  - Errors:
    - `Only an owner account can book a demo.`
    - `Enter your name (2 to 80 characters).`
    - `Enter a valid 10-digit mobile number.`
    - `Enter the PG name (2 to 120 characters).`
    - `Enter the city (2 to 80 characters).`
    - `Choose how many beds your PG has.`
    - `Pick a day in the next two weeks and an hourly time between 10 AM and 6 PM, at least two hours from now.` (`hint` = `slot_start`)
    - `You already have a demo booked for <DD Mon, HH:MI AM>. Cancel it to pick another time.`
  - Limit: 5 a day, `Too many demo requests today. Try again tomorrow.`
- **`ow_my_demo_request()`** → `{id, slot_start, status, name, phone, pg_name, city, bed_band, created_at}` for the open request, or `null`.
- **`ow_cancel_demo_request()`** → `{id, status: 'cancelled'}`.
  - Errors: `You have no demo booked.`, `Only an owner account can do that.`
  - Limit: 10 a day.
- **Super Admin:**
  - `sa_demo_requests(p_status text default null, p_limit int default 50, p_offset int default 0)` returns rows
    `(id, owner_user_id, owner_name, owner_email, hostel_id, name, phone, pg_name, city, bed_band, slot_start, status, note, created_at, handled_at)`.
  - `sa_update_demo_request(p_id uuid, p_status text, p_note text default null)` → `{id, status}`. Status is one of `requested`, `confirmed`, `done`, `no_show` or `cancelled`.
  - Errors: `Not allowed.`, `Choose a valid status.`, `Keep the note under 500 characters.`, `Demo request not found.`

---

## 5. Tenant: finding and joining a PG (Flow 4)

The two search RPCs return the same row shape: **`(hostel_id uuid, name text, property_type text, gender_policy text, locality text, city text, distance_km numeric)`**.
They never return an address or owner contact. They list only PGs that are `listed` and whose plan is active or on trial, at most 25 rows. The caller's location is never stored.
Both are for tenant accounts only and share a limit of 120 an hour (`Too many searches. Try again in a few minutes.`).

- **`st_nearby_hostels(p_lat numeric, p_lng numeric)`** searches about 50 km and sorts by `distance_km`.
  - `Your location could not be read. Search by name or city instead.`
  - `Only a tenant account can search for PGs.`
- **`st_search_hostels(p_query text)`** matches the name or city. `distance_km` is null.
  - `Type at least 2 letters of the PG name or city.`
- **`st_request_join(p_hostel_id uuid, p_message text default null)`** → `{request_id, hostel_id, hostel_name, status: 'pending'}`. It notifies the owner and wardens.
  - Requirements: a phone on the profile **and a profile photo**, no PG, and no other pending request.
  - Errors:
    - `Only a tenant account can ask to join a PG.`
    - `You are already part of a PG. Ask your PG owner to remove you before joining another.`
    - `You already asked to join <PG>. Cancel that request to ask another PG.`
    - `Add your phone number in Your details first.`
    - `Add a profile photo before sending a request.`
    - `Keep the message under 300 characters.`
    - `This PG is not taking requests right now.`
  - Limit: 10 a day, `Too many requests today. Try again tomorrow.`
- **`st_cancel_join_request()`** → `{request_id, status: 'cancelled'}`.
  - Errors: `You have no pending request.`, `Only a tenant account can do that.`
  - Limit: 10 a day.
- **`st_my_join_request()`** → `{request_id, hostel_id, hostel_name, status, message, decision_note, created_at, decided_at}` or `null`.
  - A pending request comes first. Otherwise it returns the latest request decided within 30 days.
  - `status` is one of `pending`, `accepted`, `declined`, `cancelled` or `expired`.
  - Use it for the **Waiting for <PG> to accept** screen. Refresh on resume and on push.
  - `accepted`: refresh the profile, since `users.hostel_id` is now set, and route to the tenant home.
  - `declined`: show `decision_note` and let them search again.

### Owner and warden side
- **`ow_join_requests(p_hostel_id uuid default null, p_status text default 'pending', p_limit int default 50, p_offset int default 0)`** returns rows
  `(request_id, hostel_id, hostel_name, user_id, full_name, phone, email, avatar_path, gender, date_of_birth, emergency_contact_name, emergency_contact_phone, message, status, created_at, decided_at, decision_note, documents jsonb)`.
  - `documents` is `[{id, kind, storage_path, created_at}]`. Open each through a 60-second signed URL from `identity-documents`. The avatar comes from `avatars`.
  - `email` is null for unreachable addresses.
  - `p_status` is one of `pending`, `accepted`, `declined`, `cancelled`, `expired` or `all`.
  - Errors: `Not allowed.`, `Unknown status.`
- **`ow_pending_join_request_count()`** → integer. Use it for the badge on the People tab and the owner home attention list.
- **`ow_decide_join_request(p_request_id uuid, p_accept boolean, p_note text default null)`**:
  - Accept → `{request_id, status: 'accepted', student_id}`. It creates the roster row with no room and links the account.
  - Decline → `{request_id, status: 'declined'}`.
  - Either way the tenant is notified.
  - Errors:
    - `This request is no longer available.`
    - `This request was already handled.`
    - `Keep the note under 300 characters.`
    - `Subscription expired — hostel is read-only.`
    - `This person can no longer join: they are already in a PG or their account was closed.`
    - `This person has no phone number on their profile. Ask them to add it and send the request again.`
    - `A resident with this phone number is already registered in a PG.`
  - Limit: 120 an hour.
  - The warden fills in the room and rent later through the existing edit flows.
- **Leaving:** the existing `wd_vacate_student(p_student_id)` flow, unchanged for the app. For a self-signed-up tenant it now also clears the account's
  `users.hostel_id`, and the account stays active, so they can ask another PG. A tenant cannot leave by themselves.

---

## 6. Owner deletes a manager or warden (Flow 5): `owner-staff-account`

`POST { "action": "delete", "userId": "<uuid>" }`, with the owner's access token.

The deletion is permanent:
- The profile becomes "Deleted staff member", so history keeps its links.
- The login is removed: the email and phone are free again, and every session and factor is ended.
- Documents and photo are erased.

After this, the old login answers "No account found", and the person can later sign up as an owner or tenant.

| HTTP | error |
|---|---|
| 200 | `data: {user_id, role, already_deleted}`, message `Account deleted.` (`already_deleted: true` on a repeat) |
| 404 | `Staff member not found.` (not a manager or warden in one of the caller's PGs; "not yours" and "missing" read the same) |
| 400 | `You cannot delete your own account here.` |
| 403 | `You don't have permission to do that.` (not an owner) / `Verify your email address before creating accounts or changing anyone's login. …` (owner with an unverified real address) |
| 429 | `Too many account operations in a short time. Try again in Ns.` (20 an hour per owner) |

The dialog must say the deletion is permanent. After success, refresh the staff list.

---

## 7. Plans and payment (Flow 8)

### `plan_catalog()` (any signed-in user)
Returns rows `(plan_id, name, months, bonus_months, total_months, price_per_month, amount, amount_paise, saving_vs_monthly, sort_order)`:

| plan_id | months | bonus | total months | per month | amount |
|---|---|---|---|---|---|
| `monthly` | 1 | 0 | 1 | ₹1,099 | ₹1,099 |
| `quarterly` | 3 | 0 | 3 | ₹999 | ₹2,997 |
| `yearly` | 12 | 1 | 13 | ₹959 | ₹11,508 |

`saving_vs_monthly` is in rupees, against the monthly price × total months. Display these numbers only: the app never sends an amount.

### `ow_plan_status(p_hostel_id uuid)` (the owner of that hostel, or the Super Admin)
Returns `{hostel_id, hostel_name, hostel_status, state, plan_kind, start_date, end_date, days_left, writable, last_payment}`.
- `state` is one of:
  - `trial`: "Trial ends <end_date>".
  - `active`.
  - `expiring`: active with 15 days or fewer left.
  - `expired`: "Your plan has ended — choose a plan".
- `plan_kind` is `manual`, `trial` or `paid`.
- `last_payment` is `{plan_id, amount_paise, paid_at, period_start, period_end}` or null.
- Error: `Hostel not found.` (42501).

A trial counts as an active plan everywhere else: writes, the cron and the Super Admin screens.

### `subscription-order` (Edge Function, owner token)
**`{ "action": "create", "hostelId": "<uuid>", "planId": "monthly"|"quarterly"|"yearly" }`**

Returns:

```json
{ "order_id": "order_…", "key_id": "rzp_…", "amount_paise": 109900, "amount_rupees": 1099, "currency": "INR",
  "plan_id": "monthly", "plan_name": "Monthly", "months": 1, "bonus_months": 0,
  "hostel_id": "…", "hostel_name": "…", "test_mode": true,
  "prefill": { "name": "…", "email": "… or null" } }
```

Open Razorpay checkout with the existing plugin, `order_id`, `key_id`, `amount_paise` and UPI preferred. Nothing opens a browser.

**`{ "action": "verify", "orderId": "order_…", "paymentId": "pay_…", "signature": "<razorpay_signature>" }`**

Call it right after the checkout success callback, with the three values the SDK returns. The server:
1. checks the HMAC signature;
2. fetches the payment from Razorpay, which must be captured or authorized, for this order, for this exact amount;
3. extends the plan. The new end is the later of the current end and today, plus the plan months (+1 for yearly).

It returns `{outcome: 'paid'|'duplicate', hostel_id, plan_id, period_start, period_end}`. Then refresh `ow_plan_status`.
- `duplicate` means it was already activated, usually by the webhook. Treat it as success.
- If verify fails, or the app dies after checkout, the Razorpay webhook activates the plan anyway, so on resume the app just re-reads `ow_plan_status`.

| action | HTTP | code | error |
|---|---|---|---|
| both | 503 | `not_configured` | `Online plan payment isn't set up yet. Please try again later.` |
| both | 503 | | `Plan payment is temporarily unavailable. Please try again in a minute.` |
| both | 429 | | `Too many payment attempts. Please wait N minute(s) and try again.` (create 6 an hour, verify 30 an hour, per owner) |
| create | 400 | | `Choose a plan.` |
| create | 404 | | `Hostel not found.` (not the caller's) |
| create | 403 | | `This hostel is suspended. Contact support.` |
| create | 400 | | `The plan price changed. Please try again.` |
| verify | 404 | | `Payment not found.` (order not the caller's) |
| verify | 400 | | `We could not confirm this payment. If money left your account, your plan will switch on automatically within a few minutes.` |
| verify | 409 | `processing` | `Your payment is still processing. Your plan will switch on automatically once it completes.` |
| verify | 409 | `payment_failed` | the "could not confirm" sentence |
| verify | 400 | | `Order already settled by a different payment.` / `Paid amount does not match the order.` (should never happen; show and stop) |

A checkout "success" with no verified signature activates nothing.

---

## 8. Notifications this round adds (`public.notifications`)
| type | title | to |
|---|---|---|
| `system` | `New PG signed up` | Super Admins |
| `system` | `New demo request` | Super Admins |
| `system` | `New join request` | owner and wardens of the PG |
| `system` | `Request accepted` / `Request declined` | the tenant |
| `system` | `You have left <PG>` | a self-signed-up tenant who was vacated |
| `subscription` | `Plan activated` | the owner |

---

## 9. Server configuration the app depends on
- Edge Function secrets (never in the app):
  - `GOOGLE_WEB_CLIENT_ID` (existing).
  - `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET`: the platform account, the same as rent.
  - `RAZORPAY_WEBHOOK_SECRET` (existing). The webhook must subscribe to `order.paid` as well as `payment.captured`.
  - `FACEBOOK_APP_ID` and `FACEBOOK_APP_SECRET`: when unset, `facebook` answers `not_configured`.
  - `TRUECALLER_CLIENT_ID`: when unset, `truecaller` answers `not_configured`. Optional: `TRUECALLER_TOKEN_URL` and `TRUECALLER_USERINFO_URL`.
- The app may hide the Facebook and Truecaller buttons by build flag, or by calling the action once and hiding the button on `not_configured`.
