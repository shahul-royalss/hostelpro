-- ═════════════════════════════════════════════════════════════════════════════════════════
-- EMAIL VERIFICATION — a proof that is actually a proof
-- ═════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT WAS WRONG ──────────────────────────────────────────────────────────────────────
--
-- Every account-creation path passed `email_confirm: true` to auth.admin.createUser:
-- supabase/functions/_shared/accounts.ts, lib/auth/accounts.ts, db/seed.ts and
-- scripts/rotate-super-admin.mjs. So `auth.users.email_confirmed_at` was stamped at creation
-- for all 27 accounts this project has ever had, and not one confirmation email was ever sent.
-- The column therefore recorded nothing: it said "somebody typed this address", never "the
-- person who owns this address answered".
--
-- ── WHY THE FIX IS NOT "STOP PASSING email_confirm" ─────────────────────────────────────
--
-- Measured against the live project on 2026-08-31:
--
--     GET https://nimxvgzscbanhtvgnjll.supabase.co/auth/v1/settings
--       -> {"mailer_autoconfirm": false, ...}
--
-- `mailer_autoconfirm: false` means the project has "Confirm email" ON, and GoTrue refuses a
-- password grant for a user whose email_confirmed_at is null (error_code
-- `email_not_confirmed`). Creating accounts unconfirmed would therefore NOT merely nag the new
-- user — it would make the temporary password unusable until they clicked a link. Three things
-- follow from that, and together they decide the design:
--
--   1. The hostel desk breaks. A warden registers a resident standing in front of them and
--      hands over a login. "It will work once you check your email" is not a handover.
--   2. A typo is unrecoverable. If the address is wrong the code goes to nobody, the account
--      can never sign in, and the only person who could fix it is the staff member who created
--      it — who, under a strict rule, may themselves be locked out. That is a circular lockout
--      with no way back that does not involve the Supabase dashboard.
--   3. A resident registered WITHOUT an email gets the synthetic login
--      <digits>@student.hostelpro.local. No mail server on earth accepts that domain. A rule
--      that demands a proof which cannot be produced is a permanent lockout, not a policy.
--
-- ── WHAT THIS MIGRATION DOES INSTEAD ────────────────────────────────────────────────────
--
-- It moves the proof to a column that means what it says, and leaves GoTrue's flag doing the
-- only job it can still do honestly: letting the temporary password work.
--
--     auth.users.email_confirmed_at   = "GoTrue will accept a password grant for this user"
--     public.users.email_verified_at  = "the person holding this address entered a code we
--                                        emailed to it"
--
-- email_verified_at starts NULL for every account that has ever existed — including the eight
-- live ones — so "everyone has to verify" is true from the first deploy without a backfill and
-- without anyone losing access on the day it ships.
--
-- WHO IS REQUIRED TO VERIFY is decided by the ADDRESS, not by the role. Any account whose
-- login address can receive mail owes a proof: owner, manager, warden, super admin, and a
-- resident whose warden collected a real email (see createStudentAuthUser — a real address
-- becomes that student's login id). The only exemption is the reserved phone-mapping
-- namespace, which exists precisely because that resident gave no address at all.
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────
--
-- No RLS policy is changed. An unverified staff account can still read and run the PG; what it
-- cannot do is MINT ANOTHER ACCOUNT (enforced in the three account-creation Edge Functions via
-- requireVerifiedEmail), which is the one action where an unproved address turns into
-- credentials in a stranger's inbox. app.email_verification_owed() is defined here so a future
-- policy can gate on it in one line, and is deliberately not wired into one today.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. THE COLUMN
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.users add column if not exists email_verified_at timestamptz;

comment on column public.users.email_verified_at is
  'When the account holder proved control of users.email by entering an emailed one-time code. '
  'NULL means unproved. Written ONLY by the verify-email-code Edge Function with the service '
  'role (app.users_update_guard refuses every other writer), and reset to NULL by that same '
  'trigger whenever the address changes.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. WHICH ADDRESSES CAN ACTUALLY BE PROVED
-- ─────────────────────────────────────────────────────────────────────────────

-- Mirrors isStudentLoginEmail() in supabase/functions/_shared/validate.ts and
-- studentLoginDomain in nivora_app/lib/core/auth/auth_controller.dart. Three copies of one
-- string is two too many, but the alternative is a cross-language import that does not exist;
-- the constant is at least named in all three places so one grep finds them together.
create or replace function app.email_is_reachable(p_email text) returns boolean
language sql immutable set search_path = public as $$
  select p_email is not null
     and length(btrim(p_email)) > 0
     and lower(btrim(p_email)) not like '%@student.hostelpro.local'
$$;

comment on function app.email_is_reachable(text) is
  'False for the reserved <digits>@student.hostelpro.local phone-mapping namespace, which no '
  'mail server accepts. Demanding proof of an unreachable address is a permanent lockout.';

-- Does this account still owe a proof? Defaults to the caller, so a future policy can write
-- `app.email_verification_owed()` with no argument.
create or replace function app.email_verification_owed(p_user uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users u
    where u.id = coalesce(p_user, auth.uid())
      and u.email_verified_at is null
      and app.email_is_reachable(u.email)
  )
$$;

comment on function app.email_verification_owed(uuid) is
  'True when the account has a reachable address it has not proved. False for a verified '
  'account AND for a resident whose only login id is the synthetic phone address.';

grant execute on function app.email_is_reachable(text) to authenticated, service_role;
grant execute on function app.email_verification_owed(uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. THE FLAG IS NOT SELF-SERVICEABLE
-- ─────────────────────────────────────────────────────────────────────────────
--
-- users_update in db/rls-policies.sql admits `id = auth.uid()`, and this trigger's tail
-- explicitly lets the account holder edit full_name, phone, email and must_change_password.
-- Without the two rules added below, `update users set email_verified_at = now()` through
-- PostgREST would be a one-line bypass of the entire feature, and
-- `update users set email = 'attacker@example.com'` would carry a proof earned for one address
-- onto another.
--
-- Both new rules sit ABOVE the super-admin early return on purpose. The service role reaches
-- this path only from verify-email-code, which has just watched GoTrue accept the code; a
-- super admin editing a row through PostgREST has watched nothing, and there is no reason for
-- a human — any human — to be able to hand out a proof by hand.
create or replace function app.users_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_manages_target boolean;
begin
  -- Changing the address invalidates any proof attached to the old one. This fires for EVERY
  -- writer including the service role, which is what makes scripts/rotate-super-admin.mjs safe
  -- without that script having to remember: rotating the super admin onto a new address drops
  -- the verified stamp, and the new address has to be proved like any other.
  if new.email is distinct from old.email then
    new.email_verified_at := null;

  -- Otherwise the stamp moves only when the verification endpoint moves it.
  elsif new.email_verified_at is distinct from old.email_verified_at and not app.is_service_role() then
    raise exception 'Email verification cannot be granted by hand — it is earned by entering the emailed code.'
      using errcode = '42501';
  end if;

  -- Super Admin (and the service role, used by account-management server actions)
  -- may change anything; those paths do their own authorization first.
  if app.is_super_admin() then
    return new;
  end if;

  -- Who legitimately administers the TARGET account?
  v_manages_target :=
       (old.role in ('manager','warden') and app.owns_hostel(old.hostel_id))
    or (old.role = 'student' and app.has_role_in(old.hostel_id, 'warden'));

  -- Identity, role and tenant binding are never self-serviceable.
  if new.id is distinct from old.id then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    raise exception 'You cannot change an account''s role.' using errcode = '42501';
  end if;
  if new.hostel_id is distinct from old.hostel_id then
    raise exception 'You cannot move an account to another hostel.' using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  -- Activation state may only be changed by the account's administrator.
  if (new.status is distinct from old.status or new.deleted_at is distinct from old.deleted_at)
     and not v_manages_target then
    raise exception 'You cannot change this account''s status.' using errcode = '42501';
  end if;

  -- Remaining columns (full_name, phone, email, must_change_password):
  -- the account holder themselves, or the account's administrator.
  if new.id = auth.uid() or v_manages_target then
    return new;
  end if;
  raise exception 'Not allowed.' using errcode = '42501';
end $$;

drop trigger if exists users_update_guard on public.users;
create trigger users_update_guard before update on public.users
  for each row execute function app.users_update_guard();
