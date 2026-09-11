-- ─────────────────────────────────────────────────────────────────────────────
-- FLOORS GET NAMES, AND THE WARDEN CAN EDIT THE LAYOUT TOO
--
-- The product owner: "like how admin can edit layout same as like that warden also can have
-- edit layout option and they can also edit the floor names... in both admin and warden".
--
-- ── 1. A NAME FOR A FLOOR ───────────────────────────────────────────────────────────────────
--
-- public.floors had a number and nothing else, so every screen printed "Floor 1". Real PGs say
-- "Ground floor", "Terrace", "Girls' wing". floors.name is optional, trimmed, 1–40 characters,
-- and every screen falls back to "Floor N" when it is null — so a hostel that never names a
-- floor sees exactly what it saw before.
--
-- The NUMBER stays the identity. ow_set_floor_plan reasons about floors as 1..N, room numbers
-- are derived from it (101, 201…), and a name is a label on top of that, never a key.
--
-- ── 2. WHO MAY RESHAPE A BUILDING ───────────────────────────────────────────────────────────
--
-- app.can_edit_layout(hostel) = Super Admin, the hostel's owner, or an active warden of that
-- hostel. It gates ow_set_floor_plan (which until now said "Only this hostel's owner") and the
-- new set_floor_name. The warden is the person standing in the building; the owner asked for
-- them to have the same editor, and the safety of that editor does not depend on who holds it:
-- ow_set_floor_plan still refuses, by name, to remove any room somebody is sleeping in.
--
-- The manager is deliberately NOT included. CLAUDE_2.md §6.3 scopes the manager to money, tasks
-- and the menu; rooms and residents are not theirs.
--
-- ── 3. THE GRID LEARNS THE NAME ─────────────────────────────────────────────────────────────
--
-- rpc_room_occupancy gains floor_name as its LAST column, so anything reading the existing six
-- positionally is untouched. Changing a RETURNS TABLE signature cannot be done with CREATE OR
-- REPLACE, hence the drop — inside this migration's transaction, so there is no moment at which
-- the function is missing — and the grants are restated because a dropped function takes its
-- ACL with it. Supabase grants EXECUTE on new public functions to anon explicitly, so the
-- revoke names anon rather than relying on PUBLIC.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.floors add column if not exists name text;
alter table public.floors drop constraint if exists floors_name_check;
alter table public.floors add constraint floors_name_check
  check (name is null or (name = btrim(name) and char_length(name) between 1 and 40));

create or replace function app.can_edit_layout(p_hostel_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select app.is_super_admin()
      or p_hostel_id in (select app.owned_hostel_ids())
      or (app.user_hostel_id() = p_hostel_id and app.user_role() = 'warden')
$$;

create or replace function public.set_floor_name(p_floor_id uuid, p_name text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_hostel uuid;
  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
begin
  select hostel_id into v_hostel from public.floors where id = p_floor_id;
  -- One message for "no such floor" and "not your floor", so this is not an oracle for which
  -- floor ids exist.
  if v_hostel is null or not app.can_edit_layout(v_hostel) then
    raise exception 'You can''t rename that floor.' using errcode = '42501';
  end if;
  if not app.is_super_admin() and not app.hostel_writable(v_hostel) then
    raise exception 'This hostel is read-only until its subscription is renewed.' using errcode = 'P0001';
  end if;
  if v_name is not null and char_length(v_name) > 40 then
    raise exception 'A floor name can be at most 40 characters.' using errcode = 'P0001';
  end if;
  update public.floors set name = v_name, updated_at = now() where id = p_floor_id;
end $$;

revoke all on function public.set_floor_name(uuid, text) from public, anon;
grant execute on function public.set_floor_name(uuid, text) to authenticated;

drop function if exists public.rpc_room_occupancy(uuid);
create function public.rpc_room_occupancy(p_hostel_id uuid)
returns table(room_id uuid, floor_id uuid, floor_number integer, room_number text,
              capacity integer, occupied integer, floor_name text)
language sql stable set search_path to 'public' as $function$
  select r.id, f.id, f.floor_number, r.room_number, r.capacity,
         (select count(*)::int from public.beds b where b.room_id = r.id and b.student_id is not null),
         f.name
    from public.rooms r
    join public.floors f on f.id = r.floor_id
   where r.hostel_id = p_hostel_id
   order by f.floor_number, r.room_number
$function$;

revoke all on function public.rpc_room_occupancy(uuid) from public, anon;
grant execute on function public.rpc_room_occupancy(uuid) to authenticated, service_role;

-- The whole function, restated rather than patched: three things change in it at once (who may
-- call it, the 20-bed ceiling applied on 2026-09-12, and the optional per-floor name), and a
-- chain of string replacements over its own definition would be three places to get wrong.
create or replace function public.ow_set_floor_plan(p_hostel_id uuid, p_plan jsonb)
returns jsonb
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_floors      int;
  v_row         jsonb;
  v_floor_no    int;
  v_want_rooms  int;
  v_want_beds   int;
  v_floor_id    uuid;
  v_have        int;
  v_added       int := 0;
  v_removed     int := 0;
  v_seq         int;
  v_room_no     text;
  v_multiplier  int;
  v_blocked     text;
  v_new_id      uuid;
  v_name        text;
begin
  if not app.can_edit_layout(p_hostel_id) then
    raise exception 'Only this hostel''s owner or warden can change its layout.' using errcode = '42501';
  end if;

  if not app.is_super_admin() and not app.hostel_writable(p_hostel_id) then
    raise exception 'This hostel is read-only until its subscription is renewed.'
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.hostels where id = p_hostel_id) then
    raise exception 'Hostel not found.' using errcode = 'P0001';
  end if;

  if jsonb_typeof(p_plan) <> 'array' or jsonb_array_length(p_plan) = 0 then
    raise exception 'Send a plan with at least one floor.' using errcode = 'P0001';
  end if;

  v_floors := jsonb_array_length(p_plan);
  if v_floors > 50 then
    raise exception 'A hostel may have at most 50 floors.' using errcode = 'P0001';
  end if;

  for v_row in select * from jsonb_array_elements(p_plan) loop
    v_floor_no   := (v_row ->> 'floor')::int;
    v_want_rooms := (v_row ->> 'rooms')::int;
    v_want_beds  := (v_row ->> 'beds')::int;

    if v_floor_no is null or v_want_rooms is null or v_want_beds is null then
      raise exception 'Every floor needs a number, a room count and a bed count.'
        using errcode = 'P0001';
    end if;
    if v_floor_no < 1 or v_floor_no > v_floors then
      raise exception 'Floors must be numbered 1 to % with none missing.', v_floors
        using errcode = 'P0001';
    end if;
    if v_want_rooms < 1 or v_want_rooms > 200 then
      raise exception 'Floor % must have between 1 and 200 rooms.', v_floor_no
        using errcode = 'P0001';
    end if;
    if v_want_beds < 1 or v_want_beds > 20 then
      raise exception 'Floor %: a room holds between 1 and 20 beds.', v_floor_no
        using errcode = 'P0001';
    end if;
    -- `name` is optional. Present-and-null clears it; absent leaves whatever is there alone,
    -- so a plan that never mentions names cannot wipe the ones set with set_floor_name.
    if (v_row -> 'name') is not null and jsonb_typeof(v_row -> 'name') not in ('string', 'null') then
      raise exception 'Floor %: the name must be text.', v_floor_no using errcode = 'P0001';
    end if;
    if char_length(btrim(coalesce(v_row ->> 'name', ''))) > 40 then
      raise exception 'Floor %: a floor name can be at most 40 characters.', v_floor_no
        using errcode = 'P0001';
    end if;
  end loop;

  if (select count(distinct (e ->> 'floor')::int) from jsonb_array_elements(p_plan) e) <> v_floors
  then
    raise exception 'The plan names the same floor twice.' using errcode = 'P0001';
  end if;

  select string_agg(name, ', ' order by name) into v_blocked
  from (
    select r.room_number as name
      from public.rooms r
      join public.floors f on f.id = r.floor_id
     where r.hostel_id = p_hostel_id
       and f.floor_number > v_floors
       and exists (select 1 from public.beds b where b.room_id = r.id and b.student_id is not null)
    union
    select name from (
      select r.room_number as name,
             row_number() over (partition by f.floor_number order by r.room_number desc) as rn,
             (select count(*) from public.rooms r2 where r2.floor_id = f.id) as have,
             (select (e ->> 'rooms')::int from jsonb_array_elements(p_plan) e
               where (e ->> 'floor')::int = f.floor_number) as want,
             (select count(*) from public.beds b where b.room_id = r.id and b.student_id is not null) as occ
        from public.rooms r
        join public.floors f on f.id = r.floor_id
       where r.hostel_id = p_hostel_id and f.floor_number <= v_floors
    ) t
    where want is not null and have > want and rn <= (have - want) and occ > 0
  ) blocked;

  if v_blocked is not null then
    raise exception 'Room % still has residents in it. Move them to another bed first.', v_blocked
      using errcode = 'P0001';
  end if;

  for v_row in select * from jsonb_array_elements(p_plan) order by (value ->> 'floor')::int loop
    v_floor_no   := (v_row ->> 'floor')::int;
    v_want_rooms := (v_row ->> 'rooms')::int;
    v_want_beds  := (v_row ->> 'beds')::int;

    insert into public.floors (hostel_id, floor_number)
    values (p_hostel_id, v_floor_no)
    on conflict (hostel_id, floor_number)
      do update set updated_at = now()
    returning id into v_floor_id;

    if (v_row -> 'name') is not null then
      v_name := nullif(btrim(coalesce(v_row ->> 'name', '')), '');
      update public.floors set name = v_name
       where id = v_floor_id and name is distinct from v_name;
    end if;

    select count(*) into v_have from public.rooms where floor_id = v_floor_id;

    if v_want_rooms > v_have then
      v_multiplier := case when v_want_rooms > 99 then 1000 else 100 end;
      v_seq := 1;
      while v_have < v_want_rooms loop
        v_room_no := (v_floor_no * v_multiplier + v_seq)::text;
        if not exists (
          select 1 from public.rooms
           where hostel_id = p_hostel_id and room_number = v_room_no
        ) then
          insert into public.rooms (hostel_id, floor_id, room_number, capacity)
          values (p_hostel_id, v_floor_id, v_room_no, v_want_beds)
          returning id into v_new_id;
          v_have  := v_have + 1;
          v_added := v_added + 1;
        end if;
        v_seq := v_seq + 1;
        if v_seq > 100000 then
          raise exception 'Could not find a free room number on floor %.', v_floor_no
            using errcode = 'P0001';
        end if;
      end loop;

    elsif v_want_rooms < v_have then
      with doomed as (
        select r.id
          from public.rooms r
         where r.floor_id = v_floor_id
           and not exists (
             select 1 from public.beds b where b.room_id = r.id and b.student_id is not null
           )
         order by r.room_number desc
         limit (v_have - v_want_rooms)
      )
      delete from public.rooms r using doomed d where r.id = d.id;
      get diagnostics v_seq = row_count;
      v_removed := v_removed + v_seq;
    end if;
  end loop;

  delete from public.floors
   where hostel_id = p_hostel_id and floor_number > v_floors;

  update public.hostels h
     set total_floors = v_floors,
         total_rooms  = (select count(*) from public.rooms where hostel_id = p_hostel_id),
         updated_at   = now()
   where h.id = p_hostel_id;

  return jsonb_build_object(
    'floors',        v_floors,
    'rooms_added',   v_added,
    'rooms_removed', v_removed,
    'rooms_total',   (select count(*) from public.rooms where hostel_id = p_hostel_id),
    'beds_total',    (select count(*) from public.beds  where hostel_id = p_hostel_id)
  );
end $function$;
