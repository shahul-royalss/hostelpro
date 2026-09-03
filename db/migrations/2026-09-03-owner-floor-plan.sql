-- ─────────────────────────────────────────────────────────────────────────────
-- THE OWNER MAPS THEIR OWN BUILDING
--
-- Until now the physical layout was Super Admin's alone. `sa_update_hostel_structure` takes a
-- total floor count and a total room count, spreads the rooms EVENLY across the floors, and
-- refuses to go down. A real PG is not evenly spread — a ground floor with two big rooms over a
-- first floor with eight small ones is ordinary — and the person who knows that is the owner,
-- not the platform.
--
-- This adds one function: the owner states a plan, floor by floor, and the server reconciles the
-- building to it.
--
--   [{"floor": 1, "rooms": 4, "beds": 3},
--    {"floor": 2, "rooms": 6, "beds": 2}]
--
-- ── WHAT MAKES IT SAFE TO HAND THIS TO AN OWNER ──────────────────────────────────────────────
--
-- A room is not a number in a settings screen. It has beds, the beds have residents, and the
-- residents have fee history. So the only destructive operation this function will perform is
-- removing a room that is EMPTY, and it checks that itself rather than discovering it:
--
--   * `beds.room_id` cascades from rooms, and `rooms.floor_id` cascades from floors — so a
--     careless delete would take the beds with it.
--   * `students.room_id` and `students.bed_id` are NO ACTION, so the database would ultimately
--     refuse and roll back. That is a genuine backstop, and it is not a good experience: the
--     owner would see a raw foreign-key violation naming a constraint.
--
-- So this counts occupants first and raises a sentence naming the room. The FK stays as the
-- thing that makes the guarantee true even if this function is ever wrong.
--
-- ── WHY IT MAY SHRINK WHERE THE SUPER ADMIN'S VERSION MAY NOT ────────────────────────────────
--
-- `sa_update_hostel_structure` is increase-only, which is the right rule for a function that
-- cannot see whether anything would be destroyed — it works in totals and spreads evenly, so
-- "fewer rooms" tells it nothing about WHICH rooms. This one works room by room and checks each,
-- so "remove a room nobody is living in" is a safe and ordinary thing for an owner to do: they
-- mistyped 8 when they meant 3, or a floor is being renovated. A room with anybody in it is
-- refused, by name, every time.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.ow_set_floor_plan(p_hostel_id uuid, p_plan jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
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
begin
  -- ── 1. WHO ────────────────────────────────────────────────────────────────
  -- The owner of THIS hostel, or the Super Admin. `owned_hostel_ids()` is the same helper the
  -- rooms_update policy uses, so ownership means exactly what it means everywhere else.
  if not (app.is_super_admin() or p_hostel_id in (select app.owned_hostel_ids())) then
    raise exception 'Only this hostel''s owner can change its layout.' using errcode = '42501';
  end if;

  -- A lapsed subscription is read-only for everyone but the Super Admin, and the layout is not
  -- an exception to that.
  if not app.is_super_admin() and not app.hostel_writable(p_hostel_id) then
    raise exception 'This hostel is read-only until its subscription is renewed.'
      using errcode = 'P0001';
  end if;

  if not exists (select 1 from public.hostels where id = p_hostel_id) then
    raise exception 'Hostel not found.' using errcode = 'P0001';
  end if;

  -- ── 2. THE PLAN IS CHECKED BEFORE ANYTHING MOVES ──────────────────────────
  if jsonb_typeof(p_plan) <> 'array' or jsonb_array_length(p_plan) = 0 then
    raise exception 'Send a plan with at least one floor.' using errcode = 'P0001';
  end if;

  v_floors := jsonb_array_length(p_plan);
  if v_floors > 50 then
    raise exception 'A hostel may have at most 50 floors.' using errcode = 'P0001';
  end if;

  -- Floors must be 1..N with nothing missing. A plan that names floors 1 and 3 is a plan with a
  -- typo in it, and guessing which the owner meant is not this function's job.
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
    -- 200 is well past any real PG and stops a typo generating a hundred thousand rows.
    if v_want_rooms < 1 or v_want_rooms > 200 then
      raise exception 'Floor % must have between 1 and 200 rooms.', v_floor_no
        using errcode = 'P0001';
    end if;
    -- Matches the CHECK on rooms.capacity, so a bad value is refused here with a sentence
    -- instead of there with a constraint name.
    if v_want_beds < 1 or v_want_beds > 12 then
      raise exception 'Floor %: a room holds between 1 and 12 beds.', v_floor_no
        using errcode = 'P0001';
    end if;
  end loop;

  if (select count(distinct (e ->> 'floor')::int) from jsonb_array_elements(p_plan) e) <> v_floors
  then
    raise exception 'The plan names the same floor twice.' using errcode = 'P0001';
  end if;

  -- ── 3. REFUSE THE WHOLE THING IF ANY PART OF IT WOULD EVICT SOMEBODY ──────
  -- Checked BEFORE the first insert so a plan that cannot complete changes nothing at all. The
  -- function is transactional anyway, but failing late would still have burned the room numbers.
  select string_agg(name, ', ' order by name) into v_blocked
  from (
    -- Rooms on floors the plan drops entirely.
    select r.room_number as name
      from public.rooms r
      join public.floors f on f.id = r.floor_id
     where r.hostel_id = p_hostel_id
       and f.floor_number > v_floors
       and exists (select 1 from public.beds b where b.room_id = r.id and b.student_id is not null)
    union
    -- Rooms that would be trimmed off the end of a floor that is shrinking. Highest room number
    -- first, which is the order the trim below removes them in.
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

  -- ── 4. RECONCILE, FLOOR BY FLOOR ──────────────────────────────────────────
  for v_row in select * from jsonb_array_elements(p_plan) order by (value ->> 'floor')::int loop
    v_floor_no   := (v_row ->> 'floor')::int;
    v_want_rooms := (v_row ->> 'rooms')::int;
    v_want_beds  := (v_row ->> 'beds')::int;

    insert into public.floors (hostel_id, floor_number)
    values (p_hostel_id, v_floor_no)
    on conflict (hostel_id, floor_number)
      do update set updated_at = now()
    returning id into v_floor_id;

    select count(*) into v_have from public.rooms where floor_id = v_floor_id;

    if v_want_rooms > v_have then
      -- The house numbering the scaffolder uses: floor 1 → 101, 102…; floor 2 → 201, 202…, and
      -- four digits once a floor holds more than 99 rooms. An owner may have RENAMED a room, so
      -- the number is probed rather than assumed free — `rooms.room_number` is unique per hostel
      -- and a clash here would abort the whole plan over a cosmetic detail.
      v_multiplier := case when v_want_rooms > 99 then 1000 else 100 end;
      v_seq := 1;
      while v_have < v_want_rooms loop
        v_room_no := (v_floor_no * v_multiplier + v_seq)::text;
        if not exists (
          select 1 from public.rooms
           where hostel_id = p_hostel_id and room_number = v_room_no
        ) then
          -- The beds come with it: app.rooms_capacity_sync fires AFTER INSERT on rooms and
          -- creates `capacity` of them. Nothing here inserts a bed by hand.
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
      -- Highest room number first, and only ones nobody is living in. Step 3 has already proved
      -- that is enough of them; this repeats the occupancy test anyway, because a delete that
      -- depends on a check made earlier in the transaction is one refactor away from not being
      -- checked at all.
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

  -- ── 5. FLOORS THE PLAN NO LONGER HAS ──────────────────────────────────────
  -- Their rooms cascade, and step 3 proved none of them is occupied.
  delete from public.floors
   where hostel_id = p_hostel_id and floor_number > v_floors;

  -- ── 6. THE HOSTEL'S OWN TOTALS FOLLOW THE BUILDING ────────────────────────
  -- Read back rather than computed from the plan: the two must agree, and the rooms table is the
  -- one that is true.
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
end $$;

comment on function public.ow_set_floor_plan(uuid, jsonb) is
  'Owner (or Super Admin) sets the per-floor room counts and each new room''s bed count. Adds '
  'freely; removes only rooms with nobody in them, naming any that block it.';

revoke all on function public.ow_set_floor_plan(uuid, jsonb) from public, anon;
grant execute on function public.ow_set_floor_plan(uuid, jsonb) to authenticated;
