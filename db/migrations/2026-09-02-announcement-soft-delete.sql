-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-09-02 · ANNOUNCEMENTS: a soft delete the owner can actually perform
-- ─────────────────────────────────────────────────────────────────────────────
--
-- WHAT WAS BROKEN. `announcements.deleted_at` exists, and rls-policies.sql gives the owner an
-- UPDATE policy over their own hostel's rows, so "retract a notice" reads like a one-line
-- update. It is not. Every attempt is refused with 42501 — at aal2, by the hostel's real owner,
-- with a WITH CHECK that provably evaluates true:
--
--     set local request.jwt.claims = '{"sub":"<owner>","role":"authenticated","aal":"aal2"}';
--     select (select count(*) from app.owned_hostel_ids() x where x = '<hostel>'),   -- 1
--            app.hostel_writable('<hostel>');                                        -- true
--     update public.announcements set deleted_at = now() where id = '<id>';
--     -- ERROR: 42501 new row violates row-level security policy for table "announcements"
--
-- WHY. `announcements_select` is `deleted_at is null and (...)`. PostgreSQL applies a table's
-- SELECT policy to the NEW row of an UPDATE: a row may not be updated out of the updater's own
-- visibility. Setting `deleted_at` makes the new row invisible under that policy, so the write
-- is rejected no matter how permissive the UPDATE policy is. Measured here against a scratch
-- table whose only UPDATE policy was `using (true) with check (true)` and whose SELECT policy
-- was `using (deleted_at is null)` — still refused. It is structural, not a mis-written policy,
-- and no arrangement of client-side calls gets around it. It is also not reachable from the
-- other direction: `announcements_delete` is `app.is_service_role()`, so a hard delete is not
-- open to the owner either. Before this migration an owner could post a notice and never
-- retract it.
--
-- THE FIX. One security-definer RPC in the ow_* family (ow_update_hostel_rules is its
-- neighbour), which re-checks ownership and the §4.4 read-only gate itself and then performs
-- the update with RLS out of the way.
--
-- THE SELECT POLICY IS DELIBERATELY NOT LOOSENED. Letting an owner read back their own
-- retracted notices would change what the noticeboard returns for a role that reads it every
-- day, to buy nothing the owner asked for: the audit trail `deleted_at` preserves is for the
-- database and for whoever answers a dispute later, not for the app's own list. The client's
-- `.isFilter('deleted_at', null)` in NoticeRepository.page stays what it was — redundant with
-- the policy, and legible at the call site.
--
-- IDEMPOTENT. Retracting a notice that a second device has already retracted is the end state
-- the caller asked for, so it returns quietly instead of raising. Same for an id that is not
-- there at all — which is also what keeps this from being a probe for other hostels' row ids.

create or replace function public.ow_delete_announcement(p_announcement_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_hostel_id  uuid;
  v_deleted_at timestamptz;
begin
  select a.hostel_id, a.deleted_at
    into v_hostel_id, v_deleted_at
    from public.announcements a
   where a.id = p_announcement_id;

  -- No such notice: nothing to retract, and nothing to report about a row that may not be
  -- this caller's to know about.
  if not found then
    return;
  end if;

  if not app.owns_hostel(v_hostel_id) and not app.is_super_admin() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  if not app.is_super_admin() and not app.hostel_writable(v_hostel_id) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  if v_deleted_at is not null then
    return;
  end if;

  update public.announcements set deleted_at = now() where id = p_announcement_id;
end $$;

-- The blanket grant/revoke pair in schema.sql runs before this function exists, so both halves
-- are restated here. `anon` must not hold EXECUTE: a refused FUNCTION is how failure.dart tells
-- a dead session apart from a role refusal.
revoke execute on function public.ow_delete_announcement(uuid) from public, anon;
grant  execute on function public.ow_delete_announcement(uuid) to authenticated, service_role;
