-- UNDO 2026-10-31-round4.sql. Fee rows that a rent change froze at the old rent are kept: they are
-- billing history (amount_paid 0), and the old code reads them the same way.
begin;
set local lock_timeout = '10s';

do $$ begin
  if current_user <> 'postgres' then raise exception 'run as postgres (got %)', current_user; end if;
end $$;

create or replace function pg_temp.r4_patch(p_fn regprocedure, p_from text, p_to text)
returns void language plpgsql as $$
declare v_def text := pg_get_functiondef(p_fn);
begin
  if (length(v_def) - length(replace(v_def, p_from, ''))) <> length(p_from) then
    raise exception 'r4 undo: % does not contain the expected text exactly once; nothing changed', p_fn;
  end if;
  execute replace(v_def, p_from, p_to);
end $$;

drop function public.wd_update_tenant_profile(uuid, text, text, text, text, date, text, text, text, text, text);
drop function public.wd_set_tenant_rent(uuid, numeric, integer);
drop function public.wd_residents_needing_rent(uuid);
drop trigger students_rent_freeze on public.students;
drop function app.students_rent_freeze();
drop function app.first_unbilled_month(uuid);

select pg_temp.r4_patch('public.rpc_fee_ledger(uuid,text)',
  E'\n    and (s.monthly_fee > 0 or fp.id is not null)', '');
select pg_temp.r4_patch('public.rpc_student_fee_months(uuid)',
  E'     where fp.id is not null or v.monthly_fee > 0\n', '');
select pg_temp.r4_patch('public.wd_record_payment(uuid,text,numeric,payment_mode,date,text)',
  E'  if coalesce(v_fee, 0) <= 0 and not exists (select 1 from public.fee_payments f\n'
  || E'      where f.student_id = p_student_id and f.period_month = p_period_month and f.amount_due > 0) then\n'
  || E'    raise exception ''Set this resident''''s monthly rent before recording a payment.'' using errcode = ''P0001'', hint = ''monthly_fee'';\n'
  || E'  end if;\n', '');
select pg_temp.r4_patch('app.send_rent_reminders()',
  $p$s.hostel_id, coalesce(s.rent_due_day, h.rent_due_day) as rent_due_day,$p$, $p$s.hostel_id, h.rent_due_day,$p$);
select pg_temp.r4_patch('public.st_timeline(uuid)',
  $p$coalesce(v.rent_due_day, h.rent_due_day, 1)$p$, $p$coalesce(h.rent_due_day, 1)$p$);

drop function public.ow_decide_join_request(uuid, boolean, text, numeric, integer);
-- The 2026-10-25 body, as read from live on 2026-10-31.
CREATE OR REPLACE FUNCTION public.ow_decide_join_request(p_request_id uuid, p_accept boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
revoke all on function public.ow_decide_join_request(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.ow_decide_join_request(uuid, boolean, text) to authenticated, service_role;

drop function app.check_rent(numeric, integer);
alter table public.students drop column rent_due_day;

do $verify$
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
  for k in select jsonb_object_keys(v_expected) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = k::regprocedure;
    if v_md5 is distinct from v_expected ->> k then
      raise exception 'undo: % did not return to its 2026-10-31 body (md5 %)', k, v_md5;
    end if;
  end loop;
end
$verify$;

delete from supabase_migrations.schema_migrations where version = '20261031100000';
notify pgrst, 'reload schema';
commit;
