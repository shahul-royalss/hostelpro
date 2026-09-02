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
-- ── "TODAY" IS THE HOSTEL'S TODAY, NEVER THE SERVER'S ────────────────────────
-- This instance runs TimeZone = UTC, so `current_date` is 5h30m behind the building. Measured
-- 2026-09-01 02:18 IST: current_date = 2026-08-31 while the hostel's calendar said 2026-09-01,
-- and an expense the manager had just recorded (dated from the handset clock, correctly) read
-- expenses_today = 0 on their own home screen. Use this function wherever "today" means the day
-- a person at the desk would name; the full argument, and the list of places deliberately left
-- on current_date, are in db/migrations/2026-09-01-hostel-local-today.sql.
--
-- STABLE, not IMMUTABLE: it moves with the clock, so it is legal in a DEFAULT and in a WHERE
-- and must never appear in an index predicate.
create or replace function app.today() returns date
language sql stable set search_path = public as $$
  select (now() at time zone 'Asia/Kolkata')::date
$$;
grant execute on function app.today() to authenticated, service_role;

-- The rest of the app.* helpers live further down, next to the RLS predicates they serve. This
-- one is up here because public.expenses, public.revenues and public.students take a column
-- DEFAULT on it, and a default cannot reference a function that does not exist yet.

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
  -- When GoTrue accepted a confirmation LINK emailed to `email`. NULL means unproved, which is
  -- where every account starts. NOT the same thing as auth.users.email_confirmed_at, which
  -- every account-creation path stamps at creation so the temporary password works (the project
  -- has "Confirm email" ON — mailer_autoconfirm=false — and GoTrue refuses a password grant to
  -- an unconfirmed user). Only the email-verification Edge Function may write this;
  -- app.users_update_guard refuses every other writer and clears it whenever the address
  -- changes. See db/migrations/2026-09-01-email-link-verification.sql.
  email_verified_at    timestamptz,
  -- When `email` last changed. Stamped by the same guard statement that clears the line above,
  -- and read by public.email_link_proof() as the floor under a magic-link claim — otherwise a
  -- click that proved the OLD address could be re-read as a proof of the NEW one.
  email_verification_reset_at timestamptz,
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
  -- ON DELETE SET NULL, so erasing the login (auth.users → public.users) RELEASES this row
  -- instead of being refused by it. Without it a resident's account can never be deleted, and
  -- "erased" would leave GoTrue holding their email address. See app.erase_student().
  user_id           uuid references public.users(id) on delete set null,
  full_name         text not null,
  phone             text not null,
  email             text,
  photo_url         text,
  guardian_name     text,
  guardian_phone    text,
  permanent_address text,
  id_proof_type     text,
  id_proof_url      text,
  date_of_joining   date not null default app.today(),
  room_id           uuid references public.rooms(id),
  bed_id            uuid,                                   -- FK added after beds
  monthly_fee       numeric(10,2) not null default 0 check (monthly_fee >= 0 and monthly_fee <= 10000000),
  status            public.student_status not null default 'active',
  vacated_at        timestamptz,
  -- ── THE DEFERRED ERASURE (checklist §27 + DPDP §12, the owner's own words: "student data
  -- deletion request has to sent while he is leaving hostel and that student data will be
  -- deleted after 1 month"). Raised at check-out by wd_vacate_student(), withdrawn by
  -- wd_cancel_student_erasure() or automatically by re-admission (app.students_erasure_guard),
  -- carried out by app.erase_student() from the nightly retention job.
  --
  -- The DATE is stored rather than derived from `requested_at + 1 month`, because it is the
  -- thing the resident is told and the thing the warden cancels; deriving it would put the
  -- same interval in the Flutter client, the web client and here, to drift apart later.
  erasure_requested_at timestamptz,
  erasure_due_at       timestamptz,
  erasure_requested_by uuid references public.users(id) on delete set null,
  -- Non-null means this row is a TOMBSTONE: identity gone, fee ledger still hanging off the id.
  erased_at            timestamptz,
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
-- A request always has a date on it, or it is not a request.
do $$ begin
  alter table public.students add constraint students_erasure_pair
    check ((erasure_requested_at is null) = (erasure_due_at is null));
exception when duplicate_object then null; end $$;
create index if not exists students_erasure_due_idx
  on public.students (erasure_due_at)
  where erasure_due_at is not null and erased_at is null;
-- Restated for a database created before the erasure shipped: `create table if not exists`
-- does not alter an existing one, and without SET NULL here a resident's login can never be
-- deleted. Idempotent, so re-running this file is safe either way.
alter table public.students drop constraint if exists students_user_id_fkey;
alter table public.students add  constraint students_user_id_fkey
  foreign key (user_id) references public.users(id) on delete set null;

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
  -- app.today(), not current_date: the Dart layer omits this field on purpose and lets the
  -- column default fire (finance_repository.dart), so this default IS the money's date.
  date         date not null default app.today(),
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
  date         date not null default app.today(),
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

-- ── EMAIL VERIFICATION ───────────────────────────────────────────────────────
-- Who is required to prove their address is decided by the ADDRESS, not by the role.
-- Mirrors isStudentLoginEmail() in supabase/functions/_shared/validate.ts and
-- studentLoginDomain in nivora_app/lib/core/auth/auth_controller.dart: a resident registered
-- without an email signs in as <digits>@student.hostelpro.local, a namespace no mail server
-- accepts, so demanding a proof of it would be a permanent lockout rather than a policy.
create or replace function app.email_is_reachable(p_email text) returns boolean
language sql immutable set search_path = public as $$
  select p_email is not null
     and length(btrim(p_email)) > 0
     and lower(btrim(p_email)) not like '%@student.hostelpro.local'
$$;

-- True when the account has a reachable address it has not proved. Defaults to the caller so a
-- policy can be written `app.email_verification_owed()`. Defined for that purpose; deliberately
-- not wired into any policy yet — today the gate is applied in the three account-creation Edge
-- Functions, which is the one action where an unproved address becomes credentials in someone
-- else's inbox.
create or replace function app.email_verification_owed(p_user uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users u
    where u.id = coalesce(p_user, auth.uid())
      and u.email_verified_at is null
      and app.email_is_reachable(u.email)
  )
$$;

grant execute on function app.email_is_reachable(text) to authenticated, service_role;
grant execute on function app.email_verification_owed(uuid) to authenticated, service_role;

-- WHEN THE ACCOUNT HOLDER LAST OPENED A CONFIRMATION LINK WE EMAILED THEM, or NULL.
--
-- Since 2026-09-01 the proof is a link, not a typed code, so nothing of ours is present at the
-- moment it is used: the user clicks in their mail app and GoTrue verifies the token. The proof
-- is therefore READ from the facts GoTrue writes itself.
--
-- WHICH facts was got wrong on the first attempt, and the correction is worth stating here
-- because the shape is not guessable. The first version read auth.mfa_amr_claims and an
-- audit row carrying traits.provider = 'magiclink'. Measured against the owner's real click on
-- 2026-09-02, BOTH missed and the function returned NULL for a proof that existed twice over:
--
--   · auth.mfa_amr_claims gains NOTHING under PKCE, which is the flow the app pins. GoTrue's
--     /auth/v1/verify stamps an auth code and redirects; it creates no session, and an AMR
--     claim is written only when a session is. The row is never inserted, so no string would
--     have fixed it. Deleted.
--   · the audit row GoTrue actually writes for a link login carries NO `traits` key at all.
--     A password grant is the one that carries {"provider":"email"}.
--
-- So: auth.flow_state.auth_code_issued_at (stamped by the verify handler the instant it matched
-- the emailed token, and naming the method outright) and auth.audit_log_entries in its real
-- shape — a login with no provider trait, anchored to a link this project emailed within the
-- preceding hour so that a login of some other kind is never credited.
--
-- The one lower bound is the last address change. Without it a user could verify their own
-- address, repoint users.email at a stranger's, and have the old click re-read as a proof of
-- the new address. There is deliberately NO recovery_sent_at bound: re-sending a link used to
-- raise the floor above an already-earned proof and destroy it, so every retry erased the
-- evidence of the last one. Full argument in
-- db/migrations/2026-09-02-email-link-proof-pkce.sql.
create or replace function public.email_link_proof(p_user uuid) returns timestamptz
language sql stable security definer set search_path = '' as $$
  with floor_at as (
    select coalesce(pu.email_verification_reset_at, '-infinity'::timestamptz) as since
    from public.users pu
    where pu.id = p_user
  )
  select greatest(
    (select max(f.auth_code_issued_at)
       from auth.flow_state f
      where f.user_id = p_user
        and f.authentication_method in ('magiclink', 'otp', 'recovery')
        and f.auth_code_issued_at is not null
        and f.auth_code_issued_at >= (select since from floor_at)),
    (select max(a.created_at)
       from auth.audit_log_entries a
      where a.payload ->> 'actor_id' = p_user::text
        and a.payload ->> 'action' = 'login'
        and coalesce(a.payload -> 'traits' ->> 'provider', 'link') in ('link', 'magiclink', 'otp')
        and a.created_at >= (select since from floor_at)
        and exists (
          select 1 from auth.audit_log_entries r
           where r.payload ->> 'actor_id' = p_user::text
             and r.payload ->> 'action' in ('user_recovery_requested', 'user_confirmation_requested')
             and r.created_at <= a.created_at
             and r.created_at >= a.created_at - interval '1 hour'))
  )
  where exists (select 1 from floor_at);
$$;

-- The email-verification Edge Function is the only caller. An authenticated user must not be
-- able to ask this about anybody — the answer is only meaningful next to a write they are not
-- allowed to make.
revoke all on function public.email_link_proof(uuid) from public, anon, authenticated;
grant execute on function public.email_link_proof(uuid) to service_role;

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
  -- ── EMAIL VERIFICATION IS NOT SELF-SERVICEABLE ─────────────────────────────
  -- users_update admits `id = auth.uid()` and the tail of this function lets the holder edit
  -- full_name, phone, email and must_change_password. Without these two rules,
  -- `update users set email_verified_at = now()` through PostgREST would be a one-line bypass
  -- of the whole feature, and changing the address afterwards would carry a proof earned for
  -- one address onto another.
  --
  -- Changing the address invalidates the proof. This fires for EVERY writer including the
  -- service role, which is what makes scripts/rotate-super-admin.mjs safe without that script
  -- having to remember.
  if new.email is distinct from old.email then
    new.email_verified_at := null;
    -- Stamped in the SAME statement, so the two can never disagree. It is the floor that stops
    -- public.email_link_proof() reading the click that proved the OLD address as a proof of the
    -- new one — see db/migrations/2026-09-01-email-link-verification.sql.
    new.email_verification_reset_at := now();

  -- Otherwise the stamp moves only when the verification endpoint moves it. This sits ABOVE
  -- the super-admin early return on purpose: the service role reaches here only from
  -- email-verification, which has just read GoTrue's own record of the link being consumed,
  -- whereas a human editing a row through PostgREST has read nothing.
  elsif new.email_verified_at is distinct from old.email_verified_at and not app.is_service_role() then
    raise exception 'Email verification cannot be granted by hand — it is earned by opening the link Nivora emails to the address.'
      using errcode = '42501';
  end if;

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
  -- app.today(), not current_date: a payment taken at the desk at 01:00 IST was taken today,
  -- and dating it yesterday puts it in the wrong month for anyone paying on the 1st.
  if new.amount_paid > 0 and new.paid_on is null then
    new.paid_on := app.today();
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
  -- AUTHORIZATION. This is SECURITY DEFINER and writes notifications, subscription statuses and
  -- hostel read-only flags, so it must not be callable by just anyone holding a JWT. The comment
  -- above still says "callable by any authenticated user by design" — that WAS the design and it
  -- is no longer. The guard lived only in an untracked migration file, which meant a fresh
  -- `schema.sql` apply would have recreated this function WIDE OPEN on a new environment.
  --
  -- The coalesce is load-bearing: app.user_role() is NULL for a caller with no active,
  -- non-deleted users row, and `false or NULL` = NULL, which would slip past `if not (...)`
  -- and fail OPEN. Fail closed, as app.mfa_satisfied() does with a missing aal claim.
  if not coalesce(
    app.is_service_role()
    or app.user_role() = any (array['super_admin', 'owner']::public.user_role[]),
    false
  ) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

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

-- Warden: vacate (checkout) a student → frees bed, deactivates login, RAISES THE ERASURE
-- REQUEST. Signature unchanged, so every existing caller keeps working.
create or replace function public.wd_vacate_student(p_student_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_user uuid; v_erased timestamptz; v_actor uuid := auth.uid();
begin
  select hostel_id, user_id, erased_at into v_hostel, v_user, v_erased
    from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  -- ONE UPDATE. app.students_bed_guard fires once, and the check-out and the erasure request
  -- cannot come apart if the connection drops between them. coalesce() stops a second
  -- check-out resetting a clock that is already running.
  update public.students
     set status               = 'vacated',
         erasure_requested_at = case when v_erased is null
                                     then coalesce(erasure_requested_at, now())
                                     else erasure_requested_at end,
         erasure_due_at       = case when v_erased is null
                                     then coalesce(erasure_due_at, now() + interval '1 month')
                                     else erasure_due_at end,
         erasure_requested_by = case when v_erased is null
                                     then coalesce(erasure_requested_by, v_actor)
                                     else erasure_requested_by end
   where id = p_student_id;

  if v_user is not null then
    update public.users set status = 'inactive' where id = v_user;
  end if;
end $$;

-- Warden/owner: withdraw a pending erasure. The returning-resident path.
--
-- NOT gated on app.hostel_writable(). Every other write in this schema stops when a
-- subscription lapses, and that is right for writes that CREATE an obligation — this one
-- REMOVES one. A hostel that cannot pay its bill must still be able to stop a resident's
-- record being destroyed; the alternative is data loss as a billing consequence.
create or replace function public.wd_cancel_student_erasure(p_student_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_requested timestamptz; v_erased timestamptz;
begin
  select hostel_id, erasure_requested_at, erased_at
    into v_hostel, v_requested, v_erased
    from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if v_erased is not null then
    raise exception 'This record has already been erased. It cannot be restored.' using errcode = 'P0001';
  end if;
  if v_requested is null then
    raise exception 'No deletion is scheduled for this resident.' using errcode = 'P0001';
  end if;

  update public.students
     set erasure_requested_at = null, erasure_due_at = null, erasure_requested_by = null
   where id = p_student_id;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), app.user_role(), 'student.erasure_cancelled', 'student',
          p_student_id::text, v_hostel, jsonb_build_object('was_requested_at', v_requested));
end $$;

-- Warden/owner: raise the request by hand — for a resident who left before this shipped, or
-- one whose request was cancelled and who has now really gone. Same one-month deferral.
create or replace function public.wd_request_student_erasure(p_student_id uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_status public.student_status; v_erased timestamptz; v_due timestamptz;
begin
  select hostel_id, status, erased_at into v_hostel, v_status, v_erased
    from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  if v_erased is not null then
    raise exception 'This record has already been erased.' using errcode = 'P0001';
  end if;
  if v_status <> 'vacated' then
    raise exception 'Check this resident out first — a deletion cannot be scheduled for someone still in a bed.'
      using errcode = 'P0001';
  end if;

  update public.students
     set erasure_requested_at = coalesce(erasure_requested_at, now()),
         erasure_due_at       = coalesce(erasure_due_at, now() + interval '1 month'),
         erasure_requested_by = coalesce(erasure_requested_by, auth.uid())
   where id = p_student_id
  returning erasure_due_at into v_due;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), app.user_role(), 'student.erasure_requested', 'student',
          p_student_id::text, v_hostel, jsonb_build_object('due_at', v_due));

  return v_due;
end $$;

revoke execute on function public.wd_cancel_student_erasure(uuid)  from public, anon;
revoke execute on function public.wd_request_student_erasure(uuid) from public, anon;
grant  execute on function public.wd_cancel_student_erasure(uuid)  to authenticated, service_role;
grant  execute on function public.wd_request_student_erasure(uuid) to authenticated, service_role;

-- Warden: record / top-up a fee payment for a period (upsert)
-- Warden records / tops up a fee payment. Hardened: no NaN (Postgres numeric NaN compares
-- EQUAL to itself, so the IEEE `x <> x` idiom never fires — test against 'NaN'::numeric), no payments for
-- checked-out students, sane upper bound, no future-dating.
create or replace function public.wd_record_payment(
  p_student_id uuid, p_period_month text, p_amount numeric, p_mode public.payment_mode,
  -- Defaulted in the body rather than here, so the fallback is the HOSTEL's today. See app.today().
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
  -- One day of slack, against app.today(): the guard exists to refuse a mis-keyed year, not to
  -- police a handset's clock, and a phone an hour fast must not be told its cashier is
  -- time-travelling.
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

-- ─────────────────────────────────────────────────────────────────────────────
-- PAY AT THE WARDEN'S DESK
--
-- Online payment is out of v1: the razorpay-order / razorpay-webhook functions stay deployed
-- but unconfigured, so the money path never worked. Rent is handed over at the desk and a
-- warden records it. That makes two things the schema did not have:
--
--   wd_correct_payment   wd_record_payment ADDS (it is an upsert with `amount_paid + excluded`),
--                        which is right for a top-up and useless for a typo. A warden who keys
--                        7000 instead of 700 currently has no way back — there is no client
--                        path that can lower a figure, and a second entry only makes it worse.
--                        This SETS the month's received total to an exact figure.
--
--   rpc_recent_payments  "Who paid?" — the owner's question. fee_payments carries recorded_by
--                        but no name, and users is not readable to every role that needs the
--                        answer, so the join is done here under a definer and gated to the
--                        people who may see a hostel's money.
-- ─────────────────────────────────────────────────────────────────────────────

-- Warden / owner: SET what a month has actually received. Not a payment — a correction.
--
-- WHY THIS IS NOT wd_record_payment WITH A NEGATIVE AMOUNT. A negative payment is a lie about
-- what happened at the desk, it would have to be exempted from the `amount > 0` rule that keeps
-- the rest of the ledger honest, and it leaves the resident's own history showing a refund that
-- never took place. A correction says what the month's total should have been all along, and
-- says in the audit log what it used to be.
--
-- A ROW MUST ALREADY EXIST. Correcting a month nobody has recorded anything for is not a
-- correction; wd_record_payment is the way a month gets its first figure.
--
-- ZERO IS ALLOWED, and it is the whole point: it undoes a payment recorded against the wrong
-- resident. paid_on and mode go with it — a month that received nothing was not paid on a day
-- by a method.
--
-- A CHECKED-OUT RESIDENT CAN STILL BE CORRECTED, unlike wd_record_payment which refuses them.
-- Refusing here would leave a wrong figure on the ledger of the one person who can no longer
-- walk up to the desk about it.
create or replace function public.wd_correct_payment(
  p_student_id uuid, p_period_month text, p_amount_paid numeric,
  p_mode public.payment_mode default null, p_paid_on date default null, p_notes text default null
) returns public.fee_payments
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_old public.fee_payments; v_row public.fee_payments;
begin
  select hostel_id into v_hostel from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  select * into v_old from public.fee_payments
   where student_id = p_student_id and period_month = p_period_month;
  if v_old.id is null then
    raise exception 'There is nothing recorded for that month to correct.' using errcode = 'P0001';
  end if;

  -- Postgres numeric NaN compares EQUAL to itself, so the IEEE `x <> x` idiom never fires here.
  if p_amount_paid is null or p_amount_paid = 'NaN'::numeric then
    raise exception 'Enter a valid amount.' using errcode = 'P0001';
  end if;
  if p_amount_paid < 0 then
    raise exception 'A corrected total cannot be negative.' using errcode = 'P0001';
  end if;
  if p_amount_paid > 10000000 then
    raise exception 'That amount is too large.' using errcode = 'P0001';
  end if;
  if p_paid_on is not null and p_paid_on > current_date + 1 then
    raise exception 'Payment date cannot be in the future.' using errcode = 'P0001';
  end if;

  update public.fee_payments set
      amount_paid = p_amount_paid,
      -- Zero received is not a payment: it has no date and no method. Above zero, an omitted
      -- date or mode means "leave what is there" — correcting the AMOUNT should not silently
      -- rewrite when the money came in.
      paid_on     = case when p_amount_paid = 0 then null else coalesce(p_paid_on, v_old.paid_on) end,
      mode        = case when p_amount_paid = 0 then null else coalesce(p_mode, v_old.mode) end,
      notes       = coalesce(p_notes, v_old.notes),
      recorded_by = auth.uid()
   where id = v_old.id
  returning * into v_row;

  -- Money moving DOWN on a ledger is the one edit worth being able to reconstruct later.
  -- audit_event swallows its own failures, so this cannot break the correction.
  perform public.audit_event(
    'warden.fee.corrected', 'fee_payment', v_row.id::text, v_hostel,
    jsonb_build_object(
      'student_id', p_student_id,
      'period_month', p_period_month,
      'amount_paid_before', v_old.amount_paid,
      'amount_paid_after', v_row.amount_paid,
      'amount_due', v_row.amount_due
    )
  );

  return v_row;
end $$;

-- Owner / warden: who paid, most recently recorded first.
--
-- THE ANSWER TO "WHO PAID", AND THE ONLY PLACE THE RECORDER HAS A NAME. fee_payments.recorded_by
-- is a uuid; public.users holds the name, and a warden cannot read the owner's users row (an
-- owner's users.hostel_id is not the warden's hostel), so the join has to happen under a definer
-- or half the rows would print a blank where a person belongs.
--
-- ONLY ROWS THAT RECEIVED SOMETHING. A fee_payments row can exist at amount_paid = 0 — a month
-- opened and then corrected back to nothing. That is not a payment and does not belong on a
-- list of payments.
--
-- NOT PAGINATED HERE, PAGINATED BY PostgREST. `.range()` is applied to the function's result
-- set, exactly as rpc_fee_ledger is paged, so the client gets a page without the function
-- growing a limit/offset contract of its own.
--
-- GATED WITH AN EXCEPTION, NOT A PREDICATE. A hostel that has genuinely taken no money yet must
-- read as empty, and a caller who may not see the money must read as refused. A `where` clause
-- would make those the same zero rows.
create or replace function public.rpc_recent_payments(p_hostel_id uuid)
returns table(
  id uuid, student_id uuid, full_name text, room_number text, bed_number int,
  period_month text, amount_due numeric, amount_paid numeric, status public.fee_status,
  paid_on date, mode public.payment_mode, notes text,
  recorded_by uuid, recorded_by_name text, recorded_by_role public.user_role,
  recorded_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not app.has_role_in(p_hostel_id, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  return query
    select fp.id, fp.student_id, s.full_name, r.room_number, b.bed_number,
           fp.period_month, fp.amount_due, fp.amount_paid, fp.status,
           fp.paid_on, fp.mode, fp.notes,
           fp.recorded_by, u.full_name, u.role,
           fp.updated_at
      from public.fee_payments fp
      join public.students s on s.id = fp.student_id
      left join public.rooms r on r.id = s.room_id
      left join public.beds b on b.id = s.bed_id
      left join public.users u on u.id = fp.recorded_by
     where fp.hostel_id = p_hostel_id
       and fp.amount_paid > 0
     -- updated_at is when the desk last touched the row, which is what "recent" means to an
     -- owner. paid_on is the day the money changed hands, and it can be backdated.
     order by fp.updated_at desc, fp.id desc;
end $$;

revoke all on function public.wd_correct_payment(uuid, text, numeric, public.payment_mode, date, text) from public, anon;
grant execute on function public.wd_correct_payment(uuid, text, numeric, public.payment_mode, date, text) to authenticated, service_role;
revoke all on function public.rpc_recent_payments(uuid) from public, anon;
grant execute on function public.rpc_recent_payments(uuid) to authenticated, service_role;

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

-- Owner: retract a notice (soft delete).
--
-- NOT A PLAIN UPDATE, AND IT CANNOT BE ONE. `announcements_select` is `deleted_at is null
-- and (...)`, and PostgreSQL applies a table's SELECT policy to the NEW row of an UPDATE — a
-- row may not be updated out of the updater's own visibility. So setting `deleted_at` through
-- PostgREST is refused with 42501 however permissive announcements_update is; measured against
-- a scratch table with `with check (true)` and it is still refused. `announcements_delete` is
-- service-role only, so a hard delete is not open to the owner either, and before this function
-- existed an owner could post a notice and never take it back. See
-- db/migrations/2026-09-02-announcement-soft-delete.sql for the measurement.
--
-- Idempotent: an id that is gone, or a notice a second device already retracted, is the end
-- state the caller asked for and returns quietly.
create or replace function public.ow_delete_announcement(p_announcement_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_hostel_id  uuid;
  v_deleted_at timestamptz;
begin
  select a.hostel_id, a.deleted_at
    into v_hostel_id, v_deleted_at
    from public.announcements a
   where a.id = p_announcement_id;

  if not found then
    return;
  end if;

  if not app.owns_hostel(v_hostel_id) and not app.is_super_admin() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  if not app.is_super_admin() and not app.hostel_writable(v_hostel_id) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  if v_deleted_at is not null then
    return;
  end if;

  update public.announcements set deleted_at = now() where id = p_announcement_id;
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
    -- ...and so do these two. They read `date = current_date` until 2026-09-01, which is UTC,
    -- so both tiles were empty for the first five and a half hours of every Indian day while
    -- the day's takings sat one row away. See db/migrations/2026-09-01-hostel-local-today.sql.
    coalesce((select sum(amount) from public.revenues where hostel_id = p_hostel_id and date = app.today() and deleted_at is null), 0),
    coalesce((select sum(amount) from public.expenses where hostel_id = p_hostel_id and date = app.today() and deleted_at is null), 0),
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

-- THE SIGNED-OUT DOOR TO THE SAME TABLE — the forgot-password send, and nothing else.
--
-- public.rate_limit() above is service_role only, so a locked-out person cannot spend it, and
-- the forgot-password form is by definition used with no session. This is the narrow
-- replacement: two fixed windows, no argument that can become an arbitrary key, and it reads NO
-- user table — so its refusal varies with request VOLUME and never with whether an account
-- exists. The address is hashed here rather than on the phone, so app.rate_limits never holds
-- one in plain text and the mobile client needs no crypto dependency.
--
-- The global bucket is spent BEFORE the per-identifier row is inserted, which is what bounds
-- how many new rows an anonymous caller can create. app.apply_retention() already deletes
-- app.rate_limits rows older than a day and needs no change for these keys.
--
-- It is not a security boundary and does not pretend to be one: /auth/v1/recover is public and
-- the anon key ships inside the APK, so the mail is actually bounded by GoTrue's
-- SMTP_MAX_FREQUENCY and GOTRUE_RATE_LIMIT_EMAIL_SENT. This constrains OUR app.
-- See db/migrations/2026-09-02-password-reset-gate.sql.
create or replace function public.password_reset_gate(p_identifier text)
returns table (allowed boolean, retry_after_seconds int)
language plpgsql security definer set search_path = app, public as $$
declare
  v_now  timestamptz := now();
  v_id   text := lower(btrim(coalesce(p_identifier, '')));
  v_row  app.rate_limits%rowtype;
  c_id_max     constant int      := 3;
  c_id_window  constant interval := interval '1 hour';
  c_all_max    constant int      := 200;
  c_all_window constant interval := interval '1 hour';
begin
  insert into app.rate_limits (key, window_start, count) values ('pwreset:all', v_now, 1)
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
    return next; return;
  end if;

  insert into app.rate_limits (key, window_start, count)
  values ('pwreset:id:' || encode(sha256(convert_to(v_id, 'UTF8')), 'hex'), v_now, 1)
  on conflict (key) do update set
    count = case when app.rate_limits.window_start < v_now - c_id_window
                 then 1 else app.rate_limits.count + 1 end,
    window_start = case when app.rate_limits.window_start < v_now - c_id_window
                        then v_now else app.rate_limits.window_start end
  returning * into v_row;

  allowed := v_row.count <= c_id_max;
  retry_after_seconds := case when allowed then 0
    else greatest(1, ceil(extract(epoch from (v_row.window_start + c_id_window - v_now)))::int)
  end;
  return next;
end $$;
revoke all on function public.password_reset_gate(text) from public;
grant execute on function public.password_reset_gate(text) to anon, authenticated;

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
    -- NULL is a RELEASE, anything else is a takeover. Only the first is allowed: erasing a
    -- resident's login cascades public.users away, and the FK above then nulls this column.
    -- Refusing that would make the account impossible to delete.
    if new.user_id is distinct from old.user_id and new.user_id is not null then
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

-- ─────────────────────────────────────────────────────────────────────────────
-- COMING BACK IS A CANCELLATION
--
-- The scenario the deferred erasure is built around: a resident checks out in March and is
-- back in a bed in April. Re-admitting them moves students.status off 'vacated' — and if the
-- pending request survived that, the retention job would erase somebody asleep in the
-- building. So reactivation withdraws the request, without anybody having to remember.
--
-- The reverse is closed too: an erased row is a tombstone the fee ledger hangs on, not a
-- resident record with the name rubbed off. It cannot be brought back into service.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.students_erasure_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.erased_at is not null and new.status <> 'vacated' then
    raise exception 'This record was erased at the resident''s request. Register them as a new resident instead.'
      using errcode = 'P0001';
  end if;

  if old.status = 'vacated' and new.status <> 'vacated'
     and new.erasure_requested_at is not null and new.erased_at is null then
    new.erasure_requested_at := null;
    new.erasure_due_at       := null;
    new.erasure_requested_by := null;
  end if;

  return new;
end $$;

drop trigger if exists students_erasure_guard on public.students;
create trigger students_erasure_guard before update on public.students
  for each row execute function app.students_erasure_guard();

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
--
-- THAT TWO-STAGE RULE IS THE WHOLE POLICY'S SHAPE, and everything added since follows it:
-- keep the EVENT, drop the PERSON. It is why a departed resident is anonymised rather than
-- deleted (their rent ledger is the hostel's record, not theirs to erase), and why an erased
-- account's audit rows keep their action and lose their actor.
--
-- The owner's three requirements, in their own words:
--   (a) "that student complaints and notices data has to deleted after 2 months"
--   (b) "student data deletion request has to sent while he is leaving hostel and that
--        student data will be deleted after 1 month"
--   (c) "the fee history of student never has to be deleted"
-- (b) is a DEFERRED, CANCELLABLE erasure — see public.students.erasure_due_at and
-- app.students_erasure_guard. Full derivation in
-- db/migrations/2026-09-02-retention-and-erasure.sql.
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists pg_cron with schema pg_catalog;

-- ─────────────────────────────────────────────────────────────────────────────
-- FILES DO NOT DISAPPEAR WHEN A ROW DOES, AND THIS DATABASE CANNOT DELETE THEM
--
-- The three private buckets hold personal data, and `*_url` columns hold a KEY into them
-- (`<hostelId>/<folder>/<uuid>.<ext>`), not a URL. Dropping the row that held the key does not
-- touch the object; it makes it unfindable by us and still perfectly readable by anyone who
-- can enumerate the bucket. A "deletion" that leaves the ID-proof scan behind is not one.
--
-- And SQL cannot fix it. Supabase installs a guard for exactly this:
--
--     storage.protect_delete()  BEFORE DELETE ON storage.objects  (FOR EACH STATEMENT)
--     → "Direct deletion from storage tables is not allowed. Use the Storage API instead."
--       HINT: "This prevents accidental data loss from orphaned objects."
--
-- Deleting the metadata row would leave the bytes in the S3 backend forever, so Supabase
-- refuses, and it is right to. That leaves one honest shape: the database records the
-- OBLIGATION, and a process holding the service role discharges it through the Storage API.
--
-- Hence this table — rows here have to OUTLIVE the rows they came from, which is exactly why
-- it cannot be a column. app.apply_retention() reports the pending depth as its last step, so
-- a queue nobody drains shows up as a number that climbs every night instead of as silence.
--
-- NOT DRAINED FROM HERE, DELIBERATELY. Draining needs the service role, and the only way to
-- hold one inside Postgres is to keep the key in the database and fire pg_net at the Storage
-- API. A permanently readable service-role credential — a key to every bucket and every row,
-- sitting where any SECURITY DEFINER function can read it — is a worse privacy problem than
-- the one it would solve.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists app.storage_erasures (
  id           bigint generated always as identity primary key,
  bucket       text        not null,
  object_path  text        not null,
  -- No FK. The hostel may itself be gone by the time this is drained, and ON DELETE CASCADE
  -- here would delete the record of an obligation as a side effect of the obligation's
  -- subject disappearing — the exact failure this table exists to prevent.
  hostel_id    uuid,
  reason       text        not null,
  enqueued_at  timestamptz not null default now(),
  purged_at    timestamptz,
  attempts     int         not null default 0,
  last_error   text,
  unique (bucket, object_path)
);
create index if not exists storage_erasures_pending_idx
  on app.storage_erasures (enqueued_at) where purged_at is null;
revoke all on app.storage_erasures from public, anon, authenticated;

-- Queue one object for destruction. True when a NEW obligation was recorded.
-- Refuses anything that is not a real storage key: `*_url` columns are writable by staff
-- through PostgREST, so their contents may be an absolute https:// URL or junk, and queueing
-- that would burn the drain's retries on an object that does not exist. Same shape
-- lib/storage.ts and supabase/functions/_shared/storage.ts accept.
create or replace function app.enqueue_storage_erasure(
  p_bucket text, p_path text, p_hostel uuid, p_reason text
) returns boolean
language plpgsql security definer set search_path = public as $fn$
begin
  if p_path is null
     or p_path !~ '^[0-9a-f-]{36}/[a-z-]{1,32}/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$' then
    return false;
  end if;
  insert into app.storage_erasures (bucket, object_path, hostel_id, reason)
  values (p_bucket, p_path, p_hostel, p_reason)
  on conflict (bucket, object_path) do nothing;
  return found;
end $fn$;

revoke all on function app.enqueue_storage_erasure(text, text, uuid, text)
  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- ERASING ONE DEPARTED RESIDENT  (the owner's (b), carried out one month late)
--
-- WHY THIS ANONYMISES AND NEVER DELETES. The schema settles it:
--
--     fee_payments.student_id → students(id) ON DELETE CASCADE
--
-- so `delete from students` IS `delete from fee_payments`. There is no version of "delete the
-- student row" that keeps the money, and (c) says the money stays. The row therefore survives
-- as an id, a monthly_fee and a joining date — a hook the ledger hangs on — with every
-- identifying column emptied and `erased_at` stamped so the tombstone describes itself. A
-- money record with no name on it is still a money record; a missing one is a hole in the
-- books and, for the PG owner, possibly a tax problem.
--
-- WHAT GOES: full_name, phone, email, guardian_name, guardian_phone, permanent_address,
-- id_proof_type, id_proof_url, photo_url; the photo and ID-proof OBJECTS in student-docs and
-- any complaint photos in complaint-photos (queued, see above); their complaints and the
-- complaint_events under them; their leaves; their visitors; every notification addressed to
-- them; and the login itself — auth.users, which is where the address, the password hash, the
-- MFA factors and the session history live. Leaving GoTrue holding the email while calling the
-- resident erased would be the same lie as leaving the file in the bucket.
--
-- WHAT STAYS: fee_payments in full, the tenancy's shape (hostel, bed dates, monthly_fee), and
-- the audit trail's ROWS with their actor nulled.
--
-- Idempotent: erased_at short-circuits it, so a second run the same night is a no-op.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.erase_student(p_student_id uuid) returns boolean
language plpgsql security definer set search_path = public as $fn$
declare
  s        public.students%rowtype;
  v_user   uuid;
  v_note   text := null;
begin
  select * into s from public.students where id = p_student_id for update;
  if not found or s.erased_at is not null then
    return false;
  end if;
  -- Only a departed resident is erasable. app.students_erasure_guard withdraws the request the
  -- moment somebody is re-admitted, so reaching here with an active resident means an
  -- assumption broke; refuse rather than empty a living record.
  if s.status <> 'vacated' then
    return false;
  end if;

  v_user := s.user_id;

  -- FILES FIRST, WHILE THE KEYS ARE STILL READABLE.
  perform app.enqueue_storage_erasure('student-docs', s.photo_url,    s.hostel_id, 'erasure.student_photo');
  perform app.enqueue_storage_erasure('student-docs', s.id_proof_url, s.hostel_id, 'erasure.student_id_proof');
  perform app.enqueue_storage_erasure('complaint-photos', c.photo_url, c.hostel_id, 'erasure.complaint_photo')
    from public.complaints c
   where c.student_id = p_student_id and c.photo_url is not null;

  -- THEIR PRIVATE LIFE IN THIS BUILDING. "The food in room 3 made me ill" is health data
  -- about a named person; where they went on leave and who came to visit are no different.
  delete from public.complaints where student_id = p_student_id;   -- complaint_events cascade
  delete from public.leaves     where student_id = p_student_id;
  delete from public.visitors   where student_id = p_student_id;

  -- THE ROW: EMPTIED, NOT DELETED. phone is NOT NULL and unique among non-vacated residents,
  -- so the placeholder is keyed on the row's own id and cannot collide.
  update public.students set
      full_name         = 'Erased resident',
      phone             = 'erased-' || replace(p_student_id::text, '-', ''),
      email             = null,
      photo_url         = null,
      guardian_name     = null,
      guardian_phone    = null,
      permanent_address = null,
      id_proof_type     = null,
      id_proof_url      = null,
      erased_at         = now()
    where id = p_student_id;

  -- THE LOGIN.
  if v_user is not null then
    -- Release the NO ACTION references a resident's account can legitimately hold, so the
    -- delete below is not refused by a row that carries no personal data anyway.
    update public.complaint_events set actor_user_id = null where actor_user_id = v_user;
    if to_regclass('public.payment_intents') is not null then
      execute 'update public.payment_intents set created_by = null where created_by = $1' using v_user;
    end if;

    begin
      -- Cascades: public.users → notifications, and students.user_id is released by that
      -- column's ON DELETE SET NULL. GoTrue's identities / sessions / refresh_tokens /
      -- mfa_factors all cascade off auth.users, which is why this one statement is the whole
      -- account.
      delete from auth.users where id = v_user;
    exception when foreign_key_violation then
      -- Do not fail the night's run, and do not start nulling columns blind.
      -- app.users_update_guard refuses every UPDATE to public.users from a context with no JWT
      -- (auth.uid() is null in pg_cron), so this job cannot anonymise the account either. The
      -- only honest move is to say so, loudly, where a human looks. The resident's own data
      -- above is already gone.
      v_note := 'account retained: still referenced by another record';
      perform app.raise_security_alert(
        'medium', 'privacy.erasure.account_retained',
        'A resident was erased but their login could not be deleted — it is still referenced elsewhere.',
        s.hostel_id, null::uuid, null::text,
        jsonb_build_object('student_id', p_student_id, 'user_id', v_user));
    end;
  end if;

  -- THE TRAIL: KEEP THE EVENT, DROP THE PERSON. audit_log has no FK to users, so the uuid
  -- would otherwise outlive the account it names.
  if v_user is not null then
    update public.audit_log set actor_user_id = null where actor_user_id = v_user;
  end if;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (null, null, 'student.erased', 'student', p_student_id::text, s.hostel_id,
          jsonb_build_object(
            'requested_at', s.erasure_requested_at,
            'due_at',       s.erasure_due_at,
            'requested_by', s.erasure_requested_by,
            'note',         v_note));

  return true;
end $fn$;

revoke all on function app.erase_student(uuid) from public, anon, authenticated;
revoke all on function app.students_erasure_guard() from public, anon, authenticated;

-- ╔═══════════════════════════════════════════════════════════════════════════════════════╗
-- ║  public.fee_payments IS NOT IN THIS FUNCTION AND MUST NEVER BE.                        ║
-- ║  "the fee history of student never has to be deleted" — the owner, 2026-09.            ║
-- ║  It is the book the PG is assessed on. A row missing from it is not tidiness, it is an ║
-- ║  unexplainable gap in front of a tax officer. If a future policy seems to require      ║
-- ║  touching it, that policy is wrong; anonymise the STUDENT (app.erase_student) instead  ║
-- ║  — the ledger keeps its id and loses its name, which is what erasure actually asks for.║
-- ╚═══════════════════════════════════════════════════════════════════════════════════════╝
--
-- COMPLAINTS AGE FROM created_at, RESOLVED OR NOT. Ageing them from resolved_at would let a
-- hostel defeat the policy by never pressing "Resolved" — and the rows a resident would most
-- want gone are exactly the ones nobody closed.
create or replace function app.apply_retention()
returns table (step text, rows_affected bigint)
language plpgsql security definer set search_path = public as $fn$
declare n bigint; v_student uuid;
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

  -- ── (a) COMPLAINTS AND NOTICES, 2 MONTHS ────────────────────────────────────────────────
  -- Photos are queued BEFORE their complaints go, or the key is unrecoverable.
  select count(*) into n from (
    select app.enqueue_storage_erasure('complaint-photos', c.photo_url, c.hostel_id,
                                       'retention.complaint_photo') as queued
      from public.complaints c
     where c.created_at < now() - interval '2 months' and c.photo_url is not null
  ) q where q.queued;
  step := 'complaint photos queued for erasure (>2mo)'; rows_affected := n; return next;

  -- Explicit, though complaint_events would cascade, so the count is reportable rather than
  -- invisible inside somebody else's DELETE.
  delete from public.complaint_events e
   using public.complaints c
   where e.complaint_id = c.id and c.created_at < now() - interval '2 months';
  get diagnostics n = row_count;
  step := 'complaint_events deleted (>2mo)'; rows_affected := n; return next;

  delete from public.complaints where created_at < now() - interval '2 months';
  get diagnostics n = row_count;
  step := 'complaints deleted (>2mo)'; rows_affected := n; return next;

  -- "notices" is what the owner calls announcements. Soft-deleted ones go too: deleted_at was
  -- a retraction from the feed, not an erasure.
  delete from public.announcements where created_at < now() - interval '2 months';
  get diagnostics n = row_count;
  step := 'announcements deleted (>2mo)'; rows_affected := n; return next;

  -- ── (b) DEFERRED ERASURES THAT HAVE COME DUE ────────────────────────────────────────────
  n := 0;
  for v_student in
    select id from public.students
     where erasure_due_at is not null and erasure_due_at <= now()
       and erased_at is null and status = 'vacated'
     order by erasure_due_at
     limit 500
  loop
    if app.erase_student(v_student) then n := n + 1; end if;
  end loop;
  step := 'residents erased (requested + 1mo)'; rows_affected := n; return next;

  -- ── THE GAUGE ───────────────────────────────────────────────────────────────────────────
  -- Not a delete: Postgres cannot destroy a storage object (see app.storage_erasures above).
  -- This is the depth of the queue a service-role drain has to work through, and a number
  -- that climbs every night is the alarm that nothing is draining it.
  select count(*) into n from app.storage_erasures where purged_at is null;
  step := 'storage objects awaiting purge (queue depth)'; rows_affected := n; return next;
end $fn$;

revoke all on function app.apply_retention() from public, anon, authenticated;

-- 03:15 UTC daily
select cron.unschedule('hostelpro-retention')
 where exists (select 1 from cron.job where jobname = 'hostelpro-retention');
select cron.schedule('hostelpro-retention', '15 3 * * *', $job$select app.apply_retention()$job$);

-- ─────────────────────────────────────────────────────────────────────────────
-- KEEP THE VERCEL FUNCTION WARM
--
-- Vercel's Hobby plan has no provisioned concurrency, so a function idle for a few minutes pays
-- a cold start. Measured on production: /api/health — which touches no database and renders no
-- page — ranged 0.47s warm to 1.29s cold, and a real page hit 3.6s on an unlucky invocation.
-- The application code is not the cause; it adds only ~0.1s over an empty endpoint.
--
-- pg_cron is already here for retention and pg_net can make an outbound request, so the database
-- keeps the function warm at no cost. /api/health is the cheapest route in the app (no auth, no
-- query) and is already in middleware's PUBLIC_PATHS.
--
-- ~10,800 invocations/month, well inside the Hobby allowance. To stop it:
--   select cron.unschedule('hostelpro-keepwarm');
-- Change the URL here if the deployment ever moves to a custom domain.
create extension if not exists pg_net with schema extensions;

select cron.unschedule('hostelpro-keepwarm')
 where exists (select 1 from cron.job where jobname = 'hostelpro-keepwarm');

select cron.schedule(
  'hostelpro-keepwarm',
  '*/4 * * * *',
  $job$
    select net.http_get(
      url     := 'https://hostelpro-three.vercel.app/api/health',
      headers := '{"User-Agent": "hostelpro-keepwarm/pg_cron"}'::jsonb,
      timeout_milliseconds := 8000
    );
  $job$
);
