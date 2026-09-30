-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- TESTS FOR 2026-09-30-multi-pg-staff-access.sql
--
-- Run it as ONE batch, after the migration, in the SQL editor or with
--   psql "$DATABASE_URL" -f db/migrations/2026-09-30-multi-pg-staff-access.test.sql
-- as postgres. Everything happens inside BEGIN ... ROLLBACK, so it changes nothing: the owners,
-- PGs, staff, residents, grants, notifications, audit rows and rate-limit counters it creates are
-- all thrown away. The notifications it causes go to its own accounts, which have no push
-- devices, so no push is queued; pg_net's queue is transactional anyway and would be rolled back
-- with the rest.
--
-- It builds its own world (two owners, five PGs, nine staff, two residents) with fresh ids, so it
-- does not depend on, or touch, any real account. The only real data it reads is the invariant
-- in sections 1 and 2: every existing warden and manager has an access row for the PG they are
-- in, and every existing account still resolves to the same PG through app.user_hostel_id().
--
-- A failed expectation raises 'FAIL <section>: ...' and aborts the batch. Success ends with
-- NOTICE 'ALL MULTI-PG TESTS PASSED' and a one-row result saying the same, for tools that do not
-- show notices.
--
-- Callers are impersonated the way PostgREST does it: request.jwt.claims carries sub, role
-- 'authenticated' and aal 'aal2', and the role is switched to authenticated wherever grants or
-- row-level security are part of what is being tested.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;

do $test$
declare
  v_tag     text := 'mpg-test-' || left(gen_random_uuid()::text, 8);
  v_owner   uuid := gen_random_uuid();   -- owns PGs A, B, C and D
  v_owner2  uuid := gen_random_uuid();   -- owns PG X
  v_pg_a    uuid := gen_random_uuid();
  v_pg_b    uuid := gen_random_uuid();
  v_pg_c    uuid := gen_random_uuid();   -- five other wardens already have access
  v_pg_d    uuid := gen_random_uuid();
  v_pg_x    uuid := gen_random_uuid();   -- another owner's PG
  v_warden  uuid := gen_random_uuid();   -- the warden who gets several PGs; home A
  v_w2      uuid := gen_random_uuid();   -- a second warden; home A
  v_idle    uuid := gen_random_uuid();   -- a deactivated warden; home A
  v_manager uuid := gen_random_uuid();   -- a manager; home A
  v_res_a   uuid := gen_random_uuid();   -- a resident of A
  v_res_b   uuid := gen_random_uuid();   -- a resident of B
  v_crowd   uuid[] := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
                            gen_random_uuid(), gen_random_uuid()];   -- five wardens; home C
  v_student uuid;                        -- public.students row of v_res_b
  v_n       int;
  v_m       int;
  v_k       int;
  v_id      uuid;
  v_ids     uuid[];
  v_text    text;
  v_state   text;
  v_msg     text;
  v_json    jsonb;
  r         record;
begin
  -- ─── 1. The backfill: every warden and manager has an access row for the PG they are in ───
  select count(*) into v_n
    from public.users u
   where u.role in ('manager', 'warden')
     and u.hostel_id is not null
     and not exists (select 1 from public.staff_hostel_access a
                      where a.user_id = u.id and a.hostel_id = u.hostel_id);
  if v_n <> 0 then
    raise exception 'FAIL 1: % existing warden or manager account(s) have no access row for the PG they are in', v_n;
  end if;

  -- ─── 2. Every existing account still resolves to its PG (single-PG staff, owners, residents) ─
  for r in
    select u.id, u.hostel_id from public.users u
     where u.status = 'active' and u.deleted_at is null
       and u.role in ('owner', 'manager', 'warden', 'student')
  loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', r.id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    if app.user_hostel_id() is distinct from r.hostel_id then
      raise exception 'FAIL 2: existing account % no longer resolves to users.hostel_id', r.id;
    end if;
  end loop;

  -- ─── Fixtures, as the service role ─────────────────────────────────────────────────────────
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  insert into auth.users (id)
  select unnest(array[v_owner, v_owner2, v_warden, v_w2, v_idle, v_manager, v_res_a, v_res_b] || v_crowd);

  insert into public.users (id, role, full_name, status) values
    (v_owner,  'owner', v_tag || ' owner',  'active'),
    (v_owner2, 'owner', v_tag || ' owner2', 'active');

  -- The common prefix makes "first by name" mean A, then B, then C, then D.
  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms) values
    (v_pg_a, v_tag || ' A', v_owner,  1, 1),
    (v_pg_b, v_tag || ' B', v_owner,  1, 1),
    (v_pg_c, v_tag || ' C', v_owner,  1, 1),
    (v_pg_d, v_tag || ' D', v_owner,  1, 1),
    (v_pg_x, v_tag || ' X', v_owner2, 1, 1);

  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount)
  select h.id, h.owner_user_id, current_date - 1, current_date + 365, 0
    from public.hostels h
   where h.id in (v_pg_a, v_pg_b, v_pg_c, v_pg_d, v_pg_x);

  -- created_at decides who a contact card names (the longest-serving holder), so v_warden is oldest.
  insert into public.users (id, role, full_name, phone, hostel_id, status, created_by, created_at) values
    (v_warden,  'warden',  v_tag || ' warden',  '+910000000001', v_pg_a, 'active',   v_owner, now() - interval '5 days'),
    (v_manager, 'manager', v_tag || ' manager', '+910000000002', v_pg_a, 'active',   v_owner, now() - interval '5 days'),
    (v_w2,      'warden',  v_tag || ' w2',      '+910000000003', v_pg_a, 'active',   v_owner, now() - interval '4 days'),
    (v_idle,    'warden',  v_tag || ' idle',    '+910000000004', v_pg_a, 'inactive', v_owner, now() - interval '4 days');

  insert into public.users (id, role, full_name, hostel_id, status, created_by, created_at)
  select t.c, 'warden', v_tag || ' crowd ' || t.i, v_pg_c, 'active', v_owner, now() - interval '2 days'
    from unnest(v_crowd) with ordinality as t(c, i);

  insert into public.users (id, role, full_name, hostel_id, status) values
    (v_res_a, 'student', v_tag || ' resident a', v_pg_a, 'active'),
    (v_res_b, 'student', v_tag || ' resident b', v_pg_b, 'active');

  insert into public.students (hostel_id, user_id, full_name, phone)
  values (v_pg_b, v_res_b, v_tag || ' resident b', v_tag || '-phone-b')
  returning id into v_student;

  -- ─── 3. A new warden or manager gets exactly their home PG; a resident gets nothing ─────────
  select count(*) into v_n
    from public.staff_hostel_access a
   where a.user_id = any (array[v_warden, v_manager, v_w2, v_idle] || v_crowd);
  if v_n <> 9 then
    raise exception 'FAIL 3: new staff accounts got % home-PG rows, expected 9', v_n;
  end if;
  if not exists (select 1 from public.staff_hostel_access a
                  where a.user_id = v_warden and a.hostel_id = v_pg_a and a.granted_by = v_owner) then
    raise exception 'FAIL 3: the warden''s home-PG row is missing or not credited to the owner';
  end if;
  if exists (select 1 from public.staff_hostel_access a where a.user_id in (v_res_a, v_res_b)) then
    raise exception 'FAIL 3: a resident was given an access row';
  end if;

  -- ─── 4. A single-PG warden and a single-PG manager behave exactly as before ─────────────────
  perform set_config('role', 'authenticated', true);
  foreach v_id in array array[v_w2, v_manager] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    if app.user_hostel_id() is distinct from v_pg_a then
      raise exception 'FAIL 4: single-PG account % resolves to % instead of their PG', v_id, app.user_hostel_id();
    end if;
    select count(*), count(*) filter (where s.hostel_id = v_pg_a and s.is_active)
      into v_n, v_m from public.my_staff_hostels() s;
    if v_n <> 1 or v_m <> 1 then
      raise exception 'FAIL 4: my_staff_hostels for single-PG account % returned % rows (% active on A)', v_id, v_n, v_m;
    end if;
  end loop;

  -- ─── 5. The owner gives the warden a second PG ──────────────────────────────────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  select count(*),
         count(*) filter (where s.hostel_id = v_pg_a and s.is_active),
         count(*) filter (where s.hostel_id = v_pg_b and not s.is_active)
    into v_n, v_m, v_k
    from public.owner_set_staff_hostels(v_warden, array[v_pg_b, v_pg_a, v_pg_b, null]) s;
  if v_n <> 2 or v_m <> 1 or v_k <> 1 then
    raise exception 'FAIL 5: owner_set_staff_hostels returned % rows, active A %, inactive B %', v_n, v_m, v_k;
  end if;

  -- ─── 6. my_staff_hostels lists both, by name, with the current one marked ──────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  select array_agg(s.hostel_id order by s.name), string_agg(s.is_active::text, ',' order by s.name)
    into v_ids, v_text from public.my_staff_hostels() s;
  if v_ids is distinct from array[v_pg_a, v_pg_b] or v_text <> 'true,false' then
    raise exception 'FAIL 6: my_staff_hostels gave % / %', v_ids, v_text;
  end if;

  -- ─── 7. Switching to a granted PG works, and every policy follows ───────────────────────────
  if public.staff_switch_hostel(v_pg_b) is distinct from v_pg_b then
    raise exception 'FAIL 7: staff_switch_hostel did not return the PG';
  end if;
  if app.user_hostel_id() is distinct from v_pg_b then
    raise exception 'FAIL 7: app.user_hostel_id() did not follow the switch';
  end if;
  select string_agg(s.is_active::text, ',' order by s.name) into v_text from public.my_staff_hostels() s;
  if v_text <> 'false,true' then
    raise exception 'FAIL 7: my_staff_hostels after the switch gave %', v_text;
  end if;
  -- Row-level security now shows B and only B: its hostels row, and its resident.
  select count(*) into v_n from public.hostels where id in (v_pg_a, v_pg_b);
  select count(*) into v_m from public.students where hostel_id in (v_pg_a, v_pg_b);
  if v_n <> 1 or not exists (select 1 from public.hostels where id = v_pg_b) or v_m <> 1 then
    raise exception 'FAIL 7: after switching to B the warden sees % hostels and % residents', v_n, v_m;
  end if;
  -- Switching to the PG you are in is a no-op.
  if public.staff_switch_hostel(v_pg_b) is distinct from v_pg_b then
    raise exception 'FAIL 7: switching to the current PG did not return it';
  end if;

  -- ─── 8. Switching to a PG without access is refused ─────────────────────────────────────────
  foreach v_id in array array[v_pg_c, v_pg_x] loop
    begin
      perform public.staff_switch_hostel(v_id);
      v_state := 'ok'; v_msg := null;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    end;
    if v_state <> 'P0001' or v_msg is distinct from 'You do not have access to that PG.' then
      raise exception 'FAIL 8: switching to a PG without access gave [%] %', v_state, v_msg;
    end if;
  end loop;
  if app.user_hostel_id() is distinct from v_pg_b then
    raise exception 'FAIL 8: a refused switch moved the warden';
  end if;

  -- ─── 9. A direct UPDATE of users.hostel_id is held to the same rule ─────────────────────────
  foreach v_id in array array[v_pg_c, v_pg_x] loop
    begin
      update public.users set hostel_id = v_id where id = v_warden;
      v_state := 'ok'; v_msg := null;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    end;
    if v_state <> '42501' or v_msg is distinct from 'You cannot move an account to another hostel.' then
      raise exception 'FAIL 9: a direct UPDATE to a PG without access gave [%] %', v_state, v_msg;
    end if;
  end loop;
  update public.users set hostel_id = v_pg_a where id = v_warden;
  get diagnostics v_n = row_count;
  if v_n <> 1 or app.user_hostel_id() is distinct from v_pg_a then
    raise exception 'FAIL 9: a direct UPDATE to a granted PG did not take effect (% rows)', v_n;
  end if;

  -- ─── 10. A resident, an owner and a deactivated warden cannot switch ────────────────────────
  foreach v_id in array array[v_res_a, v_owner, v_idle] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    begin
      perform public.staff_switch_hostel(v_pg_b);
      v_state := 'ok'; v_msg := null;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    end;
    if v_state <> 'P0001' or v_msg is distinct from 'Only wardens and managers can switch PG.' then
      raise exception 'FAIL 10: staff_switch_hostel as % gave [%] %', v_id, v_state, v_msg;
    end if;
    if exists (select 1 from public.my_staff_hostels()) then
      raise exception 'FAIL 10: my_staff_hostels returned rows for %', v_id;
    end if;
  end loop;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_res_a, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  begin
    update public.users set hostel_id = v_pg_b where id = v_res_a;
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> '42501' then
    raise exception 'FAIL 10: a resident moving their own users.hostel_id gave [%] %', v_state, v_msg;
  end if;

  -- ─── 11. owner_set_staff_hostels and the table refuse what they must ────────────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  for r in
    select * from (values
      (1, 'You can only give access to your own PGs.'),   -- another owner's PG
      (2, 'Choose at least one PG.'),                     -- an empty list
      (3, 'Choose at least one PG.'),                     -- NULL
      (4, 'That staff member is not yours.'),             -- a resident
      (5, 'That staff member is not yours.'),             -- another owner's account
      (6, 'You can only give access to your own PGs.'),   -- a warden trying it
      (7, 'That staff member is not yours.')              -- another owner trying it
    ) as c(k, expected)
  loop
    if r.k = 6 then
      perform set_config('request.jwt.claims',
        json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    elsif r.k = 7 then
      perform set_config('request.jwt.claims',
        json_build_object('sub', v_owner2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    end if;
    begin
      perform public.owner_set_staff_hostels(
        case r.k when 4 then v_res_a when 5 then v_owner2 else v_warden end,
        case r.k when 1 then array[v_pg_a, v_pg_x] when 2 then '{}'::uuid[] when 3 then null
                 when 7 then array[v_pg_x] else array[v_pg_a] end);
      v_state := 'ok'; v_msg := null;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    end;
    if v_state <> 'P0001' or v_msg is distinct from r.expected then
      raise exception 'FAIL 11.%: owner_set_staff_hostels gave [%] %, expected %', r.k, v_state, v_msg, r.expected;
    end if;
  end loop;

  -- Clients cannot write the table at all, TRUNCATE included. anon cannot even read it. The
  -- service role keeps what owner-create-staff needs to add the extra PGs of a new account.
  if has_table_privilege('authenticated', 'public.staff_hostel_access', 'INSERT')
     or has_table_privilege('authenticated', 'public.staff_hostel_access', 'UPDATE')
     or has_table_privilege('authenticated', 'public.staff_hostel_access', 'DELETE')
     or has_table_privilege('authenticated', 'public.staff_hostel_access', 'TRUNCATE')
     or has_table_privilege('anon', 'public.staff_hostel_access', 'SELECT')
     or has_table_privilege('anon', 'public.staff_hostel_access', 'INSERT')
     or has_table_privilege('anon', 'public.staff_hostel_access', 'UPDATE')
     or has_table_privilege('anon', 'public.staff_hostel_access', 'DELETE')
     or has_table_privilege('anon', 'public.staff_hostel_access', 'TRUNCATE')
     or not has_table_privilege('authenticated', 'public.staff_hostel_access', 'SELECT')
     or not has_table_privilege('service_role', 'public.staff_hostel_access', 'SELECT')
     or not has_table_privilege('service_role', 'public.staff_hostel_access', 'INSERT')
     or not has_table_privilege('service_role', 'public.staff_hostel_access', 'DELETE') then
    raise exception 'FAIL 11: the table grants on staff_hostel_access are wrong';
  end if;
  -- Signed-in callers can run the five RPCs; anon cannot. Supabase grants anon EXECUTE on every
  -- new public function, so this is the revoke-by-name in section 10 of the migration.
  for r in
    select * from (values
      ('public.my_staff_hostels()'),
      ('public.staff_switch_hostel(uuid)'),
      ('public.owner_set_staff_hostels(uuid, uuid[])'),
      ('public.owner_hostel_staff(uuid)'),
      ('public.hostel_staff_names(uuid)')
    ) as f(sig)
  loop
    if has_function_privilege('anon', r.sig, 'EXECUTE')
       or not has_function_privilege('authenticated', r.sig, 'EXECUTE') then
      raise exception 'FAIL 11: EXECUTE on % is wrong (anon %, authenticated %)', r.sig,
        has_function_privilege('anon', r.sig, 'EXECUTE'),
        has_function_privilege('authenticated', r.sig, 'EXECUTE');
    end if;
  end loop;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  begin
    insert into public.staff_hostel_access (user_id, hostel_id) values (v_manager, v_pg_b);
    v_state := 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  if v_state <> '42501' then
    raise exception 'FAIL 11: an owner inserted an access row directly ([%])', v_state;
  end if;

  -- The guard holds the service role to the same rules.
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  for r in
    select * from (values
      (1, 'You can only give access to your own PGs.'),                   -- another owner's PG
      (2, 'Only wardens and managers can be given access to a PG.')       -- a resident
    ) as c(k, expected)
  loop
    begin
      insert into public.staff_hostel_access (user_id, hostel_id)
      values (case r.k when 2 then v_res_a else v_warden end,
              case r.k when 2 then v_pg_a else v_pg_x end);
      v_state := 'ok'; v_msg := null;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    end;
    if v_state <> 'P0001' or v_msg is distinct from r.expected then
      raise exception 'FAIL 11.g%: a service-role insert gave [%] %', r.k, v_state, v_msg;
    end if;
  end loop;

  -- ─── 12. Removing the PG somebody is working in moves them; never a revoked PG ──────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.owner_set_staff_hostels(v_warden, array[v_pg_a, v_pg_b, v_pg_d]);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform public.staff_switch_hostel(v_pg_d);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  -- Given as [B, A]: the move is to the first remaining PG BY NAME, which is A.
  select array_agg(s.hostel_id order by s.hostel_id), max(s.hostel_id::text) filter (where s.is_active)
    into v_ids, v_text
    from public.owner_set_staff_hostels(v_warden, array[v_pg_b, v_pg_a]) s;
  if v_text is distinct from v_pg_a::text or cardinality(v_ids) <> 2 or v_pg_d = any (v_ids) then
    raise exception 'FAIL 12: after removing D the result was % with % active', v_ids, v_text;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if app.user_hostel_id() is distinct from v_pg_a then
    raise exception 'FAIL 12: after removing D the warden resolves to %', app.user_hostel_id();
  end if;
  -- Even if a service-role path deletes the grant and leaves users.hostel_id behind, the account
  -- resolves to no PG rather than the revoked one.
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  delete from public.staff_hostel_access where user_id = v_warden and hostel_id = v_pg_a;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if app.user_hostel_id() is not null then
    raise exception 'FAIL 12: with its grant deleted, the warden still resolves to %', app.user_hostel_id();
  end if;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into public.staff_hostel_access (user_id, hostel_id, granted_by) values (v_warden, v_pg_a, v_owner);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if app.user_hostel_id() is distinct from v_pg_a then
    raise exception 'FAIL 12: restoring the grant did not restore the PG';
  end if;

  -- ─── 13. The 5-per-PG limit counts grants; a switch is never counted ────────────────────────
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  -- (i) C already has five active wardens with access. A sixth grant is refused, and the
  --     warden's list is left exactly as it was.
  begin
    perform public.owner_set_staff_hostels(v_warden, array[v_pg_a, v_pg_b, v_pg_c]);
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> 'P0001' or v_msg is distinct from 'This PG already has 5 active wardens. Remove one from it first.' then
    raise exception 'FAIL 13.i: a sixth warden grant to C gave [%] %', v_state, v_msg;
  end if;
  perform set_config('role', 'none', true);
  select array_agg(a.hostel_id order by a.hostel_id) into v_ids
    from public.staff_hostel_access a where a.user_id = v_warden;
  if v_ids is distinct from (select array_agg(x order by x) from unnest(array[v_pg_a, v_pg_b]) x) then
    raise exception 'FAIL 13.i: a refused change still altered the warden''s PGs: %', v_ids;
  end if;

  -- (ii) Five other wardens WORKING in B (users.hostel_id = B, moved there by the service role,
  --      with no access to B, so they do not count). The old presence count would refuse the
  --      warden's switch into B; the switch path counts nothing and lets it through.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.users set hostel_id = v_pg_b where id = any (v_crowd);
  select count(*) into v_n from public.users
   where hostel_id = v_pg_b and role = 'warden' and status = 'active' and id <> v_warden;
  if v_n < 5 then
    raise exception 'FAIL 13.ii: setup put only % other wardens in B', v_n;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  -- Two statements, not one expression: app.user_hostel_id() is STABLE, so inside the same
  -- statement as the switch it would read the snapshot taken before the switch wrote.
  if public.staff_switch_hostel(v_pg_b) is distinct from v_pg_b then
    raise exception 'FAIL 13.ii: the switch into B, where five others are working, was refused';
  end if;
  if app.user_hostel_id() is distinct from v_pg_b then
    raise exception 'FAIL 13.ii: after the switch into B the warden resolves to %', app.user_hostel_id();
  end if;
  perform public.staff_switch_hostel(v_pg_a);
  -- Those five are in B without access to it, so they resolve to no PG at all.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_crowd[1], 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if app.user_hostel_id() is not null then
    raise exception 'FAIL 13.ii: a warden without access to the PG they are in resolves to %', app.user_hostel_id();
  end if;

  -- (iii) Presence in B does not use up B's grants: a second warden can still be given B.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  select count(*) into v_n from public.owner_set_staff_hostels(v_w2, array[v_pg_a, v_pg_b]);
  if v_n <> 2 then
    raise exception 'FAIL 13.iii: granting B to a second warden returned % rows', v_n;
  end if;

  -- (iv) A reactivation is counted against EVERY PG on the account's list.
  select count(*) into v_n from public.owner_set_staff_hostels(v_idle, array[v_pg_a, v_pg_c]);
  if v_n <> 2 then
    raise exception 'FAIL 13.iv: giving an inactive warden C returned % rows (an inactive grant is not counted)', v_n;
  end if;
  begin
    update public.users set status = 'active' where id = v_idle;
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> 'P0001' or v_msg is distinct from 'This PG already has 5 active wardens. Remove one from it first.' then
    raise exception 'FAIL 13.iv: reactivating a warden with access to a full PG gave [%] %', v_state, v_msg;
  end if;
  -- Taking A (the PG they are in) and C away from the inactive warden moves them to B, through
  -- the owner arm of users_update_guard, and then the reactivation fits.
  select max(s.hostel_id::text) filter (where s.is_active), count(*) into v_text, v_n
    from public.owner_set_staff_hostels(v_idle, array[v_pg_b]) s;
  if v_text is distinct from v_pg_b::text or v_n <> 1 then
    raise exception 'FAIL 13.iv: the inactive warden was not moved to B (% active, % rows)', v_text, v_n;
  end if;
  update public.users set status = 'active' where id = v_idle;
  get diagnostics v_n = row_count;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_idle, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if v_n <> 1 or app.user_hostel_id() is distinct from v_pg_b then
    raise exception 'FAIL 13.iv: the reactivated warden resolves to %', app.user_hostel_id();
  end if;

  -- ─── 14. owner_hostel_staff lists the multi-PG warden under both PGs ────────────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  foreach v_id in array array[v_pg_a, v_pg_b] loop
    select count(*) into v_n
      from public.owner_hostel_staff(v_id) s
     where s.user_id = v_warden
       and s.active_hostel_id = v_pg_a
       and s.active_hostel_name = v_tag || ' A'
       and s.hostel_ids = array[v_pg_a, v_pg_b];
    if v_n <> 1 then
      raise exception 'FAIL 14: owner_hostel_staff(%) does not list the warden with both PGs', v_id;
    end if;
  end loop;
  -- A lists its manager first (ordered by role), and nobody without access to A.
  select array_agg(s.user_id order by s.ord) into v_ids
    from (select o.user_id, row_number() over () as ord from public.owner_hostel_staff(v_pg_a) o) s;
  if v_ids[1] is distinct from v_manager or v_crowd[1] = any (v_ids) or not (v_w2 = any (v_ids)) then
    raise exception 'FAIL 14: owner_hostel_staff(A) listed % ', v_ids;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  begin
    perform public.owner_hostel_staff(v_pg_a);
    v_state := 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  if v_state <> '42501' then
    raise exception 'FAIL 14: another owner read owner_hostel_staff(A) ([%])', v_state;
  end if;

  -- ─── 15. The contact card names the warden for a resident of either PG ──────────────────────
  -- The warden is working in A throughout.
  foreach v_id in array array[v_res_a, v_res_b] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select c.warden_name into v_text from public.st_hostel_contacts() c;
    if v_text is distinct from v_tag || ' warden' then
      raise exception 'FAIL 15: the contact card for resident % names warden %', v_id, v_text;
    end if;
  end loop;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_res_a, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  select c.manager_name into v_text from public.st_hostel_contacts() c;
  if v_text is distinct from v_tag || ' manager' then
    raise exception 'FAIL 15: the contact card for A names manager %', v_text;
  end if;

  -- ─── 16. B's notices reach the warden while they work in A ──────────────────────────────────
  -- Inserted as postgres (no row-level security) under the caller each trigger expects, so the
  -- rate-limit buckets are these fresh accounts' and nobody real is charged.
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_res_b, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  insert into public.leaves (hostel_id, student_id, from_date, to_date)
  values (v_pg_b, v_student, current_date + 1, current_date + 2);
  insert into public.complaints (hostel_id, student_id, title)
  values (v_pg_b, v_student, v_tag || ' complaint');
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  insert into public.announcements (hostel_id, author_user_id, title, body, audience)
  values (v_pg_b, v_owner, v_tag || ' notice', 'For the wardens of B.', 'warden');
  for r in select * from (values ('leave'), ('complaint'), ('announcement')) as t(kind) loop
    if not exists (select 1 from public.notifications n
                    where n.user_id = v_warden and n.hostel_id = v_pg_b and n.type::text = r.kind) then
      raise exception 'FAIL 16: the warden working in A got no % notice from B', r.kind;
    end if;
  end loop;
  if exists (select 1 from public.notifications n where n.user_id = any (v_crowd) and n.hostel_id = v_pg_b) then
    raise exception 'FAIL 16: wardens with no access to B were sent B''s notices';
  end if;
  -- A resident's deletion request goes to every warden with access to their PG.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_res_b, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  v_json := public.request_account_deletion('Testing', null);
  perform set_config('role', 'none', true);
  if not exists (select 1 from public.notifications n
                  where n.user_id = v_warden and n.hostel_id = v_pg_b
                    and n.title = 'Account deletion requested') then
    raise exception 'FAIL 16: the deletion request did not reach the warden working in A (%)', v_json;
  end if;
  -- A task in B can go to a manager with access to B, wherever they are working; one in C cannot.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.owner_set_staff_hostels(v_manager, array[v_pg_a, v_pg_b]);
  perform set_config('role', 'none', true);
  insert into public.tasks (hostel_id, assigned_to, title, created_by)
  values (v_pg_b, v_manager, v_tag || ' task in B', v_owner);
  begin
    insert into public.tasks (hostel_id, assigned_to, title, created_by)
    values (v_pg_c, v_manager, v_tag || ' task in C', v_owner);
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> '42501' or v_msg is distinct from 'Tasks can only be assigned to this hostel''s active manager.' then
    raise exception 'FAIL 16: a task in C for a manager without access to C gave [%] %', v_state, v_msg;
  end if;

  -- ─── 17. hostel_staff_names names B's staff, for readers of B only ──────────────────────────
  perform set_config('role', 'authenticated', true);
  select count(*),
         count(*) filter (where s.user_id in (v_owner, v_warden, v_w2, v_idle, v_manager)),
         count(*) filter (where s.user_id = any (v_crowd))
    into v_n, v_m, v_k
    from public.hostel_staff_names(v_pg_b) s;
  if v_m <> 5 or v_k <> 0 or v_n <> 5 then
    raise exception 'FAIL 17: hostel_staff_names(B) gave % rows, % expected, % without access', v_n, v_m, v_k;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_res_a, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if exists (select 1 from public.hostel_staff_names(v_pg_b)) then
    raise exception 'FAIL 17: a resident of A read the staff names of B';
  end if;

  -- ─── 18. Who can read staff_hostel_access ───────────────────────────────────────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  select count(*), count(*) filter (where user_id <> v_warden) into v_n, v_m from public.staff_hostel_access;
  if v_n <> 2 or v_m <> 0 then
    raise exception 'FAIL 18: the warden sees % access rows, % of them not their own', v_n, v_m;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  select count(*) into v_n from public.staff_hostel_access where user_id = v_warden;
  if v_n <> 2 then
    raise exception 'FAIL 18: the owner sees % of the warden''s access rows, expected 2', v_n;
  end if;
  foreach v_id in array array[v_owner2, v_res_a] loop
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_id, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    select count(*) into v_n from public.staff_hostel_access
     where hostel_id in (v_pg_a, v_pg_b, v_pg_c, v_pg_d);
    if v_n <> 0 then
      raise exception 'FAIL 18: % sees % access rows of PGs that are not theirs', v_id, v_n;
    end if;
  end loop;

  -- ─── 19. An owner can re-point their own staff to a granted PG, and only that ───────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  update public.users set hostel_id = v_pg_b where id = v_warden;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FAIL 19: the owner could not move the warden to a PG the warden has';
  end if;
  begin
    update public.users set hostel_id = v_pg_c where id = v_warden;
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> '42501' or v_msg is distinct from 'You cannot move an account to another hostel.' then
    raise exception 'FAIL 19: the owner moving the warden to a PG they lack gave [%] %', v_state, v_msg;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner2, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  update public.users set hostel_id = v_pg_x where id = v_warden;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FAIL 19: another owner moved the warden';
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  if app.user_hostel_id() is distinct from v_pg_b then
    raise exception 'FAIL 19: after the owner''s move the warden resolves to %', app.user_hostel_id();
  end if;

  -- ─── 20. With no JWT at all the move rule fails closed ──────────────────────────────────────
  -- auth.uid() is NULL, so the "moving itself" arm is NULL rather than false. Without the
  -- coalesce in users_update_guard the hostel rule would wave the move through and only the
  -- guard's last line would refuse it ('Not allowed.'). Expecting the hostel sentence checks
  -- the rule itself.
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '', true);
  begin
    update public.users set hostel_id = v_pg_a where id = v_warden;
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> '42501' or v_msg is distinct from 'You cannot move an account to another hostel.' then
    raise exception 'FAIL 20: a move with no JWT gave [%] %', v_state, v_msg;
  end if;

  -- ─── 21. A read-only or suspended PG takes nobody new, but can still lose people ────────────
  -- The warden has A and B and is working in B (section 19). D is not on their list.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.hostels set status = 'suspended' where id in (v_pg_b, v_pg_d);
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.owner_set_staff_hostels(v_warden, array[v_pg_a, v_pg_b, v_pg_d]);
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> 'P0001' or v_msg is distinct from 'You cannot give access to a PG that is read-only or suspended.' then
    raise exception 'FAIL 21: giving access to a suspended PG gave [%] %', v_state, v_msg;
  end if;
  -- The service role (owner-create-staff adding a new account's other PGs) is held to it too.
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  begin
    insert into public.staff_hostel_access (user_id, hostel_id, granted_by) values (v_warden, v_pg_d, v_owner);
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> 'P0001' or v_msg is distinct from 'You cannot give access to a PG that is read-only or suspended.' then
    raise exception 'FAIL 21: a service-role grant of a suspended PG gave [%] %', v_state, v_msg;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  -- Taking the suspended B away still works, and moves the warden to A.
  select max(s.hostel_id::text) filter (where s.is_active), count(*) into v_text, v_n
    from public.owner_set_staff_hostels(v_warden, array[v_pg_a]) s;
  if v_text is distinct from v_pg_a::text or v_n <> 1 then
    raise exception 'FAIL 21: taking the suspended PG away gave % active, % rows', v_text, v_n;
  end if;

  raise notice 'ALL MULTI-PG TESTS PASSED';
end
$test$;

select 'ALL MULTI-PG TESTS PASSED' as result;

rollback;
