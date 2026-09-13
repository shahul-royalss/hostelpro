-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO PG (PLAY REVIEW): ENOUGH OF A MONTH THAT A REVIEWER SEES THE PRODUCT WORK
--
-- Google Play reviewers sign in with the demo accounts handed to them under App access. Before
-- this file, "Demo PG (Play review)" held one resident, two complaints, one notice and nothing
-- else: no expenses, no revenue, no mess menu, no leave requests, no visitors. A reviewer opening
-- the owner's expense charts, the warden's leave queue or the resident's menu would have seen an
-- empty state on almost every screen — and "the app does nothing" is a review outcome.
--
-- WHAT IS ADDED, all of it fabricated, all of it scoped to this one hostel:
--   expenses   four months of monthly and day-to-day costs, so the month-by-month charts compare
--   revenues   non-rent money in (guest meals, a deposit) — rent is counted separately
--   menus      a full week, four meals a day
--   announcements  two more notices, one to residents and one to everyone
--   leaves     one pending request in the future, one approved trip in the past
--   visitors   one visitor on site now, one who came and left three days ago
--
-- WHAT IS DELIBERATELY NOT ADDED
--   tasks      a task must be assigned to a manager, and this hostel has none. Creating that
--              account is for the operator to do; see docs/play-console-submission.md.
--   accounts   none are created or changed here.
--   leave      no APPROVED leave covering today: leaves_after_change sets the resident to
--              'on_leave' when that happens, which would change what the resident home shows.
--
-- SIDE EFFECTS, checked before writing this: announcements_after_insert and leaves_after_change
-- write in-app notification rows for this hostel's own demo warden, owner and resident. Nothing
-- emails anyone. Push delivery is not configured, so push-send skips those rows.
--
-- IDEMPOTENT. Fixed ids in the d3300000- namespace the original demo rows already use, with
-- ON CONFLICT DO NOTHING, so applying this twice changes nothing the second time. Dates are
-- relative to the day it is first applied, so the data reads as recent.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from public.hostels
     where id = 'd3300000-0000-4000-8000-000000000001'
       and name = 'Demo PG (Play review)'
       and owner_user_id = '3bdd80c9-01f2-49df-855a-5ce3f136d0ea'
  ) then
    raise exception 'Demo PG (Play review) is not the row this seed was written for. Refusing to write.';
  end if;
end $$;

-- ── Expenses: four months, monthly and day-to-day ──────────────────────────────────────────
with months(m) as (values (0), (1), (2), (3)),
t(k, dom, category, amount, note, kind) as (values
  (0,  1, 'staff',       18000, 'Cook and cleaner salaries', 'monthly'),
  (1,  3, 'electricity',  6800, 'Electricity bill',          'monthly'),
  (2,  3, 'water',        1800, 'Water supply and tanker',   'monthly'),
  (3,  5, 'other',        1199, 'Broadband internet',        'monthly'),
  (4,  2, 'groceries',    2450, 'Vegetables and milk',       'daily'),
  (5,  6, 'groceries',    3120, 'Rice, dal and cooking oil', 'daily'),
  (6,  9, 'maintenance',   850, 'Tap and geyser repair',     'daily'),
  (7, 11, 'groceries',    1980, 'Vegetables and eggs',       'daily'),
  (8, 14, 'other',         640, 'Gas cylinder refill',       'daily'),
  (9, 17, 'groceries',    2760, 'Weekly provisions',         'daily')
)
insert into public.expenses (id, hostel_id, date, category, amount, note, kind, uploaded_by)
select ('d3300000-0000-4000-8000-' || lpad(to_hex(4096 + months.m * 16 + t.k), 12, '0'))::uuid,
       'd3300000-0000-4000-8000-000000000001',
       (date_trunc('month', current_date) - make_interval(months => months.m))::date + (t.dom - 1),
       t.category::public.expense_category,
       t.amount + ((months.m * 137) % 400),
       t.note,
       t.kind::public.expense_kind,
       '3bdd80c9-01f2-49df-855a-5ce3f136d0ea'
  from months cross join t
 where (date_trunc('month', current_date) - make_interval(months => months.m))::date + (t.dom - 1) <= current_date
on conflict (id) do nothing;

-- ── Revenues: non-rent money in ────────────────────────────────────────────────────────────
with months(m) as (values (0), (1), (2), (3)),
t(k, dom, source, amount, note) as (values
  (0,  4, 'mess',  4200, 'Guest meals'),
  (1,  8, 'other', 5000, 'Security deposit from a new resident'),
  (2, 12, 'mess',  2600, 'Weekend guest meals')
)
insert into public.revenues (id, hostel_id, date, source, amount, note, uploaded_by)
select ('d3300000-0000-4000-8000-' || lpad(to_hex(8192 + months.m * 16 + t.k), 12, '0'))::uuid,
       'd3300000-0000-4000-8000-000000000001',
       (date_trunc('month', current_date) - make_interval(months => months.m))::date + (t.dom - 1),
       t.source::public.revenue_source,
       t.amount + ((months.m * 211) % 500),
       t.note,
       '3bdd80c9-01f2-49df-855a-5ce3f136d0ea'
  from months cross join t
 where (date_trunc('month', current_date) - make_interval(months => months.m))::date + (t.dom - 1) <= current_date
   and not (t.k = 1 and months.m in (1, 3))
on conflict (id) do nothing;

-- ── Mess menu: a full week ─────────────────────────────────────────────────────────────────
with d(idx, dow) as (values (1, 'mon'), (2, 'tue'), (3, 'wed'), (4, 'thu'), (5, 'fri'), (6, 'sat'), (7, 'sun')),
m(meal, items) as (values
  ('breakfast', array['Idli, sambar, chutney', 'Poha, tea', 'Upma, coconut chutney', 'Aloo paratha, curd',
                      'Masala dosa, sambar', 'Bread omelette, tea', 'Puri, potato masala']),
  ('lunch',     array['Rice, dal, beans poriyal, curd', 'Veg biryani, raita', 'Rice, sambar, cabbage fry',
                      'Chapati, rajma, rice', 'Rice, rasam, potato fry', 'Lemon rice, curd rice',
                      'Veg pulao, paneer curry']),
  ('snacks',    array['Tea, biscuits', 'Samosa, tea', 'Onion bajji, tea', 'Coffee, sundal', 'Tea, mixture',
                      'Bread pakora, tea', 'Tea, murukku']),
  ('dinner',    array['Chapati, mixed veg, rice', 'Roti, paneer butter masala, dal tadka', 'Dosa, tomato chutney',
                      'Chapati, chana masala, rice', 'Egg curry and rice, paneer for vegetarians',
                      'Veg fried rice, gobi manchurian', 'Chapati, dal, rice'])
)
insert into public.menus (hostel_id, day_of_week, meal, items, updated_by)
select 'd3300000-0000-4000-8000-000000000001',
       d.dow::public.day_of_week, m.meal::public.meal_type, m.items[d.idx],
       '796da02b-1a0b-4e56-a00a-fa0c3b488a04'
  from d cross join m
 where not exists (
   select 1 from public.menus x
    where x.hostel_id = 'd3300000-0000-4000-8000-000000000001'
      and x.day_of_week = d.dow::public.day_of_week
      and x.meal = m.meal::public.meal_type
 );

-- ── Notices ────────────────────────────────────────────────────────────────────────────────
insert into public.announcements (id, hostel_id, author_user_id, title, body, audience, created_at, updated_at)
values
  ('d3300000-0000-4000-8000-000000003001', 'd3300000-0000-4000-8000-000000000001',
   '3bdd80c9-01f2-49df-855a-5ce3f136d0ea',
   'Rent for this month is due on the 5th',
   'Pay in the app or at the desk. A receipt is issued the moment the payment is recorded.',
   'students', now() - interval '2 days', now() - interval '2 days'),
  ('d3300000-0000-4000-8000-000000003002', 'd3300000-0000-4000-8000-000000000001',
   '3bdd80c9-01f2-49df-855a-5ce3f136d0ea',
   'Pest control on Sunday morning',
   'Rooms on both floors will be treated between 9 and 11 am. Please keep food covered and open your windows afterwards.',
   'all', now() - interval '6 hours', now() - interval '6 hours')
on conflict (id) do nothing;

-- ── Leave: one waiting on the warden, one already taken ───────────────────────────────────
insert into public.leaves (id, hostel_id, student_id, from_date, to_date, reason, status, decided_by, decided_at, decision_note)
values
  ('d3300000-0000-4000-8000-000000004001', 'd3300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-00000000ffff',
   current_date + 9, current_date + 11, 'Going home for a family function',
   'pending', null, null, null),
  ('d3300000-0000-4000-8000-000000004002', 'd3300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-00000000ffff',
   current_date - 24, current_date - 22, 'Sister''s wedding in Tirupati',
   'approved', '796da02b-1a0b-4e56-a00a-fa0c3b488a04', now() - interval '27 days', 'Approved. Safe travels.')
on conflict (id) do nothing;

-- ── Visitors: one on site now, one who has been and gone ──────────────────────────────────
insert into public.visitors (id, hostel_id, student_id, visitor_name, visitor_phone, relation, check_in_at, check_out_at, logged_by)
values
  ('d3300000-0000-4000-8000-000000005001', 'd3300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-00000000ffff',
   'Ramesh Babu', '9000000011', 'Father', now() - interval '2 hours', null,
   '796da02b-1a0b-4e56-a00a-fa0c3b488a04'),
  ('d3300000-0000-4000-8000-000000005002', 'd3300000-0000-4000-8000-000000000001',
   'd3300000-0000-4000-8000-00000000ffff',
   'Kavya', '9000000012', 'Sister', now() - interval '3 days', now() - interval '3 days' + interval '90 minutes',
   '796da02b-1a0b-4e56-a00a-fa0c3b488a04')
on conflict (id) do nothing;

-- ═══ AFTER APPLYING ═══
-- select c.table_name, count(*) from ... — or, per table:
--   select count(*) from public.expenses  where hostel_id = 'd3300000-0000-4000-8000-000000000001';
--   select count(*) from public.menus     where hostel_id = 'd3300000-0000-4000-8000-000000000001';  -- 28
