-- Legal version 2026-11-04 (Cashfree rent, docs/cashfree-rent.md). Same shape as 2026-11-01-legal-version-round6.sql.
-- Apply after 2026-11-04-cashfree-rent.sql and once the privacy policy and terms pages carry the new text.
-- Undo: 2026-11-04-legal-version-cashfree.down.sql (only while nobody has accepted it).

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-11-04',
  -- 2026-11-04 00:00 IST, matching app.today()'s Asia/Kolkata day boundary.
  '2026-11-03 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'Rent paid in the app for most PGs now goes through Cashfree Payments, which settles it straight to the PG '
  'owner''s own UPI ID. Paying tenants give Cashfree their name, phone and email; owners who turn on online '
  'rent give Cashfree their legal name, email, phone, UPI ID and PAN (and GSTIN if they have one) so Cashfree '
  'can verify and pay them. Apnivaas keeps the UPI ID and only the last four characters of the PAN. Razorpay '
  'stays only for the PGs that keep it and for owners'' plan payments.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at, terms_url = excluded.terms_url,
      privacy_url = excluded.privacy_url, summary = excluded.summary;
