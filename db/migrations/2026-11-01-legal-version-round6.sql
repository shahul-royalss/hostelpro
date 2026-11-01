-- Legal version 2026-11-01 (round 6, docs/round6-api.md). Same shape as 2026-10-31-legal-version-round5.sql.
-- Apply after 2026-11-01-round6.sql and once the privacy policy and terms pages carry the new text.
-- Undo: 2026-11-01-legal-version-round6.down.sql (only while nobody has accepted it).

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-11-01',
  -- 2026-11-01 00:00 IST, matching app.today()'s Asia/Kolkata day boundary.
  '2026-10-31 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'A listed PG''s page now shows the map pin its owner placed, which you can open in Google Maps, and says '
  'only whether a bed is free, never how many. Maps in the app come from Esri (satellite) and OpenStreetMap, '
  'which see your phone''s IP address and the part of the map on screen. Continue with Truecaller works '
  'through the Truecaller app, and the app declares one more Android permission for it (fourteen in all), '
  'which only asks the Truecaller app whether you are signed in to it. Google Play tells the app when a newer '
  'version is available.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;
