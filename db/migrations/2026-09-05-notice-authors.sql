-- ─────────────────────────────────────────────────────────────────────────────
-- A NOTICE CAN SAY WHO WROTE IT
--
-- public.announcements has carried author_user_id since it was created, and no reader has ever
-- been able to resolve it to a name. A resident cannot read public.users AT ALL — hard rule
-- §4.8, and the reason st_hostel_contacts() exists to hand back the three staff fields they are
-- allowed to have — so `select ... users!inner(full_name)` from the app is refused by RLS rather
-- than merely empty. The notice list therefore showed a title, a body and a date, and the
-- product owner is right that it reads as a system message from nobody.
--
-- ── WHY A FUNCTION AND NOT A JOIN, A VIEW, OR A COLUMN ────────────────────────────────────────
--
--   * A JOIN is what RLS is there to refuse. Loosening the users policy so residents could read
--     staff rows would hand every resident the whole staff table to get one display name.
--   * A VIEW inherits the querying user's permissions, so a plain view over users is refused for
--     exactly the same reason. `security_invoker = off` would work and is the same thing as this
--     function with less control over the gate.
--   * DENORMALISING the name onto announcements — an author_name column — is the tempting cheap
--     option and it rots: rename a warden and every notice they ever posted keeps the old name.
--
-- So: one SECURITY DEFINER function, returning the smallest useful row, gated on
-- app.can_read_hostel() — the same predicate the announcements select policy already trusts, so
-- this cannot widen who sees what. If you may read the hostel's notices, you may learn the names
-- attached to them, and nothing else about those people.
--
-- WHAT IT DELIBERATELY DOES NOT RETURN: no phone, no email, no id proof, no hostel_id. A name
-- and a role. The role is there so the app can print "Warden" under "Xeyrion" — a resident
-- seeing who in the building said something is the point of the change.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.notice_authors(p_hostel_id uuid)
returns table (user_id uuid, full_name text, role public.user_role)
language sql
stable
security definer
set search_path = public
as $$
  select u.id, u.full_name, u.role
    from public.users u
   where app.can_read_hostel(p_hostel_id)
     and u.id in (
           select a.author_user_id
             from public.announcements a
            where a.hostel_id = p_hostel_id
              and a.deleted_at is null
              and a.author_user_id is not null
         );
$$;

comment on function public.notice_authors(uuid) is
  'Display name and role for every author of a hostel''s live notices. Gated on '
  'app.can_read_hostel(), the same predicate announcements_select uses, so it cannot reveal a '
  'notice author to anyone who could not already read the notice. Returns no contact details: '
  'residents cannot read public.users directly (§4.8) and this is not a way around that.';

revoke all on function public.notice_authors(uuid) from public;
-- AND FROM anon SPECIFICALLY. Supabase grants EXECUTE on a newly created public function to the
-- anon role by default, and `revoke ... from public` does not touch a grant held by a named role
-- — so the line above leaves anon holding it, which the database linter flags and which
-- st_hostel_contacts (the same shape of read) does not do. The gate inside already returns zero
-- rows to a caller with no auth.uid(), verified against production, so this is closing the door
-- rather than plugging a leak.
revoke execute on function public.notice_authors(uuid) from anon;
grant execute on function public.notice_authors(uuid) to authenticated;

-- ═══ AFTER APPLYING ═══
-- As a resident of the hostel, this returns the staff who have posted notices:
--
--   select * from public.notice_authors('<their hostel id>');
--
-- As anyone else, it returns zero rows rather than raising — the gate is a WHERE clause, so a
-- caller who cannot read the hostel simply learns nothing.
