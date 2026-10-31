-- TESTS FOR 2026-10-31-round5.sql. One batch, as postgres, inside BEGIN ... ROLLBACK (changes nothing).
-- Before applying: run the migration (without its BEGIN/COMMIT) and this file (without its BEGIN)
-- as one batch ending in ROLLBACK. Builds its own world with fresh ids (@example.com addresses).
-- Callers are impersonated through request.jwt.claims, as PostgREST does.
-- A failure raises 'FAIL <section>: ...'; success ends with 'ALL ROUND 5 TESTS PASSED'.

begin;

create function pg_temp.claims(p_user uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
end $$;

create function pg_temp.ok(p_cond boolean, p_label text)
returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception 'FAIL %', p_label;
  end if;
end $$;

do $test$
declare
  v_tag  text := 'r5-' || left(gen_random_uuid()::text, 8);
  v_own  uuid := gen_random_uuid();  v_mgr uuid := gen_random_uuid();
  v_wdn  uuid := gen_random_uuid();  v_sa  uuid := gen_random_uuid();
  v_ten  uuid := gen_random_uuid();  v_new uuid := gen_random_uuid();
  v_pg   uuid := gen_random_uuid();  v_fl  uuid := gen_random_uuid();
  v_r2   uuid := gen_random_uuid();  v_r3  uuid := gen_random_uuid();
  v_b21  uuid;                       v_st  uuid := gen_random_uuid();
  v_j jsonb;
  p1 text;
begin
  p1 := '9' || substr(regexp_replace(md5(v_tag || '1'), '\D', '', 'g') || '123456789', 1, 9);

  -- ─── Fixtures ───────────────────────────────────────────────────────────────────────────
  insert into auth.users (id, email) values
    (v_own, v_tag || '-own@example.com'), (v_mgr, v_tag || '-mgr@example.com'),
    (v_wdn, v_tag || '-wdn@example.com'), (v_sa, v_tag || '-sa@example.com'),
    (v_ten, p1 || '@student.hostelpro.local');
  insert into public.users (id, role, full_name, email, status, must_change_password) values
    (v_own, 'owner', v_tag || ' Owner', v_tag || '-own@example.com', 'active', false),
    (v_sa, 'super_admin', v_tag || ' Admin', v_tag || '-sa@example.com', 'active', false);
  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms, city, locality, pincode, address, status)
  values (v_pg, v_tag || ' Beds PG', v_own, 1, 2, 'Pune', 'Sector 5', '411001', '5 Test Road', 'active');
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount)
  values (v_pg, v_own, current_date - 10, current_date + 100, 0);
  -- Owner-created staff: signup_source stays 'admin', the case round 3 refused.
  insert into public.users (id, role, full_name, email, hostel_id, status, created_by) values
    (v_mgr, 'manager', v_tag || ' Manager', v_tag || '-mgr@example.com', v_pg, 'active', v_own),
    (v_wdn, 'warden', v_tag || ' Warden', v_tag || '-wdn@example.com', v_pg, 'active', v_own),
    (v_ten, 'student', v_tag || ' Tenant', null, v_pg, 'active', v_wdn);

  insert into public.floors (id, hostel_id, floor_number) values (v_fl, v_pg, 1);
  insert into public.rooms (id, hostel_id, floor_id, room_number, capacity) values
    (v_r2, v_pg, v_fl, v_tag || '-201', 2), (v_r3, v_pg, v_fl, v_tag || '-301', 3);
  -- A room's beds are created with it, one per place (2026-09-07-per-room-beds).
  select b.id into v_b21 from public.beds b where b.room_id = v_r2 and b.bed_number = 1;
  perform pg_temp.ok(v_b21 is not null and (select count(*) from public.beds where hostel_id = v_pg) = 5,
                     '0 rooms came with their beds');
  insert into public.students (id, hostel_id, user_id, full_name, phone, date_of_joining, monthly_fee, created_by)
  values (v_st, v_pg, v_ten, v_tag || ' Tenant', p1, app.today() - 5, 5000, v_wdn);
  update public.students set bed_id = v_b21 where id = v_st;

  -- ─── 1. R5.1 who may use Google and Facebook ────────────────────────────────────────────
  perform pg_temp.ok(app.external_signin_allowed(v_own), '1 owner');
  perform pg_temp.ok(app.external_signin_allowed(v_ten), '1 tenant');
  perform pg_temp.ok(app.external_signin_allowed(v_mgr), '1 owner-created manager');
  perform pg_temp.ok(app.external_signin_allowed(v_wdn), '1 owner-created warden');
  perform pg_temp.ok(app.external_signin_allowed(v_new), '1 no profile yet (a new sign-up)');
  perform pg_temp.ok(not app.external_signin_allowed(v_sa), '1 super admin refused');
  perform pg_temp.ok(
    (select count(*) from pg_proc
      where oid in ('app.guard_external_identity()'::regprocedure, 'app.guard_external_identity_link()'::regprocedure)
        and prosrc like '%Administrator accounts sign in with their password.%') = 2,
    '1 guard messages name administrators only');

  -- ─── 2. R5.2 free beds on the PG's page ─────────────────────────────────────────────────
  perform pg_temp.claims(v_own);
  v_j := public.st_pg_profile(v_pg);
  perform pg_temp.ok((v_j ->> 'beds_total')::int = 5, '2 beds_total');
  perform pg_temp.ok((v_j ->> 'beds_free')::int = 4, '2 beds_free (one taken)');
  perform pg_temp.ok(v_j -> 'free_by_sharing' = '[{"free": 1, "sharing": 2}, {"free": 3, "sharing": 3}]'::jsonb,
                     '2 free_by_sharing ' || coalesce((v_j -> 'free_by_sharing')::text, 'null'));
  perform pg_temp.ok(not (v_j ? 'address') and not (v_j ? 'latitude') and v_j ? 'reviews', '2 still no address or pin');

  -- A full sharing type drops out of the list: three residents fill the 3-sharing room.
  perform set_config('request.jwt.claims', '', true);
  insert into public.students (hostel_id, full_name, phone, date_of_joining, monthly_fee, created_by, bed_id)
  select v_pg, v_tag || ' Resident ' || b.bed_number,
         '8' || substr(regexp_replace(md5(v_tag || b.bed_number), '\D', '', 'g') || '123456789', 1, 9),
         app.today() - 2, 4000, v_wdn, b.id
    from public.beds b where b.room_id = v_r3;
  perform pg_temp.claims(v_own);
  v_j := public.st_pg_profile(v_pg);
  perform pg_temp.ok((v_j ->> 'beds_free')::int = 1
                     and v_j -> 'free_by_sharing' = '[{"free": 1, "sharing": 2}]'::jsonb, '2 a full type is left out');

  perform set_config('request.jwt.claims', '', true);
  raise notice 'ALL ROUND 5 TESTS PASSED';
end
$test$;

rollback;
