# Round 6 API (2026-11-01)

Migration `db/migrations/2026-11-01-round6.sql` (undo `.down.sql`, tests `.test.sql`).

## `st_pg_profile(p_hostel_id uuid) → jsonb` (changed)
- Removed: `beds_total`, `beds_free`, `free_by_sharing`.
- Added: `beds_available` (boolean): whether any bed in the PG is free. Never a count.
- Added: `latitude`, `longitude` (numeric, 6 decimals, or null): the owner's map pin.
- Unchanged: who may read it (`app.can_view_pg`: a listed, active PG with a running plan, or one's
  own PG), and no street address or owner contact.

## `st_browse_hostels() → table` (new)
Same columns as `st_search_hostels` (`distance_km` is null). Listed, active PGs with a running plan,
most reviewed first, 25 at most. Tenant accounts only (`42501` otherwise); shares the
`hostel_search` rate limit (120 an hour). `authenticated` only; not `anon`.

## Unchanged on purpose
`st_request_join` still refuses a tenant who already lives in a PG ("Ask your PG owner to remove you
before joining another."). Joined tenants browse only (owner's decision, 2026-11-01).

## App side
- Owner pin: `ow_update_pg_profile` and the sign-up PG step already take latitude/longitude; the app
  now sets them from a satellite map picker (`features/common/map_pin.dart`).
- Tenant: the PG page shows the pin and opens it in the Google Maps app (`geo:` intent, MainActivity
  `apnivaas/apps` → `openMap`). Never a browser.
- Update popup: MainActivity `apnivaas/apps` → `checkUpdate` (Play in-app update info) and
  `openStore` (`market://details?id=com.nivorasr.app` in the Play Store app).
