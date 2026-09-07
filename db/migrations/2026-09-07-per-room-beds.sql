-- ─────────────────────────────────────────────────────────────────────────────
-- EVERY ROOM GETS ITS OWN BED COUNT AND ITS OWN NAME
--
-- The product owner's words: "each room they can change their beds as their wish like Room 103
-- having 4 beds but room 104 having 3 beds… as many beds as they want as less as they want, and
-- owner and warden can change the room names."
--
-- Most of that is already true. `rooms.capacity` is per-room, and app.rooms_capacity_sync turns a
-- change to it into bed rows — adding empty beds when it goes up, removing only FREE beds when it
-- goes down, and refusing to strip a bed somebody is asleep in. `rooms.room_number` is text
-- precisely so a PG can call a room "Annexe 2". What this migration fixes is the two places the
-- database did not yet agree with that sentence.
--
-- ── 1. THE OWNER WAS MISSING FROM rooms_update, IN THE REPOSITORY ────────────────────────────
--
-- The live database has admitted the owner since 2026-09-02 and the Flutter code has said so in
-- comments since then ("the RLS admits the warden AND the owner"). No migration ever recorded it.
-- So db/rls-policies.sql and 2026-08-31-rls-initplan-hoist.sql both still say warden-only, and
-- rebuilding this database from the repository would have quietly taken away the owner's ability
-- to rename a room or change its beds — while every screen went on offering both.
--
-- This is a no-op against the live database on purpose: it states what is already there, so the
-- two stop disagreeing. Repository drift that only shows up on a restore is the kind that gets
-- found during the restore.
--
-- ── 2. TWELVE BEDS WAS NOT A RULE, IT WAS A NUMBER ───────────────────────────────────────────
--
-- `check (capacity between 1 and 12)` has been in the schema since the beginning with no comment
-- explaining it, and nothing in the product depends on it. Indian PGs and hostels routinely run
-- dormitories well past twelve. The ceiling goes to 20.
--
-- A ceiling still has to exist — it is what stops a typo in a stepper turning into hundreds of
-- bed rows, and the trigger creates a row per bed. 20 is the largest count that still describes a
-- ROOM rather than a hall, and it keeps the per-bed list in the warden's room sheet to a length a
-- person can actually scroll and assign from.
--
-- WIDENING A CHECK IS SAFE: no existing row can violate the new bound, so the validation scan
-- cannot fail. Narrowing it back later would not be safe, which is worth knowing before anyone
-- tries.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── STATUS: SECTION 1 IS ALREADY TRUE OF THE LIVE DATABASE; SECTION 2 IS NOT YET APPLIED ────
--
-- Running the whole file is safe and idempotent: section 1 re-states the policy the live
-- database already has, and section 2 is the widening that has not been run.
--
-- WHEN SECTION 2 IS RUN, FOUR PLACES IN THE APPLICATION FOLLOW IT, and until then they are
-- correct as they stand — a stepper that offers a value the server refuses is a trap:
--
--   nivora_app/lib/data/models/structure.dart   maxBedsPerRoom            12 -> 20
--   db/schema.sql                               both CHECK constraints    12 -> 20
--   lib/validators/super-admin.ts               .max(12, "Maximum 12 …")  12 -> 20
--   supabase/functions/sa-create-owner/index.ts { min: 1, max: 12 }       12 -> 20
--
-- Nothing in the product depends on 12 otherwise; the room grid draws one dot per bed and
-- already wraps.

begin;

-- ── 1 ────────────────────────────────────────────────────────────────────────
drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms for update
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    (select app.is_super_admin())
    -- hostel_writable() on both non-SA branches: a lapsed subscription is read-only, and the
    -- layout is not an exception to that.
    or (hostel_id in (select app.owned_hostel_ids()) and app.hostel_writable(hostel_id))
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'
        and app.hostel_writable(hostel_id))
  );

-- Insert and delete stay Super-Admin-only, deliberately. Adding and removing ROOMS is
-- public.ow_set_floor_plan's job, which counts occupants first and names the room it refuses;
-- a bare DELETE would take the beds with it by cascade and find out about the residents from a
-- foreign-key violation.

-- ── 2 ────────────────────────────────────────────────────────────────────────
alter table public.rooms drop constraint if exists rooms_capacity_check;
alter table public.rooms add constraint rooms_capacity_check
  check (capacity between 1 and 20);

alter table public.hostels drop constraint if exists hostels_beds_per_room_default_check;
alter table public.hostels add constraint hostels_beds_per_room_default_check
  check (beds_per_room_default between 1 and 20);

-- ow_set_floor_plan carries the same bound in its own words, so that a bad value is refused with
-- a sentence instead of a constraint name. Patched from its own definition rather than restated:
-- the function is 250 lines and only two of its characters are changing, and a copy pasted here
-- would be a second place for it to drift from. The `raise` is what stops this being a silent
-- no-op if the function is ever rewritten around these strings.
do $patch$
declare
  src     text;
  patched text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'ow_set_floor_plan';

  if src is null then
    raise exception 'ow_set_floor_plan does not exist — run 2026-09-03-owner-floor-plan.sql first';
  end if;

  patched := replace(src, 'v_want_beds > 12', 'v_want_beds > 20');
  patched := replace(patched, 'between 1 and 12 beds', 'between 1 and 20 beds');

  if patched = src and src not like '%v_want_beds > 20%' then
    raise exception 'ow_set_floor_plan no longer contains the 12-bed guard this expected to patch';
  end if;

  execute patched;
end $patch$;

commit;
