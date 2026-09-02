-- ⚠ SUPERSEDED IN PART BY db/migrations/2026-09-02-email-link-proof-pkce.sql.
--
-- Everything below about WHY the proof is read rather than written still stands. The two TABLES
-- it chose to read do not. This file said outright that the strings were taken from GoTrue's
-- source vocabulary rather than from this project's data, because a magic-link click could not
-- be produced from a migration. That click has since happened and was measured, and both arms
-- missed it:
--
--   · auth.mfa_amr_claims never gains a row for a PKCE link click — /auth/v1/verify issues an
--     auth code and creates no session, and an AMR claim is written only with a session. DELETED.
--   · the audit row for a link login carries NO `traits` key at all, so the
--     traits.provider in ('magiclink','otp') test below could never match.
--
-- Read the 2026-09-02 migration for what actually replaced them. Do not restore anything from
-- the function in section 2 of this file.

-- ═════════════════════════════════════════════════════════════════════════════════════════
-- EMAIL VERIFICATION BY LINK — the proof arrives from GoTrue, not from a typed code
-- ═════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY THE CODE FLOW WAS REPLACED ──────────────────────────────────────────────────────
--
-- Until today the sending path was: app -> email-verification Edge Function -> GoTrue -> mail.
-- The Edge Function existed to hold a durable per-user send counter and to be the only writer
-- of public.users.email_verified_at. It also sat in the one part of the flow that had to work
-- before anything else could: if it did not answer, no code was ever sent.
--
-- It did not answer. The product owner's failure screenshot read "The Nivora server did not
-- answer" — the phone's 15s deadline expiring on that function while this free-tier NANO
-- instance was flipping PostgREST and Auth to Unhealthy at ~72% RAM. The verification feature
-- was therefore unavailable exactly when the platform was least healthy, and it was unavailable
-- because we had inserted our own service into a path that did not need one.
--
-- A confirmation LINK is composed and sent by GoTrue itself. The app calls /auth/v1/otp
-- directly, so the path becomes app -> GoTrue -> mail: one fewer hop, and the hop removed is
-- the component that kept failing. That is the entire engineering argument, and it is the
-- reason this is a change worth making rather than a change of taste.
--
-- ── WHICH LEAVES ONE QUESTION: WHO WRITES THE PROOF? ────────────────────────────────────
--
-- With a code, the answer was easy — something watched GoTrue accept the six digits and wrote
-- the column. With a link, nothing of ours is present at the moment of truth: the user clicks
-- in their mail app, GoTrue verifies the one-time token, and the browser lands on a page.
--
-- The naive answers are all worse than they look:
--
--   · auth.users.email_confirmed_at — useless, and this is the whole reason the feature exists.
--     Every account-creation path stamps it at creation so the temporary password works at all
--     ("Confirm email" is ON: mailer_autoconfirm is false, re-verified 2026-09-01). It records
--     that somebody TYPED an address.
--   · auth.users.last_sign_in_at moving — a password sign-in on any device moves it too. That
--     is a coincidence, not a proof.
--   · a trigger on the auth schema — a trigger that raises inside GoTrue's login transaction
--     breaks SIGN-IN for every user of the project. Not a risk worth any convenience.
--   · a hand-rolled token table — a second implementation of something GoTrue already does,
--     and the first mistake in every hand-rolled one is storing the token in plaintext.
--
-- So the proof is READ, not written: GoTrue records two independent facts when a magic link is
-- consumed, and this migration adds one function that reads them.
--
--   auth.mfa_amr_claims  — one row per session naming HOW it was authenticated. This is the
--                          table behind the `amr` JWT claim, it is what MFA assurance levels
--                          are computed from, and on this project it currently holds exactly
--                          the two values you would expect ('password', 'totp' — checked
--                          2026-09-01). A link consumed through /auth/v1/verify creates a
--                          session whose method is 'magiclink' (or 'otp' if the same mail's
--                          code was used instead).
--   auth.audit_log_entries — the rows behind the dashboard's Auth Logs. A password grant on
--                          this project logs {"action":"login","traits":{"provider":"email"}}
--                          (read from the live table, 2026-09-01); a magic link logs the same
--                          shape with provider 'magiclink'.
--
-- BOTH are consulted, and either is sufficient. Not belt-and-braces for its own sake: neither
-- table's exact behaviour for a magiclink login could be produced and observed from here — that
-- needs a real click on a real emailed link — so the function is written to survive being wrong
-- about one of them. If GoTrue names the AMR method differently in some future release, the
-- audit row still lands, and vice versa.
--
-- ── WHAT MAKES THIS A PROOF AND NOT A COINCIDENCE ───────────────────────────────────────
--
-- Both facts are written by GoTrue, inside GoTrue's own transaction, only after it has matched
-- a single-use token that it emailed to the address on the account. Nothing on the phone and
-- nothing in an Edge Function can fabricate either one. The client's role shrinks to ASKING
-- for the mail; it cannot manufacture the answer.
--
-- Both are then bounded below, and the bound is the security-relevant part of this file:
--
--     the claim must be no older than the most recent link this project actually sent
--     (auth.users.recovery_sent_at — GoTrue's own timestamp for a magic-link mail)
--     AND no older than the last time this account's address changed.
--
-- The second half closes a real bypass. users_update in db/rls-policies.sql lets an account
-- holder edit their own `email`, and the guard below nulls email_verified_at when they do.
-- Without an address-change floor, a user could verify a@example.com, repoint the row at a
-- stranger's address, and have the OLD click re-read as a proof of the NEW one — which is
-- precisely the action email verification exists to prevent, since a verified account is the
-- one allowed to mint credentials into somebody's inbox.
--
-- ── WHAT DOES NOT CHANGE ────────────────────────────────────────────────────────────────
--
-- requireVerifiedEmail() in supabase/functions/_shared/verification.ts still decides what an
-- unverified account may do, and it still reads public.users.email_verified_at. The security
-- boundary is in the same place it was yesterday; only the evidence that satisfies it arrives
-- by a different route. No RLS policy is touched.
--
-- ── THE ONE THING THAT COULD NOT BE TESTED FROM HERE, AND HOW TO SETTLE IT ───────────────
--
-- Producing a magiclink login needs a real click on a real emailed link, which cannot be done
-- from a migration. So the STRINGS GoTrue writes for that login — 'magiclink' as the AMR method,
-- 'magiclink' as the audit trait — are taken from GoTrue's source vocabulary, not from this
-- project's own data. Everything around them was verified live on 2026-09-01: both tables
-- exist, mfa_amr_claims holds 'password' and 'totp', and a password login logs
-- {"action":"login","traits":{"provider":"email"}}.
--
-- If verification ever appears to hang — the link is opened, the page says confirmed, and the
-- app's banner never clears — these two queries say exactly what GoTrue wrote, and the answer
-- goes straight into the IN lists below:
--
--   select c.authentication_method, c.created_at
--     from auth.mfa_amr_claims c join auth.sessions s on s.id = c.session_id
--    where s.user_id = '<the user id>' order by c.created_at desc limit 5;
--
--   select a.payload::text, a.created_at from auth.audit_log_entries a
--    where a.payload->>'actor_id' = '<the user id>' order by a.created_at desc limit 5;
--
-- Check auth.users.recovery_sent_at for that user at the same time: a claim older than it is
-- being refused by the lower bound rather than not existing, which is a different fault.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. THE ADDRESS-CHANGE FLOOR
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Set by app.users_update_guard() at the same instant it clears email_verified_at, so the two
-- can never disagree. NULL means the address has never changed since this column existed,
-- which is true of every account on the project today.
alter table public.users
  add column if not exists email_verification_reset_at timestamptz;

comment on column public.users.email_verification_reset_at is
  'When users.email last changed, invalidating any proof attached to the old address. Read by '
  'public.email_link_proof() as the floor under a magic-link claim, so a click on the OLD '
  'address can never be re-read as a proof of the NEW one.';

comment on column public.users.email_verified_at is
  'When GoTrue accepted a confirmation link that this project emailed to users.email. NULL '
  'means unproved. Written ONLY by the email-verification Edge Function with the service role '
  '(app.users_update_guard refuses every other writer), and reset to NULL by that same trigger '
  'whenever the address changes.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. THE PROOF
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Returns WHEN the account holder last consumed a confirmation link this project sent them, or
-- NULL if they have not. SECURITY DEFINER because the auth schema is not readable by any role
-- an Edge Function client runs as; `search_path = ''` with every name qualified, so nothing on
-- the caller's path can be substituted for a table this function trusts.
--
-- STABLE and side-effect free: it decides nothing and writes nothing. The caller
-- (confirmEmailFromLink) is what turns a non-NULL answer into a stamped column, and
-- app.users_update_guard still refuses that write from anyone but the service role.
create or replace function public.email_link_proof(p_user uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  with bounds as (
    select
      -- The 10 seconds of slack absorb clock skew between GoTrue stamping recovery_sent_at in
      -- Go and Postgres defaulting created_at with now(). It is far too small to matter to the
      -- address-change floor, which is the bound that is actually load-bearing.
      greatest(
        au.recovery_sent_at - interval '10 seconds',
        coalesce(pu.email_verification_reset_at, '-infinity'::timestamptz)
      ) as since
    from auth.users au
    join public.users pu on pu.id = au.id
    -- No send, no proof. This is also what stops a brand-new account from being credited with
    -- a session it created by signing in normally.
    where au.id = p_user and au.recovery_sent_at is not null
  )
  select greatest(
    (
      select max(c.created_at)
      from auth.mfa_amr_claims c
      join auth.sessions s on s.id = c.session_id
      where s.user_id = p_user
        and c.authentication_method in ('magiclink', 'otp')
        and c.created_at >= (select since from bounds)
    ),
    (
      select max(a.created_at)
      from auth.audit_log_entries a
      where a.payload ->> 'actor_id' = p_user::text
        and a.payload ->> 'action' = 'login'
        and a.payload -> 'traits' ->> 'provider' in ('magiclink', 'otp')
        and a.created_at >= (select since from bounds)
    )
  )
  where exists (select 1 from bounds);
$$;

comment on function public.email_link_proof(uuid) is
  'When this account last consumed an emailed confirmation link, per GoTrue''s own '
  'auth.mfa_amr_claims and auth.audit_log_entries, bounded below by the last link actually '
  'sent AND by the last address change. NULL means no proof. Service role only.';

-- The Edge Function is the only caller. An authenticated user must not be able to ask this
-- about anybody — including themselves, since the answer is only meaningful next to a write
-- they are not allowed to make.
revoke all on function public.email_link_proof(uuid) from public, anon, authenticated;
grant execute on function public.email_link_proof(uuid) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. THE GUARD LEARNS THE FLOOR
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Identical to the version in db/schema.sql except for two things: clearing the proof on an
-- address change now also STAMPS the change, and the refusal no longer tells people to enter a
-- code that no longer exists anywhere in the product.
create or replace function app.users_update_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_manages_target boolean;
begin
  -- Changing the address invalidates any proof attached to the old one. This fires for EVERY
  -- writer including the service role, which is what makes scripts/rotate-super-admin.mjs safe
  -- without that script having to remember: rotating the super admin onto a new address drops
  -- the verified stamp, and the new address has to be proved like any other.
  --
  -- email_verification_reset_at is stamped in the SAME statement, because it is the floor that
  -- stops public.email_link_proof() reading the click that proved the OLD address as a proof
  -- of the new one.
  if new.email is distinct from old.email then
    new.email_verified_at := null;
    new.email_verification_reset_at := now();

  -- Otherwise the stamp moves only when the verification endpoint moves it.
  elsif new.email_verified_at is distinct from old.email_verified_at and not app.is_service_role() then
    raise exception 'Email verification cannot be granted by hand — it is earned by opening the link Nivora emails to the address.'
      using errcode = '42501';
  end if;

  -- Super Admin (and the service role, used by account-management server actions)
  -- may change anything; those paths do their own authorization first.
  if app.is_super_admin() then
    return new;
  end if;

  -- Who legitimately administers the TARGET account?
  v_manages_target :=
       (old.role in ('manager','warden') and app.owns_hostel(old.hostel_id))
    or (old.role = 'student' and app.has_role_in(old.hostel_id, 'warden'));

  -- Identity, role and tenant binding are never self-serviceable.
  if new.id is distinct from old.id then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    raise exception 'You cannot change an account''s role.' using errcode = '42501';
  end if;
  if new.hostel_id is distinct from old.hostel_id then
    raise exception 'You cannot move an account to another hostel.' using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  -- Activation state may only be changed by the account's administrator.
  if (new.status is distinct from old.status or new.deleted_at is distinct from old.deleted_at)
     and not v_manages_target then
    raise exception 'You cannot change this account''s status.' using errcode = '42501';
  end if;

  -- Remaining columns (full_name, phone, email, must_change_password):
  -- the account holder themselves, or the account's administrator.
  if new.id = auth.uid() or v_manages_target then
    return new;
  end if;
  raise exception 'Not allowed.' using errcode = '42501';
end $$;

drop trigger if exists users_update_guard on public.users;
create trigger users_update_guard before update on public.users
  for each row execute function app.users_update_guard();
