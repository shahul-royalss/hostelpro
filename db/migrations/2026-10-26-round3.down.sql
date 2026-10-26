-- Undo 2026-10-26-round3.sql. Restores the eight redefined routines to their 2026-10-25 bodies and
-- drops every table, column, trigger, routine, policy, cron job and the bucket the migration added.
-- BEFORE RUNNING: redeploy the previous mobile-auth; ship an app that no longer calls round-3 RPCs;
-- empty pg-media through the Storage API; convert or delete staff applicants and self_email accounts
-- (the restored check constraint refuses self_email). Payment claims, check-out requests, reviews,
-- staff requests and the deletion log are dropped: export them first if they matter.

begin;
set local lock_timeout = '10s';

do $$
begin
  if exists (select 1 from storage.objects where bucket_id = 'pg-media') then
    raise exception 'pg-media still holds objects; empty it through the Storage API first';
  end if;
  if exists (select 1 from public.users where signup_source = 'self_email' or staff_applicant) then
    raise exception 'self_email accounts or staff applicants exist; deal with them first';
  end if;
end
$$;

select cron.unschedule('apnivaas-due-checkouts');

drop policy if exists apnivaas_pg_media_insert on storage.objects;
drop policy if exists apnivaas_pg_media_select on storage.objects;
set local storage.allow_delete_query = 'true';
delete from storage.buckets where id = 'pg-media';

drop trigger if exists users_deletion_log on public.users;
drop trigger if exists audit_log_deletion_log on public.audit_log;
drop trigger if exists students_room_audit on public.students;
drop trigger if exists hostel_join_requests_not_applicant on public.hostel_join_requests;

drop function if exists
  public.svc_external_signin_allowed(uuid), public.svc_secure_unverified_account(uuid, boolean),
  public.rpc_student_fee_months(uuid), public.st_timeline(uuid),
  public.ow_update_pg_profile(uuid, text, text, text[], text, text[], boolean, numeric, numeric),
  public.st_save_review(integer, text), public.st_my_review(), public.pg_review_list(uuid, integer, integer),
  public.st_pg_profile(uuid),
  public.st_request_checkout(date, text), public.st_my_checkout_request(), public.st_cancel_checkout_request(),
  public.wd_checkout_requests(uuid, text), public.wd_decide_checkout_request(uuid, boolean, date, text),
  public.ow_checkout_summary(uuid),
  public.sa_signups(date, date, text, text, integer, integer), public.sa_deleted_accounts(text, date, date, integer, integer),
  public.sa_purge_account(uuid, text),
  public.stf_request_join(uuid, text), public.stf_my_join_request(), public.stf_cancel_join_request(),
  public.ow_staff_requests(uuid, text), public.ow_pending_staff_request_count(),
  public.ow_decide_staff_request(uuid, boolean, text, text),
  public.ow_set_upi_settings(uuid, text, text), public.hostel_upi_settings(uuid),
  public.st_submit_payment_claim(numeric, text, text), public.st_my_payment_claims(integer),
  public.st_cancel_payment_claim(uuid), public.wd_payment_claims(uuid, text), public.wd_decide_payment_claim(uuid, boolean, text),
  app.run_due_checkouts(), app.checkout_json(uuid), app.staff_request_json(uuid), app.claim_json(uuid),
  app.users_deletion_log(), app.audit_deletion_log(), app.students_room_audit(), app.join_request_not_applicant(),
  app.readable_student(uuid), app.can_upload_pg_media(text), app.can_view_pg(uuid),
  app.pg_media_path_ok(uuid, text, text), app.notify_hostel(uuid, boolean, boolean, text, text, text, text, uuid),
  app.month_label(text), app.inr(numeric);

drop table if exists public.payment_claims, public.hostel_upi_settings, public.checkout_requests, public.pg_reviews,
                     public.staff_join_requests, public.account_deletions;

alter table public.hostels drop column if exists description, drop column if exists amenities,
                           drop column if exists logo_path, drop column if exists cover_paths;

-- ── Restored bodies (2026-10-25) ─────────────────────────────────────────────────────────
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
  order by r.room_number nulls last, s.full_name $function$;

create or replace function app.guard_external_identity()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare
  v_role public.user_role;
begin
  if new.provider in ('email', 'phone') then
    return new;
  end if;

  if new.provider not in ('google', 'facebook') then
    raise exception 'This sign-in method is not available.'
      using errcode = '42501';
  end if;

  -- No profile row means a brand-new sign-up that has not chosen a role yet. It reaches nothing:
  -- app.user_role() resolves only through public.users.
  select u.role into v_role from public.users u where u.id = new.user_id;

  if v_role in ('super_admin', 'manager', 'warden') then
    raise exception 'Staff and administrator accounts sign in with the login they were given.'
      using errcode = '42501';
  end if;

  return new;
end
$function$;

create or replace function app.guard_external_identity_link()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
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
$function$;

create or replace function app.users_self_signup_guard()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
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
$function$;

create or replace function app.users_update_guard()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
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

drop function public.st_nearby_hostels(numeric, numeric);
create function public.st_nearby_hostels(p_lat numeric, p_lng numeric)
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

drop function public.st_search_hostels(text);
create function public.st_search_hostels(p_query text)
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

drop function public.svc_create_self_signup_profile(uuid, text, text, text, text, text, text, text);
create function public.svc_create_self_signup_profile(
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

drop function if exists app.external_signin_allowed(uuid);

alter table public.users drop constraint users_signup_source_check;
alter table public.users
  add constraint users_signup_source_check
    check (signup_source in ('admin', 'self_google', 'self_facebook', 'self_truecaller')),
  drop column staff_applicant, drop column city, drop column pincode;

do $grants$
declare
  r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('svc_create_self_signup_profile', 'st_nearby_hostels', 'st_search_hostels') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if r.proname like 'svc\_%' then
      execute format('grant execute on function %s to service_role', r.sig);
    else
      execute format('grant execute on function %s to authenticated, service_role', r.sig);
    end if;
  end loop;
end
$grants$;

delete from supabase_migrations.schema_migrations where version = '20261026100000';
notify pgrst, 'reload schema';
commit;
