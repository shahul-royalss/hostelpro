# CLAUDE.md — PG / Hostel Management SaaS (Build Spec)

> This file is the single source of truth for building this product. Read it fully before writing any code. Where something is not covered, pick the simplest option that does not violate the Hard Business Rules in §4, and log the choice in `DECISIONS.md`.

---

## 1. Product summary

A multi-tenant SaaS platform for managing PG hostels.

- **Platform operator (us)** → Super Admin. Sells subscriptions, creates hostel owners, monitors everything.
- **Customer** → Owner. One hostel per subscription. Runs the hostel through staff.
- **Staff per hostel** → exactly 1 Manager (finance/ops) and 1 Warden (students/rooms).
- **Residents** → Students (up to 10,000 per hostel), who get their own login.

Five roles total: `super_admin`, `owner`, `manager`, `warden`, `student`.

---

## 2. Tech stack (default — only swap if explicitly told)

| Layer | Choice |
|---|---|
| Framework | Next.js 15 (App Router) + TypeScript |
| Styling | Tailwind CSS + shadcn/ui |
| Database / Auth | Supabase (Postgres + Auth + Row Level Security + Storage) |
| Charts | Recharts |
| Forms / validation | React Hook Form + Zod (validate again on the server) |
| Deployment | Vercel |

- Super Admin / Owner / Manager UIs are **desktop-first** dashboards (still responsive).
- Warden / Student UIs are **mobile-first** (bottom navigation, thumb-reachable actions, PWA-installable).
- UI components come from the Stitch exports described in `DESIGN.md` (see §10). Place raw exports in `/design-exports/` and adapt them into `/components/`.

---

## 3. Roles & access model

| Role | Created by | Scope | Limits |
|---|---|---|---|
| Super Admin | Seeded (env credentials) | Entire platform, all hostels | — |
| Owner | Super Admin | Their hostel(s) only | 1 hostel per subscription |
| Manager | Owner | One hostel | Max **1 active** per hostel |
| Warden | Owner | One hostel | Max **1 active** per hostel |
| Student | Warden (via registration form) | Their own data + shared hostel info | Max **10,000 active** per hostel |

Single login page for everyone → after auth, redirect by role (`/super-admin`, `/owner`, `/manager`, `/warden`, `/student`). Every non-super-admin session is bound to a `hostel_id`.

---

## 4. Hard business rules (enforce server-side, never trust the client)

1. **One subscription ↔ one hostel.** A hostel cannot exist without a subscription record. If an owner wants a second hostel, Super Admin creates a second hostel + second subscription (it may sit under the same owner account; the owner then switches hostels from a dropdown).
2. **Super Admin decides hostel structure at creation**: hostel name, number of floors, number of rooms. The system auto-scaffolds: floors → rooms (numbered `101, 102… 201, 202…`, distributed evenly across floors) → beds (default 3 beds per room). The Warden can later edit beds-per-room and room numbers; only Super Admin can change floor/room counts.
3. **Role limits**: max 1 active Manager, 1 active Warden, 10,000 active Students per hostel. Creating beyond the limit must fail with a clear error. Deactivating frees the slot.
4. **Subscription lifecycle**: `active → expiring (≤15 days left) → expired`. On expiry the hostel goes **read-only** for Owner, Manager, Warden, Students (data visible, all writes blocked, persistent renewal banner). Super Admin dashboard flags hostels expiring in 7/15/30 days. Renewal = Super Admin extends `end_date`.
5. **Tenant isolation**: every table with hostel data carries `hostel_id`; every query filters by it; Supabase RLS policies enforce it. A user must never read or write another hostel's rows.
6. **Owner announcements** are visible to Manager, Warden, and all Students of that hostel (audience can also be narrowed to a single role).
7. **A bed holds at most one active student.** Assigning an occupied bed must fail. Checkout frees the bed.
8. **Students never see other students' personal data** except roommates' names and phone numbers.
9. Passwords are generated for new accounts, shown exactly once to the creator, and the user is forced to change password on first login.
10. Soft-delete everything user-facing (`status`/`deleted_at`), never hard-delete financial or student records.

---

## 5. Data model (Postgres)

Use these tables (add `created_at`, `updated_at` everywhere; UUID primary keys):

```
users            id, role, full_name, email, phone, password (via Supabase Auth),
                 hostel_id (null for super_admin), status (active|inactive),
                 must_change_password bool, created_by

hostels          id, name, owner_user_id, total_floors, total_rooms,
                 address, status (active|readonly|suspended)

subscriptions    id, hostel_id, owner_user_id, start_date, end_date,
                 amount, status (active|expiring|expired), created_by, notes

floors           id, hostel_id, floor_number
rooms            id, hostel_id, floor_id, room_number, capacity (beds count)
beds             id, room_id, bed_number, status (free|occupied), student_id nullable

students         id, hostel_id, user_id, full_name, phone, email, photo_url,
                 guardian_name, guardian_phone, permanent_address, id_proof_type,
                 id_proof_url, date_of_joining, room_id, bed_id,
                 monthly_fee, status (active|on_leave|vacated)

fee_payments     id, hostel_id, student_id, period_month (YYYY-MM), amount_due,
                 amount_paid, status (paid|partial|unpaid), paid_on, mode
                 (cash|upi|bank), recorded_by

complaints       id, hostel_id, student_id, category (food|cleaning|maintenance|
                 wifi|roommate|other), title, description, photo_url,
                 status (open|in_progress|resolved), resolved_at, resolution_note

expenses         id, hostel_id, date, category (groceries|staff|electricity|
                 water|maintenance|other), amount, note, receipt_url, uploaded_by

revenues         id, hostel_id, date, source (fees|mess|other), amount, note,
                 uploaded_by

announcements    id, hostel_id, author_user_id, title, body,
                 audience (all|manager|warden|students), created_at

tasks            id, hostel_id, assigned_to (manager user_id), title, description,
                 due_date, status (pending|in_progress|done), created_by (owner)

leaves           id, hostel_id, student_id, from_date, to_date, reason,
                 status (pending|approved|rejected), decided_by (warden)

visitors         id, hostel_id, student_id, visitor_name, visitor_phone,
                 relation, check_in_at, check_out_at, logged_by (warden)

menus            id, hostel_id, day_of_week (mon..sun),
                 meal (breakfast|lunch|snacks|dinner), items text
```

Derived values (compute, don't store): occupancy % = occupied beds / total beds; monthly profit = revenues − expenses; fee collection % = paid students / active students.

---

## 6. Feature spec by role

### 6.1 Super Admin (`/super-admin`)

- **Dashboard**: total hostels, active/expiring/expired subscriptions, total owners, total students across platform, monthly subscription revenue, chart of hostels onboarded over time, list of subscriptions expiring soon.
- **Create Owner + Hostel (wizard)**: step 1 owner details (name, email, phone) → step 2 hostel details (name, floors, rooms) → step 3 subscription (start date, end date, amount) → step 4 review → on submit: create owner user, hostel, scaffold floors/rooms/beds, create subscription, display generated credentials once (with copy button).
- **Hostels / subscriptions table**: search + filter by status; row actions: view detail, extend/renew subscription, suspend, regenerate owner password.
- **Hostel detail**: subscription history, occupancy, revenue vs expense summary, complaint volume, staff & student counts. Read-only into tenant data (monitoring, not editing).

### 6.2 Owner (`/owner`)

- **Dashboard**: occupancy stat (beds occupied/total), active students, fees collected vs pending this month, revenue vs expenses chart (last 30 days), open complaints count, latest announcements, subscription days-remaining card.
- **Complaints inbox**: list with status filters; open a complaint, change status, add resolution note. (Owner sees all; Warden can also update status — see 6.4.)
- **Broadcast updates**: compose title + body, pick audience (all / manager / warden / students), send; history list. These appear in every recipient's app.
- **Staff management**: create/deactivate the 1 Manager and 1 Warden (name, phone, email → generated credentials shown once). Send **personal tasks to the Manager** (title, description, due date) and track status.
- **Students**: read-only directory with search, room filter, fee status; open a student profile.
- **Finance view**: monthly expense breakdown by category, revenue by source, profit trend — all fed by Manager's entries and fee payments.
- If the owner has multiple hostels (multiple subscriptions), a hostel-switcher dropdown in the header.

### 6.3 Manager (`/manager`)

- **Dashboard**: today's expenses total, today's revenue total, this-month profit, pending tasks from owner, expense-by-category donut for the month.
- **Daily expenses**: quick-entry form (date defaults today, category, amount, note, optional receipt photo); editable list of this month's entries; monthly CSV export.
- **Daily revenue**: same pattern (date, source, amount, note); list + export.
- **My tasks**: tasks assigned by Owner; update status pending → in progress → done; owner gets the status change reflected.
- **Mess menu management**: weekly grid editor (day × meal → items). Students see this menu.
- **Announcements feed**: read-only view of owner updates targeted at manager/all.

### 6.4 Warden (`/warden`, mobile-first)

- **Home**: occupancy summary card (free vs occupied beds), fees pending count, pending leave requests, today's visitors, owner announcements.
- **Register student (multi-step form)**: personal info → guardian info → ID proof upload + photo → assign room & bed (only free beds selectable) → fee amount → review → submit. On submit: student record + student login created, credentials shown once, bed marked occupied.
- **Rooms & beds**: floor-wise list of rooms, each showing `occupied/total` beds with color state; tap a room → **Room detail**: every bed with occupant name, phone, fee status, join date; free beds marked; actions: reassign bed, vacate (checkout) student.
- **Fees tracker**: month selector; list of students with paid / partial / unpaid chips; tap to record a payment (amount, mode, date). Filter unpaid only.
- **Leaves**: student leave requests with approve/reject; history.
- **Visitors**: log a visitor (student, name, phone, relation, check-in) and mark check-out; today's list + history.
- **Complaints**: view student complaints, update status / add note (same data Owner sees).

### 6.5 Student (`/student`, mobile-first)

- **Home**: room number + bed card, fee status for current month (paid / due with amount), latest owner announcements, quick actions (raise complaint, apply leave, view menu).
- **My details**: everything the warden registered (read-only) + change password.
- **My room & roommates**: room number, floor, and roommates' **names and phone numbers** only.
- **Mess menu**: weekly menu grid by day and meal.
- **Complaints**: raise (category, title, description, optional photo) and track status timeline of own complaints.
- **Leave**: apply (dates + reason), see approval status.
- **Hostel info**: warden contact card, hostel rules (static text the owner can edit — nice-to-have).

---

## 7. Shared modules

- **Announcements**: one write path (Owner), read path filtered by audience + hostel.
- **Complaints lifecycle**: student creates → open; warden/owner move to in_progress/resolved with note; student sees the timeline.
- **Notifications (v1 = in-app only)**: bell icon with unread count for: new announcement, task assigned/updated, complaint status change, leave decision, subscription expiring (owner), fee recorded (student). Email/SMS is out of scope for v1.
- **Audit-light**: store `created_by` / `recorded_by` / `decided_by` on every mutating table (already in schema).

---

## 8. Auth & credential flows

1. Super Admin seeded from env vars on first run.
2. Super Admin creates Owner → generated password shown once → owner logs in → forced password change.
3. Owner creates Manager/Warden → same generated-password flow.
4. Warden registers Student → student account auto-created (login = phone number, generated password) → same flow.
5. Middleware: check session → check role matches route group → check `hostel_id` matches resource → check subscription status (block writes if expired, except Super Admin).

---

## 9. Route map (App Router)

```
/login
/super-admin            dashboard
/super-admin/hostels    list + [id] detail
/super-admin/create     owner+hostel wizard
/super-admin/subscriptions
/owner                  dashboard
/owner/complaints
/owner/updates          broadcast composer + history
/owner/staff            manager & warden + tasks
/owner/students         directory + [id]
/owner/finance
/manager                dashboard
/manager/expenses
/manager/revenue
/manager/tasks
/manager/menu
/warden                 home
/warden/register
/warden/rooms           list + [id] room detail
/warden/fees
/warden/leaves
/warden/visitors
/warden/complaints
/student                home
/student/profile
/student/room
/student/menu
/student/complaints
/student/leave
```

API: prefer Next.js Server Actions for mutations; route handlers under `/api/` only where needed (file upload, exports).

---

## 10. Using the Stitch design exports

`DESIGN.md` (separate file) contains the full UI spec that was fed to Google Stitch. When Stitch screens are exported:

1. Drop raw exports into `/design-exports/<screen-id>/` (screen IDs like `OW-1`, `WD-3` match DESIGN.md).
2. Rebuild each export as a proper React component with real props/data — copy the **visual language** (colors, spacing, glass cards, radii), not the dummy markup.
3. Centralize the design tokens from DESIGN.md §1 in `tailwind.config.ts` (colors, radius, font) before building any screen.

---

## 11. Folder structure

```
/app                  route groups per role
/components/ui        shadcn primitives
/components/<role>    role-specific composites
/lib/supabase         client, server client, RLS helpers
/lib/validators       zod schemas
/lib/permissions.ts   role checks + subscription gate
/design-exports       raw Stitch output (never imported directly)
/db                   schema.sql, rls-policies.sql, seed.ts
```

---

## 12. Build order

- **M0** — Project setup, Tailwind tokens from DESIGN.md, Supabase schema + RLS, seeded Super Admin, login + role redirect + forced password change.
- **M1** — Super Admin: dashboard, create-owner wizard (with scaffold generation), subscriptions table, renew/suspend.
- **M2** — Owner: dashboard, staff creation, broadcast updates; subscription read-only gate working end-to-end.
- **M3** — Warden: student registration (creates login, occupies bed), rooms & beds views, room detail, vacate/reassign.
- **M4** — Manager: expenses, revenue, tasks (owner assign → manager complete), mess menu.
- **M5** — Student app: home, profile, room & roommates, menu, complaints, leave. Warden fees tracker + leaves + visitors. Complaint lifecycle wired to Owner + Warden.
- **M6** — Analytics polish (all charts), notifications, CSV exports, empty states, seed/demo data, QA pass on the rules in §4.

---

## 13. Seed / demo data

Provide `db/seed.ts`: 1 super admin, 1 owner, 1 hostel (3 floors × 4 rooms × 3 beds), 1 manager, 1 warden, 12 students spread across rooms, 1 month of fees (mixed paid/unpaid), 15 expense entries, 10 revenue entries, 4 complaints in mixed states, 2 announcements, 2 tasks, a full weekly menu, 2 leaves, 3 visitors. Print all demo credentials at the end of seeding.

---

## 14. Definition of done

- Every Hard Business Rule in §4 has at least one server-side guard **and** a visible UI behavior (error toast, disabled state, or banner).
- No cross-hostel data leak: verified by logging in as two different hostels' wardens.
- Expired subscription actually blocks writes for all four tenant roles.
- Role limits (1/1/10,000) return friendly errors when exceeded.
- Warden and Student flows fully usable on a 390px-wide viewport.
- Seed script runs clean on a fresh database; demo login works for all five roles.
