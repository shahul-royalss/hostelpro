-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- PASSWORD RESET — THE ONE DURABLE LIMIT ON "EMAIL ME A LINK"
-- ═══════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY THIS IS IN POSTGRES AND NOT IN THE APP.
--
-- The forgot-password form is reachable with NO SESSION — that is the whole point of it, the
-- person is locked out. So the phone talks to GoTrue's public /auth/v1/recover directly, exactly
-- as the email-verification flow talks to /auth/v1/otp directly, and for the same measured
-- reason: putting an Edge Function in the SENDING path is what produced "The Nivora server did
-- not answer" on this free-tier NANO instance (see supabase/functions/_shared/verification.ts).
--
-- A cooldown enforced inside the process being asked to obey it is a suggestion. A counter in
-- the database is not. `app.rate_limits` is the durable one this project already has, and
-- `public.rate_limit()` is granted to service_role ONLY — measured 2026-09-02:
--
--     has_function_privilege('anon','public.rate_limit(text,int,int)','execute')  ->  false
--
-- so a signed-out caller cannot spend it. This function is the narrow, signed-out-safe door to
-- the same table: one purpose, two fixed windows, no arguments that can be turned into an
-- arbitrary key, and it reads NO user table at all.
--
-- ═══ WHAT IT DOES NOT DO, SAID PLAINLY ═══
--
-- It does not stop an attacker. /auth/v1/recover is a public endpoint and the anon key is
-- printed inside the APK, so anybody who wants to make this project send mail can always call
-- GoTrue directly and never touch this function. What actually bounds the mail is GoTrue's own
-- SMTP_MAX_FREQUENCY (60s per address) and GOTRUE_RATE_LIMIT_EMAIL_SENT (project-wide/hour).
-- This constrains OUR app — it stops a resident tapping "send" eleven times and it stops a
-- stolen handset walking a phone book — and it is honest about being that and not a boundary.
--
-- ═══ WHY IT CANNOT BE AN ENUMERATION ORACLE ═══
--
-- It never looks the identifier up. It hashes the string it was handed and counts it. The
-- refusal therefore varies with REQUEST VOLUME and never with whether an account exists, which
-- is the same property lib/actions/password-reset.ts relies on in the web app.
--
-- The address is hashed HERE rather than on the phone, deliberately: it means `app.rate_limits`
-- never holds a resident's email address in plain text (the table is swept daily by
-- app.apply_retention(), but a row that never contained an address cannot leak one), and it
-- means the mobile client needs no crypto dependency to participate.
--
-- ═══ THE GLOBAL BUCKET, AND WHY IT IS CHECKED FIRST ═══
--
-- Granting `anon` a function that INSERTS is granting `anon` the ability to create rows. The
-- per-identifier key is a fixed-length hash, so the key space is not arbitrary text, but a sweep
-- across a phone book would still mint one row per number tried. The global bucket is checked
-- and spent BEFORE the per-identifier row is inserted, so the number of NEW rows this function
-- can create is bounded by c_all_max per hour, whatever is thrown at it. Everything older than
-- a day is already removed by app.apply_retention() — which is EXTENDED for nothing here,
-- because its existing `delete from app.rate_limits where window_start < now() - interval '1 day'`
-- covers these keys exactly as it covers every other one.
--
-- 200/hour is far above real use — the largest tenant on this project has 45 beds — and far
-- below anything that costs storage worth naming.
create or replace function public.password_reset_gate(p_identifier text)
returns table (allowed boolean, retry_after_seconds int)
language plpgsql
security definer
set search_path = app, public
as $$
declare
  v_now  timestamptz := now();
  v_id   text := lower(btrim(coalesce(p_identifier, '')));
  v_row  app.rate_limits%rowtype;
  c_id_max     constant int      := 3;
  c_id_window  constant interval := interval '1 hour';
  c_all_max    constant int      := 200;
  c_all_window constant interval := interval '1 hour';
begin
  -- ── The floodwall. Spent first, so a sweep cannot mint unbounded per-identifier rows. ──
  insert into app.rate_limits (key, window_start, count)
  values ('pwreset:all', v_now, 1)
  on conflict (key) do update set
    count = case when app.rate_limits.window_start < v_now - c_all_window
                 then 1 else app.rate_limits.count + 1 end,
    window_start = case when app.rate_limits.window_start < v_now - c_all_window
                        then v_now else app.rate_limits.window_start end
  returning * into v_row;

  if v_row.count > c_all_max then
    allowed := false;
    retry_after_seconds :=
      greatest(1, ceil(extract(epoch from (v_row.window_start + c_all_window - v_now)))::int);
    return next;
    return;
  end if;

  -- ── Per address. sha256 of the normalised string; the address itself is never stored. ──
  insert into app.rate_limits (key, window_start, count)
  values ('pwreset:id:' || encode(sha256(convert_to(v_id, 'UTF8')), 'hex'), v_now, 1)
  on conflict (key) do update set
    count = case when app.rate_limits.window_start < v_now - c_id_window
                 then 1 else app.rate_limits.count + 1 end,
    window_start = case when app.rate_limits.window_start < v_now - c_id_window
                        then v_now else app.rate_limits.window_start end
  returning * into v_row;

  allowed := v_row.count <= c_id_max;
  retry_after_seconds := case
    when allowed then 0
    else greatest(1, ceil(extract(epoch from (v_row.window_start + c_id_window - v_now)))::int)
  end;
  return next;
end $$;

-- The whole point is that a SIGNED-OUT person can spend it. `public` is revoked first so the
-- grant below is the entire access list rather than an addition to whatever PUBLIC had.
revoke all on function public.password_reset_gate(text) from public;
grant execute on function public.password_reset_gate(text) to anon, authenticated;

comment on function public.password_reset_gate(text) is
  'Durable per-address rate limit for the forgot-password send. Reads no user table, so its '
  'refusal varies with request volume and never with whether an account exists. Hashes the '
  'identifier so app.rate_limits never holds an address. Swept by app.apply_retention().';
