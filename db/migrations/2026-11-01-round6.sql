-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 2026-11-01 — ROUND 6 backend. App contract: docs/round6-api.md.
--   R6.1 st_pg_profile says only WHETHER a bed is free (beds_available), never how many: the
--        owner's rule ("tenants can only know beds are available or not"). beds_total,
--        beds_free and free_by_sharing are gone.
--   R6.2 st_pg_profile returns the owner's map pin (latitude, longitude, 6 decimals) when one is
--        set, so a tenant can see the PG on a map and open it in Google Maps. Who may read the
--        page is unchanged (app.can_view_pg: a listed, active PG, or one's own PG).
--   R6.3 st_browse_hostels(): the listed PGs, before anything is typed into Find a PG. Same
--        columns, same tenant-only rule and same rate limit as st_search_hostels.
-- Redefined live routines are md5-checked (read with md5(prosrc) on 2026-11-01).
-- Undo: 2026-11-01-round6.down.sql. Tests: 2026-11-01-round6.test.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;
set local lock_timeout = '10s';

do $guard$
declare
  v_md5 text;
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres (got %)', current_user;
  end if;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = 'public.st_pg_profile(uuid)'::regprocedure;
  if v_md5 is distinct from '5ffe197f2195ee26f1e9528d7ed07679' then
    raise exception 'public.st_pg_profile(uuid) is not the body measured on 2026-11-01 (md5 %); nothing changed', v_md5;
  end if;
  if to_regprocedure('public.st_browse_hostels()') is not null then
    raise exception 'public.st_browse_hostels() already exists; nothing changed';
  end if;
end
$guard$;

-- ─── R6.1 + R6.2 The PG page: beds yes or no, and the pin ───────────────────────────────────
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
    'beds_available', exists (select 1 from public.beds b where b.hostel_id = v_h.id and b.status = 'free'),
    'latitude', round(v_h.latitude::numeric, 6),
    'longitude', round(v_h.longitude::numeric, 6));
end
$fn$;

-- ─── R6.3 The listed PGs, before a search ───────────────────────────────────────────────────
create function public.st_browse_hostels()
returns table (hostel_id uuid, name text, property_type text, gender_policy text, locality text,
               city text, distance_km numeric, logo_path text, rating_avg numeric,
               rating_count integer, amenities text[])
language plpgsql security definer set search_path = '' as $fn$
begin
  if auth.uid() is null or not coalesce(app.user_role() = 'student', false) then
    raise exception 'Only a tenant account can search for PGs.' using errcode = '42501';
  end if;
  perform app.spend('hostel_search', 120, 3600, 'Too many searches. Try again in a few minutes.');

  return query
    select h.id, h.name, h.property_type, h.gender_policy, h.locality, h.city, null::numeric,
           h.logo_path, rt.avg, rt.n, h.amenities
      from public.hostels h
      left join lateral (select round(avg(r.rating)::numeric, 1) as avg, count(*)::int as n
                           from public.pg_reviews r where r.hostel_id = h.id) rt on true
     where h.listed
       and h.status = 'active'
       and app.hostel_writable(h.id)
     order by rt.n desc, rt.avg desc nulls last, h.name, h.id
     limit 25;
end
$fn$;

revoke all on function public.st_browse_hostels() from public, anon;
grant execute on function public.st_browse_hostels() to authenticated;

do $verify$
begin
  if exists (select 1 from pg_proc p
              where p.oid in ('public.st_pg_profile(uuid)'::regprocedure,
                              'public.st_browse_hostels()'::regprocedure)
                and (not p.prosecdef or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=""')) then
    raise exception 'a routine is not SECURITY DEFINER with an empty search_path';
  end if;
  if position('beds_available' in (select prosrc from pg_proc where oid = 'public.st_pg_profile(uuid)'::regprocedure)) = 0
     or position('beds_free''' in (select prosrc from pg_proc where oid = 'public.st_pg_profile(uuid)'::regprocedure)) > 0 then
    raise exception 'st_pg_profile did not take its new body';
  end if;
  if has_function_privilege('anon', 'public.st_browse_hostels()', 'execute') then
    raise exception 'anon may call st_browse_hostels';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261101090000', 'round6') on conflict (version) do nothing;

notify pgrst, 'reload schema';

commit;
