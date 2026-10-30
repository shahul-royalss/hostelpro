-- TESTS FOR 2026-10-31-round4.sql. One batch, as postgres, inside BEGIN ... ROLLBACK (changes nothing).
-- Before applying: run the migration (without its BEGIN/COMMIT) and this file (without its BEGIN)
-- as one batch ending in ROLLBACK. Builds its own world with fresh ids (@example.com addresses,
-- md5-derived phones). Callers are impersonated through request.jwt.claims, as PostgREST does.
-- A failure raises 'FAIL <section>: ...'; success ends with 'ALL ROUND 4 TESTS PASSED'.

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
  v_tag   text := 'r4-' || left(gen_random_uuid()::text, 8);
  v_own   uuid := gen_random_uuid();   v_own2  uuid := gen_random_uuid();
  v_wdn   uuid := gen_random_uuid();   v_wdn_c uuid := gen_random_uuid();
  v_res   uuid := gen_random_uuid();   v_res2  uuid := gen_random_uuid();
  v_t1    uuid := gen_random_uuid();   v_t2    uuid := gen_random_uuid();
  v_pg_a  uuid := gen_random_uuid();   v_pg_c  uuid := gen_random_uuid();
  v_res_st uuid := gen_random_uuid();  v_mid_st uuid := gen_random_uuid();  v_res2_st uuid := gen_random_uuid();
  v_t1_st uuid; v_t2_st uuid; v_req1 uuid; v_req2 uuid;
  v_join  date := app.today() - 75;
  v_jm    text := to_char(app.today() - 75, 'YYYY-MM');
  v_m0    text := to_char(app.today(), 'YYYY-MM');
  v_m1    text := to_char(app.today() - interval '1 month', 'YYYY-MM');
  v_due0  date := make_date(extract(year from app.today())::int, extract(month from app.today())::int, 5);
  v_j jsonb; v_n int;
  p1 text; p2 text; p3 text; p4 text; p5 text; p6 text; p7 text; p8 text;
begin
  p1 := '9' || substr(regexp_replace(md5(v_tag || '1'), '\D', '', 'g') || '123456789', 1, 9);
  p2 := '8' || substr(regexp_replace(md5(v_tag || '2'), '\D', '', 'g') || '123456789', 1, 9);
  p3 := '7' || substr(regexp_replace(md5(v_tag || '3'), '\D', '', 'g') || '123456789', 1, 9);
  p4 := '6' || substr(regexp_replace(md5(v_tag || '4'), '\D', '', 'g') || '123456789', 1, 9);
  p5 := '9' || substr(regexp_replace(md5(v_tag || '5'), '\D', '', 'g') || '123456789', 1, 9);
  p6 := '8' || substr(regexp_replace(md5(v_tag || '6'), '\D', '', 'g') || '123456789', 1, 9);
  p7 := '7' || substr(regexp_replace(md5(v_tag || '7'), '\D', '', 'g') || '123456789', 1, 9);
  p8 := '6' || substr(regexp_replace(md5(v_tag || '8'), '\D', '', 'g') || '123456789', 1, 9);

  -- ─── Fixtures ───────────────────────────────────────────────────────────────────────────
  perform pg_temp.claims(null);
  insert into auth.users (id, email) values
    (v_own, v_tag || '-own@example.com'), (v_own2, v_tag || '-own2@example.com'),
    (v_wdn, v_tag || '-wdn@example.com'), (v_wdn_c, v_tag || '-wdnc@example.com'),
    (v_res, p1 || '@student.hostelpro.local'), (v_res2, p6 || '@student.hostelpro.local'),
    (v_t1, v_tag || '-t1@example.com'), (v_t2, v_tag || '-t2@example.com');
  insert into public.users (id, role, full_name, email, status, must_change_password) values
    (v_own, 'owner', v_tag || ' Owner', v_tag || '-own@example.com', 'active', false),
    (v_own2, 'owner', v_tag || ' Owner2', v_tag || '-own2@example.com', 'active', false);
  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms, city, locality, pincode, address, status) values
    (v_pg_a, v_tag || ' Alpha PG', v_own, 1, 1, 'Pune', 'Sector 1', '411001', '1 Test Road', 'active'),
    (v_pg_c, v_tag || ' Gamma PG', v_own2, 1, 1, 'Pune', 'Sector 3', '411001', '3 Test Road', 'active');
  update public.hostels set rent_due_day = 5 where id in (v_pg_a, v_pg_c);
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount) values
    (v_pg_a, v_own, current_date - 200, current_date + 100, 0),
    (v_pg_c, v_own2, current_date - 200, current_date + 100, 0);
  insert into public.users (id, role, full_name, email, phone, hostel_id, status, created_by) values
    (v_wdn, 'warden', v_tag || ' Warden', v_tag || '-wdn@example.com', null, v_pg_a, 'active', v_own),
    (v_wdn_c, 'warden', v_tag || ' WardenC', v_tag || '-wdnc@example.com', null, v_pg_c, 'active', v_own2),
    (v_res, 'student', v_tag || ' Resident', null, p1, v_pg_a, 'active', v_wdn),
    (v_res2, 'student', v_tag || ' Resident Two', null, p6, v_pg_a, 'active', v_wdn);
  insert into public.students (id, hostel_id, user_id, full_name, phone, date_of_joining, monthly_fee, created_by) values
    (v_res_st, v_pg_a, v_res, v_tag || ' Resident', p1, v_join, 5000, v_wdn),
    (v_mid_st, v_pg_a, null, v_tag || ' No Account', p7, app.today() - 10, 4000, v_wdn),
    (v_res2_st, v_pg_a, v_res2, v_tag || ' Resident Two', p6, app.today() - 40, 4500, v_wdn);
  perform public.svc_create_self_signup_profile(v_t1, 'student', 'Tara Tenant', p2, null, 'self_email', 'Pune', '411001');
  perform public.svc_create_self_signup_profile(v_t2, 'student', 'Tanu Tenant', p3, null, 'self_email');
  insert into public.hostel_join_requests (hostel_id, user_id) values (v_pg_a, v_t1) returning id into v_req1;
  insert into public.hostel_join_requests (hostel_id, user_id) values (v_pg_a, v_t2) returning id into v_req2;

  -- ─── 1. Accept with rent, atomically; old 3-argument call still works ───────────────────
  perform pg_temp.claims(v_wdn);
  perform pg_temp.expect(format('select public.ow_decide_join_request(%L, true, null, 0)', v_req1),
                         'P0001', 'Enter the monthly rent (₹1 to ₹10,00,000).', '1 rent zero');
  perform pg_temp.expect(format('select public.ow_decide_join_request(%L, true, null, 1000001)', v_req1),
                         'P0001', 'Enter the monthly rent (₹1 to ₹10,00,000).', '1 rent too high');
  perform pg_temp.expect(format('select public.ow_decide_join_request(%L, true, null, 6000, 29)', v_req1),
                         'P0001', 'Choose a due day from 1 to 28.', '1 due day');
  perform pg_temp.ok((select status = 'pending' from public.hostel_join_requests where id = v_req1), '1 refused accept left it pending');
  v_j := public.ow_decide_join_request(v_req1, true, null, 6000, 10);
  v_t1_st := (v_j ->> 'student_id')::uuid;
  perform pg_temp.ok((select monthly_fee = 6000 and rent_due_day = 10 and user_id = v_t1 from public.students where id = v_t1_st),
                     '1 rent + due day saved with the accept');
  v_j := public.ow_decide_join_request(v_req2, true);
  v_t2_st := (v_j ->> 'student_id')::uuid;
  perform pg_temp.ok((select monthly_fee = 0 and rent_due_day is null from public.students where id = v_t2_st), '1 old call: rent unset');

  -- ─── 2. Residents needing rent ──────────────────────────────────────────────────────────
  perform pg_temp.ok((select count(*) from public.wd_residents_needing_rent() r where r.student_id = v_t2_st and r.has_account) = 1
                     and (select count(*) from public.wd_residents_needing_rent(v_pg_a) r where r.student_id in (v_t1_st, v_res_st)) = 0,
                     '2 warden list');
  perform pg_temp.claims(v_own);
  perform pg_temp.ok((select count(*) from public.wd_residents_needing_rent() r where r.student_id = v_t2_st) = 1, '2 owner list');
  perform pg_temp.claims(v_wdn_c);
  perform pg_temp.ok((select count(*) from public.wd_residents_needing_rent() r where r.hostel_id = v_pg_a) = 0, '2 other PG sees none');
  perform pg_temp.expect(format('select * from public.wd_residents_needing_rent(%L)', v_pg_a), '42501', 'Not allowed.', '2 other PG by id');
  perform pg_temp.claims(v_res);
  perform pg_temp.expect('select * from public.wd_residents_needing_rent()', '42501', 'Not allowed.', '2 tenant');

  -- ─── 3. No dues while rent is unset ─────────────────────────────────────────────────────
  perform pg_temp.claims(v_wdn);
  perform pg_temp.ok((select count(*) from public.rpc_fee_ledger(v_pg_a, v_m0) l where l.student_id = v_t2_st) = 0
                     and (select count(*) from public.rpc_fee_ledger(v_pg_a, v_m0) l where l.student_id = v_t1_st) = 1,
                     '3 ledger skips rent-unset resident');
  perform pg_temp.ok((select count(*) from public.rpc_student_fee_months(v_t2_st)) = 0, '3 no fee months');
  perform pg_temp.ok((select count(*) from public.st_timeline(v_t2_st) t where t.kind = 'due') = 0, '3 no timeline dues');
  perform pg_temp.expect(format('select public.wd_record_payment(%L, %L, 100, ''cash'')', v_t2_st, v_m0),
                         'P0001', 'Set this resident''s monthly rent before recording a payment.', '3 desk payment refused');

  -- ─── 4. Set / change rent ───────────────────────────────────────────────────────────────
  perform pg_temp.expect(format('select public.wd_set_tenant_rent(%L, 0)', v_t2_st),
                         'P0001', 'Enter the monthly rent%', '4 zero');
  perform pg_temp.claims(v_wdn_c);
  perform pg_temp.expect(format('select public.wd_set_tenant_rent(%L, 4000)', v_t2_st), '42501', 'Not allowed.', '4 other PG');
  perform pg_temp.claims(v_t2);
  perform pg_temp.expect(format('select public.wd_set_tenant_rent(%L, 1)', v_t2_st), '42501', 'Not allowed.', '4 tenant');
  perform pg_temp.claims(v_wdn);
  v_j := public.wd_set_tenant_rent(v_t2_st, 4000, 7);
  perform pg_temp.ok(v_j ->> 'applies_from' = v_m0 and (v_j ->> 'rent_due_day')::int = 7, '4 first rent bills from check-in');
  perform pg_temp.ok((select count(*) = 1 and min(amount_due) = 4000 from public.rpc_student_fee_months(v_t2_st)), '4 dues start');
  perform public.wd_record_payment(v_t2_st, v_m0, 100, 'cash');

  -- Change: paid month untouched, billed months frozen at the old rent, new rent from the next unbilled month.
  perform public.wd_record_payment(v_res_st, v_m1, 5000, 'cash');
  v_j := public.wd_set_tenant_rent(v_res_st, 7000);
  perform pg_temp.ok(v_j ->> 'applies_from' = case when v_due0 >= app.today() then v_m0
                                                   else to_char(app.today() + interval '1 month', 'YYYY-MM') end,
                     '4 applies_from ' || coalesce(v_j ->> 'applies_from', 'null'));
  perform pg_temp.ok((select amount_due = 5000 and status = 'paid' from public.rpc_student_fee_months(v_res_st) where period_month = v_m1),
                     '4 paid month unchanged');
  perform pg_temp.ok((select amount_due = 5000 and status = 'unpaid' from public.rpc_student_fee_months(v_res_st) where period_month = v_jm),
                     '4 billed month frozen at old rent');
  perform pg_temp.ok((select amount_due = case when v_due0 < app.today() then 5000 else 7000 end
                        from public.rpc_student_fee_months(v_res_st) where period_month = v_m0), '4 current month');
  perform pg_temp.ok((select monthly_fee = 7000 from public.students where id = v_res_st), '4 new rent stored');
  perform pg_temp.ok(exists (select 1 from public.audit_log where action = 'student.rent.set' and target_id = v_res_st::text), '4 audit');

  -- ─── 5. R4.2 wd_update_tenant_profile ───────────────────────────────────────────────────
  v_j := public.wd_update_tenant_profile(v_t1_st, p_full_name => 'Tara  Updated', p_phone => p4,
           p_email => 'Tara.Shown@Example.com', p_gender => 'Female', p_date_of_birth => date '2000-01-02',
           p_emergency_contact_name => 'Meera Tenant', p_emergency_contact_phone => p5,
           p_address => '12 MG Road, Pune', p_city => 'Pune', p_pincode => '411002');
  perform pg_temp.ok((select full_name = 'Tara Updated' and phone = p4 and gender = 'female' and date_of_birth = date '2000-01-02'
                             and emergency_contact_name = 'Meera Tenant' and emergency_contact_phone = p5
                             and city = 'Pune' and pincode = '411002'
                             and email = v_tag || '-t1@example.com' and role = 'student' and hostel_id = v_pg_a
                        from public.users where id = v_t1), '5 account updated, login email/role/PG untouched');
  perform pg_temp.ok((select full_name = 'Tara Updated' and phone = p4 and email = 'tara.shown@example.com'
                             and guardian_name = 'Meera Tenant' and guardian_phone = p5 and permanent_address = '12 MG Road, Pune'
                        from public.students where id = v_t1_st), '5 roster updated');
  perform pg_temp.ok(jsonb_array_length(v_j -> 'changed') = 9 and not (v_j -> 'changed') ? 'city', '5 changed fields (city was already Pune) ' || (v_j -> 'changed')::text);
  perform pg_temp.ok(exists (select 1 from public.audit_log where action = 'student.profile.update' and target_id = v_t1_st::text),
                     '5 audit');
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_phone => %L)', v_t1_st, '12345'),
                         'P0001', 'Enter a valid 10-digit mobile number.', '5 phone');
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_pincode => %L)', v_t1_st, '012345'),
                         'P0001', 'Enter a valid 6-digit pincode.', '5 pincode');
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_emergency_contact_phone => %L)', v_t1_st, p4),
                         'P0001', 'The emergency contact needs a different number%', '5 same number');
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_email => %L)', v_t1_st, 'not-an-email'),
                         'P0001', 'Enter a valid email address.', '5 email');
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_phone => %L)', v_t1_st, p6),
                         'P0001', 'Another resident or account already uses this phone number.', '5 duplicate phone');
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_gender => %L)', v_mid_st, 'male'),
                         'P0001', 'This resident has no app account%', '5 no account: account field');
  perform public.wd_update_tenant_profile(v_mid_st, p_full_name => 'Kiran Roster', p_address => '');
  perform pg_temp.ok((select full_name = 'Kiran Roster' and permanent_address is null from public.students where id = v_mid_st),
                     '5 no account: roster fields');
  perform pg_temp.claims(v_own);
  perform public.wd_update_tenant_profile(v_t2_st, p_full_name => 'Tanu Owner Edit');
  perform pg_temp.ok((select full_name = 'Tanu Owner Edit' from public.users where id = v_t2), '5 owner edits');
  perform pg_temp.claims(v_wdn_c);
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_full_name => %L)', v_t1_st, 'Hacker'),
                         '42501', 'Not allowed.', '5 other PG');
  perform pg_temp.claims(v_t1);
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_full_name => %L)', v_t1_st, 'Self Edit'),
                         '42501', 'Not allowed.', '5 tenant');
  perform pg_temp.claims(v_wdn);
  perform pg_temp.expect(format('select public.wd_update_tenant_profile(%L, p_full_name => %L)', gen_random_uuid(), 'Nobody'),
                         'P0001', 'Resident not found.', '5 unknown');

  perform set_config('request.jwt.claims', '', true);
  raise notice 'ALL ROUND 4 TESTS PASSED';
end
$test$;

select 'ALL ROUND 4 TESTS PASSED' as result;

rollback;
