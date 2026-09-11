-- ─────────────────────────────────────────────────────────────────────────────
-- TASKS GO TO MANAGERS; NOTICES STOP GOING TO THEM
--
-- The product owner: "owner can send tasks separately to manager, not as notice... notice is
-- different and remove notice section for manager."
--
-- ── NOTICES ─────────────────────────────────────────────────────────────────────────────────
--
-- A notice is the owner talking to the people who live and work in the building — the wardens
-- and the residents. A manager's instructions arrive as TASKS, which have a due date, a status,
-- and a person who is answerable for them. Sending the manager both meant the same instruction
-- could arrive as either, and the notice version had no way to be marked done.
--
-- So, three changes that say one thing:
--
--   announcements_select   an audience of 'all' now means wardens and residents; the 'manager'
--                          audience is readable by the owner (who wrote it) and nobody else.
--   announcements_insert   refuses a NEW notice addressed to 'manager'. The enum value stays,
--                          because old rows carry it and dropping an enum label means
--                          rewriting every row that uses it.
--   announcements_after_insert  fans a notice out to wardens and residents only.
--
-- ── TASK NOTIFICATIONS ──────────────────────────────────────────────────────────────────────
--
-- With up to five managers per PG (2026-09-12-five-staff-per-role.sql), "marked done by manager"
-- no longer says who. It names them. The owner's link points at the owner's own task list, which
-- this release adds, instead of the staff screen. Reassigning a task tells the new assignee, and
-- the owner is no longer notified about a status change they made themselves.
--
-- app.tasks_assignee_guard already refuses a task addressed to anyone but an active manager of
-- the same hostel, and app.tasks_before_update already stops a manager editing anything but the
-- status. Neither changes.
-- ─────────────────────────────────────────────────────────────────────────────

drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select
using (
  deleted_at is null and (
    (select app.is_super_admin())
    or hostel_id in (select app.owned_hostel_ids())
    or (
      hostel_id = (select app.user_hostel_id()) and (
           (audience = 'all'      and (select app.user_role()) in ('warden', 'student'))
        or (audience = 'warden'   and (select app.user_role()) = 'warden')
        or (audience = 'students' and (select app.user_role()) = 'student')
      )
    )
  )
);

drop policy if exists announcements_insert on public.announcements;
create policy announcements_insert on public.announcements for insert
with check (
  hostel_id in (select app.owned_hostel_ids())
  and app.hostel_writable(hostel_id)
  and author_user_id = (select auth.uid())
  and audience <> 'manager'
);

create or replace function app.announcements_after_insert() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
begin
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select new.hostel_id, u.id, 'announcement', new.title, left(new.body, 140),
         case u.role when 'warden' then '/warden/notices' else '/student/notices' end
    from public.users u
   where u.hostel_id = new.hostel_id
     and u.status = 'active'
     and u.deleted_at is null
     and u.id <> new.author_user_id
     and (
          (new.audience = 'all'      and u.role in ('warden', 'student'))
       or (new.audience = 'warden'   and u.role = 'warden')
       or (new.audience = 'students' and u.role = 'student')
     );
  return new;
end $function$;

create or replace function app.tasks_after_change() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_name text;
begin
  if tg_op = 'INSERT' then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (new.hostel_id, new.assigned_to, 'task', 'New task: ' || new.title,
            coalesce('Due ' || to_char(new.due_date, 'DD Mon'), 'From the owner'), '/manager/tasks');
    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (new.hostel_id, new.assigned_to, 'task', 'New task: ' || new.title,
            coalesce('Due ' || to_char(new.due_date, 'DD Mon'), 'From the owner'), '/manager/tasks');
  end if;

  if new.status is distinct from old.status
     and new.created_by is not null
     and auth.uid() is distinct from new.created_by then
    select full_name into v_name from public.users where id = new.assigned_to;
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (new.hostel_id, new.created_by, 'task',
            'Task ' || replace(new.status::text, '_', ' '),
            '"' || new.title || '" marked ' || replace(new.status::text, '_', ' ')
              || ' by ' || coalesce(v_name, 'the manager') || '.',
            '/owner/tasks');
  end if;
  return new;
end $function$;
