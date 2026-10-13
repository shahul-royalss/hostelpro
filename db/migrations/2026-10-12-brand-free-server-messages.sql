-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- SERVER MESSAGES STOP NAMING THE PRODUCT
--
-- App 1.2.0 renames the product from Nivora to Apnivaas. The phones do not all move at once:
-- 1.0.0 and 1.1.0 stay installed, still called Nivora on the home screen, and every build talks
-- to this one database. A sentence the database writes is read inside whichever build the
-- person has, so "Nivora has suspended ..." is wrong inside Apnivaas and "Apnivaas has
-- suspended ..." is wrong inside Nivora. The fix that is right on every build is to name
-- neither. The Edge Functions were reworded the same way in the same change.
--
-- ── WHAT CHANGES ────────────────────────────────────────────────────────────────────────────
--
-- Five routines, one sentence or two each, and nothing else in them:
--
--   public.sa_set_hostel_status    notification to the owner
--     'Nivora has suspended %s. ... Contact Nivora support.'
--       -> '%s has been suspended. ... Contact support.'
--     '... until the plan is renewed. Contact Nivora support to renew.'
--       -> '... until the plan is renewed. Contact support to renew.'
--   public.sa_cancel_subscription  notification to the owner
--     'Nivora has cancelled the plan for %s. ...' -> 'The plan for %s has been cancelled. ...'
--   public.sa_rename_hostel        notification to the owner
--     'Nivora has renamed %s to %s. ...'          -> '%s has been renamed to %s. ...'
--   public.request_account_deletion  notification to the warden, owner or super admin
--     '... asked for their NIVORA account and personal data to be deleted.'
--       -> '... asked for their account and personal data to be deleted.'
--   app.users_update_guard         error (42501) for a hand-written email_verified_at
--     '... opening the link Nivora emails to the address.'
--       -> '... opening the confirmation link emailed to the address.'
--
-- "Contact support" means the address every build already prints in its legal and help
-- screens (support@nivora.dhrishtaerf.org, kept working for good because old builds print it).
--
-- ── HOW THE BODIES WERE COPIED ──────────────────────────────────────────────────────────────
--
-- Each function below is the LIVE definition, read on 2026-10-12 with
--   select pg_get_functiondef('<signature>'::regprocedure);
-- and copied verbatim, then only the sentences above edited. The .down.sql next to this file
-- holds the untouched live text, and md5 of each block there was checked against
-- md5(pg_get_functiondef(oid)) on live, byte for byte, before this file was written. That
-- matters most for request_account_deletion: the live body is the 2026-09-30 multi-PG one (its
-- warden fan-out goes through staff_hostel_access), not the 2026-09-13 original, and copying
-- the older body would quietly undo the multi-PG change.
--
-- CREATE OR REPLACE on an unchanged signature keeps each function's owner, grants, SECURITY
-- DEFINER and pinned search_path, so no GRANT or REVOKE is repeated here. Behaviour is
-- unchanged: the same rows are written to the same people with the same titles and links.
--
-- ── WHAT WAS FOUND AND LEFT ALONE ───────────────────────────────────────────────────────────
--
-- A scan of live, 2026-10-12:
--   select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where p.prosrc ~* '(nivora|hostelpro|apnivaas)' and n.nspname not in ('pg_catalog','information_schema');
-- found ten routines. The five above say the name to a person. The other five hold identifiers
-- that must not change, and nobody reads them as the product's name:
--
--   app.demo_review_email_verified        'demo.%@nivora.app' — the Play review demo logins
--   app.email_is_reachable,
--   app.set_student_login_email           '@student.hostelpro.local' — every phone-login
--                                          resident's auth address
--   public.mfa_verification_attempt,
--   public.password_verification_attempt  '[nivora]' tags on RAISE WARNING, server logs only
--
-- Notifications already delivered keep the words they were written with. They are history, and
-- the people who received them read them in a build that was called Nivora at the time.
--
-- ── ORDER ───────────────────────────────────────────────────────────────────────────────────
--
-- None. No client matches on any of these sentences (checked across nivora_app/lib, the
-- website's lib/ and app/, and supabase/functions on 2026-10-12), so this can be applied before
-- or after any app build, website push, legal-version row or Edge Function deploy.
-- 2026-10-12-brand-free-server-messages.test.sql checks it afterwards and rolls itself back;
-- 2026-10-12-brand-free-server-messages.down.sql undoes it.
--
-- db/schema.sql carries the same sentences for the three sa_* routines and users_update_guard.
-- It has no copy of request_account_deletion (a drift older than this change: that routine
-- lives only in db/migrations/), so there was nothing to edit there for it.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;


-- ═══ THE FIVE ROUTINES, LIVE TEXT WITH THE SENTENCES REWORDED ═══════════════════════════════

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
      when 'suspended' then format('%s has been suspended. Your team can still open the app and read records, but nothing can be added or changed until it is reactivated. Contact support.', v_hostel.name)
      when 'readonly'  then format('%s is not suspended, but its plan has ended, so it is read-only until the plan is renewed. Contact support to renew.', v_hostel.name)
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
    format('The plan for %s has been cancelled. From today your team can still read records, but nothing can be added or changed until a new plan starts. Reason: %s', v_hostel.name, v_reason),
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
    format('%s has been renamed to %s. Your team will see the new name the next time they open the app.', v_hostel.name, v_name),
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
         || ' asked for their account and personal data to be deleted.'
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
    raise exception 'Email verification cannot be granted by hand — it is earned by opening the confirmation link emailed to the address.'
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


-- ═══ AFTER APPLYING ════════════════════════════════════════════════════════════════════════
--
-- 1. Run db/migrations/2026-10-12-brand-free-server-messages.test.sql. It rolls itself back and
--    ends with NOTICE 'ALL BRAND-FREE MESSAGE TESTS PASSED' (and a one-row result saying the
--    same).
--
-- 2. The new bodies are the ones in this file:
--      select p.oid::regprocedure, md5(p.prosrc)
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where (n.nspname, p.proname) in (('public','sa_set_hostel_status'),
--             ('public','sa_cancel_subscription'), ('public','sa_rename_hostel'),
--             ('public','request_account_deletion'), ('app','users_update_guard'))
--       order by 1;
--    app.users_update_guard()                 12a976f46a4987c3cf51956192eb02f4
--    request_account_deletion(text,uuid)      57743b6b59b6a9f5d932d12de99c3b8f
--    sa_cancel_subscription(uuid,text)        13ffdd13b054c8c7e1200d4f5bcaee0c
--    sa_rename_hostel(uuid,text)              920b7279b2bc695e4790c592a5d115fb
--    sa_set_hostel_status(uuid,text)          9ebc5aad7e8417a14c249e9a1acb3bc8
--    (Computed from this file with LF line endings. Run from a copy with CRLF endings, the
--    bodies behave the same but hash differently.)
--
-- 3. The grants did not move (CREATE OR REPLACE keeps them):
--      select p.oid::regprocedure, array_to_string(p.proacl, ' | '), p.prosecdef, p.proconfig
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('sa_set_hostel_status', 'sa_cancel_subscription', 'sa_rename_hostel',
--                           'request_account_deletion');
--    Four rows: postgres=X/postgres | authenticated=X/postgres | service_role=X/postgres,
--    prosecdef true, {search_path=public}. No anon, no PUBLIC.
