-- Legal version 2026-10-26 (round 3, docs/round3-spec.md R10). Same shape as 2026-10-25-legal-version-signup.sql.
-- Apply after 2026-10-26-round3.sql and once the privacy policy and terms pages carry the new text.
-- Undo: 2026-10-26-legal-version-round3.down.sql (only while nobody has accepted it).

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-10-26',
  -- 2026-10-26 00:00 IST, matching app.today()'s Asia/Kolkata day boundary.
  '2026-10-25 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'You can now sign up with your email and a password, and staff can sign up and ask to join a PG. '
  'Owners can store the exact location of their PG; "PGs near you" uses your precise location once and '
  'does not store it. The optional fingerprint or face lock works only on your phone. PG photos, '
  'descriptions and tenant reviews are shown to signed-in people looking for a PG. Tenants can request '
  'a check-out, and can pay rent by UPI straight to the owner: Apnivaas stores the UTR you enter but '
  'never holds that money. When an account is permanently deleted, payment records, receipts and dues are kept, '
  'marked "Deleted user", for legal and accounting reasons.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;
