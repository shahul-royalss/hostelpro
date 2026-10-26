-- TESTS FOR 2026-10-26-round3.sql. One batch, as postgres, inside BEGIN ... ROLLBACK (changes nothing).
-- Before applying: run the migration (without its BEGIN/COMMIT) and this file (without its BEGIN)
-- as one batch ending in ROLLBACK. Builds its own world with fresh ids (@example.com addresses,
-- md5-derived phones). Callers are impersonated through request.jwt.claims, as PostgREST does.
-- A failure raises 'FAIL <section>: ...'; success ends with 'ALL ROUND 3 TESTS PASSED'.

begin;

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
create function pg_temp.claims(p_user uuid, p_aal text default 'aal2')
returns void language plpgsql as $$
begin
  if p_user is null then
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text, true);
  end if;
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
  v_tag   text := 'r3-' || left(gen_random_uuid()::text, 8);
  v_sa    uuid := gen_random_uuid();
  v_own   uuid := gen_random_uuid();   -- admin owner: PG A (listed), PG B (unlisted)
  v_own2  uuid := gen_random_uuid();   -- admin owner: PG C
  v_wdn   uuid := gen_random_uuid();   -- warden in A
  v_wdn_c uuid := gen_random_uuid();   -- warden in C
  v_res   uuid := gen_random_uuid();   -- admin-created resident in A, with a login
  v_res2  uuid := gen_random_uuid();   -- second resident in A, with a login
  v_se_t  uuid := gen_random_uuid();   -- self_email tenant, no PG
  v_ap    uuid := gen_random_uuid();   -- self_email staff applicant
  v_apg   uuid := gen_random_uuid();   -- self_google staff applicant
  v_se_own uuid := gen_random_uuid();  -- self_email owner
  v_x     uuid := gen_random_uuid();   -- auth user with no profile
  v_pg_a  uuid := gen_random_uuid();
  v_pg_b  uuid := gen_random_uuid();
  v_pg_c  uuid := gen_random_uuid();
  v_floor uuid := gen_random_uuid();
  v_room  uuid := gen_random_uuid();
  v_b1 uuid := gen_random_uuid(); v_b2 uuid := gen_random_uuid(); v_b3 uuid := gen_random_uuid(); v_b4 uuid := gen_random_uuid();
  v_res_st uuid := gen_random_uuid(); v_mid_st uuid := gen_random_uuid(); v_res2_st uuid := gen_random_uuid();
  v_m0 text := to_char(app.today(), 'YYYY-MM');
  v_m1 text := to_char(app.today() - interval '1 month', 'YYYY-MM');
  v_m2 text := to_char(app.today() - interval '2 months', 'YYYY-MM');
  v_logo text; v_c1 text; v_c2 text;
  v_req uuid; v_req2 uuid; v_claim uuid; v_claim2 uuid;
  v_j jsonb; v_n int; v_s text;
  p1 text; p2 text; p3 text; p4 text; p5 text; p6 text; p7 text;
begin
  p1 := '9' || substr(regexp_replace(md5(v_tag || '1'), '\D', '', 'g') || '123456789', 1, 9);
  p2 := '8' || substr(regexp_replace(md5(v_tag || '2'), '\D', '', 'g') || '123456789', 1, 9);
  p3 := '7' || substr(regexp_replace(md5(v_tag || '3'), '\D', '', 'g') || '123456789', 1, 9);
  p4 := '6' || substr(regexp_replace(md5(v_tag || '4'), '\D', '', 'g') || '123456789', 1, 9);
  p5 := '9' || substr(regexp_replace(md5(v_tag || '5'), '\D', '', 'g') || '123456789', 1, 9);
  p6 := '8' || substr(regexp_replace(md5(v_tag || '6'), '\D', '', 'g') || '123456789', 1, 9);
  p7 := '7' || substr(regexp_replace(md5(v_tag || '7'), '\D', '', 'g') || '123456789', 1, 9);

  -- ─── Fixtures ───────────────────────────────────────────────────────────────────────────
  perform pg_temp.claims(null);
  insert into auth.users (id, email) values
    (v_sa, v_tag || '-sa@example.com'), (v_own, v_tag || '-own@example.com'), (v_own2, v_tag || '-own2@example.com'),
    (v_wdn, v_tag || '-wdn@example.com'), (v_wdn_c, v_tag || '-wdnc@example.com'),
    (v_res, p1 || '@student.hostelpro.local'), (v_res2, p6 || '@student.hostelpro.local'),
    (v_se_t, v_tag || '-set@example.com'), (v_ap, v_tag || '-ap@example.com'), (v_apg, v_tag || '-apg@example.com'),
    (v_se_own, v_tag || '-seown@example.com'), (v_x, v_tag || '-x@example.com');
  insert into public.users (id, role, full_name, email, status, must_change_password) values
    (v_sa, 'super_admin', v_tag || ' SA', v_tag || '-sa@example.com', 'active', false),
    (v_own, 'owner', v_tag || ' Owner', v_tag || '-own@example.com', 'active', false),
    (v_own2, 'owner', v_tag || ' Owner2', v_tag || '-own2@example.com', 'active', false);
  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms, city, locality, pincode, address,
                              latitude, longitude, listed, status) values
    (v_pg_a, v_tag || ' Alpha PG', v_own, 1, 1, 'City ' || v_tag, 'Sector 1', '560001', '1 Secret Road',
     12.971600, 77.594600, true, 'active'),
    (v_pg_b, v_tag || ' Hidden PG', v_own, 1, 1, 'City ' || v_tag, 'Sector 2', '560001', '2 Secret Road',
     12.972000, 77.595000, false, 'active'),
    (v_pg_c, v_tag || ' Gamma PG', v_own2, 1, 1, 'City ' || v_tag, 'Sector 3', '560001', '3 Secret Road',
     12.973000, 77.596000, true, 'active');
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount) values
    (v_pg_a, v_own, current_date - 200, current_date + 100, 0),
    (v_pg_b, v_own, current_date - 200, current_date + 100, 0),
    (v_pg_c, v_own2, current_date - 200, current_date + 100, 0);
  insert into public.users (id, role, full_name, email, phone, hostel_id, status, created_by) values
    (v_wdn, 'warden', v_tag || ' Warden', v_tag || '-wdn@example.com', null, v_pg_a, 'active', v_own),
    (v_wdn_c, 'warden', v_tag || ' WardenC', v_tag || '-wdnc@example.com', null, v_pg_c, 'active', v_own2),
    (v_res, 'student', v_tag || ' Resident', null, p1, v_pg_a, 'active', v_wdn),
    (v_res2, 'student', v_tag || ' Resident Two', null, p6, v_pg_a, 'active', v_wdn);
  insert into public.floors (id, hostel_id, floor_number) values (v_floor, v_pg_a, 1);
  insert into public.rooms (id, hostel_id, floor_id, room_number, capacity) values (v_room, v_pg_a, v_floor, '101', 4);
  -- The room's beds are created with it.
  select id into v_b1 from public.beds where room_id = v_room and bed_number = 1;
  select id into v_b2 from public.beds where room_id = v_room and bed_number = 2;
  select id into v_b3 from public.beds where room_id = v_room and bed_number = 3;
  select id into v_b4 from public.beds where room_id = v_room and bed_number = 4;
  insert into public.students (id, hostel_id, user_id, full_name, phone, date_of_joining, room_id, bed_id, monthly_fee, created_by)
  values (v_res_st, v_pg_a, v_res, v_tag || ' Resident', p1, app.today() - 75, v_room, v_b1, 5000, v_wdn),
         (v_mid_st, v_pg_a, null, v_tag || ' Mid Joiner', p7,
          (date_trunc('month', app.today() - interval '1 month') + interval '14 days')::date, v_room, v_b2, 4000, v_wdn),
         (v_res2_st, v_pg_a, v_res2, v_tag || ' Resident Two', p6, app.today() - 40, v_room, v_b4, 4500, v_wdn);

  -- ─── 1. R1 sign-up sources and staff applicants ─────────────────────────────────────────
  v_j := public.svc_create_self_signup_profile(v_se_t, 'student', 'Sita  Tenant', p2, null, 'self_email', 'Pune', '411001');
  perform pg_temp.ok((select signup_source = 'self_email' and email_verified_at is null and city = 'Pune' and pincode = '411001'
                        and not staff_applicant from public.users where id = v_se_t), '1 self_email tenant');
  perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, null, null, %L)',
                                v_x, 'owner', 'Some Name', 'self_email'),
                         '22023', 'Enter a valid 10-digit mobile number.', '1 phone required');
  perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, %L, null, %L, null, %L)',
                                v_x, 'owner', 'Some Name', p5, 'self_email', '012345'),
                         '22023', 'Enter a valid 6-digit pincode.', '1 pincode');
  perform pg_temp.expect(format('select public.svc_create_self_signup_profile(%L, %L, %L, %L, null, %L)',
                                v_x, 'warden', 'Some Name', p5, 'self_email'),
                         '22023', 'Only owner and tenant accounts can be created by sign-up.', '1 warden persona');
  perform public.svc_create_self_signup_profile(v_ap, 'staff', 'Arun Applicant', p3, null, 'self_email');
  perform public.svc_create_self_signup_profile(v_apg, 'staff', 'Gauri Applicant', null, null, 'self_google');
  perform public.svc_create_self_signup_profile(v_se_own, 'owner', 'Selma Owner', p4, null, 'self_email', 'Pune', '411002');
  perform pg_temp.ok((select role = 'student' and staff_applicant and hostel_id is null from public.users where id = v_ap),
                     '1 applicant shape');
  perform pg_temp.expect(format($q$insert into public.users (id, role, full_name, status, hostel_id, staff_applicant)
                                  values (%L, 'student', 'X Person', 'active', %L, true)$q$, v_x, v_pg_a),
                         '22023', 'Only a sign-up account can apply as staff.', '1 admin applicant');
  perform pg_temp.expect(format('update public.users set role = %L, hostel_id = %L, staff_applicant = false where id = %L',
                                'warden', v_pg_a, v_ap),
                         '22023', 'Only owner and tenant accounts can be created by sign-up.', '1 convert by hand');
  perform pg_temp.claims(v_ap);
  perform pg_temp.expect(format('update public.users set staff_applicant = false where id = %L', v_ap),
                         '42501', 'The staff application cannot be changed by hand.', '1 flag by hand');
  perform pg_temp.expect(format('insert into public.hostel_join_requests (hostel_id, user_id) values (%L, %L)', v_pg_a, v_ap),
                         '42501', 'Staff accounts ask to join a PG as staff.', '1 applicant as tenant');

  -- ─── 2. R2 dues start at check-in; fee months; timeline ─────────────────────────────────
  perform pg_temp.claims(v_wdn);
  perform pg_temp.ok((select count(*) from public.rpc_fee_ledger(v_pg_a, v_m2) l where l.student_id = v_mid_st) = 0,
                     '2 mid joiner not in the month before check-in');
  perform pg_temp.ok((select count(*) from public.rpc_fee_ledger(v_pg_a, v_m1) l where l.student_id = v_mid_st) = 1,
                     '2 mid joiner in the check-in month');
  perform pg_temp.ok((select count(*) from public.rpc_fee_ledger(v_pg_a, v_m2) l where l.student_id = v_res_st) = 1,
                     '2 earlier resident still listed');
  perform pg_temp.ok((select students_unpaid from public.rpc_hostel_stats(v_pg_a, v_m2))
                     = (select count(*) from public.students s where s.hostel_id = v_pg_a and s.status <> 'vacated'
                         and s.date_of_joining < to_date(v_m2 || '-01', 'YYYY-MM-DD') + interval '1 month'),
                     '2 stats count only checked-in residents');
  perform pg_temp.ok((select count(*) = 2 and min(period_month) = v_m1 from public.rpc_student_fee_months(v_mid_st)),
                     '2 fee months of a mid-period joiner');
  perform public.wd_record_payment(v_res_st, v_m0, 2000, 'cash', null, null);
  update public.students set bed_id = v_b3 where id = v_res_st;
  perform pg_temp.claims(v_res);
  perform pg_temp.ok((select min(period_month) from public.rpc_student_fee_months())
                     = to_char(app.today() - 75, 'YYYY-MM'), '2 own fee months start at check-in');
  select string_agg(distinct kind, ',' order by kind) into v_s from public.st_timeline();
  perform pg_temp.ok(v_s like '%checked_in%' and v_s like '%due%' and v_s like '%payment%' and v_s like '%room%',
                     '2 timeline kinds: ' || coalesce(v_s, 'none'));
  perform pg_temp.ok((select count(*) from public.st_timeline() t
                       where t.kind = 'due' and t.at < (app.today() - 75)::timestamp at time zone 'Asia/Kolkata') = 0,
                     '2 no due before check-in');
  perform pg_temp.claims(v_se_t);
  perform pg_temp.expect(format('select * from public.rpc_student_fee_months(%L)', v_res_st), 'P0001', 'Resident not found.', '2 other tenant');
  perform pg_temp.expect(format('select * from public.st_timeline(%L)', v_res_st), 'P0001', 'Resident not found.', '2 other timeline');

  -- ─── 3. R3 an owner with no factor is not forced to enrol ───────────────────────────────
  perform pg_temp.claims(v_own, 'aal1');
  perform pg_temp.ok(app.owns_hostel(v_pg_a), '3 owner without a factor works at aal1');

  -- ─── 4. R5 PG profile, media, reviews, discovery ────────────────────────────────────────
  v_logo := v_pg_a || '/logo/' || gen_random_uuid() || '.jpg';
  v_c1 := v_pg_a || '/cover/' || gen_random_uuid() || '.jpg';
  v_c2 := v_pg_a || '/cover/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name, owner_id) values
    ('pg-media', v_logo, v_own::text), ('pg-media', v_c1, v_own::text), ('pg-media', v_c2, v_own::text);
  perform pg_temp.claims(v_own);
  perform pg_temp.ok(app.can_upload_pg_media(v_pg_a || '/cover/' || gen_random_uuid() || '.jpg'), '4 owner may upload');
  perform pg_temp.ok(not app.can_upload_pg_media(v_pg_a || '/other/' || gen_random_uuid() || '.jpg'), '4 bad folder');
  v_j := public.ow_update_pg_profile(v_pg_a, v_tag || ' Alpha PG', 'Clean rooms', array['wifi', 'food', 'wifi'],
                                     v_logo, array[v_c1, v_c2]);
  perform pg_temp.ok(v_j -> 'amenities' = '["food", "wifi"]'::jsonb and v_j ->> 'logo_path' = v_logo, '4 profile saved');
  perform pg_temp.expect(format('select public.ow_update_pg_profile(%L, %L, null, array[%L], null, null)', v_pg_a, 'Alpha', 'pool'),
                         'P0001', 'Unknown amenity.', '4 amenity');
  perform pg_temp.expect(format('select public.ow_update_pg_profile(%L, %L, null, null, %L, null)', v_pg_a, 'Alpha',
                                v_pg_a || '/logo/' || gen_random_uuid() || '.jpg'),
                         'P0001', 'Upload the logo again.', '4 logo not uploaded');
  perform pg_temp.expect(format('select public.ow_update_pg_profile(%L, %L, null, null, null, array[%L])', v_pg_a, 'Alpha',
                                replace(v_c1, v_pg_a::text, v_pg_c::text)),
                         'P0001', 'Upload the cover photos again.', '4 cover of another PG');
  v_j := public.ow_update_pg_profile(v_pg_a, v_tag || ' Alpha PG', 'Clean rooms', array['wifi', 'food'], v_logo, array[v_c1]);
  perform pg_temp.ok(exists (select 1 from app.storage_erasures e where e.bucket = 'pg-media' and e.object_path = v_c2),
                     '4 removed cover queued for erasure');
  perform pg_temp.claims(v_own2);
  perform pg_temp.ok(not app.can_upload_pg_media(v_pg_a || '/cover/' || gen_random_uuid() || '.jpg'), '4 other owner upload');
  perform pg_temp.expect(format('select public.ow_update_pg_profile(%L, %L, null, null, null, null)', v_pg_a, 'Mine'),
                         '42501', 'You can only edit your own PG.', '4 other owner edit');
  perform pg_temp.claims(v_wdn);
  perform pg_temp.ok(not app.can_upload_pg_media(v_pg_a || '/cover/' || gen_random_uuid() || '.jpg'), '4 warden upload');
  perform pg_temp.claims(v_se_t);
  perform pg_temp.ok(app.can_view_pg(v_pg_a) and not app.can_view_pg(v_pg_b), '4 media visibility for a prospect');
  perform pg_temp.claims(v_own);
  perform pg_temp.ok(app.can_view_pg(v_pg_b), '4 owner sees own unlisted PG');

  perform pg_temp.claims(v_res);
  perform public.st_save_review(4, 'Good food');
  v_j := public.st_save_review(5, 'Great food');
  perform pg_temp.ok((select count(*) = 1 and max(rating) = 5 from public.pg_reviews where hostel_id = v_pg_a), '4 one review, edited');
  perform pg_temp.expect('select public.st_save_review(6)', 'P0001', 'Choose 1 to 5 stars.', '4 rating range');
  perform pg_temp.claims(v_se_t);
  perform pg_temp.expect('select public.st_save_review(3)', '42501', 'Only a current tenant can rate their PG.', '4 prospect review');
  perform pg_temp.claims(v_own);
  perform pg_temp.expect('select public.st_save_review(1)', '42501', 'Only a current tenant can rate their PG.', '4 owner review');
  perform pg_temp.ok((select count(*) from public.pg_review_list(v_pg_a)) = 1, '4 owner reads reviews');
  perform pg_temp.claims(v_se_t);
  select count(*) into v_n from public.st_search_hostels(v_tag) s
   where s.hostel_id = v_pg_a and s.rating_avg = 5.0 and s.rating_count = 1 and s.logo_path = v_logo and 'wifi' = any (s.amenities);
  perform pg_temp.ok(v_n = 1, '4 search carries logo, rating, amenities');
  perform pg_temp.ok(not exists (select 1 from public.st_search_hostels(v_tag) s where s.hostel_id = v_pg_b), '4 unlisted hidden');
  perform pg_temp.ok((select count(*) from public.st_nearby_hostels(12.9716, 77.5946) s
                       where s.hostel_id = v_pg_a and s.rating_count = 1) = 1, '4 nearby carries rating');
  v_j := public.st_pg_profile(v_pg_a);
  perform pg_temp.ok(not (v_j ? 'address') and not (v_j ? 'pincode') and not (v_j ? 'latitude') and not (v_j ? 'owner_user_id')
                     and jsonb_array_length(v_j -> 'reviews') = 1 and (v_j ->> 'rating_count')::int = 1
                     and v_j ->> 'description' = 'Clean rooms', '4 PG profile shape');
  perform pg_temp.expect(format('select public.st_pg_profile(%L)', v_pg_b), 'P0001', 'This PG is not available.', '4 unlisted profile');

  -- ─── 5. R6 check-out requests ───────────────────────────────────────────────────────────
  perform pg_temp.claims(v_res);
  perform pg_temp.expect(format('select public.st_request_checkout(%L)', app.today() + 120),
                         'P0001', 'Choose a date from today up to 90 days ahead.', '5 date range');
  v_req := (public.st_request_checkout(app.today() + 10, 'Moving out') ->> 'request_id')::uuid;
  perform pg_temp.expect(format('select public.st_request_checkout(%L)', app.today() + 12),
                         'P0001', 'You already have a check-out request.', '5 one open request');
  perform pg_temp.ok((select count(*) from public.notifications n
                       where n.user_id in (v_wdn, v_own) and n.title = 'Check-out request' and n.hostel_id = v_pg_a) = 2,
                     '5 warden and owner notified');
  perform pg_temp.claims(v_wdn_c);
  perform pg_temp.expect(format('select public.wd_decide_checkout_request(%L, true)', v_req),
                         'P0001', 'This request is no longer available.', '5 other PG warden');
  perform pg_temp.claims(v_wdn);
  perform pg_temp.ok((select count(*) from public.wd_checkout_requests(v_pg_a, 'pending')) = 1, '5 warden list');
  v_j := public.wd_decide_checkout_request(v_req, true, app.today() + 5, null);
  perform pg_temp.ok(v_j ->> 'status' = 'accepted'
                     and (select status from public.students where id = v_res_st) = 'active', '5 accepted for a later date');
  perform pg_temp.expect(format('select public.wd_decide_checkout_request(%L, false)', v_req),
                         'P0001', 'This request was already handled.', '5 decide twice');
  perform pg_temp.claims(v_own);
  perform pg_temp.ok((public.ow_checkout_summary() ->> 'scheduled')::int >= 1
                     and jsonb_array_length(public.ow_checkout_summary(v_pg_a) -> 'items') = 1, '5 owner summary');
  update public.checkout_requests set checkout_date = app.today() where id = v_req;
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.ok(app.run_due_checkouts() >= 1, '5 nightly run');
  perform pg_temp.ok((select status from public.students where id = v_res_st) = 'vacated'
                     and (select status from public.checkout_requests where id = v_req) = 'completed'
                     and (select status from public.users where id = v_res) = 'inactive', '5 vacate flow ran on the date');
  perform pg_temp.claims(v_res2);
  v_req2 := (public.st_request_checkout(app.today() + 3) ->> 'request_id')::uuid;
  perform pg_temp.claims(v_wdn);
  perform public.wd_decide_checkout_request(v_req2, false, null, 'Notice period is 30 days');
  perform pg_temp.ok((select status from public.checkout_requests where id = v_req2) = 'declined'
                     and exists (select 1 from public.notifications n where n.user_id = v_res2
                                  and n.title = 'Check-out request declined' and n.body like '%30 days%'), '5 declined with note');
  perform pg_temp.claims(v_res2);
  perform pg_temp.expect('select public.st_cancel_checkout_request()', 'P0001', 'There is no pending check-out request.', '5 cancel none');

  -- ─── 6. R8 staff requests, conversion, social sign-in for self-sourced staff ────────────
  perform pg_temp.claims(v_ap);
  perform pg_temp.expect(format('select public.stf_request_join(%L)', v_pg_b), 'P0001', 'This PG is not available.', '6 unlisted');
  v_req := (public.stf_request_join(v_pg_a, 'I have run a mess') ->> 'request_id')::uuid;
  perform pg_temp.expect(format('select public.stf_request_join(%L)', v_pg_c),
                         'P0001', 'You already have a pending request. Cancel it to ask another PG.', '6 one pending');
  perform pg_temp.claims(v_se_t);
  perform pg_temp.expect(format('select public.stf_request_join(%L)', v_pg_a),
                         '42501', 'Only a staff sign-up account can ask to join a PG as staff.', '6 tenant as staff');
  perform pg_temp.claims(v_own2);
  perform pg_temp.expect(format('select public.ow_decide_staff_request(%L, true, %L)', v_req, 'warden'),
                         'P0001', 'This request is no longer available.', '6 other owner');
  perform pg_temp.claims(v_wdn);
  perform pg_temp.expect(format('select public.ow_decide_staff_request(%L, true, %L)', v_req, 'warden'),
                         '42501', 'Not allowed.', '6 warden decides');
  perform pg_temp.claims(v_own);
  perform pg_temp.ok(public.ow_pending_staff_request_count() = 1 and (select count(*) from public.ow_staff_requests(v_pg_a)) = 1,
                     '6 owner sees the request');
  perform pg_temp.expect(format('select public.ow_decide_staff_request(%L, true, %L)', v_req, 'super_admin'),
                         '22023', 'Choose Manager or Warden.', '6 role allowlist');
  perform public.ow_decide_staff_request(v_req, true, 'warden', null);
  perform pg_temp.ok((select role = 'warden' and hostel_id = v_pg_a and not staff_applicant from public.users where id = v_ap)
                     and exists (select 1 from public.staff_hostel_access a where a.user_id = v_ap and a.hostel_id = v_pg_a),
                     '6 converted and assigned');
  perform pg_temp.claims(v_ap);
  perform pg_temp.ok(app.user_hostel_id() = v_pg_a and app.has_role_in(v_pg_a, 'warden'), '6 the new warden has access');
  perform pg_temp.claims(v_own);
  perform pg_temp.expect(format('update public.users set role = %L, hostel_id = %L, staff_applicant = false where id = %L',
                                'manager', v_pg_a, v_apg),
                         '22023', 'Only owner and tenant accounts can be created by sign-up.', '6 owner converts by hand');
  perform pg_temp.claims(v_apg);
  v_req := (public.stf_request_join(v_pg_a) ->> 'request_id')::uuid;
  perform pg_temp.claims(v_own);
  perform public.ow_decide_staff_request(v_req, true, 'manager', null);

  perform pg_temp.claims(null);
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_tag || '-g-apg', v_apg, jsonb_build_object('sub', v_tag || '-g-apg', 'email', v_tag || '-apg@example.com'),
          'google', now(), now(), now());
  perform pg_temp.expect(format($q$insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
                                  values (%L, %L, '{}'::jsonb, 'google', now(), now())$q$, v_tag || '-g-wdn', v_wdn),
                         '42501', 'Staff and administrator accounts sign in with the login they were given.', '6 admin warden google');
  perform pg_temp.expect(format($q$insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
                                  values (%L, %L, '{}'::jsonb, 'google', now(), now())$q$, v_tag || '-g-sa', v_sa),
                         '42501', 'Staff and administrator accounts sign in with the login they were given.', '6 super admin google');
  perform pg_temp.expect(format($q$insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
                                  values (%L, %L, '{}'::jsonb, 'google', now(), now())$q$, v_tag || '-g-ap', v_ap),
                         '42501', 'Staff and administrator accounts sign in with the login they were given.', '6 unverified self_email warden');
  update public.users set email_verified_at = now() where id = v_ap;
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_tag || '-g-ap', v_ap, '{}'::jsonb, 'google', now(), now(), now());
  insert into public.external_identities (provider, subject, user_id) values ('facebook', v_tag || '-fb-apg', v_apg);
  perform pg_temp.expect(format($q$insert into public.external_identities (provider, subject, user_id) values ('truecaller', %L, %L)$q$,
                                v_tag || '-tc-wdn', v_wdn),
                         '42501', 'Staff and administrator accounts sign in with the login they were given.', '6 admin warden link');
  perform pg_temp.ok(public.svc_external_signin_allowed(v_apg) and not public.svc_external_signin_allowed(v_wdn)
                     and public.svc_external_signin_allowed(gen_random_uuid()), '6 svc_external_signin_allowed');
  perform pg_temp.ok(public.svc_secure_unverified_account(v_se_t, true), '6 secure unverified');
  perform pg_temp.ok((select encrypted_password is null from auth.users where id = v_se_t)
                     and (select email_verified_at is not null from public.users where id = v_se_t)
                     and not public.svc_secure_unverified_account(v_se_t, true)
                     and not public.svc_secure_unverified_account(v_apg, true), '6 unverified account secured once');
  perform pg_temp.claims(v_own);
  perform pg_temp.expect(format('select public.svc_external_signin_allowed(%L)', v_apg), '42501', 'Not allowed.', '6 svc only');

  -- ─── 7. R9 UPI settings and payment claims ──────────────────────────────────────────────
  perform pg_temp.expect(format('select public.ow_set_upi_settings(%L, %L, %L)', v_pg_a, 'not a vpa', 'Alpha'),
                         'P0001', 'Enter a valid UPI ID, like name@okhdfcbank.', '7 vpa format');
  perform public.ow_set_upi_settings(v_pg_a, ' Alpha.PG@OKHDFCBANK ', 'Alpha PG');
  perform pg_temp.claims(v_wdn);
  perform pg_temp.expect(format('select public.ow_set_upi_settings(%L, %L, %L)', v_pg_a, 'x@ybl', 'X'),
                         '42501', 'You can only change your own PG.', '7 warden writes');
  perform pg_temp.claims(v_res2);
  perform pg_temp.ok(public.hostel_upi_settings() ->> 'upi_vpa' = 'alpha.pg@okhdfcbank', '7 tenant reads');
  perform pg_temp.claims(v_se_t);
  perform pg_temp.expect('select public.hostel_upi_settings()', '42501', 'Not allowed.', '7 outsider reads');
  perform pg_temp.claims(v_res2);
  v_claim := (public.st_submit_payment_claim(4500, v_m0, '1234 5678 9012') ->> 'claim_id')::uuid;
  perform pg_temp.expect(format('select public.st_submit_payment_claim(4500, %L, %L)', v_m0, '123456789012'),
                         '23505', 'This UTR has already been submitted.', '7 utr unique');
  perform pg_temp.expect(format('select public.st_submit_payment_claim(4500, %L, %L)', v_m0, 'abc'),
                         'P0001', 'Enter the UTR / transaction ID from your UPI app (usually 12 digits).', '7 utr shape');
  perform pg_temp.expect(format('select public.st_submit_payment_claim(4500, %L, %L)',
                                to_char(app.today() - interval '2 years', 'YYYY-MM'), '999988887777'),
                         'P0001', 'Choose a month from your check-in month up to next month.', '7 month before check-in');
  v_claim2 := (public.st_submit_payment_claim(100, v_m0, '555566667777') ->> 'claim_id')::uuid;
  perform pg_temp.claims(v_wdn);
  perform pg_temp.ok((select count(*) from public.wd_payment_claims(v_pg_a)) = 2, '7 warden list');
  perform pg_temp.expect(format('select public.wd_decide_payment_claim(%L, false)', v_claim2),
                         'P0001', 'Add a note saying why it was not found.', '7 reject needs a note');
  v_j := public.wd_decide_payment_claim(v_claim, true);
  perform pg_temp.ok(v_j ->> 'status' = 'confirmed'
                     and (select amount_paid = 4500 and mode = 'upi' and id = (v_j ->> 'fee_payment_id')::uuid
                            from public.fee_payments where student_id = v_res2_st and period_month = v_m0), '7 confirm records the payment');
  perform public.wd_decide_payment_claim(v_claim2, false, 'Not in the bank statement');
  perform pg_temp.ok(exists (select 1 from public.notifications n where n.user_id = v_res2 and n.title = 'Payment not confirmed'),
                     '7 tenant told of the rejection');
  perform pg_temp.claims(v_res2);
  perform pg_temp.expect(format('select public.st_cancel_payment_claim(%L)', v_claim),
                         'P0001', 'This payment can no longer be cancelled.', '7 cancel confirmed');

  -- ─── 8. R7 Super Admin lists, deletion log, permanent delete ────────────────────────────
  perform pg_temp.claims(null);
  update public.users set email_verified_at = now() where id = v_se_own;
  perform pg_temp.claims(v_se_own);
  perform public.ow_create_first_hostel(v_tag || ' Selma PG', 'pg', 'boys', '9 Test Lane, Testpur', 'Sector 9',
                                        'City ' || v_tag, '560001', 1, 1, 1);
  perform pg_temp.claims(v_sa);
  perform pg_temp.ok((select count(*) from public.sa_signups(null, null, 'trial') s
                       where s.user_id = v_se_own and s.trial_start is not null and s.trial_end > s.trial_start
                         and s.hostel_name = v_tag || ' Selma PG') = 1, '8 sign-ups list with trial dates');
  perform pg_temp.ok(not exists (select 1 from public.sa_signups(null, null, 'no_pg') s where s.user_id = v_se_own), '8 status filter');
  perform pg_temp.claims(v_own);
  perform pg_temp.expect('select * from public.sa_signups()', '42501', 'Not allowed.', '8 owner reads sign-ups');

  perform pg_temp.claims(null);
  perform public.svc_delete_staff_account(v_own2, v_wdn_c);
  perform pg_temp.claims(v_res2);
  perform public.request_account_deletion('Leaving the city', null);
  perform pg_temp.claims(v_sa);
  perform pg_temp.ok((select count(*) from public.sa_deleted_accounts() d
                       where (d.user_id = v_wdn_c and d.kind = 'owner_deleted_staff' and d.by_user_id = v_own2
                              and d.full_name = v_tag || ' WardenC')
                          or (d.user_id = v_res2 and d.kind = 'self_request')) = 2, '8 deletion log');
  perform pg_temp.expect(format('select public.sa_purge_account(%L, %L)', v_res2, 'Asked to be removed'),
                         'P0001', 'This tenant is still checked in. Check them out of their PG first.', '8 purge checked-in');
  perform pg_temp.expect(format('select public.sa_purge_account(%L, %L)', v_sa, 'Asked to be removed'),
                         '42501', 'A Super Admin account cannot be deleted here.', '8 purge super admin');
  perform pg_temp.expect(format('select public.sa_purge_account(%L, %L)', v_res, 'no'),
                         'P0001', 'Give a reason between 5 and 300 characters.', '8 purge reason');
  v_j := public.sa_purge_account(v_res, 'Asked to be removed');
  perform pg_temp.ok((select full_name = 'Deleted user' and phone is null and deleted_at is not null from public.users where id = v_res)
                     and (select email like 'deleted-%' and encrypted_password is null from auth.users where id = v_res)
                     and (select full_name = 'Erased resident' and erased_at is not null from public.students where id = v_res_st)
                     and exists (select 1 from public.fee_payments where student_id = v_res_st and amount_paid = 2000)
                     and not exists (select 1 from public.pg_reviews where user_id = v_res)
                     and not exists (select 1 from public.account_deletions where user_id = v_res and full_name <> 'Deleted user')
                     and exists (select 1 from public.account_deletions where user_id = v_res and kind = 'sa_deleted'
                                  and purged_at is not null and by_user_id = v_sa)
                     and not exists (select 1 from public.audit_log where actor_user_id = v_res), '8 purge erases, keeps money');
  perform pg_temp.expect(format('select public.sa_purge_account(%L, %L)', v_res, 'Asked again please'),
                         'P0001', 'This account was already permanently deleted.', '8 purge twice');
  perform pg_temp.claims(v_own);
  perform pg_temp.expect(format('select public.sa_purge_account(%L, %L)', v_res2, 'Asked to be removed'),
                         '42501', 'Not allowed.', '8 owner purges');

  -- ─── 9. Grants and row-level security ───────────────────────────────────────────────────
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('st_timeline', 'sa_purge_account', 'wd_decide_payment_claim', 'ow_decide_staff_request',
                       'st_pg_profile', 'rpc_student_fee_months', 'svc_secure_unverified_account')
     and has_function_privilege('anon', p.oid, 'execute');
  perform pg_temp.ok(v_n = 0, '9 anon executes none');
  perform pg_temp.ok(not has_function_privilege('authenticated', 'public.svc_secure_unverified_account(uuid,boolean)', 'execute'),
                     '9 svc not for clients');
  perform pg_temp.claims(v_res2);
  perform set_config('role', 'authenticated', true);
  perform pg_temp.expect(format($q$insert into public.payment_claims (hostel_id, student_id, period_month, amount, utr, upi_vpa)
                                  values (%L, %L, %L, 1, 'AAAAAAAAAAAA', 'x@ybl')$q$, v_pg_a, v_res2_st, v_m0),
                         '42501', null, '9 client insert');
  perform pg_temp.ok((select count(*) from public.payment_claims) = 2, '9 tenant reads own claims only');
  perform pg_temp.ok((select count(*) from public.account_deletions) = 0, '9 deletion log is Super Admin only');
  perform set_config('role', 'none', true);

  raise notice 'ALL ROUND 3 TESTS PASSED';
end
$test$;

select 'ALL ROUND 3 TESTS PASSED' as result;

rollback;
