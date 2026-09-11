-- ─────────────────────────────────────────────────────────────────────────────
-- UP TO FIVE MANAGERS AND FIVE WARDENS PER PG
--
-- The product owner: "we have added successfully another pg in existing owner account through
-- super admin... then what about that pg warden and manager accounts... owner can create upto 5
-- warden & 5 manager accounts."
--
-- Hard rule §4.3 used to be ONE active manager and ONE active warden per hostel, enforced three
-- times over: app.enforce_role_limits (a friendly sentence), the partial unique index
-- users_one_active_staff_per_hostel (the race the trigger's count(*) cannot settle), and a
-- pre-check in supabase/functions/owner-create-staff. A real PG with two shifts, or a second
-- building on the same compound, needs more than one of each.
--
-- ── WHY THE UNIQUE INDEX GOES, AND WHAT REPLACES ITS JOB ────────────────────────────────────
--
-- A unique index can say "at most one" and nothing else, so it cannot express five. Dropping it
-- alone would reopen the race it existed to close: two owners' taps arriving together could both
-- count four and both insert, landing six. So the trigger now takes a transaction-scoped advisory
-- lock on (hostel, role) BEFORE it counts. The second activation waits for the first to commit,
-- and under READ COMMITTED its count statement then sees the first one's row. Five is exact.
--
-- The lock is taken only for manager and warden rows. Students have a 10,000 ceiling that no
-- race can meaningfully overshoot, and serialising every student registration in a hostel to
-- protect it would be cost with no benefit.
--
-- ── WHAT STILL ASSUMES ONE ──────────────────────────────────────────────────────────────────
--
-- public.st_hostel_contacts shows a resident ONE warden and ONE manager to call. That is still
-- the right shape for a contact card — a resident needs a name, not a roster — but `limit 1`
-- with no `order by` picks an arbitrary row, and with five candidates "arbitrary" would change
-- from one page load to the next. It now names the longest-serving active holder.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function app.enforce_role_limits() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_count int;
  v_limit int;
begin
  if new.status <> 'active' or new.deleted_at is not null then
    return new;
  end if;
  if new.role not in ('manager','warden','student') then
    return new;
  end if;
  if new.hostel_id is null then
    raise exception 'A % must belong to a hostel.', new.role using errcode = 'P0001';
  end if;

  v_limit := case new.role when 'manager' then 5 when 'warden' then 5 else 10000 end;

  if new.role in ('manager','warden') then
    -- Replaces users_one_active_staff_per_hostel. See the header.
    perform pg_advisory_xact_lock(hashtextextended(new.hostel_id::text || ':' || new.role::text, 0));
  end if;

  select count(*) into v_count
  from public.users u
  where u.hostel_id = new.hostel_id
    and u.role = new.role
    and u.status = 'active'
    and u.deleted_at is null
    and u.id <> new.id;

  if v_count >= v_limit then
    if new.role = 'student' then
      raise exception 'This hostel has reached the limit of 10,000 active students.' using errcode = 'P0001';
    else
      -- The Flutter sheet and the edge function both recognise this sentence by its opening
      -- words ("This PG already has 5 active"), so it is a contract, not just copy.
      raise exception 'This PG already has % active %s. Deactivate one first.', v_limit, new.role
        using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;

drop index if exists public.users_one_active_staff_per_hostel;

create or replace function public.st_hostel_contacts()
returns table(hostel_name text, address text, rules text, warden_name text, warden_phone text,
              manager_name text, manager_phone text, owner_name text)
language sql stable security definer set search_path to 'public' as $function$
  select h.name, h.address, h.rules,
    (select u.full_name from public.users u
      where u.hostel_id = h.id and u.role = 'warden' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.phone from public.users u
      where u.hostel_id = h.id and u.role = 'warden' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.full_name from public.users u
      where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.phone from public.users u
      where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.full_name from public.users u where u.id = h.owner_user_id)
  from public.hostels h
  where h.id = coalesce(app.user_hostel_id(),
                        (select hostel_id from public.students where user_id = auth.uid() limit 1))
    and app.mfa_satisfied()
$function$;
