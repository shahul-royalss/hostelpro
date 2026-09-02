-- ============================================================================
-- Attach a real email address to a student login that was created under the
-- phone mapping.
--
-- Applied to nimxvgzscbanhtvgnjll as two migrations:
--   student_email_login_attach                        (the function)
--   student_email_login_attach_reuse_reachability     (fold the reserved-domain
--                                                      test into the function
--                                                      that already owns it)
-- The definition below is the second, i.e. what is live.
-- ----------------------------------------------------------------------------
-- WHY THIS EXISTS
--
-- Students used to have no email at all. The warden collected a phone number,
-- `studentLoginEmail()` mapped it to <digits>@student.hostelpro.local, and that
-- synthetic address is what auth.users carries. `public.users.email` was left
-- NULL. From now on the warden may collect a real address, and when they do it
-- IS the login (see supabase/functions/warden-register-student/index.ts).
--
-- That leaves the residents registered before the change with a login they
-- cannot replace from inside the app: changing an account's login address means
-- writing auth.users AND auth.identities, which no client key may do. Deleting
-- and re-creating the account is not an option either — it would orphan the
-- students row, the fee ledger and the bed.
--
-- This function is the path. It renames the login in place, in ONE transaction,
-- so the account, its history and its live sessions all survive: the JWT `sub`
-- does not change, so a resident signed in on their phone stays signed in and
-- simply has a new thing to type next time.
--
-- ----------------------------------------------------------------------------
-- WHAT IT WILL NOT DO
--
--   * It refuses any account whose login is NOT currently a synthetic phone
--     address. This is a migration path, not a general "change my email":
--     re-pointing an address a resident already uses is a consent question and
--     belongs behind the emailed-code flow, not behind a service key. A second
--     call on the same account therefore fails, which makes the operation safe
--     to retry after a partial failure.
--   * It refuses an address inside @student.hostelpro.local. That namespace is
--     reserved for the phone mapping; an address in it would claim the login id
--     belonging to somebody else's number, and GoTrue never gives an address
--     back. The test is app.email_is_reachable(), the same predicate
--     app.email_verification_owed() reads, so the migration path and the
--     verification gate cannot disagree about one address.
--   * It refuses an address already used by any account, checking BOTH
--     auth.users and public.users. public.users carries a UNIQUE index on
--     lower(email) WHERE email IS NOT NULL, and that index is GLOBAL, not
--     per-hostel: two residents at two different hostels cannot share one
--     address. That matches GoTrue, which allows one account per address across
--     the whole project, so the two rules agree rather than fighting. Students
--     with no email are unaffected — the index is partial and NULLs are free.
--   * It does NOT mark the address verified. `app.users_update_guard` nulls
--     `users.email_verified_at` on any email change, deliberately: a warden
--     typing an address is not proof the resident reads it. Verification stays
--     something earned by entering the emailed code.
--
-- ----------------------------------------------------------------------------
-- WHAT IT DOES TO THE ONE EXISTING STUDENT
--
-- NOTHING, on its own. This migration creates a function and changes zero rows.
-- There is exactly one student on the platform today —
-- 7569716576@student.hostelpro.local, user c60a9a2d-3db6-430f-bd95-13bc8aac460b
-- — and no real address is on file for them, so none can be invented here.
-- Attaching one is a single call, made by the owner once they have the address
-- from the resident themselves:
--
--   select app.attach_student_login_email(
--     'c60a9a2d-3db6-430f-bd95-13bc8aac460b', 'the.resident@example.com');
--
-- Until that call is made, that student signs in with 7569716576 exactly as
-- they do today. After it, they sign in with the address and the SAME password,
-- and the phone number stops working as a login — there is one login id per
-- account by design (resolving both would need a phone→account lookup on an
-- unauthenticated endpoint, which is an enumeration oracle over a population of
-- young residents). Their phone number stays on both rows for contact and for
-- students_phone_active_key; only the login moves.
-- ============================================================================

create or replace function app.attach_student_login_email(
  p_user_id uuid,
  p_email   text
) returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_email  text := lower(btrim(p_email));
  v_role   public.user_role;
  v_auth   text;
  v_prev   text;
begin
  if v_email is null or v_email = '' then
    raise exception 'An email address is required.' using errcode = 'P0001';
  end if;
  -- The same shape the Edge Function's EMAIL_RE accepts, so an address is not taken here and
  -- refused there (or the reverse).
  if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Enter a valid email address.' using errcode = 'P0001';
  end if;
  -- The phone-mapping namespace is reserved: an address in it would claim the login id
  -- belonging to somebody else's phone number, and GoTrue never gives an address back.
  if not app.email_is_reachable(v_email) then
    raise exception 'That domain is reserved for phone logins — use a real email address.'
      using errcode = 'P0001';
  end if;

  select u.role into v_role from public.users u where u.id = p_user_id;
  if v_role is null then
    raise exception 'No such account.' using errcode = 'P0001';
  end if;
  if v_role <> 'student' then
    raise exception 'Only a student login is phone-mapped; % accounts already sign in with an email.', v_role
      using errcode = 'P0001';
  end if;

  select au.email into v_auth from auth.users au where au.id = p_user_id;
  if v_auth is null then
    raise exception 'That account has no login to rename.' using errcode = 'P0001';
  end if;
  -- A migration path, not a general "change my email". The account's CURRENT login must be an
  -- address no mail server accepts — i.e. it was minted from a phone number.
  if app.email_is_reachable(v_auth) then
    raise exception 'That login is already an email address (%). This function only migrates phone-mapped logins.', v_auth
      using errcode = 'P0001';
  end if;

  -- users_email_key is UNIQUE on lower(email) and GLOBAL, not per hostel; GoTrue allows one
  -- account per address project-wide. The two rules agree, and this says so before anything is
  -- written rather than after.
  if exists (select 1 from auth.users au where lower(au.email) = v_email and au.id <> p_user_id)
     or exists (select 1 from public.users u where lower(u.email) = v_email and u.id <> p_user_id) then
    raise exception 'That email address already belongs to another account.' using errcode = 'P0001';
  end if;

  -- app.users_update_guard refuses an update it cannot attribute to an administrator, and a
  -- plain SQL session carries no JWT for it to read. This function is executable by the service
  -- role alone (see the grants), so asserting that role for the rest of THIS transaction
  -- restates who already got in. The previous value is put back.
  v_prev := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- BOTH auth tables, because GoTrue reads both. auth.identities.email is a generated column
  -- over identity_data->>'email', so the JSON is what has to move; provider_id is the user's
  -- uuid on this project and stays put.
  update auth.users
     set email = v_email,
         updated_at = now()
   where id = p_user_id;

  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_email), true),
         updated_at = now()
   where user_id = p_user_id
     and provider = 'email';

  -- The profile row RLS and requireCaller() read. users_update_guard nulls email_verified_at on
  -- the way through, which is the intended outcome: a warden typing an address is not proof the
  -- resident reads it. app.email_verification_owed() then becomes true for this account, and
  -- the emailed-code flow is how the proof is earned.
  update public.users set email = v_email where id = p_user_id;

  -- The roster row the warden's screens read, kept in step.
  update public.students set email = v_email where user_id = p_user_id;

  perform set_config('request.jwt.claims', coalesce(v_prev, ''), true);

  return v_email;
end $$;

comment on function app.attach_student_login_email(uuid, text) is
  'Migration path: replace a student''s synthetic phone login with a real email address, in auth.users, auth.identities, public.users and public.students at once. Service role only. The session and the password survive; the phone number stops working as a login.';

-- Not callable by anon, authenticated, or a warden holding a user token. Renaming somebody
-- else's login is an owner-with-the-service-key operation and nothing less.
revoke all on function app.attach_student_login_email(uuid, text) from public;
revoke all on function app.attach_student_login_email(uuid, text) from anon, authenticated;
grant execute on function app.attach_student_login_email(uuid, text) to service_role;
