# HostelPro — PG / Hostel Management SaaS

Multi-tenant SaaS for running PG hostels. The platform operator (Super Admin) sells
subscriptions and creates hostel owners; each owner runs one hostel per subscription
through a Manager (finance/ops) and a Warden (students/rooms); students get their own
mobile app for fees, complaints, leaves and the mess menu.

Five roles: `super_admin`, `owner`, `manager`, `warden`, `student`. Desktop-first
dashboards for Super Admin / Owner / Manager; mobile-first (390px, bottom nav,
PWA-installable) for Warden / Student. Full product spec: [`CLAUDE_2.md`](./CLAUDE_2.md);
UI spec: [`DESIGN.md`](./DESIGN.md); design decisions & rule enforcement map:
[`DECISIONS.md`](./DECISIONS.md).

---

## Stack

| Layer | Choice |
|---|---|
| Framework | Next.js 15 (App Router, Server Components + Server Actions), React 19, TypeScript strict |
| Styling | Tailwind CSS 3.4 (tokens in `tailwind.config.ts`), shadcn-style primitives in `components/ui` |
| Database / Auth / Storage | Supabase (Postgres + RLS + Auth + private buckets) |
| Charts | Recharts (wrapped in `components/shared/charts.tsx`) |
| Forms | React Hook Form + Zod (validated again on the server) |
| Tooling | `tsx` for scripts, ESLint 9, `dotenv` |
| Deployment | Vercel |

---

## Folder structure

```
app/                       App Router — one route group per role
  login/  change-password/ auth screens (A-1, A-2)
  super-admin/             dashboard, create wizard, hostels, subscriptions
  owner/                   dashboard, complaints, updates, staff, students, finance
  manager/                 dashboard, expenses, revenue, tasks, menu
  warden/                  home, register, rooms, fees, leaves, visitors, complaints
  student/                 home, profile, room, menu, complaints, leave, info
  api/                     route handlers (health check, CSV exports)
components/
  ui/                      button, input, dialog, sheet, tabs, table, misc …
  shared/                  GlassCard, StatCard, StatusPill, EmptyState, charts, forms …
  shell/                   desktop sidebar shell + mobile bottom-nav shell, nav config
  <role>/                  role-specific composites (client components)
lib/
  supabase/                browser / server (RLS) / admin (service role) / middleware clients
  auth/                    account creation, password generation (service role only)
  actions/<role>.ts        Server Actions (zod → context assert → RLS client → ok/fail)
  queries/<role>.ts        server-side reads
  validators/<role>.ts     zod schemas
  permissions.ts           requireRole / requireHostelContext / assertWritableContext
  storage.ts               private-bucket uploads + signed URLs
  types.ts  utils.ts  roles.ts
hooks/use-action.ts        client hook around Server Actions (pending state + toasts)
db/
  schema.sql               tables, enums, triggers, RPCs (apply first)
  rls-policies.sql         row-level security policies (apply second)
  seed.ts                  demo data seed (see below)
design-exports/<ID>/       raw Stitch exports (reference only — never imported)
scripts/                   QA helpers (see scripts/README.md)
```

---

## Setup

### 1. Supabase project

1. Create a project at <https://supabase.com> (any region; note the **Project URL**).
2. Open **SQL Editor** and run, in this order:
   1. `db/schema.sql` — enums, tables, helper functions (`app.*`), triggers, RPCs
   2. `db/rls-policies.sql` — enables RLS on every table and creates the policies
3. Storage: `schema.sql` inserts the three **private** buckets (`student-docs`, `receipts`,
   `complaint-photos`) into `storage.buckets`. If your SQL user can't write that table,
   create them manually as private buckets — the server writes to them with the service
   role, so no storage policies are needed.
4. Auth → Providers → Email: keep enabled. Sign-ups are never done from the UI —
   every account is created by the server (auth admin API) — so you can disable
   "Allow new users to sign up" and "Confirm email". Recommended: Authentication →
   Settings → enable **Leaked password protection** (flagged by the Supabase security advisor;
   dashboard-only setting).

### 2. Environment

```bash
cp .env.example .env.local
```

| Variable | Where to get it |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Dashboard → **Settings → API** → Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Settings → API → Project API keys → `anon` `public` |
| `SUPABASE_SERVICE_ROLE_KEY` | Settings → API → Project API keys → `service_role` (**server-only**; used for creating accounts, regenerating passwords, private uploads and seeding — never expose to the browser) |
| `SUPER_ADMIN_EMAIL` / `SUPER_ADMIN_PASSWORD` / `SUPER_ADMIN_NAME` | Your platform login; the seed creates it |
| `NEXT_PUBLIC_APP_NAME` | `HostelPro` |
| `NEXT_PUBLIC_APP_URL` | `http://localhost:3000` locally; your Vercel URL in production |

### 3. Install, seed, run

```bash
npm install
npm run db:seed          # super admin + full demo data (two hostels) — needs the service-role key
npm run dev              # http://localhost:3000
```

Other seed modes:

```bash
npm run db:seed:admin                 # super admin only (production bootstrap)
npx tsx db/seed.ts --force            # wipe the demo hostels/accounts and reseed
npx tsx db/seed.ts --force --force-admin   # …and recreate the super admin too
```

The seed uses the same RPCs the UI calls (`sa_create_hostel_with_subscription`,
`wd_register_student`, `wd_record_payment`) so triggers, notifications and role limits
run exactly as in the app. It refuses to run on top of existing demo accounts
("Already seeded — rerun with --force"). Note: the current dev Supabase project already
contains this demo data (created via SQL for QA), so the first real run there must use
`--force`.

> **TLS-inspecting antivirus (Norton, etc.)** — if `npm run dev` / the seed fails with
> `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` / `self signed certificate in certificate chain`,
> Node must trust the AV's root certificate: point `NODE_EXTRA_CA_CERTS` at its PEM,
> e.g. `NODE_EXTRA_CA_CERTS=C:\ProgramData\Norton\Antivirus\wscert.pem`. `.claude/launch.json`
> already sets this for the dev server; set it in your shell for `npm run db:seed`.
> `GET /api/health` reports whether the server can reach Supabase (and the TLS error cause).

---

## Demo credentials (created by `npm run db:seed`)

| Role | Name | Login ID | Password | URL |
|---|---|---|---|---|
| Super Admin | from `.env.local` | `SUPER_ADMIN_EMAIL` (e.g. admin@hostelpro.app) | `SUPER_ADMIN_PASSWORD` | `/super-admin` |
| Owner | Ananya Rao | owner@demo.hostelpro.app | Owner@12345 | `/owner` |
| Manager | Rahul Mehta | manager@demo.hostelpro.app | Manager@12345 | `/manager` |
| Warden | Priya Nair | warden@demo.hostelpro.app | Warden@12345 | `/warden` |
| Student (×12) | Aarav Sharma … Siddharth Bose | phone `9000000001` … `9000000012` | Student@12345 | `/student` |
| Owner (expired hostel) | Vikram Shetty | owner2@demo.hostelpro.app | Owner@12345 | `/owner` |
| Warden (expired hostel) | Lakeview Warden | warden2@demo.hostelpro.app | Warden@12345 | `/warden` |
| Student (×2, expired hostel) | Nikhil Joshi, Tanvi Menon | phone `9000000101`, `9000000102` | Student@12345 | `/student` |

Students sign in with their **phone number** (mapped internally to
`<phone>@student.hostelpro.local`). Demo accounts skip the forced password change.

What the seed creates:

- **Sunrise Residency** (owner Ananya Rao) — 3 floors × 12 rooms × 3 beds = 36 beds,
  subscription active (started 60 days ago, 305 days left, ₹24,000), 12 students spread
  101/102 full · 103 two · 104 one · 201 two · 202 one, current-month fees 6 paid / 2 partial /
  4 unpaid, 15 expenses + 10 revenues (last 30 days), 4 complaints (2 open, 1 in progress,
  1 resolved with note), 2 announcements, 2 tasks (1 done, 1 pending), full 7×4 mess menu,
  2 leaves (1 pending, 1 approved), 3 visitors (2 in today, 1 checked out).
- **Lakeview PG** (owner Vikram Shetty) — 2 floors × 6 rooms, subscription **expired 3 days
  ago** → hostel is read-only (banner + every write blocked); warden2 + 2 students. Use it to
  verify the expiry gate and cross-tenant isolation.

The seed prints this table plus both hostel ids when it finishes.

### Role URLs

| Role | Home | Screens |
|---|---|---|
| Super Admin | `/super-admin` | `/super-admin/create`, `/super-admin/hostels`, `/super-admin/hostels/[id]`, `/super-admin/subscriptions` |
| Owner | `/owner` | `/owner/complaints`, `/owner/updates`, `/owner/staff`, `/owner/students`, `/owner/students/[id]`, `/owner/finance` |
| Manager | `/manager` | `/manager/expenses`, `/manager/revenue`, `/manager/tasks`, `/manager/menu` |
| Warden | `/warden` | `/warden/register`, `/warden/rooms`, `/warden/rooms/[id]`, `/warden/fees`, `/warden/leaves`, `/warden/visitors`, `/warden/complaints` |
| Student | `/student` | `/student/profile`, `/student/room`, `/student/menu`, `/student/complaints`, `/student/leave`, `/student/info` |

`/login` is the single sign-in page for everyone; after auth the user is redirected by
role, and users with `must_change_password` land on `/change-password` first.

---

## How the hard business rules are enforced

Every rule in `CLAUDE_2.md` §4 has a **database guard** (schema/RLS/trigger/RPC) **and** a
UI behaviour. The full mapping lives in [`DECISIONS.md`](./DECISIONS.md) ("Hard rules → where
enforced"); in short:

| Rule | Server-side guard | UI |
|---|---|---|
| One subscription ↔ one hostel | `sa_create_hostel_with_subscription()` creates hostel + subscription + scaffold atomically | Super Admin wizard |
| Scaffold floors → rooms → beds | `scaffold_hostel()`; `rooms_capacity_sync` trigger; only SA may insert rooms/floors | Warden edits room number / beds only |
| Role limits 1 / 1 / 10,000 | `enforce_role_limits` trigger on `users` (friendly error) | Add-staff disabled when slot filled; toast |
| Subscription lifecycle → read-only | live `app.subscription_state()`; every write policy + RPC checks `app.hostel_writable()` | `SubscriptionBanner`, `ctx.writable=false` disables buttons, `assertWritableContext()` in actions |
| Tenant isolation | `hostel_id` on every table; RLS via `app.can_read_hostel()` / `has_role_in()` | session bound to one hostel (`requireHostelContext`), owner switcher validated server-side |
| Announcement audience | `announcements_select` policy filters by role; trigger fans out notifications | audience pills |
| One active student per bed | partial unique index + `students_bed_guard` trigger | only free beds selectable |
| Students see roommates' name + phone only | student RLS = own row; `st_my_roommates()` returns name/phone/bed | `/student/room` |
| Generated password, shown once, forced change | `users.must_change_password`; server-generated passwords never stored | `CredentialsDialog`, `/change-password` redirect |
| Soft delete | no delete policies for tenant roles; `status` / `deleted_at` columns | UI never hard-deletes |

Server rule of thumb: pages call `requireHostelContext('<role>')`; Server Actions
`zod`-validate → `assertWritableContext('<role>')` (or `assertHostelContext` for reads) →
RLS client → `ok()` / `fail(errorMessage(e))` → `revalidatePath()`. Client-supplied
`hostel_id` is never trusted — the context's hostel is used.

---

## Deploying to Vercel

1. Push the repo and import it in Vercel (framework preset: Next.js; build `next build`).
2. Project → Settings → Environment Variables: add every key from `.env.example`
   (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
   `SUPER_ADMIN_*`, `NEXT_PUBLIC_APP_NAME`, `NEXT_PUBLIC_APP_URL=https://<your-domain>`).
   The service-role key is used only in server code (`lib/supabase/admin.ts`) — keep it out
   of `NEXT_PUBLIC_*`.
3. Supabase → Auth → URL Configuration: set Site URL to the Vercel domain (cookies are
   same-site; no OAuth redirect URLs are needed).
4. Bootstrap the platform account against the production project from your machine:
   `npm run db:seed:admin` with `.env.local` pointed at production (never run the full demo
   seed in production).
5. `next.config.ts` raises the Server Action body limit to 8 MB (receipt / photo uploads go
   through actions — fine on Vercel) and allows `*.supabase.co` images. The middleware
   (`middleware.ts`) refreshes the Supabase session on every non-static request and runs on
   the Vercel edge runtime. `/api/health` can be used as an uptime probe.

---

## Verify checklist (CLAUDE_2.md §14 — definition of done)

Run through this after seeding, once as a human in the browser and once with the QA helper
(`scripts/README.md`: `COOKIE=$(node scripts/_qa-login.mjs <login> <password>)` then
`curl -s -b "$COOKIE" http://localhost:3000/<route>`).

- [ ] `npx tsc --noEmit` and `npm run lint` are clean; `npm run build` succeeds.
- [ ] Every hard rule in §4 has a server-side guard **and** a visible UI behaviour
      (error toast, disabled control, or banner) — see the table above.
- [ ] **No cross-hostel leak**: log in as `warden@` (Sunrise) and `warden2@` (Lakeview);
      each sees only its own rooms, students, fees, complaints, visitors, leaves. Opening a
      Sunrise student / room / complaint id while logged in as Lakeview returns 404 / not
      found, never data.
- [ ] **Expired subscription blocks writes** for all four tenant roles: as `owner2@`,
      `warden2@` and Lakeview students, the renewal banner is shown, write buttons are
      disabled, and any direct Server Action / RPC call fails with "Subscription expired —
      hostel is read-only".
- [ ] **Role limits** return friendly errors: as `owner@`, adding a second Manager or Warden
      shows "This hostel already has an active manager/warden…" (button disabled while the
      slot is filled; deactivating frees it).
- [ ] **One student per bed**: registering onto an occupied bed is impossible from the UI and
      fails at the DB with "Bed N is already occupied".
- [ ] **Generated credentials**: creating an owner / manager / warden / student shows the
      password exactly once (copy buttons); first login is forced to `/change-password`.
- [ ] **Announcement audience**: an owner post to `students` is visible to students but not
      to the manager/warden feeds; `all` reaches everyone; notification bell counts update.
- [ ] **Complaint lifecycle**: student raises → warden/owner move to in progress → resolved
      with note; the student's timeline shows every step.
- [ ] Warden and Student flows fully usable at a **390px** viewport (bottom nav, full-width
      CTAs, no horizontal scroll).
- [ ] Every list has an empty state; every route has a `loading.tsx` skeleton; charts and
      stats show real seeded numbers (Sunrise: 12/36 beds, 6 paid / 2 partial / 4 unpaid).
- [ ] Seed runs clean on a fresh database (`npm run db:seed`) and demo login works for all
      five roles at the URLs above.
