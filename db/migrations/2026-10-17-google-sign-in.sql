-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 2026-10-17 — GOOGLE SIGN-IN: WHAT THE DATABASE HAS TO DECIDE
-- ═══════════════════════════════════════════════════════════════════════════════════════════
--
-- The app gains "Continue with Google". The phone gets a Google ID token from Android's own
-- account sheet (no browser) and hands it to supabase/functions/mobile-auth, action "google".
-- That function verifies the token, looks the account up, refuses staff, and only then asks
-- GoTrue for a session. Three things cannot live in that function, and they are this file:
--
-- 1. app.guard_external_identity(), a trigger on auth.identities.
--
--    GoTrue links a Google identity to whichever existing user has the same email address,
--    AUTOMATICALLY, on every path: the app's, and the two public ones no Edge Function can stand
--    in front of (/auth/v1/token?grant_type=id_token and the browser redirect /auth/v1/authorize,
--    which works for anyone with a Google account the moment the provider is switched on,
--    whether or not the app ships a button). So "staff never sign in with Google" is enforced
--    where the link is written, inside GoTrue's own transaction:
--      - email and phone identities pass: every account is created with one;
--      - google and facebook identities are refused for super_admin, manager and warden;
--      - every other provider is refused outright. GitHub was found switched ON in this
--        project's dashboard on 2026-10-17 with nothing using it; this makes it inert even
--        before someone switches it off.
--    Why it matters here and not in theory: the Play review logins use @nivora.app, a parked
--    domain this project does not own. A staff login on an address like that is one Google
--    Workspace account away from belonging to someone else.
--
-- 2. public.login_account_for_email(text), service role only.
--
--    mobile-auth verifies the token's signature first and then has to know whether an account
--    uses that address, and what it is, before GoTrue is involved: "Allow new users to sign up"
--    is ON in this project today, so handing GoTrue a token for an unknown address would CREATE
--    an account. auth.users is not reachable through PostgREST, so this is the narrow door: one
--    address in, id + role + status out, executable by service_role and nobody else. It is not
--    an enumeration oracle in the function's hands either, because the function only asks after
--    Google has proved the caller owns the address being asked about.
--
-- 3. public.email_link_proof() gains ARM C.
--
--    Google only issues an ID token for an address it has verified (email_verified = true in the
--    token, which GoTrue keeps in identity_data). An owner who signs in with Google has proved
--    the address as surely as one who clicked the emailed link, so the email-verification gate
--    lets them through on the next `status` call. ARM C credits it only while the Google
--    identity's address IS the account's current address (an address change moves auth.users
--    and public.users but never the Google identity), and only from a link or sign-in at or
--    after the floor, email_verification_reset_at. An address change therefore still
--    invalidates the proof, exactly as it does for arms A and B. Facebook is deliberately NOT
--    credited: it is not wired up, and its address claim needs its own look.
--
-- The replaced email_link_proof() body is the one measured on live on 2026-10-17 (md5 of
-- prosrc 87dd8e31d2789103bb6d11669d1689d6, comment-free, same logic as
-- 2026-09-02-email-link-proof-pkce.sql). Anything else and this batch refuses to run.
--
-- NOT IN THIS FILE, AND IN THIS ORDER AFTER IT:
--   - GOOGLE_WEB_CLIENT_ID as an Edge Function secret, and the mobile-auth redeploy;
--   - the dashboard switch: Authentication → Sign In / Providers → Google, with the Web client
--     ID and its secret. Apply THIS file first, for the redirect reason in (1).
--
-- Undo: 2026-10-17-google-sign-in.down.sql. Tests: 2026-10-17-google-sign-in.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;
set local lock_timeout = '10s';

do $guard$
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.email_link_proof(uuid)'::regprocedure)
       <> '87dd8e31d2789103bb6d11669d1689d6' then
    raise exception 'public.email_link_proof() is not the body measured on 2026-10-17; nothing changed';
  end if;
  -- Nothing but email identities existed when this was written. A google/facebook identity
  -- already sitting on a staff account would be exactly what the trigger exists to prevent, and
  -- it would not be undone by adding the trigger now.
  if exists (
    select 1
      from auth.identities i
      join public.users u on u.id = i.user_id
     where i.provider not in ('email', 'phone')
       and u.role in ('super_admin', 'manager', 'warden')
  ) then
    raise exception 'a staff or super admin account already has a non-email identity; remove it first';
  end if;
end
$guard$;

-- ─── 1. The identity guard ────────────────────────────────────────────────────────────────
create or replace function app.guard_external_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_role public.user_role;
begin
  if new.provider in ('email', 'phone') then
    return new;
  end if;

  if new.provider not in ('google', 'facebook') then
    raise exception 'This sign-in method is not available.'
      using errcode = '42501';
  end if;

  -- No profile row means a brand-new sign-up that has not chosen a role yet. It reaches nothing:
  -- app.user_role() resolves only through public.users.
  select u.role into v_role from public.users u where u.id = new.user_id;

  if v_role in ('super_admin', 'manager', 'warden') then
    raise exception 'Staff and administrator accounts sign in with the login they were given.'
      using errcode = '42501';
  end if;

  return new;
end
$fn$;

comment on function app.guard_external_identity() is
  'Trigger on auth.identities. Lets email/phone identities through, refuses google/facebook on super_admin, manager and warden accounts, and refuses every other provider. Enforces "staff never sign in with Google" on GoTrue''s public paths too. See db/migrations/2026-10-17-google-sign-in.sql.';

revoke all on function app.guard_external_identity() from public;

-- UPDATE OF user_id, provider as well as INSERT: moving an existing Google identity onto a staff
-- account is the same act as linking one. GoTrue's own updates (identity_data, last_sign_in_at)
-- and this project's address-change functions (identity_data on the email identity) do not name
-- these columns, so they do not fire it; GoTrue rewriting every column of an email identity would,
-- and passes at the first line.
drop trigger if exists identities_guard_external on auth.identities;
create trigger identities_guard_external
  before insert or update of user_id, provider on auth.identities
  for each row execute function app.guard_external_identity();

-- ─── 2. The account lookup ────────────────────────────────────────────────────────────────
create or replace function public.login_account_for_email(p_email text)
returns table (user_id uuid, role public.user_role, status public.user_status, deleted_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select au.id, pu.role, pu.status, pu.deleted_at
    from auth.users au
    left join public.users pu on pu.id = au.id
   where lower(au.email) = lower(btrim(p_email))
     and au.deleted_at is null
   order by au.created_at
   limit 2;
$$;

comment on function public.login_account_for_email(text) is
  'Service role only. The account (if any) whose login address is p_email: auth id, and role/status/deleted_at from public.users (NULL role = an auth user with no profile). Two rows means GoTrue would refuse to link. Used by mobile-auth after it has verified a Google token for that address.';

revoke all on function public.login_account_for_email(text) from public, anon, authenticated;
grant execute on function public.login_account_for_email(text) to service_role;

-- ─── 3. ARM C on the email proof ──────────────────────────────────────────────────────────
-- CREATE OR REPLACE keeps the grants (postgres, service_role), which the verify block checks.
create or replace function public.email_link_proof(p_user uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  with floor_at as (
    select coalesce(pu.email_verification_reset_at, '-infinity'::timestamptz) as since,
           lower(pu.email) as email
    from public.users pu
    where pu.id = p_user
  )
  select greatest(
    (
      select max(f.auth_code_issued_at)
      from auth.flow_state f
      where f.user_id = p_user
        and f.authentication_method in ('magiclink', 'otp', 'recovery')
        and f.auth_code_issued_at is not null
        and f.auth_code_issued_at >= (select since from floor_at)
    ),
    (
      select max(a.created_at)
      from auth.audit_log_entries a
      where a.payload ->> 'actor_id' = p_user::text
        and a.payload ->> 'action' = 'login'
        and coalesce(a.payload -> 'traits' ->> 'provider', 'link')
              in ('link', 'magiclink', 'otp')
        and a.created_at >= (select since from floor_at)
        and exists (
          select 1
          from auth.audit_log_entries r
          where r.payload ->> 'actor_id' = p_user::text
            and r.payload ->> 'action'
                  in ('user_recovery_requested', 'user_confirmation_requested')
            and r.created_at <= a.created_at
            and r.created_at >= a.created_at - interval '1 hour'
        )
    ),
    (
      select max(coalesce(i.last_sign_in_at, i.created_at))
      from auth.identities i
      where i.user_id = p_user
        and i.provider = 'google'
        and lower(i.identity_data ->> 'email') = (select email from floor_at)
        and i.identity_data ->> 'email_verified' = 'true'
        and coalesce(i.last_sign_in_at, i.created_at) >= (select since from floor_at)
    )
  )
  where exists (select 1 from floor_at);
$$;

comment on function public.email_link_proof(uuid) is
  'When the account last proved its CURRENT address: an emailed link GoTrue accepted (arms A and B), or a Google sign-in whose verified address is the account''s address (arm C), at or after email_verification_reset_at. NULL = unproved. Service role only; read by supabase/functions/_shared/verification.ts.';

-- ─── 4. What live looks like afterwards, or no commit ─────────────────────────────────────
do $verify$
begin
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'auth.identities'::regclass
       and tgname = 'identities_guard_external'
       and tgenabled = 'O'
       and not tgisinternal
  ) then
    raise exception 'the identity guard trigger is missing or disabled';
  end if;

  if has_function_privilege('anon', 'public.login_account_for_email(text)', 'execute')
     or has_function_privilege('authenticated', 'public.login_account_for_email(text)', 'execute')
     or not has_function_privilege('service_role', 'public.login_account_for_email(text)', 'execute') then
    raise exception 'login_account_for_email has the wrong grants';
  end if;

  if has_function_privilege('anon', 'public.email_link_proof(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.email_link_proof(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.email_link_proof(uuid)', 'execute') then
    raise exception 'email_link_proof lost or gained a grant';
  end if;

  if (select count(*) from pg_proc
       where oid in ('app.guard_external_identity()'::regprocedure,
                     'public.login_account_for_email(text)'::regprocedure,
                     'public.email_link_proof(uuid)'::regprocedure)
         and prosecdef
         and proconfig = array['search_path=""']) <> 3 then
    raise exception 'a new function is not SECURITY DEFINER with an empty search_path';
  end if;

  if position('auth.identities' in (select prosrc from pg_proc where oid = 'public.email_link_proof(uuid)'::regprocedure)) = 0 then
    raise exception 'email_link_proof did not gain arm C';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261017100000', 'google_sign_in') on conflict (version) do nothing;

commit;
