-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 2026-10-31 — ROUND 5 backend. App contract: docs/round5-api.md.
--   R5.1 Staff (manager, warden) may sign in with Google and Facebook, including accounts an owner
--        created: app.external_signin_allowed now refuses Super Admin only. Google and Facebook
--        prove the address, which is no weaker than the email reset a staff account already has.
--   R5.2 st_pg_profile also returns how many beds are free (in total and by sharing), so a tenant
--        knows before asking to join. Counts only: no room numbers, nobody's name.
-- Redefined live routines are md5-checked (read with md5(prosrc) on 2026-10-31).
-- Undo: 2026-10-31-round5.down.sql. Tests: 2026-10-31-round5.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;
set local lock_timeout = '10s';

do $guard$
declare
  v_expected constant jsonb := jsonb_build_object(
    'app.external_signin_allowed(uuid)', 'f9167c67cdad075b003432cf3910d013',
    'app.guard_external_identity()',     '2ce695fa7d3235f80a3efd8cffb2db09',
    'app.guard_external_identity_link()', '7aa55d2ce127c071fd3e3b564cac8e46',
    'public.st_pg_profile(uuid)',        '9b75e348ea91cf9461e8e29d08fd6185');
  k text;
  v_md5 text;
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  for k in select jsonb_object_keys(v_expected) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = k::regprocedure;
    if v_md5 is distinct from v_expected ->> k then
      raise exception '% is not the body measured on 2026-10-31 (md5 %); nothing changed', k, v_md5;
    end if;
  end loop;
end
$guard$;

-- ─── R5.1 Staff may use Google and Facebook ─────────────────────────────────────────────────
-- No profile yet (a new sign-up), owner, tenant, manager or warden: yes. Super Admin: never.
create or replace function app.external_signin_allowed(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select u.role::text in ('owner', 'student', 'manager', 'warden')
      from public.users u where u.id = p_user), true);
$$;

create or replace function app.guard_external_identity()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if new.provider in ('email', 'phone') then
    return new;
  end if;
  if new.provider not in ('google', 'facebook') then
    raise exception 'This sign-in method is not available.' using errcode = '42501';
  end if;
  if not app.external_signin_allowed(new.user_id) then
    raise exception 'Administrator accounts sign in with their password.' using errcode = '42501';
  end if;
  return new;
end
$fn$;

create or replace function app.guard_external_identity_link()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if not app.external_signin_allowed(new.user_id) then
    raise exception 'Administrator accounts sign in with their password.' using errcode = '42501';
  end if;
  return new;
end
$fn$;

-- ─── R5.2 Free beds on the PG's page ────────────────────────────────────────────────────────
-- What a prospective tenant (or staff applicant) sees. No owner contact, address, pincode or pin;
-- bed counts, never which room or who is in it.
create or replace function public.st_pg_profile(p_hostel_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_h public.hostels%rowtype;
begin
  if not coalesce(app.can_view_pg(p_hostel_id), false) then
    raise exception 'This PG is not available.' using errcode = 'P0001';
  end if;
  select * into v_h from public.hostels h where h.id = p_hostel_id;
  return jsonb_build_object(
    'hostel_id', v_h.id, 'name', v_h.name, 'property_type', v_h.property_type, 'gender_policy', v_h.gender_policy,
    'locality', v_h.locality, 'city', v_h.city, 'description', v_h.description, 'amenities', to_jsonb(v_h.amenities),
    'rules', v_h.rules, 'logo_path', v_h.logo_path, 'cover_paths', to_jsonb(v_h.cover_paths), 'listed', v_h.listed,
    'rating_avg', (select round(avg(r.rating)::numeric, 1) from public.pg_reviews r where r.hostel_id = v_h.id),
    'rating_count', (select count(*) from public.pg_reviews r where r.hostel_id = v_h.id),
    'reviews', coalesce((select jsonb_agg(to_jsonb(x) order by x.updated_at desc)
                           from public.pg_review_list(v_h.id, 10, 0) x), '[]'::jsonb),
    'beds_total', (select count(*) from public.beds b where b.hostel_id = v_h.id),
    'beds_free', (select count(*) from public.beds b where b.hostel_id = v_h.id and b.status = 'free'),
    'free_by_sharing', coalesce((
      select jsonb_agg(jsonb_build_object('sharing', x.capacity, 'free', x.free) order by x.capacity)
        from (select r.capacity, count(*) filter (where b.status = 'free') as free
                from public.rooms r join public.beds b on b.room_id = r.id
               where r.hostel_id = v_h.id
               group by r.capacity) x
       where x.free > 0), '[]'::jsonb));
end
$fn$;

do $verify$
begin
  if exists (select 1 from pg_proc p
              where p.oid in ('app.external_signin_allowed(uuid)'::regprocedure,
                              'app.guard_external_identity()'::regprocedure,
                              'app.guard_external_identity_link()'::regprocedure,
                              'public.st_pg_profile(uuid)'::regprocedure)
                and (not p.prosecdef or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=""')) then
    raise exception 'a redefined routine is not SECURITY DEFINER with an empty search_path';
  end if;
  if position('beds_free' in (select prosrc from pg_proc where oid = 'public.st_pg_profile(uuid)'::regprocedure)) = 0
     or position('''manager'', ''warden''' in (select prosrc from pg_proc
                   where oid = 'app.external_signin_allowed(uuid)'::regprocedure)) = 0 then
    raise exception 'a redefined routine did not take its new body';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261031110000', 'round5') on conflict (version) do nothing;

notify pgrst, 'reload schema';

commit;

-- AFTER APPLYING: run 2026-10-31-round5.test.sql (rolls itself back, ends 'ALL ROUND 5 TESTS PASSED').
