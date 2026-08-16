# DECISIONS.md — choices made where CLAUDE_2.md was silent or needed interpretation

Each entry: what was decided, why, and where it lives. Newest at the bottom.

## Stack

1. **Next.js 15.5 (App Router) + React 19 + TypeScript, Tailwind CSS 3.4 (`tailwind.config.ts`)** — the spec asks for tokens in `tailwind.config.ts` (§10.3), so Tailwind v3 was chosen over v4's CSS-first config. shadcn primitives are hand-adapted in `components/ui/*` (new-york style, `cssVariables: false`) so every control uses the DESIGN.md tokens directly (navy/teal/sage/sand/red, 20px cards, 12px controls).
2. **Icons: `lucide-react`** — DESIGN.md §1 says "thin-line, rounded (Lucide style)"; the Stitch exports used Material Symbols, which we replaced when rebuilding.
3. **`@supabase/ssr` 0.12** (bumped from 0.6 — its types were incompatible with supabase-js 2.112's new dist layout).
4. **Charts: Recharts 2.15** wrapped in `components/shared/charts.tsx` so every chart shares the palette (navy main / teal comparison / red expenses, rounded bars, dashed light grid).

## Auth & accounts

5. **Students sign in with their phone number.** Supabase Auth requires an email, so we map `phone → <10digits>@student.hostelpro.local` deterministically (`lib/utils.ts: studentLoginEmail`). The login form accepts email or phone and resolves it client-blind on the server (`resolveLoginEmail`). The student's real email (optional) is stored on `students.email` only.
6. **`public.users.id = auth.users.id`.** Profile rows are inserted explicitly by the server (service role) right after `auth.admin.createUser`; on failure the auth user is deleted (no orphaned logins). `role`, `hostel_id`, `must_change_password` are also mirrored into `app_metadata` for convenience, but **the DB row is the source of truth** (JWTs lag until refresh) — middleware reads `public.users` on every request.
7. **Generated passwords** are word-number-word (`Sage-7413-Kite`), returned once from the server action and shown in `CredentialsDialog` (copy buttons, must tick "I've saved these" to close). Nothing is stored in plaintext.
8. **Deactivation** = `users.status='inactive'` + Supabase auth ban (`ban_duration`), so a live session cannot continue. Vacating a student deactivates their login.
9. **"Forgot password?"** on the login screen is intentionally not a self-service flow (no email/SMS in v1, §7); admins regenerate passwords instead.

## Data model additions (beyond §5)

10. **`beds.hostel_id`** (denormalised) so bed RLS/queries don't need a join. `students.bed_id` is the **source of truth**; triggers keep `beds.status/student_id` in sync and block direct bed edits.
11. **`complaint_events`** table (auto-filled by trigger) gives students a real status timeline (§6.5) instead of inferring it from timestamps.
12. **`notifications`** table (§7 in-app notifications) — rows are created **only by DB triggers** (announcement fan-out by audience, task assigned/updated, complaint status change, leave decision, fee recorded, subscription expiring/renewed). The bell polls `rpc_unread_count` every 60 s.
13. **`hostels.rules`** text + `ow_update_hostel_rules()` for the §6.5 "hostel rules" nice-to-have. `hostels.beds_per_room_default` records the scaffold default (3).
14. **Subscription history** = one row per period; renewals insert a new row starting at the previous `end_date` (`sa_renew_subscription`). Effective status is always computed live from `max(end_date)` (`app.subscription_state`) so read-only enforcement never depends on a cron. `refresh_subscription_statuses()` also syncs the stored `status` column + `hostels.status='readonly'` and notifies owners entering the 15-day window; it is called on Super Admin / Owner dashboard loads.

## Hard rules → where enforced (server-side)

| Rule | DB (schema.sql / rls-policies.sql) | App |
|---|---|---|
| §4.1 one subscription ↔ one hostel | `sa_create_hostel_with_subscription()` creates hostel + subscription + scaffold atomically | SA wizard calls it after creating the owner auth user |
| §4.2 scaffold floors→rooms→beds | `scaffold_hostel()` — rooms spread evenly, numbered `floor*100+n` (or `*1000` when >99 rooms/floor), 3 beds default; `rooms_capacity_sync` trigger adds/removes free beds when the warden edits capacity; only SA can insert/delete rooms/floors | Warden room-edit UI only exposes room number + capacity |
| §4.3 role limits 1/1/10,000 | `enforce_role_limits` trigger on `users` (friendly `raise exception`) | Owner staff page shows disabled "Add" when a slot is filled; toast surfaces the DB message |
| §4.4 subscription lifecycle / read-only | every write policy uses `app.hostel_writable()`; RPCs re-check it | `assertWritable(ctx)` in server actions, `SubscriptionBanner` in both shells, buttons disabled when `!ctx.writable` |
| §4.5 tenant isolation | every table has `hostel_id`; `app.can_read_hostel()` / `has_role_in()` in all policies; helper fns are `SECURITY DEFINER` w/ fixed `search_path` | `getHostelContext()` binds the session to one hostel; owners switch via cookie validated against `hostels.owner_user_id` |
| §4.6 announcement audience | `announcements_select` policy filters by audience & role; trigger fans out notifications | Composer segmented pills; feeds read through RLS |
| §4.7 one student per bed | partial unique indexes + `students_bed_guard` trigger | Register/reassign UIs only list free beds; DB error surfaced on races |
| §4.8 students see only roommates' name+phone | student `students_select` policy = own row only; roommates via `st_my_roommates()` returning name/phone/bed only | `/student/room` |
| §4.9 generated password, shown once, forced change | `users.must_change_password` | middleware redirects to `/change-password`; `CredentialsDialog` |
| §4.10 soft delete | no `delete` policies for tenant roles (service role only); `deleted_at`/`status` columns | UI never hard-deletes |

## Files & uploads

15. **Private buckets** (`student-docs`, `receipts`, `complaint-photos`) written by the server with the service role (`lib/storage.ts`) into `<hostel_id>/<folder>/<uuid>`; displayed via 1-hour signed URLs. No client-side storage policies needed.

## Ops

16. **Service-role key** is required for account creation / password regeneration / uploads / seeding and must be added to `.env.local` from the Supabase dashboard (not retrievable via the MCP). Everything else (all reads, RLS-gated writes, triggers) works with the anon key.
17. **Seeding**: `npm run db:seed` (full demo, §13) and `npm run db:seed:admin` (super admin only, §8.1). The seed uses the auth admin API and prints all demo credentials.

## Super Admin review follow-ups

18. **Second hostel for an existing owner (§4.1)** — the SA-2 wizard's Owner step has a "New owner / Existing owner" toggle. `owner` in `createOwnerHostelSchema` is a discriminated union (`{mode:'new', name,email,phone}` | `{mode:'existing', ownerUserId}`); in existing mode `createOwnerAndHostel` skips account creation and calls `sa_create_hostel_with_subscription` with the chosen `p_owner_user_id`, returning `credentials: null` (no dialog). Inactive owners are listed but not selectable.
19. **Structure edits are grow-only (§4.2)** — `updateHostelStructure` (SA only) calls the DB RPC `sa_update_hostel_structure(hostel, floors, rooms)`, which checks `app.is_super_admin()`, rejects shrinking (it would orphan occupied rooms/beds), updates `hostels.total_floors/total_rooms` and re-runs `scaffold_hostel` (idempotent, `ON CONFLICT DO NOTHING`) in one transaction. `scaffold_hostel` itself is not executable by users (see 22). The "Edit structure" dialog on SA-4 clamps to the current counts.
20. **SA-4 header** — DESIGN.md says "no edit buttons except Renew"; the §6.1 row actions (suspend, regenerate owner password) are kept on the detail page but tucked behind a single ghost "⋯" menu (`HostelHeaderMenu`) so Renew stays the only prominent control.
21. **7 / 15 / 30-day flags (§4.4)** — `DaysLeftPill` tiers its tone (≤7 red · ≤15 sand · ≤30 navy · >30 teal) and the dashboard "Expiring soon" card shows three window counters + filter pills (`ExpiringSoonTable`) instead of a single ≤30-day list.

## Hardening (Supabase security advisor pass)

22. **RPC execute privileges** — Postgres grants `EXECUTE` on new functions to `PUBLIC` by default, so `anon` could reach every RPC (all of them check `auth.uid()`/role internally, but hardening says don't expose them). `schema.sql` now revokes `EXECUTE` from `public`/`anon` on every function in `public` and `app` (and via default privileges), keeps `authenticated`/`service_role`, and additionally revokes `scaffold_hostel` from `authenticated` — it is reachable only through `sa_create_hostel_with_subscription` / `sa_update_hostel_structure` (SECURITY DEFINER wrappers) or the service role. All helper/trigger functions have a fixed `search_path = public`.
23. **"Today" is IST** — `rpc_hostel_stats.visitors_today` and the warden pages use `Asia/Kolkata` day boundaries (India-only product; hostel-level time zones can come later).
24. **Not done (dashboard-only settings)**: enable Supabase Auth "Leaked password protection" (HaveIBeenPwned) in Dashboard → Authentication → Settings — the advisor flags it and it can't be set via SQL/MCP.
