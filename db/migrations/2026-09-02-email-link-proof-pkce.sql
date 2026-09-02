-- ═════════════════════════════════════════════════════════════════════════════════════════
-- email_link_proof() READ THE WRONG TABLES. Both arms were dead; this rebuilds it on the two
-- facts a PKCE link click actually writes.
-- ═════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE MEASUREMENT THAT FORCED THIS ────────────────────────────────────────────────────
--
-- The 2026-09-01 migration guessed at the strings GoTrue writes for a magic-link login, and
-- said so in its own header: "the STRINGS GoTrue writes for that login … are taken from
-- GoTrue's source vocabulary, not from this project's own data", because producing one needs a
-- real click on a real emailed link. That click has now happened. On 2026-08-31 the product
-- owner asked for a link, opened it, and GoTrue matched the token. Read back from the live
-- project on 2026-09-02, user 10cc575f-db4b-4616-a3a8-44189122943b:
--
--   auth.users.recovery_sent_at ............ 2026-08-31 20:02:43.246+00   (the mail)
--   auth.flow_state.auth_code_issued_at .... 2026-08-31 20:03:46.999+00   (the click)
--   auth.audit_log_entries.created_at ...... 2026-08-31 20:03:46.987+00   (the click)
--   auth.mfa_amr_claims .................... NOTHING
--
--   public.email_link_proof(that user) ..... NULL
--
-- The proof existed twice over in GoTrue's own tables and the function returned NULL, which is
-- why public.users.email_verified_at is still null for the owner today. Both arms missed, each
-- for its own reason:
--
-- ARM 1, auth.mfa_amr_claims — DELETED BELOW. An AMR claim is written when a SESSION is
--   created. The app pins AuthFlowType.pkce (nivora_app/lib/main.dart), and under PKCE
--   /auth/v1/verify does not create a session: it stamps an auth code on the flow state and
--   redirects with ?code=. The session only exists once that code is exchanged for tokens by
--   the holder of the code verifier — the app, which never sees the code because the click
--   lands in a browser. No session, no claim, ever. This is not a vocabulary mistake that a
--   different string would fix; the row is never inserted.
--
--   It is not merely dead — it is also REDUNDANT wherever it does fire. Non-PKCE consumers
--   (the E2E harness verifies links server-side) DO create a session and DO write an AMR claim,
--   and on this project every account that has one also has the audit row of arm 2, written
--   6-7ms earlier:
--
--     owner.e2e1   amr 20:27:53.677   audit 20:27:53.670
--     warden.e2e1  amr 20:28:37.038   audit 20:28:37.032
--
--   So arm 2 is a superset of arm 1 on every row this project has. Keeping the join over
--   auth.sessions + auth.mfa_amr_claims buys nothing and reads as though it works.
--
-- ARM 2, auth.audit_log_entries — FIRES, but the predicate did not match it. The migration
--   required payload->'traits'->>'provider' in ('magiclink','otp'). The row GoTrue actually
--   wrote for the owner's click was:
--
--     {"action":"login","actor_id":"10cc575f-…","actor_name":"Platform Admin",
--      "actor_username":"codewithshahul@gmail.com","actor_via_sso":false,"log_type":"account"}
--
--   There is no `traits` key at all. GoTrue passes nil traits when a login comes from consuming
--   an emailed one-time token; it passes {"provider":"email"} only for a password grant. The
--   old predicate was therefore asking for the one shape this event never has.
--
-- ── WHAT REPLACES THEM ──────────────────────────────────────────────────────────────────
--
-- ARM A — auth.flow_state.auth_code_issued_at. This is the PKCE-native fact and the exact
--   counterpart of the AMR claim: GoTrue's verify handler calls RecordAuthCodeIssuedAtTime()
--   only after it has matched the single-use token it emailed. The row also names
--   `authentication_method` outright ('magiclink'), so this is a POSITIVE signal, not an
--   inference. Nothing on the phone can write it.
--
-- ARM B — auth.audit_log_entries, corrected to the shape above: action='login' with NO
--   provider trait (or one naming a link). Because "no provider trait" is a NEGATIVE signal
--   and negatives age badly, it is anchored: the login must be preceded, within the link's own
--   one-hour validity, by a `user_recovery_requested` or `user_confirmation_requested` row for
--   the same actor — i.e. by this project actually emailing that account a link. A login that
--   no link preceded is not credited, whatever it is.
--
-- Both are still written by GoTrue, inside GoTrue's own transaction, only after it matched a
-- single-use token it mailed to the address on the account. The client's role is still only to
-- ASK for the mail; it cannot manufacture either answer.
--
-- ── WHY 'recovery' COUNTS TOO, SAID OUT LOUD ────────────────────────────────────────────
--
-- On this project signInWithOtp writes recovery_sent_at and logs `user_recovery_requested`, so
-- magic links and password-reset links are the same machinery wearing different names, and arm
-- B cannot tell them apart even in principle. Rather than pretend otherwise, both count — and
-- they should: a reset link is emailed to users.email and opening it proves control of that
-- mailbox exactly as well as a magic link does. That is the whole question being asked.
--
-- ── THE FLOOR: ONE BOUND NOW, NOT TWO, AND THAT IS A BUG FIX ────────────────────────────
--
-- The old function bounded a claim below by greatest(recovery_sent_at - 10s, address-change).
-- The recovery_sent_at half is REMOVED, because it is a trap:
--
--   send link (T1) → user clicks (T2) → user reopens the verify screen, which auto-sends
--   (T3 > T2) → recovery_sent_at is now T3 → the proof earned at T2 is below the floor and is
--   discarded → "Not confirmed yet" → the user tries again, which sends again, which raises
--   the floor again. Every attempt destroys the evidence of the previous one.
--
-- Nothing is given up by dropping it. It existed to stop "a brand-new account being credited
-- with a session it created by signing in normally", and neither replacement arm can credit a
-- normal sign-in: arm A needs a magiclink/otp/recovery flow state, arm B needs a link request
-- in the hour before the login. "No send, no proof" is now carried structurally by each arm
-- instead of by a floor that also destroys real proofs.
--
-- THE ADDRESS-CHANGE FLOOR STAYS, and it is the security-relevant one. users_update in
-- db/rls-policies.sql lets an account holder edit their own email; app.users_update_guard nulls
-- email_verified_at and stamps email_verification_reset_at in the same statement. Without that
-- floor a user could verify a@example.com, repoint the row at a stranger's address, and have
-- the OLD click re-read as proof of the NEW one — which is precisely what email verification
-- exists to prevent, since a verified account is the one allowed to mint credentials into
-- somebody's inbox.
--
-- ── RETENTION, AND WHY TWO ARMS ARE STILL RIGHT ─────────────────────────────────────────
--
-- Measured on the live project 2026-09-02: auth.flow_state holds rows back to 2026-08-24
-- (8 days), auth.audit_log_entries only back to 2026-08-31 17:23 (hours). GoTrue prunes both on
-- its own schedule and neither is ours to configure. That costs nothing here — the window that
-- matters is from the click to the next `status` call, which the app issues every time it
-- returns to the foreground, i.e. seconds — but it is the reason two independent arms are worth
-- keeping rather than one.
--
-- ── VERIFYING THIS AGAINST THE LIVE PROJECT ─────────────────────────────────────────────
--
--   select u.email, public.email_link_proof(u.id) from public.users u order by u.email;
--
-- Expected after this migration, from the data as it stood on 2026-09-02:
--   codewithshahul@gmail.com  2026-08-31 20:03:46.999+00   (arm A, the owner's real click)
--   owner.e2e1@example.com    2026-08-31 20:27:53.670+00   (arm B, server-side verify)
--   warden.e2e1@example.com   2026-08-31 20:28:37.032+00   (arm B)
--   manager.e2e1@…, student.e2e1@…   NULL                  (never consumed a link)

create or replace function public.email_link_proof(p_user uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  with floor_at as (
    -- The ONE bound. NULL means the address has never changed, which is true of every account
    -- on the project today; -infinity then admits any click, which is correct — verification
    -- does not expire, it is invalidated by an address change.
    select coalesce(pu.email_verification_reset_at, '-infinity'::timestamptz) as since
    from public.users pu
    where pu.id = p_user
  )
  select greatest(
    -- ARM A — the PKCE flow state. Stamped by GoTrue's verify handler at the instant it
    -- matched the emailed token, and it names the method itself.
    (
      select max(f.auth_code_issued_at)
      from auth.flow_state f
      where f.user_id = p_user
        and f.authentication_method in ('magiclink', 'otp', 'recovery')
        and f.auth_code_issued_at is not null
        and f.auth_code_issued_at >= (select since from floor_at)
    ),
    -- ARM B — the audit row, in the shape GoTrue actually writes: a login with no provider
    -- trait. Anchored to a link this project emailed within the preceding hour, so that a
    -- login of some other kind that also happens to carry no provider trait is not credited.
    (
      select max(a.created_at)
      from auth.audit_log_entries a
      where a.payload ->> 'actor_id' = p_user::text
        and a.payload ->> 'action' = 'login'
        and coalesce(a.payload -> 'traits' ->> 'provider', 'link')
              in ('link', 'magiclink', 'otp')
        and a.created_at >= (select since from floor_at)
        and exists (
          select 1
          from auth.audit_log_entries r
          where r.payload ->> 'actor_id' = p_user::text
            and r.payload ->> 'action'
                  in ('user_recovery_requested', 'user_confirmation_requested')
            and r.created_at <= a.created_at
            -- GoTrue's default OTP_EXP. A link older than its own validity cannot be the one
            -- that produced this login.
            and r.created_at >= a.created_at - interval '1 hour'
        )
    )
  )
  where exists (select 1 from floor_at);
$$;

comment on function public.email_link_proof(uuid) is
  'When this account last consumed a confirmation link this project emailed it, read from '
  'GoTrue''s own auth.flow_state.auth_code_issued_at (the PKCE flow the app uses) and '
  'auth.audit_log_entries (every flow), bounded below by the last address change. NULL means '
  'no proof. Service role only.';

-- Unchanged, restated because create-or-replace does not re-run them and this file must be
-- safe to apply on its own.
revoke all on function public.email_link_proof(uuid) from public, anon, authenticated;
grant execute on function public.email_link_proof(uuid) to service_role;
