-- ─────────────────────────────────────────────────────────────────────────────
-- TWO KINDS OF EXPENSE, AND THE MONTHS SIDE BY SIDE
--
-- The product owner: "add two menu options in manager in expenses section... one time monthly
-- expense... day to day expenses... what manager records it has to show perfectly in graphs,
-- stats" — and, for the owner and the manager, "graphs, stats dashboard... expenses... compares
-- other months".
--
-- ── expenses.kind ───────────────────────────────────────────────────────────────────────────
--
--   monthly  — paid once for a month: the building's rent, salaries, the electricity bill.
--   daily    — day-to-day spending: vegetables, gas, a plumber, cleaning supplies.
--
-- It is a separate axis from `category` on purpose. Electricity can be a monthly bill in one PG
-- and a daily prepaid top-up in another; folding the two into one enum would force every PG into
-- one of those shapes.
--
-- EXISTING ROWS BECOME 'daily', and that is a default, not a classification. Nothing in the old
-- rows says which kind they were, and re-labelling a year of somebody's books by guessing from
-- the category would put invented numbers into exactly the graphs this migration exists to draw.
--
-- ── THE STATS ARE READ UNDER RLS ────────────────────────────────────────────────────────────
--
-- Both functions are SECURITY INVOKER, so expenses_select decides who sees what — the hostel's
-- owner, its manager, the Super Admin — exactly as it does for the expense list. They aggregate
-- in the database rather than shipping every row to the phone, so a PG that records forty
-- vegetable purchases a month draws its twelve-month chart from at most a few hundred grouped
-- rows. expenses_hostel_date_idx (hostel_id, date desc) already covers both range scans.
--
-- Months are calendar months in Asia/Kolkata (app.today()), not UTC: at 1am on the 1st in India
-- it is still the previous month in UTC, and a chart that put tonight's gas cylinder into last
-- month would be wrong for five and a half hours every month.
-- ─────────────────────────────────────────────────────────────────────────────

do $$ begin
  create type public.expense_kind as enum ('monthly', 'daily');
exception when duplicate_object then null; end $$;

alter table public.expenses
  add column if not exists kind public.expense_kind not null default 'daily';

-- Month totals, split by kind and category, for the last p_months months including this one.
-- Clamped to 1..24 so a client cannot ask the database to scan a decade.
create or replace function public.rpc_expense_months(p_hostel_id uuid, p_months int default 6)
returns table(period_month text, kind public.expense_kind, category public.expense_category,
              total numeric, entries int)
language sql stable set search_path = public as $$
  with bounds as (
    select (date_trunc('month', app.today())
              - make_interval(months => greatest(least(coalesce(p_months, 6), 24), 1) - 1))::date as from_day,
           (date_trunc('month', app.today()) + interval '1 month')::date as to_day
  )
  select to_char(date_trunc('month', e.date), 'YYYY-MM'),
         e.kind,
         e.category,
         sum(e.amount),
         count(*)::int
    from public.expenses e, bounds b
   where e.hostel_id = p_hostel_id
     and e.deleted_at is null
     and e.date >= b.from_day
     and e.date <  b.to_day
   group by 1, 2, 3
   order by 1, 2, 3
$$;

-- Day totals for one month, split by kind — the "day to day" line.
create or replace function public.rpc_expense_days(p_hostel_id uuid, p_period_month text)
returns table(day date, kind public.expense_kind, total numeric, entries int)
language sql stable set search_path = public as $$
  select e.date, e.kind, sum(e.amount), count(*)::int
    from public.expenses e
   where e.hostel_id = p_hostel_id
     and e.deleted_at is null
     and p_period_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     and e.date >= to_date(p_period_month || '-01', 'YYYY-MM-DD')
     and e.date <  (to_date(p_period_month || '-01', 'YYYY-MM-DD') + interval '1 month')::date
   group by e.date, e.kind
   order by e.date, e.kind
$$;

revoke all on function public.rpc_expense_months(uuid, int) from public, anon;
revoke all on function public.rpc_expense_days(uuid, text) from public, anon;
grant execute on function public.rpc_expense_months(uuid, int) to authenticated;
grant execute on function public.rpc_expense_days(uuid, text) to authenticated;
