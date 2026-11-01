-- TESTS FOR 2026-11-01-round6.sql. One batch, as postgres, inside BEGIN ... ROLLBACK (changes nothing).
-- Before applying: run the migration (without its BEGIN/COMMIT) and this file (without its BEGIN)
-- as one batch ending in ROLLBACK. Builds its own world with fresh ids (@example.com addresses).
-- Callers are impersonated through request.jwt.claims, as PostgREST does.
-- A failure raises 'FAIL <section>: ...'; success ends with 'ALL ROUND 6 TESTS PASSED'.

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
  v_tag  text := 'r6-' || left(gen_random_uuid()::text, 8);
  v_own  uuid := gen_random_uuid();  v_wdn uuid := gen_random_uuid();
  v_ten  uuid := gen_random_uuid();  v_seek uuid := gen_random_uuid();
  v_pg   uuid := gen_random_uuid();  v_fl  uuid := gen_random_uuid();
  v_r2   uuid := gen_random_uuid();  v_st  uuid := gen_random_uuid();
  v_j jsonb;
  v_n int;
  p1 text; p2 text;
begin
  p1 := '9' || substr(regexp_replace(md5(v_tag || '1'), '\D', '', 'g') || '123456789', 1, 9);
  p2 := '9' || substr(regexp_replace(md5(v_tag || '2'), '\D', '', 'g') || '123456789', 1, 9);

  -- ─── Fixtures ───────────────────────────────────────────────────────────────────────────
  insert into auth.users (id, email) values
    (v_own, v_tag || '-own@example.com'), (v_wdn, v_tag || '-wdn@example.com'),
    (v_ten, p1 || '@student.hostelpro.local'), (v_seek, p2 || '@student.hostelpro.local');
  insert into public.users (id, role, full_name, email, status, must_change_password) values
    (v_own, 'owner', v_tag || ' Owner', v_tag || '-own@example.com', 'active', false);
  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms, city, locality, pincode,
                              address, status, listed, latitude, longitude)
  values (v_pg, v_tag || ' Map PG', v_own, 1, 1, 'Pune', 'Sector 5', '411001', '5 Test Road', 'active', true,
          18.52043212, 73.85674398);
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount)
  values (v_pg, v_own, current_date - 10, current_date + 100, 0);
  insert into public.users (id, role, full_name, email, hostel_id, status, created_by) values
    (v_wdn, 'warden', v_tag || ' Warden', v_tag || '-wdn@example.com', v_pg, 'active', v_own),
    (v_ten, 'student', v_tag || ' Tenant', null, v_pg, 'active', v_wdn);
  -- A tenant with no PG yet, looking for one.
  -- As the sign-up service does it (mobile-auth calls this with the service role).
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  perform public.svc_create_self_signup_profile(v_seek, 'student', v_tag || ' Seeker', null, null, 'self_google');
  perform set_config('request.jwt.claims', '', true);

  insert into public.floors (id, hostel_id, floor_number) values (v_fl, v_pg, 1);
  insert into public.rooms (id, hostel_id, floor_id, room_number, capacity) values (v_r2, v_pg, v_fl, v_tag || '-201', 2);
  insert into public.students (id, hostel_id, user_id, full_name, phone, date_of_joining, monthly_fee, created_by, bed_id)
  values (v_st, v_pg, v_ten, v_tag || ' Tenant', p1, app.today() - 5, 5000, v_wdn,
          (select b.id from public.beds b where b.room_id = v_r2 and b.bed_number = 1));

  -- ─── 1. R6.1 beds: yes or no, never a count ─────────────────────────────────────────────
  perform pg_temp.claims(v_seek);
  v_j := public.st_pg_profile(v_pg);
  perform pg_temp.ok((v_j ->> 'beds_available')::boolean, '1 one of two beds free: available');
  perform pg_temp.ok(not (v_j ? 'beds_total') and not (v_j ? 'beds_free') and not (v_j ? 'free_by_sharing'),
                     '1 no counts anywhere');

  perform set_config('request.jwt.claims', '', true);
  insert into public.students (hostel_id, full_name, phone, date_of_joining, monthly_fee, created_by, bed_id)
  values (v_pg, v_tag || ' Second', '8' || substr(p2, 2), app.today() - 1, 4000, v_wdn,
          (select b.id from public.beds b where b.room_id = v_r2 and b.bed_number = 2));
  perform pg_temp.claims(v_seek);
  v_j := public.st_pg_profile(v_pg);
  perform pg_temp.ok(not (v_j ->> 'beds_available')::boolean, '1 both beds taken: not available');

  -- ─── 2. R6.2 the pin, rounded, and still no address ─────────────────────────────────────
  perform pg_temp.ok((v_j ->> 'latitude')::numeric = 18.520432 and (v_j ->> 'longitude')::numeric = 73.856744,
                     '2 pin to 6 decimals ' || coalesce(v_j ->> 'latitude', 'null'));
  perform pg_temp.ok(not (v_j ? 'address') and not (v_j ? 'pincode'), '2 still no street address');

  -- A PG that is not listed stays private to strangers, pin and all.
  perform set_config('request.jwt.claims', '', true);
  update public.hostels set listed = false where id = v_pg;
  perform pg_temp.claims(v_seek);
  begin
    perform public.st_pg_profile(v_pg);
    raise exception 'FAIL 2 an unlisted PG was readable by a stranger';
  exception when sqlstate 'P0001' then
    perform pg_temp.ok(sqlerrm = 'This PG is not available.', '2 unlisted refusal: ' || sqlerrm);
  end;
  -- Its own tenant still sees it.
  perform pg_temp.claims(v_ten);
  perform pg_temp.ok(public.st_pg_profile(v_pg) ? 'latitude', '2 own tenant reads their PG');

  -- ─── 3. R6.3 browse: listed PGs only, tenants only ──────────────────────────────────────
  perform pg_temp.claims(v_seek);
  select count(*) into v_n from public.st_browse_hostels() x where x.hostel_id = v_pg;
  perform pg_temp.ok(v_n = 0, '3 an unlisted PG is not in the list');

  perform set_config('request.jwt.claims', '', true);
  update public.hostels set listed = true where id = v_pg;
  perform pg_temp.claims(v_seek);
  select count(*) into v_n from public.st_browse_hostels() x where x.hostel_id = v_pg and x.distance_km is null;
  perform pg_temp.ok(v_n = 1, '3 a listed PG is in the list');
  -- A resident browses too (browse only: st_request_join still refuses them).
  perform pg_temp.claims(v_ten);
  select count(*) into v_n from public.st_browse_hostels() x where x.hostel_id = v_pg;
  perform pg_temp.ok(v_n = 1, '3 a resident can browse');

  perform pg_temp.claims(v_own);
  begin
    perform public.st_browse_hostels();
    raise exception 'FAIL 3 an owner could browse';
  exception when sqlstate '42501' then
    null;
  end;
  perform pg_temp.ok(not has_function_privilege('anon', 'public.st_browse_hostels()', 'execute'),
                     '3 anon may not call it');

  perform set_config('request.jwt.claims', '', true);
  raise notice 'ALL ROUND 6 TESTS PASSED';
end
$test$;

rollback;
