-- ============================================================================
--  2026-08-31 — hoist_rls_predicates_into_initplans
--  Applied to nimxvgzscbanhtvgnjll as migration `hoist_rls_predicates_into_initplans`.
--
--  WHY. app.is_staff_of(hostel_id), app.has_role_in(hostel_id, ...) and
--  app.can_read_hostel(hostel_id) are SECURITY DEFINER SQL functions, so the planner
--  cannot inline them; and they take the ROW's hostel_id, so it cannot hoist them into
--  an InitPlan either. Result: three to four nested SECURITY DEFINER calls PER ROW.
--  Measured here, after the earlier `(select auth.uid())` and beds-index fixes:
--      select count(*) from public.beds   as warden harani@gmail.com
--      = 328.6 ms, 2136 shared buffers, seq scan of a 207-row table.
--
--  WHAT. Every per-row dependency inside those helpers has one of two shapes:
--      <no-arg stable fn>() = hostel_id   ->  hostel_id = (select fn())   [InitPlan]
--      app.owns_hostel(hostel_id)         ->  hostel_id in (select app.owned_hostel_ids())
--  so each policy is rewritten as the same boolean over expressions the planner
--  evaluates ONCE per statement instead of once per row.
--
--  The helper functions themselves are NOT changed and NOT dropped: plpgsql RPCs in
--  schema.sql call them once per statement, where they were never the problem.
--
--  THIS IS THE SECURITY BOUNDARY. The rewrite is truth-table identical branch for
--  branch; the reasoning is recorded above each group. It was verified after apply by
--  (a) re-counting every table for all 8 real accounts and (b) evaluating the old
--  helper expression and the new inline expression for every row of every table for
--  every account and requiring them equal.
-- ============================================================================

-- ── the one new helper ──────────────────────────────────────────────────────
-- app.owns_hostel(h) is
--     exists (select 1 from hostels where id = h and owner_user_id = auth.uid())
--     and coalesce(app.user_role() = 'owner', false)
-- Turned inside out that is a SET of hostel ids which does not depend on the row, so
-- `h in (select app.owned_hostel_ids())` is an uncorrelated SubLink the planner hashes
-- once. Truth table: user_role() null or <> 'owner' -> empty set -> false, matching the
-- coalesce; otherwise membership is exactly the EXISTS. (h null yields NULL rather than
-- false, which RLS treats identically to false, and no policy negates it.)
--
-- SECURITY DEFINER for the same reason app.owns_hostel is: it reads public.hostels,
-- which is itself under RLS (hostels_select), and the ownership test must not be gated
-- by the policy it exists to evaluate. It returns only hostels the CALLER owns, so it
-- discloses nothing the caller could not already read.
create or replace function app.owned_hostel_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select h.id from public.hostels h
   where (select app.user_role()) = 'owner'
     and h.owner_user_id = (select auth.uid())
$$;

revoke all on function app.owned_hostel_ids() from public;
grant execute on function app.owned_hostel_ids() to authenticated, anon, service_role;

comment on function app.owned_hostel_ids() is
  'Hostel ids the caller owns. The set form of app.owns_hostel() so an RLS predicate can hoist it into a single InitPlan: h in (select app.owned_hostel_ids()) <=> app.owns_hostel(h).';


-- ── users ───────────────────────────────────────────────────────────────────
-- can_read_hostel(c) = is_super_admin() or owns_hostel(c) or user_hostel_id() = c.
-- Its leading is_super_admin() is dropped inside branches 3 and 4 because branch 2 of
-- this same OR already returns true for a super admin (is_super_admin() is never NULL:
-- both of its own branches are coalesce()d).
drop policy if exists users_select on public.users;
create policy users_select on public.users for select
  using (
    (id = (select auth.uid()) and status = 'active' and deleted_at is null)
    or (select app.is_super_admin())
    or ((select app.user_role()) in ('owner','warden')
        and (hostel_id in (select app.owned_hostel_ids())
             or hostel_id = (select app.user_hostel_id())))
    -- the Manager needs staff for tasks/announcements, but must not enumerate residents
    or ((select app.user_role()) = 'manager'
        and (hostel_id in (select app.owned_hostel_ids())
             or hostel_id = (select app.user_hostel_id()))
        and role in ('owner','manager','warden'))
  );

-- has_role_in(c,'warden') = is_super_admin() or (user_hostel_id() = c and user_role() = 'warden').
-- 'owner' is not in the role list so has_role_in's owner branch is dead, and its
-- `user_role() <> 'owner'` guard is implied by user_role() = 'warden'.
drop policy if exists users_insert on public.users;
create policy users_insert on public.users for insert
  with check (
    (select app.is_super_admin())
    or (role in ('manager','warden')
        and hostel_id in (select app.owned_hostel_ids())
        and app.hostel_writable(hostel_id))
    or (role = 'student'
        and hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'
        and app.hostel_writable(hostel_id))
  );

drop policy if exists users_update on public.users;
create policy users_update on public.users for update
  using (
    (select app.is_super_admin())
    or (id = (select auth.uid()) and status = 'active' and deleted_at is null)
    or (role in ('manager','warden') and hostel_id in (select app.owned_hostel_ids()))
    or (role = 'student'
        and hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    (select app.is_super_admin())
    or (id = (select auth.uid()) and status = 'active' and deleted_at is null)
    or (role in ('manager','warden')
        and hostel_id in (select app.owned_hostel_ids())
        and app.hostel_writable(hostel_id))
    or (role = 'student'
        and hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'
        and app.hostel_writable(hostel_id))
  );


-- ── hostels / floors / rooms ────────────────────────────────────────────────
drop policy if exists hostels_select on public.hostels;
create policy hostels_select on public.hostels for select
  using (
    (select app.is_super_admin())
    or id in (select app.owned_hostel_ids())
    or id = (select app.user_hostel_id())
  );

drop policy if exists floors_select on public.floors;
create policy floors_select on public.floors for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or hostel_id = (select app.user_hostel_id())
  );

-- FOR ALL, so this USING is evaluated on every SELECT of public.floors too.
drop policy if exists floors_write on public.floors;
create policy floors_write on public.floors for all
  using ((select app.is_super_admin()))
  with check ((select app.is_super_admin()));

drop policy if exists rooms_select on public.rooms;
create policy rooms_select on public.rooms for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or hostel_id = (select app.user_hostel_id())
  );

drop policy if exists rooms_update on public.rooms;
create policy rooms_update on public.rooms for update
  using (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'
        and app.hostel_writable(hostel_id))
  );


-- ── beds ────────────────────────────────────────────────────────────────────
-- is_staff_of(c) = is_super_admin() or owns_hostel(c)
--                  or (user_hostel_id() = c and user_role() in ('manager','warden')).
-- The student's own-room branch is carried over unchanged.
drop policy if exists beds_select on public.beds;
create policy beds_select on public.beds for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id())
        and (select app.user_role()) in ('manager','warden'))
    or room_id = (select s.room_id from public.students s
                   where s.user_id = (select auth.uid()) and s.status <> 'vacated' limit 1)
  );

-- FOR ALL, so this USING is evaluated on every SELECT of public.beds too.
drop policy if exists beds_write on public.beds;
create policy beds_write on public.beds for all
  using (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'
        and app.hostel_writable(hostel_id))
  );


-- ── students ────────────────────────────────────────────────────────────────
-- has_role_in(c,'warden','owner'): 'owner' IS in the list, so that branch becomes
-- owns_hostel(c) -> set membership. The remaining branch is warden-only, because
-- has_role_in's third branch requires user_role() <> 'owner'.
drop policy if exists students_select on public.students;
create policy students_select on public.students for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
    or user_id = (select auth.uid())
  );

drop policy if exists students_insert on public.students;
create policy students_insert on public.students for insert
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );

drop policy if exists students_update on public.students;
create policy students_update on public.students for update
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    ((select app.is_super_admin())
     or hostel_id in (select app.owned_hostel_ids())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );


-- ── fee_payments ────────────────────────────────────────────────────────────
drop policy if exists fees_select on public.fee_payments;
create policy fees_select on public.fee_payments for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
    or student_id = (select app.current_student_id())
  );

drop policy if exists fees_insert on public.fee_payments;
create policy fees_insert on public.fee_payments for insert
  with check (
    ((select app.is_super_admin())
     or hostel_id in (select app.owned_hostel_ids())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );

drop policy if exists fees_update on public.fee_payments;
create policy fees_update on public.fee_payments for update
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    ((select app.is_super_admin())
     or hostel_id in (select app.owned_hostel_ids())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );


-- ── payment_intents ─────────────────────────────────────────────────────────
drop policy if exists payment_intents_select on public.payment_intents;
create policy payment_intents_select on public.payment_intents for select
  using (
    student_id = (select app.current_student_id())
    or (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  );


-- ── complaints / complaint_events ───────────────────────────────────────────
drop policy if exists complaints_select on public.complaints;
create policy complaints_select on public.complaints for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
    or student_id = (select app.current_student_id())
  );

drop policy if exists complaints_insert on public.complaints;
create policy complaints_insert on public.complaints for insert
  with check (
    student_id = (select app.current_student_id())
    and hostel_id = (select app.user_hostel_id())
    and app.hostel_writable(hostel_id)
  );

drop policy if exists complaints_update on public.complaints;
create policy complaints_update on public.complaints for update
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    ((select app.is_super_admin())
     or hostel_id in (select app.owned_hostel_ids())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );

drop policy if exists complaint_events_select on public.complaint_events;
create policy complaint_events_select on public.complaint_events for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
    or exists (select 1 from public.complaints c
                where c.id = complaint_events.complaint_id
                  and c.student_id = (select app.current_student_id()))
  );


-- ── leaves ──────────────────────────────────────────────────────────────────
drop policy if exists leaves_select on public.leaves;
create policy leaves_select on public.leaves for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
    or student_id = (select app.current_student_id())
  );

drop policy if exists leaves_insert on public.leaves;
create policy leaves_insert on public.leaves for insert
  with check (
    student_id = (select app.current_student_id())
    and hostel_id = (select app.user_hostel_id())
    and app.hostel_writable(hostel_id)
  );

drop policy if exists leaves_update on public.leaves;
create policy leaves_update on public.leaves for update
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    ((select app.is_super_admin())
     or hostel_id in (select app.owned_hostel_ids())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );


-- ── visitors ────────────────────────────────────────────────────────────────
drop policy if exists visitors_select on public.visitors;
create policy visitors_select on public.visitors for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  );

drop policy if exists visitors_insert on public.visitors;
create policy visitors_insert on public.visitors for insert
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );

drop policy if exists visitors_update on public.visitors;
create policy visitors_update on public.visitors for update
  using (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden')
  )
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'warden'))
    and app.hostel_writable(hostel_id)
  );


-- ── expenses / revenues (owner reads, manager writes) ───────────────────────
drop policy if exists expenses_select on public.expenses;
create policy expenses_select on public.expenses for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager')
  );

drop policy if exists expenses_insert on public.expenses;
create policy expenses_insert on public.expenses for insert
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager'))
    and app.hostel_writable(hostel_id)
  );

drop policy if exists expenses_update on public.expenses;
create policy expenses_update on public.expenses for update
  using (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager')
  )
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager'))
    and app.hostel_writable(hostel_id)
  );

drop policy if exists revenues_select on public.revenues;
create policy revenues_select on public.revenues for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager')
  );

drop policy if exists revenues_insert on public.revenues;
create policy revenues_insert on public.revenues for insert
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager'))
    and app.hostel_writable(hostel_id)
  );

drop policy if exists revenues_update on public.revenues;
create policy revenues_update on public.revenues for update
  using (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager')
  )
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager'))
    and app.hostel_writable(hostel_id)
  );


-- ── menus ───────────────────────────────────────────────────────────────────
drop policy if exists menus_select on public.menus;
create policy menus_select on public.menus for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or hostel_id = (select app.user_hostel_id())
  );

-- FOR ALL, so this USING is evaluated on every SELECT of public.menus too.
drop policy if exists menus_write on public.menus;
create policy menus_write on public.menus for all
  using (
    (select app.is_super_admin())
    or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager')
  )
  with check (
    ((select app.is_super_admin())
     or (hostel_id = (select app.user_hostel_id()) and (select app.user_role()) = 'manager'))
    and app.hostel_writable(hostel_id)
  );


-- ── announcements ───────────────────────────────────────────────────────────
drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select
  using (
    deleted_at is null
    and ((select app.is_super_admin())
         or hostel_id in (select app.owned_hostel_ids())
         or (hostel_id = (select app.user_hostel_id())
             and (audience = 'all'
                  or (audience = 'manager'  and (select app.user_role()) = 'manager')
                  or (audience = 'warden'   and (select app.user_role()) = 'warden')
                  or (audience = 'students' and (select app.user_role()) = 'student'))))
  );

drop policy if exists announcements_insert on public.announcements;
create policy announcements_insert on public.announcements for insert
  with check (
    hostel_id in (select app.owned_hostel_ids())
    and app.hostel_writable(hostel_id)
    and author_user_id = (select auth.uid())
  );

drop policy if exists announcements_update on public.announcements;
create policy announcements_update on public.announcements for update
  using (hostel_id in (select app.owned_hostel_ids()))
  with check (hostel_id in (select app.owned_hostel_ids()) and app.hostel_writable(hostel_id));


-- ── tasks ───────────────────────────────────────────────────────────────────
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks for select
  using (
    deleted_at is null
    and ((select app.is_super_admin())
         or hostel_id in (select app.owned_hostel_ids())
         or assigned_to = (select auth.uid()))
  );

drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks for insert
  with check (
    hostel_id in (select app.owned_hostel_ids())
    and app.hostel_writable(hostel_id)
    and created_by = (select auth.uid())
  );

drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks for update
  using (hostel_id in (select app.owned_hostel_ids()) or assigned_to = (select auth.uid()))
  with check (
    (hostel_id in (select app.owned_hostel_ids()) or assigned_to = (select auth.uid()))
    and app.hostel_writable(hostel_id)
  );


-- ── subscriptions ───────────────────────────────────────────────────────────
-- is_super_admin() or owns_hostel(c) or has_role_in(c,'manager','warden'); the role
-- list has no 'owner', so has_role_in contributes only the staff branch.
drop policy if exists subscriptions_select on public.subscriptions;
create policy subscriptions_select on public.subscriptions for select
  using (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (hostel_id = (select app.user_hostel_id())
        and (select app.user_role()) in ('manager','warden'))
  );

-- FOR ALL, so this USING is evaluated on every SELECT of public.subscriptions too.
drop policy if exists subscriptions_write on public.subscriptions;
create policy subscriptions_write on public.subscriptions for all
  using ((select app.is_super_admin()))
  with check ((select app.is_super_admin()));


-- ── audit_log / security_alerts ─────────────────────────────────────────────
drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select on public.audit_log for select
  using (
    (select app.is_super_admin())
    or (hostel_id is not null and hostel_id in (select app.owned_hostel_ids()))
  );

drop policy if exists security_alerts_select on public.security_alerts;
create policy security_alerts_select on public.security_alerts for select
  using (
    (select app.is_super_admin())
    or (hostel_id is not null and hostel_id in (select app.owned_hostel_ids()))
  );
