-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- TESTS FOR 2026-10-25-self-signup-onboarding.sql
--
-- Run it as ONE batch, after the migration, as postgres:
--   psql "$DATABASE_URL" -f db/migrations/2026-10-25-self-signup-onboarding.test.sql
-- or, before applying, as one batch together with the migration inside a single
-- BEGIN ... ROLLBACK (how it was run on live on 2026-10-24: the migration's own BEGIN/COMMIT
-- and this file's BEGIN/ROLLBACK are left out, and the batch ends with ROLLBACK).
--
-- Everything happens inside BEGIN ... ROLLBACK, so it changes nothing. It builds its own world
-- (a super admin, two admin-created owners and five PGs, a manager, two wardens, a resident
-- with a login, three self-signed-up owners and two self-signed-up tenants) with fresh ids,
-- tagged @example.com and @identity.apnivaas.invalid addresses and md5-derived phone numbers,
-- and reads no real account. It calls app.apply_retention() once, which also runs the existing
-- nightly steps on real rows; the cron already ran today, and the rollback discards it all.
--
-- Callers are impersonated the way PostgREST does it: request.jwt.claims carries sub, role
-- 'authenticated' and aal 'aal2'. The role is switched to authenticated wherever grants or
-- row-level security are what is being tested.
--
-- A failed expectation raises 'FAIL <section>: ...' and aborts the batch. Success ends with
-- NOTICE 'ALL SELF SIGN-UP TESTS PASSED' and a one-row result saying the same.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;

-- p_sql must fail with p_state (and, when given, a message LIKE p_msg).
create function pg_temp.expect(p_sql text, p_state text, p_msg text, p_label text)
returns void language plpgsql as $$
declare
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state is distinct from p_state or (p_msg is not null and v_msg not like p_msg) then
    raise exception 'FAIL %: expected [%] %, got [%] %', p_label, p_state, coalesce(p_msg, '*'),
      coalesce(v_state, 'no error'), v_msg;
  end if;
end $$;

-- NULL = the service role.
create function pg_temp.claims(p_user uuid)
returns void language plpgsql as $$
begin
  if p_user is null then
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  end if;
end $$;

create function pg_temp.rls(p_on boolean)
returns void language plpgsql as $$
begin
  perform set_config('role', case when p_on then 'authenticated' else 'none' end, true);
end $$;

do $test$
declare
  v_tag    text := 'ssu-' || left(gen_random_uuid()::text, 8);
  v_t      text;                          -- v_tag without the hyphen, for Razorpay-shaped ids
  v_sa     uuid := gen_random_uuid();
  v_own_a  uuid := gen_random_uuid();     -- admin owner: PGs A, U (unlisted), X (expired)
  v_own_b  uuid := gen_random_uuid();     -- admin owner: PGs B, S (suspended)
  v_mgr    uuid := gen_random_uuid();     -- manager in A
  v_wdn    uuid := gen_random_uuid();     -- warden in A
  v_wdn_b  uuid := gen_random_uuid();     -- warden in B
  v_res    uuid := gen_random_uuid();     -- warden-created resident in A, with a login
  v_g_own  uuid := gen_random_uuid();     -- self_google owner
  v_fb_own uuid := gen_random_uuid();     -- self_facebook owner, real address not proved
  v_tc_own uuid := gen_random_uuid();     -- self_truecaller owner, synthetic address
  v_t1     uuid := gen_random_uuid();     -- self_google tenant
  v_t2     uuid := gen_random_uuid();     -- self_truecaller tenant
  v_x      uuid := gen_random_uuid();     -- an auth user with no profile
  v_new    uuid := gen_random_uuid();     -- re-uses the deleted warden's address
  v_pg_a   uuid := gen_random_uuid();
  v_pg_b   uuid := gen_random_uuid();
  v_pg_u   uuid := gen_random_uuid();
  v_pg_x   uuid := gen_random_uuid();
  v_pg_s   uuid := gen_random_uuid();
  v_pg_g   uuid;                          -- the self-signed-up Google owner's PG
  v_pg_tc  uuid;                          -- the Truecaller owner's PG
  v_res_st uuid := gen_random_uuid();     -- v_res's roster row
  v_t1_st  uuid;                          -- t1's roster row after acceptance
  v_p_t1   text;  v_p_em text;  v_p_t2 text;  v_p_tc text;  v_p_res text;  v_p_free text;
  v_av1    text;  v_av2 text;  v_av_t2 text;  v_av_wdn text;  v_av_res text;  v_doc_t2 text;  v_orphan text;
  v_req1   uuid;  v_req2 uuid;  v_req3 uuid;
  v_j      jsonb;
  v_n      int;
  v_m      int;
  v_s      text;
  v_d      date;
  v_trial_end date;
  v_ts     timestamptz;
  v_k1     numeric;
  v_k2     numeric;
  v_role   text;
begin
  v_t      := replace(v_tag, '-', '');
  v_p_t1   := '7' || substr(regexp_replace(md5(v_tag || 't1'),   '\D', '', 'g') || '123456789', 1, 9);
  v_p_em   := '8' || substr(regexp_replace(md5(v_tag || 'em'),   '\D', '', 'g') || '123456789', 1, 9);
  v_p_t2   := '7' || substr(regexp_replace(md5(v_tag || 't2'),   '\D', '', 'g') || '123456789', 1, 9);
  v_p_tc   := '9' || substr(regexp_replace(md5(v_tag || 'tc'),   '\D', '', 'g') || '123456789', 1, 9);
  v_p_res  := '6' || substr(regexp_replace(md5(v_tag || 'res'),  '\D', '', 'g') || '123456789', 1, 9);
  v_p_free := '6' || substr(regexp_replace(md5(v_tag || 'free'), '\D', '', 'g') || '123456789', 1, 9);

  -- ─── Fixtures, as the service role ──────────────────────────────────────────────────────
  perform pg_temp.claims(null);

  insert into auth.users (id, email) values
    (v_sa,     v_tag || '-sa@example.com'),
    (v_own_a,  v_tag || '-owna@example.com'),
    (v_own_b,  v_tag || '-ownb@example.com'),
    (v_mgr,    v_tag || '-mgr@example.com'),
    (v_wdn,    v_tag || '-wdn@example.com'),
    (v_wdn_b,  v_tag || '-wdnb@example.com'),
    (v_res,    v_p_res || '@student.hostelpro.local'),
    (v_g_own,  v_tag || '-gown@example.com'),
    (v_fb_own, v_tag || '-fbown@example.com'),
    (v_tc_own, 'tc-' || v_tag || '@identity.apnivaas.invalid'),
    (v_t1,     v_tag || '-t1@example.com'),
    (v_t2,     'tc-' || v_tag || '-t2@identity.apnivaas.invalid'),
    (v_x,      v_tag || '-x@example.com');

  insert into public.users (id, role, full_name, email, status, must_change_password) values
    (v_sa,    'super_admin', v_tag || ' SA',      v_tag || '-sa@example.com',   'active', false),
    (v_own_a, 'owner',       v_tag || ' Owner A', v_tag || '-owna@example.com', 'active', false),
    (v_own_b, 'owner',       v_tag || ' Owner B', v_tag || '-ownb@example.com', 'active', false);

  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms, city, locality,
                              latitude, longitude, listed, status) values
    (v_pg_a, v_tag || ' Alpha PG',     v_own_a, 1, 2, 'City ' || v_tag, 'Sector 1', 12.971600, 77.594600, true,  'active'),
    (v_pg_b, v_tag || ' Beta PG',      v_own_b, 1, 2, 'City ' || v_tag, 'Sector 2', 12.981600, 77.604600, true,  'active'),
    (v_pg_u, v_tag || ' Unlisted PG',  v_own_a, 1, 1, 'City ' || v_tag, 'Sector 3', 12.972000, 77.595000, false, 'active'),
    (v_pg_x, v_tag || ' Expired PG',   v_own_a, 1, 1, 'City ' || v_tag, 'Sector 4', 12.973000, 77.596000, true,  'active'),
    (v_pg_s, v_tag || ' Suspended PG', v_own_b, 1, 1, 'City ' || v_tag, 'Sector 5', 12.974000, 77.597000, true,  'suspended');
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount) values
    (v_pg_a, v_own_a, current_date - 10,  current_date + 100, 0),
    (v_pg_b, v_own_b, current_date - 10,  current_date + 100, 0),
    (v_pg_u, v_own_a, current_date - 10,  current_date + 100, 0),
    (v_pg_x, v_own_a, current_date - 100, current_date - 1,   0),
    (v_pg_s, v_own_b, current_date - 10,  current_date + 100, 0);

  insert into public.users (id, role, full_name, email, phone, hostel_id, status, created_by) values
    (v_mgr,   'manager', v_tag || ' Manager',  v_tag || '-mgr@example.com',  null,    v_pg_a, 'active', v_own_a),
    (v_wdn,   'warden',  v_tag || ' Warden',   v_tag || '-wdn@example.com',  null,    v_pg_a, 'active', v_own_a),
    (v_wdn_b, 'warden',  v_tag || ' Warden B', v_tag || '-wdnb@example.com', null,    v_pg_b, 'active', v_own_b),
    (v_res,   'student', v_tag || ' Resident', null,                         v_p_res, v_pg_a, 'active', v_wdn);
  insert into public.students (id, hostel_id, user_id, full_name, phone, created_by)
  values (v_res_st, v_pg_a, v_res, v_tag || ' Resident', v_p_res, v_wdn);

  if (select signup_source from public.users where id = v_res) <> 'admin' then
    raise exception 'FAIL 0: an account created the old way did not default to signup_source admin';
  end if;

  -- ─── 1. The sign-up profile door ────────────────────────────────────────────────────────
  foreach v_role in array array['manager', 'warden', 'super_admin', 'tenant', ''] loop
    perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, null, null, %L)',
                                  v_x, v_role, 'Some Name', 'self_google'),
                           '22023', 'Only owner and tenant accounts can be created by sign-up.', '1 role ' || v_role);
  end loop;
  perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, null, null, %L)',
                                v_x, 'owner', 'Some Name', 'admin'), '22023', 'Unknown sign-up source.', '1 source');
  perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, null, %L, %L)',
                                v_x, 'owner', 'Some Name', 'other@example.com', 'self_google'),
                         '22023', 'The address does not match the sign-in account.', '1 address');
  perform pg_temp.claims(v_own_a);
  perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, null, null, %L)',
                                v_x, 'owner', 'Some Name', 'self_google'), '42501', 'Not allowed.', '1 not service');
  perform pg_temp.claims(null);

  perform public.svc_create_self_signup_profile(v_g_own,  'owner',   '  Gita    Owner ', null, null, 'self_google');
  perform public.svc_create_self_signup_profile(v_fb_own, 'owner',   'Farid Owner', null, v_tag || '-FBOWN@example.com', 'self_facebook');
  perform public.svc_create_self_signup_profile(v_tc_own, 'owner',   'Tara Owner', '+91 ' || v_p_tc, null, 'self_truecaller');
  perform public.svc_create_self_signup_profile(v_t1,     'student', 'Tanvi Tenant', null, null, 'self_google');
  perform public.svc_create_self_signup_profile(v_t2,     'student', 'Tarun Tenant', v_p_t2, null, 'self_truecaller');

  select count(*) into v_n from public.users
   where id in (v_g_own, v_fb_own, v_tc_own, v_t1, v_t2) and hostel_id is null and status = 'active'
     and not must_change_password and signup_source like 'self\_%';
  if v_n <> 5 then
    raise exception 'FAIL 1: expected 5 self-created profiles, found %', v_n;
  end if;
  if (select full_name from public.users where id = v_g_own) <> 'Gita Owner'
     or (select email_verified_at from public.users where id = v_g_own) is null
     or (select email_verified_at from public.users where id = v_fb_own) is not null
     or (select phone from public.users where id = v_tc_own) <> v_p_tc then
    raise exception 'FAIL 1: name clean-up, Google address proof or phone normalisation is wrong';
  end if;
  perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, null, null, %L)',
                                v_t1, 'student', 'Again', 'self_google'), '23505', null, '1 twice');

  -- ─── 2. users_self_signup_guard ────────────────────────────────────────────────────────
  -- (With a PG, so enforce_role_limits, which fires first, has nothing to say.)
  perform pg_temp.expect(format($q$insert into public.users (id, role, full_name, status, signup_source, hostel_id)
                                  values (%L, 'manager', 'Staff Person', 'active', 'self_google', %L)$q$, v_x, v_pg_a),
                         '22023', 'Only owner and tenant accounts can be created by sign-up.', '2 staff insert');
  perform pg_temp.expect(format($q$insert into public.users (id, role, full_name, status, signup_source)
                                  values (%L, 'student', 'Some Tenant', 'active', 'self_google')$q$, v_x),
                         '42501', 'Sign-up accounts are created by the sign-up service only.', '2 bypass');
  perform pg_temp.expect(format('update public.users set signup_source = %L where id = %L', 'admin', v_t1),
                         '42501', 'The sign-up source of an account cannot be changed.', '2 source to admin');
  perform pg_temp.expect(format('update public.users set signup_source = %L where id = %L', 'self_google', v_res),
                         '42501', 'The sign-up source of an account cannot be changed.', '2 source to self');
  perform pg_temp.expect(format('update public.users set role = %L, hostel_id = %L where id = %L', 'warden', v_pg_a, v_t1),
                         '22023', 'Only owner and tenant accounts can be created by sign-up.', '2 role to staff');
  perform pg_temp.claims(v_t1);
  perform pg_temp.expect(format('update public.users set avatar_path = %L where id = %L',
                                v_t1 || '/avatar/' || gen_random_uuid() || '.jpg', v_t1),
                         '42501', 'Change your photo from your profile.', '2 avatar by hand');

  -- ─── 3. A waiting tenant has no PG; a warden-created resident still must ─────────────────
  perform pg_temp.claims(null);
  perform pg_temp.expect(format('update public.users set hostel_id = null where id = %L', v_res),
                         'P0001', 'A student must belong to a hostel.', '3 admin resident');

  -- ─── 4. Owner onboarding ────────────────────────────────────────────────────────────────
  perform pg_temp.claims(v_own_a);
  perform pg_temp.expect($q$select public.ow_create_first_hostel('My PG', 'pg', 'boys', '1 Some Road', 'Area', 'Town', '560001', 1, 2, 2)$q$,
                         'P0001', 'Your PG is added by the platform administrator for this account.', '4 admin owner');
  perform pg_temp.claims(v_fb_own);
  perform pg_temp.expect($q$select public.ow_create_first_hostel('My PG', 'pg', 'boys', '1 Some Road', 'Area', 'Town', '560001', 1, 2, 2)$q$,
                         'P0001', 'Verify your email address before adding a PG.', '4 unproved address');
  perform pg_temp.claims(v_t1);
  perform pg_temp.expect($q$select public.ow_create_first_hostel('My PG', 'pg', 'boys', '1 Some Road', 'Area', 'Town', '560001', 1, 2, 2)$q$,
                         '42501', 'Only an owner account can add a PG here.', '4 tenant');
  perform pg_temp.claims(v_g_own);
  perform pg_temp.expect($q$select public.ow_create_first_hostel('My PG', 'pg', 'boys', '1 Some Road', 'Area', 'Town', '060001', 1, 2, 2)$q$,
                         'P0001', 'Enter a valid 6-digit pincode.', '4 pincode');
  perform pg_temp.expect($q$select public.ow_create_first_hostel('My PG', 'pg', 'boys', '1 Some Road', 'Area', 'Town', '560001', 1, 2, 2, 77.6, 12.9)$q$,
                         'P0001', 'That map pin is outside India. Try again or skip it.', '4 swapped pin');

  v_j := public.ow_create_first_hostel(v_tag || ' Gamma PG', 'co_living', 'girls', '12 Test Road, Testpur', 'Sector 9',
                                       'City ' || v_tag, '560001', 2, 5, 3, 12.900000, 77.600000);
  v_pg_g := (v_j ->> 'hostel_id')::uuid;
  v_trial_end := (v_j ->> 'trial_end')::date;
  if v_trial_end <> app.today() + 30 or (v_j ->> 'trial_start')::date <> app.today() then
    raise exception 'FAIL 4: trial dates %', v_j;
  end if;
  if not exists (select 1 from public.hostels where id = v_pg_g and owner_user_id = v_g_own and property_type = 'co_living'
                   and gender_policy = 'girls' and city = 'City ' || v_tag and pincode = '560001' and listed
                   and total_floors = 2 and total_rooms = 5 and beds_per_room_default = 3) then
    raise exception 'FAIL 4: the PG row is wrong';
  end if;
  if not exists (select 1 from public.subscriptions where hostel_id = v_pg_g and kind = 'trial' and amount = 0
                   and start_date = app.today() and end_date = app.today() + 30 and notes = 'free trial'
                   and status in ('active', 'expiring')) then
    raise exception 'FAIL 4: the trial subscription is wrong';
  end if;
  select count(*) into v_n from public.rooms where hostel_id = v_pg_g;
  select count(*) into v_m from public.beds where hostel_id = v_pg_g;
  if v_n <> 5 or v_m <> 15 then
    raise exception 'FAIL 4: scaffold made % rooms and % beds, expected 5 and 15', v_n, v_m;
  end if;
  if (select hostel_id from public.users where id = v_g_own) is distinct from v_pg_g then
    raise exception 'FAIL 4: the owner was not bound to the new PG';
  end if;
  if not coalesce(app.hostel_writable(v_pg_g), false) or not coalesce(app.owns_hostel(v_pg_g), false) then
    raise exception 'FAIL 4: the trial PG is not writable / owned';
  end if;
  if not exists (select 1 from public.notifications where user_id = v_sa and hostel_id = v_pg_g and title = 'New PG signed up'
                   and body = v_tag || ' Gamma PG, City ' || v_tag) then
    raise exception 'FAIL 4: the Super Admin was not told';
  end if;
  if not exists (select 1 from public.audit_log where action = 'owner.hostel.self_created' and hostel_id = v_pg_g and actor_user_id = v_g_own) then
    raise exception 'FAIL 4: no audit row';
  end if;
  perform pg_temp.expect($q$select public.ow_create_first_hostel('Second PG', 'pg', 'boys', '1 Some Road', 'Area', 'Town', '560001', 1, 2, 2)$q$,
                         'P0001', 'Your PG is already set up.', '4 second PG');
  if public.ow_plan_status(v_pg_g) ->> 'state' <> 'trial' then
    raise exception 'FAIL 4: ow_plan_status says % for a trial', public.ow_plan_status(v_pg_g) ->> 'state';
  end if;

  perform pg_temp.claims(v_tc_own);
  v_pg_tc := (public.ow_create_first_hostel(v_tag || ' Tango PG', 'pg', 'boys', '9 Test Lane, Testpur', 'Sector 7',
                                            'Town ' || v_tag, '400001', 1, 2, 2) ->> 'hostel_id')::uuid;
  if v_pg_tc is null then
    raise exception 'FAIL 4: a Truecaller owner (synthetic address) could not add a PG';
  end if;

  -- ─── 5. users.hostel_id is never client-writable ────────────────────────────────────────
  perform pg_temp.claims(v_t1);
  perform pg_temp.expect(format('update public.users set hostel_id = %L where id = %L', v_pg_a, v_t1),
                         '42501', 'You cannot move an account to another hostel.', '5 tenant links self');
  -- Even with the transaction-local marker forged, with no accepted request there is no path.
  perform set_config('app.linking_student', v_t1::text || ':' || v_pg_a::text, true);
  perform pg_temp.claims(v_own_a);
  perform pg_temp.expect(format('update public.users set hostel_id = %L where id = %L', v_pg_a, v_t1),
                         '42501', 'You cannot move an account to another hostel.', '5 forged marker');
  perform set_config('app.linking_student', '', true);
  perform pg_temp.claims(v_tc_own);
  perform pg_temp.expect(format('update public.users set hostel_id = %L where id = %L', v_pg_b, v_tc_own),
                         '42501', 'You cannot move an account to another hostel.', '5 owner moves self');

  -- ─── 6. Profile and photo ───────────────────────────────────────────────────────────────
  perform pg_temp.claims(v_t1);
  perform pg_temp.expect($q$select public.me_update_profile(p_phone => '12345')$q$,
                         'P0001', 'Enter a valid 10-digit mobile number.', '6 phone');
  perform pg_temp.expect(format('select public.me_update_profile(p_date_of_birth => %L::date)', current_date),
                         'P0001', 'Enter a valid date of birth.', '6 dob');
  perform pg_temp.expect(format('select public.me_update_profile(%L, %L, %L, %L::date, %L, %L)',
                                'Tanvi T', '+91 ' || v_p_t1, 'female', '2004-05-06', 'Mother T', v_p_t1),
                         'P0001', 'The emergency contact needs a different number from yours.', '6 same number');
  v_j := public.me_update_profile('Tanvi T', '+91 ' || v_p_t1, 'Female', date '2004-05-06', 'Mother T', '0' || v_p_em);
  if v_j ->> 'phone' <> v_p_t1 or v_j ->> 'gender' <> 'female' or v_j ->> 'emergency_contact_phone' <> v_p_em
     or (select date_of_birth from public.users where id = v_t1) <> date '2004-05-06' then
    raise exception 'FAIL 6: profile not saved as normalised: %', v_j;
  end if;
  -- NULL keeps a value, '' clears an optional one.
  v_j := public.me_update_profile(p_gender => '');
  if v_j ->> 'gender' is not null or v_j ->> 'phone' <> v_p_t1 then
    raise exception 'FAIL 6: partial update semantics: %', v_j;
  end if;
  perform public.me_update_profile(p_gender => 'female');

  perform pg_temp.expect(format('select public.st_request_join(%L)', v_pg_a),
                         'P0001', 'Add a profile photo before sending a request.', '6 no photo');

  v_av1 := v_t1::text || '/avatar/' || gen_random_uuid() || '.jpg';
  v_av2 := v_t1::text || '/avatar/' || gen_random_uuid() || '.jpg';
  perform pg_temp.expect(format('select public.me_set_avatar(%L)', v_av1),
                         'P0001', 'The photo did not finish uploading. Please try again.', '6 not uploaded');
  insert into storage.objects (bucket_id, name, owner_id) values ('avatars', v_av1, v_t1::text), ('avatars', v_av2, v_t1::text);
  perform pg_temp.expect(format('select public.me_set_avatar(%L)', v_t2::text || '/avatar/' || gen_random_uuid() || '.jpg'),
                         'P0001', 'That photo could not be used. Please try again.', '6 someone else''s key');
  perform public.me_set_avatar(v_av1);
  perform public.me_set_avatar(v_av2);
  if (select avatar_path from public.users where id = v_t1) <> v_av2 then
    raise exception 'FAIL 6: the avatar was not saved';
  end if;
  if not exists (select 1 from app.storage_erasures where bucket = 'avatars' and object_path = v_av1
                   and reason = 'account.avatar_replaced') then
    raise exception 'FAIL 6: the replaced photo was not queued for erasure';
  end if;

  -- ─── 7. Storage: uploads under your own id only ─────────────────────────────────────────
  v_av_t2  := v_t2::text || '/avatar/' || gen_random_uuid() || '.jpg';
  v_doc_t2 := v_t2::text || '/document/' || gen_random_uuid() || '.pdf';
  perform pg_temp.claims(v_t2);
  perform pg_temp.rls(true);
  insert into storage.objects (bucket_id, name, owner_id) values ('avatars', v_av_t2, v_t2::text);
  insert into storage.objects (bucket_id, name, owner_id) values ('identity-documents', v_doc_t2, v_t2::text);
  perform pg_temp.expect(format($q$insert into storage.objects (bucket_id, name, owner_id) values ('avatars', %L, %L)$q$,
                                v_t1::text || '/avatar/' || gen_random_uuid() || '.jpg', v_t2::text),
                         '42501', null, '7 upload as someone else');
  perform pg_temp.expect(format($q$insert into storage.objects (bucket_id, name, owner_id) values ('avatars', %L, %L)$q$,
                                v_t2::text || '/photo.jpg', v_t2::text),
                         '42501', null, '7 upload with a free-form key');
  perform pg_temp.expect(format($q$insert into storage.objects (bucket_id, name, owner_id) values ('identity-documents', %L, %L)$q$,
                                v_t2::text || '/document/' || gen_random_uuid() || '.exe', v_t2::text),
                         '42501', null, '7 upload with a bad extension');
  perform pg_temp.rls(false);

  -- Staff and resident photos, written as the service role, for the visibility checks.
  perform pg_temp.claims(null);
  v_av_wdn := v_wdn::text || '/avatar/' || gen_random_uuid() || '.jpg';
  v_av_res := v_res::text || '/avatar/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name, owner_id) values ('avatars', v_av_wdn, v_wdn::text), ('avatars', v_av_res, v_res::text);
  update public.users set avatar_path = v_av_wdn where id = v_wdn;
  update public.users set avatar_path = v_av_res where id = v_res;

  perform pg_temp.rls(true);
  for v_j in
    select * from jsonb_array_elements(jsonb_build_array(
      -- who,          which key, visible?
      jsonb_build_array(v_t1,    v_av2,    1),   -- self
      jsonb_build_array(v_own_b, v_av2,    0),   -- no relationship yet
      jsonb_build_array(v_own_a, v_av_wdn, 1),   -- owner sees their warden
      jsonb_build_array(v_own_a, v_av_res, 1),   -- owner sees their resident
      jsonb_build_array(v_mgr,   v_av_wdn, 1),   -- manager sees staff photos
      jsonb_build_array(v_mgr,   v_av_res, 0),   -- ... never a resident's
      jsonb_build_array(v_wdn,   v_av_res, 1),   -- warden sees the resident
      jsonb_build_array(v_own_b, v_av_res, 0),   -- another owner does not
      jsonb_build_array(v_sa,    v_av_res, 1),   -- super admin does
      jsonb_build_array(v_t2,    v_av_res, 0)))  -- another tenant does not
  loop
    perform pg_temp.claims((v_j ->> 0)::uuid);
    select count(*) into v_n from storage.objects where bucket_id = 'avatars' and name = v_j ->> 1;
    if v_n <> (v_j ->> 2)::int then
      raise exception 'FAIL 7: % sees % copies of %', v_j ->> 0, v_n, v_j ->> 1;
    end if;
  end loop;
  perform pg_temp.rls(false);

  -- ─── 8. Identity documents ──────────────────────────────────────────────────────────────
  perform pg_temp.claims(v_t2);
  perform pg_temp.expect(format('select public.me_add_document(%L, %L)', 'ration_card', v_doc_t2),
                         'P0001', 'Choose the type of document.', '8 kind');
  perform pg_temp.expect(format('select public.me_add_document(%L, %L)', 'pan', v_t1::text || '/document/' || gen_random_uuid() || '.pdf'),
                         'P0001', 'That file could not be used. Please try again.', '8 someone else''s key');
  v_j := public.me_add_document('pan', v_doc_t2);
  if v_j ->> 'storage_path' <> v_doc_t2 or v_j ->> 'kind' <> 'pan' then
    raise exception 'FAIL 8: me_add_document returned %', v_j;
  end if;
  perform pg_temp.rls(true);
  perform pg_temp.claims(v_own_b);
  select count(*) into v_n from public.user_documents where user_id = v_t2;
  select count(*) into v_m from storage.objects where bucket_id = 'identity-documents' and name = v_doc_t2;
  if v_n <> 0 or v_m <> 0 then
    raise exception 'FAIL 8: an unrelated owner sees % document rows and % files', v_n, v_m;
  end if;
  perform pg_temp.claims(v_t2);
  select count(*) into v_n from public.user_documents where user_id = v_t2;
  if v_n <> 1 then
    raise exception 'FAIL 8: the owner of a document cannot see it (% rows)', v_n;
  end if;
  perform pg_temp.expect($q$insert into public.user_documents (user_id, kind, storage_path) values (auth.uid(), 'pan', 'x')$q$,
                         '42501', null, '8 client insert');
  perform pg_temp.rls(false);

  -- ─── 9. Finding a PG ────────────────────────────────────────────────────────────────────
  perform pg_temp.claims(v_t1);
  select string_agg(s.name, ',' order by s.name) into v_s from public.st_search_hostels(v_tag) s;
  if v_s is distinct from v_tag || ' Alpha PG,' || v_tag || ' Beta PG,' || v_tag || ' Gamma PG,' || v_tag || ' Tango PG' then
    raise exception 'FAIL 9: search by name found %', v_s;
  end if;
  select count(*) into v_n from public.st_search_hostels('Town ' || v_tag);
  if v_n <> 1 then
    raise exception 'FAIL 9: search by city found % PGs', v_n;
  end if;
  select string_agg(s.name, ',' order by s.distance_km),
         max(s.distance_km) filter (where s.name = v_tag || ' Alpha PG'),
         max(s.distance_km) filter (where s.name = v_tag || ' Beta PG')
    into v_s, v_k1, v_k2
    from public.st_nearby_hostels(12.971600, 77.594600) s where s.name like v_tag || '%';
  -- Beta is 0.01 degrees north and east: 1.55 km. Unlisted, expired and suspended PGs, and
  -- the Tango PG (no pin), are not offered.
  if v_s is distinct from v_tag || ' Alpha PG,' || v_tag || ' Beta PG,' || v_tag || ' Gamma PG'
     or v_k1 <> 0.0 or v_k2 not between 1.5 and 1.6 then
    raise exception 'FAIL 9: nearby found % (Alpha % km, Beta % km)', v_s, v_k1, v_k2;
  end if;
  if pg_get_function_result('public.st_nearby_hostels(numeric,numeric)'::regprocedure) ~* '(address|owner|phone|latitude)'
     or pg_get_function_result('public.st_search_hostels(text)'::regprocedure) ~* '(address|owner|phone|latitude)' then
    raise exception 'FAIL 9: a search returns an address, owner, phone or coordinates';
  end if;
  perform pg_temp.expect($q$select * from public.st_search_hostels('a')$q$,
                         'P0001', 'Type at least 2 letters of the PG name or city.', '9 short query');
  if exists (select 1 from public.audit_log where meta::text like '%12.9716%') then
    raise exception 'FAIL 9: the caller''s location was written down';
  end if;
  perform pg_temp.claims(v_own_a);
  perform pg_temp.expect(format('select * from public.st_search_hostels(%L)', v_tag),
                         '42501', 'Only a tenant account can search for PGs.', '9 owner searches');

  -- ─── 10. Join requests ──────────────────────────────────────────────────────────────────
  perform pg_temp.claims(v_t1);
  perform pg_temp.expect(format('select public.st_request_join(%L)', v_pg_u),
                         'P0001', 'This PG is not taking requests right now.', '10 unlisted');
  perform pg_temp.expect(format('select public.st_request_join(%L)', v_pg_x),
                         'P0001', 'This PG is not taking requests right now.', '10 expired');
  v_j := public.st_request_join(v_pg_a, 'Hi, I would like a bed.');
  v_req1 := (v_j ->> 'request_id')::uuid;
  if v_j ->> 'status' <> 'pending' or v_j ->> 'hostel_name' <> v_tag || ' Alpha PG' then
    raise exception 'FAIL 10: st_request_join returned %', v_j;
  end if;
  perform pg_temp.expect(format('select public.st_request_join(%L)', v_pg_b),
                         'P0001', 'You already asked to join %', '10 second request');
  if public.st_my_join_request() ->> 'status' <> 'pending' then
    raise exception 'FAIL 10: st_my_join_request does not show the pending request';
  end if;
  select count(*) into v_n from public.notifications
   where title = 'New join request' and hostel_id = v_pg_a
     and ((user_id = v_own_a and link = '/owner/join-requests') or (user_id = v_wdn and link = '/warden/join-requests'));
  select count(*) into v_m from public.notifications where title = 'New join request' and user_id = v_mgr;
  if v_n <> 2 or v_m <> 0 then
    raise exception 'FAIL 10: owner+warden notified %, manager notified %', v_n, v_m;
  end if;

  perform pg_temp.rls(true);
  for v_j in
    select * from jsonb_array_elements(jsonb_build_array(
      jsonb_build_array(v_t1, 1), jsonb_build_array(v_own_a, 1), jsonb_build_array(v_wdn, 1),
      jsonb_build_array(v_own_b, 0), jsonb_build_array(v_mgr, 0), jsonb_build_array(v_t2, 0),
      jsonb_build_array(v_wdn_b, 0)))
  loop
    perform pg_temp.claims((v_j ->> 0)::uuid);
    select count(*) into v_n from public.hostel_join_requests where id = v_req1;
    if v_n <> (v_j ->> 1)::int then
      raise exception 'FAIL 10: % sees % rows of the request', v_j ->> 0, v_n;
    end if;
  end loop;
  -- A pending request lets that PG's owner and warden see the requester's photo.
  perform pg_temp.claims(v_wdn);
  select count(*) into v_n from storage.objects where bucket_id = 'avatars' and name = v_av2;
  perform pg_temp.claims(v_wdn_b);
  select count(*) into v_m from storage.objects where bucket_id = 'avatars' and name = v_av2;
  if v_n <> 1 or v_m <> 0 then
    raise exception 'FAIL 10: requester photo visible to the PG warden %, to another warden %', v_n, v_m;
  end if;
  perform pg_temp.rls(false);

  perform pg_temp.claims(v_own_a);
  select count(*), max(r.avatar_path), max(r.phone) into v_n, v_s, v_role
    from public.ow_join_requests() r where r.request_id = v_req1;
  if v_n <> 1 or v_s <> v_av2 or v_role <> v_p_t1 then
    raise exception 'FAIL 10: the owner''s list shows % rows (photo %, phone %)', v_n, v_s, v_role;
  end if;
  if public.ow_pending_join_request_count() < 1 then
    raise exception 'FAIL 10: the badge count is zero';
  end if;
  perform pg_temp.claims(v_own_b);
  select count(*) into v_n from public.ow_join_requests() r where r.request_id = v_req1;
  if v_n <> 0 then
    raise exception 'FAIL 10: another owner lists the request';
  end if;
  perform pg_temp.expect(format('select * from public.ow_join_requests(%L)', v_pg_a), '42501', 'Not allowed.', '10 other owner by id');
  perform pg_temp.expect(format('select public.ow_decide_join_request(%L, true)', v_req1),
                         'P0001', 'This request is no longer available.', '10 other owner decides');
  perform pg_temp.claims(v_mgr);
  perform pg_temp.expect('select * from public.ow_join_requests()', '42501', 'Not allowed.', '10 manager lists');

  perform pg_temp.claims(v_wdn);
  v_j := public.ow_decide_join_request(v_req1, true);
  v_t1_st := (v_j ->> 'student_id')::uuid;
  if v_j ->> 'status' <> 'accepted' or v_t1_st is null then
    raise exception 'FAIL 10: accept returned %', v_j;
  end if;
  if not exists (select 1 from public.students where id = v_t1_st and hostel_id = v_pg_a and user_id = v_t1
                   and phone = v_p_t1 and guardian_name = 'Mother T' and guardian_phone = v_p_em
                   and monthly_fee = 0 and room_id is null and status = 'active') then
    raise exception 'FAIL 10: the roster row is wrong';
  end if;
  if (select hostel_id from public.users where id = v_t1) is distinct from v_pg_a then
    raise exception 'FAIL 10: the tenant account was not linked';
  end if;
  if not exists (select 1 from public.notifications where user_id = v_t1 and title = 'Request accepted') then
    raise exception 'FAIL 10: the tenant was not told';
  end if;
  perform pg_temp.expect(format('select public.ow_decide_join_request(%L, false)', v_req1),
                         'P0001', 'This request was already handled.', '10 decide twice');
  perform pg_temp.claims(v_t1);
  if app.user_hostel_id() is distinct from v_pg_a then
    raise exception 'FAIL 10: the linked tenant does not resolve to the PG';
  end if;
  perform pg_temp.expect(format('select public.st_request_join(%L)', v_pg_b),
                         'P0001', 'You are already part of a PG.%', '10 linked tenant asks again');

  -- Decline, with a note; then the tenant can ask elsewhere; cancel.
  perform pg_temp.claims(v_t2);
  perform public.me_set_avatar(v_av_t2);
  v_req2 := (public.st_request_join(v_pg_b) ->> 'request_id')::uuid;
  perform pg_temp.rls(true);
  perform pg_temp.claims(v_own_b);
  select count(*) into v_n from public.user_documents where user_id = v_t2;
  select count(*) into v_m from storage.objects where bucket_id = 'identity-documents' and name = v_doc_t2;
  if v_n <> 1 or v_m <> 1 then
    raise exception 'FAIL 10: the PG being asked cannot see the requester''s documents (% rows, % files)', v_n, v_m;
  end if;
  perform pg_temp.claims(v_wdn_b);
  select count(*) into v_n from public.user_documents where user_id = v_t2;
  perform pg_temp.claims(v_own_a);
  select count(*) into v_m from public.user_documents where user_id = v_t2;
  if v_n <> 1 or v_m <> 0 then
    raise exception 'FAIL 10: documents visible to the asked warden %, to an unrelated owner %', v_n, v_m;
  end if;
  perform pg_temp.claims(v_mgr);
  select count(*) into v_n from public.user_documents where user_id = v_t2;
  if v_n <> 0 then
    raise exception 'FAIL 10: a manager sees documents';
  end if;
  perform pg_temp.rls(false);

  perform pg_temp.claims(v_own_b);
  v_j := public.ow_decide_join_request(v_req2, false, 'No beds this month');
  if v_j ->> 'status' <> 'declined'
     or not exists (select 1 from public.notifications where user_id = v_t2 and title = 'Request declined'
                      and body like '%Note: No beds this month') then
    raise exception 'FAIL 10: decline returned % or did not notify', v_j;
  end if;
  perform pg_temp.claims(v_t2);
  if public.st_my_join_request() ->> 'status' <> 'declined' then
    raise exception 'FAIL 10: the declined request is not shown to the tenant';
  end if;
  v_req3 := (public.st_request_join(v_pg_a) ->> 'request_id')::uuid;
  if public.st_cancel_join_request() ->> 'status' <> 'cancelled' then
    raise exception 'FAIL 10: cancel failed';
  end if;
  perform pg_temp.expect('select public.st_cancel_join_request()', 'P0001', 'You have no pending request.', '10 cancel twice');

  -- A waiting tenant calling the resident RPCs gets nothing, not an error.
  select count(*) into v_n from public.st_hostel_contacts();
  select count(*) into v_m from public.st_my_roommates();
  if v_n <> 0 or v_m <> 0 then
    raise exception 'FAIL 10: a waiting tenant sees contacts (%) or roommates (%)', v_n, v_m;
  end if;

  -- ─── 11. Leaving: the owner removes the tenant, who can then ask another PG ──────────────
  perform pg_temp.claims(v_own_a);
  perform public.wd_vacate_student(v_t1_st);
  if not exists (select 1 from public.students where id = v_t1_st and status = 'vacated' and user_id is null
                   and erasure_due_at is not null) then
    raise exception 'FAIL 11: the roster row did not let go of the account';
  end if;
  if not exists (select 1 from public.users where id = v_t1 and hostel_id is null and status = 'active') then
    raise exception 'FAIL 11: the tenant account was not unlinked';
  end if;
  if not exists (select 1 from public.notifications where user_id = v_t1 and title = 'You have left ' || v_tag || ' Alpha PG') then
    raise exception 'FAIL 11: the tenant was not told';
  end if;
  perform pg_temp.claims(v_t1);
  if public.st_request_join(v_pg_b) ->> 'status' <> 'pending' then
    raise exception 'FAIL 11: the unlinked tenant cannot ask another PG';
  end if;
  perform public.st_cancel_join_request();
  -- The owner checking out a warden-created resident with a login used to fail here.
  perform pg_temp.claims(v_own_a);
  perform public.wd_vacate_student(v_res_st);
  if not exists (select 1 from public.users where id = v_res and status = 'inactive' and hostel_id = v_pg_a)
     or not exists (select 1 from public.students where id = v_res_st and status = 'vacated' and user_id = v_res) then
    raise exception 'FAIL 11: an owner could not check out a warden-created resident the old way';
  end if;

  -- ─── 12. Book a demo ────────────────────────────────────────────────────────────────────
  perform pg_temp.claims(v_g_own);
  v_ts := ((app.today() + 2)::timestamp + interval '9 hours') at time zone 'Asia/Kolkata';
  perform pg_temp.expect(format('select public.ow_book_demo(%L, %L, %L, %L, %L, %L::timestamptz)',
                                'Gita', v_p_em, 'Gamma PG', 'Testpur', '21-50', v_ts),
                         'P0001', 'Pick a day in the next two weeks%', '12 9 AM');
  v_ts := ((app.today() + 2)::timestamp + interval '11 hours') at time zone 'Asia/Kolkata';
  perform pg_temp.expect(format('select public.ow_book_demo(%L, %L, %L, %L, %L, %L::timestamptz)',
                                'Gita', v_p_em, 'Gamma PG', 'Testpur', '20-50', v_ts),
                         'P0001', 'Choose how many beds your PG has.', '12 band');
  v_j := public.ow_book_demo('Gita', '+91' || v_p_em, 'Gamma PG', 'Testpur', '21-50', v_ts);
  if v_j ->> 'status' <> 'requested' then
    raise exception 'FAIL 12: booking returned %', v_j;
  end if;
  perform pg_temp.expect(format('select public.ow_book_demo(%L, %L, %L, %L, %L, %L::timestamptz)',
                                'Gita', v_p_em, 'Gamma PG', 'Testpur', '21-50', v_ts + interval '1 day'),
                         'P0001', 'You already have a demo booked for %', '12 second open');
  if public.ow_my_demo_request() ->> 'status' <> 'requested'
     or not exists (select 1 from public.notifications where user_id = v_sa and title = 'New demo request') then
    raise exception 'FAIL 12: the open demo is not visible or the Super Admin was not told';
  end if;
  perform pg_temp.claims(v_own_a);
  perform pg_temp.expect('select * from public.sa_demo_requests()', '42501', 'Not allowed.', '12 owner lists all demos');
  perform pg_temp.claims(v_sa);
  select count(*) into v_n from public.sa_demo_requests() d where d.owner_user_id = v_g_own and d.phone = v_p_em;
  if v_n <> 1 then
    raise exception 'FAIL 12: the Super Admin sees % of the demo', v_n;
  end if;
  if public.sa_update_demo_request((v_j ->> 'id')::uuid, 'confirmed', 'Call at 11') ->> 'status' <> 'confirmed' then
    raise exception 'FAIL 12: the Super Admin could not confirm';
  end if;
  perform pg_temp.expect(format('select public.sa_update_demo_request(%L, %L)', v_j ->> 'id', 'lost'),
                         'P0001', 'Choose a valid status.', '12 bad status');
  perform pg_temp.rls(true);
  perform pg_temp.claims(v_own_b);
  select count(*) into v_n from public.demo_requests where owner_user_id = v_g_own;
  perform pg_temp.claims(v_g_own);
  select count(*) into v_m from public.demo_requests where owner_user_id = v_g_own;
  if v_n <> 0 or v_m <> 1 then
    raise exception 'FAIL 12: demo rows visible to another owner %, to the booker %', v_n, v_m;
  end if;
  perform pg_temp.rls(false);
  perform public.ow_cancel_demo_request();
  if public.ow_book_demo('Gita', v_p_em, 'Gamma PG', 'Testpur', '100+', v_ts + interval '1 day') ->> 'status' <> 'requested' then
    raise exception 'FAIL 12: could not book again after cancelling';
  end if;

  -- ─── 13. Plans and plan payments ────────────────────────────────────────────────────────
  perform pg_temp.claims(v_t1);
  select string_agg(c.plan_id || ':' || c.amount_paise || ':' || c.total_months || ':' || c.saving_vs_monthly, ',' order by c.sort_order)
    into v_s from public.plan_catalog() c;
  if v_s <> 'monthly:109900:1:0.00,quarterly:299700:3:300.00,yearly:1150800:13:2779.00' then
    raise exception 'FAIL 13: the catalogue is %', v_s;
  end if;

  perform pg_temp.claims(null);
  perform pg_temp.expect(format('select public.svc_open_subscription_order(%L, %L, %L, %L, %s)',
                                v_g_own, v_pg_g, 'monthly', 'order_' || v_t || 'A1', 100),
                         'P0001', 'The plan price changed. Please try again.', '13 client amount');
  perform pg_temp.expect(format('select public.svc_open_subscription_order(%L, %L, %L, %L, %s)',
                                v_own_b, v_pg_g, 'monthly', 'order_' || v_t || 'A1', 109900),
                         'P0001', 'Hostel not found.', '13 not the owner');
  perform pg_temp.expect(format('select public.svc_open_subscription_order(%L, %L, %L, %L, %s)',
                                v_own_b, v_pg_s, 'monthly', 'order_' || v_t || 'A1', 109900),
                         'P0001', 'This hostel is suspended. Contact support.', '13 suspended');
  perform pg_temp.expect(format('select public.svc_open_subscription_order(%L, %L, %L, %L, %s)',
                                v_g_own, v_pg_g, 'gold', 'order_' || v_t || 'A1', 109900),
                         'P0001', 'Choose a plan.', '13 unknown plan');
  perform public.svc_open_subscription_order(v_g_own, v_pg_g, 'monthly', 'order_' || v_t || 'A1', 109900);
  perform pg_temp.expect(format('select public.svc_activate_subscription_payment(%L, %L, %s, %L, %L)',
                                'order_' || v_t || 'A1', 'pay_' || v_t || 'P1', 100, 'upi', 'checkout'),
                         'P0001', 'Paid amount does not match the order.', '13 wrong amount');
  perform pg_temp.expect(format('select public.svc_activate_subscription_payment(%L, %L, %s, %L, %L)',
                                'order_' || v_t || 'ZZ', 'pay_' || v_t || 'P1', 109900, 'upi', 'webhook'),
                         'P0001', 'Unknown subscription order.', '13 unknown order');
  v_j := public.svc_activate_subscription_payment('order_' || v_t || 'A1', 'pay_' || v_t || 'P1', 109900, 'upi', 'checkout');
  if v_j ->> 'outcome' <> 'paid' or (v_j ->> 'period_start')::date <> v_trial_end + 1
     or (v_j ->> 'period_end')::date <> (v_trial_end + interval '1 month')::date then
    raise exception 'FAIL 13: monthly on a trial gave % (trial ends %)', v_j, v_trial_end;
  end if;
  v_j := public.svc_activate_subscription_payment('order_' || v_t || 'A1', 'pay_' || v_t || 'P1', 109900, 'upi', 'webhook');
  select count(*) into v_n from public.subscriptions where hostel_id = v_pg_g and kind = 'paid';
  if v_j ->> 'outcome' <> 'duplicate' or v_n <> 1 then
    raise exception 'FAIL 13: the second delivery was not a no-op (%, % paid rows)', v_j, v_n;
  end if;
  perform pg_temp.expect(format('select public.svc_activate_subscription_payment(%L, %L, %s, %L, %L)',
                                'order_' || v_t || 'A1', 'pay_' || v_t || 'P2', 109900, 'upi', 'webhook'),
                         'P0001', 'Order already settled by a different payment.', '13 other payment');
  perform pg_temp.claims(v_g_own);
  v_j := public.ow_plan_status(v_pg_g);
  if v_j ->> 'state' not in ('active', 'expiring') or v_j ->> 'plan_kind' <> 'paid'
     or v_j -> 'last_payment' ->> 'plan_id' <> 'monthly' or (v_j ->> 'writable')::boolean is not true then
    raise exception 'FAIL 13: plan status after paying is %', v_j;
  end if;

  -- Yearly is 12 months plus 1 free; on an expired PG the new period starts today.
  perform pg_temp.claims(null);
  v_d := (select max(end_date) from public.subscriptions where hostel_id = v_pg_tc and cancelled_at is null);
  perform public.svc_open_subscription_order(v_tc_own, v_pg_tc, 'yearly', 'order_' || v_t || 'Y1', 1150800);
  v_j := public.svc_activate_subscription_payment('order_' || v_t || 'Y1', 'pay_' || v_t || 'Y1', 1150800, 'card', 'webhook');
  if (v_j ->> 'period_end')::date <> (v_d + interval '13 months')::date then
    raise exception 'FAIL 13: yearly gave % from %', v_j, v_d;
  end if;
  if (select status from public.hostels where id = v_pg_x) <> 'readonly' then
    raise exception 'FAIL 13: the expired fixture PG is not read-only to begin with';
  end if;
  perform public.svc_open_subscription_order(v_own_a, v_pg_x, 'monthly', 'order_' || v_t || 'X1', 109900);
  v_j := public.svc_activate_subscription_payment('order_' || v_t || 'X1', 'pay_' || v_t || 'X1', 109900, 'upi', 'checkout');
  if (v_j ->> 'period_start')::date <> app.today()
     or (v_j ->> 'period_end')::date <> (app.today() + interval '1 month')::date
     or (select status from public.hostels where id = v_pg_x) <> 'active' then
    raise exception 'FAIL 13: paying for an expired PG gave % and left it %', v_j, (select status from public.hostels where id = v_pg_x);
  end if;
  perform public.svc_open_subscription_order(v_own_a, v_pg_a, 'quarterly', 'order_' || v_t || 'F1', 299700);
  if not public.svc_mark_subscription_payment_failed('order_' || v_t || 'F1', 'Payment failed')
     or public.svc_mark_subscription_payment_failed('order_' || v_t || 'A1', 'late failure') then
    raise exception 'FAIL 13: a failure was not recorded, or it overwrote a paid order';
  end if;

  perform pg_temp.rls(true);
  perform pg_temp.claims(v_g_own);
  perform pg_temp.expect(format('select public.svc_activate_subscription_payment(%L, %L, %s, %L, %L)',
                                'order_' || v_t || 'F1', 'pay_' || v_t || 'F1', 299700, 'upi', 'checkout'),
                         '42501', null, '13 client activates');
  select count(*) into v_n from public.subscription_payments where hostel_id = v_pg_g;
  perform pg_temp.claims(v_own_b);
  select count(*) into v_m from public.subscription_payments where hostel_id = v_pg_g;
  if v_n <> 1 or v_m <> 0 then
    raise exception 'FAIL 13: payments visible to the owner %, to another owner %', v_n, v_m;
  end if;
  perform pg_temp.expect($q$update public.platform_plans set amount = 1, price_per_month = 1 where id = 'monthly'$q$,
                         '42501', null, '13 client edits a price');
  perform pg_temp.rls(false);

  -- ─── 14. An owner deletes a warden ──────────────────────────────────────────────────────
  perform pg_temp.claims(null);
  perform pg_temp.expect(format('select public.svc_delete_staff_account(%L, %L)', v_own_b, v_wdn),
                         'P0001', 'Staff member not found.', '14 another owner');
  perform pg_temp.expect(format('select public.svc_delete_staff_account(%L, %L)', v_own_a, v_t1),
                         'P0001', 'Staff member not found.', '14 not staff');
  v_j := public.svc_delete_staff_account(v_own_a, v_wdn);
  if v_j ->> 'role' <> 'warden' or (v_j ->> 'already_deleted')::boolean then
    raise exception 'FAIL 14: delete returned %', v_j;
  end if;
  if not exists (select 1 from public.users where id = v_wdn and full_name = 'Deleted staff member' and email is null
                   and status = 'inactive' and deleted_at is not null and avatar_path is null) then
    raise exception 'FAIL 14: the profile is not a tombstone';
  end if;
  if not exists (select 1 from auth.users where id = v_wdn and email like 'deleted-%@identity.apnivaas.invalid'
                   and deleted_at is not null and banned_until > now() and encrypted_password is null) then
    raise exception 'FAIL 14: the login was not soft-deleted';
  end if;
  select count(*) into v_n from public.login_account_for_email(v_tag || '-wdn@example.com');
  select count(*) into v_m from public.staff_hostel_access where user_id = v_wdn;
  if v_n <> 0 or v_m <> 0 then
    raise exception 'FAIL 14: the old address still finds % accounts, % access rows left', v_n, v_m;
  end if;
  if not exists (select 1 from app.storage_erasures where bucket = 'avatars' and object_path = v_av_wdn) then
    raise exception 'FAIL 14: the deleted warden''s photo was not queued';
  end if;
  -- The address is free: the same person can sign up as a tenant or owner.
  insert into auth.users (id, email) values (v_new, v_tag || '-wdn@example.com');
  perform public.svc_create_self_signup_profile(v_new, 'student', 'Former Warden', null, null, 'self_google');
  if (select count(*) from public.login_account_for_email(v_tag || '-wdn@example.com') l where l.role = 'student') <> 1 then
    raise exception 'FAIL 14: the freed address does not find the new account';
  end if;
  v_j := public.svc_delete_staff_account(v_own_a, v_wdn);
  if not (v_j ->> 'already_deleted')::boolean then
    raise exception 'FAIL 14: a repeat delete was not idempotent: %', v_j;
  end if;
  perform pg_temp.rls(true);
  perform pg_temp.claims(v_own_a);
  perform pg_temp.expect(format('select public.svc_delete_staff_account(%L, %L)', v_own_a, v_mgr),
                         '42501', null, '14 client calls the service function');
  perform pg_temp.rls(false);

  -- ─── 15. Facebook / Truecaller identities, phone matching ───────────────────────────────
  perform pg_temp.claims(null);
  if not public.svc_link_external_identity('facebook', v_tag || '-fb1', v_fb_own) then
    raise exception 'FAIL 15: could not link a Facebook identity to an owner';
  end if;
  select count(*), max(l.role::text) into v_n, v_s from public.svc_login_account_for_external('facebook', v_tag || '-fb1') l;
  if v_n <> 1 or v_s <> 'owner' then
    raise exception 'FAIL 15: the lookup found % rows, role %', v_n, v_s;
  end if;
  if public.svc_link_external_identity('facebook', v_tag || '-fb1', v_g_own)
     or public.svc_link_external_identity('facebook', v_tag || '-fb2', v_fb_own) then
    raise exception 'FAIL 15: a Facebook profile moved accounts, or an account took a second one';
  end if;
  perform pg_temp.expect(format('select public.svc_link_external_identity(%L, %L, %L)', 'truecaller', v_tag || '-tcs', v_mgr),
                         '42501', 'Staff and administrator accounts sign in with the login they were given.', '15 staff');
  if not public.svc_phone_in_use('+91 ' || v_p_t2) or not public.svc_phone_in_use(v_p_res)
     or public.svc_phone_in_use(v_p_free) then
    raise exception 'FAIL 15: phone matching is wrong';
  end if;
  perform pg_temp.rls(true);
  perform pg_temp.claims(v_fb_own);
  perform pg_temp.expect('select count(*) from public.external_identities', '42501', null, '15 client reads identities');
  perform pg_temp.rls(false);

  -- ─── 16. Synthetic addresses are not reachable ──────────────────────────────────────────
  if app.email_is_reachable('tc-x@identity.apnivaas.invalid') or not app.email_is_reachable('a@example.com')
     or app.email_verification_owed(v_tc_own) or not app.email_verification_owed(v_fb_own) then
    raise exception 'FAIL 16: email reachability is wrong';
  end if;

  -- ─── 17. Retention ──────────────────────────────────────────────────────────────────────
  perform pg_temp.claims(null);
  insert into public.hostel_join_requests (hostel_id, user_id, status, created_at)
  values (v_pg_b, v_t2, 'pending', now() - interval '31 days') returning id into v_req3;
  insert into public.demo_requests (owner_user_id, name, phone, pg_name, city, bed_band, slot_start, status)
  values (v_tc_own, 'Old Demo', v_p_tc, 'Old PG', 'Testpur', '1-20', now() - interval '181 days', 'done');
  v_orphan := v_t2::text || '/avatar/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name, owner_id, created_at) values ('avatars', v_orphan, v_t2::text, now() - interval '2 days');
  perform * from app.apply_retention();
  if (select status from public.hostel_join_requests where id = v_req3) <> 'expired'
     or exists (select 1 from public.demo_requests where owner_user_id = v_tc_own and name = 'Old Demo')
     or not exists (select 1 from app.storage_erasures where object_path = v_orphan and reason = 'retention.unused_upload')
     or exists (select 1 from app.storage_erasures where object_path in (v_av2, v_av_t2, v_doc_t2)) then
    raise exception 'FAIL 17: retention expired/deleted/queued the wrong things';
  end if;

  -- ─── 18. A tenant who is in no PG deletes their own account ─────────────────────────────
  perform pg_temp.claims(v_g_own);
  perform pg_temp.expect('select public.me_delete_account()', 'P0001', 'Your account is part of a PG%', '18 owner with a PG');
  perform pg_temp.claims(v_t2);
  if not (public.me_delete_account() ->> 'deleted')::boolean then
    raise exception 'FAIL 18: me_delete_account did not say deleted';
  end if;
  if exists (select 1 from auth.users where id = v_t2) or exists (select 1 from public.users where id = v_t2)
     or exists (select 1 from public.hostel_join_requests where user_id = v_t2)
     or exists (select 1 from public.user_documents where user_id = v_t2) then
    raise exception 'FAIL 18: something of the deleted account is left';
  end if;
  if not exists (select 1 from app.storage_erasures where object_path = v_doc_t2 and reason = 'account.document_deleted')
     or not exists (select 1 from app.storage_erasures where object_path = v_av_t2 and reason = 'account.avatar_deleted') then
    raise exception 'FAIL 18: the deleted account''s files were not queued';
  end if;

  -- ─── 19. Grants ─────────────────────────────────────────────────────────────────────────
  select count(*) into v_n
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'svc\_%' or p.proname like 'me\_%' or p.proname like 'st\_%' or p.proname like 'ow\_%'
          or p.proname in ('plan_catalog', 'sa_demo_requests', 'sa_update_demo_request'))
     and p.proname not in ('svc_clear_owner_login_tokens', 'svc_revoke_user_sessions', 'svc_set_owner_login_email',
                           'svc_set_student_login_email', 'st_hostel_contacts', 'st_my_roommates',
                           'ow_delete_announcement', 'ow_set_floor_plan', 'ow_set_rent_due_day', 'ow_update_hostel_rules')
     and has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 0 then
    raise exception 'FAIL 19: anon can execute % of the new functions', v_n;
  end if;

  raise notice 'ALL SELF SIGN-UP TESTS PASSED';
end
$test$;

select 'ALL SELF SIGN-UP TESTS PASSED' as result;

rollback;
