-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- TESTS FOR 2026-10-12-brand-free-server-messages.sql
--
-- Run it as ONE batch, after the migration, in the SQL editor or with
--   psql "$DATABASE_URL" -f db/migrations/2026-10-12-brand-free-server-messages.test.sql
-- as postgres. Everything happens inside BEGIN ... ROLLBACK, so it changes nothing: the super
-- admin, owner, warden, PG, plan, notifications, audit rows and rate-limit counters it creates
-- are all thrown away. The notifications it causes go to its own accounts, which have no push
-- devices, so no push is queued; pg_net's queue is transactional anyway and would be rolled back
-- with the rest.
--
-- What it checks:
--   1. No routine in the database says a product name (Nivora, Apnivaas, HostelPro) to a
--      person. Identifiers that must keep the old names are allowed and stripped before the
--      search: '[nivora]' log tags, the demo logins '@nivora.app', the support mailbox
--      '@nivora.dhrishtaerf.org', the push channel 'nivora_default', the secret
--      NIVORA_SERVICE_ROLE_KEY, the HMAC label 'nivora/password-reset-ticket/v1', cron job names
--      'nivora-…' and 'hostelpro-…', the app id 'com.nivorasr.app', the Firebase project
--      'nivorapg' and the residents' login domain '@student.hostelpro.local'.
--   2. The five redefined routines carry the new sentences (so a FAIL here on a database the
--      migration has not reached says so plainly, instead of passing on the old text).
--   3. Their grants and settings did not move: SECURITY DEFINER, search_path=public, execute
--      for authenticated and not for anon or PUBLIC; the users_update_guard trigger still
--      calls app.users_update_guard().
--   4-9. Each routine still compiles and behaves: it is run end to end and the exact sentence
--      it writes is compared, as is its refusal of the wrong caller.
--
-- It builds its own world (one super admin, one owner, one PG, one warden) with fresh ids, so
-- it does not depend on, or touch, any real account. The only real data it reads is pg_proc.
--
-- A failed expectation raises 'FAIL <section>: ...' and aborts the batch. Success ends with
-- NOTICE 'ALL BRAND-FREE MESSAGE TESTS PASSED' and a one-row result saying the same, for tools
-- that do not show notices.
--
-- Callers are impersonated the way PostgREST does it: request.jwt.claims carries sub, role
-- 'authenticated' and aal 'aal2', and the role is switched to authenticated around each RPC so
-- that the grant is part of what is tested. Notifications are read back as postgres, because a
-- notification addressed to the owner is not the super admin's to read.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;

do $test$
declare
  v_tag     text := 'brand-test-' || left(gen_random_uuid()::text, 8);
  v_sa      uuid := gen_random_uuid();   -- a super admin
  v_owner   uuid := gen_random_uuid();   -- owns the PG; every notification under test is theirs
  v_warden  uuid := gen_random_uuid();   -- works in the PG; asks for their account to be deleted
  v_pg      uuid := gen_random_uuid();
  v_pg_name text;                        -- the PG's name before the rename
  v_renamed text;                        -- and after it
  v_reason  text := 'Checking the wording';
  v_expect  text;
  v_text    text;
  v_state   text;
  v_msg     text;
  v_n       int;
  v_json    jsonb;
  r         record;
begin
  v_pg_name := v_tag || ' PG';
  v_renamed := v_tag || ' Renamed';

  -- ─── 1. No routine says a product name to a person ──────────────────────────────────────────
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog', 'information_schema')
     and regexp_replace(p.prosrc,
           '\[nivora\]|@nivora\.app|@nivora\.dhrishtaerf\.org|nivora_default|nivora_service_role_key|nivora/password-reset-ticket/v1|nivora-[a-z0-9-]+|com\.nivorasr\.app|nivorapg|@student\.hostelpro\.local|hostelpro-[a-z0-9-]+',
           '', 'gi') ~* '(nivora|apnivaas|hostelpro)';
  if v_text is not null then
    raise exception 'FAIL 1: these routines still name the product in text a person reads: %', v_text;
  end if;

  -- ─── 2. The five routines carry the new sentences ───────────────────────────────────────────
  for r in
    select * from (values
      ('public.sa_set_hostel_status(uuid,text)',     '%s has been suspended.'),
      ('public.sa_set_hostel_status(uuid,text)',     'until it is reactivated. Contact support.'''),
      ('public.sa_set_hostel_status(uuid,text)',     'until the plan is renewed. Contact support to renew.'''),
      ('public.sa_cancel_subscription(uuid,text)',   'The plan for %s has been cancelled.'),
      ('public.sa_rename_hostel(uuid,text)',         '%s has been renamed to %s.'),
      ('public.request_account_deletion(text,uuid)', ' asked for their account and personal data to be deleted.'''),
      ('app.users_update_guard()',                   'opening the confirmation link emailed to the address.''')
    ) as t(fn, phrase)
  loop
    select p.prosrc into v_text from pg_proc p where p.oid = r.fn::regprocedure;
    if strpos(v_text, r.phrase) = 0 then
      raise exception 'FAIL 2: % does not contain [%]. Has 2026-10-12-brand-free-server-messages.sql been applied?', r.fn, r.phrase;
    end if;
  end loop;

  -- ─── 3. Grants, settings and the trigger did not move ───────────────────────────────────────
  for r in
    select p.oid::regprocedure::text as fn, p.prosecdef, p.proconfig,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_x,
           has_function_privilege('anon', p.oid, 'EXECUTE') as anon_x,
           exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0) as public_x
      from pg_proc p
     where p.oid in ('public.sa_set_hostel_status(uuid,text)'::regprocedure,
                     'public.sa_cancel_subscription(uuid,text)'::regprocedure,
                     'public.sa_rename_hostel(uuid,text)'::regprocedure,
                     'public.request_account_deletion(text,uuid)'::regprocedure)
  loop
    if not r.prosecdef or r.proconfig is distinct from array['search_path=public']
       or not r.auth_x or r.anon_x or r.public_x then
      raise exception 'FAIL 3: % has secdef=% config=% authenticated=% anon=% public=%',
        r.fn, r.prosecdef, r.proconfig, r.auth_x, r.anon_x, r.public_x;
    end if;
  end loop;
  select count(*) into v_n
    from pg_proc p
   where p.oid = 'app.users_update_guard()'::regprocedure
     and p.prosecdef and p.proconfig = array['search_path=public'];
  if v_n <> 1 then
    raise exception 'FAIL 3: app.users_update_guard() lost SECURITY DEFINER or its search_path';
  end if;
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.users'::regclass
                    and t.tgname = 'users_update_guard'
                    and t.tgfoid = 'app.users_update_guard()'::regprocedure
                    and t.tgenabled <> 'D') then
    raise exception 'FAIL 3: the users_update_guard trigger no longer calls app.users_update_guard()';
  end if;

  -- ─── Fixtures, as the service role ─────────────────────────────────────────────────────────
  perform set_config('role', 'none', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  insert into auth.users (id) values (v_sa), (v_owner), (v_warden);
  insert into public.users (id, role, full_name, status) values
    (v_sa,    'super_admin', v_tag || ' super admin', 'active'),
    (v_owner, 'owner',       v_tag || ' owner',       'active');
  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms)
  values (v_pg, v_pg_name, v_owner, 1, 1);
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount)
  values (v_pg, v_owner, current_date - 1, current_date + 365, 0);
  insert into public.users (id, role, full_name, hostel_id, status, created_by)
  values (v_warden, 'warden', v_tag || ' warden', v_pg, 'active', v_owner);

  -- ─── 4. request_account_deletion: the warden's request reaches the owner, brand-free ────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_warden, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  v_json := public.request_account_deletion(v_reason, null);
  perform set_config('role', 'none', true);
  if (v_json ->> 'already_pending')::boolean is distinct from false
     or (v_json ->> 'notified')::int is distinct from 1 then
    raise exception 'FAIL 4: the warden''s deletion request returned %', v_json;
  end if;
  v_expect := v_tag || ' warden asked for their account and personal data to be deleted.'
           || ' Reason: "' || v_reason || '" Verify who they are in person before acting.';
  select count(*) into v_n
    from public.notifications n
   where n.user_id = v_owner and n.hostel_id = v_pg
     and n.title = 'Account deletion requested' and n.body = v_expect
     and n.link = '/owner/staff';
  if v_n <> 1 then
    raise exception 'FAIL 4: the owner has % deletion notices reading [%]', v_n, v_expect;
  end if;

  -- ─── 5. sa_rename_hostel: the owner is told, brand-free; nobody else may rename ─────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.sa_rename_hostel(v_pg, v_renamed);
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  perform set_config('role', 'none', true);
  if v_state <> '42501' or v_msg is distinct from 'Only the Super Admin can rename a hostel.' then
    raise exception 'FAIL 5: an owner renaming their own PG gave [%] %', v_state, v_msg;
  end if;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_sa, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  perform set_config('role', 'authenticated', true);
  v_text := public.sa_rename_hostel(v_pg, '  ' || v_renamed || '  ');
  perform set_config('role', 'none', true);
  if v_text is distinct from v_renamed then
    raise exception 'FAIL 5: sa_rename_hostel returned [%], expected [%]', v_text, v_renamed;
  end if;
  v_expect := format('%s has been renamed to %s. Your team will see the new name the next time they open the app.',
                     v_pg_name, v_renamed);
  select count(*) into v_n
    from public.notifications n
   where n.user_id = v_owner and n.hostel_id = v_pg and n.type = 'system'
     and n.title = 'Hostel renamed' and n.body = v_expect;
  if v_n <> 1 then
    raise exception 'FAIL 5: the owner has % rename notices reading [%]', v_n, v_expect;
  end if;

  -- ─── 6. sa_set_hostel_status: suspend, then reactivate while the plan runs ──────────────────
  perform set_config('role', 'authenticated', true);
  v_text := public.sa_set_hostel_status(v_pg, 'suspended');
  perform set_config('role', 'none', true);
  if v_text is distinct from 'suspended' then
    raise exception 'FAIL 6: suspending gave [%]', v_text;
  end if;
  v_expect := format('%s has been suspended. Your team can still open the app and read records, but nothing can be added or changed until it is reactivated. Contact support.',
                     v_renamed);
  select count(*) into v_n
    from public.notifications n
   where n.user_id = v_owner and n.type = 'subscription'
     and n.title = 'Hostel suspended' and n.body = v_expect;
  if v_n <> 1 then
    raise exception 'FAIL 6: the owner has % suspension notices reading [%]', v_n, v_expect;
  end if;

  perform set_config('role', 'authenticated', true);
  v_text := public.sa_set_hostel_status(v_pg, 'active');
  perform set_config('role', 'none', true);
  if v_text is distinct from 'active' then
    raise exception 'FAIL 6: reactivating with a running plan gave [%]', v_text;
  end if;
  v_expect := format('%s is active again. Your team can add and change records as usual.', v_renamed);
  select count(*) into v_n
    from public.notifications n
   where n.user_id = v_owner and n.title = 'Hostel reactivated' and n.body = v_expect;
  if v_n <> 1 then
    raise exception 'FAIL 6: the owner has % reactivation notices reading [%]', v_n, v_expect;
  end if;

  -- ─── 7. sa_cancel_subscription: the owner is told, brand-free, and the PG goes read-only ────
  perform set_config('role', 'authenticated', true);
  v_n := public.sa_cancel_subscription(v_pg, v_reason);
  perform set_config('role', 'none', true);
  if v_n is distinct from 1 then
    raise exception 'FAIL 7: cancelling the plan cancelled % periods, expected 1', v_n;
  end if;
  if (select h.status::text from public.hostels h where h.id = v_pg) is distinct from 'readonly' then
    raise exception 'FAIL 7: after cancelling, the PG is % instead of readonly',
      (select h.status::text from public.hostels h where h.id = v_pg);
  end if;
  v_expect := format('The plan for %s has been cancelled. From today your team can still read records, but nothing can be added or changed until a new plan starts. Reason: %s',
                     v_renamed, v_reason);
  select count(*) into v_n
    from public.notifications n
   where n.user_id = v_owner and n.type = 'subscription'
     and n.title = 'Plan cancelled' and n.body = v_expect;
  if v_n <> 1 then
    raise exception 'FAIL 7: the owner has % cancellation notices reading [%]', v_n, v_expect;
  end if;

  -- ─── 8. sa_set_hostel_status: lifting a suspension with no plan leaves it read-only ─────────
  perform set_config('role', 'authenticated', true);
  v_text := public.sa_set_hostel_status(v_pg, 'suspended');
  v_msg  := public.sa_set_hostel_status(v_pg, 'active');
  perform set_config('role', 'none', true);
  if v_text is distinct from 'suspended' or v_msg is distinct from 'readonly' then
    raise exception 'FAIL 8: suspend then reactivate without a plan gave [%] then [%]', v_text, v_msg;
  end if;
  v_expect := format('%s is not suspended, but its plan has ended, so it is read-only until the plan is renewed. Contact support to renew.',
                     v_renamed);
  select count(*) into v_n
    from public.notifications n
   where n.user_id = v_owner and n.type = 'subscription' and n.body = v_expect;
  if v_n <> 1 then
    raise exception 'FAIL 8: the owner has % read-only notices reading [%]', v_n, v_expect;
  end if;

  -- ─── 9. app.users_update_guard: the proof cannot be written by hand; the rest still works ───
  -- As postgres (no row-level security) under the owner's claims, so the trigger is what answers.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  begin
    update public.users set email_verified_at = now() where id = v_owner;
    v_state := 'ok'; v_msg := null;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state <> '42501' or v_msg is distinct from
       'Email verification cannot be granted by hand — it is earned by opening the confirmation link emailed to the address.' then
    raise exception 'FAIL 9: an owner stamping their own email_verified_at gave [%] %', v_state, v_msg;
  end if;
  -- Their own name, on the other hand, is theirs to change.
  update public.users set full_name = v_tag || ' owner renamed' where id = v_owner;
  if (select u.full_name from public.users u where u.id = v_owner) is distinct from v_tag || ' owner renamed' then
    raise exception 'FAIL 9: an owner could not change their own name';
  end if;
  -- The service role may stamp the proof (email-verification does), and a new address clears it.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.users set email = v_tag || '-owner@example.invalid', email_verified_at = null where id = v_owner;
  update public.users set email_verified_at = now() where id = v_owner;
  if (select u.email_verified_at from public.users u where u.id = v_owner) is null then
    raise exception 'FAIL 9: the service role could not stamp email_verified_at';
  end if;
  update public.users set email = v_tag || '-owner2@example.invalid' where id = v_owner;
  if (select u.email_verified_at from public.users u where u.id = v_owner) is not null then
    raise exception 'FAIL 9: changing the address did not clear email_verified_at';
  end if;

  -- ─── 10. Nothing this run wrote names a product ─────────────────────────────────────────────
  select count(*) into v_n
    from public.notifications n
   where n.user_id in (v_sa, v_owner, v_warden)
     and (n.title || ' ' || coalesce(n.body, '')) ~* '(nivora|apnivaas|hostelpro)';
  if v_n <> 0 then
    raise exception 'FAIL 10: % notification(s) written by this run name a product', v_n;
  end if;

  raise notice 'ALL BRAND-FREE MESSAGE TESTS PASSED';
end
$test$;

select 'ALL BRAND-FREE MESSAGE TESTS PASSED' as result;

rollback;
