-- Legal version 2026-10-31 (round 5, docs/round5-api.md). Same shape as 2026-10-26-legal-version-round3.sql.
-- Apply after 2026-10-31-round5.sql and once the privacy policy and terms pages carry the new text.
-- Undo: 2026-10-31-legal-version-round5.down.sql (only while nobody has accepted it).

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-10-31',
  -- 2026-10-31 00:00 IST, matching app.today()'s Asia/Kolkata day boundary.
  '2026-10-30 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'Managers and wardens can now sign in with Continue with Google, and with Continue with Facebook, '
  'which works through the Facebook app on your phone with its event logging and advertising ID switched off. '
  'Platform administrators still sign in only with their password and second factor. Signing up no longer '
  'asks for your city or pincode. The language you choose stays on your phone. A PG''s page now shows how many '
  'beds are free in each room type, as a count only.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;
