-- ─────────────────────────────────────────────────────────────────────────────
-- THE POLICY CATCHES UP WITH PUSH NOTIFICATIONS
--
-- On 2026-09-12 the app started sending push notifications: it registers a Firebase Cloud
-- Messaging token against the signed-in user (public.push_devices), and supabase/functions/
-- push-send posts each notification's title and body to Google to have it delivered.
--
-- Both documents said the opposite. The published privacy policy carried the sentence "No push
-- notifications. Notifications appear inside the app when you open it. The Android build
-- registers no device token with any notification service.", and the copy bundled in the app
-- carried its own wording of the same denial. Every clause of it became false the moment the
-- feature shipped, and the app copy is the worse of the two — it is the text a person is shown
-- at the consent gate and recorded as having agreed to.
--
-- WHY THE VERSION MOVES. Nothing here is bookkeeping. A new category of personal data (the device
-- token) and a new purpose for an existing sub-processor (Google, which already carried account
-- email and now also carries notification content) are material changes by the rule the policy
-- itself publishes. The consent gate compares the version an app build ships against the versions
-- a user has accepted, so bumping re-asks everyone — which is the point. Nobody should be
-- recorded as having agreed to a guarantee that the software stopped honouring.
--
-- ── THIS MIGRATION MUST LAND BEFORE ANY BUILD CARRYING '2026-09-12' ──────────────────────────
--
-- public.accept_legal_terms() REFUSES a version that is not in this table. An APK shipping
-- '2026-09-12' against a database that only knows '2026-09-04' does not degrade gracefully: the
-- gate is the first thing after sign-in and the only thing a user may do there is agree, so the
-- refusal turns it into a dead end for EVERY user at once. Migration first, build second.
--
-- Note for this particular release: dist/NIVORA-1.0.0.aab as built earlier on 2026-09-12 carries
-- '2026-09-04' and the old denial, so it is consistent with the database but ships a privacy
-- policy that contradicts its own behaviour. It must be rebuilt before it is uploaded, and the
-- rebuild is what makes this row necessary.
--
-- The old rows are kept. They are the text people actually agreed to before today, and
-- public.legal_acceptances references them; deleting one would orphan every consent record taken
-- against it and destroy the evidence the table exists to hold.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-09-12',
  -- 2026-09-12 00:00 IST, matching app.today()'s Asia/Kolkata boundary, as with every prior row.
  '2026-09-11 18:30:00+00',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'Push notifications shipped, and both documents were corrected to describe them. The previous '
  'text guaranteed that no push notifications were sent and that the app registered no device '
  'token anywhere; the app now registers a Firebase Cloud Messaging token when you sign in on a '
  'phone, and rent reminders, notices, payment confirmations and assigned tasks are delivered '
  'through it. Three disclosures were added: the device token is listed among the personal data '
  'held, with its retention (released at sign-out, deleted with the account, dropped after 90 '
  'days unused); Google is named as the sub-processor that receives the token together with each '
  'notification''s title and body; and the Android permission list was corrected from four '
  'entries to the ten the build actually declares. The permission correction also disclosed '
  'CAMERA, which the app has requested since before this feature and which the previous text '
  'omitted. No commitment was weakened and no retention period lengthened.'
)
on conflict (version) do update
  set effective_at = excluded.effective_at,
      terms_url    = excluded.terms_url,
      privacy_url  = excluded.privacy_url,
      summary      = excluded.summary;

-- ═══ AFTER APPLYING ═══
-- All three rows present, and every acceptance still pointing at the text it was taken against:
--
--   select version, effective_at from public.legal_versions order by version;
--   select version, count(*) from public.legal_acceptances group by version order by version;
