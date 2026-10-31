-- UNDO 2026-10-31-round5.sql: puts back the round 3 bodies (staff Google only when self-created;
-- no bed counts on the PG page). Run as postgres.
begin;
set local lock_timeout = '10s';

create or replace function app.external_signin_allowed(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select case
             when u.role in ('owner', 'student') then true
             when u.role in ('manager', 'warden') then
                  u.signup_source in ('self_google', 'self_facebook', 'self_truecaller')
               or (u.signup_source = 'self_email' and u.email_verified_at is not null)
             else false end
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
    raise exception 'Staff and administrator accounts sign in with the login they were given.' using errcode = '42501';
  end if;
  return new;
end
$fn$;

create or replace function app.guard_external_identity_link()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if not app.external_signin_allowed(new.user_id) then
    raise exception 'Staff and administrator accounts sign in with the login they were given.' using errcode = '42501';
  end if;
  return new;
end
$fn$;

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
                           from public.pg_review_list(v_h.id, 10, 0) x), '[]'::jsonb));
end
$fn$;

delete from supabase_migrations.schema_migrations where version = '20261031110000';

notify pgrst, 'reload schema';

commit;
