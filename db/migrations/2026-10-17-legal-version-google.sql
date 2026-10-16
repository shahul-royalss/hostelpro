-- ─────────────────────────────────────────────────────────────────────────────
--
--   ███  THIS MIGRATION MUST LAND ON LIVE BEFORE ANY WEBSITE PUSH OR APP BUILD  ███
--   ███  CARRYING THE LEGAL VERSION '2026-10-17'.                               ███
--
--   public.accept_legal_terms() refuses a version that is not in this table, and at the
--   consent gate the only thing a person may do is agree. A build or a website deploy that
--   carries '2026-10-17' before this row exists strands every one of its users there: Agree
--   fails with 22023 "Unknown legal document version 2026-10-17." Builds and pages carrying
--   '2026-10-12' (Apnivaas 1.2.0) are unaffected either way. Inserting the row early is harmless.
--
--   Order: (1) apply this file to nimxvgzscbanhtvgnjll and run the check at the bottom;
--          (2) push the website, whose pages carry LEGAL_VERSION = '2026-10-17';
--          (3) only then build, upload or hand round any app build with kLegalVersion
--              '2026-10-17'. docs/google-sign-in.md §3 has the whole Google order.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LEGAL VERSION 2026-10-17: "CONTINUE WITH GOOGLE"
--
-- Owners and residents whose login is an email address that is also a Google account may sign in
-- with Google instead of their password (docs/google-sign-in.md). That is a new source of data and
-- a new job for a company the policy already lists, so the wording changes and the version moves.
--
-- What changed, in lib/legal-config.ts, app/legal/** and the app's bundled copy in
-- apnivaas_app/lib/features/legal/legal_documents.dart:
--   · Privacy, how accounts work: owners and residents may use Continue with Google; managers,
--     wardens and platform administrators cannot, and the database refuses it;
--   · Privacy, what is collected: a new row — the Google account ID, and the name, email address
--     and profile photo link Google shares at sign-in, kept with the login and used only for it;
--   · Privacy, recipients: Google's entry gains its third job, confirming who you are at sign-in
--     (it learns that you signed in to this app). Still five companies; Google was already one;
--   · Terms, your account: the same sentence about Continue with Google, and keeping that Google
--     account secure alongside the password.
-- What did NOT change: no new recipient, no retention period, no right, no contact. Nothing is
-- posted to anybody's Google account and nothing else is read from it.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-10-17',
  -- 2026-10-17 00:00 IST, matching app.today()'s Asia/Kolkata day boundary, as with every prior row.
  '2026-10-16 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'Owners and residents can now sign in with Continue with Google instead of a password. If you '
  'use it, Google confirms who you are and shares your Google account ID, name, email address and '
  'profile photo link, which are kept with your login and used only to sign you in. Staff accounts '
  'cannot use it. Nothing else changes: no new company receives data and no retention period is longer.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;

-- ═══ AFTER APPLYING ═══
-- Six rows, the newest '2026-10-17', and every acceptance still pointing at the text it was
-- taken against:
--
--   select version, effective_at from public.legal_versions order by version;
--   select version, count(*) from public.legal_acceptances group by version order by version;
--
-- Expected before this file: 2026-09-02, 2026-09-04, 2026-09-12, 2026-09-13, 2026-10-12.
