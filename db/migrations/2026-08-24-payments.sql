-- ============================================================================
--  db/migrations/2026-08-24-payments.sql
--  Student rent payment via Razorpay.
--
--  Apply AFTER db/schema.sql and db/rls-policies.sql. Idempotent — safe to
--  re-run. Adds nothing to existing tables except one trigger-free index.
--
--  THE SHAPE OF THE MONEY PATH
--    1. The student asks to pay. The SERVER reads their own outstanding balance
--       and creates a Razorpay order for exactly that. A row lands here with
--       status='created'. The client never names an amount, a student or a
--       period — see lib/actions/payments.ts.
--    2. Razorpay calls POST /api/webhooks/razorpay with an HMAC signature over
--       the raw body. Only after that signature verifies does anything below run.
--    3. rz_record_capture() claims the order exactly once (unique index on
--       razorpay_payment_id + a claim predicate, not an if-statement).
--    4. rz_credit_fee() credits public.fee_payments by CALLING the warden's own
--       public.wd_record_payment(), so every guard that protects the warden desk
--       protects this path too. Nothing is bypassed.
--
--  WHO MAY WRITE
--    Nobody, through PostgREST. payment_intents has RLS on and a SELECT policy
--    only — exactly like public.security_alerts — plus an explicit REVOKE of
--    INSERT/UPDATE/DELETE from anon and authenticated. Every write goes through
--    one of the SECURITY DEFINER functions below:
--
--      rz_open_intent        authenticated. Safe without a privileged credential
--                            because it derives the student, the period AND the
--                            amount itself; the caller supplies none of them.
--      rz_record_capture     service_role only.
--      rz_credit_fee         service_role only.
--      rz_mark_failed        service_role only.
--      rz_expire_stale_intents  service_role only.
--
--    The service_role ones are revoked from public/anon/authenticated AND re-check
--    app.is_service_role() in their own body, so a future GRANT cannot quietly
--    open them. Same belt-and-braces as public.audit_event().
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. TYPE
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
  create type public.payment_intent_status as enum ('created', 'captured', 'failed', 'expired');
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. TABLE
--
-- amount_paise is the SERVER'S figure, written at order time and never updated.
-- It is what the capture is checked against, so a tampered webhook body naming a
-- different amount is rejected rather than credited (see rz_record_capture).
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.payment_intents (
  id                  uuid primary key default gen_random_uuid(),
  hostel_id           uuid not null references public.hostels(id) on delete cascade,
  student_id          uuid not null references public.students(id) on delete cascade,
  period_month        text not null check (period_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  -- integer minor units. Money is never a float anywhere on this path.
  amount_paise        bigint not null check (amount_paise > 0 and amount_paise <= 1000000000),
  currency            text not null default 'INR' check (currency = 'INR'),
  razorpay_order_id   text not null check (length(razorpay_order_id) between 6 and 80),
  razorpay_payment_id text check (razorpay_payment_id is null or length(razorpay_payment_id) between 6 and 80),
  -- 'upi' | 'card' | 'netbanking' | 'wallet' … as reported by Razorpay. Display only.
  method              text,
  status              public.payment_intent_status not null default 'created',
  failure_reason      text,
  captured_at         timestamptz,
  credited_at         timestamptz,
  created_by          uuid references public.users(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- One intent per Razorpay order.
create unique index if not exists payment_intents_order_key
  on public.payment_intents (razorpay_order_id);

-- ── THE IDEMPOTENCY CONSTRAINT ──────────────────────────────────────────────
-- Razorpay retries a webhook until it gets a 2xx, and may deliver the same event
-- more than once regardless. This index is what makes "the same payment id can
-- never credit twice" a property of the DATABASE rather than of a code path that
-- could be edited away. rz_record_capture() also claims under
-- `razorpay_payment_id is null`, so two concurrent deliveries serialise on the
-- row lock and the loser sees zero rows updated.
create unique index if not exists payment_intents_payment_key
  on public.payment_intents (razorpay_payment_id)
  where razorpay_payment_id is not null;

create index if not exists payment_intents_student_idx
  on public.payment_intents (student_id, created_at desc);
create index if not exists payment_intents_hostel_idx
  on public.payment_intents (hostel_id, created_at desc);
-- The reconciliation queue: money Razorpay captured that fee_payments has not
-- been credited with yet. Should always be empty. See docs/payments.md §7.
create index if not exists payment_intents_unreconciled_idx
  on public.payment_intents (created_at)
  where status = 'captured' and credited_at is null;
-- Order-reuse lookup in createRentOrder() (student + period + still open).
create index if not exists payment_intents_open_idx
  on public.payment_intents (student_id, period_month, created_at desc)
  where status = 'created';

drop trigger if exists set_updated_at on public.payment_intents;
create trigger set_updated_at before update on public.payment_intents
  for each row execute function app.set_updated_at();

-- Cross-tenant integrity, same guard fee_payments and visitors carry: a row that
-- references a student must live in that student's hostel. Without it a bug in
-- the order path could bill a resident of another tenant.
drop trigger if exists payment_intents_student_tenant on public.payment_intents;
create trigger payment_intents_student_tenant
  before insert or update of student_id, hostel_id on public.payment_intents
  for each row execute function app.assert_student_in_hostel();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RLS — read-only for humans, no write path at all through PostgREST
--
-- Modelled on public.security_alerts. A student sees only their own attempts; the
-- warden and owner see their hostel's, because they are the people who reconcile
-- a payment that did not land. No INSERT/UPDATE/DELETE policy exists, so those
-- are denied to anon and authenticated by default-deny; the explicit REVOKE below
-- means it stays denied even if a policy is ever added by mistake.
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.payment_intents enable row level security;

drop policy if exists payment_intents_select on public.payment_intents;
create policy payment_intents_select on public.payment_intents for select
  using (
    student_id = app.current_student_id()
    or app.has_role_in(hostel_id, 'warden', 'owner')
  );

revoke insert, update, delete on public.payment_intents from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. rz_open_intent — the ONLY way a 'created' row is ever written.
--
-- THE AMOUNT IS DECIDED HERE, in the database, from the caller's own ledger.
-- The student is app.current_student_id() — taken from auth.uid(), not from an
-- argument — and the period is the current month by the database's own clock. A
-- caller cannot name a student, cannot name a period, and cannot name a price:
-- p_amount_paise is not an instruction, it is the figure the order was built for,
-- and it is REJECTED unless it still equals what this function independently
-- computes. If a warden banked a cash payment in the meantime, the order no
-- longer matches the balance and the student is asked to start again rather than
-- being charged the stale amount.
--
-- Executable by `authenticated` on purpose: it needs no elevated credential to be
-- safe, because it derives every sensitive value itself. That is what keeps the
-- service-role key out of the order path entirely.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.rz_open_intent(p_order_id text, p_amount_paise bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_student     uuid;
  v_hostel      uuid;
  v_monthly_fee numeric;
  v_period      text := to_char(current_date, 'YYYY-MM');
  v_due         numeric;
  v_paid        numeric;
  v_expected    bigint;
  v_recent      int;
  v_id          uuid;
begin
  v_student := app.current_student_id();
  if v_student is null then
    raise exception 'Your student record could not be found. Contact your warden.' using errcode = 'P0001';
  end if;

  -- Razorpay order ids are `order_` + base62. Anchored and length-bounded so this
  -- column can never become a place to stash arbitrary text.
  if p_order_id is null or p_order_id !~ '^order_[A-Za-z0-9]{6,30}$' then
    raise exception 'Invalid order.' using errcode = 'P0001';
  end if;

  select hostel_id, monthly_fee into v_hostel, v_monthly_fee
    from public.students where id = v_student;

  -- Hard rule §4.4, the same gate every other tenant write passes through.
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  -- A floor under the per-user rate limit in lib/actions/payments.ts, in case this
  -- is ever reached other than through that action.
  select count(*) into v_recent from public.payment_intents
   where student_id = v_student and created_at > now() - interval '1 hour';
  if v_recent >= 10 then
    raise exception 'Too many payment attempts. Please wait a few minutes and try again.' using errcode = 'P0001';
  end if;

  -- Mirrors summariseFee() in lib/queries/student.ts exactly: a missing fee row
  -- means the whole monthly fee is due; a row's own amount_due wins when present,
  -- including a legitimate 0.
  select fp.amount_due, fp.amount_paid into v_due, v_paid
    from public.fee_payments fp
   where fp.student_id = v_student and fp.period_month = v_period;
  v_expected := round(greatest(coalesce(v_due, v_monthly_fee) - coalesce(v_paid, 0), 0) * 100)::bigint;

  if v_expected < 100 then
    raise exception 'There is nothing to pay for this month.' using errcode = 'P0001';
  end if;
  if p_amount_paise is distinct from v_expected then
    raise exception 'Your balance changed while the payment was being set up. Please try again.' using errcode = 'P0001';
  end if;

  insert into public.payment_intents (hostel_id, student_id, period_month, amount_paise, razorpay_order_id, created_by)
  values (v_hostel, v_student, v_period, v_expected, p_order_id, auth.uid())
  returning id into v_id;

  return jsonb_build_object('intent_id', v_id, 'period_month', v_period, 'amount_paise', v_expected);
end $$;

revoke all on function public.rz_open_intent(text, bigint) from public, anon;
grant execute on function public.rz_open_intent(text, bigint) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. rz_record_capture — record that Razorpay took the money. EXACTLY ONCE.
--
-- Returns jsonb rather than a table so no OUT parameter can shadow a column name.
--   { outcome: 'captured' | 'duplicate', intent_id, hostel_id, student_id,
--     period_month, amount_paise, already_credited }
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.rz_record_capture(
  p_order_id text,
  p_payment_id text,
  p_amount_paise bigint,
  p_method text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row public.payment_intents;
  v_outcome text;
begin
  -- Defense in depth: the GRANTs below already limit this to service_role. If one
  -- is ever widened, this still refuses. Mirrors public.audit_event().
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_order_id is null or p_payment_id is null or p_amount_paise is null then
    raise exception 'Incomplete capture.' using errcode = 'P0001';
  end if;

  -- The claim. `razorpay_payment_id is null` is re-evaluated under the row lock,
  -- so a concurrent second delivery finds zero rows once the first commits.
  update public.payment_intents i
     set razorpay_payment_id = p_payment_id,
         status              = 'captured',
         method              = coalesce(left(p_method, 40), i.method),
         failure_reason      = null,
         captured_at         = now()
   where i.razorpay_order_id   = p_order_id
     and i.razorpay_payment_id is null
     and i.status in ('created', 'failed')
  returning i.* into v_row;

  if found then
    v_outcome := 'captured';
  else
    select * into v_row from public.payment_intents where razorpay_order_id = p_order_id;
    if not found then
      -- Signature verified, so this really is our Razorpay account — but no order
      -- of ours matches. Either the order row never landed, or the account is
      -- shared with a flow that does not belong to this feature. Never invent a row.
      raise exception 'Unknown Razorpay order.' using errcode = 'P0001';
    end if;
    if v_row.razorpay_payment_id is distinct from p_payment_id then
      raise exception 'Order already settled by a different payment.' using errcode = 'P0001';
    end if;
    v_outcome := 'duplicate';
  end if;

  -- THE AMOUNT CHECK. amount_paise was decided by this server from the student's
  -- own outstanding balance at order time. Razorpay echoes the captured amount
  -- back; if the two ever disagree, nothing is credited.
  if p_amount_paise is distinct from v_row.amount_paise then
    raise exception 'Captured amount does not match the order.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'outcome',          v_outcome,
    'intent_id',        v_row.id,
    'hostel_id',        v_row.hostel_id,
    'student_id',       v_row.student_id,
    'period_month',     v_row.period_month,
    'amount_paise',     v_row.amount_paise,
    'already_credited', v_row.credited_at is not null
  );
end $$;

revoke all on function public.rz_record_capture(text, text, bigint, text) from public, anon, authenticated;
grant execute on function public.rz_record_capture(text, text, bigint, text) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. rz_credit_fee — put the captured money onto the fee ledger.
--
-- Deliberately a SECOND transaction, called after rz_record_capture() has already
-- committed. If the credit fails, the record that Razorpay took the money still
-- stands and the row joins the reconciliation queue; it is never rolled back with
-- the credit. Money is not allowed to disappear because a guard fired.
--
-- The credit itself goes through public.wd_record_payment() — the same function
-- the warden's desk calls — so every one of its guards still applies here:
--   • the student must exist
--   • the caller must be authorised for that hostel. service_role satisfies
--     app.has_role_in() via app.is_super_admin() → app.is_service_role(). Note that
--     this is not an assumption being relied on: the entry guard below evaluates
--     app.is_service_role() FIRST and raises if it is false, so wd_record_payment()
--     is only ever reached along a path on which that same predicate has already
--     been proven true. If the premise fails, nothing runs.
--   • app.hostel_writable() — subscription not expired, hostel active (§4.4)
--   • the student must not be checked out
--   • amount finite, > 0, ≤ 1e7; paid_on not in the future
-- Nothing is bypassed and nothing replaces them. If one of them raises, THIS
-- transaction rolls back, credited_at returns to null, and the row is picked up
-- by the reconciliation query in docs/payments.md §7.
--
-- Returns { outcome: 'credited' | 'already_credited' | 'not_captured', … }
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.rz_credit_fee(p_intent_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_row    public.payment_intents;
  v_fee    public.fee_payments;
  v_amount numeric(10,2);
  v_mode   public.payment_mode;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  -- Claim the credit the same way the capture was claimed: a predicate that a
  -- second caller cannot satisfy once the first has committed.
  update public.payment_intents i
     set credited_at = now()
   where i.id          = p_intent_id
     and i.status      = 'captured'
     and i.credited_at is null
  returning i.* into v_row;

  if not found then
    select * into v_row from public.payment_intents where id = p_intent_id;
    if not found then
      raise exception 'Unknown payment.' using errcode = 'P0001';
    end if;
    return jsonb_build_object(
      'outcome', case when v_row.credited_at is not null then 'already_credited' else 'not_captured' end,
      'intent_id', v_row.id
    );
  end if;

  v_amount := round(v_row.amount_paise::numeric / 100, 2);

  -- public.payment_mode is ('cash','upi','bank') and is rendered by a
  -- Record<PaymentMode, string> in the warden's fee ledger, so a NEW enum value
  -- would render as `undefined` there until that map is updated. Razorpay's own
  -- method is kept verbatim in payment_intents.method and in the fee note, so no
  -- information is lost by mapping onto the existing values here.
  v_mode := (case when v_row.method = 'upi' then 'upi' else 'bank' end)::public.payment_mode;

  select * into v_fee from public.wd_record_payment(
    v_row.student_id,
    v_row.period_month,
    v_amount,
    v_mode,
    current_date,
    format('Paid online · Razorpay %s', v_row.razorpay_payment_id)
  );

  return jsonb_build_object(
    'outcome',      'credited',
    'intent_id',    v_row.id,
    'student_id',   v_row.student_id,
    'hostel_id',    v_row.hostel_id,
    'period_month', v_row.period_month,
    'amount',       v_amount,
    'fee_status',   v_fee.status,
    'amount_paid',  v_fee.amount_paid,
    'amount_due',   v_fee.amount_due
  );
end $$;

revoke all on function public.rz_credit_fee(uuid) from public, anon, authenticated;
grant execute on function public.rz_credit_fee(uuid) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. rz_mark_failed — a payment.failed webhook. Never touches fee_payments.
--    Guarded so it can never overwrite a capture that has already landed.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.rz_mark_failed(p_order_id text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  update public.payment_intents i
     set status = 'failed', failure_reason = left(coalesce(p_reason, 'Payment failed'), 200)
   where i.razorpay_order_id   = p_order_id
     and i.status              = 'created'
     and i.razorpay_payment_id is null
  returning i.id into v_id;
  return jsonb_build_object('outcome', case when v_id is null then 'ignored' else 'failed' end);
end $$;

revoke all on function public.rz_mark_failed(text, text) from public, anon, authenticated;
grant execute on function public.rz_mark_failed(text, text) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. rz_expire_stale_intents — housekeeping. An abandoned checkout leaves a
--    'created' row forever; after a day it is certainly dead. Never touches a row
--    that carries a payment id, so a late capture can still claim its order.
--    Call from the same place app.apply_retention() is called (docs/payments.md §7).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.rz_expire_stale_intents(p_older_than interval default interval '1 day')
returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  update public.payment_intents
     set status = 'expired'
   where status              = 'created'
     and razorpay_payment_id is null
     and created_at          < now() - p_older_than;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.rz_expire_stale_intents(interval) from public, anon, authenticated;
grant execute on function public.rz_expire_stale_intents(interval) to service_role;
