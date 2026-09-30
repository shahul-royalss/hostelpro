-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- UNDO 2026-09-30-multi-pg-staff-access.sql
--
-- Puts every routine that migration redefined back to its live text of 2026-09-30, exactly as
-- pg_get_functiondef() printed it before the migration ran, and drops everything it added:
--
--   restored  app.user_hostel_id, app.users_update_guard, app.enforce_role_limits,
--             public.st_hostel_contacts, app.complaints_after_change, app.leaves_after_change,
--             app.announcements_after_insert, app.tasks_assignee_guard,
--             public.request_account_deletion
--   dropped   public.my_staff_hostels, public.staff_switch_hostel,
--             public.owner_set_staff_hostels, public.owner_hostel_staff,
--             public.hostel_staff_names, trigger users_grant_home_hostel with
--             app.staff_grant_home_hostel, and public.staff_hostel_access with its policy, index
--             and trigger, then app.staff_hostel_access_guard
--
-- ── WHAT UNDOING DOES TO DATA ───────────────────────────────────────────────────────────────
--
-- Every grant is lost. A warden or manager stays in whatever PG users.hostel_id names when this
-- runs, which may not be the PG they were created in: after the undo that is simply "their PG",
-- as it was before the feature. Tell anybody with several PGs which one they were left in.
--
-- The staff limit goes back to counting users.hostel_id. If people switched so that one PG now
-- holds more than 5 active wardens (or managers) by that count, nobody is removed. The restored
-- enforce_role_limits only refuses the NEXT activation or move into that PG until one leaves.
--
-- Roll back everything that calls the five RPCs or writes staff_hostel_access (the website,
-- owner-create-staff, any app build with the Switch PG control) FIRST, and run this after. The
-- other way round, they get "function does not exist" or "relation does not exist" instead of a
-- working screen. An app build already on phones cannot be rolled back, so its PG screens show
-- that error until it is updated. The v6 Android app uses none of them.
--
-- ── ORDER ───────────────────────────────────────────────────────────────────────────────────
--
-- app.user_hostel_id() first, so from the next statement on no policy consults the table. Then
-- the other routines, so no trigger still reads it. Then the new objects. The same lock as the
-- migration, so no user is inserted or moved half way through.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;

lock table public.users in share row exclusive mode;


-- ═══ 1. THE LIVE ROUTINES, AS THEY WERE ═════════════════════════════════════════════════════
-- Verbatim pg_get_functiondef() output from the live database, 2026-09-30. Do not reformat:
-- md5(prosrc) of each must match what was live, and AFTER UNDOING below lists those values.
-- CREATE OR REPLACE on an unchanged signature keeps each function's grants.

CREATE OR REPLACE FUNCTION app.user_hostel_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select u.hostel_id from public.users u
   where u.id = auth.uid()
     and u.status = 'active'
     and u.deleted_at is null
     and app.mfa_satisfied()
$function$
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
  if new.hostel_id is distinct from old.hostel_id then
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

CREATE OR REPLACE FUNCTION app.enforce_role_limits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  v_limit := case new.role when 'manager' then 5 when 'warden' then 5 else 10000 end;

  if new.role in ('manager','warden') then
    perform pg_advisory_xact_lock(hashtextextended(new.hostel_id::text || ':' || new.role::text, 0));
  end if;

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
      raise exception 'This PG already has % active %s. Deactivate one first.', v_limit, new.role
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.st_hostel_contacts()
 RETURNS TABLE(hostel_name text, address text, rules text, warden_name text, warden_phone text, manager_name text, manager_phone text, owner_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select h.name, h.address, h.rules,
    (select u.full_name from public.users u
      where u.hostel_id = h.id and u.role = 'warden' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.phone from public.users u
      where u.hostel_id = h.id and u.role = 'warden' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.full_name from public.users u
      where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.phone from public.users u
      where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.full_name from public.users u where u.id = h.owner_user_id)
  from public.hostels h
  where h.id = coalesce(app.user_hostel_id(),
                        (select hostel_id from public.students where user_id = auth.uid() limit 1))
    and app.mfa_satisfied()
$function$
;

CREATE OR REPLACE FUNCTION app.complaints_after_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_student_user uuid; v_actor uuid := coalesce(auth.uid(), new.updated_by); r record;
begin
  if tg_op = 'INSERT' then
    insert into public.complaint_events (hostel_id, complaint_id, status, note, actor_user_id) values (new.hostel_id, new.id, new.status, 'Complaint raised', v_actor);
    for r in
      select u.id, u.role from public.users u
      where u.status = 'active' and u.deleted_at is null and (
        (u.role = 'warden' and u.hostel_id = new.hostel_id)
        or (u.role = 'owner' and u.id = (select owner_user_id from public.hostels where id = new.hostel_id)))
    loop
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, r.id, 'complaint', 'New complaint: ' || new.title, initcap(new.category::text) || ' complaint raised by a student.',
              case when r.role = 'owner' then '/owner/complaints' else '/warden/complaints' end);
    end loop;
    return new;
  end if;
  if tg_op = 'UPDATE' and (new.status is distinct from old.status or new.resolution_note is distinct from old.resolution_note) then
    if new.status = 'resolved' and new.resolved_at is null then update public.complaints set resolved_at = now() where id = new.id; end if;
    insert into public.complaint_events (hostel_id, complaint_id, status, note, actor_user_id)
    values (new.hostel_id, new.id, new.status, case when new.resolution_note is distinct from old.resolution_note then new.resolution_note else null end, v_actor);
    if new.status is distinct from old.status then
      select user_id into v_student_user from public.students where id = new.student_id;
      if v_student_user is not null then
        insert into public.notifications (hostel_id, user_id, type, title, body, link)
        values (new.hostel_id, v_student_user, 'complaint', 'Complaint ' || replace(new.status::text, '_', ' '),
                '"' || new.title || '" is now ' || replace(new.status::text, '_', ' ') || '.', '/student/complaints');
      end if;
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION app.leaves_after_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_student_user uuid; v_name text; r record;
begin
  select user_id, full_name into v_student_user, v_name from public.students where id = new.student_id;
  if tg_op = 'INSERT' then
    for r in select id from public.users where hostel_id = new.hostel_id and role = 'warden' and status = 'active' and deleted_at is null loop
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, r.id, 'leave', 'Leave request from ' || coalesce(v_name, 'student'), to_char(new.from_date, 'DD Mon') || ' → ' || to_char(new.to_date, 'DD Mon'), '/warden/leaves');
    end loop;
  elsif new.status is distinct from old.status and new.status <> 'pending' then
    if new.decided_at is null then update public.leaves set decided_at = now() where id = new.id; end if;
    if v_student_user is not null then
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, v_student_user, 'leave', 'Leave ' || new.status::text,
              'Your leave (' || to_char(new.from_date, 'DD Mon') || ' → ' || to_char(new.to_date, 'DD Mon') || ') was ' || new.status::text || '.', '/student/leave');
    end if;
    if new.status = 'approved' and current_date between new.from_date and new.to_date then
      update public.students set status = 'on_leave' where id = new.student_id and status = 'active';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION app.announcements_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select new.hostel_id, u.id, 'announcement', new.title, left(new.body, 140),
         case u.role when 'warden' then '/warden/notices' else '/student/notices' end
    from public.users u
   where u.hostel_id = new.hostel_id
     and u.status = 'active'
     and u.deleted_at is null
     and u.id <> new.author_user_id
     and (
          (new.audience = 'all'      and u.role in ('warden', 'student'))
       or (new.audience = 'warden'   and u.role = 'warden')
       or (new.audience = 'students' and u.role = 'student')
     );
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION app.tasks_assignee_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_hostel uuid; v_status public.user_status;
begin
  if app.is_super_admin() then return new; end if;
  select role, hostel_id, status into v_role, v_hostel, v_status from public.users where id = new.assigned_to;
  if v_role is null then
    raise exception 'That user does not exist.' using errcode = 'P0001';
  end if;
  if v_role <> 'manager' or v_hostel is distinct from new.hostel_id or v_status <> 'active' then
    raise exception 'Tasks can only be assigned to this hostel''s active manager.' using errcode = '42501';
  end if;
  return new;
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
       and u.role = 'warden' and u.hostel_id = v_hostel and u.status = 'active' and u.deleted_at is null
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


-- ═══ 2. WHAT THE MIGRATION ADDED ════════════════════════════════════════════════════════════

drop function if exists public.my_staff_hostels();
drop function if exists public.staff_switch_hostel(uuid);
drop function if exists public.owner_set_staff_hostels(uuid, uuid[]);
drop function if exists public.owner_hostel_staff(uuid);
drop function if exists public.hostel_staff_names(uuid);

drop trigger if exists users_grant_home_hostel on public.users;
drop function if exists app.staff_grant_home_hostel();

-- Takes staff_hostel_access_select, staff_hostel_access_hostel_idx and the guard trigger with it.
drop table if exists public.staff_hostel_access;
drop function if exists app.staff_hostel_access_guard();

notify pgrst, 'reload schema';

commit;


-- ═══ AFTER UNDOING ═════════════════════════════════════════════════════════════════════════
--
-- 1. Nothing the migration added is left:
--      select to_regclass('public.staff_hostel_access'),
--             to_regprocedure('public.my_staff_hostels()'),
--             to_regprocedure('public.staff_switch_hostel(uuid)'),
--             to_regprocedure('public.owner_set_staff_hostels(uuid, uuid[])'),
--             to_regprocedure('public.owner_hostel_staff(uuid)'),
--             to_regprocedure('public.hostel_staff_names(uuid)'),
--             to_regprocedure('app.staff_grant_home_hostel()'),
--             to_regprocedure('app.staff_hostel_access_guard()');
--    Every column NULL.
--
-- 2. The restored bodies are the ones that were live on 2026-09-30:
--      select p.oid::regprocedure, md5(p.prosrc)
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where (n.nspname, p.proname) in (('app','user_hostel_id'), ('app','users_update_guard'),
--             ('app','enforce_role_limits'), ('public','st_hostel_contacts'),
--             ('app','complaints_after_change'), ('app','leaves_after_change'),
--             ('app','announcements_after_insert'), ('app','tasks_assignee_guard'),
--             ('public','request_account_deletion'))
--       order by 1;
--    app.announcements_after_insert()      8c7a1ffddc375466e5efffa0a98ed7b6
--    app.complaints_after_change()         6abac7821f38ec45263b0cf256b87877
--    app.enforce_role_limits()             9c007e7977008306003b7145a16a88ad
--    app.leaves_after_change()             a178c02c37b69a572af0c46f4a7af73d
--    app.tasks_assignee_guard()            242e47943006a2fe132f466e152dadad
--    app.user_hostel_id()                  45e186ca9995b827152b8efdbf3ce647
--    app.users_update_guard()              3a15b9a08d4c0cb38564d8c6152e5a7b
--    request_account_deletion(text,uuid)   e4b848fc8369c0ae0c510736173c2b4c
--    st_hostel_contacts()                  fe4fc1fad1ad74a5d4ae04355d4ace7f
