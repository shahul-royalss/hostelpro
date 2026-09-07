-- THE REST OF THE RATE LIMITING, AND THE SUPER ADMIN CONSOLE'S INDEXES.
--
-- Applied live in this order. Everything here was verified against the database rather than
-- asserted; the probes are quoted with each one.

-- ═══ 1. PASSWORD RESET WAS A KILL SWITCH FOR THE WHOLE PRODUCT ═══════════════════════════
--
-- password_reset_gate is callable by `anon` — correctly, because somebody who has forgotten
-- their password is signed out by definition. The bug was the ORDER of its two counters.
--
-- It spent a single product-wide bucket, `pwreset:all`, capped at 200/hour, BEFORE looking at
-- the per-identifier one, and every call spent it — including calls about to be refused. So 201
-- requests from one machine, no account and no password needed, and every real user in every
-- hostel is told to wait, on the one screen they reach precisely because they are already
-- locked out.
--
-- The fix is the ordering, not the number. Per-identifier (3/hour) is checked first and a
-- refusal there returns without touching the global counter. The cost ceiling stays — outbound
-- email is a real cost — but only requests that will actually send now spend it, and it is
-- raised to 1000 because exhausting it should require ~334 DISTINCT identifiers in an hour.
--
-- PROBE: 4 attempts on one identifier -> allowed, allowed, allowed, REFUSED(3600s), and the
-- global bucket had spent 3 units, not 4. A different identifier was still allowed.
-- (Function body applied separately; see 2026-09-07 migration
--  `password_reset_gate_stop_being_a_kill_switch`.)

-- ═══ 2. THE PAYMENT WRITE ════════════════════════════════════════════════════════════════
--
-- wd_record_payment upserts fee_payments and fires app.fee_payments_after_change, which writes
-- a notifications row — one loop is two writes plus a push to a resident's phone.
--
-- ON INSERT **OR UPDATE**, and that matters: wd_record_payment is an UPSERT, so a BEFORE INSERT
-- trigger would fire once per student-month and then never again as every later call takes the
-- ON CONFLICT branch. A limiter that stops applying after the first call is worse than none,
-- because it reads as covered.
--
-- 150/hour, much looser than notices and complaints, because the honest shape of this job is
-- bursty: the first of the month, a cash box, forty residents in one sitting. A limit tuned for
-- a quiet Tuesday would fire on the one day the product is most in use.
create or replace function app.rl_fee_payment() returns trigger
language plpgsql security definer set search_path = app, public as $$
begin
  perform app.spend(
    'fee_payment', 150, 3600,
    'That is a lot of payments in one hour. Take a short break and carry on in a few minutes — '
    'nothing already recorded has been lost.'
  );
  return new;
end $$;

drop trigger if exists fee_payments_rate_limit on public.fee_payments;
create trigger fee_payments_rate_limit
  before insert or update on public.fee_payments
  for each row execute function app.rl_fee_payment();

-- ═══ 3. THE SUPER ADMIN CONSOLE ══════════════════════════════════════════════════════════
--
-- rpc_sa_hostels is the one query whose cost grows with the number of paying customers. Per
-- hostel it runs four correlated count subqueries plus app.subscription_state() and
-- app.subscription_days_left(), then sorts by created_at with nothing to read.
--
-- The client half went in alongside: SaRepository.hostel() used `db.rpc(...).eq('hostel_id',id)`,
-- which is a PostgREST filter over the function's RESULT — so opening ONE hostel enumerated the
-- whole platform, ran six subqueries against every row, sorted, and discarded all but one. The
-- function already takes p_hostel_id and applies it in its own WHERE; it is passed now.

create index if not exists hostels_created_at_desc_idx
  on public.hostels (created_at desc, id desc);

-- Partial, because the predicate is a constant the query always uses — so the index holds only
-- the rows the count actually wants and the count becomes a scan of exactly what it returns.
create index if not exists beds_hostel_occupied_idx
  on public.beds (hostel_id) where student_id is not null;
create index if not exists students_hostel_active_idx
  on public.students (hostel_id) where status <> 'vacated';
create index if not exists complaints_hostel_open_idx
  on public.complaints (hostel_id) where status <> 'resolved';

-- One index for the LATERAL and both subscription_* functions; the shape lets `limit 1` stop at
-- the first tuple.
create index if not exists subscriptions_hostel_end_desc_idx
  on public.subscriptions (hostel_id, end_date desc);

-- Supabase's linter reported 25 unindexed foreign keys. Most are audit columns nothing filters
-- on, and indexing all 25 would add write cost to every table for reads nobody performs. These
-- three are the ones this product's screens genuinely traverse.
create index if not exists announcements_author_idx on public.announcements (author_user_id);
create index if not exists complaint_events_hostel_idx on public.complaint_events (hostel_id);
create index if not exists subscriptions_owner_idx on public.subscriptions (owner_user_id);

analyze public.hostels;
analyze public.beds;
analyze public.students;
analyze public.complaints;
analyze public.subscriptions;
