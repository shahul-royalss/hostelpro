-- ─────────────────────────────────────────────────────────────────────────────
-- LEGAL VERSION 2026-09-13: THE APP'S COPY OF THE POLICY CATCHES UP WITH THE PUBLISHED ONE
--
-- Version 2026-09-12 fixed the published privacy policy for push notifications, but the copy
-- bundled in the Android app — the text a person is shown at the consent gate and recorded as
-- having agreed to — was only partly corrected. A Play compliance audit on 2026-09-13 found it
-- still said the app declares four Android permissions ("Those four are the whole list") when
-- the build declares ten, including the camera and notifications, and still named Google only
-- for account email. Two documents carried the same version string and said different things.
--
-- The same audit found that the Razorpay checkout on Android runs INSIDE the app, not in a web
-- iframe as the policy's reasoning assumed. While a payment is open it handles the card or UPI
-- details the person types and checks which UPI apps are installed so it can offer them. Play
-- counts data an in-app SDK collects as collected by the app, so the Data safety form and both
-- documents now say so.
--
-- WHY THE VERSION MOVES AGAIN. The wording of both documents changes, so every person is asked
-- once more; nobody should be recorded as agreeing to a permission list the app does not match.
--
-- ── THIS MIGRATION MUST LAND BEFORE ANY BUILD OR DEPLOY CARRYING '2026-09-13' ─────────────────
-- public.accept_legal_terms() refuses a version that is not in this table, and at the consent
-- gate the only thing a person may do is accept — so the wrong order locks everyone out.
-- Earlier rows are kept: they are the text people actually agreed to, and legal_acceptances
-- references them.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-09-13',
  -- 2026-09-13 00:00 IST, matching app.today()'s Asia/Kolkata day boundary.
  '2026-09-12 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'The copy of the privacy policy inside the app now matches the published one. It lists the ten '
  'Android permissions the app declares, including the camera and notifications, where it '
  'previously said there were four, and names Google as the service that delivers push '
  'notifications, receiving the device token and each notification''s title and body. Both '
  'documents now say that the Razorpay checkout runs inside the app on Android and, while a '
  'payment is open, handles the card or UPI details you type and checks which UPI apps are '
  'installed so it can offer them; Nivora still never receives those details. The privacy policy '
  'also describes the in-app route for requesting account deletion. No retention period was '
  'lengthened and no new use of data was introduced.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;

-- ═══ AFTER APPLYING ═══
--   select version, effective_at from public.legal_versions order by version;
