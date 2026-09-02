-- ═════════════════════════════════════════════════════════════════════════════════════════
-- BRUTE-FORCE PROTECTION FOR THE AUTH ENDPOINTS
--
-- Two things live here, and only the first is live the moment this migration runs.
--
--   PART 1  app.detect_suspicious_activity() learns two new actions. Applied and active.
--   PART 2  The two GoTrue auth hooks. Created, granted, and INERT until an operator enables
--           them in the dashboard. Nothing calls them until then. See PART 2's header.
--
-- ── THE FINDING ──────────────────────────────────────────────────────────────────────────
--
-- The Flutter client called GoTrue directly, so the browser's throttle (lib/actions/auth.ts)
-- never applied to it. Twelve consecutive wrong-password POSTs to
-- /auth/v1/token?grant_type=password for a real account all returned 400 invalid_credentials:
-- no 429, no lockout, and back-off DECREASING between attempts. Nothing on that path wrote to
-- public.audit_log either, so the 124 auth.login.failed rows this database holds are all from
-- the web app and an attack against the mobile surface was invisible to
-- app.detect_suspicious_activity().
--
-- supabase/functions/mobile-auth now sits between the app and GoTrue and closes the app's
-- path. It cannot close the RAW path — /auth/v1/token is public and the anon key ships inside
-- the APK — because an Edge Function is not in that request's way. PART 2 is.
-- ═════════════════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────────────────
-- PART 1 — TWO MORE PATTERNS THE DETECTOR RECOGNISES
--
-- Unchanged from the original except for the two new branches at the end; the existing five
-- are reproduced verbatim so this file is the whole function rather than a diff to apply by
-- eye. `auth.mfa.rate_limited` is new (mobile-auth writes it) and `auth.login.hook_rejected`
-- is written by PART 2 when the hook refuses a raw attempt that never touched our app.
-- ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function app.detect_suspicious_activity() returns trigger
language plpgsql security definer set search_path = public as $fn$
declare n int;
begin
  if new.action = 'auth.login.failed' then
    -- count by IP as well as by actor: a failed login often has no actor_user_id at all
    select count(*) into n from public.audit_log
     where action = 'auth.login.failed'
       and at > now() - interval '15 minutes'
       and ((new.actor_user_id is not null and actor_user_id = new.actor_user_id)
            or (new.actor_user_id is null and new.ip is not null and ip = new.ip));
    if n >= 5 then
      perform app.raise_security_alert('high', 'auth.bruteforce',
        format('%s failed sign-ins in 15 minutes from %s', n, coalesce(new.ip, 'unknown IP')),
        new.hostel_id, new.actor_user_id, new.ip, jsonb_build_object('count', n, 'window', '15 minutes'));
    end if;
  elsif new.action = 'authz.denied' then
    select count(*) into n from public.audit_log
     where action = 'authz.denied' and actor_user_id = new.actor_user_id
       and at > now() - interval '10 minutes';
    if n >= 5 then
      perform app.raise_security_alert('high', 'authz.probing',
        format('%s authorization denials in 10 minutes for one account', n),
        new.hostel_id, new.actor_user_id, new.ip, jsonb_build_object('count', n));
    end if;
  elsif new.action = 'auth.mfa.failed' then
    select count(*) into n from public.audit_log
     where action = 'auth.mfa.failed' and actor_user_id = new.actor_user_id
       and at > now() - interval '10 minutes';
    if n >= 3 then
      perform app.raise_security_alert('high', 'auth.mfa.bruteforce',
        format('%s failed second-factor attempts in 10 minutes', n),
        new.hostel_id, new.actor_user_id, new.ip, jsonb_build_object('count', n));
    end if;
  elsif new.action = 'auth.login.rate_limited' then
    perform app.raise_security_alert('medium', 'auth.rate_limited',
      'Sign-in rate limit tripped', new.hostel_id, new.actor_user_id, new.ip, '{}'::jsonb);

  -- NEW. A tripped second-factor limiter is a stronger signal than a tripped sign-in limiter:
  -- whoever is guessing codes already holds a working password for this account.
  elsif new.action = 'auth.mfa.rate_limited' then
    perform app.raise_security_alert('high', 'auth.mfa.rate_limited',
      'Second-factor rate limit tripped — the first factor for this account has already been passed',
      new.hostel_id, new.actor_user_id, new.ip, '{}'::jsonb);

  -- NEW. The hook only ever fires for a request that did NOT come through mobile-auth or the
  -- web app, because both of those refuse before GoTrue is ever called. So this action means
  -- something is talking to /auth/v1/token directly — which is the exact shape of the attack
  -- that was measured, and is critical rather than merely high.
  elsif new.action = 'auth.login.hook_rejected' then
    perform app.raise_security_alert('critical', 'auth.raw_endpoint_bruteforce',
      'Sign-in attempts are hitting /auth/v1/token directly, past both app clients',
      new.hostel_id, new.actor_user_id, new.ip, '{}'::jsonb);

  elsif new.action in ('sa.owner.password_reset', 'owner.staff.password_reset') then
    perform app.raise_security_alert('medium', 'account.password_reset_by_admin',
      format('An administrator reset another account password (%s)', new.action),
      new.hostel_id, new.actor_user_id, new.ip, jsonb_build_object('target', new.target_id));
  end if;
  return new;
end $fn$;

revoke all on function app.detect_suspicious_activity() from public, anon, authenticated;


-- ─────────────────────────────────────────────────────────────────────────────────────────
-- PART 2 — THE HOOKS THAT COVER THE ENDPOINT AN EDGE FUNCTION CANNOT REACH
--
-- ── READ THIS BEFORE ENABLING ────────────────────────────────────────────────────────────
--
-- These two functions are NOT called by anything yet. GoTrue invokes them only once they are
-- named in the project's auth configuration:
--
--   Dashboard → Authentication → Hooks
--     "Password verification attempt"  → postgres function → public.password_verification_attempt
--     "MFA verification attempt"       → postgres function → public.mfa_verification_attempt
--
--   or in supabase/config.toml for a local stack:
--     [auth.hook.password_verification_attempt]
--     enabled = true
--     uri = "pg-functions://postgres/public/password_verification_attempt"
--     [auth.hook.mfa_verification_attempt]
--     enabled = true
--     uri = "pg-functions://postgres/public/mfa_verification_attempt"
--
-- Until then the raw endpoint behaves exactly as it was measured. Enabling them is the only
-- step in this work that a person has to do by hand, and it is the step that makes the
-- protection true of the endpoint rather than only of the app.
--
-- ── WHY THESE FAIL OPEN WHEN EVERYTHING ELSE HERE FAILS CLOSED ───────────────────────────
--
-- supabase/functions/_shared/ratelimit.ts refuses when it cannot consult the limiter, and
-- that is right: it guards one client, and if it breaks that client stops working while
-- everything else carries on.
--
-- These run INSIDE GoTrue's token endpoint, for every client, on every attempt. A hook that
-- raises takes sign-in down for the whole product — web, mobile, the Super Admin, everybody —
-- with no way back in to fix it. So the exception handler at the bottom of each returns
-- 'continue'. What that concedes is bounded: an internal error here drops the hook back to
-- today's behaviour, and today's behaviour is still covered by mobile-auth's own fail-closed
-- limiter on the path the app actually uses. Choosing the other way round would trade a
-- guessing attack that needs the password for a certain, total, self-inflicted outage.
-- ─────────────────────────────────────────────────────────────────────────────────────────

-- Deliberately LOOSER than LIMITS.loginPerIdentifier (8 / 900s) and LIMITS.mfaVerifyPerUser
-- (6 / 600s) in supabase/functions/_shared/ratelimit.ts. The Edge Function is the primary
-- control for the app and should always be the one that trips first, so a NIVORA user never
-- sees a GoTrue-worded refusal when our own, better-worded one was available. These numbers
-- are the backstop for callers that skipped the app entirely.
create or replace function app.auth_hook_limit(p_scope text, p_subject uuid, p_max int, p_window_seconds int)
returns int
language plpgsql security definer set search_path = app, public as $fn$
declare v_key text; v_allowed boolean; v_retry int;
begin
  -- Same digest as hashKey() in _shared/ratelimit.ts and lib/rate-limit.ts: sha256, hex, first
  -- 48 characters. app.rate_limits must never become a readable list of user ids, and it is
  -- readable by nobody anyway, but the two rules agree so the table has one format in it.
  v_key := substr(encode(sha256(convert_to(p_scope || ':' || p_subject::text, 'UTF8')), 'hex'), 1, 48);
  select allowed, retry_after_seconds into v_allowed, v_retry
    from public.rate_limit(v_key, p_max, p_window_seconds);
  if v_allowed then return 0; end if;
  return greatest(1, coalesce(v_retry, p_window_seconds));
end $fn$;

-- Clears a subject's failure budget. Called when the credential was CORRECT, so that a
-- resident who fumbles their password four times and then gets it right does not walk around
-- for the next quarter of an hour one typo away from a lockout. An attacker who never guesses
-- correctly never reaches this.
create or replace function app.auth_hook_reset(p_scope text, p_subject uuid)
returns void
language plpgsql security definer set search_path = app, public as $fn$
begin
  delete from app.rate_limits
   where key = substr(encode(sha256(convert_to(p_scope || ':' || p_subject::text, 'UTF8')), 'hex'), 1, 48);
end $fn$;

create or replace function public.password_verification_attempt(event jsonb)
returns jsonb
language plpgsql security definer set search_path = app, public as $fn$
declare
  v_user   uuid;
  v_valid  boolean;
  v_wait   int;
  v_role   public.user_role;
  v_hostel uuid;
begin
  v_user  := nullif(event->>'user_id', '')::uuid;
  v_valid := coalesce((event->>'valid')::boolean, false);

  -- No subject means nothing to key on; GoTrue is asking about an address that resolved to no
  -- user. Let it answer for itself — inventing a bucket here would let anyone exhaust one
  -- shared counter and lock every account out at once.
  if v_user is null then
    return jsonb_build_object('decision', 'continue');
  end if;

  if v_valid then
    perform app.auth_hook_reset('hook:login', v_user);
    return jsonb_build_object('decision', 'continue');
  end if;

  v_wait := app.auth_hook_limit('hook:login', v_user, 10, 900);

  if v_wait = 0 then
    -- Under the limit: record the failure so the trail sees raw-endpoint attempts at all, and
    -- so detect_suspicious_activity() can count them. Above the limit we deliberately STOP
    -- writing (see below), which is why this is inside the branch.
    select role, hostel_id into v_role, v_hostel from public.users where id = v_user;
    perform public.audit_event(
      'auth.login.failed', 'user', v_user::text, v_hostel,
      jsonb_build_object('surface', 'gotrue_hook'), null, null, v_user, v_role);
    return jsonb_build_object('decision', 'continue');
  end if;

  -- Rejected. Exactly ONE audit row per window per user from here on: an attacker who keeps
  -- hammering after the refusal must not be able to fill audit_log on a free-plan database,
  -- and app.raise_security_alert() has already deduplicated the alert to one per hour anyway.
  -- auth_hook_limit with max = 1 is that "once per window" gate, on the same counter.
  if app.auth_hook_limit('hook:login:reported', v_user, 1, 900) = 0 then
    select role, hostel_id into v_role, v_hostel from public.users where id = v_user;
    perform public.audit_event(
      'auth.login.hook_rejected', 'user', v_user::text, v_hostel,
      jsonb_build_object('surface', 'gotrue_hook', 'retryAfterSeconds', v_wait), null, null, v_user, v_role);
  end if;

  -- The wording matters twice over. To a person it is the honest answer. To
  -- supabase/functions/mobile-auth it is the marker that turns a GoTrue error into a 429
  -- rather than into "your password is wrong" — it matches /too many attempts/i there.
  return jsonb_build_object(
    'decision', 'reject',
    'message', 'Too many attempts. Please wait and try again.');
exception when others then
  -- See the header: this hook is in the path of every sign-in for every client.
  raise warning '[nivora] password_verification_attempt fell through: %', sqlerrm;
  return jsonb_build_object('decision', 'continue');
end $fn$;

create or replace function public.mfa_verification_attempt(event jsonb)
returns jsonb
language plpgsql security definer set search_path = app, public as $fn$
declare
  v_user   uuid;
  v_valid  boolean;
  v_wait   int;
  v_role   public.user_role;
  v_hostel uuid;
begin
  v_user  := nullif(event->>'user_id', '')::uuid;
  v_valid := coalesce((event->>'valid')::boolean, false);

  if v_user is null then
    return jsonb_build_object('decision', 'continue');
  end if;

  if v_valid then
    perform app.auth_hook_reset('hook:mfa', v_user);
    return jsonb_build_object('decision', 'continue');
  end if;

  v_wait := app.auth_hook_limit('hook:mfa', v_user, 8, 600);

  if v_wait = 0 then
    select role, hostel_id into v_role, v_hostel from public.users where id = v_user;
    perform public.audit_event(
      'auth.mfa.failed', 'user', v_user::text, v_hostel,
      jsonb_build_object('surface', 'gotrue_hook'), null, null, v_user, v_role);
    return jsonb_build_object('decision', 'continue');
  end if;

  if app.auth_hook_limit('hook:mfa:reported', v_user, 1, 600) = 0 then
    select role, hostel_id into v_role, v_hostel from public.users where id = v_user;
    perform public.audit_event(
      'auth.mfa.rate_limited', 'user', v_user::text, v_hostel,
      jsonb_build_object('surface', 'gotrue_hook', 'retryAfterSeconds', v_wait), null, null, v_user, v_role);
  end if;

  return jsonb_build_object(
    'decision', 'reject',
    'message', 'Too many attempts. Please wait and try again.');
exception when others then
  raise warning '[nivora] mfa_verification_attempt fell through: %', sqlerrm;
  return jsonb_build_object('decision', 'continue');
end $fn$;

-- GoTrue calls these as supabase_auth_admin and nobody else may call them at all. They are
-- SECURITY DEFINER so they can reach public.rate_limit() and public.audit_event(), both of
-- which are service_role-only; that is the whole reason for the definer marking, and it is
-- also the reason the grants below have to be this narrow.
revoke all on function app.auth_hook_limit(text, uuid, int, int) from public, anon, authenticated;
revoke all on function app.auth_hook_reset(text, uuid) from public, anon, authenticated;
revoke all on function public.password_verification_attempt(jsonb) from public, anon, authenticated;
revoke all on function public.mfa_verification_attempt(jsonb) from public, anon, authenticated;

grant execute on function public.password_verification_attempt(jsonb) to supabase_auth_admin;
grant execute on function public.mfa_verification_attempt(jsonb) to supabase_auth_admin;
