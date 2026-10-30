-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 2026-10-31 — ROUND 4 backend (docs/round4-spec.md R4.1, R4.2). App contract: docs/round4-api.md.
--   R4.1 accepting a join request records the monthly rent + due day in the same call; a list of
--        residents whose rent is not set; no dues while rent is unset (ledger, fee months, timeline,
--        reminders, desk payments); a rent change applies from the next unbilled month (earlier
--        unbilled months are frozen at the old rent first), so paid history is never rewritten.
--   R4.2 wd_update_tenant_profile: a warden/owner edits a tenant's details (never role, PG or login email).
-- Redefined live routines are md5-checked (bodies read with pg_get_functiondef 2026-10-31); small
-- changes are applied as exact one-occurrence text patches of the live body.
-- Undo: 2026-10-31-round4.down.sql. Tests: 2026-10-31-round4.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;
set local lock_timeout = '10s';

do $guard$
declare
  v_expected constant jsonb := jsonb_build_object(
    'public.rpc_fee_ledger(uuid,text)',                                   'e4189e5c0bf0aab2574332a5ac8f89b8',
    'public.rpc_student_fee_months(uuid)',                                '652e035cc2a37b9f6d6665018bd6fea2',
    'public.st_timeline(uuid)',                                           '817be61e6b7063e2843ac57556eea495',
    'app.send_rent_reminders()',                                          '66924f80199d5fd57674e25489e12958',
    'public.wd_record_payment(uuid,text,numeric,payment_mode,date,text)', 'd77c98c45f78e7176dc7c020ab9ab6cf',
    'public.ow_decide_join_request(uuid,boolean,text)',                   'f6b1d876a7fefe9bd7b6828dbacd8667');
  k text;
  v_md5 text;
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  for k in select jsonb_object_keys(v_expected) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = k::regprocedure;
    if v_md5 is distinct from v_expected ->> k then
      raise exception '% is not the body measured on 2026-10-31 (md5 %); nothing changed', k, v_md5;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'students' and column_name = 'rent_due_day') then
    raise exception 'public.students.rent_due_day already exists: this migration has already run';
  end if;
end
$guard$;

-- Replaces p_from (which must occur exactly once in the live definition) and re-creates the routine.
create or replace function pg_temp.r4_patch(p_fn regprocedure, p_from text, p_to text)
returns void language plpgsql as $$
declare v_def text := pg_get_functiondef(p_fn);
begin
  if (length(v_def) - length(replace(v_def, p_from, ''))) <> length(p_from) then
    raise exception 'r4 patch: % does not contain the expected text exactly once; nothing changed', p_fn;
  end if;
  execute replace(v_def, p_from, p_to);
end $$;

-- ─── 1. Per-resident due day (NULL = the PG's rent_due_day) ───────────────────────────────
alter table public.students
  add column rent_due_day smallint constraint students_rent_due_day_check check (rent_due_day between 1 and 28);
comment on column public.students.rent_due_day is
  'Day of the month this resident''s rent is due (1-28). NULL follows hostels.rent_due_day.';

create function app.check_rent(p_fee numeric, p_day integer)
returns void language plpgsql immutable set search_path = '' as $$
begin
  if p_fee is null or p_fee = 'NaN' or p_fee < 1 or p_fee > 1000000 then
    raise exception 'Enter the monthly rent (₹1 to ₹10,00,000).' using errcode = 'P0001', hint = 'monthly_fee';
  end if;
  if p_day is not null and p_day not between 1 and 28 then
    raise exception 'Choose a due day from 1 to 28.' using errcode = 'P0001', hint = 'due_day';
  end if;
end $$;

-- First month the current rent of a resident does not yet cover: a month is billed once it has a
-- fee row or its due date (never before check-in) is in the past.
create function app.first_unbilled_month(p_student_id uuid)
returns date language plpgsql stable security definer set search_path = '' as $$
declare
  v   public.students%rowtype;
  v_day int;
  m   date;
begin
  select * into v from public.students s where s.id = p_student_id;
  if v.monthly_fee <= 0 then
    return date_trunc('month', v.date_of_joining)::date;
  end if;
  select coalesce(v.rent_due_day, h.rent_due_day, 5) into v_day from public.hostels h where h.id = v.hostel_id;
  m := greatest(date_trunc('month', v.date_of_joining), date_trunc('month', app.today()))::date;
  for i in 1..36 loop
    exit when greatest(make_date(extract(year from m)::int, extract(month from m)::int, v_day), v.date_of_joining) >= app.today()
          and not exists (select 1 from public.fee_payments f where f.student_id = v.id and f.period_month = to_char(m, 'YYYY-MM'));
    m := (m + interval '1 month')::date;
  end loop;
  return m;
end $$;

-- A rent change never rewrites a billed month: those still without a fee row are frozen at the OLD
-- rent before the new one takes over. Rent going from unset (0) to a value bills from check-in.
create function app.students_rent_freeze()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_day int;
  v_to  date := case when old.status = 'vacated'
                     then coalesce((old.vacated_at at time zone 'Asia/Kolkata')::date, app.today()) else app.today() end;
begin
  if old.monthly_fee > 0 and new.monthly_fee is distinct from old.monthly_fee then
    select coalesce(old.rent_due_day, h.rent_due_day, 5) into v_day from public.hostels h where h.id = old.hostel_id;
    insert into public.fee_payments (hostel_id, student_id, period_month, amount_due, amount_paid, recorded_by)
    select old.hostel_id, old.id, to_char(m, 'YYYY-MM'), old.monthly_fee, 0, auth.uid()
      from generate_series(date_trunc('month', old.date_of_joining::timestamp), date_trunc('month', v_to::timestamp),
                           interval '1 month') m
     where greatest(make_date(extract(year from m)::int, extract(month from m)::int, v_day), old.date_of_joining) < app.today()
    on conflict (student_id, period_month) do nothing;
  end if;
  return new;
end $$;
create trigger students_rent_freeze after update of monthly_fee on public.students
  for each row execute function app.students_rent_freeze();

-- ─── 2. No dues while rent is unset ───────────────────────────────────────────────────────
select pg_temp.r4_patch('public.rpc_fee_ledger(uuid,text)',
  $p$'YYYY-MM-DD') + interval '1 month')$p$,
  $p$'YYYY-MM-DD') + interval '1 month')$p$ || E'\n    and (s.monthly_fee > 0 or fp.id is not null)');

select pg_temp.r4_patch('public.rpc_student_fee_months(uuid)',
  $p$     order by 1 desc;$p$,
  E'     where fp.id is not null or v.monthly_fee > 0\n     order by 1 desc;');

select pg_temp.r4_patch('public.wd_record_payment(uuid,text,numeric,payment_mode,date,text)',
  $p$  insert into public.fee_payments (hostel_id, student_id, period_month, amount_due, amount_paid, paid_on, mode, notes, recorded_by)$p$,
  E'  if coalesce(v_fee, 0) <= 0 and not exists (select 1 from public.fee_payments f\n'
  || E'      where f.student_id = p_student_id and f.period_month = p_period_month and f.amount_due > 0) then\n'
  || E'    raise exception ''Set this resident''''s monthly rent before recording a payment.'' using errcode = ''P0001'', hint = ''monthly_fee'';\n'
  || E'  end if;\n'
  || $p$  insert into public.fee_payments (hostel_id, student_id, period_month, amount_due, amount_paid, paid_on, mode, notes, recorded_by)$p$);

-- Per-resident due day in reminders and the timeline.
select pg_temp.r4_patch('app.send_rent_reminders()',
  $p$s.hostel_id, h.rent_due_day,$p$,
  $p$s.hostel_id, coalesce(s.rent_due_day, h.rent_due_day) as rent_due_day,$p$);

select pg_temp.r4_patch('public.st_timeline(uuid)',
  $p$coalesce(h.rent_due_day, 1)$p$,
  $p$coalesce(v.rent_due_day, h.rent_due_day, 1)$p$);

-- ─── 3. Accept a join request with rent (old 3-argument calls still work: rent left unset) ─
drop function public.ow_decide_join_request(uuid, boolean, text);
create function public.ow_decide_join_request(p_request_id uuid, p_accept boolean, p_note text default null,
                                              p_monthly_fee numeric default null, p_due_day integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
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

  -- Round 4: rent is optional for old clients; when given it must be valid.
  if p_monthly_fee is not null or p_due_day is not null then
    perform app.check_rent(coalesce(p_monthly_fee, 1), p_due_day);
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
                                 date_of_joining, monthly_fee, rent_due_day, created_by)
    values (v_req.hostel_id, v_tenant.id, v_tenant.full_name, v_tenant.phone,
            case when app.email_is_reachable(v_tenant.email) then v_tenant.email end,
            v_tenant.emergency_contact_name, v_tenant.emergency_contact_phone, app.today(),
            coalesce(round(p_monthly_fee, 2), 0), p_due_day, v_uid)
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
          jsonb_build_object('student_id', v_student, 'user_id', v_tenant.id, 'surface', 'rpc',
                             'monthly_fee', coalesce(round(p_monthly_fee, 2), 0), 'rent_due_day', p_due_day));

  return jsonb_build_object('request_id', v_req.id, 'status', 'accepted', 'student_id', v_student,
                            'monthly_fee', coalesce(round(p_monthly_fee, 2), 0), 'rent_due_day', p_due_day);
end
$fn$;

-- ─── 4. Residents whose rent is not set ───────────────────────────────────────────────────
create function public.wd_residents_needing_rent(p_hostel_id uuid default null)
returns table (student_id uuid, hostel_id uuid, hostel_name text, full_name text, phone text, photo_url text,
               room_number text, bed_number integer, date_of_joining date, has_account boolean)
language plpgsql stable security definer set search_path = '' as $fn$
#variable_conflict use_column
begin
  if auth.uid() is null or coalesce(app.user_role()::text, '') not in ('owner', 'warden', 'super_admin') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if p_hostel_id is not null and not coalesce(app.has_role_in(p_hostel_id, 'owner', 'warden'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return query
    select s.id, s.hostel_id, h.name, s.full_name, s.phone, s.photo_url, r.room_number, b.bed_number,
           s.date_of_joining, s.user_id is not null
      from public.students s
      join public.hostels h on h.id = s.hostel_id
      left join public.rooms r on r.id = s.room_id
      left join public.beds b on b.id = s.bed_id
     where s.monthly_fee <= 0 and s.status <> 'vacated' and s.deleted_at is null and s.erased_at is null
       and (p_hostel_id is null or s.hostel_id = p_hostel_id)
       and coalesce(app.has_role_in(s.hostel_id, 'owner', 'warden'), false)
     order by s.date_of_joining desc, s.full_name
     limit 200;
end
$fn$;

-- ─── 5. Set or change a resident's rent ───────────────────────────────────────────────────
create function public.wd_set_tenant_rent(p_student_id uuid, p_monthly_fee numeric, p_due_day integer default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_uid  uuid := auth.uid();
  v      public.students%rowtype;
  v_from date;
begin
  if v_uid is null or app.user_role() is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  select * into v from public.students s where s.id = p_student_id for update;
  if v.id is null or v.deleted_at is not null or v.erased_at is not null then
    raise exception 'Resident not found.' using errcode = 'P0001';
  end if;
  if not coalesce(app.has_role_in(v.hostel_id, 'owner', 'warden'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if v.status = 'vacated' then
    raise exception 'This resident has checked out.' using errcode = 'P0001';
  end if;
  perform app.check_rent(p_monthly_fee, p_due_day);
  if not coalesce(app.hostel_writable(v.hostel_id), false) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  perform app.spend('rent_set', 120, 3600, 'Too many rent changes in a short time. Try again in a few minutes.');

  v_from := app.first_unbilled_month(v.id);   -- measured before the change (old rent, old due day)
  update public.students
     set monthly_fee = round(p_monthly_fee, 2), rent_due_day = coalesce(p_due_day, rent_due_day)
   where id = v.id;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, app.user_role(), 'student.rent.set', 'student', v.id::text, v.hostel_id,
          jsonb_build_object('old_fee', v.monthly_fee, 'new_fee', round(p_monthly_fee, 2),
                             'old_due_day', v.rent_due_day, 'new_due_day', coalesce(p_due_day, v.rent_due_day),
                             'applies_from', to_char(v_from, 'YYYY-MM'), 'surface', 'rpc'));

  return jsonb_build_object('student_id', v.id, 'monthly_fee', round(p_monthly_fee, 2),
                            'rent_due_day', coalesce(p_due_day, v.rent_due_day),
                            'applies_from', to_char(v_from, 'YYYY-MM'));
end
$fn$;

-- ─── 6. R4.2 warden/owner edits a tenant's details ────────────────────────────────────────
-- NULL keeps a value, '' clears an optional one. Rules copy me_update_profile. Never touches the
-- role, the PG, or the login email; the sign-in identifier of a phone login does not change either.
create function public.wd_update_tenant_profile(
  p_student_id uuid,
  p_full_name text default null, p_phone text default null, p_email text default null,
  p_gender text default null, p_date_of_birth date default null,
  p_emergency_contact_name text default null, p_emergency_contact_phone text default null,
  p_address text default null, p_city text default null, p_pincode text default null)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_uid    uuid := auth.uid();
  v_s      public.students%rowtype;
  v_u      public.users%rowtype;
  v_name   text;  v_phone text;  v_email text;  v_gender text;  v_dob date;
  v_ename  text;  v_ephone text; v_addr text;   v_city text;    v_pin text;
  v_fields text[];
begin
  if v_uid is null or app.user_role() is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;
  select * into v_s from public.students s where s.id = p_student_id for update;
  if v_s.id is null or v_s.deleted_at is not null or v_s.erased_at is not null or v_s.status = 'vacated' then
    raise exception 'Resident not found.' using errcode = 'P0001';
  end if;
  if app.user_role() not in ('owner', 'warden', 'super_admin')
     or not coalesce(app.has_role_in(v_s.hostel_id, 'owner', 'warden'), false) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not coalesce(app.hostel_writable(v_s.hostel_id), false) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  perform app.spend('tenant_profile_update', 60, 3600, 'Too many profile changes. Try again in a while.');
  if v_s.user_id is not null then
    select * into v_u from public.users u where u.id = v_s.user_id for update;
  end if;
  if v_u.id is null and (p_gender is not null or p_date_of_birth is not null or p_city is not null or p_pincode is not null) then
    raise exception 'This resident has no app account, so gender, date of birth, city and pincode cannot be saved.'
      using errcode = 'P0001', hint = case when p_gender is not null then 'gender' when p_date_of_birth is not null
                                           then 'date_of_birth' when p_city is not null then 'city' else 'pincode' end;
  end if;

  v_name := v_s.full_name;
  if p_full_name is not null then
    v_name := app.clean_line(p_full_name);
    if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 80 then
      raise exception 'Enter the full name (2 to 80 characters).' using errcode = 'P0001', hint = 'full_name';
    end if;
  end if;

  v_phone := v_s.phone;
  if p_phone is not null then
    v_phone := app.normalize_phone(p_phone);
    if v_phone is null or v_phone !~ '^[6-9][0-9]{9}$' then
      raise exception 'Enter a valid 10-digit mobile number.' using errcode = 'P0001', hint = 'phone';
    end if;
  end if;

  v_email := v_s.email;
  if p_email is not null then
    v_email := nullif(lower(btrim(p_email)), '');
    if v_email is not null and (char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
      raise exception 'Enter a valid email address.' using errcode = 'P0001', hint = 'email';
    end if;
  end if;

  v_gender := v_u.gender;
  if p_gender is not null then
    if btrim(p_gender) = '' then
      v_gender := null;
    elsif lower(btrim(p_gender)) in ('male', 'female', 'other') then
      v_gender := lower(btrim(p_gender));
    else
      raise exception 'Choose male, female or other.' using errcode = 'P0001', hint = 'gender';
    end if;
  end if;

  v_dob := v_u.date_of_birth;
  if p_date_of_birth is not null then
    if p_date_of_birth > (app.today() - interval '10 years')::date
       or p_date_of_birth < (app.today() - interval '100 years')::date then
      raise exception 'Enter a valid date of birth.' using errcode = 'P0001', hint = 'date_of_birth';
    end if;
    v_dob := p_date_of_birth;
  end if;

  v_ename := coalesce(v_u.emergency_contact_name, v_s.guardian_name);
  if p_emergency_contact_name is not null then
    v_ename := app.clean_line(p_emergency_contact_name);
    if v_ename is not null and (char_length(v_ename) < 2 or char_length(v_ename) > 80) then
      raise exception 'Enter the emergency contact''s name (2 to 80 characters).'
        using errcode = 'P0001', hint = 'emergency_contact_name';
    end if;
  end if;

  v_ephone := coalesce(v_u.emergency_contact_phone, v_s.guardian_phone);
  if p_emergency_contact_phone is not null then
    if btrim(p_emergency_contact_phone) = '' then
      v_ephone := null;
    else
      v_ephone := app.normalize_phone(p_emergency_contact_phone);
      if v_ephone is null or v_ephone !~ '^[6-9][0-9]{9}$' then
        raise exception 'Enter a valid 10-digit number for the emergency contact.'
          using errcode = 'P0001', hint = 'emergency_contact_phone';
      end if;
    end if;
  end if;
  if v_ephone is not null and v_ephone = v_phone then
    raise exception 'The emergency contact needs a different number from the resident''s.'
      using errcode = 'P0001', hint = 'emergency_contact_phone';
  end if;

  v_addr := v_s.permanent_address;
  if p_address is not null then
    v_addr := app.clean_line(p_address);
    if v_addr is not null and (char_length(v_addr) < 5 or char_length(v_addr) > 500) then
      raise exception 'Enter the full address (5 to 500 characters).' using errcode = 'P0001', hint = 'address';
    end if;
  end if;

  v_city := v_u.city;
  if p_city is not null then
    v_city := app.clean_line(p_city);
    if v_city is not null and char_length(v_city) not between 2 and 80 then
      raise exception 'Enter the city (2 to 80 characters).' using errcode = 'P0001', hint = 'city';
    end if;
  end if;

  v_pin := v_u.pincode;
  if p_pincode is not null then
    v_pin := nullif(btrim(p_pincode), '');
    if v_pin is not null and v_pin !~ '^[1-9][0-9]{5}$' then
      raise exception 'Enter a valid 6-digit pincode.' using errcode = 'P0001', hint = 'pincode';
    end if;
  end if;

  begin
    update public.students
       set full_name = v_name, phone = v_phone, email = v_email, guardian_name = v_ename,
           guardian_phone = v_ephone, permanent_address = v_addr
     where id = v_s.id;
    if v_u.id is not null then
      update public.users
         set full_name = v_name, phone = v_phone, gender = v_gender, date_of_birth = v_dob,
             emergency_contact_name = v_ename, emergency_contact_phone = v_ephone, city = v_city, pincode = v_pin
       where id = v_u.id;
    end if;
  exception when unique_violation then
    raise exception 'Another resident or account already uses this phone number.' using errcode = 'P0001', hint = 'phone';
  end;

  v_fields := array_remove(array[
    case when v_name   is distinct from v_s.full_name         then 'full_name' end,
    case when v_phone  is distinct from v_s.phone             then 'phone' end,
    case when v_email  is distinct from v_s.email             then 'email' end,
    case when v_gender is distinct from v_u.gender            then 'gender' end,
    case when v_dob    is distinct from v_u.date_of_birth     then 'date_of_birth' end,
    case when v_ename  is distinct from coalesce(v_u.emergency_contact_name, v_s.guardian_name)   then 'emergency_contact_name' end,
    case when v_ephone is distinct from coalesce(v_u.emergency_contact_phone, v_s.guardian_phone) then 'emergency_contact_phone' end,
    case when v_addr   is distinct from v_s.permanent_address then 'address' end,
    case when v_city   is distinct from v_u.city              then 'city' end,
    case when v_pin    is distinct from v_u.pincode           then 'pincode' end], null);

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (v_uid, app.user_role(), 'student.profile.update', 'student', v_s.id::text, v_s.hostel_id,
          jsonb_build_object('fields', to_jsonb(v_fields), 'user_id', v_s.user_id, 'surface', 'rpc'));

  return jsonb_build_object(
    'student_id', v_s.id, 'full_name', v_name, 'phone', v_phone, 'email', v_email, 'gender', v_gender,
    'date_of_birth', v_dob, 'emergency_contact_name', v_ename, 'emergency_contact_phone', v_ephone,
    'address', v_addr, 'city', v_city, 'pincode', v_pin, 'has_account', v_u.id is not null,
    'changed', to_jsonb(v_fields));
end
$fn$;

-- ─── 7. Grants ────────────────────────────────────────────────────────────────────────────
revoke all on function app.check_rent(numeric, integer) from public, anon, authenticated;
revoke all on function app.first_unbilled_month(uuid) from public, anon, authenticated;
revoke all on function app.students_rent_freeze() from public, anon, authenticated;
do $grants$
declare s text;
begin
  foreach s in array array[
    'public.ow_decide_join_request(uuid,boolean,text,numeric,integer)',
    'public.wd_residents_needing_rent(uuid)',
    'public.wd_set_tenant_rent(uuid,numeric,integer)',
    'public.wd_update_tenant_profile(uuid,text,text,text,text,date,text,text,text,text,text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', s);
    execute format('grant execute on function %s to authenticated, service_role', s);
  end loop;
end
$grants$;

-- ─── 8. What live looks like afterwards, or no commit ─────────────────────────────────────
do $verify$
declare v_n int;
begin
  select count(*) into v_n
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ow_decide_join_request', 'wd_residents_needing_rent', 'wd_set_tenant_rent', 'wd_update_tenant_profile')
     and p.prosecdef and p.proconfig = array['search_path=""']
     and not has_function_privilege('anon', p.oid, 'execute')
     and has_function_privilege('authenticated', p.oid, 'execute');
  if v_n <> 4 then
    raise exception 'expected 4 round-4 RPCs with the right security and grants, found %', v_n;
  end if;
  if position('fp.id is not null' in (select prosrc from pg_proc where oid = 'public.rpc_fee_ledger(uuid,text)'::regprocedure)) = 0
     or position('fp.id is not null' in (select prosrc from pg_proc where oid = 'public.rpc_student_fee_months(uuid)'::regprocedure)) = 0
     or position('s.rent_due_day' in (select prosrc from pg_proc where oid = 'app.send_rent_reminders()'::regprocedure)) = 0
     or position('v.rent_due_day' in (select prosrc from pg_proc where oid = 'public.st_timeline(uuid)'::regprocedure)) = 0
     or position('monthly rent before' in (select prosrc from pg_proc
                   where oid = 'public.wd_record_payment(uuid,text,numeric,payment_mode,date,text)'::regprocedure)) = 0 then
    raise exception 'a patched routine did not take its new body';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261031100000', 'round4') on conflict (version) do nothing;

notify pgrst, 'reload schema';

commit;

-- AFTER APPLYING: run 2026-10-31-round4.test.sql (rolls itself back, ends 'ALL ROUND 4 TESTS PASSED').
