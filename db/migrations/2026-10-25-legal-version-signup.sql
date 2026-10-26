-- ─────────────────────────────────────────────────────────────────────────────
--
--   ███  THIS MIGRATION MUST LAND ON LIVE BEFORE ANY WEBSITE PUSH OR APP BUILD  ███
--   ███  CARRYING THE LEGAL VERSION '2026-10-25'.                               ███
--
--   public.accept_legal_terms() refuses a version that is not in this table, and at the
--   consent gate the only thing a person may do is agree. A build or a website deploy that
--   carries '2026-10-25' before this row exists strands every one of its users there: Agree
--   fails with 22023 "Unknown legal document version 2026-10-25." Builds and pages carrying
--   '2026-10-17' are unaffected either way. Inserting the row early is harmless.
--
--   Order: (1) apply this file to nimxvgzscbanhtvgnjll and run the check at the bottom;
--          (2) push the website, whose pages carry LEGAL_VERSION = '2026-10-25';
--          (3) only then build, upload or hand round any app build with kLegalVersion
--              '2026-10-25'.
--   It does not depend on 2026-10-25-self-signup-onboarding.sql and may go first or after it,
--   but both must be live before a 1.3.0 build reaches anybody.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LEGAL VERSION 2026-10-25: SELF SIGN-UP, PHOTOS, IDENTITY DOCUMENTS, NEARBY SEARCH, PLANS
--
-- docs/self-signup-onboarding-spec.md Flow 10. What changed, in lib/legal-config.ts,
-- app/legal/** and the app's bundled copy in apnivaas_app/lib/features/legal/legal_documents.dart:
--   · Privacy, how accounts work: owners and tenants may now create their own account in the
--     Android app (Google; Facebook and Truecaller only once those buttons are switched on);
--     staff accounts are still made only by an owner, and the database refuses the rest.
--     For an account you create yourself, ShaReshi Tech is the Data Fiduciary until a PG
--     accepts you;
--   · Privacy, what is collected: gender, date of birth and an emergency contact (from the
--     tenant's own details form); a profile photo for every role; identity documents a person
--     uploads themselves; the Facebook or Truecaller ID and what those services share; join
--     requests; demo requests; plan payments; the PG's address and optional map position;
--   · Privacy, what is never collected: "no date of birth" and "no location" are withdrawn;
--     approximate location is used once for "PGs near you" and is not stored. The permission
--     count goes from ten to eleven (ACCESS_COARSE_LOCATION);
--   · Privacy, photos and documents: who can see a profile photo and an identity document,
--     the one-minute link, and how they are deleted;
--   · Privacy, recipients: Razorpay's entry gains plan payments; Meta (Facebook) and Truecaller
--     are listed as recipients only when those sign-in options are offered and chosen;
--   · Privacy, retention: join requests (pending ones lapse after 30 days, answered ones are
--     deleted 180 days after the answer), demo requests (180 days after the slot), photos and
--     documents (with the account; abandoned uploads after a day), plan payments (kept, as
--     money records); a self-made account survives leaving a PG;
--   · Terms: self sign-up and who may use it (18 or over), the free first month, plan prices
--     from the app, server-verified activation, no automatic renewal, demo requests and join
--     requests.
-- What did NOT change: no right, no contact, no shorter protection, no data sold or used for
-- advertising.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-10-25',
  -- 2026-10-25 00:00 IST, matching app.today()'s Asia/Kolkata day boundary, as with every prior row.
  '2026-10-24 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'Owners and tenants can now create their own account in the app. Every account can add a profile '
  'photo, and tenants can add identity documents, a date of birth and an emergency contact; the owner '
  'and wardens of a PG you ask to join can see your photo and documents. "PGs near you" uses your '
  'approximate location once and does not store it, so the app now asks for one more permission. '
  'Owners can pay for a plan through Razorpay and book a free demo. The policy says who sees each of '
  'these and how long they are kept.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;

-- ═══ AFTER APPLYING ═══
-- Seven rows, the newest '2026-10-25', and every acceptance still pointing at the text it was
-- taken against:
--
--   select version, effective_at from public.legal_versions order by version;
--   select version, count(*) from public.legal_acceptances group by version order by version;
--
-- Expected before this file: 2026-09-02, 2026-09-04, 2026-09-12, 2026-09-13, 2026-10-12, 2026-10-17.
