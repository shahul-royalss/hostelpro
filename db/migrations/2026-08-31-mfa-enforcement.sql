-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- TWO-FACTOR AUTHENTICATION, ENFORCED SERVER-SIDE
-- Applied to nimxvgzscbanhtvgnjll on 2026-08-31 as three migrations:
--   mfa_enforcement_predicate
--   mfa_enforcement_wire_rls_helpers
--   mfa_enforcement_gate_live_owner_paths
-- ═══════════════════════════════════════════════════════════════════════════════════════════
--
-- WHAT WAS TRUE BEFORE. MFA_REQUIRED_ROLES=super_admin,owner lived in .env.local and had
-- exactly one reader: the Next.js middleware (lib/supabase/middleware.ts:37,333). Postgres knew
-- nothing about it — 0 of 65 live policies mentioned `aal`. supabase/functions/_shared/caller.ts
-- never read an assurance level either. On 2026-08-30 an auditor signed in as SUPER_ADMIN with
-- a password alone, through the same endpoint the Flutter app uses, and was issued a working
-- token at aal1. The Flutter client reads PostgREST directly for nearly everything, so for that
-- client the second factor was decoration.
--
-- ── THE RULE, CHOSEN AGAINST THE LIVE DATABASE ───────────────────────────────────────────
--
-- On the day this shipped the platform held 8 users: 1 super_admin (0 factors), 3 owners (ONE
-- with a verified TOTP factor since 2026-08-23, two with none), 1 manager, 2 wardens,
-- 1 student. A flat "privileged ⇒ aal2 or nothing" would have locked out the super admin and
-- two of three owners on their next request — the platform administrators, out of their own
-- platform, with no way back in, because enrolling a factor itself needs a working session.
--
--   role not in app.mfa_required_roles()      → unaffected (manager, warden, student)
--   privileged, session is aal2               → allowed
--   privileged, aal1, HAS a verified factor   → REFUSED. This is the enforcement.
--   privileged, aal1, has NO factor           → ALLOWED (GRACE). The client routes them to
--                                               enrolment; see nivora_app/lib/core/auth/
--                                               auth_controller.dart mfaGate().
--
-- The grace arm is a REAL hole, written down as one: a stolen password for the super admin or
-- for either factor-less owner still opens the door today. It closes per account, by itself,
-- the moment that account enrols — no migration, no redeploy. When the last privileged account
-- has a factor, delete the `not exists` arm and the hole is gone for good.
--
-- ── THE TRAP THIS MIGRATION FELL INTO, SO THE NEXT PERSON DOES NOT ───────────────────────
--
-- db/rls-policies.sql IS STALE. It declares 63 policies routed through app.can_read_hostel() /
-- app.owns_hostel() / app.has_role_in() / app.is_staff_of(). The LIVE database has 65 policies,
-- rewritten for performance, that call NONE of those four. Every live policy inlines instead:
--
--     (select app.is_super_admin())                     -- 43 policies
--     hostel_id in (select app.owned_hostel_ids())      -- 31 policies   <- the OWNER path
--     hostel_id = (select app.user_hostel_id())         -- 36 policies   <- the TENANT path
--     (select app.user_role()) = 'warden' | 'manager'   -- 30 policies   -- qualifies the above
--
-- Part 2 below gates the four helpers from the repo file. On its own it changed NOTHING for
-- PostgREST. That was caught only by probing row visibility as the real owner: after part 2 the
-- owner who has held a factor since 2026-08-23 still read their hostel, their student and their
-- fee rows at aal1. Part 3 is the fix that bites. Verify RLS against pg_policy, never against
-- this repository's SQL files.
--
-- ── HOW TO TURN IT OFF IN A HURRY ────────────────────────────────────────────────────────
--
--   create or replace function app.mfa_satisfied() returns boolean
--     language sql stable security definer set search_path = public as $fn$ select true $fn$;


-- ═══ PART 1 — the predicate ═════════════════════════════════════════════════════════════
--
-- Postgres cannot read a Vercel environment variable, so the list exists here too. This is the
-- AUTHORITY for row-level security. MFA_REQUIRED_ROLES in .env.local drives the Next.js
-- middleware; MFA_REQUIRED_ROLES in the Edge Function secrets drives
-- supabase/functions/_shared/caller.ts. All three must agree, and nothing but these comments
-- checks that they do.
create or replace function app.mfa_required_roles()
returns public.user_role[]
language sql
immutable
as $fn$ select array['super_admin', 'owner']::public.user_role[] $fn$;

comment on function app.mfa_required_roles() is
  'Roles that must carry a verified second factor. Keep in step with MFA_REQUIRED_ROLES in .env.local (lib/supabase/middleware.ts) and in the Edge Function secrets (supabase/functions/_shared/caller.ts).';

-- True when this session may exercise privilege. Safe to append to ANY policy as
-- `and app.mfa_satisfied()` — it returns true for every role not on the list.
--
-- `aal` is minted by GoTrue when it issues the token and, unlike app_metadata.role, is NOT
-- writable by the service role, so it may be read from the claims. It arrives through
-- request.jwt.claims, which PostgREST populates only after verifying the signature.
-- A MISSING aal claim is read as aal1, not as a pass: fail closed.
create or replace function app.mfa_satisfied()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_role public.user_role;
begin
  -- The service role is not a person and holds no factor. Edge Functions and the Razorpay
  -- webhook must keep working; caller.ts checks the human they act for.
  if app.is_service_role() then
    return true;
  end if;

  -- Cheap arm first: one jsonb lookup, no table read. Steady state for a stepped-up user.
  if coalesce(auth.jwt() ->> 'aal', '') = 'aal2' then
    return true;
  end if;

  v_role := app.user_role();
  if v_role is null or not (v_role = any (app.mfa_required_roles())) then
    return true;
  end if;

  -- Privileged and never presented a code this session. The grace arm: an account with no
  -- factor cannot be asked to present one. Indexed by mfa_factors_user_id_idx.
  return not exists (
    select 1 from auth.mfa_factors f
     where f.user_id = auth.uid() and f.status = 'verified'
  );
end
$fn$;

comment on function app.mfa_satisfied() is
  'True unless the caller holds a role in app.mfa_required_roles(), has a verified TOTP factor, and this session is not aal2. Users with no factor pass (grace path) so enrolment stays reachable.';

revoke all on function app.mfa_required_roles() from public;
revoke all on function app.mfa_satisfied() from public;
grant execute on function app.mfa_required_roles() to authenticated, service_role;
grant execute on function app.mfa_satisfied() to authenticated, service_role;


-- ═══ PART 2 — the helpers db/rls-policies.sql believes in ═══════════════════════════════
--
-- No LIVE policy calls these four (see the trap above), but the SECURITY DEFINER RPCs do —
-- ow_update_hostel_rules, ack_security_alert, wd_record_payment, wd_vacate_student,
-- wd_register_student, users_update_guard, tasks_assignee_guard, students_identity_guard — and
-- so will db/rls-policies.sql if it is ever replayed. The conjunct goes on the WHOLE result,
-- not on individual branches: can_read_hostel's third branch is a bare `user_hostel_id() = h`
-- and all three live owners have users.hostel_id set to the hostel they own, so a per-branch
-- gate would have left that one open.
create or replace function app.is_super_admin()
returns boolean language sql stable security definer set search_path to 'public'
as $fn$
  select (coalesce(app.user_role() = 'super_admin', false) and app.mfa_satisfied())
      or app.is_service_role()
$fn$;

create or replace function app.owns_hostel(p_hostel_id uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $fn$
  select exists (select 1 from public.hostels h where h.id = p_hostel_id and h.owner_user_id = auth.uid())
     and coalesce(app.user_role() = 'owner', false)
     and app.mfa_satisfied()
$fn$;

create or replace function app.can_read_hostel(p_hostel_id uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $fn$
  select (app.is_super_admin() or app.owns_hostel(p_hostel_id) or app.user_hostel_id() = p_hostel_id)
     and app.mfa_satisfied()
$fn$;

create or replace function app.is_staff_of(p_hostel_id uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $fn$
  select (app.is_super_admin() or app.owns_hostel(p_hostel_id)
          or (app.user_hostel_id() = p_hostel_id and app.user_role() in ('manager','warden')))
     and app.mfa_satisfied()
$fn$;

-- Gated by inheritance already (owner branch goes through owns_hostel, the other excludes
-- owners). The trailing conjunct is here so the guarantee survives a later branch edit.
create or replace function app.has_role_in(p_hostel_id uuid, variadic p_roles public.user_role[])
returns boolean language sql stable security definer set search_path to 'public'
as $fn$
  select (app.is_super_admin()
       or (app.user_role() = 'owner' and 'owner' = any(p_roles) and app.owns_hostel(p_hostel_id))
       or (app.user_hostel_id() = p_hostel_id and app.user_role() = any(p_roles) and app.user_role() <> 'owner'))
     and app.mfa_satisfied()
$fn$;

-- Resolves its hostel from app.user_hostel_id() directly rather than through a helper. Left
-- ungated it hands a refused owner the hostel address and rules and the warden's and manager's
-- names and phone numbers.
create or replace function public.st_hostel_contacts()
returns table(hostel_name text, address text, rules text, warden_name text, warden_phone text, manager_name text, manager_phone text, owner_name text)
language sql stable security definer set search_path to 'public'
as $fn$
  select h.name, h.address, h.rules,
         (select u.full_name from public.users u where u.hostel_id = h.id and u.role = 'warden'  and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.phone     from public.users u where u.hostel_id = h.id and u.role = 'warden'  and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.full_name from public.users u where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.phone     from public.users u where u.hostel_id = h.id and u.role = 'manager' and u.status = 'active' and u.deleted_at is null limit 1),
         (select u.full_name from public.users u where u.id = h.owner_user_id)
  from public.hostels h
  where h.id = coalesce(app.user_hostel_id(), (select hostel_id from public.students where user_id = auth.uid() limit 1))
    and app.mfa_satisfied()
$fn$;


-- ═══ PART 3 — the two functions the LIVE policies actually use ══════════════════════════
--
-- This is the part that bites. app.is_super_admin() was gated in part 2; these two carry the
-- rest of the privileged surface.
--
-- app.user_hostel_id() is the subtle one. Owners have users.hostel_id set to the hostel they
-- own (verified for all three live owners) and hostels_select's third branch is a bare
-- `id = (select app.user_hostel_id())` with NO role qualifier — so gating only the owner path
-- would have left the tenant path open and the refusal would have been theatre. Gating it costs
-- managers, wardens and students nothing: app.mfa_satisfied() is true for every role not on the
-- list, so the value they get back is unchanged.
create or replace function app.owned_hostel_ids()
returns setof uuid language sql stable security definer set search_path to 'public'
as $fn$
  select h.id from public.hostels h
   where (select app.user_role()) = 'owner'
     and h.owner_user_id = (select auth.uid())
     and (select app.mfa_satisfied())
$fn$;

create or replace function app.user_hostel_id()
returns uuid language sql stable security definer set search_path to 'public'
as $fn$
  select u.hostel_id from public.users u
   where u.id = auth.uid()
     and u.status = 'active'
     and u.deleted_at is null
     and app.mfa_satisfied()
$fn$;

comment on function app.owned_hostel_ids() is
  'Hostels this owner owns; empty unless app.mfa_satisfied(). Referenced by 31 live policies.';
comment on function app.user_hostel_id() is
  'The caller tenant binding; NULL unless app.mfa_satisfied(). Referenced by 36 live policies.';


-- ═══ VERIFIED ON THE LIVE DATABASE, 2026-08-31 ═════════════════════════════════════════
--
-- Each case impersonated with `set local role authenticated` + `set local request.jwt.claims`,
-- each with a distinct query shape so no cached plan could flatter the result.
--
--   A  owner WITH factor @ aal1        hostels 0  students 0  users 1 (own row)  rooms 0
--                                      fees 0  audit 0  st_hostel_contacts 0      REFUSED ✓
--   B  same owner @ aal2               hostels 1  students 1  users 4  rooms 16  contacts 1
--                                      (identical to the pre-migration baseline)     FULL ✓
--   C  super_admin, no factor @ aal1   hostels 3  users 8  rpc_sa_dashboard 3
--                                      rpc_sa_hostels 3                             GRACE ✓
--   D  owner, no factor @ aal1         hostels 1  rooms 17                           GRACE ✓
--   E  warden @ aal1                   students 1  rooms 16  users 4            UNAFFECTED ✓
--   F  owner WITH factor, aal ABSENT   hostels 0  students 0  rooms 0         FAIL CLOSED ✓
--   G  refused owner writes            students updated 0, announcements inserted 0  ✓
--   H  service_role                    hostels 3  users 8  students 1        UNAFFECTED ✓
