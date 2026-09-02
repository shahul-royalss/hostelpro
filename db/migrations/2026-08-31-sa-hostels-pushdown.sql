-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- rpc_sa_hostels(): push the predicate INTO the function instead of filtering its output.
-- Applied as migration `rpc_sa_hostels_push_filters_into_where`.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
--
-- MEASURED BEFORE, on the live database, as admin@nivora.app:
--
--   explain (analyze, buffers)
--   select * from rpc_sa_hostels() where hostel_id = 'fb4b7a75-…' limit 1;
--
--   Limit                     (actual time=10.379..10.379 rows=1)
--     -> Function Scan on rpc_sa_hostels
--          Filter: (hostel_id = '…')
--          Rows Removed by Filter: 1
--          Buffers: shared hit=1931
--   Execution Time: 10.557 ms
--
-- "Rows Removed by Filter" is the whole story. PostgREST applies .eq()/.or()/.range() to the
-- RESULT of a set-returning function, so the function had already built EVERY hostel on the
-- platform — four correlated count subqueries and a lateral subscriptions lookup each — before
-- one row was kept. The cost is per-platform on a screen that asks about one hostel, which is
-- the wrong axis to grow on: it gets worse for every customer we sign, on every detail page.
--
-- WHAT THIS IS NOT. None of the six parameters is a permission. `where app.is_super_admin()`
-- is still the first thing in the WHERE clause and is untouched, so every other role still gets
-- zero rows rather than an error, exactly as SaRepository's doc comment and the four-valued
-- verdict in sa_ui.dart describe. p_hostel_id NARROWS what a super admin may already read; it
-- can never widen what anyone else reads. Verified by counting rpc_sa_hostels() rows for all
-- eight real users at aal1 and aal2 before and after: 3 for the super admin, 0 for everyone
-- else, unchanged.
--
-- The search argument is escaped for LIKE here rather than trusted. sanitizeSearch() on the
-- Dart side already strips % and \, but that function exists to keep PostgREST's own `or=(...)`
-- parser happy — a reason that no longer applies once the needle travels as an argument. An RPC
-- argument that reaches ILIKE unescaped would make `%` a wildcard for anyone calling the
-- function directly, so the escaping lives at the boundary that actually builds the pattern.
--
-- ORDER BY gained h.id as a tiebreaker. LIMIT/OFFSET now happen inside the function, and an
-- OFFSET over a sort that ties can drop or repeat rows between pages; created_at alone is not
-- unique by anything the schema promises.

drop function if exists public.rpc_sa_hostels();

create function public.rpc_sa_hostels(
  p_hostel_id     uuid                       default null,
  p_search        text                       default null,
  p_sub_state     public.subscription_status default null,
  p_hostel_status public.hostel_status       default null,
  p_limit         integer                    default null,
  p_offset        integer                    default null
)
returns table (
  hostel_id uuid, hostel_name text, hostel_status public.hostel_status, address text,
  owner_id uuid, owner_name text, owner_email text, owner_phone text,
  sub_start date, sub_end date, sub_amount numeric, sub_state public.subscription_status, days_left int,
  total_beds int, occupied_beds int, active_students int, open_complaints int, created_at timestamptz
)
language sql stable security definer set search_path = public as $$
  with pat as (
    select case
             when nullif(btrim(p_search), '') is null then null
             else '%' || replace(replace(replace(btrim(p_search), '\', '\'), '%', '\%'), '_', '\_') || '%'
           end as like_pattern
  )
  select h.id, h.name, h.status, h.address,
         u.id, u.full_name, u.email, u.phone,
         ls.start_date, ls.end_date, ls.amount, app.subscription_state(h.id), app.subscription_days_left(h.id),
         (select count(*)::int from public.beds b where b.hostel_id = h.id),
         (select count(*)::int from public.beds b where b.hostel_id = h.id and b.student_id is not null),
         (select count(*)::int from public.students s where s.hostel_id = h.id and s.status <> 'vacated'),
         (select count(*)::int from public.complaints c where c.hostel_id = h.id and c.status <> 'resolved'),
         h.created_at
  from public.hostels h
  join public.users u on u.id = h.owner_user_id
  left join lateral (
    select * from public.subscriptions s where s.hostel_id = h.id order by s.end_date desc limit 1
  ) ls on true
  cross join pat
  where app.is_super_admin()
    and (p_hostel_id is null or h.id = p_hostel_id)
    and (p_hostel_status is null or h.status = p_hostel_status)
    and (pat.like_pattern is null
         or h.name      ilike pat.like_pattern
         or u.full_name ilike pat.like_pattern
         or u.email     ilike pat.like_pattern
         or h.address   ilike pat.like_pattern)
    and (p_sub_state is null or app.subscription_state(h.id) = p_sub_state)
  order by h.created_at desc, h.id desc
  limit p_limit offset coalesce(p_offset, 0)
$$;

-- Same grants the zero-argument version carried: {postgres, authenticated, service_role}.
-- TWO revokes, both load-bearing, and the second one was found by diffing pg_proc.proacl rather
-- than by reasoning: CREATE FUNCTION hands EXECUTE to PUBLIC, AND this project's ALTER DEFAULT
-- PRIVILEGES on the public schema hands it to anon EXPLICITLY, which a revoke from PUBLIC does
-- not reach. anon would have read zero rows either way -- app.is_super_admin() is false without
-- a JWT -- but it is a grant the function being replaced did not have.
-- Applied as migration `rpc_sa_hostels_revoke_anon_execute`.
revoke all on function public.rpc_sa_hostels(
  uuid, text, public.subscription_status, public.hostel_status, integer, integer) from public;
revoke all on function public.rpc_sa_hostels(
  uuid, text, public.subscription_status, public.hostel_status, integer, integer) from anon;
grant execute on function public.rpc_sa_hostels(
  uuid, text, public.subscription_status, public.hostel_status, integer, integer)
  to authenticated, service_role;

notify pgrst, 'reload schema';
