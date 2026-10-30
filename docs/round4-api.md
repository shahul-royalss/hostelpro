# Round 4 API (R4.1, R4.2)

Migration `db/migrations/2026-10-31-round4.sql` (undo `.down.sql`, tests `.test.sql`). All RPCs are `SECURITY DEFINER`, `search_path ''`, callable by `authenticated` (never `anon`). Errors: `42501` means not allowed, `P0001` means a user-facing message; `hint` names the form field where one applies. Money is in rupees (`numeric`, 2 decimals).

## Schema

- `public.students.rent_due_day smallint` (1 to 28, nullable). `NULL` means the PG's `hostels.rent_due_day` (5 unless the owner changed it). Readable through the existing `students` select. Rent reminders (`app.send_rent_reminders`) and `st_timeline` now use `coalesce(students.rent_due_day, hostels.rent_due_day)`.
- **Rent unset** means `students.monthly_fee = 0`.

## Rules the server now enforces

- **No dues while rent is unset.** `rpc_fee_ledger` leaves out a rent-unset resident (unless that month already has a fee row). `rpc_student_fee_months` returns no rows for them, so `st_timeline` shows no "Rent due". `wd_record_payment` refuses (message below), which means a UPI claim cannot be confirmed either. Razorpay already said "There is nothing to pay for this month."
- **A rent change applies from the next unbilled month.** A month is *billed* when it has a fee row, or when its due date (never before check-in) is before today. A trigger on `students.monthly_fee` (`students_rent_freeze`) runs on every path, including direct table updates. Before a rent change takes effect, it writes each billed month that has no fee row yet as a fee row at the **old** rent (`amount_paid 0`). Existing rows are never changed, so paid history stays as it was. Going from unset (0) to a value bills from the check-in month.

## `ow_decide_join_request(p_request_id uuid, p_accept boolean, p_note text = null, p_monthly_fee numeric = null, p_due_day integer = null) → jsonb`

This replaces the 3-argument version. Old calls `(id, accept[, note])` still work and leave the rent unset. Callers are the owner or a warden of the request's PG.
- `p_monthly_fee` (accept only): 1 to 10,00,000. The UI should require it. `p_due_day`: 1 to 28, or null to follow the PG's day; the UI should prefill 5. Both are saved on the new roster row in the same transaction as the accept.
- Returns, on accept: `{request_id, status:'accepted', student_id, monthly_fee, rent_due_day}`. On decline: `{request_id, status:'declined'}`.
- New errors (P0001): `Enter the monthly rent (₹1 to ₹10,00,000).` (hint `monthly_fee`) and `Choose a due day from 1 to 28.` (hint `due_day`). If either fires, nothing is accepted. All earlier errors are unchanged.

## `wd_residents_needing_rent(p_hostel_id uuid = null) → setof (student_id uuid, hostel_id uuid, hostel_name text, full_name text, phone text, photo_url text, room_number text, bed_number int, date_of_joining date, has_account boolean)`

This lists residents (not vacated, not erased) whose rent is unset in PGs where the caller is owner or warden, newest first, at most 200. Null means all of the caller's PGs. Use it for the warden home card, **"Set rent for N new residents"**.
- `42501 Not allowed.`: the caller is not an owner, warden or Super Admin, or `p_hostel_id` is not one of their PGs.

## `wd_set_tenant_rent(p_student_id uuid, p_monthly_fee numeric, p_due_day integer = null) → jsonb`

Sets or changes a resident's monthly rent, and optionally the due day (null keeps the current one). Callers are the owner or a warden of the resident's PG. Rate limit: 120 per hour. Audited as `student.rent.set`.
- Returns `{student_id, monthly_fee, rent_due_day, applies_from:'YYYY-MM'}`. `applies_from` is the first month billed at the new rent. Show it, for example "New rent applies from December 2026".
- Errors: `P0001 Resident not found.` · `42501 Not allowed.` · `P0001 This resident has checked out.` · `P0001 Enter the monthly rent (₹1 to ₹10,00,000).` (hint `monthly_fee`) · `P0001 Choose a due day from 1 to 28.` (hint `due_day`) · `42501 Subscription expired — hostel is read-only.` · rate limit `Too many rent changes in a short time. Try again in a few minutes.`

## `wd_update_tenant_profile(p_student_id uuid, p_full_name, p_phone, p_email, p_gender, p_date_of_birth date, p_emergency_contact_name, p_emergency_contact_phone, p_address, p_city, p_pincode) → jsonb`

Every parameter except `p_student_id` is `text = null` unless typed otherwise. Call it with named arguments. `null` keeps a value; `''` clears an optional one (full name and phone cannot be cleared). Callers are the owner or a warden of the resident's current PG (Super Admin too). The resident must not be vacated. Rate limit: 60 per hour. Audited as `student.profile.update` with the changed field names.
- Writes the roster row (`full_name`, `phone`, `email` (the shown email), `guardian_name`/`guardian_phone` (the emergency contact), `permanent_address` (address)). For a resident with an app account, it also writes `users` (`full_name`, `phone`, `gender`, `date_of_birth`, `emergency_contact_*`, `city`, `pincode`).
- It never changes the role, the PG, the login email, or the sign-in identifier. A phone-login resident keeps signing in with the original number.
- Returns `{student_id, full_name, phone, email, gender, date_of_birth, emergency_contact_name, emergency_contact_phone, address, city, pincode, has_account, changed:[field…]}`. To prefill, read the roster row (`students`), plus `users` (`gender, date_of_birth, city, pincode, emergency_contact_*`) by `students.user_id`. Owners and wardens can already select both under RLS.
- Validation copies `me_update_profile`. Errors (P0001, hint = field):
  - `Enter the full name (2 to 80 characters).` (`full_name`)
  - `Enter a valid 10-digit mobile number.` (`phone`)
  - `Enter a valid email address.` (`email`)
  - `Choose male, female or other.` (`gender`)
  - `Enter a valid date of birth.` (`date_of_birth`, age 10 to 100)
  - `Enter the emergency contact's name (2 to 80 characters).` (`emergency_contact_name`)
  - `Enter a valid 10-digit number for the emergency contact.` (`emergency_contact_phone`)
  - `The emergency contact needs a different number from the resident's.` (`emergency_contact_phone`)
  - `Enter the full address (5 to 500 characters).` (`address`)
  - `Enter the city (2 to 80 characters).` (`city`)
  - `Enter a valid 6-digit pincode.` (`pincode`)
  - `Another resident or account already uses this phone number.` (`phone`)
  - `This resident has no app account, so gender, date of birth, city and pincode cannot be saved.` (hint = the first such field; hide those four fields when `has_account` is false)
- Other errors: `P0001 Resident not found.` · `42501 Not allowed.` · `42501 Not signed in.` · `42501 Subscription expired — hostel is read-only.` · rate limit `Too many profile changes. Try again in a while.`

## Changed: `wd_record_payment`

New error, raised before anything is written: `P0001 Set this resident's monthly rent before recording a payment.` (hint `monthly_fee`). It fires when the rent is unset and that month has no fee row with an amount due.
