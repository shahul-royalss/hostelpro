-- ─────────────────────────────────────────────────────────────────────────────
--
--   ███  THIS MIGRATION MUST LAND ON LIVE BEFORE ANY WEBSITE PUSH OR APP BUILD  ███
--   ███  CARRYING THE LEGAL VERSION '2026-10-12'.                               ███
--
--   public.accept_legal_terms() refuses a version that is not in this table, and at the
--   consent gate the only thing a person may do is agree. An Apnivaas 1.2.0 build that reaches
--   anybody before this row exists strands EVERY one of its users on that screen: Agree fails
--   with 22023 "Unknown legal document version 2026-10-12." and Sign out is the only way off.
--   Older builds (1.0.0, 1.1.0) record against '2026-09-13' and are unaffected either way.
--
--   Order: (1) apply this file to nimxvgzscbanhtvgnjll and run the check at the bottom;
--          (2) push the website, whose pages carry LEGAL_VERSION = '2026-10-12';
--          (3) only then build, upload or hand round any app build with kLegalVersion
--              '2026-10-12'. The whole release order is docs/play-console-submission.md, Step 5.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LEGAL VERSION 2026-10-12: THE PRODUCT IS RENAMED APNIVAAS, AND THE OPERATOR IS NAMED
--
-- On 2026-10-12 the owner renamed the product from Nivora to Apnivaas (release 1.2.0). Both
-- documents named the product throughout, and both named "NIVORA" as the operator — the party
-- the Terms bind and the entity the privacy policy says is responsible. "NIVORA" was a product
-- name, not a legal entity (docs/legal-consent.md §6 already said so), and after the rename it
-- would have named neither the app on the Play listing (Apnivaas) nor the developer shown there
-- (ShaReshi Tech). Play's User Data policy wants the policy to name that entity.
--
-- What changed in the text, in lib/legal-config.ts, app/legal/** and the app's bundled copy in
-- nivora_app/lib/features/legal/legal_documents.dart:
--   · every mention of the product reads Apnivaas;
--   · the operator is ShaReshi Tech: section 1 of the privacy policy names it and says that
--     "Apnivaas", "we" and "us" mean it, the Terms are between it and the user, both contact
--     blocks print it, and the web copyright line is in its name;
--   · the web pages take the product name from lib/legal-config.ts instead of the
--     NEXT_PUBLIC_APP_NAME hosting variable, so a dashboard setting can no longer rewrite
--     published legal text without a commit and a version bump.
-- What did NOT change: no new category of data, no new recipient, no retention period, no
-- permission, no right, and the contact mailbox, support@nivora.dhrishtaerf.org, is the same.
-- The URLs below are unchanged too — old builds print them, and Play's privacy-policy and
-- account-deletion fields point at them.
--
-- WHY THE VERSION MOVES ANYWAY. The rule both documents publish is "change the wording → bump",
-- and changing who the operator is counts as material by any reading. Skipping the bump would
-- leave two different texts under '2026-09-13', and every acceptance recorded from 1.2.0 would
-- point at words nobody published. The bump also shows everybody the renamed documents once,
-- the first time they open 1.2.0, which is the one-time privacy notice the owner asked for.
--
-- Earlier rows are kept, including 2026-09-13's summary that still says "Nivora": they record
-- exactly what people agreed to, and public.legal_acceptances references them.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-10-12',
  -- 2026-10-12 00:00 IST, matching app.today()'s Asia/Kolkata day boundary, as with every prior row.
  '2026-10-11 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'The app is now called Apnivaas; it was called Nivora. Both documents use the new name and '
  'name ShaReshi Tech as the operator that provides the service and answers privacy, grievance '
  'and deletion requests. Requests still go to the same mailbox, support@nivora.dhrishtaerf.org. '
  'Nothing new is collected, nobody new receives any data, and no retention period is longer.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;

-- ═══ AFTER APPLYING ═══
-- Five rows, the newest '2026-10-12', and every acceptance still pointing at the text it was
-- taken against:
--
--   select version, effective_at from public.legal_versions order by version;
--   select version, count(*) from public.legal_acceptances group by version order by version;
--
-- Live on 2026-10-12, before this file: 2026-09-02, 2026-09-04, 2026-09-12, 2026-09-13.
