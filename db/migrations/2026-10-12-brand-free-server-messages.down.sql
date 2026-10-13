-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- UNDO 2026-10-12-brand-free-server-messages.sql
--
-- Puts the five routines that migration redefined back to their live text of 2026-10-12,
-- exactly as pg_get_functiondef() printed it before the migration ran:
--
--   public.sa_set_hostel_status, public.sa_cancel_subscription, public.sa_rename_hostel,
--   public.request_account_deletion, app.users_update_guard
--
-- Only words a person reads differ between the two files: the name "Nivora" / "NIVORA" comes
-- back into four notification bodies and one error message. Nothing else in these bodies
-- changed, so undoing changes no behaviour, no grant and no data. Notifications already written
-- keep the words they were written with, in either direction.
--
-- There is no ordering hazard. Nothing outside the database matches these sentences (checked
-- across the Flutter app, the website and the Edge Functions on 2026-10-12), so this can run at
-- any time, before or after any app build or Edge Function deploy.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;


-- ═══ THE LIVE ROUTINES, AS THEY WERE ════════════════════════════════════════════════════════
-- Verbatim pg_get_functiondef() output from the live database, 2026-10-12. Do not reformat:
-- md5(prosrc) of each must match what was live, and AFTER UNDOING below lists those values.
-- CREATE OR REPLACE on an unchanged signature keeps each function's owner, grants and
-- SECURITY DEFINER / search_path settings.

CREATE OR REPLACE FUNCTION public.sa_set_hostel_status(p_hostel_id uuid, p_status text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_hostel public.hostels%rowtype;
  v_result public.hostel_status;
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Only the Super Admin can suspend or reactivate a hostel.' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('suspended', 'active') then
    raise exception 'Choose whether to suspend or reactivate the hostel.' using errcode = 'P0001';
  end if;
  select * into v_hostel from public.hostels where id = p_hostel_id for update;
  if not found then
    raise exception 'No such hostel.' using errcode = 'P0001';
  end if;
  if p_status = 'suspended' then
    v_result := 'suspended';
  elsif app.subscription_state(p_hostel_id) = 'expired' then
    v_result := 'readonly';
  else
    v_result := 'active';
  end if;
  if v_result = v_hostel.status then
    return v_result::text;
  end if;
  update public.hostels
     set status = v_result,
         updated_at = now()
   where id = p_hostel_id;
  perform public.audit_event(
    'sa.hostel.status',
    'hostel',
    p_hostel_id::text,
    p_hostel_id,
    jsonb_build_object('from', v_hostel.status, 'to', v_result, 'requested', p_status, 'surface', 'rpc'),
    null, null, null, null
  );
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (
    p_hostel_id, v_hostel.owner_user_id, 'subscription',
    case
      when v_result = 'suspended'         then 'Hostel suspended'
      when v_hostel.status = 'suspended'  then 'Hostel reactivated'
      else                                     'Hostel is read-only'
    end,
    case v_result
      when 'suspended' then format('Nivora has suspended %s. Your team can still open the app and read records, but nothing can be added or changed until it is reactivated. Contact Nivora support.', v_hostel.name)
      when 'readonly'  then format('%s is not suspended, but its plan has ended, so it is read-only until the plan is renewed. Contact Nivora support to renew.', v_hostel.name)
      else                  format('%s is active again. Your team can add and change records as usual.', v_hostel.name)
    end,
    '/owner'
  );
  return v_result::text;
end $function$
;

CREATE OR REPLACE FUNCTION public.sa_cancel_subscription(p_hostel_id uuid, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_reason text := regexp_replace(coalesce(p_reason, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_hostel public.hostels%rowtype;
  v_count  int;
  v_ends   date;
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Only the Super Admin can cancel a plan.' using errcode = '42501';
  end if;
  if char_length(v_reason) < 3 or char_length(v_reason) > 300 then
    raise exception 'Give a reason for cancelling, between 3 and 300 characters.' using errcode = 'P0001';
  end if;
  select * into v_hostel from public.hostels where id = p_hostel_id for update;
  if not found then
    raise exception 'No such hostel.' using errcode = 'P0001';
  end if;
  with cancelled as (
    update public.subscriptions
       set cancelled_at  = now(),
           cancelled_by  = auth.uid(),
           cancel_reason = v_reason
     where hostel_id = p_hostel_id
       and cancelled_at is null
       and end_date >= current_date
    returning end_date
  )
  select count(*)::int, max(end_date) into v_count, v_ends from cancelled;
  if v_count = 0 then
    raise exception 'There is no current plan to cancel.' using errcode = 'P0001';
  end if;
  update public.hostels
     set status = 'readonly',
         updated_at = now()
   where id = p_hostel_id
     and status = 'active'
     and app.subscription_state(p_hostel_id) = 'expired';
  perform public.audit_event(
    'sa.subscription.cancel',
    'hostel',
    p_hostel_id::text,
    p_hostel_id,
    jsonb_build_object('periods', v_count, 'latest_end', v_ends, 'reason', v_reason, 'surface', 'rpc'),
    null, null, null, null
  );
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (
    p_hostel_id, v_hostel.owner_user_id, 'subscription', 'Plan cancelled',
    format('Nivora has cancelled the plan for %s. From today your team can still read records, but nothing can be added or changed until a new plan starts. Reason: %s', v_hostel.name, v_reason),
    '/owner'
  );
  return v_count;
end $function$
;

CREATE OR REPLACE FUNCTION public.sa_rename_hostel(p_hostel_id uuid, p_name text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_name   text := regexp_replace(coalesce(p_name, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_hostel public.hostels%rowtype;
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Only the Super Admin can rename a hostel.' using errcode = '42501';
  end if;
  if char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'Enter a hostel name between 2 and 120 characters.' using errcode = 'P0001';
  end if;
  if v_name ~ '[[:cntrl:]]' then
    raise exception 'A hostel name has to fit on one line.' using errcode = 'P0001';
  end if;
  select * into v_hostel from public.hostels where id = p_hostel_id for update;
  if not found then
    raise exception 'No such hostel.' using errcode = 'P0001';
  end if;
  if v_hostel.name = v_name then
    return v_hostel.name;
  end if;
  update public.hostels
     set name = v_name,
         updated_at = now()
   where id = p_hostel_id;
  perform public.audit_event(
    'sa.hostel.rename',
    'hostel',
    p_hostel_id::text,
    p_hostel_id,
    jsonb_build_object('from', v_hostel.name, 'to', v_name, 'surface', 'rpc'),
    null, null, null, null
  );
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (
    p_hostel_id, v_hostel.owner_user_id, 'system', 'Hostel renamed',
    format('Nivora has renamed %s to %s. Your team will see the new name the next time they open the app.', v_hostel.name, v_name),
    '/owner'
  );
  return v_name;
end $function$
;

CREATE OR REPLACE FUNCTION public.request_account_deletion(p_reason text DEFAULT NULL::text, p_hostel_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user        uuid := auth.uid();
  v_role        public.user_role;
  v_name        text;
  v_user_hostel uuid;
  v_hostel      uuid;
  v_owner       uuid;
  v_student     uuid;
  v_reason      text := nullif(btrim(coalesce(p_reason, '')), '');
  v_existing    timestamptz;
  v_body        text;
  v_notified    integer := 0;
  v_at          timestamptz;
begin
  if v_user is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;

  select u.role, u.full_name, u.hostel_id
    into v_role, v_name, v_user_hostel
    from public.users u
   where u.id = v_user
     and u.deleted_at is null;

  if v_role is null then
    raise exception 'This account is not set up yet.' using errcode = 'P0001';
  end if;
  if v_role not in ('student', 'warden', 'manager', 'owner') then
    raise exception 'Deletion requests for this account are handled by the platform administrator.'
      using errcode = 'P0001';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Keep the reason under 500 characters.' using errcode = 'P0001';
  end if;

  if v_role = 'owner' then
    select h.id, h.owner_user_id
      into v_hostel, v_owner
      from public.hostels h
     where h.owner_user_id = v_user
       and (p_hostel_id is null or h.id = p_hostel_id)
     order by (h.id = v_user_hostel) desc nulls last, h.created_at
     limit 1;
  else
    select h.id, h.owner_user_id
      into v_hostel, v_owner
      from public.hostels h
     where h.id = v_user_hostel;
  end if;

  if v_hostel is null then
    raise exception 'No hostel is linked to this account. Please contact the address on the account deletion page.'
      using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('account-deletion:' || v_user::text));

  perform app.spend(
    'account-deletion', 3, 86400,
    'You have already sent this request. Your warden and hostel owner can see it.'
  );

  select max(a.at)
    into v_existing
    from public.audit_log a
   where a.action = 'account.deletion.requested'
     and a.actor_user_id = v_user
     and a.at >= now() - interval '30 days';

  if v_existing is not null then
    return jsonb_build_object('requested_at', v_existing, 'already_pending', true, 'notified', 0);
  end if;

  if v_role = 'student' then
    select s.id
      into v_student
      from public.students s
     where s.user_id = v_user
       and s.status <> 'vacated'
     limit 1;
  end if;

  v_body := coalesce(nullif(btrim(v_name), ''), 'A user')
         || ' asked for their NIVORA account and personal data to be deleted.'
         || case when v_reason is not null then ' Reason: "' || left(v_reason, 200) || '"' else '' end
         || ' Verify who they are in person before acting.';

  with recipients as (
    select u.id, 'super_admin' as role
      from public.users u
     where v_role = 'owner'
       and u.role = 'super_admin' and u.status = 'active' and u.deleted_at is null
    union
    select u.id, 'warden'
      from public.users u
     where v_role = 'student'
       and u.role = 'warden' and u.id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = v_hostel) and u.status = 'active' and u.deleted_at is null
    union
    select u.id, 'owner'
      from public.users u
     where v_role <> 'owner'
       and u.id = v_owner and u.status = 'active' and u.deleted_at is null
  ),
  delivered as (
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    select v_hostel, r.id, 'system', 'Account deletion requested', v_body,
           case r.role
             when 'super_admin' then '/super-admin/hostels'
             when 'owner' then case when v_student is not null
                                    then '/owner/students/' || v_student::text
                                    else '/owner/staff' end
             else '/warden/rooms'
           end
      from recipients r
     where r.id <> v_user
    returning 1
  )
  select count(*) into v_notified from delivered;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (
    v_user, v_role, 'account.deletion.requested', 'user', v_user::text, v_hostel,
    jsonb_build_object(
      'requesterRole', v_role::text,
      'studentId',     v_student,
      'notified',      v_notified,
      'hasReason',     v_reason is not null,
      'surface',       'app'
    )
  )
  returning at into v_at;

  return jsonb_build_object('requested_at', v_at, 'already_pending', false, 'notified', v_notified);
end $function$
;

CREATE OR REPLACE FUNCTION app.users_update_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_manages_target boolean;
begin
  if new.email is distinct from old.email then
    new.email_verified_at := null;
    new.email_verification_reset_at := now();
  elsif new.email_verified_at is distinct from old.email_verified_at and not app.is_service_role() then
    raise exception 'Email verification cannot be granted by hand — it is earned by opening the link Nivora emails to the address.'
      using errcode = '42501';
  end if;

  if app.is_super_admin() then
    return new;
  end if;

  v_manages_target :=
       (old.role in ('manager','warden') and app.owns_hostel(old.hostel_id))
    or (old.role = 'student' and app.has_role_in(old.hostel_id, 'warden'));

  if new.id is distinct from old.id then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    raise exception 'You cannot change an account''s role.' using errcode = '42501';
  end if;
  if new.hostel_id is distinct from old.hostel_id
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

  if new.id = auth.uid() or v_manages_target then
    return new;
  end if;
  raise exception 'Not allowed.' using errcode = '42501';
end $function$
;

commit;


-- ═══ AFTER UNDOING ═════════════════════════════════════════════════════════════════════════
--
-- The restored bodies are the ones that were live on 2026-10-12, before the migration:
--      select p.oid::regprocedure, md5(p.prosrc)
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where (n.nspname, p.proname) in (('public','sa_set_hostel_status'),
--             ('public','sa_cancel_subscription'), ('public','sa_rename_hostel'),
--             ('public','request_account_deletion'), ('app','users_update_guard'))
--       order by 1;
--    app.users_update_guard()                 9387e6822a2c25346d447bdfc9e81c28
--    request_account_deletion(text,uuid)      dc943546aacce4ea5d47e876e6e6bc6a
--    sa_cancel_subscription(uuid,text)        362c338e49ed08dd6934cd83a0dedbc0
--    sa_rename_hostel(uuid,text)              a9938994f7ee064db4cf9e0d06b2f342
--    sa_set_hostel_status(uuid,text)          849dd6089914ceee38cd608c6f4931d3
