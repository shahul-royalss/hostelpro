-- ─────────────────────────────────────────────────────────────────────────────
-- DEMO PG (PLAY REVIEW): DEMO ACCOUNTS DO NOT OWE AN EMAIL PROOF — TEMPORARY
--
-- WHY. An email address is proved by opening a link mailed to it; the proof is
-- public.users.email_verified_at, written by the email-verification Edge Function. The Play review
-- accounts use demo.*@nivora.app addresses whose mail nobody reads, so an account created with one
-- can never produce that proof, and two things then stop a reviewer:
--
--   · requireVerifiedEmail() (supabase/functions/_shared/verification.ts) refuses an unverified
--     caller in owner-create-staff, warden-register-student, warden-student-credentials and
--     sa-create-owner;
--   · a new staff account, after its first password change, is sent to a verify-email screen that
--     cannot be dismissed (nivora_app/lib/features/auth/change_password_screen.dart,
--     VerifyEmailScreen.route(blocking: true)).
--
-- demo.owner, demo.warden and the demo resident were stamped on 2026-09-04 and are unaffected. The
-- account this exists for is demo.manager@nivora.app, which the owner creates in the app — a
-- one-off UPDATE cannot cover an account that does not exist yet, and users_update_guard refuses a
-- hand-written stamp to everything but the service role anyway.
--
-- WHAT IT DOES. Stamps email_verified_at on a public.users row only when ALL of these hold:
--   · hostel_id is Demo PG (d3300000-0000-4000-8000-000000000001), the fabricated review hostel;
--   · the address is demo.<something>@nivora.app;
--   · the row is not already stamped;
--   · on UPDATE, the address itself changed (users_update_guard has just nulled the stamp).
-- Every real hostel, and every other address inside Demo PG, owes the proof exactly as before. No
-- app or Edge Function code changes: both already read this column.
--
-- ORDER. Row triggers on the same event fire in name order. `users_zz_…` sorts after
-- `users_update_guard`, so on an address change the guard clears the stamp first and this sets it
-- again, and the guard's refusal of a hand-written stamp is evaluated before this trigger runs.
--
-- TEMPORARY, AND DELIBERATELY NOT FOLDED INTO db/schema.sql. Remove it after review:
--
--   drop trigger if exists users_zz_demo_review_email_verified on public.users;
--   drop function if exists app.demo_review_email_verified();
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function app.demo_review_email_verified() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.email_verified_at is not null
     or new.hostel_id is distinct from 'd3300000-0000-4000-8000-000000000001'::uuid
     or lower(btrim(coalesce(new.email, ''))) not like 'demo.%@nivora.app' then
    return new;
  end if;

  -- OLD exists only on UPDATE; checked separately so the INSERT path never reads it.
  if tg_op = 'UPDATE' then
    if new.email is not distinct from old.email then
      return new;
    end if;
  end if;

  new.email_verified_at := now();
  return new;
end $$;

revoke all on function app.demo_review_email_verified() from public;

drop trigger if exists users_zz_demo_review_email_verified on public.users;
create trigger users_zz_demo_review_email_verified
  before insert or update of email on public.users
  for each row execute function app.demo_review_email_verified();

-- ═══ AFTER APPLYING ═══
--   select tgname from pg_trigger
--    where tgrelid = 'public.users'::regclass and not tgisinternal order by tgname;
--   -- expect users_zz_demo_review_email_verified to sort after users_update_guard
