-- ============================================================================
--  HostelPro — PG / Hostel Management SaaS
--  db/schema.sql  ·  tables, helper functions, triggers, RPCs
--  Apply in order:  schema.sql  →  rls-policies.sql  →  (npm run db:seed)
--  Idempotent-ish: safe to re-run on a fresh database.
-- ============================================================================

create extension if not exists "pgcrypto";

-- Private helper schema (functions used by RLS + triggers)
create schema if not exists app;
grant usage on schema app to authenticated, anon, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
  create type public.user_role as enum ('super_admin','owner','manager','warden','student');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.user_status as enum ('active','inactive');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.hostel_status as enum ('active','readonly','suspended');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.subscription_status as enum ('active','expiring','expired');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.bed_status as enum ('free','occupied');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.student_status as enum ('active','on_leave','vacated');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.fee_status as enum ('paid','partial','unpaid');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.payment_mode as enum ('cash','upi','bank');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.complaint_category as enum ('food','cleaning','maintenance','wifi','roommate','other');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.complaint_status as enum ('open','in_progress','resolved');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.expense_category as enum ('groceries','staff','electricity','water','maintenance','other');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.revenue_source as enum ('fees','mess','other');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.announcement_audience as enum ('all','manager','warden','students');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.task_status as enum ('pending','in_progress','done');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.leave_status as enum ('pending','approved','rejected');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.day_of_week as enum ('mon','tue','wed','thu','fri','sat','sun');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.meal_type as enum ('breakfast','lunch','snacks','dinner');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.notification_type as enum ('announcement','task','complaint','leave','subscription','fee','system');
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────────────────────────────────────────

-- users: profile row for every auth user (id = auth.users.id)
create table if not exists public.users (
  id                   uuid primary key references auth.users(id) on delete cascade,
  role                 public.user_role not null,
  full_name            text not null,
  email                text,
  phone                text,
  hostel_id            uuid,                                -- null for super_admin
  status               public.user_status not null default 'active',
  must_change_password boolean not null default true,
  created_by           uuid references public.users(id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);
create index if not exists users_hostel_role_idx on public.users (hostel_id, role, status);
create unique index if not exists users_email_key on public.users (lower(email)) where email is not null;

create table if not exists public.hostels (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  owner_user_id         uuid not null references public.users(id),
  total_floors          int  not null check (total_floors between 1 and 50),
  total_rooms           int  not null check (total_rooms between 1 and 5000),
  beds_per_room_default int  not null default 3 check (beds_per_room_default between 1 and 12),
  address               text,
  rules                 text,                                -- static hostel rules (owner-editable)
  status                public.hostel_status not null default 'active',
  created_by            uuid references public.users(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index if not exists hostels_owner_idx on public.hostels (owner_user_id);

-- users.hostel_id → hostels (added after hostels exists; circular FK)
do $$ begin
  alter table public.users
    add constraint users_hostel_id_fkey foreign key (hostel_id) references public.hostels(id);
exception when duplicate_object then null; end $$;

create table if not exists public.subscriptions (
  id             uuid primary key default gen_random_uuid(),
  hostel_id      uuid not null references public.hostels(id) on delete cascade,
  owner_user_id  uuid not null references public.users(id),
  start_date     date not null,
  end_date       date not null check (end_date >= start_date),
  amount         numeric(12,2) not null default 0 check (amount >= 0 and amount <= 100000000),
  status         public.subscription_status not null default 'active',
  created_by     uuid references public.users(id),
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists subscriptions_hostel_idx on public.subscriptions (hostel_id, end_date desc);

create table if not exists public.floors (
  id            uuid primary key default gen_random_uuid(),
  hostel_id     uuid not null references public.hostels(id) on delete cascade,
  floor_number  int  not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (hostel_id, floor_number)
);

create table if not exists public.rooms (
  id           uuid primary key default gen_random_uuid(),
  hostel_id    uuid not null references public.hostels(id) on delete cascade,
  floor_id     uuid not null references public.floors(id) on delete cascade,
  room_number  text not null,
  capacity     int  not null default 3 check (capacity between 1 and 12),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (hostel_id, room_number)
);
create index if not exists rooms_floor_idx on public.rooms (floor_id);

create table if not exists public.students (
  id                uuid primary key default gen_random_uuid(),
  hostel_id         uuid not null references public.hostels(id) on delete cascade,
  user_id           uuid references public.users(id),
  full_name         text not null,
  phone             text not null,
  email             text,
  photo_url         text,
  guardian_name     text,
  guardian_phone    text,
  permanent_address text,
  id_proof_type     text,
  id_proof_url      text,
  date_of_joining   date not null default current_date,
  room_id           uuid references public.rooms(id),
  bed_id            uuid,                                   -- FK added after beds
  monthly_fee       numeric(10,2) not null default 0 check (monthly_fee >= 0 and monthly_fee <= 10000000),
  status            public.student_status not null default 'active',
  vacated_at        timestamptz,
  created_by        uuid references public.users(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);
create index if not exists students_hostel_status_idx on public.students (hostel_id, status);
create index if not exists students_room_idx on public.students (room_id);
create index if not exists students_user_idx on public.students (user_id);
-- Hard rule §4.7 — a bed holds at most one active student (race-safe)
create unique index if not exists students_one_active_per_bed
  on public.students (bed_id) where bed_id is not null and status <> 'vacated';
-- phone is the student login → must be unique among non-vacated students
create unique index if not exists students_phone_active_key
  on public.students (phone) where status <> 'vacated';

create table if not exists public.beds (
  id          uuid primary key default gen_random_uuid(),
  hostel_id   uuid not null references public.hostels(id) on delete cascade,  -- denormalised for RLS
  room_id     uuid not null references public.rooms(id) on delete cascade,
  bed_number  int  not null,
  status      public.bed_status not null default 'free',
  student_id  uuid references public.students(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (room_id, bed_number)
);
create index if not exists beds_room_idx on public.beds (room_id);
create unique index if not exists beds_student_key on public.beds (student_id) where student_id is not null;

do $$ begin
  alter table public.students
    add constraint students_bed_id_fkey foreign key (bed_id) references public.beds(id);
exception when duplicate_object then null; end $$;

create table if not exists public.fee_payments (
  id            uuid primary key default gen_random_uuid(),
  hostel_id     uuid not null references public.hostels(id) on delete cascade,
  student_id    uuid not null references public.students(id) on delete cascade,
  period_month  text not null check (period_month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  amount_due    numeric(10,2) not null default 0 check (amount_due >= 0 and amount_due <= 10000000),
  amount_paid   numeric(10,2) not null default 0 check (amount_paid >= 0 and amount_paid <= 10000000),
  status        public.fee_status not null default 'unpaid',
  paid_on       date,
  mode          public.payment_mode,
  notes         text,
  recorded_by   uuid references public.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (student_id, period_month)
);
create index if not exists fee_payments_hostel_period_idx on public.fee_payments (hostel_id, period_month);

create table if not exists public.complaints (
  id               uuid primary key default gen_random_uuid(),
  hostel_id        uuid not null references public.hostels(id) on delete cascade,
  student_id       uuid not null references public.students(id) on delete cascade,
  category         public.complaint_category not null default 'other',
  title            text not null,
  description      text,
  photo_url        text,
  status           public.complaint_status not null default 'open',
  resolved_at      timestamptz,
  resolution_note  text,
  updated_by       uuid references public.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists complaints_hostel_status_idx on public.complaints (hostel_id, status, created_at desc);
create index if not exists complaints_student_idx on public.complaints (student_id);

-- Complaint status timeline (auto-populated by trigger)
create table if not exists public.complaint_events (
  id             uuid primary key default gen_random_uuid(),
  hostel_id      uuid not null references public.hostels(id) on delete cascade,
  complaint_id   uuid not null references public.complaints(id) on delete cascade,
  status         public.complaint_status not null,
  note           text,
  actor_user_id  uuid references public.users(id),
  created_at     timestamptz not null default now()
);
create index if not exists complaint_events_complaint_idx on public.complaint_events (complaint_id, created_at);

create table if not exists public.expenses (
  id           uuid primary key default gen_random_uuid(),
  hostel_id    uuid not null references public.hostels(id) on delete cascade,
  date         date not null default current_date,
  category     public.expense_category not null default 'other',
  amount       numeric(12,2) not null check (amount >= 0 and amount <= 100000000),
  note         text,
  receipt_url  text,
  uploaded_by  uuid references public.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index if not exists expenses_hostel_date_idx on public.expenses (hostel_id, date desc);

create table if not exists public.revenues (
  id           uuid primary key default gen_random_uuid(),
  hostel_id    uuid not null references public.hostels(id) on delete cascade,
  date         date not null default current_date,
  source       public.revenue_source not null default 'other',
  amount       numeric(12,2) not null check (amount >= 0 and amount <= 100000000),
  note         text,
  uploaded_by  uuid references public.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index if not exists revenues_hostel_date_idx on public.revenues (hostel_id, date desc);

create table if not exists public.announcements (
  id              uuid primary key default gen_random_uuid(),
  hostel_id       uuid not null references public.hostels(id) on delete cascade,
  author_user_id  uuid not null references public.users(id),
  title           text not null,
  body            text not null,
  audience        public.announcement_audience not null default 'all',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);
create index if not exists announcements_hostel_idx on public.announcements (hostel_id, created_at desc);

create table if not exists public.tasks (
  id            uuid primary key default gen_random_uuid(),
  hostel_id     uuid not null references public.hostels(id) on delete cascade,
  assigned_to   uuid not null references public.users(id),   -- manager user_id
  title         text not null,
  description   text,
  due_date      date,
  status        public.task_status not null default 'pending',
  created_by    uuid not null references public.users(id),   -- owner
  completed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index if not exists tasks_hostel_idx on public.tasks (hostel_id, status, due_date);

create table if not exists public.leaves (
  id             uuid primary key default gen_random_uuid(),
  hostel_id      uuid not null references public.hostels(id) on delete cascade,
  student_id     uuid not null references public.students(id) on delete cascade,
  from_date      date not null,
  to_date        date not null check (to_date >= from_date),
  reason         text,
  status         public.leave_status not null default 'pending',
  decided_by     uuid references public.users(id),
  decided_at     timestamptz,
  decision_note  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists leaves_hostel_status_idx on public.leaves (hostel_id, status, created_at desc);
create index if not exists leaves_student_idx on public.leaves (student_id);

create table if not exists public.visitors (
  id             uuid primary key default gen_random_uuid(),
  hostel_id      uuid not null references public.hostels(id) on delete cascade,
  student_id     uuid not null references public.students(id) on delete cascade,
  visitor_name   text not null,
  visitor_phone  text,
  relation       text,
  check_in_at    timestamptz not null default now(),
  check_out_at   timestamptz,
  logged_by      uuid references public.users(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists visitors_hostel_idx on public.visitors (hostel_id, check_in_at desc);

create table if not exists public.menus (
  id           uuid primary key default gen_random_uuid(),
  hostel_id    uuid not null references public.hostels(id) on delete cascade,
  day_of_week  public.day_of_week not null,
  meal         public.meal_type not null,
  items        text not null default '',
  updated_by   uuid references public.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (hostel_id, day_of_week, meal)
);

-- In-app notifications (§7). Rows are created by triggers below.
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  hostel_id   uuid references public.hostels(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  type        public.notification_type not null default 'system',
  title       text not null,
  body        text,
  link        text,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, read_at, created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- HELPER FUNCTIONS (schema app) — used by RLS policies and triggers
-- All are SECURITY DEFINER so they can read public.users regardless of RLS.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function app.uid() returns uuid
language sql stable set search_path = public as $$ select auth.uid() $$;

-- JWT-claim based (NOT current_user — inside SECURITY DEFINER functions current_user
-- would be the function owner and this would wrongly return true for everyone).
create or replace function app.is_service_role() returns boolean
language sql stable set search_path = public as $$
  select coalesce(auth.role() = 'service_role', false)
$$;

create or replace function app.user_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.users where id = auth.uid() and status = 'active' and deleted_at is null
$$;

create or replace function app.user_hostel_id() returns uuid
language sql stable security definer set search_path = public as $$
  select hostel_id from public.users where id = auth.uid() and status = 'active' and deleted_at is null
$$;

create or replace function app.is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(app.user_role() = 'super_admin', false) or app.is_service_role()
$$;

create or replace function app.owns_hostel(p_hostel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hostels h
    where h.id = p_hostel_id and h.owner_user_id = auth.uid()
  ) and coalesce(app.user_role() = 'owner', false)
$$;

-- Read access to a hostel: super admin, the owner, or staff/students of that hostel
create or replace function app.can_read_hostel(p_hostel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_super_admin()
      or app.owns_hostel(p_hostel_id)
      or app.user_hostel_id() = p_hostel_id
$$;

-- Effective subscription status for a hostel (computed live from end_date)
create or replace function app.subscription_state(p_hostel_id uuid) returns public.subscription_status
language sql stable security definer set search_path = public as $$
  select case
    when max(end_date) is null then 'expired'::public.subscription_status
    when max(end_date) < current_date then 'expired'::public.subscription_status
    when max(end_date) - current_date <= 15 then 'expiring'::public.subscription_status
    else 'active'::public.subscription_status
  end
  from public.subscriptions where hostel_id = p_hostel_id
$$;

create or replace function app.subscription_days_left(p_hostel_id uuid) returns int
language sql stable security definer set search_path = public as $$
  select (max(end_date) - current_date)::int from public.subscriptions where hostel_id = p_hostel_id
$$;

-- Hard rule §4.4 — writes are blocked when subscription expired or hostel not active
create or replace function app.hostel_writable(p_hostel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.hostels h
    where h.id = p_hostel_id
      and h.status = 'active'
      and app.subscription_state(h.id) <> 'expired'
  )
$$;

create or replace function app.can_write_hostel(p_hostel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_super_admin()
      or (app.can_read_hostel(p_hostel_id) and app.hostel_writable(p_hostel_id))
$$;

create or replace function app.is_staff_of(p_hostel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_super_admin()
      or app.owns_hostel(p_hostel_id)
      or (app.user_hostel_id() = p_hostel_id and app.user_role() in ('manager','warden'))
$$;

create or replace function app.has_role_in(p_hostel_id uuid, variadic p_roles public.user_role[]) returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_super_admin()
      or (app.user_role() = 'owner' and 'owner' = any(p_roles) and app.owns_hostel(p_hostel_id))
      or (app.user_hostel_id() = p_hostel_id and app.user_role() = any(p_roles) and app.user_role() <> 'owner')
$$;

create or replace function app.current_student_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.students where user_id = auth.uid() and status <> 'vacated' limit 1
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- GENERIC TRIGGERS
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function app.set_updated_at() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['users','hostels','subscriptions','floors','rooms','beds','students',
                           'fee_payments','complaints','expenses','revenues','announcements',
                           'tasks','leaves','visitors','menus']
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format('create trigger set_updated_at before update on public.%I
                    for each row execute function app.set_updated_at()', t);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- HARD RULE §4.3 — role limits (1 manager, 1 warden, 10 000 students per hostel)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.enforce_role_limits() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_count int;
  v_limit int;
begin
  if new.status <> 'active' or new.deleted_at is not null then
    return new;
  end if;
  if new.role not in ('manager','warden','student') then
    return new;
  end if;
  if new.hostel_id is null then
    raise exception 'A % must belong to a hostel.', new.role using errcode = 'P0001';
  end if;

  v_limit := case new.role when 'manager' then 1 when 'warden' then 1 else 10000 end;

  select count(*) into v_count
  from public.users u
  where u.hostel_id = new.hostel_id
    and u.role = new.role
    and u.status = 'active'
    and u.deleted_at is null
    and u.id <> new.id;

  if v_count >= v_limit then
    if new.role = 'student' then
      raise exception 'This hostel has reached the limit of 10,000 active students.' using errcode = 'P0001';
    else
      raise exception 'This hostel already has an active %. Deactivate the current % first.', new.role, new.role using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists enforce_role_limits on public.users;
create trigger enforce_role_limits
  before insert or update of role, status, hostel_id, deleted_at on public.users
  for each row execute function app.enforce_role_limits();

-- The trigger above does a count(*), which two concurrent inserts can both pass (TOCTOU).
-- This partial unique index makes the "1 active manager / 1 active warden per hostel" rule
-- race-proof at the storage layer; the trigger stays for the friendly error message.
create unique index if not exists users_one_active_staff_per_hostel
  on public.users (hostel_id, role)
  where role in ('manager','warden') and status = 'active' and deleted_at is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- PRIVILEGED COLUMN GUARD on public.users (checklist §4 "users cannot alter their
-- own role", §14 mass assignment).
--
-- RLS gates ROWS, not COLUMNS: the users_update policy allows `id = auth.uid()` so a
-- signed-in user could otherwise call PostgREST directly —
--     PATCH /rest/v1/users?id=eq.<self>   {"role":"super_admin"}
-- — and escalate to platform admin, because the anon key and REST endpoint are public.
-- This trigger makes role / hostel_id / status / created_by privileged on EVERY write
-- path (app, PostgREST, SQL), so authorization no longer depends on the client.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.users_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_manages_target boolean;
begin
  -- Super Admin (and the service role, used by account-management server actions)
  -- may change anything; those paths do their own authorization first.
  if app.is_super_admin() then
    return new;
  end if;

  -- Who legitimately administers the TARGET account?
  v_manages_target :=
       (old.role in ('manager','warden') and app.owns_hostel(old.hostel_id))
    or (old.role = 'student' and app.has_role_in(old.hostel_id, 'warden'));

  -- Identity, role and tenant binding are never self-serviceable.
  if new.id is distinct from old.id then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    raise exception 'You cannot change an account''s role.' using errcode = '42501';
  end if;
  if new.hostel_id is distinct from old.hostel_id then
    raise exception 'You cannot move an account to another hostel.' using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  -- Activation state may only be changed by the account's administrator.
  if (new.status is distinct from old.status or new.deleted_at is distinct from old.deleted_at)
     and not v_manages_target then
    raise exception 'You cannot change this account''s status.' using errcode = '42501';
  end if;

  -- Remaining columns (full_name, phone, email, must_change_password):
  -- the account holder themselves, or the account's administrator.
  if new.id = auth.uid() or v_manages_target then
    return new;
  end if;
  raise exception 'Not allowed.' using errcode = '42501';
end $$;

drop trigger if exists users_update_guard on public.users;
create trigger users_update_guard before update on public.users
  for each row execute function app.users_update_guard();

-- ─────────────────────────────────────────────────────────────────────────────
-- HARD RULE §4.7 — bed ↔ student integrity  (students.bed_id is source of truth)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.students_bed_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_bed public.beds%rowtype;
begin
  -- Vacated students never hold a bed
  if new.status = 'vacated' then
    if tg_op = 'UPDATE' and old.status <> 'vacated' then
      new.vacated_at := coalesce(new.vacated_at, now());
    end if;
    new.bed_id := null;
    new.room_id := null;
    return new;
  end if;

  if new.bed_id is not null then
    select * into v_bed from public.beds where id = new.bed_id;
    if not found then
      raise exception 'Selected bed does not exist.' using errcode = 'P0001';
    end if;
    if v_bed.hostel_id <> new.hostel_id then
      raise exception 'Bed belongs to a different hostel.' using errcode = 'P0001';
    end if;
    -- another active student already on that bed?
    if exists (
      select 1 from public.students s
      where s.bed_id = new.bed_id and s.id <> new.id and s.status <> 'vacated'
    ) then
      raise exception 'Bed % is already occupied. Choose a free bed.', v_bed.bed_number using errcode = 'P0001';
    end if;
    new.room_id := v_bed.room_id;
  else
    new.room_id := null;
  end if;
  return new;
end $$;

drop trigger if exists students_bed_guard on public.students;
create trigger students_bed_guard
  before insert or update of bed_id, status, hostel_id on public.students
  for each row execute function app.students_bed_guard();

-- keep beds.status / beds.student_id in sync
create or replace function app.students_bed_sync() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.bed_id is not null and old.bed_id is distinct from new.bed_id then
    update public.beds set status = 'free', student_id = null where id = old.bed_id and student_id = old.id;
  end if;
  if new.bed_id is not null and new.status <> 'vacated' then
    update public.beds set status = 'occupied', student_id = new.id where id = new.bed_id;
  elsif tg_op = 'UPDATE' and old.bed_id is not null and new.bed_id is null then
    update public.beds set status = 'free', student_id = null where id = old.bed_id and student_id = old.id;
  end if;
  return new;
end $$;

drop trigger if exists students_bed_sync on public.students;
create trigger students_bed_sync
  after insert or update of bed_id, status on public.students
  for each row execute function app.students_bed_sync();

-- Prevent direct edits to beds.student_id (must go through students)
create or replace function app.beds_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.student_id is distinct from old.student_id
     and not app.is_service_role() and current_setting('app.bypass_bed_guard', true) is distinct from 'on' then
    -- allow only when the referenced student actually points at this bed (trigger-driven sync)
    if new.student_id is not null and not exists (
      select 1 from public.students s where s.id = new.student_id and s.bed_id = new.id and s.status <> 'vacated'
    ) then
      raise exception 'Assign beds by updating the student record, not the bed.' using errcode = 'P0001';
    end if;
  end if;
  new.status := case when new.student_id is null then 'free' else 'occupied' end;
  return new;
end $$;

drop trigger if exists beds_guard on public.beds;
create trigger beds_guard before insert or update on public.beds
  for each row execute function app.beds_guard();

-- Deleting a bed that has an active student is not allowed (capacity edits)
create or replace function app.beds_delete_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.students s where s.bed_id = old.id and s.status <> 'vacated') then
    raise exception 'Cannot remove bed % — a student is assigned to it.', old.bed_number using errcode = 'P0001';
  end if;
  return old;
end $$;
drop trigger if exists beds_delete_guard on public.beds;
create trigger beds_delete_guard before delete on public.beds
  for each row execute function app.beds_delete_guard();

-- Room capacity ↔ beds: adding capacity creates beds, reducing removes only free beds
create or replace function app.rooms_capacity_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_current int;
  v_i int;
  v_occupied int;
begin
  select count(*) into v_current from public.beds where room_id = new.id;
  if new.capacity > v_current then
    for v_i in (v_current + 1)..new.capacity loop
      insert into public.beds (hostel_id, room_id, bed_number)
      values (new.hostel_id, new.id, v_i)
      on conflict (room_id, bed_number) do nothing;
    end loop;
  elsif new.capacity < v_current then
    select count(*) into v_occupied from public.beds where room_id = new.id and student_id is not null;
    if v_occupied > new.capacity then
      raise exception 'Room % has % occupied beds — capacity cannot be lower than that.', new.room_number, v_occupied using errcode = 'P0001';
    end if;
    delete from public.beds b
    where b.room_id = new.id and b.student_id is null
      and b.id in (
        select id from public.beds where room_id = new.id and student_id is null
        order by bed_number desc limit (v_current - new.capacity)
      );
  end if;
  return new;
end $$;
drop trigger if exists rooms_capacity_sync on public.rooms;
create trigger rooms_capacity_sync after insert or update of capacity on public.rooms
  for each row execute function app.rooms_capacity_sync();

-- ─────────────────────────────────────────────────────────────────────────────
-- FEES — derive status from amounts
-- ─────────────────────────────────────────────────────────────────────────────
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
  if new.amount_paid > 0 and new.paid_on is null then
    new.paid_on := current_date;
  end if;
  return new;
end $$;
drop trigger if exists fee_status_compute on public.fee_payments;
create trigger fee_status_compute before insert or update on public.fee_payments
  for each row execute function app.fee_status_compute();

-- ─────────────────────────────────────────────────────────────────────────────
-- SUBSCRIPTIONS — status derived from dates; hostel read-only on expiry
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.subscription_status_compute() returns trigger
language plpgsql set search_path = public as $$
begin
  new.status := case
    when new.end_date < current_date then 'expired'
    when new.end_date - current_date <= 15 then 'expiring'
    else 'active'
  end;
  return new;
end $$;
drop trigger if exists subscription_status_compute on public.subscriptions;
create trigger subscription_status_compute before insert or update on public.subscriptions
  for each row execute function app.subscription_status_compute();

-- Recompute all subscription statuses + hostel readonly flags; notify owners entering "expiring".
-- Called by the Super Admin dashboard load and by the app on owner dashboard load (cheap).
-- The "Subscription expiring soon" notification was dead code: its loop required
-- `status = 'active' AND end_date - current_date <= 15`, but the subscription_status_compute
-- trigger rewrites status to 'expiring' the moment that window is entered, so the two
-- conditions are mutually exclusive and no owner ever received the notice.
--
-- Fixing the condition alone would create a flood: this runs on EVERY owner and super-admin
-- dashboard load, so each page view would insert another row. The dedup guard is therefore
-- part of the fix, not an optimisation - it also removes any write-amplification value in
-- calling this RPC in a loop (it is callable by any authenticated user by design).
create or replace function public.refresh_subscription_statuses()
returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select s.id, s.hostel_id, s.owner_user_id, h.name, s.end_date
    from public.subscriptions s join public.hostels h on h.id = s.hostel_id
    where s.status in ('active', 'expiring')
      and s.end_date >= current_date and s.end_date - current_date <= 15
      and s.owner_user_id is not null
      and s.id = (select x.id from public.subscriptions x where x.hostel_id = s.hostel_id order by x.end_date desc limit 1)
      -- at most one expiry notice per owner per hostel per 7 days
      and not exists (
        select 1 from public.notifications n
         where n.user_id = s.owner_user_id
           and n.hostel_id = s.hostel_id
           and n.type = 'subscription'
           and n.created_at > now() - interval '7 days'
      )
  loop
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (r.hostel_id, r.owner_user_id, 'subscription', 'Subscription expiring soon',
            format('%s subscription ends on %s. Contact support to renew.', r.name, to_char(r.end_date, 'DD Mon YYYY')), '/owner');
  end loop;

  update public.subscriptions
     set status = case when end_date < current_date then 'expired' when end_date - current_date <= 15 then 'expiring' else 'active' end::public.subscription_status
   where status is distinct from (case when end_date < current_date then 'expired' when end_date - current_date <= 15 then 'expiring' else 'active' end::public.subscription_status);
  update public.hostels h set status = 'readonly' where h.status = 'active' and app.subscription_state(h.id) = 'expired';
  update public.hostels h set status = 'active'   where h.status = 'readonly' and app.subscription_state(h.id) <> 'expired';
end $$;

-- After a subscription is inserted/extended, re-evaluate that hostel's flag immediately
create or replace function app.subscription_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.hostels h set status = 'active'
   where h.id = new.hostel_id and h.status = 'readonly' and app.subscription_state(h.id) <> 'expired';
  update public.hostels h set status = 'readonly'
   where h.id = new.hostel_id and h.status = 'active' and app.subscription_state(h.id) = 'expired';
  return new;
end $$;
drop trigger if exists subscription_after_change on public.subscriptions;
create trigger subscription_after_change after insert or update on public.subscriptions
  for each row execute function app.subscription_after_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPLAINTS — timeline + notifications
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.complaints_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_student_user uuid;
  v_actor uuid := coalesce(auth.uid(), new.updated_by);
  r record;
begin
  if tg_op = 'INSERT' then
    insert into public.complaint_events (hostel_id, complaint_id, status, note, actor_user_id)
    values (new.hostel_id, new.id, new.status, 'Complaint raised', v_actor);

    -- notify owner + warden
    for r in
      select u.id from public.users u
      where u.status = 'active' and u.deleted_at is null and (
        (u.role in ('warden') and u.hostel_id = new.hostel_id)
        or (u.role = 'owner' and u.id = (select owner_user_id from public.hostels where id = new.hostel_id))
      )
    loop
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, r.id, 'complaint', 'New complaint: ' || new.title,
              initcap(new.category::text) || ' complaint raised by a student.',
              case when (select role from public.users where id = r.id) = 'owner' then '/owner/complaints' else '/warden/complaints' end);
    end loop;
    return new;
  end if;

  if tg_op = 'UPDATE' and (new.status is distinct from old.status or new.resolution_note is distinct from old.resolution_note) then
    if new.status = 'resolved' and new.resolved_at is null then
      update public.complaints set resolved_at = now() where id = new.id;
    end if;
    insert into public.complaint_events (hostel_id, complaint_id, status, note, actor_user_id)
    values (new.hostel_id, new.id, new.status,
            case when new.resolution_note is distinct from old.resolution_note then new.resolution_note else null end,
            v_actor);

    if new.status is distinct from old.status then
      select user_id into v_student_user from public.students where id = new.student_id;
      if v_student_user is not null then
        insert into public.notifications (hostel_id, user_id, type, title, body, link)
        values (new.hostel_id, v_student_user, 'complaint',
                'Complaint ' || replace(new.status::text, '_', ' '),
                '"' || new.title || '" is now ' || replace(new.status::text, '_', ' ') || '.',
                '/student/complaints');
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists complaints_after_change on public.complaints;
create trigger complaints_after_change after insert or update on public.complaints
  for each row execute function app.complaints_after_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- ANNOUNCEMENTS — fan out notifications to audience
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.announcements_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select new.hostel_id, u.id, 'announcement', new.title, left(new.body, 140),
         case u.role
           when 'manager' then '/manager'
           when 'warden'  then '/warden'
           when 'student' then '/student'
           else '/owner/updates' end
  from public.users u
  where u.hostel_id = new.hostel_id
    and u.status = 'active' and u.deleted_at is null
    and u.id <> new.author_user_id
    and (
      new.audience = 'all'
      or (new.audience = 'manager'  and u.role = 'manager')
      or (new.audience = 'warden'   and u.role = 'warden')
      or (new.audience = 'students' and u.role = 'student')
    );
  return new;
end $$;
drop trigger if exists announcements_after_insert on public.announcements;
create trigger announcements_after_insert after insert on public.announcements
  for each row execute function app.announcements_after_insert();

-- ─────────────────────────────────────────────────────────────────────────────
-- TASKS — notifications + manager may only change status
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.tasks_before_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if app.user_role() = 'manager' then
    if new.title is distinct from old.title or new.description is distinct from old.description
       or new.due_date is distinct from old.due_date or new.assigned_to is distinct from old.assigned_to
       or new.created_by is distinct from old.created_by or new.deleted_at is distinct from old.deleted_at then
      raise exception 'Managers can only update the task status.' using errcode = 'P0001';
    end if;
  end if;
  if new.status = 'done' and old.status <> 'done' then
    new.completed_at := now();
  elsif new.status <> 'done' then
    new.completed_at := null;
  end if;
  return new;
end $$;
drop trigger if exists tasks_before_update on public.tasks;
create trigger tasks_before_update before update on public.tasks
  for each row execute function app.tasks_before_update();

create or replace function app.tasks_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (new.hostel_id, new.assigned_to, 'task', 'New task: ' || new.title,
            coalesce('Due ' || to_char(new.due_date, 'DD Mon'), 'Assigned by owner'), '/manager/tasks');
  elsif new.status is distinct from old.status then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (new.hostel_id, new.created_by, 'task', 'Task ' || replace(new.status::text, '_', ' '),
            '"' || new.title || '" marked ' || replace(new.status::text, '_', ' ') || ' by manager.', '/owner/staff');
  end if;
  return new;
end $$;
drop trigger if exists tasks_after_change on public.tasks;
create trigger tasks_after_change after insert or update on public.tasks
  for each row execute function app.tasks_after_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- LEAVES — notifications
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.leaves_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_student_user uuid; v_name text; r record;
begin
  select user_id, full_name into v_student_user, v_name from public.students where id = new.student_id;
  if tg_op = 'INSERT' then
    for r in select id from public.users where hostel_id = new.hostel_id and role = 'warden' and status = 'active' and deleted_at is null loop
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, r.id, 'leave', 'Leave request from ' || coalesce(v_name, 'student'),
              to_char(new.from_date, 'DD Mon') || ' → ' || to_char(new.to_date, 'DD Mon'), '/warden/leaves');
    end loop;
  elsif new.status is distinct from old.status and new.status <> 'pending' then
    if new.decided_at is null then
      update public.leaves set decided_at = now() where id = new.id;
    end if;
    if v_student_user is not null then
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, v_student_user, 'leave', 'Leave ' || new.status::text,
              'Your leave (' || to_char(new.from_date, 'DD Mon') || ' → ' || to_char(new.to_date, 'DD Mon') || ') was ' || new.status::text || '.',
              '/student/leave');
    end if;
    -- keep student status in sync while on approved leave
    if new.status = 'approved' and current_date between new.from_date and new.to_date then
      update public.students set status = 'on_leave' where id = new.student_id and status = 'active';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists leaves_after_change on public.leaves;
create trigger leaves_after_change after insert or update on public.leaves
  for each row execute function app.leaves_after_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- FEE PAYMENTS — notify student when a payment is recorded
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.fee_payments_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_student_user uuid;
begin
  if tg_op = 'INSERT' and new.amount_paid <= 0 then return new; end if;
  if tg_op = 'UPDATE' and new.amount_paid <= old.amount_paid then return new; end if;
  select user_id into v_student_user from public.students where id = new.student_id;
  if v_student_user is not null then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (new.hostel_id, v_student_user, 'fee', 'Fee payment recorded',
            format('₹%s received for %s. Status: %s.', new.amount_paid, new.period_month, new.status), '/student');
  end if;
  return new;
end $$;
drop trigger if exists fee_payments_after_change on public.fee_payments;
create trigger fee_payments_after_change after insert or update on public.fee_payments
  for each row execute function app.fee_payments_after_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- HARD RULE §4.2 — scaffold floors → rooms → beds
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.scaffold_hostel(p_hostel_id uuid, p_floors int, p_rooms int, p_beds_per_room int default 3)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_floor int; v_floor_id uuid; v_base int; v_extra int; v_rooms_here int; v_i int; v_room_id uuid; v_room_no text; v_b int;
  v_multiplier int;
begin
  if p_floors < 1 or p_rooms < 1 then
    raise exception 'Floors and rooms must be at least 1.' using errcode = 'P0001';
  end if;
  v_base  := p_rooms / p_floors;
  v_extra := p_rooms % p_floors;
  v_multiplier := case when ceil(p_rooms::numeric / p_floors) > 99 then 1000 else 100 end;

  for v_floor in 1..p_floors loop
    insert into public.floors (hostel_id, floor_number) values (p_hostel_id, v_floor)
    on conflict (hostel_id, floor_number) do update set floor_number = excluded.floor_number
    returning id into v_floor_id;

    v_rooms_here := v_base + case when v_floor <= v_extra then 1 else 0 end;
    for v_i in 1..v_rooms_here loop
      v_room_no := (v_floor * v_multiplier + v_i)::text;
      v_room_id := null;
      insert into public.rooms (hostel_id, floor_id, room_number, capacity)
      values (p_hostel_id, v_floor_id, v_room_no, p_beds_per_room)
      on conflict (hostel_id, room_number) do nothing
      returning id into v_room_id;
      -- beds are created by rooms_capacity_sync trigger; ensure numbering if room pre-existed
      if v_room_id is null then
        select id into v_room_id from public.rooms where hostel_id = p_hostel_id and room_number = v_room_no;
      end if;
      for v_b in 1..p_beds_per_room loop
        insert into public.beds (hostel_id, room_id, bed_number) values (p_hostel_id, v_room_id, v_b)
        on conflict (room_id, bed_number) do nothing;
      end loop;
    end loop;
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- HARD RULE §4.1 — one subscription ↔ one hostel; created atomically
-- Called by the Super Admin wizard AFTER the owner's auth user exists.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.sa_create_hostel_with_subscription(
  p_owner_user_id uuid,
  p_hostel_name   text,
  p_floors        int,
  p_rooms         int,
  p_address       text,
  p_start_date    date,
  p_end_date      date,
  p_amount        numeric,
  p_notes         text default null,
  p_beds_per_room int default 3
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_hostel_id uuid; v_actor uuid := auth.uid();
begin
  if not app.is_super_admin() then
    raise exception 'Only the Super Admin can create hostels.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.users where id = p_owner_user_id and role = 'owner') then
    raise exception 'Owner user not found.' using errcode = 'P0001';
  end if;

  insert into public.hostels (name, owner_user_id, total_floors, total_rooms, beds_per_room_default, address, created_by)
  values (p_hostel_name, p_owner_user_id, p_floors, p_rooms, p_beds_per_room, p_address, v_actor)
  returning id into v_hostel_id;

  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount, created_by, notes)
  values (v_hostel_id, p_owner_user_id, p_start_date, p_end_date, p_amount, v_actor, p_notes);

  perform public.scaffold_hostel(v_hostel_id, p_floors, p_rooms, p_beds_per_room);

  -- bind the owner's session to their first hostel
  update public.users set hostel_id = v_hostel_id where id = p_owner_user_id and hostel_id is null;

  return v_hostel_id;
end $$;

-- Super Admin: change floor / room counts after creation (Hard rule §4.2). Grow-only, atomic;
-- the only sanctioned way to call scaffold_hostel() after creation.
create or replace function public.sa_update_hostel_structure(p_hostel_id uuid, p_floors int, p_rooms int)
returns void
language plpgsql security definer set search_path = public as $$
declare v_h public.hostels%rowtype;
begin
  if not app.is_super_admin() then
    raise exception 'Only the Super Admin can change the hostel structure.' using errcode = '42501';
  end if;
  select * into v_h from public.hostels where id = p_hostel_id for update;
  if not found then raise exception 'Hostel not found.' using errcode = 'P0001'; end if;
  if p_floors < v_h.total_floors then
    raise exception 'Floors can only be increased (currently %).', v_h.total_floors using errcode = 'P0001';
  end if;
  if p_rooms < v_h.total_rooms then
    raise exception 'Rooms can only be increased (currently %).', v_h.total_rooms using errcode = 'P0001';
  end if;
  if p_floors = v_h.total_floors and p_rooms = v_h.total_rooms then
    raise exception 'Nothing to change — the structure is already set to these values.' using errcode = 'P0001';
  end if;
  update public.hostels set total_floors = p_floors, total_rooms = p_rooms where id = p_hostel_id;
  perform public.scaffold_hostel(p_hostel_id, p_floors, p_rooms, v_h.beds_per_room_default);
end $$;

-- Super Admin: extend / renew subscription (adds a new subscription record = history)
create or replace function public.sa_renew_subscription(
  p_hostel_id uuid, p_new_end_date date, p_amount numeric, p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_owner uuid; v_prev_end date;
begin
  if not app.is_super_admin() then
    raise exception 'Only the Super Admin can renew subscriptions.' using errcode = '42501';
  end if;
  select owner_user_id into v_owner from public.hostels where id = p_hostel_id;
  select max(end_date) into v_prev_end from public.subscriptions where hostel_id = p_hostel_id;
  if p_new_end_date <= coalesce(v_prev_end, current_date - 1) then
    raise exception 'New end date must be after the current end date (%).', v_prev_end using errcode = 'P0001';
  end if;
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount, created_by, notes)
  values (p_hostel_id, v_owner, greatest(coalesce(v_prev_end, current_date), current_date), p_new_end_date, p_amount, auth.uid(), p_notes)
  returning id into v_id;
  -- renewal notification to owner
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (p_hostel_id, v_owner, 'subscription', 'Subscription renewed',
          'Your subscription now runs until ' || to_char(p_new_end_date, 'DD Mon YYYY') || '.', '/owner');
  return v_id;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- WARDEN — register student (DB half; auth user is created by the server action first)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.wd_register_student(
  p_user_id           uuid,          -- freshly created auth user id
  p_hostel_id         uuid,
  p_full_name         text,
  p_phone             text,
  p_email             text,
  p_photo_url         text,
  p_guardian_name     text,
  p_guardian_phone    text,
  p_permanent_address text,
  p_id_proof_type     text,
  p_id_proof_url      text,
  p_date_of_joining   date,
  p_bed_id            uuid,
  p_monthly_fee       numeric
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_student_id uuid; v_actor uuid := auth.uid();
begin
  if not (app.has_role_in(p_hostel_id, 'warden') ) then
    raise exception 'Only the warden can register students.' using errcode = '42501';
  end if;
  if not app.hostel_writable(p_hostel_id) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  insert into public.users (id, role, full_name, email, phone, hostel_id, status, must_change_password, created_by)
  values (p_user_id, 'student', p_full_name, p_email, p_phone, p_hostel_id, 'active', true, v_actor);

  insert into public.students (hostel_id, user_id, full_name, phone, email, photo_url, guardian_name, guardian_phone,
                               permanent_address, id_proof_type, id_proof_url, date_of_joining, bed_id, monthly_fee, created_by)
  values (p_hostel_id, p_user_id, p_full_name, p_phone, p_email, p_photo_url, p_guardian_name, p_guardian_phone,
          p_permanent_address, p_id_proof_type, p_id_proof_url, coalesce(p_date_of_joining, current_date), p_bed_id, p_monthly_fee, v_actor)
  returning id into v_student_id;

  return v_student_id;
end $$;

-- Warden: vacate (checkout) a student → frees bed, deactivates login
create or replace function public.wd_vacate_student(p_student_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_user uuid;
begin
  select hostel_id, user_id into v_hostel, v_user from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  update public.students set status = 'vacated' where id = p_student_id;
  if v_user is not null then
    update public.users set status = 'inactive' where id = v_user;
  end if;
end $$;

-- Warden: record / top-up a fee payment for a period (upsert)
-- Warden records / tops up a fee payment. Hardened: no NaN (Postgres numeric NaN compares
-- EQUAL to itself, so the IEEE `x <> x` idiom never fires — test against 'NaN'::numeric), no payments for
-- checked-out students, sane upper bound, no future-dating.
create or replace function public.wd_record_payment(
  p_student_id uuid, p_period_month text, p_amount numeric, p_mode public.payment_mode,
  p_paid_on date default current_date, p_notes text default null
) returns public.fee_payments
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_fee numeric; v_status public.student_status; v_row public.fee_payments;
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
  if p_paid_on > current_date + 1 then
    raise exception 'Payment date cannot be in the future.' using errcode = 'P0001';
  end if;

  insert into public.fee_payments (hostel_id, student_id, period_month, amount_due, amount_paid, paid_on, mode, notes, recorded_by)
  values (v_hostel, p_student_id, p_period_month, v_fee, p_amount, p_paid_on, p_mode, p_notes, auth.uid())
  on conflict (student_id, period_month) do update
    set amount_paid = public.fee_payments.amount_paid + excluded.amount_paid,
        paid_on = excluded.paid_on, mode = excluded.mode,
        notes = coalesce(excluded.notes, public.fee_payments.notes),
        recorded_by = excluded.recorded_by
  returning * into v_row;
  return v_row;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- STUDENT — roommates (names + phones only; Hard rule §4.8)
-- ─────────────────────────────────────────────────────────────────────────────
-- §4.8 — students see roommates' NAME and PHONE only (no photo/storage key, no address).
drop function if exists public.st_my_roommates();
create function public.st_my_roommates()
returns table (student_id uuid, full_name text, phone text, bed_number int)
language sql stable security definer set search_path = public as $$
  select s.id, s.full_name, s.phone, b.bed_number
  from public.students me
  join public.students s on s.room_id = me.room_id and s.id <> me.id and s.status <> 'vacated'
  left join public.beds b on b.id = s.bed_id
  where me.user_id = auth.uid() and me.status <> 'vacated' and me.room_id is not null
  order by b.bed_number
$$;

-- Student / staff: hostel contact card (students cannot read users rows — Hard rule §4.8)
create or replace function public.st_hostel_contacts()
returns table (hostel_name text, address text, rules text, warden_name text, warden_phone text, manager_name text, manager_phone text, owner_name text)
language sql stable security definer set search_path = public as $$
  select h.name, h.address, h.rules,
         (select u.full_name from public.users u where u.hostel_id = h.id and u.role = 'warden'  and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.phone     from public.users u where u.hostel_id = h.id and u.role = 'warden'  and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.full_name from public.users u where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.phone     from public.users u where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.full_name from public.users u where u.id = h.owner_user_id)
  from public.hostels h
  where h.id = coalesce(app.user_hostel_id(), (select hostel_id from public.students where user_id = auth.uid() limit 1))
$$;

-- Owner: update hostel rules text (only field owners may edit on hostels).
-- Subject to the §4.4 read-only gate like every other tenant write.
create or replace function public.ow_update_hostel_rules(p_hostel_id uuid, p_rules text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not app.owns_hostel(p_hostel_id) and not app.is_super_admin() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.is_super_admin() and not app.hostel_writable(p_hostel_id) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  update public.hostels set rules = left(p_rules, 20000) where id = p_hostel_id;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- READ RPCs (SECURITY INVOKER → RLS applies)
-- ─────────────────────────────────────────────────────────────────────────────

-- Fee ledger for a month: every active student with paid/partial/unpaid state
create or replace function public.rpc_fee_ledger(p_hostel_id uuid, p_period_month text)
returns table (
  student_id uuid, full_name text, phone text, photo_url text, room_number text, bed_number int,
  monthly_fee numeric, amount_due numeric, amount_paid numeric, status public.fee_status, paid_on date, mode public.payment_mode
)
language sql stable security invoker set search_path = public as $$
  select s.id, s.full_name, s.phone, s.photo_url, r.room_number, b.bed_number,
         s.monthly_fee,
         coalesce(fp.amount_due, s.monthly_fee) as amount_due,
         coalesce(fp.amount_paid, 0) as amount_paid,
         coalesce(fp.status, 'unpaid'::public.fee_status) as status,
         fp.paid_on, fp.mode
  from public.students s
  left join public.rooms r on r.id = s.room_id
  left join public.beds  b on b.id = s.bed_id
  left join public.fee_payments fp on fp.student_id = s.id and fp.period_month = p_period_month
  where s.hostel_id = p_hostel_id and s.status <> 'vacated'
  order by r.room_number nulls last, s.full_name
$$;

-- Room list with occupancy
create or replace function public.rpc_room_occupancy(p_hostel_id uuid)
returns table (room_id uuid, floor_id uuid, floor_number int, room_number text, capacity int, occupied int)
language sql stable security invoker set search_path = public as $$
  select r.id, f.id, f.floor_number, r.room_number, r.capacity,
         (select count(*)::int from public.beds b where b.room_id = r.id and b.student_id is not null)
  from public.rooms r join public.floors f on f.id = r.floor_id
  where r.hostel_id = p_hostel_id
  order by f.floor_number, r.room_number
$$;

-- Hostel headline stats (dashboards)
create or replace function public.rpc_hostel_stats(p_hostel_id uuid, p_period_month text default to_char(current_date, 'YYYY-MM'))
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
       and (check_in_at at time zone 'Asia/Kolkata')::date = (now() at time zone 'Asia/Kolkata')::date),
    (select count(*)::int from public.tasks where hostel_id = p_hostel_id and status <> 'done' and deleted_at is null),
    coalesce((select sum(amount) from public.revenues where hostel_id = p_hostel_id and date = current_date and deleted_at is null), 0),
    coalesce((select sum(amount) from public.expenses where hostel_id = p_hostel_id and date = current_date and deleted_at is null), 0),
    coalesce((select sum(amount) from public.revenues where hostel_id = p_hostel_id and to_char(date,'YYYY-MM') = p_period_month and deleted_at is null), 0),
    coalesce((select sum(amount) from public.expenses where hostel_id = p_hostel_id and to_char(date,'YYYY-MM') = p_period_month and deleted_at is null), 0),
    app.subscription_days_left(p_hostel_id),
    app.subscription_state(p_hostel_id)
$$;

-- Daily revenue vs expense series (charts)
create or replace function public.rpc_daily_finance(p_hostel_id uuid, p_from date, p_to date)
returns table (day date, revenue numeric, expense numeric)
language sql stable security invoker set search_path = public as $$
  select d::date,
         coalesce((select sum(amount) from public.revenues r where r.hostel_id = p_hostel_id and r.date = d::date and r.deleted_at is null), 0),
         coalesce((select sum(amount) from public.expenses e where e.hostel_id = p_hostel_id and e.date = d::date and e.deleted_at is null), 0)
  from generate_series(p_from, p_to, interval '1 day') d
  order by 1
$$;

-- Super Admin platform stats
create or replace function public.rpc_sa_dashboard()
returns table (
  total_hostels int, total_owners int, total_students int,
  active_subs int, expiring_subs int, expired_subs int,
  monthly_subscription_revenue numeric
)
language sql stable security definer set search_path = public as $$
  select
    (select count(*)::int from public.hostels),
    (select count(*)::int from public.users where role = 'owner' and deleted_at is null),
    (select count(*)::int from public.students where status <> 'vacated'),
    (select count(*)::int from public.hostels h where app.subscription_state(h.id) = 'active'),
    (select count(*)::int from public.hostels h where app.subscription_state(h.id) = 'expiring'),
    (select count(*)::int from public.hostels h where app.subscription_state(h.id) = 'expired'),
    coalesce((select sum(amount) from public.subscriptions where to_char(created_at,'YYYY-MM') = to_char(current_date,'YYYY-MM')), 0)
  where app.is_super_admin()
$$;

-- Hostels onboarded per month (last 12 months) for SA chart
create or replace function public.rpc_sa_onboarding_series()
returns table (month text, hostels int)
language sql stable security definer set search_path = public as $$
  select to_char(m, 'YYYY-MM'),
         (select count(*)::int from public.hostels h where to_char(h.created_at, 'YYYY-MM') = to_char(m, 'YYYY-MM'))
  from generate_series(date_trunc('month', current_date) - interval '11 months', date_trunc('month', current_date), interval '1 month') m
  where app.is_super_admin()
  order by 1
$$;

-- Hostel summary rows for the SA table (owner name, sub end, days left, counts)
create or replace function public.rpc_sa_hostels()
returns table (
  hostel_id uuid, hostel_name text, hostel_status public.hostel_status, address text,
  owner_id uuid, owner_name text, owner_email text, owner_phone text,
  sub_start date, sub_end date, sub_amount numeric, sub_state public.subscription_status, days_left int,
  total_beds int, occupied_beds int, active_students int, open_complaints int, created_at timestamptz
)
language sql stable security definer set search_path = public as $$
  select h.id, h.name, h.status, h.address,
         u.id, u.full_name, u.email, u.phone,
         ls.start_date, ls.end_date, ls.amount, app.subscription_state(h.id), app.subscription_days_left(h.id),
         (select count(*)::int from public.beds b where b.hostel_id = h.id),
         (select count(*)::int from public.beds b where b.hostel_id = h.id and b.student_id is not null),
         (select count(*)::int from public.students s where s.hostel_id = h.id and s.status <> 'vacated'),
         (select count(*)::int from public.complaints c where c.hostel_id = h.id and c.status <> 'resolved'),
         h.created_at
  from public.hostels h
  join public.users u on u.id = h.owner_user_id
  left join lateral (select * from public.subscriptions s where s.hostel_id = h.id order by end_date desc limit 1) ls on true
  where app.is_super_admin()
  order by h.created_at desc
$$;

-- Weekly complaint counts (SA hostel detail chart)
create or replace function public.rpc_complaints_per_week(p_hostel_id uuid, p_weeks int default 8)
returns table (week_start date, complaints int)
language sql stable security invoker set search_path = public as $$
  select w::date,
         (select count(*)::int from public.complaints c where c.hostel_id = p_hostel_id
            and c.created_at >= w and c.created_at < w + interval '7 days')
  from generate_series(date_trunc('week', current_date) - ((p_weeks - 1) || ' weeks')::interval, date_trunc('week', current_date), interval '1 week') w
  order by 1
$$;

-- Unread notification count (bell)
create or replace function public.rpc_unread_count() returns int
language sql stable security invoker set search_path = public as $$
  select count(*)::int from public.notifications where user_id = auth.uid() and read_at is null
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- RATE LIMITING (checklist §19) — durable fixed-window counters usable from any
-- serverless instance. Called ONLY through the service-role client (lib/rate-limit.ts);
-- the table lives in the private `app` schema and the RPC is not executable by users.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists app.rate_limits (
  key           text primary key,
  window_start  timestamptz not null default now(),
  count         int not null default 0
);

create or replace function public.rate_limit(p_key text, p_max int, p_window_seconds int)
returns table (allowed boolean, remaining int, retry_after_seconds int)
language plpgsql security definer set search_path = app, public as $$
declare v_row app.rate_limits%rowtype; v_now timestamptz := now(); v_win interval := make_interval(secs => greatest(p_window_seconds, 1));
begin
  -- opportunistic garbage collection of stale windows
  if random() < 0.005 then
    delete from app.rate_limits where window_start < v_now - interval '1 day';
  end if;
  insert into app.rate_limits (key, window_start, count) values (left(p_key, 200), v_now, 1)
  on conflict (key) do update set
    count        = case when app.rate_limits.window_start < v_now - v_win then 1 else app.rate_limits.count + 1 end,
    window_start = case when app.rate_limits.window_start < v_now - v_win then v_now else app.rate_limits.window_start end
  returning * into v_row;
  allowed := v_row.count <= p_max;
  remaining := greatest(p_max - v_row.count, 0);
  retry_after_seconds := case when allowed then 0
    else greatest(0, ceil(extract(epoch from (v_row.window_start + v_win - v_now)))::int) end;
  return next;
end $$;
revoke all on function public.rate_limit(text, int, int) from public, anon, authenticated;
grant execute on function public.rate_limit(text, int, int) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- AUDIT LOG (checklist §27) — privileged/security-relevant events. Rows are written
-- only through audit_event() (actor = auth.uid(), cannot be spoofed) or the service
-- role (unauthenticated events such as failed logins). Readable by the Super Admin
-- and, for their own hostel, the owner.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.audit_log (
  id             bigserial primary key,
  at             timestamptz not null default now(),
  actor_user_id  uuid,
  actor_role     public.user_role,
  action         text not null,
  target_type    text,
  target_id      text,
  hostel_id      uuid,
  ip             text,
  user_agent     text,
  meta           jsonb not null default '{}'::jsonb
);
create index if not exists audit_log_hostel_idx on public.audit_log (hostel_id, at desc);
create index if not exists audit_log_actor_idx  on public.audit_log (actor_user_id, at desc);
create index if not exists audit_log_action_idx on public.audit_log (action, at desc);
alter table public.audit_log enable row level security;
drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select on public.audit_log for select
  using (app.is_super_admin() or (hostel_id is not null and app.owns_hostel(hostel_id)));
-- no insert/update/delete policies for users: writes go through audit_event() / service role only

-- Audit writes are SERVICE-ROLE ONLY. If `authenticated` could execute this, any signed-in
-- user could call it through PostgREST and inject rows into another tenant's (owner-visible)
-- trail or flood the table. lib/audit.ts calls it with the service role and passes the actor
-- from the session the server already verified, so the actor still cannot be spoofed.
create or replace function public.audit_event(
  p_action text, p_target_type text default null, p_target_id text default null,
  p_hostel_id uuid default null, p_meta jsonb default '{}'::jsonb, p_ip text default null, p_user_agent text default null,
  p_actor_user_id uuid default null, p_actor_role public.user_role default null
) returns void
language plpgsql security definer set search_path = public as $$
declare v_meta jsonb := coalesce(p_meta, '{}'::jsonb); k text;
begin
  -- Defense in depth (§27 "logs do not contain secrets"): lib/audit.ts already strips
  -- credential-ish keys; strip them here too so no future caller can persist one.
  if jsonb_typeof(v_meta) = 'object' then
    for k in select jsonb_object_keys(v_meta) loop
      if k ~* '(pass|secret|token|key|otp|code|authorization|cookie)' then
        v_meta := v_meta - k;
      end if;
    end loop;
  else
    v_meta := '{}'::jsonb;
  end if;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, ip, user_agent, meta)
  values (coalesce(p_actor_user_id, auth.uid()), coalesce(p_actor_role, app.user_role()),
          left(p_action, 80), left(p_target_type, 40), left(p_target_id, 80),
          p_hostel_id, left(p_ip, 64), left(p_user_agent, 300), v_meta);
exception when others then
  null; -- auditing must never break the primary action
end $$;
revoke all on function public.audit_event(text, text, text, uuid, jsonb, text, text, uuid, public.user_role) from public, anon, authenticated;
grant execute on function public.audit_event(text, text, text, uuid, jsonb, text, text, uuid, public.user_role) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- CROSS-TENANT INTEGRITY GUARDS (checklist §4, §14, §25)
--
-- RLS gates the hostel_id COLUMN of the row being written, but nothing checked that the
-- FOREIGN KEYS on that row point at objects in the SAME tenant. Confirmed exploitable
-- before these guards existed:
--   * a warden repointed students.user_id at another hostel's warden account, handing
--     that account read access to this tenant's resident PII, fees and complaints;
--   * a warden inserted a fee_payments / visitors row whose student_id belonged to
--     another hostel's student — the victim saw the debt on their own page;
--   * an owner assigned a task to another hostel's warden, or to a student.
-- ─────────────────────────────────────────────────────────────────────────────

-- Any row that references a student must live in that student's hostel.
create or replace function app.assert_student_in_hostel() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid;
begin
  if new.student_id is null then return new; end if;
  select hostel_id into v_hostel from public.students where id = new.student_id;
  if v_hostel is null then
    raise exception 'Student not found.' using errcode = 'P0001';
  end if;
  if v_hostel is distinct from new.hostel_id then
    raise exception 'That student belongs to a different hostel.' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists fee_payments_student_tenant on public.fee_payments;
create trigger fee_payments_student_tenant before insert or update of student_id, hostel_id
  on public.fee_payments for each row execute function app.assert_student_in_hostel();
drop trigger if exists visitors_student_tenant on public.visitors;
create trigger visitors_student_tenant before insert or update of student_id, hostel_id
  on public.visitors for each row execute function app.assert_student_in_hostel();
drop trigger if exists complaints_student_tenant on public.complaints;
create trigger complaints_student_tenant before insert or update of student_id, hostel_id
  on public.complaints for each row execute function app.assert_student_in_hostel();
drop trigger if exists leaves_student_tenant on public.leaves;
create trigger leaves_student_tenant before insert or update of student_id, hostel_id
  on public.leaves for each row execute function app.assert_student_in_hostel();

-- students.user_id may only point at a student account in the SAME hostel, and may never
-- be repointed after creation (that is an account-takeover primitive).
create or replace function app.students_identity_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role public.user_role; v_hostel uuid;
begin
  if app.is_super_admin() then return new; end if;
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id then
      raise exception 'Not allowed.' using errcode = '42501';
    end if;
    if new.user_id is distinct from old.user_id then
      raise exception 'A student record cannot be re-linked to another account.' using errcode = '42501';
    end if;
    if new.hostel_id is distinct from old.hostel_id then
      raise exception 'You cannot move a student to another hostel.' using errcode = '42501';
    end if;
  end if;
  if new.user_id is not null then
    select role, hostel_id into v_role, v_hostel from public.users where id = new.user_id;
    if v_role is null then
      raise exception 'Linked account not found.' using errcode = 'P0001';
    end if;
    if v_role <> 'student' or v_hostel is distinct from new.hostel_id then
      raise exception 'A student record can only be linked to a student account in the same hostel.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists students_identity_guard on public.students;
create trigger students_identity_guard before insert or update on public.students
  for each row execute function app.students_identity_guard();

-- A task may only be assigned to this hostel's active manager.
create or replace function app.tasks_assignee_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role public.user_role; v_hostel uuid; v_status public.user_status;
begin
  if app.is_super_admin() then return new; end if;
  select role, hostel_id, status into v_role, v_hostel, v_status from public.users where id = new.assigned_to;
  if v_role is null then
    raise exception 'That user does not exist.' using errcode = 'P0001';
  end if;
  if v_role <> 'manager' or v_hostel is distinct from new.hostel_id or v_status <> 'active' then
    raise exception 'Tasks can only be assigned to this hostel active manager.' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists tasks_assignee_guard on public.tasks;
create trigger tasks_assignee_guard before insert or update of assigned_to, hostel_id
  on public.tasks for each row execute function app.tasks_assignee_guard();

-- Length ceilings so a direct PostgREST write cannot store an unbounded blob.
alter table public.complaints    drop constraint if exists complaints_text_len;
alter table public.complaints    add  constraint complaints_text_len
  check (length(title) <= 200 and (description is null or length(description) <= 4000)
         and (resolution_note is null or length(resolution_note) <= 2000));
alter table public.announcements drop constraint if exists announcements_text_len;
alter table public.announcements add  constraint announcements_text_len
  check (length(title) <= 200 and length(body) <= 4000);
alter table public.leaves        drop constraint if exists leaves_reason_len;
alter table public.leaves        add  constraint leaves_reason_len
  check (reason is null or length(reason) <= 2000);
alter table public.tasks         drop constraint if exists tasks_text_len;
alter table public.tasks         add  constraint tasks_text_len
  check (length(title) <= 200 and (description is null or length(description) <= 4000));
alter table public.expenses      drop constraint if exists expenses_note_len;
alter table public.expenses      add  constraint expenses_note_len
  check (note is null or length(note) <= 1000);
alter table public.revenues      drop constraint if exists revenues_note_len;
alter table public.revenues      add  constraint revenues_note_len
  check (note is null or length(note) <= 1000);
alter table public.visitors      drop constraint if exists visitors_text_len;
alter table public.visitors      add  constraint visitors_text_len
  check (length(visitor_name) <= 120 and (relation is null or length(relation) <= 60)
         and (visitor_phone is null or length(visitor_phone) <= 20));

-- ─────────────────────────────────────────────────────────────────────────────
-- STORAGE BUCKETS (private; files served via signed URLs from the server)
-- ─────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('student-docs',     'student-docs',     false, 8388608, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('receipts',         'receipts',         false, 8388608, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('complaint-photos', 'complaint-photos', false, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- GRANTS
-- ─────────────────────────────────────────────────────────────────────────────
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to authenticated, service_role;
grant all on all sequences in schema public to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;
grant execute on all functions in schema app to authenticated, service_role;
alter default privileges in schema public grant all on tables to authenticated, service_role;
alter default privileges in schema public grant execute on functions to authenticated, service_role;

-- Hardening: anon must never call RPCs (Postgres grants EXECUTE to PUBLIC by default);
-- internal helpers are reachable only through SECURITY DEFINER wrappers / the service role.
revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema app from public, anon;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema app revoke execute on functions from public;
revoke execute on function public.scaffold_hostel(uuid, int, int, int) from authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- DETECTION & ALERTING (checklist §27)
--
-- The audit trail recorded what happened but nothing ever LOOKED at it, so a brute-force run
-- or a privilege-probing session produced rows nobody would read until after the fact. This
-- turns the trail into a detector: suspicious PATTERNS raise a row in security_alerts, which
-- the Super Admin (all) and the hostel Owner (own hostel) see at /super-admin/security.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.security_alerts (
  id              bigint generated always as identity primary key,
  at              timestamptz not null default now(),
  severity        text not null check (severity in ('low','medium','high','critical')),
  kind            text not null,
  summary         text not null check (length(summary) <= 500),
  hostel_id       uuid references public.hostels(id) on delete cascade,
  actor_user_id   uuid references public.users(id) on delete set null,
  ip              text,
  details         jsonb not null default '{}'::jsonb,
  acknowledged_at timestamptz,
  acknowledged_by uuid references public.users(id) on delete set null
);
create index if not exists security_alerts_at_idx     on public.security_alerts (at desc);
create index if not exists security_alerts_open_idx   on public.security_alerts (acknowledged_at) where acknowledged_at is null;
create index if not exists security_alerts_hostel_idx on public.security_alerts (hostel_id, at desc);
create index if not exists security_alerts_dedup_idx  on public.security_alerts (kind, actor_user_id, at desc);

-- One alert per (kind, actor) per hour while unacknowledged, so a sustained attack produces
-- one actionable row rather than thousands.
create or replace function app.raise_security_alert(
  p_severity text, p_kind text, p_summary text,
  p_hostel_id uuid default null, p_actor uuid default null,
  p_ip text default null, p_details jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public as $fn$
begin
  if exists (
    select 1 from public.security_alerts
     where kind = p_kind
       and actor_user_id is not distinct from p_actor
       and acknowledged_at is null
       and at > now() - interval '1 hour'
  ) then
    return;
  end if;
  insert into public.security_alerts (severity, kind, summary, hostel_id, actor_user_id, ip, details)
  values (p_severity, p_kind, left(p_summary, 500), p_hostel_id, p_actor, p_ip, coalesce(p_details, '{}'::jsonb));
end $fn$;

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
  elsif new.action in ('sa.owner.password_reset', 'owner.staff.password_reset') then
    perform app.raise_security_alert('medium', 'account.password_reset_by_admin',
      format('An administrator reset another account password (%s)', new.action),
      new.hostel_id, new.actor_user_id, new.ip, jsonb_build_object('target', new.target_id));
  end if;
  return new;
end $fn$;

drop trigger if exists audit_log_detect on public.audit_log;
create trigger audit_log_detect after insert on public.audit_log
  for each row execute function app.detect_suspicious_activity();

-- Acknowledgement is an RPC, not a table UPDATE: security_alerts has no write policy at all,
-- because anyone able to edit or delete an alert could erase evidence of their own activity.
create or replace function public.ack_security_alert(p_alert_id bigint)
returns void
language plpgsql security definer set search_path = public as $fn$
declare v_hostel uuid;
begin
  select hostel_id into v_hostel from public.security_alerts where id = p_alert_id;
  if not found then raise exception 'Alert not found.' using errcode = 'P0001'; end if;
  if not (app.is_super_admin() or (v_hostel is not null and app.owns_hostel(v_hostel))) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  update public.security_alerts
     set acknowledged_at = now(), acknowledged_by = auth.uid()
   where id = p_alert_id and acknowledged_at is null;
end $fn$;

revoke all on function public.ack_security_alert(bigint) from public, anon;
grant execute on function public.ack_security_alert(bigint) to authenticated;
revoke all on function app.raise_security_alert(text,text,text,uuid,uuid,text,jsonb) from public, anon, authenticated;
revoke all on function app.detect_suspicious_activity() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- RETENTION (checklist §27 + DPDP data minimisation)
--
-- audit_log carries IP and user-agent - personal data under the DPDP Act - and grew without
-- bound. Two-stage policy: pseudonymise early, delete late. Dropping IP/UA at 90 days removes
-- the personal data while KEEPING the security event, so the trail stays useful for far longer
-- than the personal data is allowed to be retained.
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists pg_cron with schema pg_catalog;

create or replace function app.apply_retention()
returns table (step text, rows_affected bigint)
language plpgsql security definer set search_path = public as $fn$
declare n bigint;
begin
  update public.audit_log set ip = null, user_agent = null
   where at < now() - interval '90 days' and (ip is not null or user_agent is not null);
  get diagnostics n = row_count;
  step := 'audit_log pseudonymised (>90d)'; rows_affected := n; return next;

  delete from public.audit_log where at < now() - interval '365 days';
  get diagnostics n = row_count;
  step := 'audit_log deleted (>365d)'; rows_affected := n; return next;

  delete from public.security_alerts
   where acknowledged_at is not null and at < now() - interval '365 days';
  get diagnostics n = row_count;
  step := 'security_alerts deleted (ack + >365d)'; rows_affected := n; return next;

  delete from app.rate_limits where window_start < now() - interval '1 day';
  get diagnostics n = row_count;
  step := 'rate_limits swept (>1d)'; rows_affected := n; return next;

  delete from public.notifications
   where read_at is not null and created_at < now() - interval '90 days';
  get diagnostics n = row_count;
  step := 'notifications deleted (read + >90d)'; rows_affected := n; return next;
end $fn$;

revoke all on function app.apply_retention() from public, anon, authenticated;

-- 03:15 UTC daily
select cron.unschedule('hostelpro-retention')
 where exists (select 1 from cron.job where jobname = 'hostelpro-retention');
select cron.schedule('hostelpro-retention', '15 3 * * *', $job$select app.apply_retention()$job$);
