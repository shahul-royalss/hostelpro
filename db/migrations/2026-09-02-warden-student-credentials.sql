-- ============================================================================
-- The warden's student list gains credential management.
--
-- Applied to nimxvgzscbanhtvgnjll as:
--   warden_student_credentials        (both functions below)
--
-- Two service-role-only helpers behind supabase/functions/warden-student-
-- credentials. Neither is callable by anon or by a warden holding a user
-- token: both write the `auth` schema, which no client key may reach.
--
-- ----------------------------------------------------------------------------
-- WHAT THE OWNER ASKED FOR, AND WHAT IS BUILT INSTEAD
--
-- "when warden registers the student the temporary password has to be saved in
--  their student list and they can edit the email address"
--
-- The password half is built as REGENERATE ON DEMAND, not as storage, and that
-- was the owner's own choice when the question was put to them. Nothing here
-- stores a readable password: not on students, not in a side table, not in
-- Storage, not in a notification. A stored temporary password would let any
-- warden, manager or owner sign in AS a resident, and would put working
-- credentials into any database leak. It also contradicts the security
-- checklist's own line — "passwords are never encrypted for reversible
-- storage". So the list gets a RESET that mints a new password server-side and
-- shows it once, which is the same artefact the registration desk already
-- produces.
--
-- The email half is real: `set_student_login_email` below.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. CHANGE A STUDENT'S LOGIN ADDRESS — in all four places at once
-- ----------------------------------------------------------------------------
-- app.attach_student_login_email (2026-08-31-student-email-login.sql) already
-- does one third of this: it renames a login that is CURRENTLY phone-mapped to
-- a real address, once, as a migration path. It deliberately refuses a second
-- call on the same account, which is exactly the case the warden's screen is
-- for — correcting an address that was typed wrong at the desk.
--
-- This function generalises it to the three edits a warden can actually need,
-- and it is left alongside rather than replacing it: that one is a documented,
-- deployed migration path with a comment describing what it will not do, and
-- widening it in place would quietly turn "migrate a phone login" into "rename
-- any login" for every existing caller.
--
--   synthetic -> real   the resident has an address now
--   real      -> real   the address was typed wrong (the common case)
--   real      -> null   remove it; the login reverts to the phone mapping
--
-- ── WHY IT MUST TOUCH auth.users AND NOT ONLY public.users ──────────────────
-- public.users.email is the profile mirror RLS and requireCaller() read.
-- auth.users.email is THE LOGIN. Editing only the mirror would leave a resident
-- whose row shows the corrected address and whose account still answers to the
-- old one — a screen that lies, and a person who cannot sign in with what the
-- warden read out to them. Both clients resolve the sign-in box with the same
-- pure function (resolveLoginEmail / studentLoginEmail): an address signs in as
-- itself, a bare phone number maps to <digits>@student.hostelpro.local. So the
-- rule is: whatever this function leaves in auth.users.email is what the
-- resident types, and the fourth case — clearing the address — has to put the
-- phone mapping BACK or the login is orphaned.
--
-- ── VERIFICATION IS DELIBERATELY LOST ───────────────────────────────────────
-- app.users_update_guard nulls users.email_verified_at and stamps
-- email_verification_reset_at on any address change, for every writer including
-- the service role. That is correct and it is not worked around here: a warden
-- typing an address is not proof the resident reads it. The caller is told, so
-- the UI can say so rather than letting it surprise the resident later.
create or replace function app.set_student_login_email(
  p_user_id uuid,
  p_email   text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_email    text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_role     public.user_role;
  v_auth     text;
  v_phone    text;
  v_digits   text;
  v_prev     text;
  v_was_verified boolean;
begin
  select u.role, u.email_verified_at is not null
    into v_role, v_was_verified
    from public.users u where u.id = p_user_id;
  if v_role is null then
    raise exception 'No such account.' using errcode = 'P0001';
  end if;
  -- Staff sign in with an address they own; there is no phone mapping to fall
  -- back to, so "clear the email" has no meaning for them and renaming a
  -- manager's or an owner's login is not a warden's decision.
  if v_role <> 'student' then
    raise exception 'Only a student login can be changed here.' using errcode = 'P0001';
  end if;

  select au.email into v_auth from auth.users au where au.id = p_user_id;
  if v_auth is null then
    raise exception 'That account has no login to change.' using errcode = 'P0001';
  end if;

  if v_email is not null then
    -- The same shape the Edge Function's EMAIL_RE accepts, so an address is not
    -- taken here and refused there (or the reverse).
    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
      raise exception 'Enter a valid email address.' using errcode = 'P0001';
    end if;
    -- The phone-mapping namespace is reserved. An address in it would claim the
    -- login id belonging to somebody else's phone number, and GoTrue never
    -- gives an address back. app.email_is_reachable() is the same predicate
    -- app.email_verification_owed() reads, so the two cannot disagree.
    if not app.email_is_reachable(v_email) then
      raise exception 'That domain is reserved for phone logins — use a real email address.'
        using errcode = 'P0001';
    end if;
  else
    -- Clearing the address: the login goes back to the phone mapping, which is
    -- the ONLY other thing this resident can type. Byte-identical to
    -- studentLoginEmail() in _shared/validate.ts and lib/utils.ts — +91 and a
    -- leading 0 stripped, digits only — because those two resolve the sign-in
    -- box and a divergence here mints a login nobody can reach.
    select s.phone into v_phone
      from public.students s
     where s.user_id = p_user_id and s.status <> 'vacated'
     limit 1;
    if v_phone is null then
      select s.phone into v_phone from public.students s where s.user_id = p_user_id limit 1;
    end if;
    v_digits := regexp_replace(coalesce(v_phone, ''), '\D', '', 'g');
    if length(v_digits) = 12 and left(v_digits, 2) = '91' then v_digits := substr(v_digits, 3); end if;
    if length(v_digits) = 11 and left(v_digits, 1) = '0'  then v_digits := substr(v_digits, 2); end if;
    if v_digits !~ '^[0-9]{10}$' then
      raise exception 'This resident has no usable phone number to sign in with, so their email address cannot be removed.'
        using errcode = 'P0001';
    end if;
    v_email := v_digits || '@student.hostelpro.local';
  end if;

  -- Nothing to do. Returned rather than written, so that pressing Save on an
  -- unchanged address does not cost this resident their verified status.
  if lower(v_auth) = v_email then
    return jsonb_build_object(
      'loginEmail', v_email,
      'changed', false,
      'verificationCleared', false,
      'phoneLogin', not app.email_is_reachable(v_email)
    );
  end if;

  -- users_email_key is UNIQUE on lower(email) and GLOBAL, not per hostel; GoTrue
  -- allows one account per address project-wide. The two rules agree, and this
  -- says so before anything is written rather than after.
  if exists (select 1 from auth.users au where lower(au.email) = v_email and au.id <> p_user_id)
     or exists (select 1 from public.users u where lower(u.email) = v_email and u.id <> p_user_id) then
    raise exception 'That email address already belongs to another account.' using errcode = 'P0001';
  end if;

  -- app.users_update_guard refuses an update it cannot attribute to an
  -- administrator, and this function's own session carries no JWT for it to
  -- read. Execution is granted to service_role alone (see the grants), so
  -- asserting that role for the rest of THIS transaction restates who already
  -- got in. The previous value is put back.
  v_prev := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- BOTH auth tables, because GoTrue reads both. auth.identities.email is a
  -- generated column over identity_data->>'email', so the JSON is what has to
  -- move; provider_id is the user's uuid on this project and stays put.
  --
  -- The email_change_* columns are cleared as well, which attach_student_login_
  -- email does not do. If the resident had a self-service address change in
  -- flight, its single-use token would otherwise still be live and could be
  -- redeemed AFTER this edit — silently moving the login to a third address
  -- that neither the warden nor the resident chose.
  update auth.users
     set email = v_email,
         email_change = '',
         email_change_token_new = '',
         email_change_token_current = '',
         email_change_confirm_status = 0,
         updated_at = now()
   where id = p_user_id;

  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_email), true),
         updated_at = now()
   where user_id = p_user_id
     and provider = 'email';

  -- The profile row and the roster row. NULL rather than the synthetic address
  -- when the login reverts to the phone mapping: that is what
  -- wd_register_student writes for a resident who gave no address, so a
  -- reverted row and a never-had-one row are indistinguishable, as they should
  -- be. app.email_verification_owed() reads users.email through
  -- app.email_is_reachable(), which is false for both NULL and the reserved
  -- domain — so neither shape asks a resident to prove an address they cannot
  -- receive mail at.
  update public.users
     set email = case when app.email_is_reachable(v_email) then v_email else null end
   where id = p_user_id;

  update public.students
     set email = case when app.email_is_reachable(v_email) then v_email else null end
   where user_id = p_user_id;

  perform set_config('request.jwt.claims', coalesce(v_prev, ''), true);

  return jsonb_build_object(
    'loginEmail', v_email,
    'changed', true,
    -- users_update_guard nulled it on the way through. Reported so the warden's
    -- screen can say "they will have to confirm this address again" instead of
    -- the resident discovering it the next time verification is demanded.
    'verificationCleared', v_was_verified,
    'phoneLogin', not app.email_is_reachable(v_email)
  );
end $$;

comment on function app.set_student_login_email(uuid, text) is
  'Change a student''s login address in auth.users, auth.identities, public.users and public.students at once. A NULL/blank address reverts the login to the <digits>@student.hostelpro.local phone mapping. Service role only. The session id and the password survive; email verification does not, by design.';

revoke all on function app.set_student_login_email(uuid, text) from public;
revoke all on function app.set_student_login_email(uuid, text) from anon, authenticated;
grant execute on function app.set_student_login_email(uuid, text) to service_role;


-- ----------------------------------------------------------------------------
-- 2. END EVERY LIVE SESSION FOR ONE ACCOUNT
-- ----------------------------------------------------------------------------
-- A password reset that leaves the old sessions running is not a reset. The case
-- a warden resets for is "somebody else has been getting into this account", and
-- an intruder holding a refresh token does not care that the password changed.
--
-- ── THIS IS A BACKSTOP, AND THE MEASUREMENT SAYS SO ─────────────────────────
-- On this project, GoTrue revokes the sessions itself. Measured against a live
-- session on 2026-09-01, not assumed:
--
--   sign in as the resident            -> auth.sessions for that user: 1
--   auth.admin.updateUserById(password) -> auth.sessions for that user: 0
--   the open session tries to refresh   -> "Invalid Refresh Token: Refresh
--                                          Token Not Found"
--
-- So in the steady state this function deletes nothing and returns 0, which is
-- exactly what the first real reset through the Edge Function reported.
--
-- It is kept anyway, for one reason: that revocation is GoTrue's behaviour, not
-- ours. It is a platform implementation detail that a Supabase upgrade could
-- change under us, silently, and the failure mode would be invisible — resets
-- would keep succeeding while quietly leaving intruders signed in. Deleting the
-- rows here makes the property OURS, and the returned count is the tripwire:
-- every reset audits `sessionsEnded`, so a value that stops being 0 is the
-- signal that GoTrue changed and this function is now the only thing doing the
-- job. Cheap insurance against a silent regression in somebody else's code.
--
-- Deleting auth.sessions revokes the refresh tokens with it
-- (auth.refresh_tokens.session_id cascades).
create or replace function app.revoke_user_sessions(p_user_id uuid) returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_count integer;
begin
  delete from auth.sessions where user_id = p_user_id;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

comment on function app.revoke_user_sessions(uuid) is
  'Delete every auth.sessions row for one account, revoking its refresh tokens. Called after a credential reset so the old sessions cannot outlive the old password. Service role only.';

revoke all on function app.revoke_user_sessions(uuid) from public;
revoke all on function app.revoke_user_sessions(uuid) from anon, authenticated;
grant execute on function app.revoke_user_sessions(uuid) to service_role;


-- ----------------------------------------------------------------------------
-- 3. THE POSTGREST DOORS
-- ----------------------------------------------------------------------------
-- Measured, not assumed:
--
--   POST /rest/v1/rpc/set_student_login_email  (Content-Profile: app)
--   -> {"code":"PGRST106","message":"Invalid schema: app",
--       "hint":"Only the following schemas are exposed: public, graphql_public"}
--
-- The `app` schema is where this project keeps helpers that only SQL calls —
-- policies, triggers, other functions — and PostgREST cannot see into it. An
-- Edge Function reaches Postgres THROUGH PostgREST, so the two functions above
-- need a door in `public`, exactly as public.audit_event() and
-- public.rate_limit() are doors onto service-role-only work.
--
-- Each wrapper re-asserts app.is_service_role() rather than trusting the GRANT
-- alone. The grant is the lock; this is the bolt. A future migration that adds
-- `grant execute ... to authenticated` by accident — the single most likely way
-- one of these ever gets exposed — still refuses, and refuses with 42501 rather
-- than renaming somebody's login.

create or replace function public.svc_set_student_login_email(
  p_user_id uuid,
  p_email   text
) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return app.set_student_login_email(p_user_id, p_email);
end $$;

comment on function public.svc_set_student_login_email(uuid, text) is
  'PostgREST door onto app.set_student_login_email(). Service role only — called by supabase/functions/warden-student-credentials.';

revoke all on function public.svc_set_student_login_email(uuid, text) from public;
revoke all on function public.svc_set_student_login_email(uuid, text) from anon, authenticated;
grant execute on function public.svc_set_student_login_email(uuid, text) to service_role;


create or replace function public.svc_revoke_user_sessions(p_user_id uuid) returns integer
language plpgsql security definer set search_path = public as $$
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return app.revoke_user_sessions(p_user_id);
end $$;

comment on function public.svc_revoke_user_sessions(uuid) is
  'PostgREST door onto app.revoke_user_sessions(). Service role only — called by supabase/functions/warden-student-credentials after a password reset.';

revoke all on function public.svc_revoke_user_sessions(uuid) from public;
revoke all on function public.svc_revoke_user_sessions(uuid) from anon, authenticated;
grant execute on function public.svc_revoke_user_sessions(uuid) to service_role;
