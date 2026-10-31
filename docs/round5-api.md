# Round 5 contract addendum (2026-10-31)

Builds on docs/self-signup-api.md, docs/round3-api.md and docs/round4-api.md. Migration:
`db/migrations/2026-10-31-round5.sql` (+ `.down.sql`, `.test.sql`).

## R5.1 Staff sign in with Google and Facebook
- `app.external_signin_allowed(p_user)` returns true for:
  - owner, tenant (`student`), manager, warden;
  - an address with no profile yet (a new sign-up).
- It returns false for Super Admin only. Super Admin signs in with a password and a second factor.
- Owner-created manager and warden accounts (`signup_source = 'admin'`) were refused before. They are now allowed.
- Google and Facebook prove the address. That is no weaker than the email password reset these accounts already have.
- The same function guards both:
  - `auth.identities` (Google), through `app.guard_external_identity`;
  - `public.external_identities` (Facebook), through `app.guard_external_identity_link`.
- The trigger message is now `Administrator accounts sign in with their password.`
- mobile-auth's refusal sentence (`GOOGLE_STAFF`) says the same.
- Sign-up still never creates staff. A staff sign-up is an applicant with no access until an owner accepts it (round 3, §6).

## R5.2 Free beds on a PG's page
`st_pg_profile(p_hostel_id)` returns three new keys. The parameters, callers and errors are unchanged.

| key | type | meaning |
|---|---|---|
| `beds_total` | int | Every bed in the PG. |
| `beds_free` | int | Beds with `status = 'free'`. |
| `free_by_sharing` | `[{sharing, free}]` | Free beds by room capacity, smallest sharing first. A room type with nothing free is left out. |

- These are counts only. They never say which room a bed is in or who is in it.
- The page still has no owner contact, address, pincode or map pin.

## App-only changes in this round
None of these need anything new from the server:
- **Reset link:** the app now handles `AuthChangeEvent.passwordRecovery`. The router holds `/reset-password` until the new password is saved. The app then signs out everywhere, globally, so the person signs in again with the new password. A second factor is verified first when GoTrue asks for aal2.
- **Owner:**
  - assigns or moves a bed by updating `students.bed_id`, which the `students_update` policy already allows owners to do;
  - records a payment with `wd_record_payment`, which already allows the owner.
- **Tenant pay button:** tenants see one "Pay now". It uses the owner's UPI ID through UPI apps when the owner has set one, and Razorpay checkout otherwise.
