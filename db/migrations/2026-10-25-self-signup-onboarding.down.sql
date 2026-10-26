-- Undo 2026-10-25-self-signup-onboarding.sql.
--
-- Drops every table, column, trigger, routine, storage policy and bucket the migration added,
-- and puts the five routines it redefined back to the bodies measured on live on 2026-10-25
-- (copied from pg_get_functiondef before the migration ran), each proved by its md5:
--   app.users_update_guard()        12a976f46a4987c3cf51956192eb02f4
--   app.enforce_role_limits()       fb691858ad1921fc9598444933696751
--   app.email_is_reachable(text)    a9abf379e71a56a3c3ed313d2dba9cb4
--   public.wd_vacate_student(uuid)  af5dd66ac3499ecf8c1a533374358141
--   app.apply_retention()           9a76513bec102b54b9a85e1bcd57ab3f
--
-- BEFORE RUNNING THIS:
-- 1. Undeploy (or redeploy the previous versions of) mobile-auth, owner-staff-account,
--    subscription-order and razorpay-webhook. They call routines this file drops.
-- 2. Ship an app build that no longer calls the self sign-up RPCs.
-- 3. Empty the avatars and identity-documents buckets through the Storage API (or let the
--    storage-erasure drain finish). Postgres cannot delete a storage object's file; this file
--    refuses to run while either bucket still holds an object.
-- 4. Deal with the self-signed-up accounts. The restored app.enforce_role_limits() requires a
--    tenant to belong to a PG, and nothing would stop staff being made from a self-created
--    account once users_self_signup_guard is gone, so this file refuses to run while any
--    account has signup_source <> 'admin'. Delete them (Super Admin account deletion) first.
--
-- Kept on purpose: hostels and subscriptions rows created through ow_create_first_hostel or a
-- plan payment stay (they are ordinary hostels and plans); only subscriptions.kind goes.
-- The subscription_payments ledger is dropped: export it first if the money trail matters.

begin;
set local lock_timeout = '10s';

do $guard$
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'users' and column_name = 'signup_source') then
    raise exception 'public.users.signup_source does not exist: the migration is not applied';
  end if;
  if exists (select 1 from public.users where signup_source <> 'admin') then
    raise exception 'self-signed-up accounts still exist (signup_source <> admin); delete them first';
  end if;
  if exists (select 1 from storage.objects where bucket_id in ('avatars', 'identity-documents')) then
    raise exception 'the avatars or identity-documents bucket still holds objects; empty it through the Storage API first';
  end if;
end
$guard$;

-- ─── Storage ──────────────────────────────────────────────────────────────────────────────
drop policy if exists apnivaas_avatars_insert            on storage.objects;
drop policy if exists apnivaas_avatars_select            on storage.objects;
drop policy if exists apnivaas_identity_documents_insert on storage.objects;
drop policy if exists apnivaas_identity_documents_select on storage.objects;

-- storage.protect_buckets_delete refuses a direct DELETE unless this setting is on.
set local storage.allow_delete_query = 'true';
delete from storage.buckets where id in ('avatars', 'identity-documents');

-- ─── Triggers on surviving tables ─────────────────────────────────────────────────────────
drop trigger if exists users_self_signup_guard on public.users;
drop trigger if exists users_avatar_erasure    on public.users;

-- ─── New tables (their policies, triggers and indexes go with them) ───────────────────────
drop table if exists public.user_documents;
drop table if exists public.hostel_join_requests;
drop table if exists public.demo_requests;
drop table if exists public.subscription_payments;
drop table if exists public.platform_plans;
drop table if exists public.external_identities;

-- ─── New routines, by name, every overload ────────────────────────────────────────────────
do $drop$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
     where (p.pronamespace = 'public'::regnamespace and p.proname in (
              'svc_create_self_signup_profile', 'svc_login_account_for_external', 'svc_link_external_identity',
              'svc_phone_in_use', 'svc_open_subscription_order', 'svc_activate_subscription_payment',
              'svc_mark_subscription_payment_failed', 'svc_delete_staff_account',
              'me_update_profile', 'me_set_avatar', 'me_add_document', 'me_delete_document', 'me_delete_account',
              'ow_create_first_hostel', 'plan_catalog', 'ow_plan_status', 'ow_book_demo', 'ow_my_demo_request',
              'ow_cancel_demo_request', 'sa_demo_requests', 'sa_update_demo_request', 'st_nearby_hostels',
              'st_search_hostels', 'st_request_join', 'st_cancel_join_request', 'st_my_join_request',
              'ow_join_requests', 'ow_pending_join_request_count', 'ow_decide_join_request'))
        or (p.pronamespace = 'app'::regnamespace and p.proname in (
              'users_self_signup_guard', 'users_avatar_erasure', 'guard_external_identity_link',
              'user_documents_erasure', 'can_view_user_media', 'can_upload_own_media',
              'storage_path_owner', 'normalize_phone', 'clean_line'))
  loop
    execute format('drop function %s', r.sig);
  end loop;
end
$drop$;

-- ─── Columns (their indexes and check constraints go with them) ───────────────────────────
alter table public.subscriptions drop column if exists kind;

alter table public.hostels
  drop column if exists latitude,
  drop column if exists longitude,
  drop column if exists locality,
  drop column if exists city,
  drop column if exists pincode,
  drop column if exists property_type,
  drop column if exists gender_policy,
  drop column if exists listed;

alter table public.users
  drop column if exists signup_source,
  drop column if exists avatar_path,
  drop column if exists gender,
  drop column if exists date_of_birth,
  drop column if exists emergency_contact_name,
  drop column if exists emergency_contact_phone;

-- ─── The five redefined routines, back to their 2026-10-25 live bodies ────────────────────
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

  -- THE GAUGE. Not a delete: Postgres cannot destroy a storage object. This is the depth of the
  -- queue a service-role drain has to work through. A number that climbs every night is the
  -- alarm that nothing is draining it.
  select count(*) into n from app.storage_erasures where purged_at is null;
  step := 'storage objects awaiting purge (queue depth)'; rows_affected := n; return next;
end $function$
;

CREATE OR REPLACE FUNCTION app.email_is_reachable(p_email text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select p_email is not null
     and length(btrim(p_email)) > 0
     and lower(btrim(p_email)) not like '%@student.hostelpro.local'
$function$
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

CREATE OR REPLACE FUNCTION public.wd_vacate_student(p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- One UPDATE, so app.students_bed_guard fires once and the check-out and the request cannot
  -- come apart if the connection drops. coalesce() keeps a second check-out from resetting a
  -- clock that is already running.
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
end $function$
;

-- ─── Proof ────────────────────────────────────────────────────────────────────────────────
do $verify$
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
  for k in select jsonb_object_keys(v_expected) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = k::regprocedure;
    if v_md5 is distinct from v_expected ->> k then
      raise exception '% is not back to its 2026-10-25 body (md5 %)', k, v_md5;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public'
                and ((table_name = 'users' and column_name in ('signup_source', 'avatar_path', 'gender', 'date_of_birth',
                                                               'emergency_contact_name', 'emergency_contact_phone'))
                  or (table_name = 'hostels' and column_name in ('latitude', 'longitude', 'locality', 'city', 'pincode',
                                                                 'property_type', 'gender_policy', 'listed'))
                  or (table_name = 'subscriptions' and column_name = 'kind'))) then
    raise exception 'a column the migration added is still there';
  end if;
  if to_regclass('public.external_identities') is not null or to_regclass('public.platform_plans') is not null
     or to_regclass('public.subscription_payments') is not null or to_regclass('public.demo_requests') is not null
     or to_regclass('public.hostel_join_requests') is not null or to_regclass('public.user_documents') is not null then
    raise exception 'a table the migration added is still there';
  end if;
  if exists (select 1 from storage.buckets where id in ('avatars', 'identity-documents'))
     or exists (select 1 from pg_policies where schemaname = 'storage' and policyname like 'apnivaas\_%') then
    raise exception 'a bucket or storage policy the migration added is still there';
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.users'::regclass
              and tgname in ('users_self_signup_guard', 'users_avatar_erasure')) then
    raise exception 'a users trigger the migration added is still there';
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
              and proname in ('svc_create_self_signup_profile', 'svc_activate_subscription_payment',
                              'svc_delete_staff_account', 'ow_create_first_hostel', 'st_request_join')) then
    raise exception 'a routine the migration added is still there';
  end if;
end
$verify$;

delete from supabase_migrations.schema_migrations where version = '20261025100000';

notify pgrst, 'reload schema';

commit;
