-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ONE WARDEN OR MANAGER, SEVERAL PGs
--
-- An owner with two or more PGs can give a warden or manager access to one PG or several. A
-- warden or manager with several picks the PG they are working in from a "Switch PG" control.
--
-- ── THE DESIGN: ONE ACTIVE PG AT A TIME ─────────────────────────────────────────────────────
--
-- public.users.hostel_id keeps its meaning for staff: the ONE PG the account is working in right
-- now. Every tenant policy (36 of them, all through app.user_hostel_id()) and every Edge Function
-- that reads the column keeps scoping to exactly one PG. What is new is the list of PGs each
-- warden or manager is ALLOWED into, public.staff_hostel_access, and a way to move
-- users.hostel_id, only ever to a PG on that list.
--
-- Why not teach the 36 policies about a set of PGs: all of them would change at once, in the one
-- place where a mistake is a cross-tenant leak, and the live Android app (v6, no switcher) would
-- be shown several PGs' residents mixed together on screens built for one. With an active PG, v6
-- keeps working on whichever PG the account last switched to, and a warden with one PG (every
-- warden today) sees no difference at all. Owners and residents are untouched: only a manager or
-- warden can ever switch.
--
-- users.hostel_id is one column shared by every device the account is signed in on, so switching
-- on the phone switches the web too. That is the intended reading: "the PG I am working in".
-- Deactivating an account (users.status) still takes away every PG at once. Taking away ONE PG is
-- owner_set_staff_hostels.
--
-- ── WHAT KEEPS IT SAFE ──────────────────────────────────────────────────────────────────────
--
-- 1. app.user_hostel_id() returns a warden's or manager's hostel_id only while an access row
--    backs it. Removing a PG takes effect in every policy on the next request, even if
--    something left users.hostel_id pointing at it; the account then sees no PG, never the wrong one.
-- 2. The rule for moving users.hostel_id lives in app.users_update_guard, the trigger every UPDATE
--    of public.users passes through, not in the RPC. A PATCH sent straight to /rest/v1/users is
--    held to exactly the same rule as staff_switch_hostel. No GUC and no session flag: a bypass
--    that exists for the RPC exists for anybody who learns to set it.
-- 3. staff_hostel_access has no client write path. Rows are written by the RPCs below (SECURITY
--    DEFINER), by the trigger that gives a new account its home PG, or by the service role, and
--    a trigger checks every row, the service role's included: the account must be a manager or
--    warden, the PG must belong to the same owner as the account's current PG, a read-only or
--    suspended PG takes nobody new, and the per-PG staff limit must hold.
--
-- ── THE STAFF LIMIT NOW COUNTS ACCESS, NOT PRESENCE ─────────────────────────────────────────
--
-- 5 active wardens and 5 active managers per PG (2026-09-12-five-staff-per-role.sql). Counting
-- users.hostel_id would let an owner go past five by switching people in and out, and would refuse
-- a legitimate switch into a PG where five colleagues happen to be working. So the count is of
-- active staff WITH ACCESS to the PG. A switch changes nobody's access and is never counted. A
-- grant, a new account and a reactivation are counted, a reactivation against every PG on the
-- account's list. All of them take the advisory lock enforce_role_limits already takes
-- (hostel:role), so every path that can add a sixth serialises on the same key.
--
-- ── ORDER INSIDE THIS TRANSACTION ───────────────────────────────────────────────────────────
--
-- public.users is locked first (SHARE ROW EXCLUSIVE: reads carry on, writes wait for COMMIT).
-- Then every existing warden and manager gets an access row for the PG they are in, and only
-- then does app.user_hostel_id() start asking for one. Without the lock, a warden created by
-- owner-create-staff between the backfill's snapshot and COMMIT would have no row and would be
-- shut out of their own PG the moment this commits. With it, that insert waits, then fires the
-- new home-PG trigger.
--
-- ── ROUTINES THAT FOUND STAFF BY users.hostel_id ────────────────────────────────────────────
--
-- A warden with access to PG B who is working in PG A must still hear about B's complaints,
-- leaves and notices, still appear on B's residents' contact card, and still be assignable B's
-- tasks. Every routine that matched STAFF by users.hostel_id now matches them through
-- staff_hostel_access. Residents are still matched by users.hostel_id. Found on the live database
-- (2026-09-30) with
--   select oid::regprocedure from pg_proc where prosrc ~* 'hostel_id' and prosrc ~* 'public\.users'
-- and a second pass for prosrc ~* '''(warden|manager)''':
--
--   public.st_hostel_contacts         the resident's warden and manager
--   app.complaints_after_change       new-complaint notice to the wardens
--   app.leaves_after_change           new-leave notice to the wardens
--   app.announcements_after_insert    notice fan-out to wardens (residents unchanged)
--   app.tasks_assignee_guard          "this hostel's active manager"
--   public.request_account_deletion   a resident's request goes to the hostel's wardens
--
-- Looked at and left alone: sa_cancel_subscription and sa_renew_subscription notify the owner
-- only, so they have no staff fan-out, and neither do sa_create_hostel_with_subscription (the
-- owner's own row) or send_rent_reminders (residents). students_identity_guard and
-- wd_register_student are about residents. accept_legal_terms, the two GoTrue hooks
-- (password_verification_attempt, mfa_verification_attempt) and request_account_deletion's
-- lookup of the requester's own PG record the PG the person is working in, which is right.
-- notice_authors finds people by what they wrote, not where they work. Every other staff check
-- (has_role_in, is_staff_of, can_edit_layout, the wd_* RPCs, rpc_recent_payments) goes through
-- app.user_hostel_id() and is scoped to the active PG by design. No view or cron job reads
-- users.hostel_id.
--
-- hostels_select is NOT widened. A warden reads the names and addresses of their other PGs
-- through my_staff_hostels() only, so the Razorpay and payout columns on hostels stay out of reach.
--
-- Each redefinition below is copied from pg_get_functiondef() on the live database (2026-09-30),
-- not from db/schema.sql or db/rls-policies.sql, which are behind it. The .down.sql file restores
-- exactly that text, and the .test.sql file exercises all of this inside a rolled-back transaction.
--
-- ── THE CLIENT CONTRACT ─────────────────────────────────────────────────────────────────────
--
--   my_staff_hostels()                         the caller's PGs by name; is_active marks the current one
--   staff_switch_hostel(hostel)                -> hostel. P0001 carries a sentence to show.
--   owner_set_staff_hostels(user, hostels[])   replace one staff member's list -> (hostel, is_active)
--   owner_hostel_staff(hostel)                 the owner's staff screen for one PG
--   hostel_staff_names(hostel)                 names for task lines
--
-- The grants revoke from anon BY NAME. Supabase grants EXECUTE on new public functions to anon
-- explicitly, and a revoke from PUBLIC does not reach it (2026-09-07-lock-payout-rpc.sql).
-- ═══════════════════════════════════════════════════════════════════════════════════════════

begin;

-- NEVER WAIT FOREVER ON A LIVE DATABASE. This runs while real testers use the app. If a long app
-- transaction holds a lock this migration needs (users, or hostels for the foreign key), waiting
-- without a limit would queue every later query behind this one and freeze the app. After 10 s
-- the migration aborts instead, applies nothing, and can simply be run again.
set local lock_timeout = '10s';

-- See "ORDER INSIDE THIS TRANSACTION" above. users and hostels are taken in ONE statement, so the
-- migration never holds one while waiting for the other: an app transaction holding a hostels row
-- lock and then writing users cannot deadlock against it.
lock table public.users, public.hostels in share row exclusive mode;


-- ═══ 1. THE ACCESS LIST ═════════════════════════════════════════════════════════════════════

create table public.staff_hostel_access (
  user_id    uuid        not null references public.users(id)   on delete cascade,
  hostel_id  uuid        not null references public.hostels(id) on delete cascade,
  granted_by uuid        null     references public.users(id)   on delete set null,
  granted_at timestamptz not null default now(),
  constraint staff_hostel_access_pkey primary key (user_id, hostel_id)
);

-- The primary key answers "may this account work in this PG" (app.user_hostel_id() asks it on
-- every staff request). This answers "who may work in this PG": the staff limit, the contact
-- card and the notification fan-outs.
create index staff_hostel_access_hostel_idx on public.staff_hostel_access (hostel_id);

comment on table public.staff_hostel_access is
  'The PGs each manager or warden may work in. users.hostel_id is the one they are working in now '
  'and must be one of these (app.user_hostel_id() returns NULL otherwise). No client writes: rows '
  'come from owner_set_staff_hostels, the home-PG trigger on users, or the service role, and '
  'app.staff_hostel_access_guard checks every one. db/migrations/2026-09-30-multi-pg-staff-access.sql.';

alter table public.staff_hostel_access enable row level security;

-- The staff member, the owner of the PG and the Super Admin. owned_hostel_ids() and
-- is_super_admin() both carry the second factor.
create policy staff_hostel_access_select on public.staff_hostel_access
  for select using (
       user_id = (select auth.uid())
    or hostel_id in (select app.owned_hostel_ids())
    or (select app.is_super_admin())
  );

-- Not only "no write policy". Supabase grants anon and authenticated ALL on a new public table,
-- and ALL includes TRUNCATE, which row-level security never sees. So everything goes, and SELECT
-- comes back for signed-in callers, whom the policy above then narrows.
revoke all on public.staff_hostel_access from anon, authenticated;
grant select on public.staff_hostel_access to authenticated;


-- ═══ 2. BACKFILL: EVERY WARDEN AND MANAGER KEEPS THE PG THEY ARE IN ═══════════════════════════
--
-- Active and inactive alike. A deactivated warden who is reactivated comes back to the PG they
-- left, and the reactivation is counted against it. granted_by / granted_at are the account's
-- creator and creation time: the owner who put them in that PG, and when.
--
-- This runs BEFORE the guard in section 4 exists. Every row copies a pairing enforce_role_limits
-- already admitted, and a legacy row the new check disliked must not be able to fail this
-- migration halfway through a deploy.

insert into public.staff_hostel_access (user_id, hostel_id, granted_by, granted_at)
select u.id, u.hostel_id, u.created_by, u.created_at
  from public.users u
 where u.role in ('manager', 'warden')
   and u.hostel_id is not null
on conflict on constraint staff_hostel_access_pkey do nothing;


-- ═══ 3. A NEW WARDEN OR MANAGER IS GIVEN THEIR HOME PG ═══════════════════════════════════════
--
-- Both creation paths (supabase/functions/owner-create-staff and the website's server action)
-- insert the users row with the service role, and so does the owner-create-staff that is deployed
-- today, which knows nothing about this table. Doing it here means every one of them produces an
-- account that can open its own PG, with no ordering to get right in three places.

create or replace function app.staff_grant_home_hostel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role in ('manager', 'warden') and new.hostel_id is not null then
    insert into public.staff_hostel_access (user_id, hostel_id, granted_by)
    values (new.id, new.hostel_id, new.created_by)
    on conflict on constraint staff_hostel_access_pkey do nothing;
  end if;
  return null;
end $$;

-- AFTER, so the users row exists for the access row's foreign key and for the guard to read.
-- INSERT only: a Super Admin or service-role move of an existing account to a PG it has no access
-- to is deliberately NOT turned into a grant. It fails closed (app.user_hostel_id() is NULL for
-- that account) until an owner gives access.
drop trigger if exists users_grant_home_hostel on public.users;
create trigger users_grant_home_hostel after insert on public.users
  for each row execute function app.staff_grant_home_hostel();


-- ═══ 4. EVERY ACCESS ROW IS CHECKED, WHOEVER WRITES IT ══════════════════════════════════════
--
-- A trigger, not a check in the RPC, so the service role (owner-create-staff with hostelIds, a
-- repair in the SQL editor) is held to the same four rules as an owner:
--
--   · the account is a manager or warden.
--   · the PG has the same owner as the PG the account is in now. Without this, one owner could
--     be handed another owner's PG through a service-role path, and app.user_hostel_id() would
--     then read that PG's residents for them.
--   · a PG that is read-only (subscription expired) or suspended takes nobody new, the rule the
--     users_insert and users_update policies (app.hostel_writable) already apply to a new or
--     reactivated account. owner_set_staff_hostels is SECURITY DEFINER and owner-create-staff
--     checks only the first PG, so neither would meet those policies here. Taking a PG away is
--     a DELETE and is never checked.
--   · the PG stays within 5 active of the role WITH ACCESS. Skipped while the account itself is
--     inactive or deleted: it does not add an active member, and enforce_role_limits counts every
--     PG on its list the moment it is reactivated.
--
-- The users row is read FOR SHARE. That blocks a concurrent reactivation of the same account
-- (FOR NO KEY UPDATE), so a grant made "while inactive" cannot land beside a reactivation that
-- never saw it and leave six active in the PG.

create or replace function app.staff_hostel_access_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_user  public.users%rowtype;
  v_count int;
begin
  select * into v_user from public.users where id = new.user_id for share;
  if not found or v_user.role not in ('manager', 'warden') then
    raise exception 'Only wardens and managers can be given access to a PG.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
      from public.hostels target
      join public.hostels home on home.owner_user_id = target.owner_user_id
     where target.id = new.hostel_id
       and home.id = v_user.hostel_id
  ) then
    raise exception 'You can only give access to your own PGs.' using errcode = 'P0001';
  end if;

  -- The home row (the PG the account is in, written by the trigger on users at creation) is
  -- skipped: that insert is already checked, by users_insert for an owner and by assertWritable
  -- in owner-create-staff and the website, and a Super Admin may create staff in any PG.
  if new.hostel_id is distinct from v_user.hostel_id and not app.hostel_writable(new.hostel_id) then
    raise exception 'You cannot give access to a PG that is read-only or suspended.' using errcode = 'P0001';
  end if;

  if v_user.status = 'active' and v_user.deleted_at is null then
    -- The key enforce_role_limits takes, so a grant, a new account and a reactivation that would
    -- each be the fifth cannot all count four at once.
    perform pg_advisory_xact_lock(hashtextextended(new.hostel_id::text || ':' || v_user.role::text, 0));

    select count(*) into v_count
      from public.staff_hostel_access a
      join public.users u on u.id = a.user_id
     where a.hostel_id = new.hostel_id
       and u.role = v_user.role
       and u.status = 'active'
       and u.deleted_at is null
       and u.id <> new.user_id;

    if v_count >= 5 then
      -- Same opening words as enforce_role_limits ("This PG already has 5 active"), which the
      -- Flutter sheet and the Edge Function recognise.
      raise exception 'This PG already has % active %s. Remove one from it first.', 5, v_user.role
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end $$;

-- UPDATE as well as INSERT: nothing in the product updates these rows, but a service-role repair
-- that re-points one should meet the same four rules as a new grant, not skip them.
drop trigger if exists staff_hostel_access_guard on public.staff_hostel_access;
create trigger staff_hostel_access_guard before insert or update of user_id, hostel_id
  on public.staff_hostel_access
  for each row execute function app.staff_hostel_access_guard();


-- ═══ 5. app.user_hostel_id(): A STAFF MEMBER'S PG COUNTS ONLY WHILE THEY HAVE ACCESS ═══════════
--
-- Live body, one change: the last condition. For managers and wardens the PG in users.hostel_id
-- is returned only while an access row backs it, so removing a PG from somebody takes effect in
-- all 36 policies at once and needs no second write to users. Owners, residents and the Super
-- Admin are exactly as before. One primary-key probe per call.
create or replace function app.user_hostel_id()
returns uuid
language sql stable security definer set search_path = public as $$
  select u.hostel_id from public.users u
   where u.id = auth.uid()
     and u.status = 'active'
     and u.deleted_at is null
     and app.mfa_satisfied()
     and (u.role not in ('manager', 'warden')
          or exists (select 1 from public.staff_hostel_access a
                      where a.user_id = u.id and a.hostel_id = u.hostel_id))
$$;


-- ═══ 6. app.users_update_guard: THE ONE RULE FOR MOVING users.hostel_id ═══════════════════════
--
-- Live body, one change: the hostel_id check. Moving an account between PGs used to be refused
-- outright for everyone but the Super Admin and the service role (whose early return is
-- untouched). It is now allowed when ALL of these hold, and still raises the same 42501 otherwise:
--
--   · the account is a manager or warden and is not deleted,
--   · the new PG is not NULL and the account has an access row for it,
--   · the new PG has the same owner as the old one,
--   · and EITHER the account is moving itself, is active, and has met the second-factor rule
--     (staff switching PG), OR the caller owns both PGs (an owner re-pointing their own staff,
--     which is what owner_set_staff_hostels does when it removes the PG somebody is working in).
--
-- The owner arm does not require the account to be active, on purpose. owner_set_staff_hostels
-- has to be able to take a PG away from a deactivated warden, and if it could not move their
-- users.hostel_id they would be reactivated into a PG they no longer have (app.user_hostel_id()
-- NULL, and the reactivation counted against a PG they are not in). An owner can already
-- reactivate the account and move it, so this grants nothing new.
--
-- The whole condition is wrapped in coalesce(..., false). With no JWT, auth.uid() is NULL, so
-- `old.id = auth.uid()` is NULL, `NULL or false` is NULL, and `if not NULL` does not raise: the
-- rule would wave the move through, and only the guard's last line (where new.id = auth.uid()
-- is NULL too) would still stop it. The rule has to refuse on its own, not lean on a backstop
-- written for something else. Same lesson as refresh_subscription_statuses.
create or replace function app.users_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_manages_target boolean;
begin
  if new.email is distinct from old.email then
    new.email_verified_at := null;
    new.email_verification_reset_at := now();
  elsif new.email_verified_at is distinct from old.email_verified_at and not app.is_service_role() then
    raise exception 'Email verification cannot be granted by hand — it is earned by opening the link Nivora emails to the address.'
      using errcode = '42501';
  end if;

  if app.is_super_admin() then
    return new;
  end if;

  v_manages_target :=
       (old.role in ('manager','warden') and app.owns_hostel(old.hostel_id))
    or (old.role = 'student' and app.has_role_in(old.hostel_id, 'warden'));

  if new.id is distinct from old.id then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    raise exception 'You cannot change an account''s role.' using errcode = '42501';
  end if;
  if new.hostel_id is distinct from old.hostel_id
     and not coalesce(
           old.role in ('manager','warden')
       and old.deleted_at is null
       and new.hostel_id is not null
       and exists (select 1 from public.staff_hostel_access a
                    where a.user_id = old.id and a.hostel_id = new.hostel_id)
       and exists (select 1
                     from public.hostels h_new
                     join public.hostels h_old on h_old.owner_user_id = h_new.owner_user_id
                    where h_new.id = new.hostel_id and h_old.id = old.hostel_id)
       and (   (old.id = auth.uid() and old.status = 'active' and app.mfa_satisfied())
            or (app.owns_hostel(old.hostel_id) and app.owns_hostel(new.hostel_id))),
         false) then
    raise exception 'You cannot move an account to another hostel.' using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  if (new.status is distinct from old.status or new.deleted_at is distinct from old.deleted_at)
     and not v_manages_target then
    raise exception 'You cannot change this account''s status.' using errcode = '42501';
  end if;

  if new.id = auth.uid() or v_manages_target then
    return new;
  end if;
  raise exception 'Not allowed.' using errcode = '42501';
end $$;


-- ═══ 7. app.enforce_role_limits: COUNT ACCESS, NEVER COUNT A SWITCH ═══════════════════════════
--
-- Live body. Students and the "must belong to a hostel" check are unchanged. For managers and
-- wardens:
--
--   (a) An UPDATE that changes only hostel_id, to a PG the account has access to, is a switch.
--       The account was counted in that PG when it was given access, so it returns without
--       counting. This is what lets a warden switch into a PG where five colleagues are working.
--   (b) Anything else counts active staff of the role WITH ACCESS (staff_hostel_access), not
--       staff whose users.hostel_id happens to be the PG. It counts new.hostel_id, and when the
--       account is arriving (a new account, status or deleted_at coming back, or a Super Admin
--       changing its role) every PG on its list as well, since each of them gains an active
--       member of that role.
--
-- One exception to (b): an UPDATE to a PG the account has NO access to does not count that PG.
-- The account is not a member there, so there is nothing to count, and users_update_guard, which
-- fires after this trigger (alphabetical order), refuses the move for everyone but the Super
-- Admin and the service role. Counting first would answer "is this PG full?" to a warden trying
-- another owner's PG id before the guard refused them. A Super Admin move of that kind fails
-- closed (app.user_hostel_id() is NULL) until an owner gives access.
--
-- PGs are locked in uuid order, so two reactivations with overlapping lists cannot deadlock. The
-- lock key is unchanged (hostel:role) and shared with app.staff_hostel_access_guard. OLD is read
-- only on the UPDATE path, as app.demo_review_email_verified does.
create or replace function app.enforce_role_limits() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_count int;
  v_limit int;
  v_hostel uuid;
  v_arriving boolean;
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
    if tg_op = 'UPDATE' then
      if new.hostel_id is distinct from old.hostel_id
         and new.role = old.role
         and new.status = old.status
         and new.deleted_at is not distinct from old.deleted_at
         and exists (select 1 from public.staff_hostel_access a
                      where a.user_id = new.id and a.hostel_id = new.hostel_id) then
        return new;
      end if;
      v_arriving := old.status <> 'active' or old.deleted_at is not null or new.role <> old.role;
    else
      v_arriving := true;
    end if;

    for v_hostel in
      select new.hostel_id
       where tg_op = 'INSERT'
          or exists (select 1 from public.staff_hostel_access a
                      where a.user_id = new.id and a.hostel_id = new.hostel_id)
      union
      select a.hostel_id
        from public.staff_hostel_access a
       where v_arriving
         and a.user_id = new.id
      order by 1
    loop
      perform pg_advisory_xact_lock(hashtextextended(v_hostel::text || ':' || new.role::text, 0));

      select count(*) into v_count
      from public.staff_hostel_access a
      join public.users u on u.id = a.user_id
      where a.hostel_id = v_hostel
        and u.role = new.role
        and u.status = 'active'
        and u.deleted_at is null
        and u.id <> new.id;

      if v_count >= v_limit then
        -- The Flutter sheet and the Edge Function both recognise this sentence by its opening
        -- words ("This PG already has 5 active"), so it is a contract, not just copy.
        raise exception 'This PG already has % active %s. Remove one from it first.', v_limit, new.role
          using errcode = 'P0001';
      end if;
    end loop;
    return new;
  end if;

  select count(*) into v_count
  from public.users u
  where u.hostel_id = new.hostel_id
    and u.role = new.role
    and u.status = 'active'
    and u.deleted_at is null
    and u.id <> new.id;

  if v_count >= v_limit then
    raise exception 'This hostel has reached the limit of 10,000 active students.' using errcode = 'P0001';
  end if;
  return new;
end $$;


-- ═══ 8. THE RPCs ═══════════════════════════════════════════════════════════════════════════
--
-- Every refusal a person can reach is P0001, because the app shows a P0001 message word for word
-- and turns 42501 into a generic "You do not have access to that" (see
-- 2026-09-13-account-deletion-request-rpc.sql). owner_hostel_staff keeps 42501 for a caller who
-- does not own the PG: the owner's own screen never sends one, so only a probe sees it.

-- ── my_staff_hostels ────────────────────────────────────────────────────────────────────────
-- The PGs the calling manager or warden may switch to, for the switcher. The ONLY way staff read
-- another PG's hostels row, and it returns four harmless columns of it. Empty for every other
-- role, and for an inactive account.
create or replace function public.my_staff_hostels()
returns table(hostel_id uuid, name text, address text, status text, is_active boolean)
language sql stable security definer set search_path = public as $$
  select h.id, h.name, h.address, h.status::text, coalesce(h.id = u.hostel_id, false)
    from public.users u
    join public.staff_hostel_access a on a.user_id = u.id
    join public.hostels h on h.id = a.hostel_id
   where u.id = auth.uid()
     and u.role in ('manager', 'warden')
     and u.status = 'active'
     and u.deleted_at is null
     and app.mfa_satisfied()
   order by h.name, h.id
$$;

comment on function public.my_staff_hostels() is
  'The PGs the calling manager or warden may work in, by name; is_active marks the one they are in now. Empty for any other role. db/migrations/2026-09-30-multi-pg-staff-access.sql.';

-- ── staff_switch_hostel ─────────────────────────────────────────────────────────────────────
-- Moves the caller's users.hostel_id. The UPDATE goes through app.users_update_guard like any
-- other, so this function is a convenience with a friendlier refusal, not the security boundary.
-- Switching to the PG you are already in writes nothing, spends no rate limit and audits nothing.
create or replace function public.staff_switch_hostel(p_hostel_id uuid)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_user public.users%rowtype;
begin
  -- Locked, so an owner changing this account's PGs at the same moment either waits for the
  -- switch or is waited for, and the check below reads the list they left.
  select * into v_user
    from public.users u
   where u.id = auth.uid()
     and u.status = 'active'
     and u.deleted_at is null
   for update;

  if not found or v_user.role not in ('manager', 'warden') or not app.mfa_satisfied() then
    raise exception 'Only wardens and managers can switch PG.' using errcode = 'P0001';
  end if;

  if p_hostel_id is null or not exists (
       select 1 from public.staff_hostel_access a
        where a.user_id = v_user.id and a.hostel_id = p_hostel_id) then
    raise exception 'You do not have access to that PG.' using errcode = 'P0001';
  end if;

  if v_user.hostel_id = p_hostel_id then
    return p_hostel_id;
  end if;

  -- Each switch rewrites a users row and an audit row. A person switches a few times an hour;
  -- this only stops a loop.
  perform app.spend(
    'staff-switch-hostel', 30, 600,
    'You have switched PG many times in the last few minutes. Wait a moment and try again.'
  );

  update public.users set hostel_id = p_hostel_id where id = v_user.id;

  perform public.audit_event(
    'staff.hostel.switch',
    'user',
    v_user.id::text,
    p_hostel_id,
    jsonb_build_object('from', v_user.hostel_id, 'to', p_hostel_id, 'surface', 'rpc'),
    null, null, null, null
  );

  return p_hostel_id;
end $$;

comment on function public.staff_switch_hostel(uuid) is
  'The calling manager or warden starts working in another PG they have access to (their users.hostel_id, shared by all their devices). Returns the PG. P0001 when the caller is not an active manager or warden, or has no access to the PG. Audits staff.hostel.switch.';

-- ── owner_set_staff_hostels ─────────────────────────────────────────────────────────────────
-- Replaces a staff member's list with exactly p_hostel_ids. The checks run in the order the
-- client contract lists its errors. If the PG they are working in is removed, they are moved to
-- the first remaining PG by name, through the owner arm of users_update_guard. Saving the list
-- they already have writes nothing.
create or replace function public.owner_set_staff_hostels(p_user_id uuid, p_hostel_ids uuid[])
returns table(hostel_id uuid, is_active boolean)
language plpgsql security definer set search_path = public as $$
declare
  v_ids    uuid[];
  v_staff  public.users%rowtype;
  v_before uuid[];
  v_active uuid;
begin
  select coalesce(array_agg(distinct t.x order by t.x), '{}')
    into v_ids
    from unnest(p_hostel_ids) as t(x)
   where t.x is not null;

  if cardinality(v_ids) = 0 then
    raise exception 'Choose at least one PG.' using errcode = 'P0001';
  end if;

  -- app.owns_hostel carries the owner's second factor. A caller who is not an owner at all (a
  -- warden trying PG ids) owns none of them and is told the same thing.
  if exists (select 1 from unnest(v_ids) as t(x) where not app.owns_hostel(t.x)) then
    raise exception 'You can only give access to your own PGs.' using errcode = 'P0001';
  end if;

  -- Locked for the rest of the call: a switch or a reactivation of this account waits for us.
  select * into v_staff from public.users u where u.id = p_user_id for update;
  if not found
     or v_staff.role not in ('manager', 'warden')
     or v_staff.deleted_at is not null
     or not app.owns_hostel(v_staff.hostel_id) then
    raise exception 'That staff member is not yours.' using errcode = 'P0001';
  end if;

  select coalesce(array_agg(a.hostel_id order by a.hostel_id), '{}')
    into v_before
    from public.staff_hostel_access a
   where a.user_id = p_user_id;

  v_active := v_staff.hostel_id;

  if v_before is distinct from v_ids or not (v_active = any (v_ids)) then
    perform app.spend(
      'owner-staff-hostels', 60, 600,
      'You have changed staff access many times in the last few minutes. Wait a moment and try again.'
    );

    -- Only the caller's own PGs. The guard keeps every row on one owner, so this is belt and
    -- braces: an owner can never remove a grant that is not theirs to give.
    delete from public.staff_hostel_access a
     where a.user_id = p_user_id
       and not (a.hostel_id = any (v_ids))
       and a.hostel_id in (select h.id from public.hostels h where h.owner_user_id = auth.uid());

    -- Additions only, in uuid order, so concurrent grants and reactivations take the per-PG
    -- advisory locks in one order. The guard raises the staff-limit sentence for a full PG.
    insert into public.staff_hostel_access (user_id, hostel_id, granted_by)
    select p_user_id, t.x, auth.uid()
      from unnest(v_ids) as t(x)
     where not (t.x = any (v_before))
     order by t.x
    on conflict on constraint staff_hostel_access_pkey do nothing;

    if not (v_active = any (v_ids)) then
      select h.id into v_active
        from public.hostels h
       where h.id = any (v_ids)
       order by h.name, h.id
       limit 1;

      update public.users u set hostel_id = v_active where u.id = p_user_id;
    end if;

    perform public.audit_event(
      'owner.staff.hostels',
      'user',
      p_user_id::text,
      v_active,
      jsonb_build_object('role', v_staff.role, 'before', v_before, 'after', v_ids,
                         'active_from', v_staff.hostel_id, 'active_to', v_active, 'surface', 'rpc'),
      null, null, null, null
    );
  end if;

  return query
    select a.hostel_id, a.hostel_id = v_active
      from public.staff_hostel_access a
      join public.hostels h on h.id = a.hostel_id
     where a.user_id = p_user_id
     order by h.name, h.id;
end $$;

comment on function public.owner_set_staff_hostels(uuid, uuid[]) is
  'Owner only. Replaces the PGs one of their managers or wardens may work in with exactly p_hostel_ids (deduplicated, at least one). Moves them to the first remaining PG by name if the one they are in is removed. Returns every PG on the new list with is_active. P0001 on every refusal, including the 5-per-PG staff limit. Audits owner.staff.hostels.';

-- ── owner_hostel_staff ──────────────────────────────────────────────────────────────────────
-- The owner's staff screen for one PG: every manager and warden, active or not, who may work in
-- it, wherever they are working now. Soft-deleted accounts are left out, as getStaff() in
-- lib/queries/owner.ts leaves them out. hostel_ids and the active PG are limited to the caller's
-- own PGs, which the guard makes the same thing as all of them.
create or replace function public.owner_hostel_staff(p_hostel_id uuid)
returns table(user_id uuid, full_name text, email text, phone text, role public.user_role,
              status public.user_status, created_at timestamptz, must_change_password boolean,
              active_hostel_id uuid, active_hostel_name text, hostel_ids uuid[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not app.owns_hostel(p_hostel_id) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  return query
    select u.id, u.full_name, u.email, u.phone, u.role, u.status, u.created_at,
           u.must_change_password, cur.id, cur.name,
           array(select mine.hostel_id
                   from public.staff_hostel_access mine
                   join public.hostels mh on mh.id = mine.hostel_id
                  where mine.user_id = u.id
                    and mh.owner_user_id = auth.uid()
                  order by mh.name, mh.id)
      from public.staff_hostel_access a
      join public.users u on u.id = a.user_id
      left join public.hostels cur on cur.id = u.hostel_id and cur.owner_user_id = auth.uid()
     where a.hostel_id = p_hostel_id
       and u.role in ('manager', 'warden')
       and u.deleted_at is null
     order by u.role, u.full_name, u.id;
end $$;

comment on function public.owner_hostel_staff(uuid) is
  'Owner only. Every manager and warden (active and inactive, not deleted) with access to the PG, with the PG they are working in now and their full list of the caller''s PGs. Ordered by role, then name.';

-- ── hostel_staff_names ──────────────────────────────────────────────────────────────────────
-- Names for task lines: the owner and every manager and warden with access to the PG. Inactive
-- staff are included so an old task keeps its assignee's name; deleted accounts are not, as in
-- the manager screen's query this replaces. Names and roles only, for anybody who can read the
-- PG, as public.notice_authors does for notice authors.
create or replace function public.hostel_staff_names(p_hostel_id uuid)
returns table(user_id uuid, full_name text, role public.user_role)
language sql stable security definer set search_path = public as $$
  select u.id, u.full_name, u.role
    from public.users u
   where app.can_read_hostel(p_hostel_id)
     and u.deleted_at is null
     and u.role in ('owner', 'manager', 'warden')
     -- Deactivated staff are named only to the people who assign and read tasks. A resident can
     -- read the PG too, and has no reason to learn who used to work there.
     and (u.status = 'active' or u.role = 'owner'
          or app.user_role() in ('owner', 'manager', 'super_admin'))
     and u.id in (
           select h.owner_user_id from public.hostels h where h.id = p_hostel_id
           union all
           select a.user_id from public.staff_hostel_access a where a.hostel_id = p_hostel_id
         )
   order by u.role, u.full_name, u.id
$$;

comment on function public.hostel_staff_names(uuid) is
  'The owner and every manager and warden with access to the PG (names and roles only), for anybody who can read the PG. Used to name task lines.';


-- ═══ 9. ROUTINES THAT FOUND STAFF BY users.hostel_id ═════════════════════════════════════════
--
-- Each is its live body with the staff match changed from `hostel_id = <pg>` to
-- `id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = <pg>)`, and
-- nothing else. Residents keep matching by users.hostel_id.
--
-- Where the match sits inside an OR (the complaint and notice fan-outs) it is written
-- `id = any (array(select ...))` instead. Under an OR an IN cannot become a join, so the planner
-- keeps it as a hashed subplan and reads every active warden on the platform to find this PG's.
-- The array is computed once and probed through users_pkey, as the old hostel_id arm probed
-- users_hostel_role_idx.

-- Live body, four identical changes (the warden and manager subqueries). A multi-PG warden is
-- on the contact card of every PG they may work in, not only the one they are in right now.
create or replace function public.st_hostel_contacts()
returns table(hostel_name text, address text, rules text, warden_name text, warden_phone text,
              manager_name text, manager_phone text, owner_name text)
language sql stable security definer set search_path = public as $$
  select h.name, h.address, h.rules,
    (select u.full_name from public.users u
      where u.id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = h.id) and u.role = 'warden' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.phone from public.users u
      where u.id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = h.id) and u.role = 'warden' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.full_name from public.users u
      where u.id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = h.id) and u.role = 'manager' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.phone from public.users u
      where u.id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = h.id) and u.role = 'manager' and u.status = 'active' and u.deleted_at is null
      order by u.created_at, u.id limit 1),
    (select u.full_name from public.users u where u.id = h.owner_user_id)
  from public.hostels h
  where h.id = coalesce(app.user_hostel_id(),
                        (select hostel_id from public.students where user_id = auth.uid() limit 1))
    and app.mfa_satisfied()
$$;

-- Live body, one change: the warden arm of the new-complaint fan-out.
create or replace function app.complaints_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_student_user uuid; v_actor uuid := coalesce(auth.uid(), new.updated_by); r record;
begin
  if tg_op = 'INSERT' then
    insert into public.complaint_events (hostel_id, complaint_id, status, note, actor_user_id) values (new.hostel_id, new.id, new.status, 'Complaint raised', v_actor);
    for r in
      select u.id, u.role from public.users u
      where u.status = 'active' and u.deleted_at is null and (
        (u.role = 'warden' and u.id = any (array(select a.user_id from public.staff_hostel_access a where a.hostel_id = new.hostel_id)))
        or (u.role = 'owner' and u.id = (select owner_user_id from public.hostels where id = new.hostel_id)))
    loop
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, r.id, 'complaint', 'New complaint: ' || new.title, initcap(new.category::text) || ' complaint raised by a student.',
              case when r.role = 'owner' then '/owner/complaints' else '/warden/complaints' end);
    end loop;
    return new;
  end if;
  if tg_op = 'UPDATE' and (new.status is distinct from old.status or new.resolution_note is distinct from old.resolution_note) then
    if new.status = 'resolved' and new.resolved_at is null then update public.complaints set resolved_at = now() where id = new.id; end if;
    insert into public.complaint_events (hostel_id, complaint_id, status, note, actor_user_id)
    values (new.hostel_id, new.id, new.status, case when new.resolution_note is distinct from old.resolution_note then new.resolution_note else null end, v_actor);
    if new.status is distinct from old.status then
      select user_id into v_student_user from public.students where id = new.student_id;
      if v_student_user is not null then
        insert into public.notifications (hostel_id, user_id, type, title, body, link)
        values (new.hostel_id, v_student_user, 'complaint', 'Complaint ' || replace(new.status::text, '_', ' '),
                '"' || new.title || '" is now ' || replace(new.status::text, '_', ' ') || '.', '/student/complaints');
      end if;
    end if;
  end if;
  return new;
end $$;

-- Live body, one change: the wardens told about a new leave request.
create or replace function app.leaves_after_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_student_user uuid; v_name text; r record;
begin
  select user_id, full_name into v_student_user, v_name from public.students where id = new.student_id;
  if tg_op = 'INSERT' then
    for r in select id from public.users where id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = new.hostel_id) and role = 'warden' and status = 'active' and deleted_at is null loop
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, r.id, 'leave', 'Leave request from ' || coalesce(v_name, 'student'), to_char(new.from_date, 'DD Mon') || ' → ' || to_char(new.to_date, 'DD Mon'), '/warden/leaves');
    end loop;
  elsif new.status is distinct from old.status and new.status <> 'pending' then
    if new.decided_at is null then update public.leaves set decided_at = now() where id = new.id; end if;
    if v_student_user is not null then
      insert into public.notifications (hostel_id, user_id, type, title, body, link)
      values (new.hostel_id, v_student_user, 'leave', 'Leave ' || new.status::text,
              'Your leave (' || to_char(new.from_date, 'DD Mon') || ' → ' || to_char(new.to_date, 'DD Mon') || ') was ' || new.status::text || '.', '/student/leave');
    end if;
    if new.status = 'approved' and current_date between new.from_date and new.to_date then
      update public.students set status = 'on_leave' where id = new.student_id and status = 'active';
    end if;
  end if;
  return new;
end $$;

-- Live body, one change: the PG filter. Residents are still found by users.hostel_id, staff by
-- their access list. The audience clauses below already limit the roles to warden and student.
create or replace function app.announcements_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  select new.hostel_id, u.id, 'announcement', new.title, left(new.body, 140),
         case u.role when 'warden' then '/warden/notices' else '/student/notices' end
    from public.users u
   where (   (u.role not in ('manager', 'warden') and u.hostel_id = new.hostel_id)
          or (u.role in ('manager', 'warden')
              and u.id = any (array(select a.user_id from public.staff_hostel_access a where a.hostel_id = new.hostel_id))))
     and u.status = 'active'
     and u.deleted_at is null
     and u.id <> new.author_user_id
     and (
          (new.audience = 'all'      and u.role in ('warden', 'student'))
       or (new.audience = 'warden'   and u.role = 'warden')
       or (new.audience = 'students' and u.role = 'student')
     );
  return new;
end $$;

-- Live body, one change: "this hostel's manager" means a manager with access to the task's PG,
-- wherever they are working right now. v_hostel went with the comparison it existed for.
create or replace function app.tasks_assignee_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role public.user_role; v_status public.user_status;
begin
  if app.is_super_admin() then return new; end if;
  select role, status into v_role, v_status from public.users where id = new.assigned_to;
  if v_role is null then
    raise exception 'That user does not exist.' using errcode = 'P0001';
  end if;
  if v_role <> 'manager' or v_status <> 'active'
     or not exists (select 1 from public.staff_hostel_access a
                     where a.user_id = new.assigned_to and a.hostel_id = new.hostel_id) then
    raise exception 'Tasks can only be assigned to this hostel''s active manager.' using errcode = '42501';
  end if;
  return new;
end $$;

-- Live body (2026-09-13), one change: a resident's request goes to every warden with access to
-- their PG. A warden or manager filing their own request is still matched to the PG they are
-- working in, whose owner is the owner of all their PGs.
create or replace function public.request_account_deletion(
  p_reason    text default null,
  p_hostel_id uuid default null
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_user        uuid := auth.uid();
  v_role        public.user_role;
  v_name        text;
  v_user_hostel uuid;
  v_hostel      uuid;
  v_owner       uuid;
  v_student     uuid;
  v_reason      text := nullif(btrim(coalesce(p_reason, '')), '');
  v_existing    timestamptz;
  v_body        text;
  v_notified    integer := 0;
  v_at          timestamptz;
begin
  if v_user is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;

  select u.role, u.full_name, u.hostel_id
    into v_role, v_name, v_user_hostel
    from public.users u
   where u.id = v_user
     and u.deleted_at is null;

  if v_role is null then
    raise exception 'This account is not set up yet.' using errcode = 'P0001';
  end if;
  if v_role not in ('student', 'warden', 'manager', 'owner') then
    raise exception 'Deletion requests for this account are handled by the platform administrator.'
      using errcode = 'P0001';
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    raise exception 'Keep the reason under 500 characters.' using errcode = 'P0001';
  end if;

  if v_role = 'owner' then
    select h.id, h.owner_user_id
      into v_hostel, v_owner
      from public.hostels h
     where h.owner_user_id = v_user
       and (p_hostel_id is null or h.id = p_hostel_id)
     order by (h.id = v_user_hostel) desc nulls last, h.created_at
     limit 1;
  else
    select h.id, h.owner_user_id
      into v_hostel, v_owner
      from public.hostels h
     where h.id = v_user_hostel;
  end if;

  if v_hostel is null then
    raise exception 'No hostel is linked to this account. Please contact the address on the account deletion page.'
      using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('account-deletion:' || v_user::text));

  perform app.spend(
    'account-deletion', 3, 86400,
    'You have already sent this request. Your warden and hostel owner can see it.'
  );

  select max(a.at)
    into v_existing
    from public.audit_log a
   where a.action = 'account.deletion.requested'
     and a.actor_user_id = v_user
     and a.at >= now() - interval '30 days';

  if v_existing is not null then
    return jsonb_build_object('requested_at', v_existing, 'already_pending', true, 'notified', 0);
  end if;

  if v_role = 'student' then
    select s.id
      into v_student
      from public.students s
     where s.user_id = v_user
       and s.status <> 'vacated'
     limit 1;
  end if;

  v_body := coalesce(nullif(btrim(v_name), ''), 'A user')
         || ' asked for their NIVORA account and personal data to be deleted.'
         || case when v_reason is not null then ' Reason: "' || left(v_reason, 200) || '"' else '' end
         || ' Verify who they are in person before acting.';

  with recipients as (
    select u.id, 'super_admin' as role
      from public.users u
     where v_role = 'owner'
       and u.role = 'super_admin' and u.status = 'active' and u.deleted_at is null
    union
    select u.id, 'warden'
      from public.users u
     where v_role = 'student'
       and u.role = 'warden' and u.id in (select a.user_id from public.staff_hostel_access a where a.hostel_id = v_hostel) and u.status = 'active' and u.deleted_at is null
    union
    select u.id, 'owner'
      from public.users u
     where v_role <> 'owner'
       and u.id = v_owner and u.status = 'active' and u.deleted_at is null
  ),
  delivered as (
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    select v_hostel, r.id, 'system', 'Account deletion requested', v_body,
           case r.role
             when 'super_admin' then '/super-admin/hostels'
             when 'owner' then case when v_student is not null
                                    then '/owner/students/' || v_student::text
                                    else '/owner/staff' end
             else '/warden/rooms'
           end
      from recipients r
     where r.id <> v_user
    returning 1
  )
  select count(*) into v_notified from delivered;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (
    v_user, v_role, 'account.deletion.requested', 'user', v_user::text, v_hostel,
    jsonb_build_object(
      'requesterRole', v_role::text,
      'studentId',     v_student,
      'notified',      v_notified,
      'hasReason',     v_reason is not null,
      'surface',       'app'
    )
  )
  returning at into v_at;

  return jsonb_build_object('requested_at', v_at, 'already_pending', false, 'notified', v_notified);
end $$;


-- ═══ 10. GRANTS ════════════════════════════════════════════════════════════════════════════
--
-- Signed-in callers only; each function checks role, ownership and the second factor itself.
-- anon is named explicitly (see the header). The redefined routines keep the grants they already
-- had, because CREATE OR REPLACE on an unchanged signature does not touch proacl. The two new
-- trigger functions keep the default, like the other app.*_guard functions: a trigger function
-- cannot be called except as a trigger.

revoke all on function public.my_staff_hostels() from public, anon;
grant execute on function public.my_staff_hostels() to authenticated;

revoke all on function public.staff_switch_hostel(uuid) from public, anon;
grant execute on function public.staff_switch_hostel(uuid) to authenticated;

revoke all on function public.owner_set_staff_hostels(uuid, uuid[]) from public, anon;
grant execute on function public.owner_set_staff_hostels(uuid, uuid[]) to authenticated;

revoke all on function public.owner_hostel_staff(uuid) from public, anon;
grant execute on function public.owner_hostel_staff(uuid) to authenticated;

revoke all on function public.hostel_staff_names(uuid) from public, anon;
grant execute on function public.hostel_staff_names(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;


-- ═══ AFTER APPLYING ════════════════════════════════════════════════════════════════════════
--
-- 1. Run db/migrations/2026-09-30-multi-pg-staff-access.test.sql. It rolls itself back and ends
--    with NOTICE 'ALL MULTI-PG TESTS PASSED' (and a one-row result saying the same).
--
-- 2. Nobody was shut out. Every active manager and warden still resolves to the PG they are in:
--      select u.id, u.role, u.hostel_id
--        from public.users u
--       where u.role in ('manager', 'warden') and u.status = 'active' and u.deleted_at is null
--         and not exists (select 1 from public.staff_hostel_access a
--                          where a.user_id = u.id and a.hostel_id = u.hostel_id);
--    Zero rows.
--
-- 3. The five RPCs exist, are SECURITY DEFINER with a pinned search_path, and anon cannot run them:
--      select p.oid::regprocedure, p.prosecdef, p.proconfig, array_to_string(p.proacl, ' | ')
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('my_staff_hostels', 'staff_switch_hostel', 'owner_set_staff_hostels',
--                           'owner_hostel_staff', 'hostel_staff_names');
--    Five rows, prosecdef true, {search_path=public}, `authenticated=X` present, `anon=X` absent.
--
-- 4. Clients cannot write the table, TRUNCATE included:
--      select grantee, string_agg(privilege_type, ',' order by privilege_type)
--        from information_schema.role_table_grants
--       where table_schema = 'public' and table_name = 'staff_hostel_access'
--       group by 1;
--    authenticated: SELECT only. anon: no row.
--
-- 5. No routine still finds staff by users.hostel_id. Zero rows (before this migration it
--    listed the six routines of sections 7 and 9 that match staff by hostel_id directly):
--      select p.oid::regprocedure
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname in ('public', 'app')
--         and p.prosrc ~* '''(warden|manager)'''
--         and p.prosrc ~* 'hostel_id'
--         and p.prosrc !~* 'staff_hostel_access|user_hostel_id|has_role_in';
