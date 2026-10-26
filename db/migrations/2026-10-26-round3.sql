-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 2026-10-26 — ROUND 3 (docs/round3-spec.md R1–R9). App contract: docs/round3-api.md.
--   R1 self_email sign-up source; persona staff creates a staff applicant (role student, no access)
--   R2 dues and per-month aggregates start at check-in; fee months + tenant timeline RPCs
--   R3 nothing to drop: no server rule forces an owner to enrol a factor (app.mfa_satisfied has a
--      no-factor grace arm); an enrolled factor is still demanded (aal2), so optional 2FA keeps working
--   R5 PG profile, bucket pg-media, reviews, richer discovery, PG profile for prospective tenants
--   R6 check-out requests (+ nightly run of accepted ones on their date)
--   R7 Super Admin sign-ups, deletion log, permanent delete (PII erased, money rows kept)
--   R8 staff applicants -> owner converts to manager|warden; self-sourced staff may use social sign-in
--   R9 hostel UPI settings + payment claims confirmed by owner/warden through wd_record_payment
-- Redefined live routines are md5-checked below (bodies read with pg_get_functiondef 2026-10-25).
-- Undo: 2026-10-26-round3.down.sql. Tests: 2026-10-26-round3.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;
set local lock_timeout = '10s';

do $guard$
declare
  v_expected constant jsonb := jsonb_build_object(
    'public.rpc_fee_ledger(uuid,text)',                                       '85d89e654b110e810a633c1186c3caf7',
    'app.guard_external_identity()',                                          'fc495977990bd57e0d0742bf456f6b81',
    'app.guard_external_identity_link()',                                     '17e2d9ec28c641d74cf7edb385987aaf',
    'app.users_self_signup_guard()',                                          '82700a42e5b5f8a7e74341351d923d1c',
    'app.users_update_guard()',                                               'd51bf221d79dbf8443ac593585089fd1',
    'public.st_nearby_hostels(numeric,numeric)',                              '98f80080c4f4d94a64d0318f2dfb4ca0',
    'public.st_search_hostels(text)',                                         '269b51447cb0662fdd049469f625fd87',
    'public.svc_create_self_signup_profile(uuid,text,text,text,text,text)',   '15a1ecb652af3cd1b349db326dbb7348');
  k text;
  v_md5 text;
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  for k in select jsonb_object_keys(v_expected) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = k::regprocedure;
    if v_md5 is distinct from v_expected ->> k then
      raise exception '% is not the body measured on 2026-10-25 (md5 %); nothing changed', k, v_md5;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'users' and column_name = 'staff_applicant') then
    raise exception 'public.users.staff_applicant already exists: this migration has already run';
  end if;
  if exists (select 1 from storage.buckets where id = 'pg-media') then
    raise exception 'a bucket named pg-media already exists; look at it first';
  end if;
end
$guard$;

-- ─── 1. Helpers ───────────────────────────────────────────────────────────────────────────
create or replace function app.inr(p numeric)
returns text language sql immutable set search_path = '' as $$
  select '₹' || trim(to_char(p, case when p = trunc(p) then 'FM99,99,99,990' else 'FM99,99,99,990D00' end));
$$;

create or replace function app.month_label(p_month text)
returns text language sql immutable set search_path = '' as $$
  select to_char(to_date(p_month || '-01', 'YYYY-MM-DD'), 'FMMonth YYYY');
$$;

-- Notify a PG's wardens and/or owner (active accounts only), except one user.
create or replace function app.notify_hostel(p_hostel uuid, p_wardens boolean, p_owner boolean, p_title text,
                                             p_body text, p_warden_link text, p_owner_link text, p_except uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select p_hostel, u.id, 'system', p_title, p_body, case when u.role = 'owner' then p_owner_link else p_warden_link end
    from public.users u
   where u.status = 'active' and u.deleted_at is null and u.id is distinct from p_except
     and (   (p_owner and u.id = (select h.owner_user_id from public.hostels h where h.id = p_hostel))
          or (p_wardens and u.role = 'warden'
              and exists (select 1 from public.staff_hostel_access a where a.user_id = u.id and a.hostel_id = p_hostel)));
$$;

-- ─── 2. R1 / R8: sign-up sources, staff applicants, who may use social sign-in ─────────────
alter table public.users drop constraint users_signup_source_check;
alter table public.users
  add constraint users_signup_source_check
    check (signup_source in ('admin', 'self_google', 'self_facebook', 'self_truecaller', 'self_email')),
  add column staff_applicant boolean not null default false,
  add column city text constraint users_city_check check (city is null or char_length(city) between 2 and 80),
  add column pincode text constraint users_pincode_check check (pincode is null or pincode ~ '^[1-9][0-9]{5}$');
comment on column public.users.staff_applicant is
  'Self sign-up as staff: role student, no PG, no access until an owner accepts a staff request (ow_decide_staff_request).';

-- No profile yet (a new sign-up) or owner/tenant: yes. Manager/warden: only when the account was
-- self-created (an email source only once the address is proved). Super Admin: never.
create or replace function app.external_signin_allowed(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case
             when u.role in ('owner', 'student') then true
             when u.role in ('manager', 'warden') then
                  u.signup_source in ('self_google', 'self_facebook', 'self_truecaller')
               or (u.signup_source = 'self_email' and u.email_verified_at is not null)
             else false end
      from public.users u where u.id = p_user), true);
$$;

create or replace function app.guard_external_identity()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if new.provider in ('email', 'phone') then
    return new;
  end if;
  if new.provider not in ('google', 'facebook') then
    raise exception 'This sign-in method is not available.' using errcode = '42501';
  end if;
  if not app.external_signin_allowed(new.user_id) then
    raise exception 'Staff and administrator accounts sign in with the login they were given.' using errcode = '42501';
  end if;
  return new;
end
$fn$;

create or replace function app.guard_external_identity_link()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if not app.external_signin_allowed(new.user_id) then
    raise exception 'Staff and administrator accounts sign in with the login they were given.' using errcode = '42501';
  end if;
  return new;
end
$fn$;

-- Sign-up never creates staff. A staff applicant becomes manager/warden only inside
-- ow_decide_staff_request (app.converting_staff); the flag never changes otherwise.
create or replace function app.users_self_signup_guard()
returns trigger language plpgsql security definer set search_path = '' as $fn$
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
    if new.staff_applicant and (new.signup_source = 'admin' or new.role <> 'student') then
      raise exception 'Only a sign-up account can apply as staff.' using errcode = '22023';
    end if;
    if new.avatar_path is not null then
      raise exception 'Add a profile photo after the account exists.' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.signup_source is distinct from old.signup_source then
    raise exception 'The sign-up source of an account cannot be changed.' using errcode = '42501';
  end if;
  if (new.role is distinct from old.role or new.staff_applicant is distinct from old.staff_applicant)
     and not (old.staff_applicant and not new.staff_applicant and old.role = 'student'
              and new.role in ('manager', 'warden')
              and split_part(coalesce(current_setting('app.converting_staff', true), ''), ':', 1) = old.id::text) then
    if new.signup_source <> 'admin' and new.role not in ('owner', 'student') then
      raise exception 'Only owner and tenant accounts can be created by sign-up.' using errcode = '22023';
    end if;
    if new.staff_applicant is distinct from old.staff_applicant then
      raise exception 'The staff application cannot be changed by hand.' using errcode = '42501';
    end if;
  end if;
  if new.avatar_path is distinct from old.avatar_path
     and not app.is_service_role()
     and coalesce(current_setting('app.setting_avatar', true), '') <> new.id::text then
    raise exception 'Change your photo from your profile.' using errcode = '42501';
  end if;
  return new;
end
$fn$;

-- Live body + arm (E): the owner's accept converts an applicant (role and PG in one UPDATE).
create or replace function app.users_update_guard()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_manages_target boolean;
  v_link_ok boolean := false;
  v_convert boolean := false;
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

  v_manages_target :=
       (old.role in ('manager','warden') and app.owns_hostel(old.hostel_id))
    or (old.role = 'student' and app.has_role_in(old.hostel_id, 'warden', 'owner'));

  -- (E) 2026-10-26: a staff applicant accepted by the owner of the PG, in THIS transaction.
  v_convert := coalesce(
        old.staff_applicant and old.role = 'student' and new.role in ('manager', 'warden')
    and old.hostel_id is null and new.hostel_id is not null
    and current_setting('app.converting_staff', true) = old.id::text || ':' || new.hostel_id::text
    and exists (select 1 from public.staff_join_requests r
                 where r.user_id = old.id and r.hostel_id = new.hostel_id
                   and r.status = 'accepted' and r.decided_at = now())
    and app.owns_hostel(new.hostel_id), false);

  if new.id is distinct from old.id then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if new.role is distinct from old.role and not v_convert then
    raise exception 'You cannot change an account''s role.' using errcode = '42501';
  end if;

  if new.hostel_id is distinct from old.hostel_id then
    v_link_ok := v_convert or coalesce(
      (    old.role = 'student' and old.hostel_id is null and new.hostel_id is not null
       and old.signup_source <> 'admin'
       and current_setting('app.linking_student', true) = old.id::text || ':' || new.hostel_id::text
       and exists (select 1 from public.hostel_join_requests r
                    where r.user_id = old.id and r.hostel_id = new.hostel_id
                      and r.status = 'accepted' and r.decided_at = now())
       and app.has_role_in(new.hostel_id, 'warden', 'owner'))
      or (    old.role = 'student' and old.hostel_id is not null and new.hostel_id is null
          and old.signup_source <> 'admin'
          and current_setting('app.unlinking_student', true) = old.id::text
          and not exists (select 1 from public.students s
                           where s.user_id = old.id and s.hostel_id = old.hostel_id and s.status <> 'vacated')
          and app.has_role_in(old.hostel_id, 'warden', 'owner'))
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

drop function public.svc_create_self_signup_profile(uuid, text, text, text, text, text);
create function public.svc_create_self_signup_profile(
  p_user uuid, p_role text, p_full_name text, p_phone text, p_email text, p_source text,
  p_city text default null, p_pincode text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_name       text := app.clean_line(p_full_name);
  v_phone      text := nullif(app.normalize_phone(p_phone), '');
  v_email      text := lower(btrim(coalesce(p_email, '')));
  v_city       text := app.clean_line(p_city);
  v_pin        text := nullif(btrim(coalesce(p_pincode, '')), '');
  v_auth_email text;
  v_role       public.user_role;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('owner', 'student', 'staff') then
    raise exception 'Only owner and tenant accounts can be created by sign-up.' using errcode = '22023';
  end if;
  v_role := case p_role when 'owner' then 'owner' else 'student' end;
  if p_source is null or p_source not in ('self_google', 'self_facebook', 'self_truecaller', 'self_email') then
    raise exception 'Unknown sign-up source.' using errcode = '22023';
  end if;
  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Enter a name between 2 and 80 characters.' using errcode = '22023';
  end if;
  if (v_phone is not null and v_phone !~ '^[6-9][0-9]{9}$') or (p_source = 'self_email' and v_phone is null) then
    raise exception 'Enter a valid 10-digit mobile number.' using errcode = '22023';
  end if;
  if v_city is not null and char_length(v_city) not between 2 and 80 then
    raise exception 'Enter your city.' using errcode = '22023';
  end if;
  if v_pin is not null and v_pin !~ '^[1-9][0-9]{5}$' then
    raise exception 'Enter a valid 6-digit pincode.' using errcode = '22023';
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
                            created_by, signup_source, email_verified_at, staff_applicant, city, pincode)
  values (p_user, v_role, v_name, v_email, v_phone, null, 'active', false,
          null, p_source, case when p_source = 'self_google' then now() end, p_role = 'staff', v_city, v_pin);
  perform set_config('app.self_signup_profile', '', true);

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (p_user, v_role, 'auth.signup.profile_created', 'user', p_user::text,
          jsonb_build_object('role', v_role, 'staff_applicant', p_role = 'staff', 'source', p_source, 'surface', 'edge_function'));

  return jsonb_build_object('user_id', p_user, 'role', v_role, 'staff_applicant', p_role = 'staff', 'signup_source', p_source);
end
$fn$;

-- mobile-auth asks this before a social sign-in reaches a manager/warden account.
create or replace function public.svc_external_signin_allowed(p_user uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return app.external_signin_allowed(p_user);
end
$fn$;

-- A provider just proved control of the address of a self_email account whose address was never
-- verified: whoever typed that password may not be the owner of the address, so the password and
-- every session go (the person can reset it), and with a proving provider the address is verified.
create or replace function public.svc_secure_unverified_account(p_user uuid, p_proved boolean)
returns boolean language plpgsql security definer set search_path = '' as $fn$
declare
  v public.users%rowtype;
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  select * into v from public.users u where u.id = p_user for update;
  if v.id is null or v.signup_source <> 'self_email' or v.email_verified_at is not null then
    return false;
  end if;
  update auth.users set encrypted_password = null, updated_at = now() where id = p_user;
  delete from auth.sessions where user_id = p_user;
  if coalesce(p_proved, false) then
    update public.users set email_verified_at = now() where id = p_user;
  end if;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, meta)
  values (null, null, 'auth.signup.unverified_secured', 'user', p_user::text,
          jsonb_build_object('proved', coalesce(p_proved, false), 'surface', 'edge_function'));
  return true;
end
$fn$;

-- A staff applicant cannot ask to join as a tenant.
create or replace function app.join_request_not_applicant()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if exists (select 1 from public.users u where u.id = new.user_id and u.staff_applicant) then
    raise exception 'Staff accounts ask to join a PG as staff.' using errcode = '42501';
  end if;
  return new;
end
$fn$;
create trigger hostel_join_requests_not_applicant
  before insert on public.hostel_join_requests
  for each row execute function app.join_request_not_applicant();

-- ─── 3. R2: dues start at check-in ────────────────────────────────────────────────────────
-- Live body + one condition: a resident who checked in after the month is not in it.
create or replace function public.rpc_fee_ledger(p_hostel_id uuid, p_period_month text)
 returns table(student_id uuid, full_name text, phone text, photo_url text, room_number text, bed_number integer, monthly_fee numeric, amount_due numeric, amount_paid numeric, status fee_status, paid_on date, mode payment_mode)
 language sql
 stable
 set search_path to 'public'
as $function$
  select s.id, s.full_name, s.phone, s.photo_url, r.room_number, b.bed_number, s.monthly_fee,
         coalesce(fp.amount_due, s.monthly_fee), coalesce(fp.amount_paid, 0), coalesce(fp.status, 'unpaid'::public.fee_status), fp.paid_on, fp.mode
  from public.students s
  left join public.rooms r on r.id = s.room_id
  left join public.beds b on b.id = s.bed_id
  left join public.fee_payments fp on fp.student_id = s.id and fp.period_month = p_period_month
  where s.hostel_id = p_hostel_id and s.status <> 'vacated'
    and s.date_of_joining < (to_date(p_period_month || '-01', 'YYYY-MM-DD') + interval '1 month')
  order by r.room_number nulls last, s.full_name $function$;

-- The roster row the caller may read: their own (p_student null = current), or one in a PG they own/ward.
create or replace function app.readable_student(p_student_id uuid)
returns public.students language plpgsql stable security definer set search_path = '' as $fn$
declare
  v public.students%rowtype;
begin
  select * into v from public.students s where s.id = coalesce(p_student_id, app.current_student_id());
  if v.id is null or not (v.user_id = auth.uid() or coalesce(app.has_role_in(v.hostel_id, 'owner', 'warden'), false)) then
    raise exception 'Resident not found.' using errcode = 'P0001';
  end if;
  return v;
end
$fn$;

create or replace function public.rpc_student_fee_months(p_student_id uuid default null)
returns table (period_month text, amount_due numeric, amount_paid numeric, status public.fee_status, paid_on date,
               mode public.payment_mode)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  v    public.students%rowtype := app.readable_student(p_student_id);
  v_to date := case when v.status = 'vacated'
                    then coalesce((v.vacated_at at time zone 'Asia/Kolkata')::date, app.today()) else app.today() end;
begin
  return query
    select to_char(m, 'YYYY-MM'), coalesce(fp.amount_due, v.monthly_fee), coalesce(fp.amount_paid, 0),
           coalesce(fp.status, 'unpaid'::public.fee_status), fp.paid_on, fp.mode
      from generate_series(date_trunc('month', v.date_of_joining::timestamp), date_trunc('month', v_to::timestamp),
                           interval '1 month') m
      left join public.fee_payments fp on fp.student_id = v.id and fp.period_month = to_char(m, 'YYYY-MM')
     order by 1 desc;
end
$fn$;

-- Room history from now on (feeds the timeline).
create or replace function app.students_room_audit()
returns trigger language plpgsql security definer set search_path = '' as $fn$
declare
  v_room text;
  v_bed  integer;
begin
  if new.bed_id is null or (tg_op = 'UPDATE' and new.bed_id is not distinct from old.bed_id) then
    return null;
  end if;
  select r.room_number, b.bed_number into v_room, v_bed
    from public.beds b join public.rooms r on r.id = b.room_id where b.id = new.bed_id;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), app.user_role(), 'student.room.assigned', 'student', new.id::text, new.hostel_id,
          jsonb_build_object('room_number', v_room, 'bed_number', v_bed, 'first', tg_op = 'INSERT'));
  return null;
end
$fn$;
create trigger students_room_audit
  after insert or update of bed_id on public.students
  for each row execute function app.students_room_audit();

-- ─── 4. R6: check-out requests (table first: the timeline reads it) ─────────────────────────
create table public.checkout_requests (
  id             uuid primary key default gen_random_uuid(),
  hostel_id      uuid not null references public.hostels (id) on delete cascade,
  student_id     uuid not null references public.students (id) on delete cascade,
  user_id        uuid references public.users (id) on delete set null,
  preferred_date date not null,
  reason         text constraint checkout_requests_reason_check check (reason is null or char_length(reason) <= 300),
  status         text not null default 'pending'
                   constraint checkout_requests_status_check
                   check (status in ('pending', 'accepted', 'declined', 'cancelled', 'completed')),
  checkout_date  date,
  decided_by     uuid references public.users (id) on delete set null,
  decided_at     timestamptz,
  decision_note  text constraint checkout_requests_note_check check (decision_note is null or char_length(decision_note) <= 300),
  completed_at   timestamptz,
  created_at     timestamptz not null default now()
);
create unique index checkout_requests_one_open on public.checkout_requests (student_id) where status in ('pending', 'accepted');
create index checkout_requests_hostel_idx on public.checkout_requests (hostel_id, status, created_at desc);
create index checkout_requests_due_idx on public.checkout_requests (checkout_date) where status = 'accepted';

-- ─── 5. R9 tables (the timeline reads claims) ──────────────────────────────────────────────
create table public.hostel_upi_settings (
  hostel_id  uuid primary key references public.hostels (id) on delete cascade,
  upi_vpa    text not null constraint hostel_upi_vpa_check check (upi_vpa ~ '^[a-z0-9][a-z0-9._-]{1,254}@[a-z][a-z0-9.-]{1,63}$'),
  payee_name text not null constraint hostel_upi_payee_check check (char_length(payee_name) between 2 and 80),
  updated_by uuid references public.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

create table public.payment_claims (
  id             uuid primary key default gen_random_uuid(),
  hostel_id      uuid not null references public.hostels (id) on delete cascade,
  student_id     uuid not null references public.students (id) on delete cascade,
  user_id        uuid references public.users (id) on delete set null,
  period_month   text not null constraint payment_claims_month_check check (period_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  amount         numeric(12,2) not null constraint payment_claims_amount_check check (amount > 0 and amount <= 10000000),
  utr            text not null constraint payment_claims_utr_check check (utr ~ '^[A-Z0-9]{10,22}$'),
  upi_vpa        text not null,
  status         text not null default 'pending'
                   constraint payment_claims_status_check check (status in ('pending', 'confirmed', 'rejected', 'cancelled')),
  decided_by     uuid references public.users (id) on delete set null,
  decided_at     timestamptz,
  decision_note  text constraint payment_claims_note_check check (decision_note is null or char_length(decision_note) <= 300),
  fee_payment_id uuid references public.fee_payments (id) on delete set null,
  created_at     timestamptz not null default now()
);
create unique index payment_claims_utr_per_hostel on public.payment_claims (hostel_id, utr) where status <> 'cancelled';
create index payment_claims_hostel_idx on public.payment_claims (hostel_id, status, created_at desc);
create index payment_claims_student_idx on public.payment_claims (student_id, created_at desc);

-- ─── 6. R2: the tenant timeline (read-only, newest first) ─────────────────────────────────
create or replace function public.st_timeline(p_student_id uuid default null)
returns table (at timestamptz, kind text, title text, detail text, amount numeric, status text, ref_id uuid)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
declare
  v       public.students%rowtype := app.readable_student(p_student_id);
  v_day   integer;
  v_rooms boolean;
begin
  select least(greatest(coalesce(h.rent_due_day, 1), 1), 28) into v_day from public.hostels h where h.id = v.hostel_id;
  v_rooms := exists (select 1 from public.audit_log a
                      where a.action = 'student.room.assigned' and a.target_type = 'student' and a.target_id = v.id::text);
  return query
  with ev as (
    select (v.date_of_joining::timestamp at time zone 'Asia/Kolkata') as at, 'checked_in'::text as kind,
           'Checked in'::text as title,
           case when not v_rooms then (select 'Room ' || r.room_number || coalesce(', bed ' || b.bed_number, '')
                                         from public.rooms r left join public.beds b on b.id = v.bed_id
                                        where r.id = v.room_id) end as detail,
           null::numeric as amount, null::text as status, v.id as ref_id
    union all
    select a.at, 'room', 'Room assigned',
           'Room ' || coalesce(a.meta ->> 'room_number', '?') || coalesce(', bed ' || (a.meta ->> 'bed_number'), ''),
           null, null, null
      from public.audit_log a
     where a.action = 'student.room.assigned' and a.target_type = 'student' and a.target_id = v.id::text
    union all
    select (greatest(make_date(split_part(fm.period_month, '-', 1)::int, split_part(fm.period_month, '-', 2)::int, v_day),
                     v.date_of_joining)::timestamp at time zone 'Asia/Kolkata'),
           'due', 'Rent due for ' || app.month_label(fm.period_month), null, fm.amount_due, fm.status::text, null
      from public.rpc_student_fee_months(v.id) fm
     where fm.amount_due > 0
    union all
    select coalesce(fp.paid_on::timestamp at time zone 'Asia/Kolkata', fp.updated_at), 'payment', 'Payment recorded',
           'For ' || app.month_label(fp.period_month) || coalesce(' · ' || upper(fp.mode::text), ''),
           fp.amount_paid, fp.status::text, fp.id
      from public.fee_payments fp where fp.student_id = v.id and fp.amount_paid > 0
    union all
    select c.created_at, 'complaint', c.title, c.category::text, null, c.status::text, c.id
      from public.complaints c where c.student_id = v.id
    union all
    select r.created_at, 'checkout_request', 'Check-out requested',
           'Preferred date ' || to_char(r.preferred_date, 'DD Mon YYYY'), null, r.status, r.id
      from public.checkout_requests r where r.student_id = v.id
    union all
    select r.decided_at, 'checkout_decision',
           case when r.status = 'declined' then 'Check-out declined' else 'Check-out accepted' end,
           coalesce('Date ' || to_char(r.checkout_date, 'DD Mon YYYY'), r.decision_note), null, r.status, r.id
      from public.checkout_requests r where r.student_id = v.id and r.decided_at is not null
    union all
    select v.vacated_at, 'checked_out', 'Checked out', null, null, null, v.id
     where v.status = 'vacated' and v.vacated_at is not null
    union all
    select pc.created_at, 'upi_claim', 'UPI payment submitted',
           'For ' || app.month_label(pc.period_month) || ' · UTR ' || pc.utr, pc.amount, pc.status, pc.id
      from public.payment_claims pc where pc.student_id = v.id
  )
  select ev.at, ev.kind, ev.title, ev.detail, ev.amount, ev.status, ev.ref_id
    from ev where ev.at is not null
   order by ev.at desc, ev.kind;
end
$fn$;

-- ─── 7. R5: PG profile, media, reviews, discovery ─────────────────────────────────────────
alter table public.hostels
  add column description text constraint hostels_description_check check (description is null or char_length(description) <= 500),
  add column amenities text[] not null default '{}'
    constraint hostels_amenities_check check (amenities <@ array['wifi', 'ac', 'food', 'laundry', 'power_backup', 'parking',
      'cctv', 'housekeeping', 'attached_bathroom', 'hot_water', 'gym', 'study_room']::text[]),
  add column logo_path text,
  add column cover_paths text[] not null default '{}'
    constraint hostels_cover_paths_check check (cardinality(cover_paths) <= 6);

create or replace function app.pg_media_path_ok(p_hostel uuid, p_kind text, p_path text)
returns boolean language sql immutable set search_path = '' as $$
  select p_path ~ ('^' || p_hostel::text || '/' || p_kind
                   || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$');
$$;

-- Any signed-in account sees a listed PG on an active/trial plan; its owner, staff and residents always.
create or replace function app.can_view_pg(p_hostel uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and app.user_role() is not null and p_hostel is not null and (
       exists (select 1 from public.hostels h
                where h.id = p_hostel and h.listed and h.status = 'active' and app.hostel_writable(h.id))
    or coalesce(app.has_role_in(p_hostel, 'owner', 'manager', 'warden', 'student'), false));
$$;

create or replace function app.can_upload_pg_media(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app.owns_hostel(app.storage_path_owner(p_name)), false)
     and coalesce(app.hostel_writable(app.storage_path_owner(p_name)), false)
     and (app.pg_media_path_ok(app.storage_path_owner(p_name), 'logo', p_name)
          or app.pg_media_path_ok(app.storage_path_owner(p_name), 'cover', p_name))
     and (select count(*) from storage.objects o
           where o.bucket_id = 'pg-media' and o.name like split_part(p_name, '/', 1) || '/%'
             and o.created_at > now() - interval '1 day') < 40;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pg-media', 'pg-media', false, 2097152, array['image/jpeg']);

create policy apnivaas_pg_media_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'pg-media' and app.can_upload_pg_media(name));
create policy apnivaas_pg_media_select on storage.objects
  for select to authenticated
  using (bucket_id = 'pg-media' and app.can_view_pg(app.storage_path_owner(name)));

create table public.pg_reviews (
  id         uuid primary key default gen_random_uuid(),
  hostel_id  uuid not null references public.hostels (id) on delete cascade,
  user_id    uuid not null references public.users (id) on delete cascade,
  rating     smallint not null constraint pg_reviews_rating_check check (rating between 1 and 5),
  comment    text constraint pg_reviews_comment_check check (comment is null or char_length(comment) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pg_reviews_one_per_tenant unique (hostel_id, user_id)
);

create or replace function public.ow_update_pg_profile(
  p_hostel_id uuid, p_name text, p_description text, p_amenities text[], p_logo_path text, p_cover_paths text[],
  p_listed boolean default null, p_latitude numeric default null, p_longitude numeric default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_h     public.hostels%rowtype;
  v_name  text := app.clean_line(p_name);
  v_desc  text := nullif(btrim(coalesce(p_description, '')), '');
  v_am    text[];
  v_cov   text[] := coalesce(p_cover_paths, '{}');
  v_logo  text := nullif(btrim(coalesce(p_logo_path, '')), '');
  v_p     text;
begin
  select * into v_h from public.hostels h where h.id = p_hostel_id for update;
  if v_h.id is null or not coalesce(app.owns_hostel(p_hostel_id), false) then
    raise exception 'You can only edit your own PG.' using errcode = '42501';
  end if;
  if not coalesce(app.hostel_writable(p_hostel_id), false) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  perform app.spend('pg_profile', 60, 3600, 'Too many changes in a short time. Try again in a few minutes.');
  if v_name is null or char_length(v_name) not between 2 and 120 then
    raise exception 'Enter a PG name between 2 and 120 characters.' using errcode = 'P0001', hint = 'name';
  end if;
  if v_desc is not null and char_length(v_desc) > 500 then
    raise exception 'Keep the description under 500 characters.' using errcode = 'P0001', hint = 'description';
  end if;
  select coalesce(array_agg(distinct x order by x), '{}') into v_am from unnest(coalesce(p_amenities, '{}')) x;
  if not v_am <@ array['wifi', 'ac', 'food', 'laundry', 'power_backup', 'parking', 'cctv', 'housekeeping',
                       'attached_bathroom', 'hot_water', 'gym', 'study_room']::text[] then
    raise exception 'Unknown amenity.' using errcode = 'P0001', hint = 'amenities';
  end if;
  if v_logo is not null and (not app.pg_media_path_ok(p_hostel_id, 'logo', v_logo)
     or not exists (select 1 from storage.objects o where o.bucket_id = 'pg-media' and o.name = v_logo)) then
    raise exception 'Upload the logo again.' using errcode = 'P0001', hint = 'logo';
  end if;
  if cardinality(v_cov) > 6 then
    raise exception 'Add up to 6 cover photos.' using errcode = 'P0001', hint = 'covers';
  end if;
  if cardinality(v_cov) <> (select count(distinct c) from unnest(v_cov) c)
     or exists (select 1 from unnest(v_cov) c
                 where not coalesce(app.pg_media_path_ok(p_hostel_id, 'cover', c), false)
                    or not exists (select 1 from storage.objects o where o.bucket_id = 'pg-media' and o.name = c)) then
    raise exception 'Upload the cover photos again.' using errcode = 'P0001', hint = 'covers';
  end if;
  if (p_latitude is null) <> (p_longitude is null)
     or (p_latitude is not null and (p_latitude = 'NaN' or p_longitude = 'NaN'
         or p_latitude not between -90 and 90 or p_longitude not between -180 and 180)) then
    raise exception 'Drop the pin on the map again.' using errcode = 'P0001', hint = 'location';
  end if;

  -- Media no longer referenced leaves through the erasure queue.
  if v_h.logo_path is not null and v_h.logo_path is distinct from v_logo then
    perform app.enqueue_storage_erasure('pg-media', v_h.logo_path, p_hostel_id, 'pg.logo_replaced');
  end if;
  foreach v_p in array v_h.cover_paths loop
    if not v_p = any (v_cov) then
      perform app.enqueue_storage_erasure('pg-media', v_p, p_hostel_id, 'pg.cover_removed');
    end if;
  end loop;

  update public.hostels
     set name = v_name, description = v_desc, amenities = v_am, logo_path = v_logo, cover_paths = v_cov,
         listed = coalesce(p_listed, listed),
         latitude = coalesce(round(p_latitude, 6), latitude), longitude = coalesce(round(p_longitude, 6), longitude)
   where id = p_hostel_id
   returning * into v_h;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), 'owner', 'owner.pg_profile.update', 'hostel', p_hostel_id::text, p_hostel_id,
          jsonb_build_object('covers', cardinality(v_cov), 'logo', v_logo is not null, 'listed', v_h.listed, 'surface', 'rpc'));

  return jsonb_build_object('hostel_id', v_h.id, 'name', v_h.name, 'description', v_h.description,
                            'amenities', to_jsonb(v_h.amenities), 'logo_path', v_h.logo_path,
                            'cover_paths', to_jsonb(v_h.cover_paths), 'listed', v_h.listed,
                            'latitude', v_h.latitude, 'longitude', v_h.longitude);
end
$fn$;

create or replace function public.st_save_review(p_rating integer, p_comment text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_st      uuid := app.current_student_id();
  v_hostel  uuid;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  v_row     public.pg_reviews%rowtype;
begin
  select s.hostel_id into v_hostel from public.students s where s.id = v_st and s.user_id = auth.uid();
  if v_hostel is null then
    raise exception 'Only a current tenant can rate their PG.' using errcode = '42501';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Choose 1 to 5 stars.' using errcode = 'P0001', hint = 'rating';
  end if;
  if v_comment is not null and char_length(v_comment) > 300 then
    raise exception 'Keep the review under 300 characters.' using errcode = 'P0001', hint = 'comment';
  end if;
  perform app.spend('pg_review', 20, 3600, 'Too many changes in a short time. Try again in a few minutes.');
  insert into public.pg_reviews (hostel_id, user_id, rating, comment)
  values (v_hostel, auth.uid(), p_rating, v_comment)
  on conflict on constraint pg_reviews_one_per_tenant
  do update set rating = excluded.rating, comment = excluded.comment, updated_at = now()
  returning * into v_row;
  return jsonb_build_object('review_id', v_row.id, 'hostel_id', v_row.hostel_id, 'rating', v_row.rating,
                            'comment', v_row.comment, 'updated_at', v_row.updated_at);
end
$fn$;

create or replace function public.st_my_review()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('review_id', r.id, 'hostel_id', r.hostel_id, 'rating', r.rating, 'comment', r.comment,
                            'updated_at', r.updated_at)
    from public.pg_reviews r
    join public.students s on s.hostel_id = r.hostel_id
   where s.id = app.current_student_id() and r.user_id = auth.uid();
$$;

create or replace function public.pg_review_list(p_hostel_id uuid, p_limit integer default 20, p_offset integer default 0)
returns table (review_id uuid, reviewer_name text, rating smallint, comment text, created_at timestamptz,
               updated_at timestamptz, is_mine boolean)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if not coalesce(app.can_view_pg(p_hostel_id), false) then
    raise exception 'This PG is not available.' using errcode = 'P0001';
  end if;
  return query
    select r.id, split_part(u.full_name, ' ', 1), r.rating, r.comment, r.created_at, r.updated_at, r.user_id = auth.uid()
      from public.pg_reviews r join public.users u on u.id = r.user_id
     where r.hostel_id = p_hostel_id
     order by r.updated_at desc, r.id
     limit greatest(1, least(coalesce(p_limit, 20), 100)) offset greatest(coalesce(p_offset, 0), 0);
end
$fn$;

-- Discovery: same filters as before, plus logo, rating and amenities. Return type grows, so drop + create.
drop function public.st_nearby_hostels(numeric, numeric);
create function public.st_nearby_hostels(p_lat numeric, p_lng numeric)
returns table (hostel_id uuid, name text, property_type text, gender_policy text, locality text, city text,
               distance_km numeric, logo_path text, rating_avg numeric, rating_count integer, amenities text[])
language plpgsql security definer set search_path = '' as $fn$
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
    select q.id, q.name, q.property_type, q.gender_policy, q.locality, q.city, round(q.km::numeric, 1),
           q.logo_path, rt.avg, rt.n, q.amenities
      from (
        select h.id, h.name, h.property_type, h.gender_policy, h.locality, h.city, h.logo_path, h.amenities,
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
      left join lateral (select round(avg(r.rating)::numeric, 1) as avg, count(*)::int as n
                           from public.pg_reviews r where r.hostel_id = q.id) rt on true
     where q.km <= 50
     order by q.km, q.name
     limit 25;
end
$fn$;

drop function public.st_search_hostels(text);
create function public.st_search_hostels(p_query text)
returns table (hostel_id uuid, name text, property_type text, gender_policy text, locality text, city text,
               distance_km numeric, logo_path text, rating_avg numeric, rating_count integer, amenities text[])
language plpgsql security definer set search_path = '' as $fn$
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
    select h.id, h.name, h.property_type, h.gender_policy, h.locality, h.city, null::numeric,
           h.logo_path, rt.avg, rt.n, h.amenities
      from public.hostels h
      left join lateral (select round(avg(r.rating)::numeric, 1) as avg, count(*)::int as n
                           from public.pg_reviews r where r.hostel_id = h.id) rt on true
     where h.listed
       and h.status = 'active'
       and (h.name ilike v_like or h.city ilike v_like or h.locality ilike v_like)
       and app.hostel_writable(h.id)
     order by (h.name ilike v_q || '%') desc, h.name, h.id
     limit 25;
end
$fn$;

-- What a prospective tenant (or staff applicant) sees. No owner contact, address, pincode or pin.
create or replace function public.st_pg_profile(p_hostel_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_h public.hostels%rowtype;
begin
  if not coalesce(app.can_view_pg(p_hostel_id), false) then
    raise exception 'This PG is not available.' using errcode = 'P0001';
  end if;
  select * into v_h from public.hostels h where h.id = p_hostel_id;
  return jsonb_build_object(
    'hostel_id', v_h.id, 'name', v_h.name, 'property_type', v_h.property_type, 'gender_policy', v_h.gender_policy,
    'locality', v_h.locality, 'city', v_h.city, 'description', v_h.description, 'amenities', to_jsonb(v_h.amenities),
    'rules', v_h.rules, 'logo_path', v_h.logo_path, 'cover_paths', to_jsonb(v_h.cover_paths), 'listed', v_h.listed,
    'rating_avg', (select round(avg(r.rating)::numeric, 1) from public.pg_reviews r where r.hostel_id = v_h.id),
    'rating_count', (select count(*) from public.pg_reviews r where r.hostel_id = v_h.id),
    'reviews', coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc)
                           from public.pg_review_list(v_h.id, 10, 0) x), '[]'::jsonb));
end
$fn$;

-- ─── 8. R6: check-out RPCs ────────────────────────────────────────────────────────────────
create or replace function app.checkout_json(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('request_id', r.id, 'hostel_id', r.hostel_id, 'student_id', r.student_id,
                            'preferred_date', r.preferred_date, 'reason', r.reason, 'status', r.status,
                            'checkout_date', r.checkout_date, 'decision_note', r.decision_note,
                            'decided_at', r.decided_at, 'completed_at', r.completed_at, 'created_at', r.created_at)
    from public.checkout_requests r where r.id = p_id;
$$;

create or replace function public.st_request_checkout(p_preferred_date date, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_s      public.students%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_room   text;
  v_id     uuid;
begin
  select * into v_s from public.students s where s.id = app.current_student_id() and s.user_id = auth.uid();
  if v_s.id is null then
    raise exception 'Only a current tenant can request a check-out.' using errcode = '42501';
  end if;
  if p_preferred_date is null or p_preferred_date not between app.today() and app.today() + 90 then
    raise exception 'Choose a date from today up to 90 days ahead.' using errcode = 'P0001', hint = 'date';
  end if;
  if v_reason is not null and char_length(v_reason) > 300 then
    raise exception 'Keep the reason under 300 characters.' using errcode = 'P0001', hint = 'reason';
  end if;
  perform app.spend('checkout_request', 10, 86400, 'Too many requests today. Try again tomorrow.');
  begin
    insert into public.checkout_requests (hostel_id, student_id, user_id, preferred_date, reason)
    values (v_s.hostel_id, v_s.id, auth.uid(), p_preferred_date, v_reason)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'You already have a check-out request.' using errcode = 'P0001';
  end;
  select r.room_number into v_room from public.rooms r where r.id = v_s.room_id;
  perform app.notify_hostel(v_s.hostel_id, true, true, 'Check-out request',
    v_s.full_name || coalesce(' (Room ' || v_room || ')', '') || ' wants to check out on '
      || to_char(p_preferred_date, 'DD Mon YYYY') || '.', '/warden/checkouts', '/owner/checkouts', auth.uid());
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), 'student', 'student.checkout.request', 'student', v_s.id::text, v_s.hostel_id,
          jsonb_build_object('request_id', v_id, 'preferred_date', p_preferred_date, 'surface', 'rpc'));
  return app.checkout_json(v_id);
end
$fn$;

create or replace function public.st_my_checkout_request()
returns jsonb language sql stable security definer set search_path = '' as $$
  select app.checkout_json(r.id)
    from public.checkout_requests r
   where r.user_id = auth.uid()
   order by (r.status in ('pending', 'accepted')) desc, r.created_at desc
   limit 1;
$$;

create or replace function public.st_cancel_checkout_request()
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_id uuid;
  v_hostel uuid;
begin
  update public.checkout_requests r set status = 'cancelled'
   where r.user_id = auth.uid() and r.status = 'pending'
   returning r.id, r.hostel_id into v_id, v_hostel;
  if v_id is null then
    raise exception 'There is no pending check-out request.' using errcode = 'P0001';
  end if;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), 'student', 'student.checkout.cancel', 'checkout_request', v_id::text, v_hostel,
          jsonb_build_object('surface', 'rpc'));
  return app.checkout_json(v_id);
end
$fn$;

create or replace function public.wd_checkout_requests(p_hostel_id uuid, p_status text default null)
returns table (request_id uuid, student_id uuid, full_name text, phone text, room_number text, bed_number integer,
               preferred_date date, reason text, status text, checkout_date date, decided_at timestamptz,
               decision_note text, completed_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if not coalesce(app.has_role_in(p_hostel_id, 'owner', 'warden'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return query
    select r.id, s.id, s.full_name, s.phone, rm.room_number, b.bed_number, r.preferred_date, r.reason, r.status,
           r.checkout_date, r.decided_at, r.decision_note, r.completed_at, r.created_at
      from public.checkout_requests r
      join public.students s on s.id = r.student_id
      left join public.rooms rm on rm.id = s.room_id
      left join public.beds b on b.id = s.bed_id
     where r.hostel_id = p_hostel_id and (p_status is null or r.status = p_status)
     order by case r.status when 'pending' then 0 when 'accepted' then 1 else 2 end, r.created_at desc
     limit 100;
end
$fn$;

create or replace function public.wd_decide_checkout_request(p_request_id uuid, p_accept boolean,
                                                             p_checkout_date date default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_uid  uuid := auth.uid();
  v_r    public.checkout_requests%rowtype;
  v_name text;
  v_note text := app.clean_line(p_note);
  v_date date;
begin
  if p_accept is null then
    raise exception 'Choose accept or decline.' using errcode = '22023';
  end if;
  select * into v_r from public.checkout_requests r where r.id = p_request_id for update;
  if v_r.id is null or not coalesce(app.has_role_in(v_r.hostel_id, 'owner', 'warden'), false) then
    raise exception 'This request is no longer available.' using errcode = 'P0001';
  end if;
  if v_r.status <> 'pending' then
    raise exception 'This request was already handled.' using errcode = 'P0001';
  end if;
  if v_note is not null and char_length(v_note) > 300 then
    raise exception 'Keep the note under 300 characters.' using errcode = 'P0001', hint = 'note';
  end if;
  perform app.spend('checkout_decide', 120, 3600, 'Too many decisions in a short time. Try again in a few minutes.');
  select s.full_name into v_name from public.students s where s.id = v_r.student_id;

  if not p_accept then
    update public.checkout_requests
       set status = 'declined', decided_by = v_uid, decided_at = now(), decision_note = v_note
     where id = v_r.id;
    if v_r.user_id is not null then
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (v_r.hostel_id, v_r.user_id, 'system', 'Check-out request declined',
              'Your check-out request was declined.' || coalesce(' Note: ' || v_note, ''), '/student');
    end if;
    perform app.notify_hostel(v_r.hostel_id, true, true, 'Check-out declined',
      v_name || '''s check-out request was declined.', '/warden/checkouts', '/owner/checkouts', v_uid);
  else
    v_date := coalesce(p_checkout_date, v_r.preferred_date);
    if v_date not between app.today() - 30 and app.today() + 90 then
      raise exception 'Choose a check-out date within 90 days.' using errcode = 'P0001', hint = 'date';
    end if;
    update public.checkout_requests
       set status = 'accepted', checkout_date = v_date, decided_by = v_uid, decided_at = now(), decision_note = v_note
     where id = v_r.id;
    if v_r.user_id is not null then
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (v_r.hostel_id, v_r.user_id, 'system', 'Check-out accepted',
              'Your check-out is set for ' || to_char(v_date, 'DD Mon YYYY') || '.' || coalesce(' Note: ' || v_note, ''),
              '/student');
    end if;
    perform app.notify_hostel(v_r.hostel_id, true, true, 'Check-out accepted',
      v_name || ' checks out on ' || to_char(v_date, 'DD Mon YYYY') || '.', '/warden/checkouts', '/owner/checkouts', v_uid);
    if v_date <= app.today() then
      perform public.wd_vacate_student(v_r.student_id);   -- the existing vacate flow, as the caller
      update public.checkout_requests set status = 'completed', completed_at = now() where id = v_r.id;
    end if;
  end if;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, app.user_role(), case when p_accept then 'warden.checkout.accept' else 'warden.checkout.decline' end,
          'checkout_request', v_r.id::text, v_r.hostel_id,
          jsonb_build_object('student_id', v_r.student_id, 'checkout_date', v_date, 'surface', 'rpc'));
  return app.checkout_json(v_r.id);
end
$fn$;

-- Nightly (cron, as postgres): accepted check-outs whose date has come run the vacate flow.
-- The service-role claim is what lets wd_vacate_student and the users guard act with no person.
create or replace function app.run_due_checkouts()
returns integer language plpgsql security definer set search_path = '' as $fn$
declare
  r   record;
  v_n integer := 0;
begin
  update public.checkout_requests c set status = 'completed', completed_at = now()
    from public.students s
   where s.id = c.student_id and s.status = 'vacated' and c.status in ('pending', 'accepted');

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  for r in
    select c.id, c.student_id, c.hostel_id from public.checkout_requests c
     where c.status = 'accepted' and c.checkout_date <= app.today()
     order by c.checkout_date, c.id
  loop
    begin
      perform public.wd_vacate_student(r.student_id);
      update public.checkout_requests set status = 'completed', completed_at = now() where id = r.id;
      perform app.notify_hostel(r.hostel_id, true, true, 'Checked out',
        (select s.full_name from public.students s where s.id = r.student_id) || ' has checked out.',
        '/warden/checkouts', '/owner/checkouts', null);
      v_n := v_n + 1;
    exception when others then
      raise warning 'run_due_checkouts: request % not completed: %', r.id, sqlerrm;   -- retried tomorrow
    end;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  return v_n;
end
$fn$;

create or replace function public.ow_checkout_summary(p_hostel_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_ids uuid[];
begin
  if app.user_role() is distinct from 'owner' then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_hostel_id is not null and not coalesce(app.owns_hostel(p_hostel_id), false) then
    raise exception 'Hostel not found.' using errcode = 'P0001';
  end if;
  select coalesce(array_agg(x), '{}') into v_ids
    from app.owned_hostel_ids() x where p_hostel_id is null or x = p_hostel_id;
  return jsonb_build_object(
    'pending', (select count(*) from public.checkout_requests r where r.hostel_id = any (v_ids) and r.status = 'pending'),
    'scheduled', (select count(*) from public.checkout_requests r where r.hostel_id = any (v_ids) and r.status = 'accepted'),
    'recent', (select count(*) from public.students s
                where s.hostel_id = any (v_ids) and s.status = 'vacated' and s.vacated_at > now() - interval '30 days'),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object('request_id', q.id, 'hostel_id', q.hostel_id, 'hostel_name', q.hname,
                                          'student_id', q.student_id, 'full_name', q.full_name, 'room_number', q.room_number,
                                          'status', q.status, 'preferred_date', q.preferred_date,
                                          'checkout_date', q.checkout_date, 'completed_at', q.completed_at,
                                          'created_at', q.created_at) order by q.ord, q.created_at desc)
        from (select r.*, h.name as hname, s.full_name, rm.room_number,
                     case r.status when 'pending' then 0 when 'accepted' then 1 else 2 end as ord
                from public.checkout_requests r
                join public.hostels h on h.id = r.hostel_id
                join public.students s on s.id = r.student_id
                left join public.rooms rm on rm.id = s.room_id
               where r.hostel_id = any (v_ids)
                 and (r.status in ('pending', 'accepted')
                      or (r.status = 'completed' and r.completed_at > now() - interval '30 days'))
               order by ord, r.created_at desc
               limit 20) q), '[]'::jsonb));
end
$fn$;

-- ─── 9. R8: staff requests ───────────────────────────────────────────────────────────────
create table public.staff_join_requests (
  id            uuid primary key default gen_random_uuid(),
  hostel_id     uuid not null references public.hostels (id) on delete cascade,
  user_id       uuid not null references public.users (id) on delete cascade,
  message       text constraint staff_join_requests_message_check check (message is null or char_length(message) <= 300),
  status        text not null default 'pending'
                  constraint staff_join_requests_status_check check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  role_granted  public.user_role
                  constraint staff_join_requests_role_check check (role_granted is null or role_granted in ('manager', 'warden')),
  decided_by    uuid references public.users (id) on delete set null,
  decided_at    timestamptz,
  decision_note text constraint staff_join_requests_note_check check (decision_note is null or char_length(decision_note) <= 300),
  created_at    timestamptz not null default now()
);
create unique index staff_join_requests_one_pending on public.staff_join_requests (user_id) where status = 'pending';
create index staff_join_requests_hostel_idx on public.staff_join_requests (hostel_id, status, created_at desc);

create or replace function app.staff_request_json(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('request_id', r.id, 'hostel_id', r.hostel_id, 'hostel_name', h.name, 'city', h.city,
                            'status', r.status, 'role_granted', r.role_granted, 'message', r.message,
                            'decision_note', r.decision_note, 'created_at', r.created_at, 'decided_at', r.decided_at)
    from public.staff_join_requests r join public.hostels h on h.id = r.hostel_id where r.id = p_id;
$$;

create or replace function public.stf_request_join(p_hostel_id uuid, p_message text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_u   public.users%rowtype;
  v_h   public.hostels%rowtype;
  v_msg text := app.clean_line(p_message);
  v_id  uuid;
begin
  select * into v_u from public.users u where u.id = auth.uid() and u.status = 'active' and u.deleted_at is null;
  if v_u.id is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  if not v_u.staff_applicant or v_u.role <> 'student' or v_u.hostel_id is not null then
    raise exception 'Only a staff sign-up account can ask to join a PG as staff.' using errcode = '42501';
  end if;
  if v_msg is not null and char_length(v_msg) > 300 then
    raise exception 'Keep the message under 300 characters.' using errcode = 'P0001', hint = 'message';
  end if;
  perform app.spend('staff_join', 10, 86400, 'Too many requests today. Try again tomorrow.');
  select * into v_h from public.hostels h where h.id = p_hostel_id and h.listed and h.status = 'active';
  if v_h.id is null or not coalesce(app.hostel_writable(v_h.id), false) then
    raise exception 'This PG is not available.' using errcode = 'P0001';
  end if;
  begin
    insert into public.staff_join_requests (hostel_id, user_id, message) values (v_h.id, v_u.id, v_msg)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'You already have a pending request. Cancel it to ask another PG.' using errcode = 'P0001';
  end;
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (v_h.id, v_h.owner_user_id, 'system', 'New staff request',
          v_u.full_name || ' wants to join ' || v_h.name || ' as staff.', '/owner/staff-requests');
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_u.id, 'student', 'staff.join_request.create', 'staff_join_request', v_id::text, v_h.id,
          jsonb_build_object('surface', 'rpc'));
  return app.staff_request_json(v_id);
end
$fn$;

create or replace function public.stf_my_join_request()
returns jsonb language sql stable security definer set search_path = '' as $$
  select app.staff_request_json(r.id) from public.staff_join_requests r
   where r.user_id = auth.uid() order by (r.status = 'pending') desc, r.created_at desc limit 1;
$$;

create or replace function public.stf_cancel_join_request()
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_id uuid;
begin
  update public.staff_join_requests r set status = 'cancelled'
   where r.user_id = auth.uid() and r.status = 'pending' returning r.id into v_id;
  if v_id is null then
    raise exception 'There is no pending request.' using errcode = 'P0001';
  end if;
  return app.staff_request_json(v_id);
end
$fn$;

create or replace function public.ow_staff_requests(p_hostel_id uuid default null, p_status text default 'pending')
returns table (request_id uuid, hostel_id uuid, hostel_name text, user_id uuid, full_name text, phone text, email text,
               message text, status text, role_granted public.user_role, created_at timestamptz,
               decided_at timestamptz, decision_note text)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if app.user_role() is distinct from 'owner' then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return query
    select r.id, r.hostel_id, h.name, r.user_id, u.full_name, u.phone,
           case when app.email_is_reachable(u.email) then u.email end, r.message, r.status, r.role_granted,
           r.created_at, r.decided_at, r.decision_note
      from public.staff_join_requests r
      join public.hostels h on h.id = r.hostel_id
      join public.users u on u.id = r.user_id
     where h.id in (select app.owned_hostel_ids())
       and (p_hostel_id is null or r.hostel_id = p_hostel_id)
       and (p_status is null or r.status = p_status)
     order by r.created_at desc
     limit 100;
end
$fn$;

create or replace function public.ow_pending_staff_request_count()
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.staff_join_requests r
   where r.status = 'pending' and r.hostel_id in (select app.owned_hostel_ids());
$$;

create or replace function public.ow_decide_staff_request(p_request_id uuid, p_accept boolean, p_role text default null,
                                                          p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_uid  uuid := auth.uid();
  v_req  public.staff_join_requests%rowtype;
  v_app  public.users%rowtype;
  v_note text := app.clean_line(p_note);
  v_name text;
begin
  if v_uid is null or app.user_role() is distinct from 'owner' then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_accept is null then
    raise exception 'Choose accept or decline.' using errcode = '22023';
  end if;
  select * into v_req from public.staff_join_requests r where r.id = p_request_id for update;
  if v_req.id is null or not coalesce(app.owns_hostel(v_req.hostel_id), false) then
    raise exception 'This request is no longer available.' using errcode = 'P0001';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'This request was already handled.' using errcode = 'P0001';
  end if;
  if v_note is not null and char_length(v_note) > 300 then
    raise exception 'Keep the note under 300 characters.' using errcode = 'P0001', hint = 'note';
  end if;
  perform app.spend('staff_decide', 60, 3600, 'Too many decisions in a short time. Try again in a few minutes.');
  select h.name into v_name from public.hostels h where h.id = v_req.hostel_id;

  if not p_accept then
    update public.staff_join_requests
       set status = 'declined', decided_by = v_uid, decided_at = now(), decision_note = v_note
     where id = v_req.id;
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (null, v_req.user_id, 'system', 'Staff request declined',
            v_name || ' could not accept your request.' || coalesce(' Note: ' || v_note, ''), '/');
    insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
    values (v_uid, 'owner', 'owner.staff_request.decline', 'staff_join_request', v_req.id::text, v_req.hostel_id,
            jsonb_build_object('surface', 'rpc'));
    return app.staff_request_json(v_req.id);
  end if;

  if p_role is null or p_role not in ('manager', 'warden') then
    raise exception 'Choose Manager or Warden.' using errcode = '22023', hint = 'role';
  end if;
  if not coalesce(app.hostel_writable(v_req.hostel_id), false) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  select * into v_app from public.users u where u.id = v_req.user_id for update;
  if v_app.id is null or not v_app.staff_applicant or v_app.role <> 'student' or v_app.status <> 'active'
     or v_app.deleted_at is not null or v_app.hostel_id is not null then
    raise exception 'This person can no longer join: their account changed or was closed.' using errcode = 'P0001';
  end if;

  update public.staff_join_requests
     set status = 'accepted', role_granted = p_role::public.user_role, decided_by = v_uid, decided_at = now(),
         decision_note = v_note
   where id = v_req.id;
  perform set_config('app.converting_staff', v_app.id::text || ':' || v_req.hostel_id::text, true);
  update public.users set role = p_role::public.user_role, hostel_id = v_req.hostel_id, staff_applicant = false
   where id = v_app.id;
  perform set_config('app.converting_staff', '', true);
  insert into public.staff_hostel_access (user_id, hostel_id, granted_by) values (v_app.id, v_req.hostel_id, v_uid)
  on conflict on constraint staff_hostel_access_pkey do nothing;

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (v_req.hostel_id, v_app.id, 'system', 'Welcome to ' || v_name,
          'You are now a ' || p_role || ' at ' || v_name || '.', '/');
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, 'owner', 'owner.staff_request.accept', 'staff_join_request', v_req.id::text, v_req.hostel_id,
          jsonb_build_object('user_id', v_app.id, 'role', p_role, 'surface', 'rpc'));
  return app.staff_request_json(v_req.id);
end
$fn$;

-- ─── 10. R9: UPI settings and payment claims ──────────────────────────────────────────────
create or replace function public.ow_set_upi_settings(p_hostel_id uuid, p_upi_vpa text, p_payee_name text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_vpa   text := lower(regexp_replace(coalesce(p_upi_vpa, ''), '\s', '', 'g'));
  v_payee text := app.clean_line(p_payee_name);
begin
  if not coalesce(app.owns_hostel(p_hostel_id), false) then
    raise exception 'You can only change your own PG.' using errcode = '42501';
  end if;
  perform app.spend('upi_settings', 20, 3600, 'Too many changes in a short time. Try again in a few minutes.');
  if v_vpa = '' then
    delete from public.hostel_upi_settings where hostel_id = p_hostel_id;
    insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
    values (auth.uid(), 'owner', 'owner.upi.removed', 'hostel', p_hostel_id::text, p_hostel_id, '{"surface":"rpc"}');
    return jsonb_build_object('hostel_id', p_hostel_id, 'upi_vpa', null, 'payee_name', null);
  end if;
  if v_vpa !~ '^[a-z0-9][a-z0-9._-]{1,254}@[a-z][a-z0-9.-]{1,63}$' then
    raise exception 'Enter a valid UPI ID, like name@okhdfcbank.' using errcode = 'P0001', hint = 'upi_vpa';
  end if;
  if v_payee is null or char_length(v_payee) not between 2 and 80 then
    raise exception 'Enter the payee name as your UPI app shows it.' using errcode = 'P0001', hint = 'payee_name';
  end if;
  insert into public.hostel_upi_settings (hostel_id, upi_vpa, payee_name, updated_by, updated_at)
  values (p_hostel_id, v_vpa, v_payee, auth.uid(), now())
  on conflict (hostel_id) do update
    set upi_vpa = excluded.upi_vpa, payee_name = excluded.payee_name, updated_by = excluded.updated_by, updated_at = now();
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), 'owner', 'owner.upi.set', 'hostel', p_hostel_id::text, p_hostel_id,
          jsonb_build_object('handle', split_part(v_vpa, '@', 2), 'surface', 'rpc'));
  return jsonb_build_object('hostel_id', p_hostel_id, 'upi_vpa', v_vpa, 'payee_name', v_payee);
end
$fn$;

-- Owner, wardens and residents of the PG. p_hostel_id null = the caller's own PG.
create or replace function public.hostel_upi_settings(p_hostel_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_h uuid := coalesce(p_hostel_id, app.user_hostel_id());
begin
  if v_h is null or not coalesce(app.has_role_in(v_h, 'owner', 'warden', 'student'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return (select jsonb_build_object('hostel_id', h.id, 'hostel_name', h.name, 'upi_vpa', u.upi_vpa,
                                    'payee_name', u.payee_name, 'updated_at', u.updated_at)
            from public.hostels h join public.hostel_upi_settings u on u.hostel_id = h.id where h.id = v_h);
end
$fn$;

create or replace function app.claim_json(p_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('claim_id', c.id, 'hostel_id', c.hostel_id, 'student_id', c.student_id,
                            'period_month', c.period_month, 'amount', c.amount, 'utr', c.utr, 'upi_vpa', c.upi_vpa,
                            'status', c.status, 'decision_note', c.decision_note, 'decided_at', c.decided_at,
                            'fee_payment_id', c.fee_payment_id, 'created_at', c.created_at)
    from public.payment_claims c where c.id = p_id;
$$;

create or replace function public.st_submit_payment_claim(p_amount numeric, p_period_month text, p_utr text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_s   public.students%rowtype;
  v_upi public.hostel_upi_settings%rowtype;
  v_utr text := upper(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g'));
  v_id  uuid;
begin
  select * into v_s from public.students s where s.id = app.current_student_id() and s.user_id = auth.uid();
  if v_s.id is null then
    raise exception 'Only a current tenant can report a payment.' using errcode = '42501';
  end if;
  select * into v_upi from public.hostel_upi_settings u where u.hostel_id = v_s.hostel_id;
  if v_upi.hostel_id is null then
    raise exception 'This PG has not set up UPI payments yet.' using errcode = 'P0001';
  end if;
  if p_period_month is null or p_period_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or to_date(p_period_month || '-01', 'YYYY-MM-DD') < date_trunc('month', v_s.date_of_joining::timestamp)
     or to_date(p_period_month || '-01', 'YYYY-MM-DD') > date_trunc('month', app.today()::timestamp) + interval '1 month' then
    raise exception 'Choose a month from your check-in month up to next month.' using errcode = 'P0001', hint = 'period_month';
  end if;
  if p_amount is null or p_amount = 'NaN' or p_amount <= 0 or p_amount > 10000000 then
    raise exception 'Enter a valid amount.' using errcode = 'P0001', hint = 'amount';
  end if;
  if v_utr !~ '^[A-Z0-9]{10,22}$' then
    raise exception 'Enter the UTR / transaction ID from your UPI app (usually 12 digits).' using errcode = 'P0001', hint = 'utr';
  end if;
  perform app.spend('payment_claim', 10, 3600, 'Too many payments reported in a short time. Try again later.');
  if (select count(*) from public.payment_claims c where c.student_id = v_s.id and c.status = 'pending') >= 5 then
    raise exception 'You have 5 payments waiting to be confirmed. Wait until they are checked.' using errcode = 'P0001';
  end if;
  begin
    insert into public.payment_claims (hostel_id, student_id, user_id, period_month, amount, utr, upi_vpa)
    values (v_s.hostel_id, v_s.id, auth.uid(), p_period_month, round(p_amount, 2), v_utr, v_upi.upi_vpa)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'This UTR has already been submitted.' using errcode = '23505', hint = 'utr';
  end;
  perform app.notify_hostel(v_s.hostel_id, true, true, 'UPI payment to confirm',
    v_s.full_name || ' says they paid ' || app.inr(round(p_amount, 2)) || ' for ' || app.month_label(p_period_month)
      || ' (UTR ending ' || right(v_utr, 4) || '). Check your UPI app, then confirm it.',
    '/warden/payment-claims', '/owner/payment-claims', auth.uid());
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), 'student', 'student.payment_claim.create', 'payment_claim', v_id::text, v_s.hostel_id,
          jsonb_build_object('student_id', v_s.id, 'period_month', p_period_month, 'amount', round(p_amount, 2), 'surface', 'rpc'));
  return app.claim_json(v_id);
end
$fn$;

create or replace function public.st_my_payment_claims(p_limit integer default 20)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select app.claim_json(c.id) from public.payment_claims c
   where c.user_id = auth.uid()
   order by c.created_at desc
   limit greatest(1, least(coalesce(p_limit, 20), 100));
$$;

create or replace function public.st_cancel_payment_claim(p_claim_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_id uuid;
begin
  update public.payment_claims c set status = 'cancelled'
   where c.id = p_claim_id and c.user_id = auth.uid() and c.status = 'pending' returning c.id into v_id;
  if v_id is null then
    raise exception 'This payment can no longer be cancelled.' using errcode = 'P0001';
  end if;
  return app.claim_json(v_id);
end
$fn$;

create or replace function public.wd_payment_claims(p_hostel_id uuid, p_status text default 'pending')
returns table (claim_id uuid, student_id uuid, full_name text, room_number text, period_month text, amount numeric,
               utr text, upi_vpa text, status text, decision_note text, decided_at timestamptz,
               fee_payment_id uuid, created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if not coalesce(app.has_role_in(p_hostel_id, 'owner', 'warden'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return query
    select c.id, s.id, s.full_name, rm.room_number, c.period_month, c.amount, c.utr, c.upi_vpa, c.status,
           c.decision_note, c.decided_at, c.fee_payment_id, c.created_at
      from public.payment_claims c
      join public.students s on s.id = c.student_id
      left join public.rooms rm on rm.id = s.room_id
     where c.hostel_id = p_hostel_id and (p_status is null or c.status = p_status)
     order by (c.status = 'pending') desc, c.created_at desc
     limit 200;
end
$fn$;

create or replace function public.wd_decide_payment_claim(p_claim_id uuid, p_confirm boolean, p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_c    public.payment_claims%rowtype;
  v_note text := app.clean_line(p_note);
  v_fp   public.fee_payments%rowtype;
begin
  if p_confirm is null then
    raise exception 'Choose confirm or reject.' using errcode = '22023';
  end if;
  select * into v_c from public.payment_claims c where c.id = p_claim_id for update;
  if v_c.id is null or not coalesce(app.has_role_in(v_c.hostel_id, 'owner', 'warden'), false) then
    raise exception 'This payment is no longer available.' using errcode = 'P0001';
  end if;
  if v_c.status <> 'pending' then
    raise exception 'This payment was already handled.' using errcode = 'P0001';
  end if;
  if v_note is not null and char_length(v_note) > 300 then
    raise exception 'Keep the note under 300 characters.' using errcode = 'P0001', hint = 'note';
  end if;
  perform app.spend('claim_decide', 200, 3600, 'Too many decisions in a short time. Try again in a few minutes.');

  if p_confirm then
    -- The existing recording path: its checks, receipts and dues apply unchanged.
    v_fp := public.wd_record_payment(v_c.student_id, v_c.period_month, v_c.amount, 'upi'::public.payment_mode,
                                     (v_c.created_at at time zone 'Asia/Kolkata')::date, 'UPI UTR ' || v_c.utr);
    update public.payment_claims
       set status = 'confirmed', decided_by = auth.uid(), decided_at = now(), decision_note = v_note, fee_payment_id = v_fp.id
     where id = v_c.id;
  else
    if v_note is null or char_length(v_note) < 3 then
      raise exception 'Add a note saying why it was not found.' using errcode = 'P0001', hint = 'note';
    end if;
    update public.payment_claims
       set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = v_note
     where id = v_c.id;
  end if;
  if v_c.user_id is not null then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (v_c.hostel_id, v_c.user_id, 'fee',
            case when p_confirm then 'Payment confirmed' else 'Payment not confirmed' end,
            app.inr(v_c.amount) || ' for ' || app.month_label(v_c.period_month)
              || case when p_confirm then ' was received.' else ' could not be found.' end
              || coalesce(' Note: ' || v_note, ''), '/student');
  end if;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), app.user_role(), case when p_confirm then 'warden.payment_claim.confirm' else 'warden.payment_claim.reject' end,
          'payment_claim', v_c.id::text, v_c.hostel_id,
          jsonb_build_object('student_id', v_c.student_id, 'amount', v_c.amount, 'fee_payment_id', v_fp.id, 'surface', 'rpc'));
  return app.claim_json(v_c.id);
end
$fn$;

-- ─── 11. R7: deletion log, Super Admin lists, permanent delete ────────────────────────────
create table public.account_deletions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  full_name   text not null,
  role        public.user_role,
  hostel_id   uuid,
  hostel_name text,
  kind        text not null constraint account_deletions_kind_check
                check (kind in ('owner_deleted_staff', 'self_request', 'self_deleted', 'sa_deleted', 'deleted')),
  reason      text,
  by_user_id  uuid,
  by_name     text,
  at          timestamptz not null default now(),
  purged_at   timestamptz
);
create index account_deletions_at_idx on public.account_deletions (at desc);
create index account_deletions_user_idx on public.account_deletions (user_id);

-- A profile tombstoned (deleted_at set) or deleted by its owner is logged with its name as it was.
create or replace function app.users_deletion_log()
returns trigger language plpgsql security definer set search_path = '' as $fn$
declare
  v_kind  text;
  v_actor uuid;
begin
  if tg_op = 'DELETE' then
    if old.id is distinct from auth.uid() then
      return null;
    end if;
    v_kind := 'self_deleted';
    v_actor := old.id;
  else
    if old.deleted_at is not null or new.deleted_at is null then
      return null;
    end if;
    v_kind := coalesce(nullif(current_setting('app.deletion_kind', true), ''),
                       case when old.role in ('manager', 'warden') then 'owner_deleted_staff' else 'deleted' end);
    v_actor := coalesce(nullif(current_setting('app.deletion_actor', true), '')::uuid, auth.uid());
  end if;
  insert into public.account_deletions (user_id, full_name, role, hostel_id, hostel_name, kind, reason, by_user_id, by_name)
  values (old.id, case when tg_op = 'DELETE' then 'Deleted user' else old.full_name end, old.role, old.hostel_id,
          (select h.name from public.hostels h where h.id = old.hostel_id), v_kind,
          nullif(current_setting('app.deletion_reason', true), ''), v_actor,
          (select u.full_name from public.users u where u.id = v_actor and u.id <> old.id));
  return null;
end
$fn$;
create trigger users_deletion_log
  after update of deleted_at or delete on public.users
  for each row execute function app.users_deletion_log();

-- Fills in who deleted a staff member, and records self-deletion requests.
create or replace function app.audit_deletion_log()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if new.action = 'owner.staff.deleted' then
    update public.account_deletions d
       set by_user_id = new.actor_user_id, kind = 'owner_deleted_staff',
           by_name = (select u.full_name from public.users u where u.id = new.actor_user_id)
     where d.user_id = new.target_id::uuid and d.at = now() and d.purged_at is null;
  else
    insert into public.account_deletions (user_id, full_name, role, hostel_id, hostel_name, kind, by_user_id, by_name, at)
    select u.id, u.full_name, u.role, new.hostel_id, (select h.name from public.hostels h where h.id = new.hostel_id),
           'self_request', u.id, u.full_name, new.at
      from public.users u where u.id = new.actor_user_id;
  end if;
  return null;
end
$fn$;
create trigger audit_log_deletion_log
  after insert on public.audit_log
  for each row when (new.action in ('owner.staff.deleted', 'account.deletion.requested'))
  execute function app.audit_deletion_log();

-- History so far, from the audit trail.
insert into public.account_deletions (user_id, full_name, role, hostel_id, hostel_name, kind, by_user_id, by_name, at)
select a.target_id::uuid,
       case when a.action = 'account.deleted.self' then 'Deleted user' else coalesce(u.full_name, 'Deleted user') end,
       coalesce(u.role, a.actor_role), a.hostel_id, h.name,
       case a.action when 'owner.staff.deleted' then 'owner_deleted_staff'
                     when 'account.deletion.requested' then 'self_request' else 'self_deleted' end,
       case when a.action = 'account.deleted.self' then a.target_id::uuid else a.actor_user_id end,
       ab.full_name, a.at
  from public.audit_log a
  left join public.users u on u.id = a.target_id::uuid
  left join public.users ab on ab.id = a.actor_user_id
  left join public.hostels h on h.id = a.hostel_id
 where a.action in ('owner.staff.deleted', 'account.deletion.requested', 'account.deleted.self')
   and a.target_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   and coalesce(a.meta ->> 'repeat', 'false') <> 'true';

create or replace function public.sa_signups(p_from date default null, p_to date default null,
                                             p_plan_status text default null, p_demo_status text default null,
                                             p_limit integer default 50, p_offset integer default 0)
returns table (user_id uuid, full_name text, phone text, email text, signup_source text, signed_up_at timestamptz,
               hostel_id uuid, hostel_name text, hostel_city text, trial_start date, trial_end date, plan_status text,
               plan_end date, demo_id uuid, demo_slot timestamptz, demo_bed_band text, demo_status text, total_count bigint)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_plan_status is not null and p_plan_status not in ('no_pg', 'trial', 'paid', 'manual', 'expired') then
    raise exception 'Unknown plan status.' using errcode = '22023';
  end if;
  if p_demo_status is not null and p_demo_status not in ('none', 'requested', 'confirmed', 'done', 'no_show', 'cancelled') then
    raise exception 'Unknown demo status.' using errcode = '22023';
  end if;
  return query
    with base as (
      select u.id, u.full_name, u.phone, case when app.email_is_reachable(u.email) then u.email end as email,
             u.signup_source, u.created_at, h.id as hid, h.name as hname, h.city as hcity,
             t.start_date as t_start, t.end_date as t_end, s.kind as s_kind, s.end_date as s_end,
             d.id as did, d.slot_start as dslot, d.bed_band as dband, d.status as dstatus
        from public.users u
        left join lateral (select x.id, x.name, x.city from public.hostels x
                            where x.owner_user_id = u.id order by x.created_at limit 1) h on true
        left join lateral (select x.start_date, x.end_date from public.subscriptions x
                            where x.owner_user_id = u.id and x.kind = 'trial' order by x.start_date limit 1) t on true
        left join lateral (select x.kind, x.end_date from public.subscriptions x
                            where x.hostel_id = h.id and x.cancelled_at is null order by x.end_date desc limit 1) s on true
        left join lateral (select x.id, x.slot_start, x.bed_band, x.status from public.demo_requests x
                            where x.owner_user_id = u.id order by x.created_at desc limit 1) d on true
       where u.role = 'owner' and u.signup_source <> 'admin' and u.deleted_at is null
         and (p_from is null or u.created_at >= (p_from::timestamp at time zone 'Asia/Kolkata'))
         and (p_to is null or u.created_at < ((p_to + 1)::timestamp at time zone 'Asia/Kolkata'))
    ), rated as (
      select b.*, case when b.hid is null then 'no_pg'
                       when b.s_end is null or b.s_end < app.today() then 'expired'
                       when b.s_kind = 'trial' then 'trial'
                       when b.s_kind = 'paid' then 'paid'
                       else 'manual' end as pstatus
        from base b
    )
    select r.id, r.full_name, r.phone, r.email, r.signup_source, r.created_at, r.hid, r.hname, r.hcity, r.t_start,
           r.t_end, r.pstatus, r.s_end, r.did, r.dslot, r.dband, r.dstatus, count(*) over ()
      from rated r
     where (p_plan_status is null or r.pstatus = p_plan_status)
       and (p_demo_status is null or coalesce(r.dstatus, 'none') = p_demo_status)
     order by r.created_at desc, r.id
     limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(coalesce(p_offset, 0), 0);
end
$fn$;

create or replace function public.sa_deleted_accounts(p_kind text default null, p_from date default null,
                                                      p_to date default null, p_limit integer default 50,
                                                      p_offset integer default 0)
returns table (id uuid, user_id uuid, full_name text, role public.user_role, hostel_id uuid, hostel_name text, kind text,
               reason text, by_user_id uuid, by_name text, at timestamptz, purged_at timestamptz, can_purge boolean,
               total_count bigint)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return query
    select d.id, d.user_id, d.full_name, d.role, d.hostel_id, d.hostel_name, d.kind, d.reason, d.by_user_id, d.by_name,
           d.at, d.purged_at,
           exists (select 1 from public.users u where u.id = d.user_id and u.role <> 'super_admin')
             and not exists (select 1 from public.account_deletions p where p.user_id = d.user_id and p.purged_at is not null),
           count(*) over ()
      from public.account_deletions d
     where (p_kind is null or d.kind = p_kind)
       and (p_from is null or d.at >= (p_from::timestamp at time zone 'Asia/Kolkata'))
       and (p_to is null or d.at < ((p_to + 1)::timestamp at time zone 'Asia/Kolkata'))
     order by d.at desc, d.id
     limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(coalesce(p_offset, 0), 0);
end
$fn$;

-- Erases the person: login (soft-deleted the way GoTrue does, so the tombstone keeps its key),
-- profile PII, photos, documents, reviews, requests. Keeps fee payments, receipts, claims,
-- subscriptions and the audit trail, which now point at "Deleted user".
create or replace function public.sa_purge_account(p_user uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_uid    uuid := auth.uid();
  v_t      public.users%rowtype;
  v_reason text := app.clean_line(p_reason);
begin
  if v_uid is null or not coalesce(app.is_super_admin(), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if v_reason is null or char_length(v_reason) not between 5 and 300 then
    raise exception 'Give a reason between 5 and 300 characters.' using errcode = 'P0001', hint = 'reason';
  end if;
  select * into v_t from public.users u where u.id = p_user for update;
  if v_t.id is null then
    raise exception 'Account not found.' using errcode = 'P0001';
  end if;
  if v_t.role = 'super_admin' then
    raise exception 'A Super Admin account cannot be deleted here.' using errcode = '42501';
  end if;
  if exists (select 1 from public.account_deletions d where d.user_id = p_user and d.purged_at is not null) then
    raise exception 'This account was already permanently deleted.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.students s where s.user_id = p_user and s.status <> 'vacated') then
    raise exception 'This tenant is still checked in. Check them out of their PG first.' using errcode = 'P0001';
  end if;
  if v_t.role = 'owner' and exists (select 1 from public.students s join public.hostels h on h.id = s.hostel_id
                                     where h.owner_user_id = p_user and s.status <> 'vacated') then
    raise exception 'This owner still has residents in a PG. Check them out or suspend the PG first.' using errcode = 'P0001';
  end if;
  perform app.spend('sa_purge', 30, 3600, 'Too many deletions in a short time. Try again later.');

  -- Their roster rows: emptied, not deleted (the ledger hangs on them). Same as app.erase_student.
  perform app.enqueue_storage_erasure('student-docs', s.photo_url, s.hostel_id, 'purge.student_photo'),
          app.enqueue_storage_erasure('student-docs', s.id_proof_url, s.hostel_id, 'purge.student_id_proof')
     from public.students s where s.user_id = p_user;
  perform app.enqueue_storage_erasure('complaint-photos', c.photo_url, c.hostel_id, 'purge.complaint_photo')
     from public.complaints c join public.students s on s.id = c.student_id
    where s.user_id = p_user and c.photo_url is not null;
  delete from public.complaints c using public.students s where s.id = c.student_id and s.user_id = p_user;
  delete from public.leaves l using public.students s where s.id = l.student_id and s.user_id = p_user;
  delete from public.visitors v using public.students s where s.id = v.student_id and s.user_id = p_user;
  update public.students s
     set full_name = 'Erased resident', phone = 'erased-' || replace(s.id::text, '-', ''), email = null,
         photo_url = null, guardian_name = null, guardian_phone = null, permanent_address = null,
         id_proof_type = null, id_proof_url = null, erased_at = coalesce(s.erased_at, now())
   where s.user_id = p_user;

  -- Their own things (file deletions are queued by the existing triggers).
  delete from public.user_documents where user_id = p_user;
  delete from public.external_identities where user_id = p_user;
  delete from public.push_devices where user_id = p_user;
  delete from public.notifications where user_id = p_user;
  delete from public.staff_hostel_access where user_id = p_user;
  delete from public.hostel_join_requests where user_id = p_user;
  delete from public.staff_join_requests where user_id = p_user;
  delete from public.demo_requests where owner_user_id = p_user;
  delete from public.pg_reviews where user_id = p_user;
  update public.checkout_requests set reason = null where user_id = p_user;

  perform set_config('app.deletion_kind', 'sa_deleted', true);
  perform set_config('app.deletion_actor', v_uid::text, true);
  perform set_config('app.deletion_reason', v_reason, true);
  perform set_config('app.setting_avatar', p_user::text, true);
  update public.users
     set full_name = 'Deleted user', email = null, phone = null, avatar_path = null, gender = null, date_of_birth = null,
         emergency_contact_name = null, emergency_contact_phone = null, city = null, pincode = null,
         status = 'inactive', deleted_at = coalesce(deleted_at, now())
   where id = p_user;
  if not exists (select 1 from public.account_deletions d where d.user_id = p_user and d.kind = 'sa_deleted' and d.at = now()) then
    insert into public.account_deletions (user_id, full_name, role, hostel_id, hostel_name, kind, reason, by_user_id, by_name)
    values (p_user, 'Deleted user', v_t.role, v_t.hostel_id, (select h.name from public.hostels h where h.id = v_t.hostel_id),
            'sa_deleted', v_reason, v_uid, (select u.full_name from public.users u where u.id = v_uid));
  end if;
  update public.account_deletions set full_name = 'Deleted user', purged_at = now() where user_id = p_user;
  perform set_config('app.deletion_kind', '', true);
  perform set_config('app.deletion_actor', '', true);
  perform set_config('app.deletion_reason', '', true);
  perform set_config('app.setting_avatar', '', true);

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

  update public.audit_log set actor_user_id = null where actor_user_id = p_user;
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, 'super_admin', 'sa.account.purged', 'user', p_user::text, v_t.hostel_id,
          jsonb_build_object('role', v_t.role, 'surface', 'rpc'));
  return jsonb_build_object('user_id', p_user, 'role', v_t.role, 'purged', true);
end
$fn$;

-- ─── 12. Who can read what (no client writes on any new table) ────────────────────────────
alter table public.checkout_requests   enable row level security;
alter table public.hostel_upi_settings enable row level security;
alter table public.payment_claims      enable row level security;
alter table public.pg_reviews          enable row level security;
alter table public.staff_join_requests enable row level security;
alter table public.account_deletions   enable row level security;

revoke all on table public.checkout_requests, public.hostel_upi_settings, public.payment_claims, public.pg_reviews,
                    public.staff_join_requests, public.account_deletions
  from public, anon, authenticated;
grant select on table public.checkout_requests, public.payment_claims, public.staff_join_requests, public.account_deletions
  to authenticated;
grant select, insert, update, delete on table public.checkout_requests, public.hostel_upi_settings, public.payment_claims,
                                              public.pg_reviews, public.staff_join_requests, public.account_deletions
  to service_role;

create policy checkout_requests_select on public.checkout_requests for select to authenticated
  using (user_id = (select auth.uid()) or (select app.is_super_admin())
         or hostel_id in (select app.owned_hostel_ids())
         or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'));
create policy payment_claims_select on public.payment_claims for select to authenticated
  using (user_id = (select auth.uid()) or (select app.is_super_admin())
         or hostel_id in (select app.owned_hostel_ids())
         or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'));
create policy staff_join_requests_select on public.staff_join_requests for select to authenticated
  using (user_id = (select auth.uid()) or (select app.is_super_admin()) or hostel_id in (select app.owned_hostel_ids()));
create policy account_deletions_select on public.account_deletions for select to authenticated
  using ((select app.is_super_admin()));

-- ─── 13. Nightly check-outs (00:05 IST) ───────────────────────────────────────────────────
select cron.schedule('apnivaas-due-checkouts', '35 18 * * *', 'select app.run_due_checkouts()');

-- ─── 14. Grants (every revoke names anon: Supabase grants new public functions to it) ─────
revoke all on function app.inr(numeric), app.month_label(text),
                       app.notify_hostel(uuid, boolean, boolean, text, text, text, text, uuid),
                       app.external_signin_allowed(uuid), app.join_request_not_applicant(), app.readable_student(uuid),
                       app.students_room_audit(), app.pg_media_path_ok(uuid, text, text), app.can_view_pg(uuid),
                       app.can_upload_pg_media(text), app.checkout_json(uuid), app.run_due_checkouts(),
                       app.staff_request_json(uuid), app.claim_json(uuid), app.users_deletion_log(), app.audit_deletion_log()
  from public, anon;
grant execute on function app.can_view_pg(uuid), app.can_upload_pg_media(text), app.pg_media_path_ok(uuid, text, text)
  to authenticated, service_role;

do $grants$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in (
         'svc_create_self_signup_profile', 'svc_external_signin_allowed', 'svc_secure_unverified_account',
         'rpc_student_fee_months', 'st_timeline',
         'ow_update_pg_profile', 'st_save_review', 'st_my_review', 'pg_review_list', 'st_pg_profile',
         'st_nearby_hostels', 'st_search_hostels',
         'st_request_checkout', 'st_my_checkout_request', 'st_cancel_checkout_request', 'wd_checkout_requests',
         'wd_decide_checkout_request', 'ow_checkout_summary',
         'sa_signups', 'sa_deleted_accounts', 'sa_purge_account',
         'stf_request_join', 'stf_my_join_request', 'stf_cancel_join_request', 'ow_staff_requests',
         'ow_pending_staff_request_count', 'ow_decide_staff_request',
         'ow_set_upi_settings', 'hostel_upi_settings', 'st_submit_payment_claim', 'st_my_payment_claims',
         'st_cancel_payment_claim', 'wd_payment_claims', 'wd_decide_payment_claim')
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

-- ─── 15. What live looks like afterwards, or no commit ────────────────────────────────────
do $verify$
declare
  v_n int;
begin
  select count(*) into v_n
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in (
       'svc_create_self_signup_profile', 'svc_external_signin_allowed', 'svc_secure_unverified_account',
       'rpc_student_fee_months', 'st_timeline',
       'ow_update_pg_profile', 'st_save_review', 'st_my_review', 'pg_review_list', 'st_pg_profile',
       'st_nearby_hostels', 'st_search_hostels',
       'st_request_checkout', 'st_my_checkout_request', 'st_cancel_checkout_request', 'wd_checkout_requests',
       'wd_decide_checkout_request', 'ow_checkout_summary',
       'sa_signups', 'sa_deleted_accounts', 'sa_purge_account',
       'stf_request_join', 'stf_my_join_request', 'stf_cancel_join_request', 'ow_staff_requests',
       'ow_pending_staff_request_count', 'ow_decide_staff_request',
       'ow_set_upi_settings', 'hostel_upi_settings', 'st_submit_payment_claim', 'st_my_payment_claims',
       'st_cancel_payment_claim', 'wd_payment_claims', 'wd_decide_payment_claim')
     and p.prosecdef
     and p.proconfig = array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute') = (p.proname not like 'svc\_%')
     and has_function_privilege('service_role', p.oid, 'execute');
  if v_n <> 34 then
    raise exception 'expected 34 new RPCs with the right security and grants, found %', v_n;
  end if;
  if exists (select 1 from pg_class c
              where c.oid in ('public.checkout_requests'::regclass, 'public.hostel_upi_settings'::regclass,
                              'public.payment_claims'::regclass, 'public.pg_reviews'::regclass,
                              'public.staff_join_requests'::regclass, 'public.account_deletions'::regclass)
                and not c.relrowsecurity) then
    raise exception 'a new table is missing row-level security';
  end if;
  if exists (select 1 from information_schema.role_table_grants g
              where g.table_schema = 'public'
                and g.table_name in ('checkout_requests', 'hostel_upi_settings', 'payment_claims', 'pg_reviews',
                                     'staff_join_requests', 'account_deletions')
                and (g.grantee = 'anon' or (g.grantee = 'authenticated' and g.privilege_type <> 'SELECT'))) then
    raise exception 'a client role can write a new table';
  end if;
  if exists (select 1 from storage.buckets b where b.id = 'pg-media' and b.public) then
    raise exception 'pg-media is public';
  end if;
  if position('converting_staff' in (select prosrc from pg_proc where oid = 'app.users_update_guard()'::regprocedure)) = 0
     or position('external_signin_allowed' in (select prosrc from pg_proc where oid = 'app.guard_external_identity()'::regprocedure)) = 0
     or position('date_of_joining' in (select prosrc from pg_proc where oid = 'public.rpc_fee_ledger(uuid,text)'::regprocedure)) = 0 then
    raise exception 'a redefined routine did not take its new body';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261026100000', 'round3') on conflict (version) do nothing;

notify pgrst, 'reload schema';

commit;

-- AFTER APPLYING: run 2026-10-26-round3.test.sql (rolls itself back, ends 'ALL ROUND 3 TESTS PASSED'),
-- apply 2026-10-26-legal-version-round3.sql, then deploy mobile-auth.
