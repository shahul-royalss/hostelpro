-- ============================================================================
--  HostelPro — db/rls-policies.sql
--  Row Level Security. Apply AFTER schema.sql.
--
--  Principles (CLAUDE_2.md §4):
--   • Tenant isolation: every row carries hostel_id; can_read_hostel() gates SELECT.
--   • Expired subscription ⇒ read-only: every INSERT/UPDATE/DELETE policy uses
--     can_write_hostel() which requires hostel.status='active' AND subscription
--     not expired. Super Admin bypasses.
--   • Students only ever see their own rows (+ roommates via st_my_roommates()).
--   • Account creation (auth) always goes through the service role in server
--     actions; the policies below still model who may write what.
-- ============================================================================

-- helper: drop every policy on a table so this file is re-runnable
create or replace function app.drop_policies(p_table text) returns void
language plpgsql as $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'public' and tablename = p_table loop
    execute format('drop policy if exists %I on public.%I', r.policyname, p_table);
  end loop;
end $$;

-- ───────────────────────────── users ─────────────────────────────
alter table public.users enable row level security;
select app.drop_policies('users');

-- The self branch carries an active/not-deleted predicate: without it a just-deactivated
-- account could still read (and via users_update edit) its own row through PostgREST until
-- its access token expired (checklist §37). Every other table already fails closed because
-- app.user_role() / app.user_hostel_id() only resolve for active accounts.
create policy users_select on public.users for select
  using (
    (id = auth.uid() and status = 'active' and deleted_at is null)
    or app.is_super_admin()
    or (app.user_role() in ('owner','manager','warden') and app.can_read_hostel(hostel_id))
  );

-- Super Admin creates owners; Owner creates manager/warden for hostels they own.
create policy users_insert on public.users for insert
  with check (
    app.is_super_admin()
    or (role in ('manager','warden') and app.owns_hostel(hostel_id) and app.hostel_writable(hostel_id))
    or (role = 'student' and app.has_role_in(hostel_id, 'warden') and app.hostel_writable(hostel_id))
  );

create policy users_update on public.users for update
  using (
    app.is_super_admin()
    or (id = auth.uid() and status = 'active' and deleted_at is null)
    or (role in ('manager','warden') and app.owns_hostel(hostel_id))
    or (role = 'student' and app.has_role_in(hostel_id, 'warden'))
  )
  with check (
    app.is_super_admin()
    or (id = auth.uid() and status = 'active' and deleted_at is null)
    or (role in ('manager','warden') and app.owns_hostel(hostel_id) and app.hostel_writable(hostel_id))
    or (role = 'student' and app.has_role_in(hostel_id, 'warden') and app.hostel_writable(hostel_id))
  );

-- no hard deletes from the app (§4.10)
create policy users_delete on public.users for delete using (app.is_service_role());

-- ───────────────────────────── hostels ─────────────────────────────
alter table public.hostels enable row level security;
select app.drop_policies('hostels');
create policy hostels_select on public.hostels for select using (app.can_read_hostel(id));
create policy hostels_insert on public.hostels for insert with check (app.is_super_admin());
create policy hostels_update on public.hostels for update using (app.is_super_admin()) with check (app.is_super_admin());
create policy hostels_delete on public.hostels for delete using (app.is_service_role());

-- ───────────────────────────── subscriptions ─────────────────────────────
alter table public.subscriptions enable row level security;
select app.drop_policies('subscriptions');
create policy subscriptions_select on public.subscriptions for select
  using (app.is_super_admin() or app.owns_hostel(hostel_id) or app.has_role_in(hostel_id, 'manager','warden'));
create policy subscriptions_write on public.subscriptions for all
  using (app.is_super_admin()) with check (app.is_super_admin());

-- ───────────────────────────── floors / rooms / beds ─────────────────────────────
alter table public.floors enable row level security;
select app.drop_policies('floors');
create policy floors_select on public.floors for select using (app.can_read_hostel(hostel_id));
create policy floors_write  on public.floors for all
  using (app.is_super_admin()) with check (app.is_super_admin());

alter table public.rooms enable row level security;
select app.drop_policies('rooms');
create policy rooms_select on public.rooms for select using (app.can_read_hostel(hostel_id));
create policy rooms_insert on public.rooms for insert with check (app.is_super_admin());
-- Warden may edit room_number / capacity (§4.2); floor/room counts are SA-only (enforced by no insert/delete)
create policy rooms_update on public.rooms for update
  using (app.is_super_admin() or app.has_role_in(hostel_id, 'warden'))
  with check (app.is_super_admin() or (app.has_role_in(hostel_id, 'warden') and app.hostel_writable(hostel_id)));
create policy rooms_delete on public.rooms for delete using (app.is_super_admin());

alter table public.beds enable row level security;
select app.drop_policies('beds');
create policy beds_select on public.beds for select using (app.can_read_hostel(hostel_id));
create policy beds_write on public.beds for all
  using (app.is_super_admin() or app.has_role_in(hostel_id, 'warden'))
  with check (app.is_super_admin() or (app.has_role_in(hostel_id, 'warden') and app.hostel_writable(hostel_id)));

-- ───────────────────────────── students ─────────────────────────────
alter table public.students enable row level security;
select app.drop_policies('students');
-- staff see all students of the hostel; a student sees ONLY their own row (§4.8)
create policy students_select on public.students for select
  using (app.is_staff_of(hostel_id) or user_id = auth.uid());
create policy students_insert on public.students for insert
  with check (app.has_role_in(hostel_id, 'warden') and app.hostel_writable(hostel_id));
create policy students_update on public.students for update
  using (app.has_role_in(hostel_id, 'warden','owner'))
  with check (app.has_role_in(hostel_id, 'warden','owner') and app.hostel_writable(hostel_id));
create policy students_delete on public.students for delete using (app.is_service_role());

-- ───────────────────────────── fee_payments ─────────────────────────────
alter table public.fee_payments enable row level security;
select app.drop_policies('fee_payments');
create policy fees_select on public.fee_payments for select
  using (app.is_staff_of(hostel_id) or student_id = app.current_student_id());
create policy fees_insert on public.fee_payments for insert
  with check (app.has_role_in(hostel_id, 'warden','manager','owner') and app.hostel_writable(hostel_id));
create policy fees_update on public.fee_payments for update
  using (app.has_role_in(hostel_id, 'warden','manager','owner'))
  with check (app.has_role_in(hostel_id, 'warden','manager','owner') and app.hostel_writable(hostel_id));
create policy fees_delete on public.fee_payments for delete using (app.is_service_role());

-- ───────────────────────────── complaints ─────────────────────────────
alter table public.complaints enable row level security;
select app.drop_policies('complaints');
create policy complaints_select on public.complaints for select
  using (app.is_staff_of(hostel_id) or student_id = app.current_student_id());
create policy complaints_insert on public.complaints for insert
  with check (
    student_id = app.current_student_id()
    and hostel_id = app.user_hostel_id()
    and app.hostel_writable(hostel_id)
  );
-- Owner + Warden move status / add note (§6.2, §6.4)
create policy complaints_update on public.complaints for update
  using (app.has_role_in(hostel_id, 'owner','warden'))
  with check (app.has_role_in(hostel_id, 'owner','warden') and app.hostel_writable(hostel_id));
create policy complaints_delete on public.complaints for delete using (app.is_service_role());

alter table public.complaint_events enable row level security;
select app.drop_policies('complaint_events');
create policy complaint_events_select on public.complaint_events for select
  using (
    app.is_staff_of(hostel_id)
    or exists (select 1 from public.complaints c where c.id = complaint_id and c.student_id = app.current_student_id())
  );
create policy complaint_events_insert on public.complaint_events for insert
  with check (app.is_service_role()); -- rows come from the trigger (security definer)

-- ───────────────────────────── expenses / revenues ─────────────────────────────
alter table public.expenses enable row level security;
select app.drop_policies('expenses');
create policy expenses_select on public.expenses for select
  using (app.has_role_in(hostel_id, 'owner','manager'));
create policy expenses_insert on public.expenses for insert
  with check (app.has_role_in(hostel_id, 'manager') and app.hostel_writable(hostel_id));
create policy expenses_update on public.expenses for update
  using (app.has_role_in(hostel_id, 'manager'))
  with check (app.has_role_in(hostel_id, 'manager') and app.hostel_writable(hostel_id));
create policy expenses_delete on public.expenses for delete using (app.is_service_role());

alter table public.revenues enable row level security;
select app.drop_policies('revenues');
create policy revenues_select on public.revenues for select
  using (app.has_role_in(hostel_id, 'owner','manager'));
create policy revenues_insert on public.revenues for insert
  with check (app.has_role_in(hostel_id, 'manager') and app.hostel_writable(hostel_id));
create policy revenues_update on public.revenues for update
  using (app.has_role_in(hostel_id, 'manager'))
  with check (app.has_role_in(hostel_id, 'manager') and app.hostel_writable(hostel_id));
create policy revenues_delete on public.revenues for delete using (app.is_service_role());

-- ───────────────────────────── announcements ─────────────────────────────
alter table public.announcements enable row level security;
select app.drop_policies('announcements');
-- audience filter (§4.6): owner/SA see all; manager sees all|manager; warden all|warden; students all|students
create policy announcements_select on public.announcements for select
  using (
    deleted_at is null and (
      app.is_super_admin()
      or app.owns_hostel(hostel_id)
      or (app.user_hostel_id() = hostel_id and (
            audience = 'all'
            or (audience = 'manager'  and app.user_role() = 'manager')
            or (audience = 'warden'   and app.user_role() = 'warden')
            or (audience = 'students' and app.user_role() = 'student')
      ))
    )
  );
create policy announcements_insert on public.announcements for insert
  with check (app.owns_hostel(hostel_id) and app.hostel_writable(hostel_id) and author_user_id = auth.uid());
create policy announcements_update on public.announcements for update
  using (app.owns_hostel(hostel_id))
  with check (app.owns_hostel(hostel_id) and app.hostel_writable(hostel_id));
create policy announcements_delete on public.announcements for delete using (app.is_service_role());

-- ───────────────────────────── tasks ─────────────────────────────
alter table public.tasks enable row level security;
select app.drop_policies('tasks');
create policy tasks_select on public.tasks for select
  using (deleted_at is null and (app.is_super_admin() or app.owns_hostel(hostel_id) or assigned_to = auth.uid()));
create policy tasks_insert on public.tasks for insert
  with check (app.owns_hostel(hostel_id) and app.hostel_writable(hostel_id) and created_by = auth.uid());
-- owner: anything; manager: status only (enforced by tasks_before_update trigger)
create policy tasks_update on public.tasks for update
  using (app.owns_hostel(hostel_id) or assigned_to = auth.uid())
  with check ((app.owns_hostel(hostel_id) or assigned_to = auth.uid()) and app.hostel_writable(hostel_id));
create policy tasks_delete on public.tasks for delete using (app.is_service_role());

-- ───────────────────────────── leaves ─────────────────────────────
alter table public.leaves enable row level security;
select app.drop_policies('leaves');
create policy leaves_select on public.leaves for select
  using (app.is_staff_of(hostel_id) or student_id = app.current_student_id());
create policy leaves_insert on public.leaves for insert
  with check (student_id = app.current_student_id() and hostel_id = app.user_hostel_id() and app.hostel_writable(hostel_id));
create policy leaves_update on public.leaves for update
  using (app.has_role_in(hostel_id, 'warden','owner'))
  with check (app.has_role_in(hostel_id, 'warden','owner') and app.hostel_writable(hostel_id));
create policy leaves_delete on public.leaves for delete using (app.is_service_role());

-- ───────────────────────────── visitors ─────────────────────────────
alter table public.visitors enable row level security;
select app.drop_policies('visitors');
create policy visitors_select on public.visitors for select using (app.is_staff_of(hostel_id));
create policy visitors_insert on public.visitors for insert
  with check (app.has_role_in(hostel_id, 'warden') and app.hostel_writable(hostel_id));
create policy visitors_update on public.visitors for update
  using (app.has_role_in(hostel_id, 'warden'))
  with check (app.has_role_in(hostel_id, 'warden') and app.hostel_writable(hostel_id));
create policy visitors_delete on public.visitors for delete using (app.is_service_role());

-- ───────────────────────────── menus ─────────────────────────────
alter table public.menus enable row level security;
select app.drop_policies('menus');
create policy menus_select on public.menus for select using (app.can_read_hostel(hostel_id));
create policy menus_write on public.menus for all
  using (app.has_role_in(hostel_id, 'manager'))
  with check (app.has_role_in(hostel_id, 'manager') and app.hostel_writable(hostel_id));

-- ───────────────────────────── notifications ─────────────────────────────
alter table public.notifications enable row level security;
select app.drop_policies('notifications');
create policy notifications_select on public.notifications for select using (user_id = auth.uid());
create policy notifications_update on public.notifications for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_insert on public.notifications for insert with check (app.is_service_role());
create policy notifications_delete on public.notifications for delete using (user_id = auth.uid());

-- ───────────────────────────── storage ─────────────────────────────
-- Buckets are private. Uploads + signed URLs are produced server-side with the
-- service role after `requireRole()` checks, so no anon/authenticated storage
-- policies are needed. (Keeping storage.objects RLS default-deny.)
