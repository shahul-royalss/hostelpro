-- ════════════════════════════════════════════════════════════════════════════════════════════
-- "TODAY" MEANS THE HOSTEL'S TODAY, NOT THE DATABASE SERVER'S
--
-- ═══ THE MEASUREMENT ═══
-- Taken against the live project (nimxvgzscbanhtvgnjll) on 2026-09-01, 02:18 IST:
--
--     select current_setting('TimeZone'), current_date, (now() at time zone 'Asia/Kolkata')::date;
--     -> UTC | 2026-08-31 | 2026-09-01
--
-- A manager recorded one expense through the app at that moment. The sheet defaults its date
-- from `DateTime.now()` on the handset (features/manager/expenses/record_money_sheet.dart:67),
-- so the row landed with date = 2026-09-01 — correct, and what the person would write on paper.
-- rpc_hostel_stats then answered:
--
--     expenses_today = 0        expenses_month = 450
--
-- because it compared that date against `current_date`, which is UTC and was still 2026-08-31.
-- Every day between 00:00 and 05:30 IST, the two "today" money tiles on the manager's home
-- screen read zero while the day's takings sit one row away. Every evening between 18:30 and
-- midnight IST the same skew runs the other way: money recorded yesterday evening counts as
-- today's. India does not observe daylight saving, so the offset is a flat +05:30 and the
-- window is the same every day of the year.
--
-- The function already knew the rule. Its visitors_today line reads
--
--     (check_in_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date
--     -- "today" in hostel-local time (India) — the app's day boundary is IST, not UTC
--
-- and the two lines directly beneath it did not follow it. This migration finishes that thought
-- and gives the rule a name so the next "today" cannot be written the other way by accident.
--
-- ═══ WHAT IS AND IS NOT CHANGED ═══
-- CHANGED — every place where a date chosen on an Indian handset is compared with, or defaulted
-- from, the server's idea of today:
--   · rpc_hostel_stats: revenue_today / expenses_today, and the p_period_month default
--   · expenses.date / revenues.date column defaults (the Dart layer deliberately omits the
--     field and lets the column default fire — finance_repository.dart:96)
--   · students.date_of_joining default
--   · wd_record_payment's p_paid_on default and its not-in-the-future guard
--   · app.fee_status_compute, which stamps paid_on when a payment arrives without one
--
-- NOT CHANGED — subscription arithmetic (`end_date < current_date`, the 15-day expiring window,
-- sa_renew_subscription). Those compare two dates that both originate in the database, nothing
-- a client picked is involved, and a subscription that expires half a day later than a
-- warden's calendar says is not a defect anybody can see. Widening the change to them would
-- churn the one part of the schema whose behaviour is load-bearing for Hard rule §4.4.
--
-- ═══ WHY A FUNCTION AND NOT `set timezone` ═══
-- Setting the database timezone to Asia/Kolkata would fix all of this in one line and break
-- more than it fixed: `timestamptz` display, every `at time zone` already written against UTC,
-- and any future tenant outside India. The dates in this product belong to a building in India;
-- the server does not. Naming that fact is the smaller and more honest change.
-- ════════════════════════════════════════════════════════════════════════════════════════════

-- The calendar day at the hostel. STABLE, not IMMUTABLE: it moves with the clock, so it can be
-- used in a DEFAULT and in a WHERE but never in an index predicate.
create or replace function app.today() returns date
language sql stable set search_path = public as $$
  select (now() at time zone 'Asia/Kolkata')::date
$$;

comment on function app.today() is
  'The current calendar day in hostel-local time (Asia/Kolkata). Use this, never current_date, '
  'wherever "today" is the day a person at the desk would name. current_date is UTC on this '
  'instance and is 5h30m behind. See db/migrations/2026-09-01-hostel-local-today.sql.';

grant execute on function app.today() to authenticated, service_role;

-- ── column defaults ─────────────────────────────────────────────────────────────────────────
alter table public.expenses  alter column date            set default app.today();
alter table public.revenues  alter column date            set default app.today();
alter table public.students  alter column date_of_joining set default app.today();

-- ── the paid_on stamp ───────────────────────────────────────────────────────────────────────
create or replace function app.fee_status_compute() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.amount_paid <= 0 then
    new.status := 'unpaid';
  elsif new.amount_paid >= new.amount_due then
    new.status := 'paid';
  else
    new.status := 'partial';
  end if;
  -- app.today(), not current_date: a payment taken at the desk at 01:00 IST was taken today,
  -- and dating it yesterday puts it in the wrong month for anyone paying on the 1st.
  if new.amount_paid > 0 and new.paid_on is null then
    new.paid_on := app.today();
  end if;
  return new;
end $$;

-- ── the desk's own record of a payment ──────────────────────────────────────────────────────
-- Recreated verbatim except for the two date expressions. p_paid_on keeps its one day of slack:
-- the guard exists to refuse a mis-keyed year, not to police a handset's clock, and a phone
-- an hour ahead of the server must not be told its cashier is time-travelling.
create or replace function public.wd_record_payment(
  p_student_id uuid, p_period_month text, p_amount numeric, p_mode public.payment_mode,
  p_paid_on date default null, p_notes text default null
) returns public.fee_payments
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_fee numeric; v_status public.student_status; v_row public.fee_payments;
        v_paid_on date := coalesce(p_paid_on, app.today());
begin
  select hostel_id, monthly_fee, status into v_hostel, v_fee, v_status
    from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  if v_status = 'vacated' then
    raise exception 'That student has been checked out — no further payments can be recorded.' using errcode = 'P0001';
  end if;
  if p_amount is null or p_amount = 'NaN'::numeric then
    raise exception 'Enter a valid amount.' using errcode = 'P0001';
  end if;
  if p_amount <= 0 then raise exception 'Amount must be greater than zero.' using errcode = 'P0001'; end if;
  if p_amount > 10000000 then raise exception 'That amount is too large.' using errcode = 'P0001'; end if;
  if v_paid_on > app.today() + 1 then
    raise exception 'Payment date cannot be in the future.' using errcode = 'P0001';
  end if;

  insert into public.fee_payments (hostel_id, student_id, period_month, amount_due, amount_paid, paid_on, mode, notes, recorded_by)
  values (v_hostel, p_student_id, p_period_month, v_fee, p_amount, v_paid_on, p_mode, p_notes, auth.uid())
  on conflict (student_id, period_month) do update
    set amount_paid = public.fee_payments.amount_paid + excluded.amount_paid,
        paid_on = excluded.paid_on, mode = excluded.mode,
        notes = coalesce(excluded.notes, public.fee_payments.notes),
        recorded_by = excluded.recorded_by
  returning * into v_row;
  return v_row;
end $$;

revoke all on function public.wd_record_payment(uuid, text, numeric, public.payment_mode, date, text) from public, anon;
grant execute on function public.wd_record_payment(uuid, text, numeric, public.payment_mode, date, text) to authenticated, service_role;

-- ── the dashboard ───────────────────────────────────────────────────────────────────────────
-- Recreated verbatim except for the three date expressions marked below.
create or replace function public.rpc_hostel_stats(p_hostel_id uuid, p_period_month text default to_char(app.today(), 'YYYY-MM'))
returns table (
  total_beds int, occupied_beds int, active_students int, open_complaints int,
  fees_collected numeric, fees_pending numeric, students_paid int, students_unpaid int,
  pending_leaves int, visitors_today int, pending_tasks int,
  revenue_today numeric, expenses_today numeric, revenue_month numeric, expenses_month numeric,
  subscription_days_left int, subscription_state public.subscription_status
)
language sql stable security invoker set search_path = public as $$
  with led as (select * from public.rpc_fee_ledger(p_hostel_id, p_period_month))
  select
    (select count(*)::int from public.beds where hostel_id = p_hostel_id),
    (select count(*)::int from public.beds where hostel_id = p_hostel_id and student_id is not null),
    (select count(*)::int from public.students where hostel_id = p_hostel_id and status <> 'vacated'),
    (select count(*)::int from public.complaints where hostel_id = p_hostel_id and status <> 'resolved'),
    coalesce((select sum(amount_paid) from led), 0),
    coalesce((select sum(greatest(amount_due - amount_paid, 0)) from led), 0),
    (select count(*)::int from led where status = 'paid'),
    (select count(*)::int from led where status <> 'paid'),
    (select count(*)::int from public.leaves where hostel_id = p_hostel_id and status = 'pending'),
    -- "today" in hostel-local time (India) — the app's day boundary is IST, not UTC
    (select count(*)::int from public.visitors where hostel_id = p_hostel_id
       and (check_in_at at time zone 'Asia/Kolkata')::date = app.today()),
    (select count(*)::int from public.tasks where hostel_id = p_hostel_id and status <> 'done' and deleted_at is null),
    -- ...and so do these two, which is the whole point of this migration. They read
    -- `date = current_date` until 2026-09-01 and so were empty for the first five and a half
    -- hours of every Indian day.
    coalesce((select sum(amount) from public.revenues where hostel_id = p_hostel_id and date = app.today() and deleted_at is null), 0),
    coalesce((select sum(amount) from public.expenses where hostel_id = p_hostel_id and date = app.today() and deleted_at is null), 0),
    coalesce((select sum(amount) from public.revenues where hostel_id = p_hostel_id and to_char(date,'YYYY-MM') = p_period_month and deleted_at is null), 0),
    coalesce((select sum(amount) from public.expenses where hostel_id = p_hostel_id and to_char(date,'YYYY-MM') = p_period_month and deleted_at is null), 0),
    app.subscription_days_left(p_hostel_id),
    app.subscription_state(p_hostel_id)
$$;

revoke all on function public.rpc_hostel_stats(uuid, text) from public, anon;
grant execute on function public.rpc_hostel_stats(uuid, text) to authenticated, service_role;
