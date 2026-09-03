-- ─────────────────────────────────────────────────────────────────────────────
-- THE SHORTER TERMS AND PRIVACY POLICY, PUBLISHED
--
-- The wording changed on 2026-09-04: on the published pages the Terms went from 18 numbered
-- sections to 8 and the Privacy Policy from 18 to 10 (the copy bundled in the app, which carries
-- the same text without the numbering, went 14 → 8 and 15 → 10), and the grievance contact
-- stopped naming a person and a street. Because the TEXT changed, the version string changed
-- with it — and that is not bookkeeping. The app's
-- consent gate compares the version it ships against the versions a user has accepted, so a bump
-- re-asks everyone. Being re-asked is the point: nobody should be recorded as having agreed to
-- text they were never shown.
--
-- ── THIS MIGRATION MUST LAND BEFORE ANY BUILD CARRYING THE NEW STRING ────────────────────────
--
-- public.accept_legal_terms() REFUSES a version that is not in this table. An APK shipping
-- '2026-09-04' against a database that only knows '2026-09-02' does not degrade gracefully: the
-- gate is the first thing after sign-in and the only thing a user may do there is agree, so the
-- refusal turns it into a dead end for EVERY user at once. The deployment order is therefore
-- migration first, build second — the note on LEGAL_VERSION in lib/legal-config.ts says the same
-- thing from the other side.
--
-- The old row is kept. It is the text people actually agreed to before today, and
-- public.legal_acceptances references it; deleting it would orphan every existing consent record
-- and destroy the evidence the table exists to hold.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-09-04',
  -- 2026-09-04 00:00 IST. The app's day boundary is Asia/Kolkata everywhere else (app.today()),
  -- and a policy that takes effect at a moment nobody in India recognises is a policy with a
  -- confusing date on it.
  '2026-09-03 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'Shortened both documents — Terms 18 sections to 8, Privacy 18 to 10 — by merging overlapping '
  'sections and removing repetition. No commitment was weakened; three claims were corrected '
  'rather than kept: complaints age from when they are raised (not resolved), the published '
  'retention periods that app.apply_retention() does not enforce were removed instead of '
  'restated, and GitHub was added to the app copy''s list of processors because it holds the '
  'nightly encrypted backup. The GDPR/UK GDPR section was removed as inapplicable to an Indian '
  'PG product. The grievance contact is now a role and a monitored mailbox rather than a named '
  'individual and a street address, which is what the DPDP Act and Play both actually require.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;

-- ═══ AFTER APPLYING ═══
-- Both rows present, and every acceptance still pointing at the text it was taken against:
--
--   select version, effective_at from public.legal_versions order by version;
--   select version, count(*) from public.legal_acceptances group by version order by version;
