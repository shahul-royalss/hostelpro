-- ─────────────────────────────────────────────────────────────────────────────
-- THE ONLINE PAYMENT PATH JOINS THE REST OF THE PRODUCT ON THE HOSTEL'S CLOCK
--
-- `app.today()` (Asia/Kolkata) was introduced on 2026-09-01 and its own comment states the rule:
-- "Use this, never current_date, wherever 'today' is the day a person at the desk would name.
-- current_date is UTC on this instance and is 5h30m behind."
--
-- public.wd_record_payment — the path a warden uses to record cash — already follows that rule
-- (two calls to app.today(), no current_date). The two Razorpay functions never did:
--
--     rz_open_intent   v_period text := to_char(current_date, 'YYYY-MM')   -- the month charged
--     rz_credit_fee    ... wd_record_payment(..., current_date, ...)       -- the receipt date
--
-- So the manual path and the online path disagreed about what day it is. That is an unfinished
-- migration, not a decision, and it produced two real defects:
--
-- 1. THE RECEIPT DATE, WRONG EVERY NIGHT. Between 00:00 and 05:30 IST — a window that exists
--    every single day — current_date is still yesterday. A resident who paid at 01:00 on the 5th
--    got a fee row dated the 4th. Every online payment in that window is misdated in the ledger
--    the hostel keeps and the resident is shown.
--
-- 2. THE MONTH CHARGED, WRONG ON THE 1st. In the same window on the 1st of a month, the server
--    opens the order against the PREVIOUS month while the app screen — which derives the month
--    from the handset, in IST — shows and then polls the current one. Three things follow, and
--    the third is the one that hurts:
--      * the resident is shown October's dues and charged September's;
--      * if September was already settled, rz_open_intent refuses and the screen says nothing is
--        due while plainly displaying a due amount;
--      * the confirmation poll in pay_rent.dart watches the month the handset named, so a
--        payment that SUCCEEDED and was credited to the other month is never seen by the poll.
--        The resident is told their payment did not confirm while their money is in the ledger.
--
--    Nobody is double-charged — a second attempt hits the same "already paid" check — but being
--    told a successful payment failed is the kind of thing that makes someone pay twice by hand.
--
-- ── WHY THIS REWRITES THE LIVE DEFINITION INSTEAD OF RESTATING THE BODIES ────────────────────
--
-- Both functions are long, and copying their bodies into this file to change one token each is
-- how a body gets silently rewritten to an older version. This reads what is actually installed
-- with pg_get_functiondef, refuses to act unless it finds EXACTLY ONE current_date in each, and
-- replays the definition with that one token swapped. If either function is ever edited to hold
-- a second current_date, this raises instead of guessing which one was meant.
--
-- Replayable on a clean database: 2026-08-24-payments.sql creates both functions with
-- current_date, and this runs after it.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare
  r        record;
  v_def    text;
  v_hits   int;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('rz_open_intent', 'rz_credit_fee')
     order by p.proname
  loop
    v_def := pg_get_functiondef(r.oid);

    select count(*) into v_hits
      from regexp_matches(v_def, 'current_date', 'g');

    if v_hits = 0 then
      raise notice 'public.% already uses no current_date — leaving it alone', r.proname;
      continue;
    elsif v_hits > 1 then
      raise exception
        'public.% contains % occurrences of current_date; this migration only knows how to '
        'replace exactly one. Update it deliberately rather than letting it guess.',
        r.proname, v_hits;
    end if;

    -- Both sites are value positions: to_char(current_date, 'YYYY-MM') and the p_paid_on
    -- argument. app.today() returns date, exactly as current_date does, so neither call
    -- signature nor type changes.
    v_def := replace(v_def, 'current_date', 'app.today()');

    execute v_def;
    raise notice 'public.% now reads the day in Asia/Kolkata', r.proname;
  end loop;
end $$;

-- ═══ AFTER APPLYING ═══
-- Both Razorpay functions on the hostel clock, and the manual path unchanged:
--
--   select p.proname,
--          (select count(*) from regexp_matches(pg_get_functiondef(p.oid), 'current_date', 'g')) as current_date,
--          (select count(*) from regexp_matches(pg_get_functiondef(p.oid), 'app\.today\(\)', 'g')) as app_today
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('rz_open_intent', 'rz_credit_fee', 'wd_record_payment')
--    order by p.proname;
--
-- Expected: current_date = 0 for all three; app_today = 1, 1 and 2 respectively.
--
-- supabase/functions/razorpay-order/index.ts computes the same month in Asia/Kolkata and must be
-- deployed with this. Its guard compares its month against the one rz_open_intent derives, so a
-- deploy of one without the other reintroduces the disagreement this removes.
