-- UNDO 2026-11-01-round6.sql: puts back the round 5 st_pg_profile (bed counts, no pin) and drops
-- st_browse_hostels. Run as postgres.
begin;
set local lock_timeout = '10s';

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

drop function if exists public.st_browse_hostels();

delete from supabase_migrations.schema_migrations where version = '20261101090000';

notify pgrst, 'reload schema';

commit;
