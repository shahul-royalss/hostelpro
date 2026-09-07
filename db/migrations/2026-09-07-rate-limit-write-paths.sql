-- THE MOBILE APP'S WRITES HAD NO CEILING OF ANY KIND.
--
-- supabase/functions/_shared/ratelimit.ts is a good piece of work — durable Postgres counters,
-- hashed keys, IP and identifier both spent, a window that expires rather than an
-- attacker-triggerable lockout. And the Flutter app never reaches it. It was built for the
-- Next.js web app and it covers the Edge Functions that mint accounts; every write the app
-- makes afterwards goes straight to PostgREST, where nothing counts anything.
--
-- Two of those writes are amplifiers, which is what makes this worth doing before launch rather
-- than after:
--
--   * An INSERT into announcements fires app.announcements_after_insert, which writes ONE
--     notifications row per active user in the hostel. One request, ~45 rows, and a push to
--     every resident's phone.
--   * An INSERT into complaints fires its own fan-out to the hostel's staff.
--
-- A single warden token in a loop therefore multiplies into tens of thousands of rows on a
-- free-tier 500MB disk.
--
-- ── WHY A TRIGGER AND NOT A REWRITTEN RPC ─────────────────────────────────────────────────
--
-- These two are plain table INSERTs through RLS, not RPCs — there is no function body to add a
-- line to. A BEFORE INSERT trigger is also strictly additive: it can refuse an insert, and it
-- cannot change what a successful one does. That carries none of the regression risk of
-- reopening wd_record_payment or rz_open_intent to thread a check through them, and those two
-- remain outstanding rather than pretended-done.
--
-- ── AND WHY IT FAILS OPEN ─────────────────────────────────────────────────────────────────
--
-- The owner's words were "rate limiting which is not gonna crash our system". The Edge Function
-- limiter fails CLOSED, and that is right for a login: refusing to authenticate when you cannot
-- count attempts is the safe direction. It is the WRONG direction here. If the counter is
-- briefly unavailable, failing closed costs a warden the ability to post a notice about the
-- water supply; failing open costs a few extra rows.
--
-- So the limiter call sits in its own block with its own handler, and anything unexpected from
-- it means allow. The deliberate refusal is raised OUTSIDE that block — putting `raise` inside a
-- `when others then` scope would have the handler swallow the very exception it exists to
-- produce, giving a fail-open limiter that can never refuse anything and looks identical to a
-- working one until the day it matters.
--
-- ── VERIFIED, NOT ASSERTED ────────────────────────────────────────────────────────────────
--
-- Three probes were run against the live database:
--
--   budget of 5   calls 1-5 allowed, calls 6 and 7 refused with the readable sentence
--   null verdict  ALLOWED  (a counter that does not answer must not block a write)
--   limiter throws ALLOWED (make_interval overflow inside public.rate_limit)
--
-- The second probe is the one worth keeping: an earlier version of it passed `1/0` as an
-- argument, which the CALLER evaluates before app.spend is entered, so it proved nothing about
-- the guarded block. A window of 2^31-1 overflows inside public.rate_limit itself, which is the
-- path that actually needed proving.

create or replace function app.spend(
  p_bucket text,
  p_max integer,
  p_window_seconds integer,
  p_message text
) returns void
language plpgsql security definer set search_path = app, public as $$
declare
  v_allowed boolean := true;
  v_retry   integer := 0;
  v_who     text := coalesce(auth.uid()::text, 'anon');
begin
  begin
    select allowed, retry_after_seconds
      into v_allowed, v_retry
      from public.rate_limit(p_bucket || ':' || v_who, p_max, p_window_seconds);
    -- A limiter that returns no row is a limiter that did not answer. Same treatment as a throw.
    if v_allowed is null then v_allowed := true; end if;
  exception when others then
    v_allowed := true;  -- FAIL OPEN. See the header.
  end;

  if not v_allowed then
    raise exception '%', p_message
      using errcode = 'P0001',
            hint = format('Try again in about %s seconds.', greatest(v_retry, 1));
  end if;
end $$;

comment on function app.spend(text, integer, integer, text) is
  'Spends one unit of a per-user budget, refusing with a readable sentence when it is gone. '
  'Fails OPEN: if the counter cannot be reached the write proceeds. For the login path, which '
  'must fail closed instead, see supabase/functions/_shared/ratelimit.ts.';

revoke all on function app.spend(text, integer, integer, text) from public, anon;

-- ── THE TWO FAN-OUTS ──────────────────────────────────────────────────────────────────────
--
-- The numbers are chosen against what the job looks like, not against what is easy to type. A
-- warden posting notices writes a handful on a busy day; twelve an hour is far beyond real use
-- and far below the volume that hurts. Complaints are raised by residents one at a time, so ten
-- an hour leaves room for a genuinely bad morning.

create or replace function app.rl_announcement() returns trigger
language plpgsql security definer set search_path = app, public as $$
begin
  perform app.spend(
    'announcement', 12, 3600,
    'You have posted a lot of notices in the last hour. Give it a few minutes before the next one.'
  );
  return new;
end $$;

create or replace function app.rl_complaint() returns trigger
language plpgsql security definer set search_path = app, public as $$
begin
  perform app.spend(
    'complaint', 10, 3600,
    'You have raised several complaints in the last hour. Please add to an existing one instead, '
    'or try again shortly.'
  );
  return new;
end $$;

drop trigger if exists announcements_rate_limit on public.announcements;
create trigger announcements_rate_limit
  before insert on public.announcements
  for each row execute function app.rl_announcement();

drop trigger if exists complaints_rate_limit on public.complaints;
create trigger complaints_rate_limit
  before insert on public.complaints
  for each row execute function app.rl_complaint();

-- ═══ STILL OUTSTANDING AFTER THIS ═══
--   * wd_record_payment — each call upserts fee_payments AND fires a notification.
--   * rz_open_intent / razorpay-order — the order-minting loop, which is the money one.
--   * password_reset_gate — a 200-request product-wide bucket, callable by anon.
--   * mobile-auth's per-IP bucket — collapses to one shared bucket on carrier CGNAT.
-- None of those are covered here. They are named so the gap is visible rather than assumed shut.
