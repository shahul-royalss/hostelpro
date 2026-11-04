-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 2026-11-04 — CASHFREE RENT GATEWAY with Easy Split to the owner's UPI VPA.
-- Contract: docs/cashfree-rent.md. Edge functions: cashfree-vendor, cashfree-order,
-- cashfree-webhook, cashfree-worker, cashfree-refund (supabase/functions/).
--
--   C1 hostels.rent_gateway: which gateway a PG's rent uses. 'cashfree' for every PG except
--      the PGs of owner Rukesh Akanambattu, which keep Razorpay (owner's decision, 2026-11-04).
--   C2 owner_payment_accounts: one Cashfree Easy Split vendor per owner. Written ONLY by the
--      service role after Cashfree answers; verified only when Cashfree says ACTIVE. The PAN is
--      sent to Cashfree and never stored here (its last four characters are, for display).
--   C3 rent_payments: one row per Cashfree order. The amount, tenant, owner, PG and vendor are
--      all derived in the database from the caller's own identity; nothing the phone sends is
--      trusted. A payment becomes SUCCESS only through svc_cf_apply_payment, which only the
--      webhook/worker call after reading the order back from Cashfree's API.
--   C4 payment_webhook_events: every webhook, deduplicated on Cashfree's idempotency header (or
--      the payload hash), so an at-least-once redelivery is processed once.
--   C5 owner_settlements: Cashfree vendor settlements, linked to the payments they carry.
--   C6 rent_refunds: owner- or Super-Admin-initiated refunds; at most one in flight per payment,
--      never more than was paid, and the rent ledger is reversed only once a refund succeeds.
--   C7 app.cashfree_tick(): pg_cron calls the worker every minute (splits after the documented
--      two-minute wait, reconciliation of missed webhooks, vendor and settlement status).
-- Undo: 2026-11-04-cashfree-rent.down.sql. Tests: 2026-11-04-cashfree-rent.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;
set local lock_timeout = '10s';

do $guard$
declare
  v_md5 text;
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  if to_regclass('public.rent_payments') is not null or to_regclass('public.owner_payment_accounts') is not null then
    raise exception 'the Cashfree tables already exist; nothing changed';
  end if;
  -- Crediting reuses wd_record_payment exactly as rz_credit_fee does; it must be the body read on 2026-11-04.
  select md5(p.prosrc) into v_md5 from pg_proc p
   where p.oid = 'public.wd_record_payment(uuid,text,numeric,public.payment_mode,date,text)'::regprocedure;
  if v_md5 is distinct from 'ed4e77e3f31305b0148e36c34e165eb1' then
    raise exception 'wd_record_payment is not the body measured on 2026-11-04 (md5 %); nothing changed', v_md5;
  end if;
end
$guard$;

-- ─── C1 Which gateway a PG's rent uses ──────────────────────────────────────────────────────
alter table public.hostels
  add column rent_gateway text not null default 'cashfree'
  constraint hostels_rent_gateway_check check (rent_gateway in ('cashfree', 'razorpay'));

update public.hostels set rent_gateway = 'razorpay'
 where owner_user_id = '1312e8e1-5216-4eac-b4a6-e276aeeddd1f';  -- Rukesh Akanambattu's PGs

-- ─── C2 Owner payment accounts (Cashfree vendors) ───────────────────────────────────────────
create table public.owner_payment_accounts (
  id                          uuid primary key default gen_random_uuid(),
  owner_id                    uuid not null unique references public.users(id) on delete restrict,
  cashfree_vendor_id          text not null unique check (cashfree_vendor_id ~ '^[A-Za-z0-9_]{3,50}$'),
  legal_name                  text not null check (char_length(legal_name) between 2 and 100),
  email                       text not null check (char_length(email) between 5 and 254),
  phone                       text not null check (phone ~ '^[6-9][0-9]{9}$'),
  upi_vpa                     text not null check (char_length(upi_vpa) <= 100 and upi_vpa ~ '^[A-Za-z0-9._-]+@[A-Za-z0-9._]+$'),
  beneficiary_name            text not null check (char_length(beneficiary_name) between 2 and 100),
  pan_last4                   text check (pan_last4 ~ '^[A-Z0-9]{4}$'),
  gstin                       text check (gstin ~ '^[0-9]{2}[A-Z0-9]{13}$'),
  -- Cashfree's own vendor status, verbatim (IN_BENE_CREATION, ACTIVE, BLOCKED, DELETED, ...).
  vendor_status               text not null,
  verification_status         text not null default 'pending'
                                check (verification_status in ('pending', 'verified', 'rejected')),
  settlement_schedule         integer,
  settlement_schedule_message text,
  provider_response           jsonb,
  last_error                  text,
  last_checked_at             timestamptz,
  activated_at                timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now()
);

-- ─── C3 Rent payments ───────────────────────────────────────────────────────────────────────
create table public.rent_payments (
  id                     uuid primary key default gen_random_uuid(),
  invoice_id             uuid references public.fee_payments(id) on delete set null,
  tenant_id              uuid not null references public.students(id) on delete restrict,
  tenant_user_id         uuid references public.users(id) on delete set null,
  owner_id               uuid not null references public.users(id) on delete restrict,
  pg_id                  uuid not null references public.hostels(id) on delete restrict,
  period_month           text not null check (period_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  cashfree_order_id      text not null unique check (cashfree_order_id ~ '^apv_[A-Za-z0-9_]{6,45}$'),
  cf_order_id            text,
  cashfree_payment_id    text unique,
  cashfree_vendor_id     text not null,
  payment_session_id     text,
  session_expires_at     timestamptz,
  amount_in_paise        bigint not null check (amount_in_paise >= 100),
  currency               text not null default 'INR' check (currency = 'INR'),
  payment_status         text not null default 'INITIATED'
                           check (payment_status in ('INITIATED', 'PENDING', 'SUCCESS', 'FAILED', 'CANCELLED', 'REFUNDED')),
  split_status           text not null default 'NOT_STARTED'
                           check (split_status in ('NOT_STARTED', 'PENDING', 'CREATED', 'FAILED')),
  settlement_status      text not null default 'NOT_STARTED'
                           check (settlement_status in ('NOT_STARTED', 'SPLIT_PENDING', 'SPLIT_CREATED',
                                                        'SETTLEMENT_PENDING', 'SETTLED', 'SETTLEMENT_FAILED')),
  payment_method         text,
  bank_reference         text,
  payment_time           timestamptz,
  failure_reason         text,
  verified_at            timestamptz,
  -- Set when the order can no longer take money (paid, expired, terminated, never created).
  closed_at              timestamptz,
  credited_at            timestamptz,
  credited_paise         bigint not null default 0 check (credited_paise >= 0),
  credit_error           text,
  receipt_no             text unique,
  overpaid               boolean not null default false,
  split_due_at           timestamptz,
  split_attempts         integer not null default 0,
  split_idempotency_key  uuid not null default gen_random_uuid(),
  split_requested_at     timestamptz,
  split_response         jsonb,
  split_error            text,
  settlement_id          text,
  settlement_utr         text,
  settled_at             timestamptz,
  last_reconciled_at     timestamptz,
  refunded_paise         bigint not null default 0 check (refunded_paise >= 0),
  reversed_paise         bigint not null default 0 check (reversed_paise >= 0),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (refunded_paise <= amount_in_paise),
  check (credited_paise <= amount_in_paise)
);

-- One order that can still take money per tenant and month: two phones cannot pay twice.
create unique index rent_payments_one_open on public.rent_payments (tenant_id, period_month)
  where closed_at is null;
create index rent_payments_owner_created on public.rent_payments (owner_id, created_at desc);
create index rent_payments_tenant_created on public.rent_payments (tenant_id, created_at desc);
create index rent_payments_pg on public.rent_payments (pg_id);
create index rent_payments_split_due on public.rent_payments (split_due_at)
  where split_status = 'PENDING';
create index rent_payments_open_created on public.rent_payments (created_at)
  where closed_at is null;
create index rent_payments_settlement on public.rent_payments (settlement_id) where settlement_id is not null;

-- ─── C4 Webhook events ──────────────────────────────────────────────────────────────────────
create table public.payment_webhook_events (
  id                 uuid primary key default gen_random_uuid(),
  provider           text not null default 'cashfree',
  provider_event_id  text not null,
  event_type         text not null,
  order_id           text,
  payload_hash       text not null,
  processing_status  text not null default 'received'
                       check (processing_status in ('received', 'processed', 'ignored', 'failed')),
  attempts           integer not null default 1,
  error              text,
  received_at        timestamptz not null default now(),
  processed_at       timestamptz,
  unique (provider, provider_event_id)
);
create index payment_webhook_events_order on public.payment_webhook_events (order_id);

-- ─── C5 Owner settlements ───────────────────────────────────────────────────────────────────
create table public.owner_settlements (
  id                    uuid primary key default gen_random_uuid(),
  owner_id              uuid references public.users(id) on delete set null,
  payment_id            uuid references public.rent_payments(id) on delete set null,
  cashfree_vendor_id    text not null,
  settlement_id         text not null,
  settlement_amount     numeric(12,2),
  settlement_status     text not null default 'PENDING'
                          check (settlement_status in ('PENDING', 'INITIATED', 'SUCCESS', 'FAILED', 'REVERSED')),
  settlement_reference  text,
  failure_reason        text,
  eligibility_date      timestamptz,
  settled_at            timestamptz,
  raw                   jsonb,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint owner_settlements_settlement_payment unique nulls not distinct (settlement_id, payment_id)
);
create index owner_settlements_owner on public.owner_settlements (owner_id, created_at desc);

-- ─── C6 Refunds ─────────────────────────────────────────────────────────────────────────────
create table public.rent_refunds (
  id                 uuid primary key default gen_random_uuid(),
  payment_id         uuid not null references public.rent_payments(id) on delete restrict,
  refund_id          text not null unique check (refund_id ~ '^apvr_[A-Za-z0-9_]{6,45}$'),
  cf_refund_id       text,
  amount_in_paise    bigint not null check (amount_in_paise >= 100),
  status             text not null default 'REQUESTED'
                       check (status in ('REQUESTED', 'PENDING', 'PENDING_APPROVAL', 'ONHOLD',
                                         'SUCCESS', 'CANCELLED', 'REJECTED', 'FAILED')),
  note               text check (note is null or char_length(note) <= 200),
  initiated_by       uuid not null references public.users(id) on delete restrict,
  initiated_role     text not null check (initiated_role in ('owner', 'super_admin')),
  provider_response  jsonb,
  failure_reason     text,
  reversed_at        timestamptz,
  processed_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create unique index rent_refunds_one_open on public.rent_refunds (payment_id)
  where status in ('REQUESTED', 'PENDING', 'PENDING_APPROVAL', 'ONHOLD');

-- updated_at on every write.
create or replace function app.cf_touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger owner_payment_accounts_touch before update on public.owner_payment_accounts
  for each row execute function app.cf_touch_updated_at();
create trigger rent_payments_touch before update on public.rent_payments
  for each row execute function app.cf_touch_updated_at();
create trigger owner_settlements_touch before update on public.owner_settlements
  for each row execute function app.cf_touch_updated_at();
create trigger rent_refunds_touch before update on public.rent_refunds
  for each row execute function app.cf_touch_updated_at();

-- ─── Row level security: owners and tenants see only their own records ──────────────────────
alter table public.owner_payment_accounts enable row level security;
alter table public.rent_payments enable row level security;
alter table public.payment_webhook_events enable row level security;
alter table public.owner_settlements enable row level security;
alter table public.rent_refunds enable row level security;

revoke all on public.owner_payment_accounts, public.rent_payments, public.payment_webhook_events,
              public.owner_settlements, public.rent_refunds from public, anon, authenticated;

create policy owner_payment_accounts_read on public.owner_payment_accounts for select to authenticated
  using (owner_id = auth.uid() or coalesce(app.user_role() = 'super_admin', false));
create policy rent_payments_read on public.rent_payments for select to authenticated
  using (tenant_user_id = auth.uid() or owner_id = auth.uid() or coalesce(app.user_role() = 'super_admin', false));
create policy payment_webhook_events_read on public.payment_webhook_events for select to authenticated
  using (coalesce(app.user_role() = 'super_admin', false));
create policy owner_settlements_read on public.owner_settlements for select to authenticated
  using (owner_id = auth.uid() or coalesce(app.user_role() = 'super_admin', false));
create policy rent_refunds_read on public.rent_refunds for select to authenticated
  using (exists (select 1 from public.rent_payments p
                  where p.id = rent_refunds.payment_id
                    and (p.tenant_user_id = auth.uid() or p.owner_id = auth.uid()))
         or coalesce(app.user_role() = 'super_admin', false));

-- Column grants: the checkout session, split internals and raw provider answers stay server-side.
grant select (id, owner_id, cashfree_vendor_id, legal_name, email, phone, upi_vpa, beneficiary_name, pan_last4,
              gstin, vendor_status, verification_status, settlement_schedule, settlement_schedule_message,
              last_error, last_checked_at, activated_at, created_at, updated_at)
  on public.owner_payment_accounts to authenticated;
-- tenant_user_id is granted because rent_refunds' policy reads it under the caller's own rights.
grant select (id, invoice_id, tenant_id, tenant_user_id, owner_id, pg_id, period_month, cashfree_order_id, cashfree_payment_id,
              amount_in_paise, currency, payment_status, split_status, settlement_status, payment_method,
              bank_reference, payment_time, failure_reason, verified_at, closed_at, credited_at, credited_paise,
              credit_error, receipt_no, overpaid, settlement_id, settlement_utr, settled_at, refunded_paise,
              created_at, updated_at)
  on public.rent_payments to authenticated;
grant select (id, provider, provider_event_id, event_type, order_id, processing_status, attempts, error,
              received_at, processed_at)
  on public.payment_webhook_events to authenticated;
grant select (id, owner_id, payment_id, cashfree_vendor_id, settlement_id, settlement_amount, settlement_status,
              settlement_reference, failure_reason, eligibility_date, settled_at, created_at, updated_at)
  on public.owner_settlements to authenticated;
grant select (id, payment_id, refund_id, cf_refund_id, amount_in_paise, status, note, initiated_by,
              initiated_role, failure_reason, reversed_at, processed_at, created_at, updated_at)
  on public.rent_refunds to authenticated;
grant all on public.owner_payment_accounts, public.rent_payments, public.payment_webhook_events,
             public.owner_settlements, public.rent_refunds to service_role;

-- ─── Helpers ────────────────────────────────────────────────────────────────────────────────
create or replace function app.cf_require_service() returns void
language plpgsql stable set search_path = '' as $$
begin
  if not coalesce(app.is_service_role(), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
end $$;

-- What a tenant owes for a month, in paise: the same arithmetic as rz_open_intent.
create or replace function app.cf_outstanding_paise(p_student uuid, p_period text) returns bigint
language sql stable security definer set search_path = '' as $$
  select round(greatest(coalesce(f.amount_due, s.monthly_fee) - coalesce(f.amount_paid, 0), 0) * 100)::bigint
    from public.students s
    left join public.fee_payments f on f.student_id = s.id and f.period_month = p_period
   where s.id = p_student;
$$;

-- ─── Tenant: which way does my rent go? ─────────────────────────────────────────────────────
create or replace function public.st_rent_gateway() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_student uuid := app.current_student_id();
  v_hostel  public.hostels%rowtype;
  v_acct    public.owner_payment_accounts%rowtype;
begin
  if v_student is null then
    raise exception 'Your student record could not be found. Contact your warden.' using errcode = 'P0001';
  end if;
  select h.* into v_hostel from public.hostels h join public.students s on s.hostel_id = h.id where s.id = v_student;
  if v_hostel.rent_gateway = 'razorpay' then
    return jsonb_build_object('gateway', 'razorpay', 'ready', true);
  end if;
  select * into v_acct from public.owner_payment_accounts where owner_id = v_hostel.owner_user_id;
  return jsonb_build_object(
    'gateway', 'cashfree',
    'ready', coalesce(v_acct.verification_status = 'verified' and v_acct.vendor_status = 'ACTIVE', false),
    'message', case
      when v_acct.id is null then 'Online rent payment is not set up for your PG yet. Please pay your PG directly.'
      when v_acct.verification_status = 'verified' and v_acct.vendor_status = 'ACTIVE' then null
      else 'Online rent payment for your PG is being verified. Please pay your PG directly for now.'
    end);
end
$fn$;

-- ─── Tenant: reserve an order (called by cashfree-order with the tenant's own token) ────────
create or replace function public.cf_reserve_payment(p_order_id text, p_amount_paise bigint) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_student  public.students%rowtype;
  v_hostel   public.hostels%rowtype;
  v_acct     public.owner_payment_accounts%rowtype;
  v_period   text := to_char(app.today(), 'YYYY-MM');
  v_expected bigint;
  v_open     public.rent_payments%rowtype;
  v_recent   int;
  v_id       uuid;
begin
  select * into v_student from public.students where id = app.current_student_id();
  if v_student.id is null then
    raise exception 'Your student record could not be found. Contact your warden.' using errcode = 'P0001';
  end if;
  if v_student.status = 'vacated' then
    raise exception 'You have checked out of this PG.' using errcode = 'P0001';
  end if;
  if p_order_id is null or p_order_id !~ '^apv_[A-Za-z0-9_]{6,45}$' then
    raise exception 'Invalid order.' using errcode = 'P0001';
  end if;

  select * into v_hostel from public.hostels where id = v_student.hostel_id;
  if not coalesce(app.hostel_writable(v_hostel.id), false) then
    raise exception 'Subscription expired - hostel is read-only.' using errcode = '42501';
  end if;
  if v_hostel.rent_gateway <> 'cashfree' then
    raise exception 'Your PG takes rent through its other payment option.' using errcode = 'P0001';
  end if;

  -- WHERE DOES THE MONEY GO: the CURRENT owner's verified Cashfree vendor, and nowhere else.
  select * into v_acct from public.owner_payment_accounts where owner_id = v_hostel.owner_user_id;
  if v_acct.id is null or v_acct.verification_status <> 'verified' or v_acct.vendor_status <> 'ACTIVE' then
    raise exception 'Online rent payment is not set up for your PG yet. Please pay your PG directly.' using errcode = 'P0001';
  end if;

  v_expected := app.cf_outstanding_paise(v_student.id, v_period);
  if coalesce(v_expected, 0) < 100 then
    raise exception 'There is nothing to pay for this month.' using errcode = 'P0001';
  end if;
  if p_amount_paise is distinct from v_expected then
    raise exception 'Your balance changed while the payment was being set up. Please try again.' using errcode = 'P0001';
  end if;

  select * into v_open from public.rent_payments
   where tenant_id = v_student.id and period_month = v_period and closed_at is null
   for update;
  if v_open.id is not null then
    if v_open.payment_session_id is not null and v_open.session_expires_at > now() + interval '2 minutes'
       and v_open.amount_in_paise = v_expected and v_open.cashfree_vendor_id = v_acct.cashfree_vendor_id then
      return jsonb_build_object('outcome', 'reuse', 'order_id', v_open.cashfree_order_id,
                                'payment_session_id', v_open.payment_session_id,
                                'amount_paise', v_open.amount_in_paise, 'period_month', v_period);
    end if;
    -- An older order that might still be paid: the function must ask Cashfree first.
    return jsonb_build_object('outcome', 'reconcile', 'order_id', v_open.cashfree_order_id);
  end if;

  select count(*) into v_recent from public.rent_payments
   where tenant_id = v_student.id and created_at > now() - interval '1 hour';
  if v_recent >= 10 then
    raise exception 'Too many payment attempts. Please wait a few minutes and try again.' using errcode = 'P0001';
  end if;

  insert into public.rent_payments (tenant_id, tenant_user_id, owner_id, pg_id, period_month, cashfree_order_id,
                                    cashfree_vendor_id, amount_in_paise)
  values (v_student.id, auth.uid(), v_hostel.owner_user_id, v_hostel.id, v_period, p_order_id,
          v_acct.cashfree_vendor_id, v_expected)
  returning id into v_id;

  return jsonb_build_object(
    'outcome', 'reserved', 'payment_id', v_id, 'order_id', p_order_id, 'amount_paise', v_expected,
    'period_month', v_period, 'hostel_name', v_hostel.name,
    'customer', jsonb_build_object('id', replace(v_student.id::text, '-', ''), 'name', v_student.full_name,
                                   'phone', v_student.phone, 'email', v_student.email));
end
$fn$;

-- ─── Service: the order exists at Cashfree / could not be created ───────────────────────────
create or replace function public.svc_cf_attach_session(p_order_id text, p_cf_order_id text, p_session_id text,
                                                        p_expires_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform app.cf_require_service();
  update public.rent_payments
     set cf_order_id = p_cf_order_id, payment_session_id = p_session_id, session_expires_at = p_expires_at
   where cashfree_order_id = p_order_id and payment_session_id is null and closed_at is null;
  if not found then
    raise exception 'Unknown order.' using errcode = 'P0001';
  end if;
end
$fn$;

create or replace function public.svc_cf_abandon_order(p_order_id text, p_reason text) returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform app.cf_require_service();
  update public.rent_payments
     set payment_status = case when payment_status in ('INITIATED', 'PENDING') then 'CANCELLED' else payment_status end,
         failure_reason = coalesce(left(p_reason, 300), failure_reason),
         closed_at = now()
   where cashfree_order_id = p_order_id and closed_at is null and payment_status <> 'SUCCESS';
end
$fn$;

-- ─── Service: apply a payment state READ BACK FROM CASHFREE'S API ───────────────────────────
create or replace function public.svc_cf_apply_payment(
  p_order_id text, p_order_status text, p_cf_payment_id text, p_payment_status text,
  p_amount_paise bigint, p_currency text, p_method text, p_bank_reference text,
  p_payment_time timestamptz, p_message text) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_row       public.rent_payments%rowtype;
  v_owe       bigint;
  v_credit    bigint;
  v_fee       public.fee_payments%rowtype;
  v_receipt   text;
  v_mode      public.payment_mode;
  v_tenant    text;
  v_pg        text;
begin
  perform app.cf_require_service();
  select * into v_row from public.rent_payments where cashfree_order_id = p_order_id for update;
  if v_row.id is null then
    raise exception 'Unknown order.' using errcode = 'P0001';
  end if;

  if p_payment_status = 'SUCCESS' then
    if v_row.payment_status in ('SUCCESS', 'REFUNDED') then
      return jsonb_build_object('outcome', 'already', 'payment_id', v_row.id);
    end if;
    -- EVERY FIELD THAT DECIDES WHO GETS CREDITED IS CHECKED HERE, not in the function that read it.
    if p_order_status is distinct from 'PAID' then
      raise exception 'Order % is not PAID at Cashfree (%).', p_order_id, p_order_status using errcode = 'P0001';
    end if;
    if p_currency is distinct from 'INR' then
      raise exception 'Currency mismatch on %.', p_order_id using errcode = 'P0001';
    end if;
    if p_amount_paise is distinct from v_row.amount_in_paise then
      update public.rent_payments set failure_reason = format('Amount mismatch: Cashfree %s, expected %s', p_amount_paise, v_row.amount_in_paise)
       where id = v_row.id;
      raise exception 'Amount mismatch on %.', p_order_id using errcode = 'P0001';
    end if;
    if p_cf_payment_id is null or p_cf_payment_id = '' then
      raise exception 'Missing payment id on %.', p_order_id using errcode = 'P0001';
    end if;

    v_receipt := 'APV-' || to_char(now() at time zone 'Asia/Kolkata', 'YYMM') || '-'
                 || upper(left(replace(v_row.id::text, '-', ''), 8));
    update public.rent_payments
       set payment_status = 'SUCCESS', cashfree_payment_id = p_cf_payment_id, payment_method = p_method,
           bank_reference = p_bank_reference, payment_time = coalesce(p_payment_time, now()), verified_at = now(),
           closed_at = now(), failure_reason = null, receipt_no = v_receipt,
           split_status = 'PENDING', settlement_status = 'SPLIT_PENDING',
           -- Cashfree: wait at least two minutes after success before Split After Payment.
           split_due_at = now() + interval '150 seconds'
     where id = v_row.id
    returning * into v_row;

    -- Credit the rent ledger with what was owed, never more. A month already settled some other
    -- way makes the payment an overpayment for the owner to refund.
    v_owe := coalesce(app.cf_outstanding_paise(v_row.tenant_id, v_row.period_month), 0);
    v_credit := least(v_owe, v_row.amount_in_paise);
    v_mode := (case when p_method = 'upi' then 'upi' else 'bank' end)::public.payment_mode;
    if v_credit >= 1 then
      begin
        select * into v_fee from public.wd_record_payment(
          v_row.tenant_id, v_row.period_month, round(v_credit::numeric / 100, 2), v_mode, app.today(),
          format('Paid online · Cashfree %s · Receipt %s', p_cf_payment_id, v_receipt));
        update public.rent_payments
           set credited_at = now(), credited_paise = v_credit, invoice_id = v_fee.id,
               overpaid = (v_credit < amount_in_paise)
         where id = v_row.id;
      exception when others then
        -- The money is captured either way. A ledger that refuses (a PG gone read-only, a tenant
        -- checked out) is recorded for the owner and the admin to resolve, never retried blindly.
        update public.rent_payments set credit_error = left(sqlerrm, 300) where id = v_row.id;
      end;
    else
      update public.rent_payments set overpaid = true where id = v_row.id;
    end if;

    select s.full_name, h.name into v_tenant, v_pg
      from public.students s join public.hostels h on h.id = s.hostel_id where s.id = v_row.tenant_id;
    insert into public.notifications (hostel_id, user_id, type, title, body, link, dedupe_key)
    select v_row.pg_id, x.uid, 'fee', x.title, x.body, x.link, 'cf_paid:' || v_row.id || ':' || x.uid
      from (values
        (v_row.tenant_user_id, 'Rent received',
         format('₹%s for %s to %s. Receipt %s.', to_char(v_row.amount_in_paise / 100.0, 'FM99999990.00'),
                v_row.period_month, v_pg, v_receipt), '/student/payments'),
        (v_row.owner_id, 'Rent received',
         format('%s paid ₹%s for %s by UPI through Cashfree.', v_tenant,
                to_char(v_row.amount_in_paise / 100.0, 'FM99999990.00'), v_row.period_month), '/owner/payments')
      ) as x(uid, title, body, link)
     where x.uid is not null
    on conflict do nothing;

    insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
    values (null, null, 'payment.cashfree.success', 'rent_payment', v_row.id::text, v_row.pg_id,
            jsonb_build_object('order_id', p_order_id, 'cf_payment_id', p_cf_payment_id, 'amount_paise', p_amount_paise));

    return jsonb_build_object('outcome', 'success', 'payment_id', v_row.id, 'receipt_no', v_receipt);
  end if;

  -- A captured payment is never moved backwards by a later failure or drop on the same order.
  if v_row.payment_status in ('SUCCESS', 'REFUNDED') then
    return jsonb_build_object('outcome', 'ignored', 'payment_id', v_row.id);
  end if;

  if p_payment_status in ('FAILED', 'VOID') then
    update public.rent_payments set payment_status = 'FAILED', failure_reason = left(coalesce(p_message, 'Payment failed'), 300),
           cashfree_payment_id = coalesce(cashfree_payment_id, nullif(p_cf_payment_id, ''))
     where id = v_row.id;
    return jsonb_build_object('outcome', 'failed', 'payment_id', v_row.id);
  elsif p_payment_status in ('USER_DROPPED', 'CANCELLED') then
    update public.rent_payments set payment_status = 'CANCELLED', failure_reason = left(coalesce(p_message, 'Payment cancelled'), 300)
     where id = v_row.id;
    return jsonb_build_object('outcome', 'cancelled', 'payment_id', v_row.id);
  elsif p_payment_status = 'PENDING' then
    update public.rent_payments set payment_status = 'PENDING' where id = v_row.id;
    return jsonb_build_object('outcome', 'pending', 'payment_id', v_row.id);
  end if;
  return jsonb_build_object('outcome', 'unchanged', 'payment_id', v_row.id);
end
$fn$;

-- An order Cashfree says can no longer be paid (EXPIRED / TERMINATED) with no successful payment.
create or replace function public.svc_cf_close_unpaid(p_order_id text, p_order_status text) returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform app.cf_require_service();
  update public.rent_payments
     set payment_status = case when payment_status in ('INITIATED', 'PENDING') then 'CANCELLED' else payment_status end,
         failure_reason = coalesce(failure_reason, 'Order ' || lower(coalesce(p_order_status, 'closed'))),
         closed_at = now(), last_reconciled_at = now()
   where cashfree_order_id = p_order_id and closed_at is null and payment_status <> 'SUCCESS';
end
$fn$;

-- ─── Service: Split After Payment ───────────────────────────────────────────────────────────
-- Claims due splits (SKIP LOCKED, so two ticks never split the same payment) and returns what
-- the worker sends: the owner's vendor gets everything paid less anything already refunded.
create or replace function public.svc_cf_split_claim(p_limit int default 20) returns table (
  payment_id uuid, order_id text, vendor_id text, amount_paise bigint, idempotency_key uuid, attempts int)
language plpgsql security definer set search_path = '' as $fn$
begin
  perform app.cf_require_service();
  return query
  with due as (
    select r.id from public.rent_payments r
     where r.split_status = 'PENDING' and r.payment_status in ('SUCCESS', 'REFUNDED')
       and r.split_due_at <= now()
     order by r.split_due_at
     limit greatest(1, least(p_limit, 50))
     for update skip locked
  )
  update public.rent_payments r
     set split_attempts = r.split_attempts + 1, split_requested_at = now(),
         split_due_at = now() + interval '10 minutes'   -- a crashed worker retries after this
    from due
   where r.id = due.id
  returning r.id, r.cashfree_order_id, r.cashfree_vendor_id, r.amount_in_paise - r.refunded_paise,
            r.split_idempotency_key, r.split_attempts;
end
$fn$;

create or replace function public.svc_cf_split_result(p_payment_id uuid, p_outcome text, p_response jsonb,
                                                      p_error text) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_row public.rent_payments%rowtype;
begin
  perform app.cf_require_service();
  select * into v_row from public.rent_payments where id = p_payment_id for update;
  if v_row.id is null then
    raise exception 'Unknown payment.' using errcode = 'P0001';
  end if;
  if p_outcome = 'created' then
    update public.rent_payments
       set split_status = 'CREATED', settlement_status = 'SPLIT_CREATED', split_response = p_response,
           split_error = null, split_due_at = null
     where id = p_payment_id;
  elsif p_outcome = 'nothing' then
    -- Fully refunded before the split: there is nothing left to give the owner.
    update public.rent_payments
       set split_status = 'NOT_STARTED', settlement_status = 'NOT_STARTED', split_due_at = null,
           split_response = p_response, split_error = p_error
     where id = p_payment_id;
  elsif p_outcome = 'retry' and v_row.split_attempts < 8 then
    update public.rent_payments
       set split_error = left(p_error, 300), split_response = p_response,
           split_due_at = now() + make_interval(mins => least(60, (2 ^ v_row.split_attempts)::int))
     where id = p_payment_id;
  else
    update public.rent_payments
       set split_status = 'FAILED', settlement_status = 'SETTLEMENT_FAILED', split_error = left(p_error, 300),
           split_response = p_response, split_due_at = null
     where id = p_payment_id;
    insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
    values (null, null, 'payment.cashfree.split_failed', 'rent_payment', p_payment_id::text, v_row.pg_id,
            jsonb_build_object('error', left(p_error, 300), 'attempts', v_row.split_attempts));
  end if;
end
$fn$;

-- ─── Service: settlements ───────────────────────────────────────────────────────────────────
-- From the split recon (GET /easy-split/orders/{order_id}): which settlement carries this order.
create or replace function public.svc_cf_link_settlement(p_order_id text, p_vendor_id text, p_settlement_id text,
                                                         p_amount numeric, p_eligibility timestamptz) returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_row    public.rent_payments%rowtype;
  v_batch  public.owner_settlements%rowtype;
begin
  perform app.cf_require_service();
  select * into v_row from public.rent_payments where cashfree_order_id = p_order_id for update;
  if v_row.id is null or v_row.cashfree_vendor_id is distinct from p_vendor_id then
    return;
  end if;
  update public.rent_payments set last_reconciled_at = now() where id = v_row.id;
  if p_settlement_id is null or p_settlement_id = '' then
    return;
  end if;

  insert into public.owner_settlements (owner_id, payment_id, cashfree_vendor_id, settlement_id, settlement_amount,
                                        eligibility_date)
  values (v_row.owner_id, v_row.id, p_vendor_id, p_settlement_id, p_amount, p_eligibility)
  on conflict on constraint owner_settlements_settlement_payment do update
    set settlement_amount = excluded.settlement_amount, eligibility_date = excluded.eligibility_date;

  -- A settlement webhook may have arrived first: carry its outcome onto this payment.
  select * into v_batch from public.owner_settlements
   where settlement_id = p_settlement_id and payment_id is null;
  update public.rent_payments
     set settlement_id = p_settlement_id,
         settlement_status = case
           when v_batch.settlement_status = 'SUCCESS' then 'SETTLED'
           when v_batch.settlement_status in ('FAILED', 'REVERSED') then 'SETTLEMENT_FAILED'
           when settlement_status in ('SPLIT_CREATED', 'SPLIT_PENDING') then 'SETTLEMENT_PENDING'
           else settlement_status end,
         settlement_utr = coalesce(v_batch.settlement_reference, settlement_utr),
         settled_at = case when v_batch.settlement_status = 'SUCCESS' then coalesce(v_batch.settled_at, now()) else settled_at end
   where id = v_row.id;
end
$fn$;

-- From a VENDOR_SETTLEMENT_* webhook (signature-verified by the caller).
create or replace function public.svc_cf_settlement_event(p_vendor_id text, p_settlement_id text, p_status text,
                                                          p_amount numeric, p_utr text, p_reason text,
                                                          p_settled_on timestamptz, p_raw jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_owner  uuid;
  v_status text := case upper(coalesce(p_status, ''))
                     when 'SUCCESS' then 'SUCCESS' when 'FAILED' then 'FAILED' when 'REVERSED' then 'REVERSED'
                     when 'CREATED' then 'INITIATED' when 'INITIATED' then 'INITIATED' else 'PENDING' end;
  v_pay_status text;
  v_n int;
begin
  perform app.cf_require_service();
  select owner_id into v_owner from public.owner_payment_accounts where cashfree_vendor_id = p_vendor_id;
  if v_owner is null then
    return jsonb_build_object('outcome', 'unknown_vendor');
  end if;

  insert into public.owner_settlements (owner_id, payment_id, cashfree_vendor_id, settlement_id, settlement_amount,
                                        settlement_status, settlement_reference, failure_reason, settled_at, raw)
  values (v_owner, null, p_vendor_id, p_settlement_id, p_amount, v_status, nullif(p_utr, ''), p_reason,
          case when v_status = 'SUCCESS' then coalesce(p_settled_on, now()) end, p_raw)
  on conflict on constraint owner_settlements_settlement_payment do update
    set settlement_status = excluded.settlement_status, settlement_amount = coalesce(excluded.settlement_amount, public.owner_settlements.settlement_amount),
        settlement_reference = coalesce(excluded.settlement_reference, public.owner_settlements.settlement_reference),
        failure_reason = excluded.failure_reason, settled_at = coalesce(excluded.settled_at, public.owner_settlements.settled_at),
        raw = excluded.raw;

  update public.owner_settlements
     set settlement_status = v_status, settlement_reference = coalesce(nullif(p_utr, ''), settlement_reference),
         failure_reason = p_reason, settled_at = case when v_status = 'SUCCESS' then coalesce(p_settled_on, now()) else settled_at end
   where settlement_id = p_settlement_id and payment_id is not null;

  v_pay_status := case v_status when 'SUCCESS' then 'SETTLED' when 'FAILED' then 'SETTLEMENT_FAILED'
                                when 'REVERSED' then 'SETTLEMENT_FAILED' else 'SETTLEMENT_PENDING' end;
  update public.rent_payments
     set settlement_status = v_pay_status, settlement_utr = coalesce(nullif(p_utr, ''), settlement_utr),
         settled_at = case when v_status = 'SUCCESS' then coalesce(p_settled_on, now()) else settled_at end
   where settlement_id = p_settlement_id and cashfree_vendor_id = p_vendor_id;
  get diagnostics v_n = row_count;

  if v_status in ('FAILED', 'REVERSED') then
    insert into public.notifications (user_id, type, title, body, link, dedupe_key)
    values (v_owner, 'fee', 'Settlement did not reach your UPI ID',
            'Cashfree could not settle rent to your UPI ID' || coalesce(' (' || p_reason || ')', '') || '. Check your payment account.',
            '/owner/payments', 'cf_settle_fail:' || p_settlement_id)
    on conflict do nothing;
  end if;
  return jsonb_build_object('outcome', 'recorded', 'payments', v_n, 'status', v_status);
end
$fn$;

-- ─── Service: refunds ───────────────────────────────────────────────────────────────────────
-- Authorisation (owner of this payment, or Super Admin, with their second factor) is checked by
-- cashfree-refund before this is called; the actor is re-checked here against the payment.
create or replace function public.svc_cf_request_refund(p_payment_id uuid, p_actor uuid, p_amount_paise bigint,
                                                        p_note text, p_refund_id text) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_row      public.rent_payments%rowtype;
  v_role     text;
  v_inflight bigint;
  v_id       uuid;
begin
  perform app.cf_require_service();
  select role::text into v_role from public.users where id = p_actor and status = 'active' and deleted_at is null;
  select * into v_row from public.rent_payments where id = p_payment_id for update;
  if v_row.id is null then
    raise exception 'Payment not found.' using errcode = 'P0001';
  end if;
  if not (v_role = 'super_admin' or (v_role = 'owner' and v_row.owner_id = p_actor)) then
    raise exception 'Only this PG''s owner or the platform admin can refund this payment.' using errcode = '42501';
  end if;
  if v_row.payment_status <> 'SUCCESS' then
    raise exception 'Only a successful payment can be refunded.' using errcode = 'P0001';
  end if;
  if p_refund_id is null or p_refund_id !~ '^apvr_[A-Za-z0-9_]{6,45}$' then
    raise exception 'Invalid refund.' using errcode = 'P0001';
  end if;
  if p_amount_paise is null or p_amount_paise < 100 then
    raise exception 'A refund must be at least ₹1.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.rent_refunds where payment_id = v_row.id
              and status in ('REQUESTED', 'PENDING', 'PENDING_APPROVAL', 'ONHOLD')) then
    raise exception 'A refund for this payment is already in progress.' using errcode = 'P0001';
  end if;
  select coalesce(sum(amount_in_paise), 0) into v_inflight from public.rent_refunds
   where payment_id = v_row.id and status = 'SUCCESS';
  if p_amount_paise > v_row.amount_in_paise - greatest(v_inflight, v_row.refunded_paise) then
    raise exception 'That is more than is left to refund on this payment.' using errcode = 'P0001';
  end if;

  insert into public.rent_refunds (payment_id, refund_id, amount_in_paise, note, initiated_by, initiated_role)
  values (v_row.id, p_refund_id, p_amount_paise, nullif(left(btrim(coalesce(p_note, '')), 200), ''), p_actor, v_role)
  returning id into v_id;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (p_actor, v_role::public.user_role, 'payment.cashfree.refund_requested', 'rent_payment', v_row.id::text, v_row.pg_id,
          jsonb_build_object('refund_id', p_refund_id, 'amount_paise', p_amount_paise));

  return jsonb_build_object('refund_row_id', v_id, 'refund_id', p_refund_id, 'order_id', v_row.cashfree_order_id,
                            'vendor_id', v_row.cashfree_vendor_id, 'split_status', v_row.split_status,
                            'amount_paise', p_amount_paise);
end
$fn$;

create or replace function public.svc_cf_refund_result(p_refund_id text, p_status text, p_cf_refund_id text,
                                                       p_response jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_ref     public.rent_refunds%rowtype;
  v_pay     public.rent_payments%rowtype;
  v_status  text := upper(coalesce(p_status, ''));
  v_reverse bigint;
begin
  perform app.cf_require_service();
  select * into v_ref from public.rent_refunds where refund_id = p_refund_id for update;
  if v_ref.id is null then
    raise exception 'Unknown refund.' using errcode = 'P0001';
  end if;
  if v_status not in ('PENDING', 'PENDING_APPROVAL', 'ONHOLD', 'SUCCESS', 'CANCELLED', 'REJECTED', 'FAILED') then
    v_status := 'PENDING';
  end if;
  -- A refund that already succeeded stays succeeded.
  if v_ref.status = 'SUCCESS' then
    return jsonb_build_object('outcome', 'already');
  end if;

  update public.rent_refunds
     set status = v_status, cf_refund_id = coalesce(nullif(p_cf_refund_id, ''), cf_refund_id),
         provider_response = coalesce(p_response, provider_response), failure_reason = p_reason,
         processed_at = case when v_status in ('SUCCESS', 'CANCELLED', 'REJECTED', 'FAILED') then now() end
   where id = v_ref.id
  returning * into v_ref;

  if v_status <> 'SUCCESS' then
    return jsonb_build_object('outcome', lower(v_status));
  end if;

  select * into v_pay from public.rent_payments where id = v_ref.payment_id for update;
  -- The ledger gives back only what it was credited: an overpaid part never reached it.
  v_reverse := least(v_ref.amount_in_paise, greatest(v_pay.credited_paise - v_pay.reversed_paise, 0));
  if v_reverse > 0 then
    update public.fee_payments f
       set amount_paid = greatest(f.amount_paid - round(v_reverse::numeric / 100, 2), 0),
           notes = left(coalesce(f.notes || chr(10), '') || format('Refunded %s · Cashfree %s',
                        to_char(v_reverse / 100.0, 'FM99999990.00'), v_ref.refund_id), 2000)
     where f.student_id = v_pay.tenant_id and f.period_month = v_pay.period_month;
  end if;
  update public.rent_payments
     set refunded_paise = refunded_paise + v_ref.amount_in_paise,
         reversed_paise = reversed_paise + v_reverse,
         payment_status = case when refunded_paise + v_ref.amount_in_paise >= amount_in_paise then 'REFUNDED' else payment_status end
   where id = v_pay.id;
  update public.rent_refunds set reversed_at = now() where id = v_ref.id;

  insert into public.notifications (hostel_id, user_id, type, title, body, link, dedupe_key)
  values (v_pay.pg_id, v_pay.tenant_user_id, 'fee', 'Refund processed',
          format('₹%s of your rent for %s was refunded to your account.', to_char(v_ref.amount_in_paise / 100.0, 'FM99999990.00'),
                 v_pay.period_month), '/student/payments', 'cf_refund:' || v_ref.refund_id)
  on conflict do nothing;
  return jsonb_build_object('outcome', 'success', 'reversed_paise', v_reverse);
end
$fn$;

-- ─── Service: webhook ledger ────────────────────────────────────────────────────────────────
create or replace function public.svc_cf_webhook_begin(p_event_id text, p_type text, p_order_id text, p_hash text)
returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_row public.payment_webhook_events%rowtype;
begin
  perform app.cf_require_service();
  insert into public.payment_webhook_events (provider_event_id, event_type, order_id, payload_hash)
  values (p_event_id, left(p_type, 80), left(p_order_id, 60), p_hash)
  on conflict (provider, provider_event_id) do nothing
  returning * into v_row;
  if v_row.id is not null then
    return jsonb_build_object('outcome', 'new', 'id', v_row.id);
  end if;
  select * into v_row from public.payment_webhook_events where provider = 'cashfree' and provider_event_id = p_event_id;
  if v_row.processing_status in ('processed', 'ignored') then
    return jsonb_build_object('outcome', 'duplicate', 'id', v_row.id);
  end if;
  update public.payment_webhook_events set attempts = attempts + 1 where id = v_row.id;
  return jsonb_build_object('outcome', 'retry', 'id', v_row.id);
end
$fn$;

create or replace function public.svc_cf_webhook_end(p_id uuid, p_status text, p_error text) returns void
language plpgsql security definer set search_path = '' as $fn$
begin
  perform app.cf_require_service();
  update public.payment_webhook_events
     set processing_status = p_status, error = left(p_error, 500), processed_at = now()
   where id = p_id;
end
$fn$;

-- ─── Service: vendor accounts ───────────────────────────────────────────────────────────────
create or replace function public.svc_cf_vendor_save(p_owner uuid, p_vendor_id text, p_legal_name text, p_email text,
                                                     p_phone text, p_vpa text, p_beneficiary text, p_pan_last4 text,
                                                     p_gstin text, p_vendor_status text, p_schedule int,
                                                     p_schedule_message text, p_response jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_verif text := case when upper(coalesce(p_vendor_status, '')) = 'ACTIVE' then 'verified'
                       when upper(coalesce(p_vendor_status, '')) in ('BLOCKED', 'DELETED') then 'rejected'
                       else 'pending' end;
  v_id uuid;
begin
  perform app.cf_require_service();
  if not exists (select 1 from public.users where id = p_owner and role = 'owner') then
    raise exception 'Only an owner can have a payment account.' using errcode = '42501';
  end if;
  insert into public.owner_payment_accounts (owner_id, cashfree_vendor_id, legal_name, email, phone, upi_vpa,
                                             beneficiary_name, pan_last4, gstin, vendor_status, verification_status,
                                             settlement_schedule, settlement_schedule_message, provider_response,
                                             last_error, last_checked_at, activated_at)
  values (p_owner, p_vendor_id, p_legal_name, lower(p_email), p_phone, p_vpa, p_beneficiary, p_pan_last4, p_gstin,
          upper(p_vendor_status), v_verif, p_schedule, p_schedule_message, p_response, null, now(),
          case when v_verif = 'verified' then now() end)
  on conflict (owner_id) do update
    set legal_name = excluded.legal_name, email = excluded.email, phone = excluded.phone, upi_vpa = excluded.upi_vpa,
        beneficiary_name = excluded.beneficiary_name, pan_last4 = coalesce(excluded.pan_last4, public.owner_payment_accounts.pan_last4),
        gstin = excluded.gstin, vendor_status = excluded.vendor_status, verification_status = excluded.verification_status,
        settlement_schedule = coalesce(excluded.settlement_schedule, public.owner_payment_accounts.settlement_schedule),
        settlement_schedule_message = coalesce(excluded.settlement_schedule_message, public.owner_payment_accounts.settlement_schedule_message),
        provider_response = excluded.provider_response, last_error = null, last_checked_at = now(),
        activated_at = case when excluded.verification_status = 'verified'
                            then coalesce(public.owner_payment_accounts.activated_at, now()) end
  returning id into v_id;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (p_owner, 'owner', 'payment.cashfree.vendor_saved', 'owner_payment_account', v_id::text,
          jsonb_build_object('vendor_id', p_vendor_id, 'vendor_status', upper(p_vendor_status)));
  return jsonb_build_object('id', v_id, 'verification_status', v_verif);
end
$fn$;

create or replace function public.svc_cf_vendor_status(p_vendor_id text, p_vendor_status text, p_response jsonb,
                                                       p_error text) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare
  v_verif text := case when upper(coalesce(p_vendor_status, '')) = 'ACTIVE' then 'verified'
                       when upper(coalesce(p_vendor_status, '')) in ('BLOCKED', 'DELETED') then 'rejected'
                       else 'pending' end;
  v_row public.owner_payment_accounts%rowtype;
begin
  perform app.cf_require_service();
  update public.owner_payment_accounts
     set vendor_status = coalesce(upper(p_vendor_status), vendor_status),
         verification_status = case when p_vendor_status is null then verification_status else v_verif end,
         provider_response = coalesce(p_response, provider_response), last_error = left(p_error, 300),
         last_checked_at = now(),
         activated_at = case when p_vendor_status is not null and v_verif = 'verified' then coalesce(activated_at, now())
                             when p_vendor_status is not null then null else activated_at end
   where cashfree_vendor_id = p_vendor_id
  returning * into v_row;
  if v_row.id is not null and v_row.verification_status = 'verified' and v_row.activated_at > now() - interval '1 minute' then
    insert into public.notifications (user_id, type, title, body, link, dedupe_key)
    values (v_row.owner_id, 'fee', 'Online rent is on',
            'Cashfree verified your UPI ID. Tenants can now pay rent in the app, settled to ' || v_row.upi_vpa || '.',
            '/owner/payments', 'cf_vendor_active:' || v_row.cashfree_vendor_id || ':' || to_char(now(), 'YYYYMMDD'))
    on conflict do nothing;
  end if;
  return jsonb_build_object('verification_status', v_row.verification_status);
end
$fn$;

-- ─── Owner dashboard figures ────────────────────────────────────────────────────────────────
create or replace function public.ow_rent_payment_summary() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_owner  uuid := auth.uid();
  v_period text := to_char(app.today(), 'YYYY-MM');
begin
  if not coalesce(app.user_role() = 'owner', false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'period_month', v_period,
    'collected_paise', (select coalesce(sum(amount_in_paise - refunded_paise), 0) from public.rent_payments
                         where owner_id = v_owner and payment_status in ('SUCCESS', 'REFUNDED')),
    'collected_this_month_paise', (select coalesce(sum(amount_in_paise - refunded_paise), 0) from public.rent_payments
                                    where owner_id = v_owner and payment_status in ('SUCCESS', 'REFUNDED')
                                      and period_month = v_period),
    'verified_count', (select count(*) from public.rent_payments where owner_id = v_owner and payment_status = 'SUCCESS'),
    'awaiting_settlement_paise', (select coalesce(sum(amount_in_paise - refunded_paise), 0) from public.rent_payments
                                   where owner_id = v_owner and payment_status in ('SUCCESS', 'REFUNDED')
                                     and settlement_status in ('SPLIT_PENDING', 'SPLIT_CREATED', 'SETTLEMENT_PENDING')),
    'settled_paise', (select coalesce(sum(amount_in_paise - refunded_paise), 0) from public.rent_payments
                       where owner_id = v_owner and settlement_status = 'SETTLED'),
    'failed_settlements', (select count(*) from public.rent_payments
                            where owner_id = v_owner and settlement_status = 'SETTLEMENT_FAILED'),
    'needs_attention', (select count(*) from public.rent_payments
                         where owner_id = v_owner and payment_status = 'SUCCESS' and (overpaid or credit_error is not null)),
    'pending_rent_paise', (select coalesce(sum(app.cf_outstanding_paise(s.id, v_period)), 0)
                             from public.students s join public.hostels h on h.id = s.hostel_id
                            where h.owner_user_id = v_owner and s.status <> 'vacated' and s.deleted_at is null));
end
$fn$;

-- ─── Grants ─────────────────────────────────────────────────────────────────────────────────
revoke all on function app.cf_outstanding_paise(uuid, text) from public, anon, authenticated;
revoke all on function public.st_rent_gateway(), public.cf_reserve_payment(text, bigint),
                       public.ow_rent_payment_summary() from public, anon;
grant execute on function public.st_rent_gateway(), public.cf_reserve_payment(text, bigint),
                          public.ow_rent_payment_summary() to authenticated;
revoke all on function public.svc_cf_attach_session(text, text, text, timestamptz),
                       public.svc_cf_abandon_order(text, text),
                       public.svc_cf_apply_payment(text, text, text, text, bigint, text, text, text, timestamptz, text),
                       public.svc_cf_close_unpaid(text, text),
                       public.svc_cf_split_claim(int),
                       public.svc_cf_split_result(uuid, text, jsonb, text),
                       public.svc_cf_link_settlement(text, text, text, numeric, timestamptz),
                       public.svc_cf_settlement_event(text, text, text, numeric, text, text, timestamptz, jsonb),
                       public.svc_cf_request_refund(uuid, uuid, bigint, text, text),
                       public.svc_cf_refund_result(text, text, text, jsonb, text),
                       public.svc_cf_webhook_begin(text, text, text, text),
                       public.svc_cf_webhook_end(uuid, text, text),
                       public.svc_cf_vendor_save(uuid, text, text, text, text, text, text, text, text, text, int, text, jsonb),
                       public.svc_cf_vendor_status(text, text, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.svc_cf_attach_session(text, text, text, timestamptz),
                          public.svc_cf_abandon_order(text, text),
                          public.svc_cf_apply_payment(text, text, text, text, bigint, text, text, text, timestamptz, text),
                          public.svc_cf_close_unpaid(text, text),
                          public.svc_cf_split_claim(int),
                          public.svc_cf_split_result(uuid, text, jsonb, text),
                          public.svc_cf_link_settlement(text, text, text, numeric, timestamptz),
                          public.svc_cf_settlement_event(text, text, text, numeric, text, text, timestamptz, jsonb),
                          public.svc_cf_request_refund(uuid, uuid, bigint, text, text),
                          public.svc_cf_refund_result(text, text, text, jsonb, text),
                          public.svc_cf_webhook_begin(text, text, text, text),
                          public.svc_cf_webhook_end(uuid, text, text),
                          public.svc_cf_vendor_save(uuid, text, text, text, text, text, text, text, text, text, int, text, jsonb),
                          public.svc_cf_vendor_status(text, text, jsonb, text)
  to service_role;

-- ─── C7 The worker tick ─────────────────────────────────────────────────────────────────────
-- Same channel push-send uses (app.push_config: project URL + anon key). The worker takes no
-- input that matters and only does idempotent, server-verified work, so the anon key is enough.
create or replace function app.cashfree_tick() returns void
language plpgsql security definer set search_path = '' as $fn$
declare
  v_cfg app.push_config%rowtype;
begin
  select * into v_cfg from app.push_config where id;
  if not found or v_cfg.function_url is null then
    return;
  end if;
  perform net.http_post(
    url     := replace(v_cfg.function_url, '/push-send', '/cashfree-worker'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_cfg.anon_key),
    body    := '{}'::jsonb,
    timeout_milliseconds := 8000);
exception when others then
  return;
end
$fn$;
revoke all on function app.cashfree_tick() from public, anon, authenticated;

select cron.schedule('apnivaas-cashfree-tick', '* * * * *', 'select app.cashfree_tick()');

do $verify$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and (p.proname like 'svc\_cf\_%' or p.proname in ('cf_reserve_payment', 'st_rent_gateway', 'ow_rent_payment_summary'))
                and (not p.prosecdef or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=""')) then
    raise exception 'a Cashfree routine is not SECURITY DEFINER with an empty search_path';
  end if;
  if has_function_privilege('authenticated', 'public.svc_cf_apply_payment(text, text, text, text, bigint, text, text, text, timestamptz, text)', 'execute')
     or has_function_privilege('anon', 'public.cf_reserve_payment(text, bigint)', 'execute') then
    raise exception 'a Cashfree routine is callable by the wrong role';
  end if;
  if has_column_privilege('authenticated', 'public.rent_payments', 'payment_session_id', 'select') then
    raise exception 'the checkout session is readable by clients';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261104090000', 'cashfree_rent') on conflict (version) do nothing;

notify pgrst, 'reload schema';

commit;
