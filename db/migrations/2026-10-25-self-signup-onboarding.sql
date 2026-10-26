-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 2026-10-25 — SELF SIGN-UP, OWNER ONBOARDING, JOIN REQUESTS, PROFILE PHOTOS, ID DOCUMENTS,
--              PLATFORM PLANS AND PLAN PAYMENTS, DEMO REQUESTS, STAFF DELETION
-- ═══════════════════════════════════════════════════════════════════════════════════════════
--
-- The database half of docs/self-signup-onboarding-spec.md (Flows 2–9). The app contract is
-- docs/self-signup-api.md; the Edge Functions that call the svc_* routines are mobile-auth,
-- owner-staff-account, subscription-order and razorpay-webhook.
--
-- ── WHAT THIS FILE GUARANTEES, WHATEVER THE APP OR AN EDGE FUNCTION DOES ────────────────────
--
-- 1. Self sign-up creates owners and tenants only. public.users.signup_source records how an
--    account was born ('admin' for every account that exists today). users_self_signup_guard
--    refuses a self-created row with any other role, refuses turning a self-created account into
--    staff later (even for the service role), refuses any change to signup_source, and refuses a
--    self-created row that did not come through svc_create_self_signup_profile, the one
--    service-role-only door.
-- 2. users.hostel_id is never client-writable. Three new transaction-local paths in
--    app.users_update_guard, each proved against the database, not against the flag alone:
--      (B) ow_decide_join_request links a tenant to the PG whose pending request it accepted
--          in this same transaction;
--      (C) wd_vacate_student unlinks a self-signed-up tenant whose roster row it just vacated;
--      (D) ow_create_first_hostel binds an owner to the PG they just created.
--    The owner-vacates-a-resident-with-a-login path also stops failing: an owner now counts as
--    managing a resident account in their own PG (it raised "You cannot change this account's
--    status" before, measured on live 2026-10-24).
-- 3. A trial is a plan. subscriptions.kind ('manual' | 'trial' | 'paid') says where a row came
--    from; status stays the date-driven enum, so every existing reader (app.hostel_writable,
--    app.subscription_state, the cron, the Super Admin screens, every installed app) treats a
--    trial exactly as an active plan without being touched. Why not an enum value 'trial':
--    app.subscription_status_compute recomputes status from the dates on every write, so a
--    'trial' status would be overwritten on insert, and ALTER TYPE ... ADD VALUE cannot be used
--    inside the transaction that adds it, so it could never be tested in a rolled-back run.
-- 4. Amounts come from public.platform_plans and nowhere else. A plan payment activates only
--    through svc_activate_subscription_payment, service role only, idempotent on the Razorpay
--    payment id, and it refuses an amount that is not the order's.
-- 5. Files: avatars and identity documents live in two PRIVATE buckets. A user uploads only
--    under their own id; reads go through app.can_view_user_media (self, Super Admin, the PG's
--    owner, the PG's warden, a manager for staff photos only, and the owner/wardens of a PG the
--    person has a pending request with). Every way a file reference disappears (photo replaced,
--    document deleted, account deleted) queues the object through app.enqueue_storage_erasure,
--    so the nightly drain removes it. Paths are <uid>/avatar/<uuid>.jpg and
--    <uid>/document/<uuid>.<ext>, the shape enqueue_storage_erasure already accepts.
-- 6. Deleting a manager or warden (svc_delete_staff_account) tombstones the profile, so every
--    history row keeps its foreign key, and soft-deletes the GoTrue user the way GoTrue's own
--    soft delete does: the address and phone are released, identities, factors, sessions and
--    one-time tokens are gone, the row is banned. The old login then finds no account.
--
-- ── REDEFINED LIVE ROUTINES (bodies copied from pg_get_functiondef on 2026-10-24) ───────────
--
--   app.users_update_guard()        12a976f46a4987c3cf51956192eb02f4   arms B, C, D; owner manages residents
--   app.enforce_role_limits()       fb691858ad1921fc9598444933696751   a self-signed-up tenant may have no PG
--   app.email_is_reachable(text)    a9abf379e71a56a3c3ed313d2dba9cb4   synthetic sign-up addresses are unreachable
--   public.wd_vacate_student(uuid)  af5dd66ac3499ecf8c1a533374358141   self-signed-up tenant leaves with the account
--   app.apply_retention()           9a76513bec102b54b9a85e1bcd57ab3f   join/demo request retention, orphan uploads
--
-- app.guard_external_identity() (the auth.identities trigger) is NOT changed. Facebook and
-- Truecaller never write an auth.identities row: mobile-auth mints their sessions with a magic
-- link on the account's own email identity. Their (provider, subject) pairs live in
-- public.external_identities, whose own guard (app.guard_external_identity_link) admits owner
-- and tenant accounts only.
--
-- Undo: 2026-10-25-self-signup-onboarding.down.sql. Tests: 2026-10-25-self-signup-onboarding.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;
set local lock_timeout = '10s';

do $guard$
declare
  v_expected constant jsonb := jsonb_build_object(
    'app.users_update_guard()',       '12a976f46a4987c3cf51956192eb02f4',
    'app.enforce_role_limits()',      'fb691858ad1921fc9598444933696751',
    'app.email_is_reachable(text)',   'a9abf379e71a56a3c3ed313d2dba9cb4',
    'public.wd_vacate_student(uuid)', 'af5dd66ac3499ecf8c1a533374358141',
    'app.apply_retention()',          '9a76513bec102b54b9a85e1bcd57ab3f');
  k     text;
  v_md5 text;
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  for k in select jsonb_object_keys(v_expected) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = k::regprocedure;
    if v_md5 is distinct from v_expected ->> k then
      raise exception '% is not the body measured on 2026-10-24 (md5 %); nothing changed', k, v_md5;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'users' and column_name = 'signup_source') then
    raise exception 'public.users.signup_source already exists: this migration has already run';
  end if;
  if to_regclass('public.hostel_join_requests') is not null or to_regclass('public.platform_plans') is not null then
    raise exception 'the self sign-up tables already exist: this migration has already run';
  end if;
  if exists (select 1 from storage.buckets where id in ('avatars', 'identity-documents')) then
    raise exception 'a bucket named avatars or identity-documents already exists; look at it before this runs';
  end if;
  if exists (select 1 from pg_index i where pg_get_indexdef(i.indexrelid) ilike '%email_is_reachable%') then
    raise exception 'an index depends on app.email_is_reachable; redefining an IMMUTABLE function under it is unsafe';
  end if;
end
$guard$;

-- ─── 1. Small helpers ─────────────────────────────────────────────────────────────────────
create or replace function app.clean_line(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(regexp_replace(regexp_replace(coalesce(p_value, ''), '[[:cntrl:]]', ' ', 'g'), '\s+', ' ', 'g')), '');
$$;
comment on function app.clean_line(text) is
  'One line of user text: control characters and runs of whitespace become one space, trimmed, '''' becomes NULL.';

create or replace function app.normalize_phone(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
           when d ~ '^91[0-9]{10}$' then substr(d, 3)
           when d ~ '^0[0-9]{10}$'  then substr(d, 2)
           else d
         end
    from (select regexp_replace(coalesce(p_value, ''), '[^0-9]', '', 'g') as d) x;
$$;
comment on function app.normalize_phone(text) is
  'Digits only, +91 / 91 / leading 0 stripped. Same rule as normalizePhone() in supabase/functions/_shared/validate.ts.';

create or replace function app.storage_path_owner(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case when split_part(coalesce(p_name, ''), '/', 1)
                   ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_name, '/', 1)::uuid end;
$$;
comment on function app.storage_path_owner(text) is
  'The user id a storage key in avatars / identity-documents belongs to: its first path segment.';

-- ─── 2. public.users: how the account was born, the photo, the tenant's details ───────────
alter table public.users
  add column signup_source text not null default 'admin'
    constraint users_signup_source_check
      check (signup_source in ('admin', 'self_google', 'self_facebook', 'self_truecaller')),
  add column avatar_path text
    constraint users_avatar_path_shape
      check (avatar_path is null
             or avatar_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/avatar/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'),
  add column gender text
    constraint users_gender_check check (gender is null or gender in ('male', 'female', 'other')),
  add column date_of_birth date
    constraint users_date_of_birth_check
      check (date_of_birth is null or date_of_birth between date '1900-01-01' and date '2099-12-31'),
  add column emergency_contact_name text
    constraint users_emergency_contact_name_check
      check (emergency_contact_name is null or char_length(emergency_contact_name) between 2 and 80),
  add column emergency_contact_phone text
    constraint users_emergency_contact_phone_check
      check (emergency_contact_phone is null or emergency_contact_phone ~ '^[6-9][0-9]{9}$');

alter table public.users
  add constraint users_avatar_path_owner
    check (avatar_path is null or split_part(avatar_path, '/', 1) = id::text);

create index users_avatar_path_idx on public.users (avatar_path) where avatar_path is not null;
create index users_self_signup_idx on public.users (signup_source, created_at) where signup_source <> 'admin';

comment on column public.users.signup_source is
  'How the account was created: admin (Super Admin, owner or warden) or self_<provider> through mobile-auth. Never changes. Self-created accounts are owner or student only (users_self_signup_guard).';
comment on column public.users.avatar_path is
  'Key in the private avatars bucket, <uid>/avatar/<uuid>.jpg. Written only by me_set_avatar (or the service role).';

create or replace function app.users_self_signup_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'INSERT' then
    if new.signup_source <> 'admin' then
      if new.role not in ('owner', 'student') then
        raise exception 'Only owner and tenant accounts can be created by sign-up.' using errcode = '22023';
      end if;
      if coalesce(current_setting('app.self_signup_profile', true), '') <> new.id::text then
        raise exception 'Sign-up accounts are created by the sign-up service only.' using errcode = '42501';
      end if;
    end if;
    if new.avatar_path is not null then
      raise exception 'Add a profile photo after the account exists.' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.signup_source is distinct from old.signup_source then
    raise exception 'The sign-up source of an account cannot be changed.' using errcode = '42501';
  end if;
  if new.signup_source <> 'admin' and new.role not in ('owner', 'student') then
    raise exception 'Only owner and tenant accounts can be created by sign-up.' using errcode = '22023';
  end if;
  if new.avatar_path is distinct from old.avatar_path
     and not app.is_service_role()
     and coalesce(current_setting('app.setting_avatar', true), '') <> new.id::text then
    raise exception 'Change your photo from your profile.' using errcode = '42501';
  end if;
  return new;
end
$fn$;
comment on function app.users_self_signup_guard() is
  'BEFORE INSERT OR UPDATE on public.users. Self-created accounts are owner/student only and only via svc_create_self_signup_profile; signup_source never changes (service role included); avatar_path changes only through me_set_avatar or the service role.';
revoke all on function app.users_self_signup_guard() from public;

create trigger users_self_signup_guard
  before insert or update on public.users
  for each row execute function app.users_self_signup_guard();

create or replace function app.users_avatar_erasure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    perform app.enqueue_storage_erasure('avatars', old.avatar_path, null, 'account.avatar_deleted');
    return old;
  end if;
  if old.avatar_path is not null and old.avatar_path is distinct from new.avatar_path then
    perform app.enqueue_storage_erasure('avatars', old.avatar_path, null, 'account.avatar_replaced');
  end if;
  return new;
end
$fn$;
revoke all on function app.users_avatar_erasure() from public;

create trigger users_avatar_erasure
  after update of avatar_path or delete on public.users
  for each row execute function app.users_avatar_erasure();

-- ─── 3. Redefinitions that the new account shapes need ────────────────────────────────────
-- A tenant who signed up has no PG until an owner or warden accepts them. Every other rule is
-- unchanged, including "A student must belong to a hostel" for every warden-created resident.
CREATE OR REPLACE FUNCTION app.enforce_role_limits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int;
  v_limit int;
  v_hostel uuid;
  v_arriving boolean;
begin
  if new.status <> 'active' or new.deleted_at is not null then
    return new;
  end if;
  if new.role not in ('manager','warden','student') then
    return new;
  end if;
  if new.hostel_id is null then
    -- 2026-10-25: a self-signed-up tenant waits without a PG until a join request is accepted.
    if new.role = 'student' and new.signup_source <> 'admin' then
      return new;
    end if;
    raise exception 'A % must belong to a hostel.', new.role using errcode = 'P0001';
  end if;

  v_limit := case new.role when 'manager' then 5 when 'warden' then 5 else 10000 end;

  if new.role in ('manager','warden') then
    if tg_op = 'UPDATE' then
      if new.hostel_id is distinct from old.hostel_id
         and new.role = old.role
         and new.status = old.status
         and new.deleted_at is not distinct from old.deleted_at
         and exists (select 1 from public.staff_hostel_access a
                      where a.user_id = new.id and a.hostel_id = new.hostel_id) then
        return new;
      end if;
      v_arriving := old.status <> 'active' or old.deleted_at is not null or new.role <> old.role;
    else
      v_arriving := true;
    end if;

    for v_hostel in
      select new.hostel_id
       where tg_op = 'INSERT'
          or exists (select 1 from public.staff_hostel_access a
                      where a.user_id = new.id and a.hostel_id = new.hostel_id)
      union
      select a.hostel_id
        from public.staff_hostel_access a
       where v_arriving
         and a.user_id = new.id
      order by 1
    loop
      perform pg_advisory_xact_lock(hashtextextended(v_hostel::text || ':' || new.role::text, 0));

      select count(*) into v_count
      from public.staff_hostel_access a
      join public.users u on u.id = a.user_id
      where a.hostel_id = v_hostel
        and u.role = new.role
        and u.status = 'active'
        and u.deleted_at is null
        and u.id <> new.id;

      if v_count >= v_limit then
        -- The Flutter sheet and the Edge Function both recognise this sentence by its opening
        -- words ("This PG already has 5 active"), so it is a contract, not just copy.
        raise exception 'This PG already has % active %s. Remove one from it first.', v_limit, new.role
          using errcode = 'P0001';
      end if;
    end loop;
    return new;
  end if;

  select count(*) into v_count
  from public.users u
  where u.hostel_id = new.hostel_id
    and u.role = new.role
    and u.status = 'active'
    and u.deleted_at is null
    and u.id <> new.id;

  if v_count >= v_limit then
    raise exception 'This hostel has reached the limit of 10,000 active students.' using errcode = 'P0001';
  end if;
  return new;
end $function$;

-- users.hostel_id stays out of every client's reach. The three new arms are reachable only from
-- inside the definer routines of this file, and each re-proves its case from the database.
CREATE OR REPLACE FUNCTION app.users_update_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_manages_target boolean;
  v_link_ok boolean := false;
begin
  if new.email is distinct from old.email then
    new.email_verified_at := null;
    new.email_verification_reset_at := now();
  elsif new.email_verified_at is distinct from old.email_verified_at and not app.is_service_role() then
    raise exception 'Email verification cannot be granted by hand — it is earned by opening the confirmation link emailed to the address.'
      using errcode = '42501';
  end if;

  if app.is_super_admin() then
    return new;
  end if;

  -- 2026-10-25: the owner of a PG manages its residents' accounts as well as its wardens do, so
  -- an owner can check out a resident who has a login (wd_vacate_student admits owners).
  v_manages_target :=
       (old.role in ('manager','warden') and app.owns_hostel(old.hostel_id))
    or (old.role = 'student' and app.has_role_in(old.hostel_id, 'warden', 'owner'));

  if new.id is distinct from old.id then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    raise exception 'You cannot change an account''s role.' using errcode = '42501';
  end if;

  if new.hostel_id is distinct from old.hostel_id then
    v_link_ok := coalesce(
      -- (B) a tenant who signed up joins the PG whose pending request was accepted in THIS
      --     transaction (ow_decide_join_request), by its owner or warden.
      (    old.role = 'student' and old.hostel_id is null and new.hostel_id is not null
       and old.signup_source <> 'admin'
       and current_setting('app.linking_student', true) = old.id::text || ':' || new.hostel_id::text
       and exists (select 1 from public.hostel_join_requests r
                    where r.user_id = old.id and r.hostel_id = new.hostel_id
                      and r.status = 'accepted' and r.decided_at = now())
       and app.has_role_in(new.hostel_id, 'warden', 'owner'))
      -- (C) a tenant who signed up leaves: their roster row in that PG is vacated
      --     (wd_vacate_student), by its owner or warden.
      or (    old.role = 'student' and old.hostel_id is not null and new.hostel_id is null
          and old.signup_source <> 'admin'
          and current_setting('app.unlinking_student', true) = old.id::text
          and not exists (select 1 from public.students s
                           where s.user_id = old.id and s.hostel_id = old.hostel_id and s.status <> 'vacated')
          and app.has_role_in(old.hostel_id, 'warden', 'owner'))
      -- (D) an owner who signed up is bound to the first PG they created (ow_create_first_hostel).
      or (    old.role = 'owner' and old.hostel_id is null and new.hostel_id is not null
          and old.id = auth.uid()
          and current_setting('app.binding_owner', true) = new.hostel_id::text
          and exists (select 1 from public.hostels h where h.id = new.hostel_id and h.owner_user_id = old.id)),
      false);
  end if;

  if new.hostel_id is distinct from old.hostel_id
     and not v_link_ok
     and not coalesce(
           old.role in ('manager','warden')
       and old.deleted_at is null
       and new.hostel_id is not null
       and exists (select 1 from public.staff_hostel_access a
                    where a.user_id = old.id and a.hostel_id = new.hostel_id)
       and exists (select 1
                     from public.hostels h_new
                     join public.hostels h_old on h_old.owner_user_id = h_new.owner_user_id
                    where h_new.id = new.hostel_id and h_old.id = old.hostel_id)
       and (   (old.id = auth.uid() and old.status = 'active' and app.mfa_satisfied())
            or (app.owns_hostel(old.hostel_id) and app.owns_hostel(new.hostel_id))),
         false) then
    raise exception 'You cannot move an account to another hostel.' using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  if (new.status is distinct from old.status or new.deleted_at is distinct from old.deleted_at)
     and not v_manages_target then
    raise exception 'You cannot change this account''s status.' using errcode = '42501';
  end if;

  if new.id = auth.uid() or v_manages_target or v_link_ok then
    return new;
  end if;
  raise exception 'Not allowed.' using errcode = '42501';
end $function$;

-- Facebook accounts without an email and every Truecaller account get a synthetic address under
-- identity.apnivaas.invalid (RFC 2606: guaranteed never to resolve). Nobody can open a link
-- there, so nobody may be asked to. Mirrored by isReachableAddress() in
-- supabase/functions/_shared/verification.ts and by the app's own copy.
CREATE OR REPLACE FUNCTION app.email_is_reachable(p_email text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select p_email is not null
     and length(btrim(p_email)) > 0
     and lower(btrim(p_email)) not like '%@student.hostelpro.local'
     and lower(btrim(p_email)) not like '%@identity.apnivaas.invalid'
$function$;

-- ─── 4. hostels: where the PG is and what it is; subscriptions: where a plan came from ─────
alter table public.hostels
  add column latitude numeric(9,6)
    constraint hostels_latitude_check check (latitude is null or latitude between -90 and 90),
  add column longitude numeric(9,6)
    constraint hostels_longitude_check check (longitude is null or longitude between -180 and 180),
  add column locality text
    constraint hostels_locality_check check (locality is null or char_length(locality) between 2 and 120),
  add column city text
    constraint hostels_city_check check (city is null or char_length(city) between 2 and 80),
  add column pincode text
    constraint hostels_pincode_check check (pincode is null or pincode ~ '^[1-9][0-9]{5}$'),
  add column property_type text not null default 'pg'
    constraint hostels_property_type_check check (property_type in ('pg', 'hostel', 'co_living', 'flats')),
  add column gender_policy text
    constraint hostels_gender_policy_check check (gender_policy is null or gender_policy in ('boys', 'girls', 'coed')),
  add column listed boolean not null default true;

alter table public.hostels
  add constraint hostels_lat_lng_pair check ((latitude is null) = (longitude is null));

create index hostels_listed_geo_idx on public.hostels (latitude, longitude)
  where listed and latitude is not null;
create index hostels_listed_city_idx on public.hostels (lower(city)) where listed;

comment on column public.hostels.listed is
  'true = tenants can find this PG in st_nearby_hostels / st_search_hostels (while its plan is active or on trial).';

alter table public.subscriptions
  add column kind text not null default 'manual'
    constraint subscriptions_kind_check check (kind in ('manual', 'trial', 'paid'));

-- One free month per owner, ever.
create unique index subscriptions_one_trial_per_owner on public.subscriptions (owner_user_id) where kind = 'trial';

comment on column public.subscriptions.kind is
  'manual = entered by the Super Admin; trial = the free month from ow_create_first_hostel; paid = a Razorpay plan payment. status stays date-driven, so a trial reads as active everywhere.';

-- ─── 5. New tables ────────────────────────────────────────────────────────────────────────

-- 5a. Facebook / Truecaller identities. Service role only: no client policy at all.
create table public.external_identities (
  provider        text not null constraint external_identities_provider_check check (provider in ('facebook', 'truecaller')),
  subject         text not null constraint external_identities_subject_check check (char_length(subject) between 1 and 255),
  user_id         uuid not null references auth.users (id) on delete cascade,
  created_at      timestamptz not null default now(),
  last_sign_in_at timestamptz,
  primary key (provider, subject),
  constraint external_identities_one_per_provider unique (provider, user_id)
);
create index external_identities_user_idx on public.external_identities (user_id);

create or replace function app.guard_external_identity_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_role public.user_role;
begin
  select u.role into v_role from public.users u where u.id = new.user_id;
  if v_role is not null and v_role not in ('owner', 'student') then
    raise exception 'Staff and administrator accounts sign in with the login they were given.'
      using errcode = '42501';
  end if;
  return new;
end
$fn$;
revoke all on function app.guard_external_identity_link() from public;

create trigger external_identities_guard
  before insert or update of user_id, provider on public.external_identities
  for each row execute function app.guard_external_identity_link();

-- 5b. The only source of plan prices.
create table public.platform_plans (
  id              text primary key constraint platform_plans_id_check check (id ~ '^[a-z_]{3,20}$'),
  name            text not null constraint platform_plans_name_check check (char_length(name) between 2 and 40),
  months          smallint not null constraint platform_plans_months_check check (months between 1 and 24),
  bonus_months    smallint not null default 0 constraint platform_plans_bonus_check check (bonus_months between 0 and 12),
  price_per_month numeric(10,2) not null constraint platform_plans_price_check check (price_per_month > 0 and price_per_month <> 'NaN'),
  amount          numeric(12,2) not null constraint platform_plans_amount_check check (amount >= 1 and amount <= 1000000 and amount <> 'NaN'),
  amount_paise    bigint generated always as ((round(amount * 100))::bigint) stored,
  active          boolean not null default true,
  sort_order      smallint not null default 0,
  created_at      timestamptz not null default now(),
  constraint platform_plans_amount_is_months_times_price check (amount = price_per_month * months)
);

insert into public.platform_plans (id, name, months, bonus_months, price_per_month, amount, sort_order) values
  ('monthly',   'Monthly',   1,  0, 1099, 1099,  1),
  ('quarterly', 'Quarterly', 3,  0,  999, 2997,  2),
  ('yearly',    'Yearly',    12, 1,  959, 11508, 3);

-- 5c. Plan payments. A row per Razorpay order; 'paid' is terminal and keyed on the payment id.
create table public.subscription_payments (
  id                  uuid primary key default gen_random_uuid(),
  hostel_id           uuid not null references public.hostels (id) on delete restrict,
  owner_user_id       uuid references public.users (id) on delete set null,
  plan_id             text not null references public.platform_plans (id),
  months              smallint not null constraint subscription_payments_months_check check (months between 1 and 24),
  bonus_months        smallint not null default 0 constraint subscription_payments_bonus_check check (bonus_months between 0 and 12),
  amount_paise        bigint not null constraint subscription_payments_amount_check check (amount_paise >= 100 and amount_paise <= 100000000),
  razorpay_order_id   text not null constraint subscription_payments_order_key unique
                        constraint subscription_payments_order_shape check (razorpay_order_id ~ '^order_[A-Za-z0-9]{6,30}$'),
  razorpay_payment_id text constraint subscription_payments_payment_key unique
                        constraint subscription_payments_payment_shape check (razorpay_payment_id is null or razorpay_payment_id ~ '^pay_[A-Za-z0-9]{6,30}$'),
  status              text not null default 'created' constraint subscription_payments_status_check check (status in ('created', 'paid', 'failed')),
  method              text constraint subscription_payments_method_check check (method is null or char_length(method) <= 40),
  failure_reason      text constraint subscription_payments_failure_check check (failure_reason is null or char_length(failure_reason) <= 200),
  verified_via        text constraint subscription_payments_via_check check (verified_via is null or verified_via in ('checkout', 'webhook')),
  subscription_id     uuid references public.subscriptions (id),
  period_start        date,
  period_end          date,
  created_by          uuid references public.users (id) on delete set null,
  created_at          timestamptz not null default now(),
  paid_at             timestamptz,
  constraint subscription_payments_paid_shape check (
    (status = 'paid') = (razorpay_payment_id is not null and paid_at is not null and subscription_id is not null
                         and period_start is not null and period_end is not null and verified_via is not null))
);
create index subscription_payments_hostel_idx on public.subscription_payments (hostel_id, created_at desc);

-- 5d. Demo requests from signed-in owners.
create table public.demo_requests (
  id            uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.users (id) on delete cascade,
  hostel_id     uuid references public.hostels (id) on delete set null,
  name          text not null constraint demo_requests_name_check check (char_length(name) between 2 and 80),
  phone         text not null constraint demo_requests_phone_check check (phone ~ '^[6-9][0-9]{9}$'),
  pg_name       text not null constraint demo_requests_pg_name_check check (char_length(pg_name) between 2 and 120),
  city          text not null constraint demo_requests_city_check check (char_length(city) between 2 and 80),
  bed_band      text not null constraint demo_requests_bed_band_check check (bed_band in ('1-20', '21-50', '51-100', '100+')),
  slot_start    timestamptz not null,
  status        text not null default 'requested'
                  constraint demo_requests_status_check check (status in ('requested', 'confirmed', 'done', 'no_show', 'cancelled')),
  note          text constraint demo_requests_note_check check (note is null or char_length(note) <= 500),
  handled_by    uuid references public.users (id) on delete set null,
  handled_at    timestamptz,
  created_at    timestamptz not null default now()
);
create unique index demo_requests_one_open_per_owner on public.demo_requests (owner_user_id)
  where status in ('requested', 'confirmed');
create index demo_requests_slot_idx on public.demo_requests (slot_start desc);

-- 5e. A tenant asks to join a PG; its owner or warden decides.
create table public.hostel_join_requests (
  id            uuid primary key default gen_random_uuid(),
  hostel_id     uuid not null references public.hostels (id) on delete cascade,
  user_id       uuid not null references public.users (id) on delete cascade,
  message       text constraint hostel_join_requests_message_check check (message is null or char_length(message) <= 300),
  status        text not null default 'pending'
                  constraint hostel_join_requests_status_check check (status in ('pending', 'accepted', 'declined', 'cancelled', 'expired')),
  decided_by    uuid references public.users (id) on delete set null,
  decided_at    timestamptz,
  decision_note text constraint hostel_join_requests_note_check check (decision_note is null or char_length(decision_note) <= 300),
  student_id    uuid references public.students (id) on delete set null,
  created_at    timestamptz not null default now(),
  constraint hostel_join_requests_decided_shape check ((status = 'pending') = (decided_at is null))
);
create unique index hostel_join_requests_one_pending_per_user on public.hostel_join_requests (user_id) where status = 'pending';
create index hostel_join_requests_hostel_idx on public.hostel_join_requests (hostel_id, status, created_at desc);
create index hostel_join_requests_user_idx on public.hostel_join_requests (user_id, created_at desc);

-- 5f. Identity documents (fraud prevention). Rows written only by me_add_document.
create table public.user_documents (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users (id) on delete cascade,
  kind         text not null
                 constraint user_documents_kind_check
                 check (kind in ('aadhaar_masked', 'pan', 'driving_licence', 'voter_id', 'passport', 'college_or_work_id', 'other')),
  storage_path text not null constraint user_documents_path_key unique
                 constraint user_documents_path_shape
                 check (storage_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/document/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|pdf)$'),
  created_at   timestamptz not null default now(),
  constraint user_documents_path_owner check (split_part(storage_path, '/', 1) = user_id::text)
);
create index user_documents_user_idx on public.user_documents (user_id, created_at desc);

create or replace function app.user_documents_erasure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  perform app.enqueue_storage_erasure('identity-documents', old.storage_path, null, 'account.document_deleted');
  return old;
end
$fn$;
revoke all on function app.user_documents_erasure() from public;

-- AFTER DELETE fires for cascaded deletes too, so an account deletion queues every file.
create trigger user_documents_erasure
  after delete on public.user_documents
  for each row execute function app.user_documents_erasure();

-- ─── 6. Who can read what (no client writes on any new table) ─────────────────────────────
alter table public.external_identities   enable row level security;
alter table public.platform_plans        enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.demo_requests         enable row level security;
alter table public.hostel_join_requests  enable row level security;
alter table public.user_documents        enable row level security;

revoke all on table public.external_identities, public.platform_plans, public.subscription_payments,
                    public.demo_requests, public.hostel_join_requests, public.user_documents
  from public, anon, authenticated;
grant select on table public.platform_plans, public.subscription_payments, public.demo_requests,
                      public.hostel_join_requests, public.user_documents
  to authenticated;
grant select, insert, update, delete on table public.external_identities, public.platform_plans,
                                              public.subscription_payments, public.demo_requests,
                                              public.hostel_join_requests, public.user_documents
  to service_role;

create policy platform_plans_select on public.platform_plans
  for select to authenticated
  using (active or (select app.is_super_admin()));

create policy subscription_payments_select on public.subscription_payments
  for select to authenticated
  using ((select app.is_super_admin()) or hostel_id in (select app.owned_hostel_ids()));

create policy demo_requests_select on public.demo_requests
  for select to authenticated
  using ((select app.is_super_admin()) or owner_user_id = (select auth.uid()));

-- No manager path: a join request is resident data.
create policy hostel_join_requests_select on public.hostel_join_requests
  for select to authenticated
  using (
       user_id = (select auth.uid())
    or (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'));

-- ─── 7. Storage: two private buckets, uploads under your own id, reads by relationship ────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('avatars',            'avatars',            false, 1048576, array['image/jpeg']),
  ('identity-documents', 'identity-documents', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']);

create or replace function app.can_view_user_media(p_subject uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_subject is not null and p_kind in ('avatar', 'document') and (
       p_subject = auth.uid()
    or coalesce(app.is_super_admin(), false)
    or exists (
         select 1
           from public.users u
          where u.id = p_subject
            and u.deleted_at is null
            and (
                 -- the owner of the PG the person is in ...
                 (u.hostel_id is not null and coalesce(app.owns_hostel(u.hostel_id), false))
                 -- ... or of any PG a staff member has access to
              or exists (select 1 from public.staff_hostel_access a
                          where a.user_id = u.id and coalesce(app.owns_hostel(a.hostel_id), false))
                 -- the PG's warden: everyone's photo, a resident's documents
              or (u.hostel_id is not null and (p_kind = 'avatar' or u.role = 'student')
                  and coalesce(app.has_role_in(u.hostel_id, 'warden'), false))
                 -- a manager: staff and owner photos only. Managers never see resident data.
              or (p_kind = 'avatar' and u.role <> 'student' and u.hostel_id is not null
                  and coalesce(app.has_role_in(u.hostel_id, 'manager'), false))
            ))
    or exists (
         select 1
           from public.hostel_join_requests r
          where r.user_id = p_subject
            and r.status = 'pending'
            and coalesce(app.has_role_in(r.hostel_id, 'owner', 'warden'), false))
  );
$$;
comment on function app.can_view_user_media(uuid, text) is
  'May the caller see this person''s avatar (p_kind avatar) or identity documents (document)? Self, Super Admin, owner of their PG (or of a PG a staff member works in), warden of their PG (documents: residents only), manager of their PG (staff/owner avatars only), owner/warden of a PG they have a pending join request with.';

create or replace function app.can_upload_own_media(p_bucket text, p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and app.user_role() is not null
     and case p_bucket
           when 'avatars' then
             p_name ~ ('^' || auth.uid()::text || '/avatar/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$')
           when 'identity-documents' then
             p_name ~ ('^' || auth.uid()::text || '/document/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|pdf)$')
           else false
         end
     -- 30 uploads a day per bucket. Unused uploads are swept by app.apply_retention after a day.
     and (select count(*) from storage.objects o
           where o.bucket_id = p_bucket
             and o.name like auth.uid()::text || '/%'
             and o.created_at > now() - interval '1 day') < 30;
$$;
comment on function app.can_upload_own_media(text, text) is
  'Storage INSERT check: an active account writing <own uid>/avatar/<uuid>.jpg or <own uid>/document/<uuid>.<jpg|png|webp|pdf>, at most 30 a day per bucket.';

revoke all on function app.clean_line(text), app.normalize_phone(text), app.storage_path_owner(text),
                       app.can_view_user_media(uuid, text), app.can_upload_own_media(text, text)
  from public;
grant execute on function app.storage_path_owner(text), app.can_view_user_media(uuid, text),
                          app.can_upload_own_media(text, text)
  to authenticated, service_role;

-- No UPDATE or DELETE policy: keys are random and never overwritten; files leave through the
-- erasure queue (me_set_avatar, me_delete_document, account deletion, retention).
create policy apnivaas_avatars_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and app.can_upload_own_media(bucket_id, name));
create policy apnivaas_avatars_select on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and app.can_view_user_media(app.storage_path_owner(name), 'avatar'));
create policy apnivaas_identity_documents_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'identity-documents' and app.can_upload_own_media(bucket_id, name));
create policy apnivaas_identity_documents_select on storage.objects
  for select to authenticated
  using (bucket_id = 'identity-documents' and app.can_view_user_media(app.storage_path_owner(name), 'document'));

create policy user_documents_select on public.user_documents
  for select to authenticated
  using (user_id = (select auth.uid()) or app.can_view_user_media(user_id, 'document'));

-- ─── 8. Sign-up (service role only) ───────────────────────────────────────────────────────
create or replace function public.svc_create_self_signup_profile(
  p_user uuid, p_role text, p_full_name text, p_phone text, p_email text, p_source text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_name       text := app.clean_line(p_full_name);
  v_phone      text := nullif(app.normalize_phone(p_phone), '');
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_auth_email text;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('owner', 'student') then
    raise exception 'Only owner and tenant accounts can be created by sign-up.' using errcode = '22023';
  end if;
  if p_source is null or p_source not in ('self_google', 'self_facebook', 'self_truecaller') then
    raise exception 'Unknown sign-up source.' using errcode = '22023';
  end if;
  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Enter a name between 2 and 80 characters.' using errcode = '22023';
  end if;
  if v_phone is not null and v_phone !~ '^[6-9][0-9]{9}$' then
    raise exception 'Enter a valid 10-digit mobile number.' using errcode = '22023';
  end if;

  select lower(au.email) into v_auth_email from auth.users au where au.id = p_user and au.deleted_at is null;
  if v_auth_email is null then
    raise exception 'The sign-in account does not exist.' using errcode = '22023';
  end if;
  if v_email = '' then
    v_email := v_auth_email;
  end if;
  if v_email <> v_auth_email then
    raise exception 'The address does not match the sign-in account.' using errcode = '22023';
  end if;
  if exists (select 1 from public.users u where u.id = p_user) then
    raise exception 'This account already has a profile.' using errcode = '23505';
  end if;

  perform set_config('app.self_signup_profile', p_user::text, true);
  insert into public.users (id, role, full_name, email, phone, hostel_id, status, must_change_password,
                            created_by, signup_source, email_verified_at)
  values (p_user, p_role::public.user_role, v_name, v_email, v_phone, null, 'active', false,
          null, p_source, case when p_source = 'self_google' then now() end);
  perform set_config('app.self_signup_profile', '', true);

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (p_user, p_role::public.user_role, 'auth.signup.profile_created', 'user', p_user::text,
          jsonb_build_object('role', p_role, 'source', p_source, 'surface', 'edge_function'));

  return jsonb_build_object('user_id', p_user, 'role', p_role, 'signup_source', p_source);
end
$fn$;

create or replace function public.svc_login_account_for_external(p_provider text, p_subject text)
returns table (user_id uuid, email text, role public.user_role, status public.user_status, deleted_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select ei.user_id, au.email::text, pu.role, pu.status, pu.deleted_at
    from public.external_identities ei
    join auth.users au on au.id = ei.user_id and au.deleted_at is null
    left join public.users pu on pu.id = ei.user_id
   where ei.provider = p_provider
     and ei.subject = p_subject
     and app.is_service_role();
$$;

create or replace function public.svc_link_external_identity(p_provider text, p_subject text, p_user uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  begin
    insert into public.external_identities (provider, subject, user_id, last_sign_in_at)
    values (p_provider, p_subject, p_user, now())
    on conflict (provider, subject) do update
      set last_sign_in_at = now()
      where public.external_identities.user_id = excluded.user_id;
  exception when unique_violation then
    -- (provider, user_id): this account already carries a different profile of that provider.
    return false;
  end;
  return exists (select 1 from public.external_identities ei
                  where ei.provider = p_provider and ei.subject = p_subject and ei.user_id = p_user);
end
$fn$;

create or replace function public.svc_phone_in_use(p_phone text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_phone text := app.normalize_phone(p_phone);
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if v_phone !~ '^[6-9][0-9]{9}$' then
    raise exception 'Not a 10-digit mobile number.' using errcode = '22023';
  end if;
  return exists (select 1 from public.users u
                  where u.deleted_at is null and app.normalize_phone(u.phone) = v_phone)
      or exists (select 1 from auth.users au
                  where au.deleted_at is null
                    and (lower(au.email) = v_phone || '@student.hostelpro.local'
                         or app.normalize_phone(au.phone) = v_phone));
end
$fn$;

-- ─── 9. Profile, photo, documents, self-deletion (any signed-in account) ──────────────────
create or replace function public.me_update_profile(
  p_full_name text default null,
  p_phone text default null,
  p_gender text default null,
  p_date_of_birth date default null,
  p_emergency_contact_name text default null,
  p_emergency_contact_phone text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_row    public.users%rowtype;
  v_name   text;
  v_phone  text;
  v_gender text;
  v_dob    date;
  v_ename  text;
  v_ephone text;
begin
  if v_uid is null or app.user_role() is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  perform app.spend('profile_update', 30, 3600, 'Too many profile changes. Try again in a while.');

  select * into v_row from public.users u where u.id = v_uid for update;

  -- NULL keeps the current value; '' clears an optional one.
  v_name := v_row.full_name;
  if p_full_name is not null then
    v_name := app.clean_line(p_full_name);
    if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 80 then
      raise exception 'Enter your full name (2 to 80 characters).' using errcode = 'P0001', hint = 'full_name';
    end if;
  end if;

  v_phone := v_row.phone;
  if p_phone is not null then
    if btrim(p_phone) = '' then
      v_phone := null;
    else
      v_phone := app.normalize_phone(p_phone);
      if v_phone !~ '^[6-9][0-9]{9}$' then
        raise exception 'Enter a valid 10-digit mobile number.' using errcode = 'P0001', hint = 'phone';
      end if;
    end if;
  end if;

  v_gender := v_row.gender;
  if p_gender is not null then
    if btrim(p_gender) = '' then
      v_gender := null;
    elsif lower(btrim(p_gender)) in ('male', 'female', 'other') then
      v_gender := lower(btrim(p_gender));
    else
      raise exception 'Choose male, female or other.' using errcode = 'P0001', hint = 'gender';
    end if;
  end if;

  v_dob := v_row.date_of_birth;
  if p_date_of_birth is not null then
    if p_date_of_birth > (app.today() - interval '10 years')::date
       or p_date_of_birth < (app.today() - interval '100 years')::date then
      raise exception 'Enter a valid date of birth.' using errcode = 'P0001', hint = 'date_of_birth';
    end if;
    v_dob := p_date_of_birth;
  end if;

  v_ename := v_row.emergency_contact_name;
  if p_emergency_contact_name is not null then
    v_ename := app.clean_line(p_emergency_contact_name);
    if v_ename is not null and (char_length(v_ename) < 2 or char_length(v_ename) > 80) then
      raise exception 'Enter the emergency contact''s name (2 to 80 characters).'
        using errcode = 'P0001', hint = 'emergency_contact_name';
    end if;
  end if;

  v_ephone := v_row.emergency_contact_phone;
  if p_emergency_contact_phone is not null then
    if btrim(p_emergency_contact_phone) = '' then
      v_ephone := null;
    else
      v_ephone := app.normalize_phone(p_emergency_contact_phone);
      if v_ephone !~ '^[6-9][0-9]{9}$' then
        raise exception 'Enter a valid 10-digit number for the emergency contact.'
          using errcode = 'P0001', hint = 'emergency_contact_phone';
      end if;
    end if;
  end if;
  if v_ephone is not null and v_ephone = v_phone then
    raise exception 'The emergency contact needs a different number from yours.'
      using errcode = 'P0001', hint = 'emergency_contact_phone';
  end if;

  update public.users
     set full_name = v_name, phone = v_phone, gender = v_gender, date_of_birth = v_dob,
         emergency_contact_name = v_ename, emergency_contact_phone = v_ephone
   where id = v_uid;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, v_row.role, 'account.profile.update', 'user', v_uid::text, v_row.hostel_id,
          jsonb_build_object(
            'fields', to_jsonb(array_remove(array[
              case when v_name   is distinct from v_row.full_name               then 'full_name' end,
              case when v_phone  is distinct from v_row.phone                   then 'phone' end,
              case when v_gender is distinct from v_row.gender                  then 'gender' end,
              case when v_dob    is distinct from v_row.date_of_birth           then 'date_of_birth' end,
              case when v_ename  is distinct from v_row.emergency_contact_name  then 'emergency_contact_name' end,
              case when v_ephone is distinct from v_row.emergency_contact_phone then 'emergency_contact_phone' end
            ], null)),
            'surface', 'rpc'));

  return jsonb_build_object(
    'full_name', v_name, 'phone', v_phone, 'gender', v_gender, 'date_of_birth', v_dob,
    'emergency_contact_name', v_ename, 'emergency_contact_phone', v_ephone,
    'avatar_path', v_row.avatar_path);
end
$fn$;

create or replace function public.me_set_avatar(p_path text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid  uuid := auth.uid();
  v_role public.user_role := app.user_role();
  v_old  text;
  v_hostel uuid;
begin
  if v_uid is null or v_role is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  perform app.spend('avatar_set', 20, 3600, 'Too many photo changes. Try again in a while.');

  if p_path is not null then
    if p_path !~ ('^' || v_uid::text || '/avatar/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$') then
      raise exception 'That photo could not be used. Please try again.' using errcode = 'P0001';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'avatars' and o.name = p_path) then
      raise exception 'The photo did not finish uploading. Please try again.' using errcode = 'P0001';
    end if;
  end if;

  select u.avatar_path, u.hostel_id into v_old, v_hostel from public.users u where u.id = v_uid for update;
  if v_old is not distinct from p_path then
    return jsonb_build_object('avatar_path', p_path);
  end if;

  -- The previous file is queued for erasure by app.users_avatar_erasure.
  perform set_config('app.setting_avatar', v_uid::text, true);
  update public.users set avatar_path = p_path where id = v_uid;
  perform set_config('app.setting_avatar', '', true);

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, v_role, case when p_path is null then 'account.avatar.remove' else 'account.avatar.set' end,
          'user', v_uid::text, v_hostel, jsonb_build_object('replaced', v_old is not null, 'surface', 'rpc'));

  return jsonb_build_object('avatar_path', p_path);
end
$fn$;

create or replace function public.me_add_document(p_kind text, p_path text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid  uuid := auth.uid();
  v_role public.user_role := app.user_role();
  v_row  public.user_documents%rowtype;
begin
  if v_uid is null or v_role is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  perform app.spend('document_add', 20, 86400, 'Too many uploads today. Try again tomorrow.');

  if p_kind is null or p_kind not in ('aadhaar_masked', 'pan', 'driving_licence', 'voter_id', 'passport',
                                      'college_or_work_id', 'other') then
    raise exception 'Choose the type of document.' using errcode = 'P0001', hint = 'kind';
  end if;
  if p_path is null
     or p_path !~ ('^' || v_uid::text || '/document/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp|pdf)$') then
    raise exception 'That file could not be used. Please try again.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'identity-documents' and o.name = p_path) then
    raise exception 'The file did not finish uploading. Please try again.' using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('user-documents:' || v_uid::text, 0));
  if (select count(*) from public.user_documents d where d.user_id = v_uid) >= 10 then
    raise exception 'You can keep up to 10 documents. Delete one first.' using errcode = 'P0001';
  end if;

  insert into public.user_documents (user_id, kind, storage_path)
  values (v_uid, p_kind, p_path)
  on conflict (storage_path) do nothing
  returning * into v_row;
  if v_row.id is null then
    select * into v_row from public.user_documents d where d.storage_path = p_path and d.user_id = v_uid;
  end if;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (v_uid, v_role, 'account.document.add', 'user_document', v_row.id::text,
          jsonb_build_object('kind', p_kind, 'surface', 'rpc'));

  return jsonb_build_object('id', v_row.id, 'kind', v_row.kind, 'storage_path', v_row.storage_path,
                            'created_at', v_row.created_at);
end
$fn$;

create or replace function public.me_delete_document(p_document_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid  uuid := auth.uid();
  v_role public.user_role := app.user_role();
  v_kind text;
begin
  if v_uid is null or v_role is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  perform app.spend('document_delete', 30, 3600, 'Too many changes. Try again in a while.');

  -- The file is queued for erasure by app.user_documents_erasure.
  delete from public.user_documents d
   where d.id = p_document_id and d.user_id = v_uid
  returning d.kind into v_kind;
  if v_kind is null then
    raise exception 'That document is no longer there.' using errcode = 'P0001';
  end if;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (v_uid, v_role, 'account.document.delete', 'user_document', p_document_id::text,
          jsonb_build_object('kind', v_kind, 'surface', 'rpc'));

  return jsonb_build_object('id', p_document_id, 'deleted', true);
end
$fn$;

-- A self-created account that is not part of any PG has nothing anybody else needs: it is
-- deleted at once, with everything that cascades from it (files are queued by the triggers).
-- Every other account keeps using request_account_deletion.
create or replace function public.me_delete_account()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := auth.uid();
  v_row public.users%rowtype;
begin
  if v_uid is null or app.user_role() is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  perform app.spend('account_delete', 3, 86400, 'Please wait a while before trying again.');

  select * into v_row from public.users u where u.id = v_uid for update;
  if v_row.signup_source = 'admin'
     or v_row.hostel_id is not null
     or exists (select 1 from public.hostels h where h.owner_user_id = v_uid)
     or exists (select 1 from public.students s where s.user_id = v_uid and s.status <> 'vacated') then
    raise exception 'Your account is part of a PG, so its deletion goes through your PG. Use "Request account deletion".'
      using errcode = 'P0001';
  end if;

  -- The same NO ACTION references app.erase_student releases for a departing resident.
  update public.complaint_events set actor_user_id = null where actor_user_id = v_uid;
  update public.payment_intents set created_by = null where created_by = v_uid;

  begin
    delete from auth.users where id = v_uid;
  exception when foreign_key_violation then
    raise exception 'Your account is still linked to records in a PG. Ask the PG owner to remove you, then try again.'
      using errcode = 'P0001';
  end;

  update public.audit_log set actor_user_id = null where actor_user_id = v_uid;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (null, v_row.role, 'account.deleted.self', 'user', v_uid::text,
          jsonb_build_object('signup_source', v_row.signup_source, 'surface', 'rpc'));

  return jsonb_build_object('deleted', true);
end
$fn$;

-- ─── 10. Owner onboarding: the first PG, live at once on a free month ─────────────────────
create or replace function public.ow_create_first_hostel(
  p_name text,
  p_property_type text,
  p_gender_policy text,
  p_address text,
  p_locality text,
  p_city text,
  p_pincode text,
  p_floors integer,
  p_rooms integer,
  p_beds_per_room integer,
  p_latitude numeric default null,
  p_longitude numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid      uuid := auth.uid();
  v_source   text;
  v_name     text := app.clean_line(p_name);
  v_address  text := app.clean_line(p_address);
  v_locality text := app.clean_line(p_locality);
  v_city     text := app.clean_line(p_city);
  v_pincode  text := btrim(coalesce(p_pincode, ''));
  v_type     text := lower(btrim(coalesce(p_property_type, '')));
  v_gender   text := lower(btrim(coalesce(p_gender_policy, '')));
  v_hostel   uuid;
  v_today    date := app.today();
  v_end      date := app.today() + 30;
begin
  if v_uid is null or not coalesce(app.user_role() = 'owner' and app.mfa_satisfied(), false) then
    raise exception 'Only an owner account can add a PG here.' using errcode = '42501';
  end if;
  select u.signup_source into v_source from public.users u where u.id = v_uid;
  if v_source is null or v_source = 'admin' then
    raise exception 'Your PG is added by the platform administrator for this account.' using errcode = 'P0001';
  end if;
  if app.email_verification_owed(v_uid) then
    raise exception 'Verify your email address before adding a PG.' using errcode = 'P0001';
  end if;

  perform app.spend('first_hostel', 5, 86400, 'Too many attempts. Try again tomorrow.');

  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'Enter the PG name (2 to 120 characters).' using errcode = 'P0001', hint = 'name';
  end if;
  if v_type not in ('pg', 'hostel', 'co_living', 'flats') then
    raise exception 'Choose PG, Hostel, Co-living or Flats.' using errcode = 'P0001', hint = 'property_type';
  end if;
  if v_gender not in ('boys', 'girls', 'coed') then
    raise exception 'Choose Boys, Girls or Co-ed.' using errcode = 'P0001', hint = 'gender_policy';
  end if;
  if v_address is null or char_length(v_address) < 5 or char_length(v_address) > 500 then
    raise exception 'Enter the full address (5 to 500 characters).' using errcode = 'P0001', hint = 'address';
  end if;
  if v_locality is null or char_length(v_locality) < 2 or char_length(v_locality) > 120 then
    raise exception 'Enter the locality (2 to 120 characters).' using errcode = 'P0001', hint = 'locality';
  end if;
  if v_city is null or char_length(v_city) < 2 or char_length(v_city) > 80 then
    raise exception 'Enter the city (2 to 80 characters).' using errcode = 'P0001', hint = 'city';
  end if;
  if v_pincode !~ '^[1-9][0-9]{5}$' then
    raise exception 'Enter a valid 6-digit pincode.' using errcode = 'P0001', hint = 'pincode';
  end if;
  if p_floors is null or p_floors < 1 or p_floors > 50 then
    raise exception 'Floors must be between 1 and 50.' using errcode = 'P0001', hint = 'floors';
  end if;
  if p_rooms is null or p_rooms < 1 or p_rooms > 500 then
    raise exception 'Rooms must be between 1 and 500.' using errcode = 'P0001', hint = 'rooms';
  end if;
  if p_beds_per_room is null or p_beds_per_room < 1 or p_beds_per_room > 20 then
    raise exception 'Beds per room must be between 1 and 20.' using errcode = 'P0001', hint = 'beds_per_room';
  end if;
  if (p_latitude is null) <> (p_longitude is null)
     or (p_latitude is not null and (p_latitude = 'NaN' or p_longitude = 'NaN'
                                     or p_latitude not between 6 and 38 or p_longitude not between 68 and 98)) then
    raise exception 'That map pin is outside India. Try again or skip it.' using errcode = 'P0001', hint = 'location';
  end if;

  -- Double taps and retries: one at a time per owner, and a second one finds the first.
  perform pg_advisory_xact_lock(hashtextextended('first-hostel:' || v_uid::text, 0));
  if exists (select 1 from public.hostels h where h.owner_user_id = v_uid) then
    raise exception 'Your PG is already set up.' using errcode = 'P0001', hint = 'already_exists';
  end if;

  insert into public.hostels (name, owner_user_id, total_floors, total_rooms, beds_per_room_default, address,
                              created_by, locality, city, pincode, property_type, gender_policy,
                              latitude, longitude, listed)
  values (v_name, v_uid, p_floors, p_rooms, p_beds_per_room, v_address, v_uid, v_locality, v_city, v_pincode,
          v_type, v_gender, round(p_latitude, 6), round(p_longitude, 6), true)
  returning id into v_hostel;

  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount, created_by, notes, kind)
  values (v_hostel, v_uid, v_today, v_end, 0, v_uid, 'free trial', 'trial');

  -- Same rooms semantics as sa_create_hostel_with_subscription: p_rooms is the TOTAL, spread over the floors.
  perform public.scaffold_hostel(v_hostel, p_floors, p_rooms, p_beds_per_room);

  perform set_config('app.binding_owner', v_hostel::text, true);
  update public.users set hostel_id = v_hostel where id = v_uid and hostel_id is null;
  perform set_config('app.binding_owner', '', true);

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select v_hostel, u.id, 'system', 'New PG signed up', v_name || ', ' || v_city, '/super-admin/hostels'
    from public.users u
   where u.role = 'super_admin' and u.status = 'active' and u.deleted_at is null;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, 'owner', 'owner.hostel.self_created', 'hostel', v_hostel::text, v_hostel,
          jsonb_build_object('city', v_city, 'property_type', v_type, 'floors', p_floors, 'rooms', p_rooms,
                             'beds_per_room', p_beds_per_room, 'has_location', p_latitude is not null,
                             'trial_end', v_end, 'surface', 'rpc'));

  return jsonb_build_object('hostel_id', v_hostel, 'name', v_name, 'trial_start', v_today, 'trial_end', v_end);
end
$fn$;

-- ─── 11. Plans: the catalogue, the owner's status ─────────────────────────────────────────
create or replace function public.plan_catalog()
returns table (plan_id text, name text, months integer, bonus_months integer, total_months integer,
               price_per_month numeric, amount numeric, amount_paise bigint, saving_vs_monthly numeric,
               sort_order integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.name, p.months::int, p.bonus_months::int, (p.months + p.bonus_months)::int,
         p.price_per_month, p.amount, p.amount_paise,
         greatest(coalesce((select m.price_per_month from public.platform_plans m where m.id = 'monthly'), p.price_per_month)
                  * (p.months + p.bonus_months) - p.amount, 0),
         p.sort_order::int
    from public.platform_plans p
   where p.active and auth.uid() is not null
   order by p.sort_order, p.id;
$$;

create or replace function public.ow_plan_status(p_hostel_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_hostel public.hostels%rowtype;
  v_sub    public.subscriptions%rowtype;
  v_pay    public.subscription_payments%rowtype;
  v_today  date := app.today();
  v_state  text;
begin
  if not coalesce(app.owns_hostel(p_hostel_id) or app.is_super_admin(), false) then
    raise exception 'Hostel not found.' using errcode = '42501';
  end if;
  select * into v_hostel from public.hostels h where h.id = p_hostel_id;
  select * into v_sub from public.subscriptions s
   where s.hostel_id = p_hostel_id and s.cancelled_at is null
   order by s.end_date desc, s.created_at desc limit 1;
  select * into v_pay from public.subscription_payments sp
   where sp.hostel_id = p_hostel_id and sp.status = 'paid'
   order by sp.paid_at desc limit 1;

  v_state := case
    when v_sub.id is null or v_sub.end_date < v_today then 'expired'
    when v_sub.kind = 'trial' then 'trial'
    when v_sub.end_date - v_today <= 15 then 'expiring'
    else 'active' end;

  return jsonb_build_object(
    'hostel_id',     p_hostel_id,
    'hostel_name',   v_hostel.name,
    'hostel_status', v_hostel.status,
    'state',         v_state,
    'plan_kind',     v_sub.kind,
    'start_date',    v_sub.start_date,
    'end_date',      v_sub.end_date,
    'days_left',     case when v_sub.id is null then null else greatest(v_sub.end_date - v_today, 0) end,
    'writable',      coalesce(app.hostel_writable(p_hostel_id), false),
    'last_payment',  case when v_pay.id is null then null else jsonb_build_object(
                       'plan_id', v_pay.plan_id, 'amount_paise', v_pay.amount_paise, 'paid_at', v_pay.paid_at,
                       'period_start', v_pay.period_start, 'period_end', v_pay.period_end) end);
end
$fn$;

-- ─── 12. Plan payments (service role only, called by subscription-order and the webhook) ──
create or replace function public.svc_open_subscription_order(
  p_actor uuid, p_hostel_id uuid, p_plan_id text, p_order_id text, p_amount_paise bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_plan   public.platform_plans%rowtype;
  v_owner  uuid;
  v_status public.hostel_status;
  v_id     uuid;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_order_id is null or p_order_id !~ '^order_[A-Za-z0-9]{6,30}$' then
    raise exception 'Invalid order.' using errcode = '22023';
  end if;
  select h.owner_user_id, h.status into v_owner, v_status from public.hostels h where h.id = p_hostel_id;
  if v_owner is null or v_owner is distinct from p_actor
     or not exists (select 1 from public.users u
                     where u.id = p_actor and u.role = 'owner' and u.status = 'active' and u.deleted_at is null) then
    raise exception 'Hostel not found.' using errcode = 'P0001';
  end if;
  if v_status = 'suspended' then
    raise exception 'This hostel is suspended. Contact support.' using errcode = 'P0001';
  end if;
  select * into v_plan from public.platform_plans p where p.id = p_plan_id and p.active;
  if v_plan.id is null then
    raise exception 'Choose a plan.' using errcode = 'P0001';
  end if;
  if p_amount_paise is distinct from v_plan.amount_paise then
    raise exception 'The plan price changed. Please try again.' using errcode = 'P0001';
  end if;

  insert into public.subscription_payments (hostel_id, owner_user_id, plan_id, months, bonus_months, amount_paise,
                                            razorpay_order_id, created_by)
  values (p_hostel_id, p_actor, v_plan.id, v_plan.months, v_plan.bonus_months, v_plan.amount_paise, p_order_id, p_actor)
  returning id into v_id;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (p_actor, 'owner', 'owner.subscription.order_created', 'subscription_payment', v_id::text, p_hostel_id,
          jsonb_build_object('plan_id', v_plan.id, 'amount_paise', v_plan.amount_paise, 'surface', 'edge_function'));

  return jsonb_build_object('id', v_id, 'order_id', p_order_id, 'plan_id', v_plan.id,
                            'amount_paise', v_plan.amount_paise, 'months', v_plan.months,
                            'bonus_months', v_plan.bonus_months);
end
$fn$;

create or replace function public.svc_activate_subscription_payment(
  p_order_id text, p_payment_id text, p_amount_paise bigint, p_method text, p_via text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_row         public.subscription_payments%rowtype;
  v_today       date := app.today();
  v_current_end date;
  v_base        date;
  v_start       date;
  v_end         date;
  v_sub         uuid;
  v_owner       uuid;
  v_hostel_name text;
  v_plan_name   text;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_via is null or p_via not in ('checkout', 'webhook') then
    raise exception 'Unknown activation source.' using errcode = '22023';
  end if;
  if p_payment_id is null or p_payment_id !~ '^pay_[A-Za-z0-9]{6,30}$' then
    raise exception 'Invalid payment.' using errcode = 'P0001';
  end if;

  select * into v_row from public.subscription_payments sp where sp.razorpay_order_id = p_order_id for update;
  if v_row.id is null then
    raise exception 'Unknown subscription order.' using errcode = 'P0001';
  end if;
  if v_row.status = 'paid' then
    if v_row.razorpay_payment_id = p_payment_id then
      return jsonb_build_object('outcome', 'duplicate', 'hostel_id', v_row.hostel_id, 'plan_id', v_row.plan_id,
                                'period_start', v_row.period_start, 'period_end', v_row.period_end,
                                'subscription_id', v_row.subscription_id);
    end if;
    raise exception 'Order already settled by a different payment.' using errcode = 'P0001';
  end if;
  if p_amount_paise is distinct from v_row.amount_paise then
    raise exception 'Paid amount does not match the order.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.subscription_payments sp where sp.razorpay_payment_id = p_payment_id) then
    raise exception 'Order already settled by a different payment.' using errcode = 'P0001';
  end if;

  -- One activation per PG at a time, so two payments landing together both extend the plan.
  perform pg_advisory_xact_lock(hashtextextended('subscription:' || v_row.hostel_id::text, 0));
  select max(s.end_date) into v_current_end
    from public.subscriptions s where s.hostel_id = v_row.hostel_id and s.cancelled_at is null;
  v_base  := greatest(coalesce(v_current_end, v_today), v_today);
  v_start := case when v_current_end is not null and v_current_end >= v_today then v_current_end + 1 else v_today end;
  v_end   := (v_base + make_interval(months => v_row.months + v_row.bonus_months))::date;

  select h.owner_user_id, h.name into v_owner, v_hostel_name from public.hostels h where h.id = v_row.hostel_id;
  select p.name into v_plan_name from public.platform_plans p where p.id = v_row.plan_id;

  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount, created_by, notes, kind)
  values (v_row.hostel_id, v_owner, v_start, v_end, round(v_row.amount_paise / 100.0, 2), null,
          format('%s plan, Razorpay %s', v_row.plan_id, p_payment_id), 'paid')
  returning id into v_sub;

  update public.subscription_payments
     set status = 'paid', razorpay_payment_id = p_payment_id, method = left(p_method, 40), failure_reason = null,
         verified_via = p_via, subscription_id = v_sub, period_start = v_start, period_end = v_end, paid_at = now()
   where id = v_row.id;

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select v_row.hostel_id, v_owner, 'subscription', 'Plan activated',
         format('%s is on the %s plan until %s.', v_hostel_name, v_plan_name, to_char(v_end, 'DD Mon YYYY')), '/owner'
   where v_owner is not null;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (null, null, 'owner.subscription.paid', 'subscription_payment', v_row.id::text, v_row.hostel_id,
          jsonb_build_object('plan_id', v_row.plan_id, 'amount_paise', v_row.amount_paise, 'payment_id', p_payment_id,
                             'via', p_via, 'period_start', v_start, 'period_end', v_end, 'surface', 'edge_function'));

  return jsonb_build_object('outcome', 'paid', 'hostel_id', v_row.hostel_id, 'plan_id', v_row.plan_id,
                            'period_start', v_start, 'period_end', v_end, 'subscription_id', v_sub);
end
$fn$;

create or replace function public.svc_mark_subscription_payment_failed(p_order_id text, p_reason text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  update public.subscription_payments
     set status = 'failed', failure_reason = left(app.clean_line(p_reason), 200)
   where razorpay_order_id = p_order_id and status = 'created';
  return found;
end
$fn$;

-- ─── 13. Book a demo ──────────────────────────────────────────────────────────────────────
create or replace function public.ow_book_demo(
  p_name text, p_phone text, p_pg_name text, p_city text, p_bed_band text, p_slot_start timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_name  text := app.clean_line(p_name);
  v_phone text := app.normalize_phone(p_phone);
  v_pg    text := app.clean_line(p_pg_name);
  v_city  text := app.clean_line(p_city);
  v_local timestamp;
  v_hostel uuid;
  v_open  timestamptz;
  v_id    uuid;
begin
  if v_uid is null or not coalesce(app.user_role() = 'owner' and app.mfa_satisfied(), false) then
    raise exception 'Only an owner account can book a demo.' using errcode = '42501';
  end if;
  perform app.spend('demo_request', 5, 86400, 'Too many demo requests today. Try again tomorrow.');

  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Enter your name (2 to 80 characters).' using errcode = 'P0001', hint = 'name';
  end if;
  if v_phone !~ '^[6-9][0-9]{9}$' then
    raise exception 'Enter a valid 10-digit mobile number.' using errcode = 'P0001', hint = 'phone';
  end if;
  if v_pg is null or char_length(v_pg) < 2 or char_length(v_pg) > 120 then
    raise exception 'Enter the PG name (2 to 120 characters).' using errcode = 'P0001', hint = 'pg_name';
  end if;
  if v_city is null or char_length(v_city) < 2 or char_length(v_city) > 80 then
    raise exception 'Enter the city (2 to 80 characters).' using errcode = 'P0001', hint = 'city';
  end if;
  if p_bed_band is null or p_bed_band not in ('1-20', '21-50', '51-100', '100+') then
    raise exception 'Choose how many beds your PG has.' using errcode = 'P0001', hint = 'bed_band';
  end if;
  v_local := p_slot_start at time zone 'Asia/Kolkata';
  if p_slot_start is null
     or extract(minute from v_local) <> 0 or extract(second from v_local) <> 0
     or extract(hour from v_local) < 10 or extract(hour from v_local) > 18
     or v_local::date > app.today() + 14
     or p_slot_start < now() + interval '2 hours' then
    raise exception 'Pick a day in the next two weeks and an hourly time between 10 AM and 6 PM, at least two hours from now.'
      using errcode = 'P0001', hint = 'slot_start';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('demo:' || v_uid::text, 0));
  select d.slot_start into v_open from public.demo_requests d
   where d.owner_user_id = v_uid and d.status in ('requested', 'confirmed');
  if v_open is not null then
    raise exception 'You already have a demo booked for %. Cancel it to pick another time.',
      to_char(v_open at time zone 'Asia/Kolkata', 'DD Mon, HH12:MI AM') using errcode = 'P0001';
  end if;

  select u.hostel_id into v_hostel from public.users u where u.id = v_uid;
  if v_hostel is not null and not exists (select 1 from public.hostels h where h.id = v_hostel and h.owner_user_id = v_uid) then
    v_hostel := null;
  end if;

  insert into public.demo_requests (owner_user_id, hostel_id, name, phone, pg_name, city, bed_band, slot_start)
  values (v_uid, v_hostel, v_name, v_phone, v_pg, v_city, p_bed_band, p_slot_start)
  returning id into v_id;

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select null, u.id, 'system', 'New demo request',
         format('%s, %s (%s) at %s', v_name, v_pg, v_city, to_char(p_slot_start at time zone 'Asia/Kolkata', 'DD Mon, HH12:MI AM')),
         '/super-admin/demo-requests'
    from public.users u
   where u.role = 'super_admin' and u.status = 'active' and u.deleted_at is null;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, 'owner', 'owner.demo.requested', 'demo_request', v_id::text, v_hostel,
          jsonb_build_object('bed_band', p_bed_band, 'slot_start', p_slot_start, 'surface', 'rpc'));

  return jsonb_build_object('id', v_id, 'slot_start', p_slot_start, 'status', 'requested');
end
$fn$;

create or replace function public.ow_my_demo_request()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', d.id, 'slot_start', d.slot_start, 'status', d.status, 'name', d.name,
                            'phone', d.phone, 'pg_name', d.pg_name, 'city', d.city, 'bed_band', d.bed_band,
                            'created_at', d.created_at)
    from public.demo_requests d
   where d.owner_user_id = auth.uid() and d.status in ('requested', 'confirmed')
   order by d.created_at desc
   limit 1;
$$;

create or replace function public.ow_cancel_demo_request()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null or not coalesce(app.user_role() = 'owner', false) then
    raise exception 'Only an owner account can do that.' using errcode = '42501';
  end if;
  perform app.spend('demo_cancel', 10, 86400, 'Too many changes today. Try again tomorrow.');
  update public.demo_requests
     set status = 'cancelled', handled_at = now()
   where owner_user_id = v_uid and status in ('requested', 'confirmed')
  returning id into v_id;
  if v_id is null then
    raise exception 'You have no demo booked.' using errcode = 'P0001';
  end if;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (v_uid, 'owner', 'owner.demo.cancelled', 'demo_request', v_id::text, jsonb_build_object('surface', 'rpc'));
  return jsonb_build_object('id', v_id, 'status', 'cancelled');
end
$fn$;

create or replace function public.sa_demo_requests(p_status text default null, p_limit integer default 50, p_offset integer default 0)
returns table (id uuid, owner_user_id uuid, owner_name text, owner_email text, hostel_id uuid, name text, phone text,
               pg_name text, city text, bed_band text, slot_start timestamptz, status text, note text,
               created_at timestamptz, handled_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return query
    select d.id, d.owner_user_id, u.full_name, case when app.email_is_reachable(u.email) then u.email end,
           d.hostel_id, d.name, d.phone, d.pg_name, d.city, d.bed_band, d.slot_start, d.status, d.note,
           d.created_at, d.handled_at
      from public.demo_requests d
      left join public.users u on u.id = d.owner_user_id
     where p_status is null or d.status = p_status
     order by (d.status in ('requested', 'confirmed')) desc, d.slot_start asc, d.id
     limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(coalesce(p_offset, 0), 0);
end
$fn$;

create or replace function public.sa_update_demo_request(p_id uuid, p_status text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_note text := app.clean_line(p_note);
  v_found uuid;
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('requested', 'confirmed', 'done', 'no_show', 'cancelled') then
    raise exception 'Choose a valid status.' using errcode = 'P0001';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'Keep the note under 500 characters.' using errcode = 'P0001';
  end if;
  update public.demo_requests d
     set status = p_status, note = coalesce(v_note, d.note), handled_by = auth.uid(), handled_at = now()
   where d.id = p_id
  returning d.id into v_found;
  if v_found is null then
    raise exception 'Demo request not found.' using errcode = 'P0001';
  end if;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (auth.uid(), app.user_role(), 'sa.demo_request.update', 'demo_request', p_id::text,
          jsonb_build_object('status', p_status, 'surface', 'rpc'));
  return jsonb_build_object('id', p_id, 'status', p_status);
end
$fn$;

-- ─── 14. Finding a PG and asking to join it ───────────────────────────────────────────────
-- Neither search stores the caller's location or query: no audit row, no table write except
-- the uid-keyed spend counter.
create or replace function public.st_nearby_hostels(p_lat numeric, p_lng numeric)
returns table (hostel_id uuid, name text, property_type text, gender_policy text, locality text, city text,
               distance_km numeric)
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_dlat numeric := 0.45;   -- ~50 km
  v_dlng numeric;
begin
  if auth.uid() is null or not coalesce(app.user_role() = 'student', false) then
    raise exception 'Only a tenant account can search for PGs.' using errcode = '42501';
  end if;
  if p_lat is null or p_lng is null or p_lat = 'NaN' or p_lng = 'NaN'
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Your location could not be read. Search by name or city instead.' using errcode = 'P0001';
  end if;
  perform app.spend('hostel_search', 120, 3600, 'Too many searches. Try again in a few minutes.');
  v_dlng := 0.45 / greatest(cos(radians(p_lat::double precision)), 0.1)::numeric;

  return query
    select q.id, q.name, q.property_type, q.gender_policy, q.locality, q.city, round(q.km::numeric, 1)
      from (
        select h.id, h.name, h.property_type, h.gender_policy, h.locality, h.city,
               6371 * 2 * asin(sqrt(
                 power(sin(radians((h.latitude - p_lat)::double precision) / 2), 2)
                 + cos(radians(p_lat::double precision)) * cos(radians(h.latitude::double precision))
                   * power(sin(radians((h.longitude - p_lng)::double precision) / 2), 2))) as km
          from public.hostels h
         where h.listed
           and h.status = 'active'
           and h.latitude between p_lat - v_dlat and p_lat + v_dlat
           and h.longitude between p_lng - v_dlng and p_lng + v_dlng
           and app.hostel_writable(h.id)
      ) q
     where q.km <= 50
     order by q.km, q.name
     limit 25;
end
$fn$;

create or replace function public.st_search_hostels(p_query text)
returns table (hostel_id uuid, name text, property_type text, gender_policy text, locality text, city text,
               distance_km numeric)
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_q text := app.clean_line(p_query);
  v_like text;
begin
  if auth.uid() is null or not coalesce(app.user_role() = 'student', false) then
    raise exception 'Only a tenant account can search for PGs.' using errcode = '42501';
  end if;
  if v_q is null or char_length(v_q) < 2 or char_length(v_q) > 60 then
    raise exception 'Type at least 2 letters of the PG name or city.' using errcode = 'P0001';
  end if;
  perform app.spend('hostel_search', 120, 3600, 'Too many searches. Try again in a few minutes.');
  v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return query
    select h.id, h.name, h.property_type, h.gender_policy, h.locality, h.city, null::numeric
      from public.hostels h
     where h.listed
       and h.status = 'active'
       and (h.name ilike v_like or h.city ilike v_like or h.locality ilike v_like)
       and app.hostel_writable(h.id)
     order by (h.name ilike v_q || '%') desc, h.name, h.id
     limit 25;
end
$fn$;

create or replace function public.st_request_join(p_hostel_id uuid, p_message text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_me      public.users%rowtype;
  v_msg     text := app.clean_line(p_message);
  v_hostel  public.hostels%rowtype;
  v_pending text;
  v_id      uuid;
begin
  if v_uid is null or not coalesce(app.user_role() = 'student', false) then
    raise exception 'Only a tenant account can ask to join a PG.' using errcode = '42501';
  end if;
  perform app.spend('join_request', 10, 86400, 'Too many requests today. Try again tomorrow.');

  perform pg_advisory_xact_lock(hashtextextended('join-request:' || v_uid::text, 0));
  select * into v_me from public.users u where u.id = v_uid for update;
  if v_me.hostel_id is not null
     or exists (select 1 from public.students s where s.user_id = v_uid and s.status <> 'vacated') then
    raise exception 'You are already part of a PG. Ask your PG owner to remove you before joining another.'
      using errcode = 'P0001';
  end if;
  select h.name into v_pending
    from public.hostel_join_requests r join public.hostels h on h.id = r.hostel_id
   where r.user_id = v_uid and r.status = 'pending';
  if v_pending is not null then
    raise exception 'You already asked to join %. Cancel that request to ask another PG.', v_pending
      using errcode = 'P0001';
  end if;
  if v_me.phone is null then
    raise exception 'Add your phone number in Your details first.' using errcode = 'P0001', hint = 'phone';
  end if;
  if v_me.avatar_path is null then
    raise exception 'Add a profile photo before sending a request.' using errcode = 'P0001', hint = 'avatar';
  end if;
  if v_msg is not null and char_length(v_msg) > 300 then
    raise exception 'Keep the message under 300 characters.' using errcode = 'P0001', hint = 'message';
  end if;

  select * into v_hostel from public.hostels h where h.id = p_hostel_id;
  if v_hostel.id is null or not v_hostel.listed or v_hostel.status <> 'active'
     or not coalesce(app.hostel_writable(v_hostel.id), false) then
    raise exception 'This PG is not taking requests right now.' using errcode = 'P0001';
  end if;

  insert into public.hostel_join_requests (hostel_id, user_id, message)
  values (v_hostel.id, v_uid, v_msg)
  returning id into v_id;

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select v_hostel.id, x.id, 'system', 'New join request',
         v_me.full_name || ' wants to join ' || v_hostel.name || '.', x.link
    from (
      select u.id, '/owner/join-requests' as link
        from public.users u
       where u.id = v_hostel.owner_user_id and u.status = 'active' and u.deleted_at is null
      union
      select u.id, '/warden/join-requests'
        from public.staff_hostel_access a
        join public.users u on u.id = a.user_id
       where a.hostel_id = v_hostel.id and u.role = 'warden' and u.status = 'active' and u.deleted_at is null
    ) x;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, 'student', 'student.join_request.create', 'join_request', v_id::text, v_hostel.id,
          jsonb_build_object('has_message', v_msg is not null, 'surface', 'rpc'));

  return jsonb_build_object('request_id', v_id, 'hostel_id', v_hostel.id, 'hostel_name', v_hostel.name,
                            'status', 'pending');
end
$fn$;

create or replace function public.st_cancel_join_request()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_id     uuid;
  v_hostel uuid;
begin
  if v_uid is null or not coalesce(app.user_role() = 'student', false) then
    raise exception 'Only a tenant account can do that.' using errcode = '42501';
  end if;
  perform app.spend('join_cancel', 10, 86400, 'Too many changes today. Try again tomorrow.');
  update public.hostel_join_requests
     set status = 'cancelled', decided_at = now()
   where user_id = v_uid and status = 'pending'
  returning id, hostel_id into v_id, v_hostel;
  if v_id is null then
    raise exception 'You have no pending request.' using errcode = 'P0001';
  end if;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, 'student', 'student.join_request.cancel', 'join_request', v_id::text, v_hostel,
          jsonb_build_object('surface', 'rpc'));
  return jsonb_build_object('request_id', v_id, 'status', 'cancelled');
end
$fn$;

create or replace function public.st_my_join_request()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('request_id', r.id, 'hostel_id', r.hostel_id, 'hostel_name', h.name,
                            'status', r.status, 'message', r.message, 'decision_note', r.decision_note,
                            'created_at', r.created_at, 'decided_at', r.decided_at)
    from public.hostel_join_requests r
    join public.hostels h on h.id = r.hostel_id
   where r.user_id = auth.uid()
     and (r.status = 'pending' or r.decided_at > now() - interval '30 days')
   order by (r.status = 'pending') desc, r.created_at desc
   limit 1;
$$;

create or replace function public.ow_join_requests(
  p_hostel_id uuid default null, p_status text default 'pending', p_limit integer default 50, p_offset integer default 0)
returns table (request_id uuid, hostel_id uuid, hostel_name text, user_id uuid, full_name text, phone text, email text,
               avatar_path text, gender text, date_of_birth date, emergency_contact_name text,
               emergency_contact_phone text, message text, status text, created_at timestamptz,
               decided_at timestamptz, decision_note text, documents jsonb)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  if auth.uid() is null or not coalesce(app.user_role() in ('owner', 'warden'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_hostel_id is not null and not coalesce(app.has_role_in(p_hostel_id, 'owner', 'warden'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('pending', 'accepted', 'declined', 'cancelled', 'expired', 'all') then
    raise exception 'Unknown status.' using errcode = '22023';
  end if;

  return query
    with allowed as (
      select x.id from (
        select o as id from app.owned_hostel_ids() o
        union
        select app.user_hostel_id() where app.user_role() = 'warden'
      ) x
      where x.id is not null and (p_hostel_id is null or x.id = p_hostel_id)
    )
    select r.id, r.hostel_id, h.name, u.id, u.full_name, u.phone,
           case when app.email_is_reachable(u.email) then u.email end,
           u.avatar_path, u.gender, u.date_of_birth, u.emergency_contact_name, u.emergency_contact_phone,
           r.message, r.status, r.created_at, r.decided_at, r.decision_note,
           coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'storage_path', d.storage_path,
                                                         'created_at', d.created_at) order by d.created_at desc)
                       from public.user_documents d where d.user_id = u.id), '[]'::jsonb)
      from public.hostel_join_requests r
      join allowed a on a.id = r.hostel_id
      join public.hostels h on h.id = r.hostel_id
      join public.users u on u.id = r.user_id
     where coalesce(p_status, 'pending') = 'all' or r.status = coalesce(p_status, 'pending')
     order by r.created_at desc, r.id
     limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(coalesce(p_offset, 0), 0);
end
$fn$;

create or replace function public.ow_pending_join_request_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int
    from public.hostel_join_requests r
   where r.status = 'pending'
     and r.hostel_id in (
           select o from app.owned_hostel_ids() o
           union
           select app.user_hostel_id() where app.user_role() = 'warden');
$$;

create or replace function public.ow_decide_join_request(p_request_id uuid, p_accept boolean, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid     uuid := auth.uid();
  v_role    public.user_role := app.user_role();
  v_req     public.hostel_join_requests%rowtype;
  v_hostel  public.hostels%rowtype;
  v_tenant  public.users%rowtype;
  v_note    text := app.clean_line(p_note);
  v_student uuid;
begin
  if v_uid is null or v_role is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  if p_accept is null then
    raise exception 'Choose accept or decline.' using errcode = '22023';
  end if;
  perform app.spend('join_decide', 120, 3600, 'Too many decisions in a short time. Try again in a few minutes.');

  select * into v_req from public.hostel_join_requests r where r.id = p_request_id for update;
  if v_req.id is null or not coalesce(app.has_role_in(v_req.hostel_id, 'owner', 'warden'), false) then
    raise exception 'This request is no longer available.' using errcode = 'P0001';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'This request was already handled.' using errcode = 'P0001';
  end if;
  if v_note is not null and char_length(v_note) > 300 then
    raise exception 'Keep the note under 300 characters.' using errcode = 'P0001', hint = 'note';
  end if;
  select * into v_hostel from public.hostels h where h.id = v_req.hostel_id;

  if not p_accept then
    update public.hostel_join_requests
       set status = 'declined', decided_by = v_uid, decided_at = now(), decision_note = v_note
     where id = v_req.id;
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (null, v_req.user_id, 'system', 'Request declined',
            v_hostel.name || ' could not accept your request.' || coalesce(' Note: ' || v_note, ''), '/student');
    insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
    values (v_uid, v_role, 'hostel.join_request.decline', 'join_request', v_req.id::text, v_req.hostel_id,
            jsonb_build_object('has_note', v_note is not null, 'surface', 'rpc'));
    return jsonb_build_object('request_id', v_req.id, 'status', 'declined');
  end if;

  if not coalesce(app.hostel_writable(v_req.hostel_id), false) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  select * into v_tenant from public.users u where u.id = v_req.user_id for update;
  if v_tenant.id is null or v_tenant.role <> 'student' or v_tenant.status <> 'active' or v_tenant.deleted_at is not null
     or v_tenant.hostel_id is not null
     or exists (select 1 from public.students s where s.user_id = v_tenant.id and s.status <> 'vacated') then
    raise exception 'This person can no longer join: they are already in a PG or their account was closed.'
      using errcode = 'P0001';
  end if;
  if v_tenant.phone is null then
    raise exception 'This person has no phone number on their profile. Ask them to add it and send the request again.'
      using errcode = 'P0001';
  end if;

  update public.hostel_join_requests
     set status = 'accepted', decided_by = v_uid, decided_at = now(), decision_note = v_note
   where id = v_req.id;

  -- Link the account first: students_identity_guard requires the account to be in the same PG.
  perform set_config('app.linking_student', v_tenant.id::text || ':' || v_req.hostel_id::text, true);
  update public.users set hostel_id = v_req.hostel_id where id = v_tenant.id;
  perform set_config('app.linking_student', '', true);

  begin
    insert into public.students (hostel_id, user_id, full_name, phone, email, guardian_name, guardian_phone,
                                 date_of_joining, monthly_fee, created_by)
    values (v_req.hostel_id, v_tenant.id, v_tenant.full_name, v_tenant.phone,
            case when app.email_is_reachable(v_tenant.email) then v_tenant.email end,
            v_tenant.emergency_contact_name, v_tenant.emergency_contact_phone, app.today(), 0, v_uid)
    returning id into v_student;
  exception when unique_violation then
    raise exception 'A resident with this phone number is already registered in a PG.' using errcode = 'P0001';
  end;

  update public.hostel_join_requests set student_id = v_student where id = v_req.id;

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (v_req.hostel_id, v_tenant.id, 'system', 'Request accepted',
          v_hostel.name || ' accepted your request. Welcome!', '/student');

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, v_role, 'hostel.join_request.accept', 'join_request', v_req.id::text, v_req.hostel_id,
          jsonb_build_object('student_id', v_student, 'user_id', v_tenant.id, 'surface', 'rpc'));

  return jsonb_build_object('request_id', v_req.id, 'status', 'accepted', 'student_id', v_student);
end
$fn$;

-- ─── 15. Staff deletion (service role only, called by owner-staff-account) ────────────────
create or replace function public.svc_delete_staff_account(p_actor uuid, p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_target   public.users%rowtype;
  v_allowed  boolean;
  v_sessions integer := 0;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  select * into v_target from public.users u where u.id = p_user for update;
  if v_target.id is null or v_target.role not in ('manager', 'warden') then
    raise exception 'Staff member not found.' using errcode = 'P0001';
  end if;
  select exists (select 1 from public.users o
                  where o.id = p_actor and o.role = 'owner' and o.status = 'active' and o.deleted_at is null)
     and (   exists (select 1 from public.staff_hostel_access a join public.hostels h on h.id = a.hostel_id
                      where a.user_id = p_user and h.owner_user_id = p_actor)
          or exists (select 1 from public.hostels h where h.id = v_target.hostel_id and h.owner_user_id = p_actor))
    into v_allowed;
  if not coalesce(v_allowed, false) then
    raise exception 'Staff member not found.' using errcode = 'P0001';
  end if;

  -- Their own things go. Files are queued by the triggers on user_documents and users.
  delete from public.user_documents where user_id = p_user;
  delete from public.external_identities where user_id = p_user;
  delete from public.push_devices where user_id = p_user;
  delete from public.notifications where user_id = p_user;
  delete from public.staff_hostel_access where user_id = p_user;

  -- The profile becomes a tombstone, so every history row keeps its foreign key.
  if v_target.deleted_at is null then
    update public.users
       set full_name = 'Deleted staff member', email = null, phone = null, avatar_path = null,
           gender = null, date_of_birth = null, emergency_contact_name = null, emergency_contact_phone = null,
           status = 'inactive', deleted_at = now()
     where id = p_user;
  end if;

  -- The login: what GoTrue's own soft delete does. The address and phone are free again.
  update auth.users
     set email = 'deleted-' || replace(p_user::text, '-', '') || '@identity.apnivaas.invalid',
         phone = null, encrypted_password = null, email_change = '', phone_change = '',
         confirmation_token = '', recovery_token = '', email_change_token_new = '',
         email_change_token_current = '', phone_change_token = '', reauthentication_token = '',
         raw_user_meta_data = '{}'::jsonb, raw_app_meta_data = '{}'::jsonb,
         banned_until = timestamptz '2999-12-31 00:00:00+00',
         deleted_at = coalesce(deleted_at, now()), updated_at = now()
   where id = p_user;
  delete from auth.identities where user_id = p_user;
  delete from auth.mfa_factors where user_id = p_user;
  delete from auth.one_time_tokens where user_id = p_user;
  delete from auth.sessions where user_id = p_user;
  get diagnostics v_sessions = row_count;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (p_actor, 'owner', 'owner.staff.deleted', 'user', p_user::text, v_target.hostel_id,
          jsonb_build_object('role', v_target.role, 'sessions_ended', v_sessions,
                             'repeat', v_target.deleted_at is not null, 'surface', 'edge_function'));

  return jsonb_build_object('user_id', p_user, 'role', v_target.role, 'already_deleted', v_target.deleted_at is not null);
end
$fn$;

-- ─── 16. Leaving a PG: the vacate flow releases a self-signed-up tenant ───────────────────
-- Before: the account went inactive and stayed pointed at the PG, and app.erase_student would
-- delete the login a month later. Now a self-signed-up tenant keeps their account: the roster
-- row lets go of it in the same UPDATE that checks them out (so the deferred erasure of that row
-- can never reach the login), and users.hostel_id is cleared through guard arm (C). Accounts the
-- warden created keep the old behaviour.
CREATE OR REPLACE FUNCTION public.wd_vacate_student(p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_hostel uuid; v_user uuid; v_erased timestamptz; v_actor uuid := auth.uid();
        v_release boolean := false; v_hostel_name text;
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

  if v_user is not null then
    select coalesce(u.signup_source, 'admin') <> 'admin' into v_release from public.users u where u.id = v_user;
    v_release := coalesce(v_release, false);
  end if;

  -- One UPDATE, so app.students_bed_guard fires once and the check-out and the request cannot
  -- come apart if the connection drops. coalesce() keeps a second check-out from resetting a
  -- clock that is already running.
  update public.students
     set status               = 'vacated',
         user_id              = case when v_release then null else user_id end,
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
    if v_release then
      perform set_config('app.unlinking_student', v_user::text, true);
      update public.users set hostel_id = null where id = v_user and hostel_id = v_hostel;
      perform set_config('app.unlinking_student', '', true);
      select name into v_hostel_name from public.hostels where id = v_hostel;
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (null, v_user, 'system', 'You have left ' || coalesce(v_hostel_name, 'your PG'),
              'You can now find your next PG and send a request.', '/student');
      insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
      values (v_actor, app.user_role(), 'student.account.unlinked', 'student', p_student_id::text, v_hostel,
              jsonb_build_object('user_id', v_user, 'surface', 'rpc'));
    else
      update public.users set status = 'inactive' where id = v_user;
    end if;
  end if;
end $function$;

-- ─── 17. Retention: request tables and unused uploads ─────────────────────────────────────
CREATE OR REPLACE FUNCTION app.apply_retention()
 RETURNS TABLE(step text, rows_affected bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- (a) COMPLAINTS AND NOTICES, 2 MONTHS.
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

  -- (b) DEFERRED ERASURES THAT HAVE COME DUE
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

  -- (c) JOIN AND DEMO REQUESTS (2026-10-25). A request nobody answered in 30 days lapses, so the
  -- tenant can ask another PG; decided ones and demo requests are kept 180 days.
  update public.hostel_join_requests
     set status = 'expired', decided_at = now()
   where status = 'pending' and created_at < now() - interval '30 days';
  get diagnostics n = row_count;
  step := 'join requests expired (pending >30d)'; rows_affected := n; return next;

  delete from public.hostel_join_requests
   where status <> 'pending' and decided_at < now() - interval '180 days';
  get diagnostics n = row_count;
  step := 'join requests deleted (decided >180d)'; rows_affected := n; return next;

  delete from public.demo_requests where slot_start < now() - interval '180 days';
  get diagnostics n = row_count;
  step := 'demo requests deleted (slot >180d)'; rows_affected := n; return next;

  -- (d) UPLOADS NOTHING POINTS AT (a photo picked and abandoned, a document never saved).
  select count(*) into n from (
    select app.enqueue_storage_erasure(o.bucket_id, o.name, null, 'retention.unused_upload') as queued
      from storage.objects o
     where o.bucket_id in ('avatars', 'identity-documents')
       and o.created_at < now() - interval '1 day'
       and not exists (select 1 from public.users u where u.avatar_path = o.name)
       and not exists (select 1 from public.user_documents d where d.storage_path = o.name)
       and not exists (select 1 from app.storage_erasures e where e.bucket = o.bucket_id and e.object_path = o.name)
     limit 500
  ) q where q.queued;
  step := 'unused uploads queued for erasure (>1d)'; rows_affected := n; return next;

  -- THE GAUGE. Not a delete: Postgres cannot destroy a storage object. This is the depth of the
  -- queue a service-role drain has to work through. A number that climbs every night is the
  -- alarm that nothing is draining it.
  select count(*) into n from app.storage_erasures where purged_at is null;
  step := 'storage objects awaiting purge (queue depth)'; rows_affected := n; return next;
end $function$;

-- ─── 18. Grants. Supabase grants EXECUTE on new public functions to anon by name, so every
--         revoke names anon (2026-09-07-lock-payout-rpc.sql). ──────────────────────────────
do $grants$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in (
         'svc_create_self_signup_profile', 'svc_login_account_for_external', 'svc_link_external_identity',
         'svc_phone_in_use', 'svc_open_subscription_order', 'svc_activate_subscription_payment',
         'svc_mark_subscription_payment_failed', 'svc_delete_staff_account',
         'me_update_profile', 'me_set_avatar', 'me_add_document', 'me_delete_document', 'me_delete_account',
         'ow_create_first_hostel', 'plan_catalog', 'ow_plan_status', 'ow_book_demo', 'ow_my_demo_request',
         'ow_cancel_demo_request', 'sa_demo_requests', 'sa_update_demo_request', 'st_nearby_hostels',
         'st_search_hostels', 'st_request_join', 'st_cancel_join_request', 'st_my_join_request',
         'ow_join_requests', 'ow_pending_join_request_count', 'ow_decide_join_request')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if r.proname like 'svc\_%' then
      execute format('grant execute on function %s to service_role', r.sig);
    else
      execute format('grant execute on function %s to authenticated, service_role', r.sig);
    end if;
  end loop;
end
$grants$;

-- ─── 19. What live looks like afterwards, or no commit ────────────────────────────────────
do $verify$
declare
  v_n int;
begin
  select count(*) into v_n
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in (
       'svc_create_self_signup_profile', 'svc_login_account_for_external', 'svc_link_external_identity',
       'svc_phone_in_use', 'svc_open_subscription_order', 'svc_activate_subscription_payment',
       'svc_mark_subscription_payment_failed', 'svc_delete_staff_account',
       'me_update_profile', 'me_set_avatar', 'me_add_document', 'me_delete_document', 'me_delete_account',
       'ow_create_first_hostel', 'plan_catalog', 'ow_plan_status', 'ow_book_demo', 'ow_my_demo_request',
       'ow_cancel_demo_request', 'sa_demo_requests', 'sa_update_demo_request', 'st_nearby_hostels',
       'st_search_hostels', 'st_request_join', 'st_cancel_join_request', 'st_my_join_request',
       'ow_join_requests', 'ow_pending_join_request_count', 'ow_decide_join_request')
     and p.prosecdef
     and p.proconfig = array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute') = (p.proname not like 'svc\_%')
     and has_function_privilege('service_role', p.oid, 'execute');
  if v_n <> 29 then
    raise exception 'expected 29 new RPCs with the right security and grants, found %', v_n;
  end if;

  select count(*) into v_n from pg_trigger t
   where not t.tgisinternal and t.tgenabled = 'O'
     and (t.tgrelid, t.tgname) in (('public.users'::regclass, 'users_self_signup_guard'),
                                  ('public.users'::regclass, 'users_avatar_erasure'),
                                  ('public.users'::regclass, 'users_update_guard'),
                                  ('public.users'::regclass, 'enforce_role_limits'),
                                  ('public.user_documents'::regclass, 'user_documents_erasure'),
                                  ('public.external_identities'::regclass, 'external_identities_guard'),
                                  ('auth.identities'::regclass, 'identities_guard_external'));
  if v_n <> 7 then
    raise exception 'a guard or erasure trigger is missing or disabled (% of 7)', v_n;
  end if;

  if exists (select 1 from pg_class c
              where c.oid in ('public.external_identities'::regclass, 'public.platform_plans'::regclass,
                              'public.subscription_payments'::regclass, 'public.demo_requests'::regclass,
                              'public.hostel_join_requests'::regclass, 'public.user_documents'::regclass)
                and not c.relrowsecurity) then
    raise exception 'a new table is missing row-level security';
  end if;
  if exists (select 1 from information_schema.role_table_grants g
              where g.table_schema = 'public'
                and g.table_name in ('external_identities', 'platform_plans', 'subscription_payments',
                                     'demo_requests', 'hostel_join_requests', 'user_documents')
                and (g.grantee = 'anon'
                     or (g.grantee = 'authenticated' and (g.privilege_type <> 'SELECT' or g.table_name = 'external_identities')))) then
    raise exception 'a client role can write a new table, or read external_identities';
  end if;
  if exists (select 1 from storage.buckets b where b.id in ('avatars', 'identity-documents') and b.public) then
    raise exception 'a new bucket is public';
  end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'apnivaas\_%') <> 4 then
    raise exception 'the four storage policies are not all there';
  end if;
  if position('app.linking_student' in (select prosrc from pg_proc where oid = 'app.users_update_guard()'::regprocedure)) = 0
     or position('signup_source' in (select prosrc from pg_proc where oid = 'app.enforce_role_limits()'::regprocedure)) = 0
     or position('identity.apnivaas.invalid' in (select prosrc from pg_proc where oid = 'app.email_is_reachable(text)'::regprocedure)) = 0
     or position('unlinking_student' in (select prosrc from pg_proc where oid = 'public.wd_vacate_student(uuid)'::regprocedure)) = 0
     or position('hostel_join_requests' in (select prosrc from pg_proc where oid = 'app.apply_retention()'::regprocedure)) = 0 then
    raise exception 'a redefined routine did not take its new body';
  end if;
  if (select sum(amount_paise) from public.platform_plans) <> 109900 + 299700 + 1150800 then
    raise exception 'the plan prices are not the agreed ones';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261025100000', 'self_signup_onboarding') on conflict (version) do nothing;

notify pgrst, 'reload schema';

commit;

-- ═══ AFTER APPLYING ════════════════════════════════════════════════════════════════════════
-- 1. Run db/migrations/2026-10-25-self-signup-onboarding.test.sql (it rolls itself back and
--    ends with 'ALL SELF SIGN-UP TESTS PASSED').
-- 2. Every existing account is 'admin' and nothing else moved:
--      select signup_source, count(*) from public.users group by 1;          -- one row: admin
--      select kind, count(*) from public.subscriptions group by 1;           -- one row: manual
-- 3. The redefined routines carry their new bodies:
--      select p.oid::regprocedure, md5(p.prosrc) from pg_proc p
--       where p.oid in ('app.users_update_guard()'::regprocedure, 'app.enforce_role_limits()'::regprocedure,
--                       'app.email_is_reachable(text)'::regprocedure, 'public.wd_vacate_student(uuid)'::regprocedure,
--                       'app.apply_retention()'::regprocedure);
--    None of the five 2026-10-24 md5 values in the $guard$ block above.
-- 4. Then deploy mobile-auth, owner-staff-account, subscription-order and razorpay-webhook, and
--    add order.paid to the Razorpay webhook's events (payment.captured is already there).
