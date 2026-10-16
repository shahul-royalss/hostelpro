-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- TESTS FOR 2026-10-17-google-sign-in.sql
--
-- Run it as ONE batch, after the migration, as postgres:
--   psql "$DATABASE_URL" -f db/migrations/2026-10-17-google-sign-in.test.sql
-- Everything happens inside BEGIN ... ROLLBACK, so it changes nothing. It builds its own world
-- (a super admin, two owners and a PG, a manager, a warden, a resident, and an auth user with no
-- profile) with fresh ids and tagged @example.com addresses, and reads no real account.
--
-- A failed expectation raises 'FAIL <section>: ...' and aborts the batch. Success ends with
-- NOTICE 'ALL GOOGLE SIGN-IN TESTS PASSED' and a one-row result saying the same, for tools that
-- do not show notices.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;

do $test$
declare
  v_tag    text := 'gsi-' || left(gen_random_uuid()::text, 8);
  v_sa     uuid := gen_random_uuid();
  v_owner  uuid := gen_random_uuid();   -- linked Google with his own, verified address
  v_owner2 uuid := gen_random_uuid();   -- linked Google, then his address was changed
  v_owner3 uuid := gen_random_uuid();   -- linked Google, then the address was re-set (floor moved)
  v_mgr    uuid := gen_random_uuid();
  v_wdn    uuid := gen_random_uuid();
  v_res    uuid := gen_random_uuid();   -- a Google address that Google itself has not verified
  v_bare   uuid := gen_random_uuid();   -- an auth user with no profile row
  v_pg     uuid := gen_random_uuid();
  v_state  text;
  v_msg    text;
  v_n      int;
  v_ts     timestamptz;
  r        record;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  insert into auth.users (id, email) values
    (v_sa,     v_tag || '-sa@example.com'),
    (v_owner,  v_tag || '-owner@example.com'),
    (v_owner2, v_tag || '-owner2-new@example.com'),
    (v_owner3, v_tag || '-owner3@example.com'),
    (v_mgr,    v_tag || '-mgr@example.com'),
    (v_wdn,    v_tag || '-wdn@example.com'),
    (v_res,    v_tag || '-res@example.com'),
    (v_bare,   v_tag || '-bare@example.com');

  insert into public.users (id, role, full_name, email, status, email_verification_reset_at) values
    (v_sa,     'super_admin', v_tag || ' sa',     v_tag || '-sa@example.com',         'active', null),
    (v_owner,  'owner',       v_tag || ' owner',  v_tag || '-owner@example.com',      'active', null),
    (v_owner2, 'owner',       v_tag || ' owner2', v_tag || '-owner2-new@example.com', 'active', now() - interval '1 day'),
    (v_owner3, 'owner',       v_tag || ' owner3', v_tag || '-owner3@example.com',     'active', now() - interval '1 day');

  insert into public.hostels (id, name, owner_user_id, total_floors, total_rooms)
  values (v_pg, v_tag || ' PG', v_owner, 1, 1);
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount)
  values (v_pg, v_owner, current_date - 1, current_date + 365, 0);

  insert into public.users (id, role, full_name, email, hostel_id, status, created_by) values
    (v_mgr, 'manager', v_tag || ' manager',  v_tag || '-mgr@example.com', v_pg, 'active', v_owner),
    (v_wdn, 'warden',  v_tag || ' warden',   v_tag || '-wdn@example.com', v_pg, 'active', v_owner),
    (v_res, 'student', v_tag || ' resident', v_tag || '-res@example.com', v_pg, 'active', null);

  -- ─── 1. The account lookup ──────────────────────────────────────────────────────────────
  select count(*), max(l.role::text), max(l.status::text)
    into v_n, v_msg, v_state
    from public.login_account_for_email('  ' || upper(v_tag) || '-MGR@Example.com ') l
   where l.user_id = v_mgr;
  if v_n <> 1 or v_msg is distinct from 'manager' or v_state is distinct from 'active' then
    raise exception 'FAIL 1: a padded, upper-case manager address gave % rows, role %, status %', v_n, v_msg, v_state;
  end if;

  select count(*), max(l.role::text) into v_n, v_msg
    from public.login_account_for_email(v_tag || '-bare@example.com') l;
  if v_n <> 1 or v_msg is not null then
    raise exception 'FAIL 1: an auth user with no profile gave % rows, role %', v_n, v_msg;
  end if;

  select count(*) into v_n from public.login_account_for_email(v_tag || '-nobody@example.com');
  if v_n <> 0 then
    raise exception 'FAIL 1: an unknown address gave % rows', v_n;
  end if;

  if has_function_privilege('anon', 'public.login_account_for_email(text)', 'execute')
     or has_function_privilege('authenticated', 'public.login_account_for_email(text)', 'execute') then
    raise exception 'FAIL 1: a client role can call login_account_for_email';
  end if;

  -- ─── 2. Google and Facebook never attach to staff or the super admin ────────────────────
  for r in
    select * from (values
      (v_sa,    'google',   'super admin'),
      (v_mgr,   'google',   'manager'),
      (v_wdn,   'google',   'warden'),
      (v_mgr,   'facebook', 'manager'),
      (v_owner, 'github',   'owner (github)'),
      (v_bare,  'twitter',  'no-profile user (twitter)')
    ) t(uid, provider, label)
  loop
    v_state := null;
    v_msg := null;
    begin
      insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (v_tag || '-' || r.provider || '-' || r.uid, r.uid,
              jsonb_build_object('sub', v_tag || '-' || r.uid, 'email', v_tag || '-x@example.com', 'email_verified', true),
              r.provider, now(), now(), now());
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    end;
    if v_state is distinct from '42501' then
      raise exception 'FAIL 2: % on a % was not refused: [%] %', r.provider, r.label, v_state, v_msg;
    end if;
  end loop;

  -- ─── 3. ...and do attach to owners, residents, brand-new sign-ups, and email anywhere ───
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at) values
    (v_tag || '-g-owner',  v_owner,
     jsonb_build_object('sub', v_tag || '-g-owner', 'email', v_tag || '-owner@example.com', 'email_verified', true),
     'google', now(), now(), now()),
    (v_tag || '-g-owner2', v_owner2,
     jsonb_build_object('sub', v_tag || '-g-owner2', 'email', v_tag || '-owner2-old@example.com', 'email_verified', true),
     'google', now(), now(), now()),
    (v_tag || '-g-owner3', v_owner3,
     jsonb_build_object('sub', v_tag || '-g-owner3', 'email', v_tag || '-owner3@example.com', 'email_verified', true),
     'google', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days'),
    (v_tag || '-g-res',    v_res,
     jsonb_build_object('sub', v_tag || '-g-res', 'email', v_tag || '-res@example.com', 'email_verified', false),
     'google', now(), now(), now()),
    (v_tag || '-g-bare',   v_bare,
     jsonb_build_object('sub', v_tag || '-g-bare', 'email', v_tag || '-bare@example.com', 'email_verified', true),
     'google', now(), now(), now()),
    (v_tag || '-f-res',    v_res,
     jsonb_build_object('sub', v_tag || '-f-res', 'email', v_tag || '-res@example.com'),
     'facebook', now(), now(), now()),
    (v_mgr::text,          v_mgr,
     jsonb_build_object('sub', v_mgr::text, 'email', v_tag || '-mgr@example.com', 'email_verified', false),
     'email', now(), now(), now());

  select count(*) into v_n from auth.identities where provider_id like v_tag || '-%' or provider_id = v_mgr::text;
  if v_n <> 7 then
    raise exception 'FAIL 3: expected 7 allowed identities, found %', v_n;
  end if;

  -- ─── 4. Moving an identity onto staff is linking it; touching its data is not ───────────
  v_state := null;
  begin
    update auth.identities set user_id = v_mgr where provider_id = v_tag || '-g-res' and provider = 'google';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state is distinct from '42501' then
    raise exception 'FAIL 4: moving a Google identity onto a manager gave [%] %', v_state, v_msg;
  end if;

  v_state := null;
  begin
    update auth.identities set provider = 'github' where provider_id = v_tag || '-g-bare' and provider = 'google';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  end;
  if v_state is distinct from '42501' then
    raise exception 'FAIL 4: renaming a Google identity to github gave [%] %', v_state, v_msg;
  end if;

  update auth.identities
     set identity_data = identity_data || jsonb_build_object('name', 'Renamed'), last_sign_in_at = now(), updated_at = now()
   where provider_id = v_tag || '-g-owner' and provider = 'google';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FAIL 4: an ordinary identity update touched % rows', v_n;
  end if;

  -- The address-change functions update the EMAIL identity's identity_data on staff accounts.
  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_tag || '-mgr2@example.com'), true), updated_at = now()
   where user_id = v_mgr and provider = 'email';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'FAIL 4: an address change on a manager''s email identity touched % rows', v_n;
  end if;

  -- ─── 5. ARM C: a verified Google address proves the account's current address ───────────
  v_ts := public.email_link_proof(v_owner);
  if v_ts is null then
    raise exception 'FAIL 5: an owner signed in with Google on his own verified address got no proof';
  end if;

  if public.email_link_proof(v_owner2) is not null then
    raise exception 'FAIL 5: a Google identity for the OLD address proved the new one';
  end if;

  if public.email_link_proof(v_owner3) is not null then
    raise exception 'FAIL 5: a Google sign-in from before the floor counted';
  end if;

  if public.email_link_proof(v_res) is not null then
    raise exception 'FAIL 5: an address Google had not verified counted (or the facebook identity did)';
  end if;

  -- The owner3 identity used again after the floor does count: it is a fresh proof.
  update auth.identities set last_sign_in_at = now(), updated_at = now()
   where provider_id = v_tag || '-g-owner3' and provider = 'google';
  if public.email_link_proof(v_owner3) is null then
    raise exception 'FAIL 5: a Google sign-in after the floor did not count';
  end if;

  -- A user id with no profile row has no floor, and so no proof.
  if public.email_link_proof(v_bare) is not null then
    raise exception 'FAIL 5: an auth user with no profile got a proof';
  end if;

  raise notice 'ALL GOOGLE SIGN-IN TESTS PASSED';
end
$test$;

select 'ALL GOOGLE SIGN-IN TESTS PASSED' as result;

rollback;
