# Access control — HostelPro

The role model, the least-privilege decisions and the reasoning behind them, how accounts are created
and removed, how administrative access works, and how often all of it is reviewed.

Companion documents: [`../SECURITY.md`](../SECURITY.md) §3–§4 (what was found and how it is enforced),
[`../THREAT-MODEL.md`](../THREAT-MODEL.md) §3 (privilege boundaries),
[`../CLAUDE_2.md`](../CLAUDE_2.md) §4, §6 (the product rules this implements),
[`incident-response.md`](./incident-response.md) §4.1–§4.3 (revoking access in a hurry).

---

## 1. Where access control actually lives

Read this before the matrix, because the matrix is meaningless without it.

| Layer | Enforces | File |
|---|---|---|
| **Middleware** | Session refresh, security headers, inactive-account block, forced password change, MFA step-up, role ↔ route-group match | `lib/supabase/middleware.ts`, `middleware.ts` |
| **Server Components / Actions** | The same authentication gates, re-checked independently, plus role assertion and the subscription write-gate | `lib/permissions.ts` (`requireUser`, `requireRole`, `assertRole`, `assertWritableContext`) |
| **RLS policies** | Row visibility and writability per role and per tenant | `db/rls-policies.sql` |
| **Database triggers** | Everything RLS structurally cannot express — privileged **columns**, foreign keys that must stay inside the tenant, role limits | `db/schema.sql` |

**The boundary that decides everything is B3 in the threat model: browser → PostgREST, directly, with
the public anon key.** Any control that exists only in React or only in middleware does not exist.
This is why the role matrix in §2 is written from the RLS policies and triggers, not from the UI —
and why every authorization claim in this project is tested twice, once through the app and once
straight against PostgREST (`scripts/_qa-rls-attack.mjs`).

The forced-password-change and MFA gates are duplicated between middleware and `requireUser()` on
purpose. A single-point authentication control keyed off a hand-written route regex was bypassable by
appending `.png` to a URL — `SECURITY.md` §3.2. Duplication here is the fix, not redundancy.

---

## 2. The five roles

`super_admin`, `owner`, `manager`, `warden`, `student` (`lib/roles.ts`). Every non-super-admin session
is bound to exactly one `hostel_id`; the owner may switch between hostels they own via a
cookie that is re-validated against ownership server-side (`getHostelContext()`, `lib/permissions.ts`).

Read `R` = can select. `W` = can insert/update. `—` = no access. All are additionally scoped to the
caller's own hostel, and every `W` is additionally gated on the subscription being live
(`app.hostel_writable()`).

| Data | super_admin | owner | manager | warden | student |
|---|---|---|---|---|---|
| `hostels` | R/W | R (own) | R | R | R |
| `subscriptions` | R/W | R (own) | R | R | — |
| `users` — staff rows | R/W | R/W (own manager + warden) | R (owner/manager/warden only) | R | — |
| `users` — resident rows | R/W | R | **—** | R/W | own row only |
| `students` (name, phone, guardian, address, photo, ID proof) | R/W | R/W | **—** | R/W | own row only |
| `fee_payments` | R/W | R/W | **—** | R/W | own rows |
| `complaints` | R/W | R/W (status, note) | **—** | R/W (status, note) | own rows + create |
| `leaves` | R/W | R/W (decide) | **—** | R/W (decide) | own rows + create |
| `visitors` | R/W | R | **—** | R/W | **—** |
| `beds` | R/W | R | R | R/W | own room only |
| `rooms` / `floors` | R/W | R | R | R (rooms: W on number + capacity) | R |
| `expenses` / `revenues` | R/W | R | R/W | **—** | — |
| `menus` | R/W | R | R/W | R | R |
| `announcements` | R | R/W | R (audience-filtered) | R (audience-filtered) | R (audience-filtered) |
| `tasks` | R | R/W | R + **status only** | — | — |
| `audit_log` | R (all) | R (own hostel) | — | — | — |
| `notifications` | own | own | own | own | own |
| Storage `student-docs` | via server | via server | **—** | via server | own documents |
| Storage `receipts` | via server | via server | via server | — | — |
| Storage `complaint-photos` | via server | via server | — | via server | own complaints |

Sources: `db/rls-policies.sql` for every row; `lib/storage.ts` for buckets; `CLAUDE_2.md` §6 for the
product intent each policy implements.

---

## 3. Least-privilege decisions, and why

Each of these is a deliberate narrowing. Several were found by audit *after* the first implementation
was too generous — that history is recorded because it is the best argument for keeping them.

### 3.1 The Manager cannot see residents at all

**Decision.** The Manager has **no** access to `students`, `fee_payments`, `complaints`, `leaves` or
`visitors`, and their `users` read is filtered to `role in ('owner','manager','warden')`.

**Why.** `CLAUDE_2.md` §6.3 scopes the Manager to expenses, revenue, tasks, mess menu and the
announcements feed. **No manager page, query or action touches a student table.** The original
policies used `app.is_staff_of()`, which includes `manager`, so the role could read every resident's
full PII, guardian phone, permanent address, fee ledger, leave history, visitor log and complaints —
a pure over-grant with zero product justification, recorded as a High finding in `SECURITY.md` §3.6.

**How it is enforced.** Resident-facing policies use `app.has_role_in(hostel_id, 'warden', 'owner')`
instead of `app.is_staff_of()` (`db/rls-policies.sql`). The Manager keeps *staff* rows in `users`
because tasks and announcements need to render names — that carve-out is explicit in
`users_select` and is the minimum that keeps the product working.

**The reasoning to reuse:** the question is never "would it be convenient?" — it is "does a page, a
query or an action in this role's surface need it?" If the answer is no, the role does not get it,
even if the role feels senior.

### 3.2 The Owner cannot renew their own subscription

**Decision.** `subscriptions` is insert/update **super-admin only** (`subscriptions_write`).

**Why.** This is the paywall. An owner who could extend `end_date` gets the product for free, and
`app.hostel_writable()` — the gate on every tenant write in the system — is computed from it. Making
this self-serviceable would not be a billing bug; it would disable a security control.

The complementary rule: `hostels` insert/update is also SA-only, and floor/room counts are SA-only
and grow-only, because shrinking would orphan occupied rooms and beds
(`sa_update_hostel_structure`, `lib/actions/super-admin.ts`).

### 3.3 Nobody can change their own role, tenant or identity

**Decision.** `role`, `hostel_id`, `status`, `created_by` and `id` are privileged on **every** write
path — app, PostgREST, raw SQL — via the `app.users_update_guard` `BEFORE UPDATE` trigger
(`db/schema.sql`). Self-service is limited to `full_name`, `phone`, `email` and
`must_change_password`. Account status may be changed only by that account's administrator.

**Why.** RLS gates *rows*, not *columns*. `users_update` legitimately allows `id = auth.uid()` so
people can edit their own name. That single clause let any authenticated user PATCH themselves to
`super_admin` through PostgREST — the first Critical of the audit (`SECURITY.md` §3.1). Everything
else downstream (cross-tenant reads, finances, the audit log) fell out of that one root cause.

**The reasoning to reuse:** whenever a policy grants a row to its own subject, ask which *columns* on
that row are privileged, and put a trigger on them. RLS cannot express it.

### 3.4 Foreign keys must stay inside the tenant

**Decision.** Triggers enforce referential tenancy: `app.assert_student_in_hostel()` on
`fee_payments`, `visitors`, `complaints` and `leaves`; `app.students_identity_guard` on `students`
(no repointing `user_id` or `hostel_id`, and a linked account must be a student of the same hostel);
`app.tasks_assignee_guard` on `tasks` (assignee must be **this hostel's active manager**).

**Why.** RLS answers *"is this row mine?"*. It cannot answer *"do this row's foreign keys stay inside
my tenant?"*. Two Criticals lived in exactly that gap and were invisible to an 80-case attack suite
that only ever asked the first question (`SECURITY.md` §3.4, §3.5): a student record could be
relinked to another tenant's account, and a warden could fabricate fee debt, visitors, complaints and
leave records against residents of a hostel they had no access to — which the victim then saw on
their own dashboard.

**The rule this creates:** any new table carrying both a `hostel_id` **and** a reference to a
tenant-scoped row needs the same guard. Add it in the same change as the table. RLS will not catch it
and neither will a review that only reads policies.

### 3.5 A student sees only their own room's beds, and only roommates' names and phones

**Decision.** `beds_select` limits students to the beds in their own room. `st_my_roommates()`
returns name and phone only.

**Why.** The bed rows carry `beds.student_id`, so a hostel-wide read let a student map every occupied
bed to another resident's account UUID (`SECURITY.md` §3.7 item 17). And `CLAUDE_2.md` §6.5 grants
roommates' "names and phone numbers only" — the function was also returning `photo_url`, which is
more than the spec allows (item 18). Both are small; both are the kind of over-fetch that becomes a
privacy finding the moment there is a real resident behind the row.

### 3.6 The Manager may only move a task's status

**Decision.** `tasks_update` lets the assignee update the row, and `app.tasks_before_update()`
refuses if a manager changes `title`, `description`, `due_date`, `assigned_to`, `created_by` or
`deleted_at`.

**Why.** The owner assigns work; the manager reports on it. Without the trigger, "can update the row"
would have meant "can rewrite the task they were given", which defeats the point of assigning it.
This is another column-level rule that RLS cannot express.

### 3.7 The Super Admin is read-only into tenants **by product intent, not by RLS**

**Decision, stated honestly.** `CLAUDE_2.md` §6.1 says the Super Admin is "read-only into tenant data
(monitoring, not editing)", and the UI implements that — there is no super-admin page that edits a
resident.

**But `app.is_super_admin()` short-circuits `app.has_role_in()` and `app.is_staff_of()`
(`db/schema.sql`), so at the database layer the Super Admin can write tenant rows through PostgREST.**
The "read-only" property is a UI property, not an enforced boundary.

**Why it is left this way.** The Super Admin is the platform root: they can already suspend a tenant,
reset an owner's password and change hostel structure. A boundary you can walk around by resetting
the owner's password is not a boundary. What matters instead is that the role is *small, few, audited
and MFA-protected* — see §5.

**What this means operationally.** Treat a super-admin compromise as SEV1 by definition
([`incident-response.md`](./incident-response.md) §1), monitor `sa.*` actions weekly
([`logging-and-monitoring.md`](./logging-and-monitoring.md) §5.2), and do not describe the platform
to a customer as "our staff cannot see or change your data" — it is not true, and the honest version
("privileged access is limited, logged and reviewed") is defensible.

### 3.8 Deactivation is honoured immediately, not at token expiry

**Decision.** `app.user_role()` and `app.user_hostel_id()` resolve only for accounts that are
`status = 'active' and deleted_at is null`, and the `users_select` self-branch carries the same
predicate.

**Why.** Without the predicate on the self-branch, a deactivated account kept PostgREST access to its
own `users` row until its access token expired (`SECURITY.md` §3.3 item 9). With it, deactivation
takes effect on the very next request, on the token the attacker already holds. This is what makes
§4.1 of the incident-response doc a real containment step rather than a delayed one.

### 3.9 No hard deletes from the application

**Decision.** Every `*_delete` policy is `app.is_service_role()`. Soft delete (`deleted_at`,
`status = 'vacated'`) is the application's only removal mechanism.

**Why.** `CLAUDE_2.md` §4.10. It preserves the fee ledger, complaint history and audit correlation.
The cost is that **erasure requires an operator with the service role** — see
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6, which is where that debt is
paid.

---

## 4. Joiner, mover, leaver

There is **no self-registration and no self-service password reset** — no account exists that someone
did not deliberately create, and there is no email provider (`THREAT-MODEL.md` §8). Every credential
event is administrator-driven and every one of them is audited.

### 4.1 Joiner

| Account | Created by | Action | Audit action |
|---|---|---|---|
| Owner + hostel + subscription | Super Admin | Wizard → `createOwnerAndHostel` (`lib/actions/super-admin.ts`) | `sa.owner_hostel.create` |
| Manager / Warden | Owner | Staff → Create (`createStaff`, `lib/actions/owner.ts`) | `owner.staff.create` |
| Student | Warden | Register student (`registerStudent`, `lib/actions/warden.ts`) — creates the student record **and** the login | `warden.student.register` |
| Super Admin | Seed script only | `npm run db:seed:admin` | — |

Every new account gets a generated password of the form `Word-1234-Word`
(`generatePassword()`, `lib/auth/password.ts`, using `crypto.randomInt`) and
`must_change_password = true`. The password is **displayed once** in the creating administrator's
browser and is never emailed, stored in plaintext, or retrievable.

**Handover is the weakest link in this design, and it is a human process, not a code one.** Read the
password to the person, or hand it over in person. Do not forward it. If it is sent over a messaging
app, treat that message as a live credential and reset it (§4.3 of the incident-response doc) once
they have signed in.

Role limits are enforced at the storage layer, not by a count: exactly 1 active manager and 1 active
warden per hostel, via a **partial unique index**, because the original `count(*)` trigger was
TOCTOU-vulnerable under concurrency (`SECURITY.md` §3.3 item 4). Deactivating frees the slot.

**On first sign-in** the forced-password-change gate fires in middleware *and* in `requireUser()` /
`assertRole()`, so it cannot be routed around.

### 4.2 Mover

| Change | How | Note |
|---|---|---|
| Owner adds a second hostel | Super Admin creates it against the existing owner | The owner gets a hostel switcher; `getHostelContext()` re-validates the cookie against ownership on every request |
| Student changes room or bed | Warden → Reassign bed (`reassignBed`) | Bed ↔ student consistency is trigger-maintained; `students.bed_id` is the source of truth and direct edits to `beds.student_id` are refused |
| Staff member changes role (warden → manager) | **Not supported.** `users_update_guard` refuses any `role` change from a non-super-admin, on every write path | Deactivate the old account and create a new one. This is the correct outcome: role changes should mint a new identity, not mutate an existing one |
| Staff or student moves to another hostel | **Not supported.** `hostel_id` is immutable for the same reason | Deactivate and re-create at the destination |

### 4.3 Leaver

| Who | Action | What happens |
|---|---|---|
| Manager / Warden | Owner → Staff → Deactivate (`setStaffStatus`) | `users.status = 'inactive'` **and** the auth user is banned (`setAccountStatus()`, `lib/auth/accounts.ts`). RLS helpers return NULL immediately; middleware signs them out on the next request. Audited as `owner.staff.status` |
| Student | Warden → Vacate (`vacateStudent` → `wd_vacate_student`) | `students.status = 'vacated'`, the linked `users` row goes inactive, and the bed is freed automatically — the `students_bed_guard` trigger nulls `bed_id` on vacate and `students_bed_sync` frees the bed. Audited as `warden.student.vacate` |
| Owner | No in-app deactivation path | Suspend the hostel (`setHostelStatus`) and/or set `users.status = 'inactive'` by SQL plus an auth ban ([`incident-response.md`](./incident-response.md) §4.1) |
| Super Admin | No in-app path | Supabase Dashboard → Authentication → Users |

**Same-day checklist for a departing staff member**, in order:

1. Deactivate the account (above) — this is the step that actually removes access.
2. If they held the `SUPABASE_SERVICE_ROLE_KEY` or the Supabase/Vercel dashboard logins, **rotate the
   key** ([`incident-response.md`](./incident-response.md) §4.5) and remove their dashboard access.
   Deactivating their HostelPro account does nothing about either.
3. Reset the passwords of any account whose once-shown credentials they handled (§4.1).
4. Check `audit_log` for their activity in their last 30 days — not out of suspicion, but because
   this is the only moment anyone will ever look:
   `select at, action, target_type, target_id from public.audit_log where actor_user_id = '<uuid>' and at > now() - interval '30 days' order by at;`
5. Create the replacement account **after** step 1, or the 1-active-per-role index will refuse it.

**Data is not deleted on departure.** Soft delete is the rule (§3.9). Actual erasure is a separate,
deliberate act — [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.

---

## 5. Administrative and break-glass access

Four things sit outside the role model. They are the real crown jewels — the role matrix is
irrelevant to anyone holding any of them.

| Access | What it grants | Held by | Controls |
|---|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | **Bypasses RLS entirely.** Read and write every row in every tenant, including `audit_log` | Vercel production env; a developer workstation's `.env.local` | `server-only` module guards, a CI assert that no server secret reaches the client bundle, and `scripts/security-scan.mjs` over the working tree **and all git history** |
| Supabase Dashboard | The above, plus auth admin, key rotation, log access, and the ability to disable RLS | Supabase account owner | Account MFA — **enable it if it is not on** |
| Vercel Dashboard | Environment variables (i.e. the service-role key), deployments, access logs | Vercel account owner | Account MFA |
| `super_admin` role | Platform-wide read, tenant lifecycle, owner password resets, and — see §3.7 — tenant writes at the DB layer | The one seeded platform admin | MFA (§5.2), and every action audited under `sa.*` |

### 5.1 Rules for the service-role key

- Only the modules on the scanner's allow-list may import the admin client — the client factory
  itself, account management, storage, rate limiting, auditing, one warden action, and the seed
  script (`ADMIN_ALLOWED` in `scripts/security-scan.mjs`). A rogue importer is a **build blocker**,
  not a warning. Keep the list short; every entry on it is a module that can read every tenant.
- Every caller **authorizes first** and only then uses it. It is the mechanism, never the
  authorization.
- It is not a debugging convenience. Reading production data with it leaves no `audit_log` entry.
- **It must be rotated before the project is handed to a customer** — it has been used from a
  developer workstation throughout the build (`SECURITY.md` §5, Info). Procedure and the
  login-outage trap: [`incident-response.md`](./incident-response.md) §4.5.

### 5.2 MFA

TOTP is available to every role at `/security/mfa` and can be **required** per role via the
`MFA_REQUIRED_ROLES` environment variable (comma-separated, `lib/supabase/middleware.ts`,
`lib/actions/mfa.ts`). When a role is listed, an account without a verified factor is redirected to
enrolment and cannot use the app until it enrols.

**Current value in `.env.example` is empty. The documented recommendation for production is
`MFA_REQUIRED_ROLES=super_admin,owner`, and that is the minimum this document endorses** — those two
roles between them can create staff, reset passwords, read every resident's PII and change tenant
lifecycle. Verify the deployed value in Vercel; an empty variable means MFA is optional for everyone.

Two properties to be honest about:

- **MFA-01 (accepted risk, `SECURITY.md` §5):** TOTP codes are not single-use — a code consumed by
  one session can be replayed into a second session inside its 30-second window. This is Supabase
  GoTrue behaviour and cannot be patched here. It does not weaken MFA against plain password
  compromise; it does weaken it against real-time phishing. Treat MFA as defence in depth.
- Enrolment and unenrolment are both audited (`auth.mfa.enrolled` / `auth.mfa.unenrolled`), and
  unenrolment is an alert ([`logging-and-monitoring.md`](./logging-and-monitoring.md) §6, A5).

Also enable **leaked-password protection** in Supabase → Authentication → Settings. It is dashboard-
only, needs the account owner, and is still off (`SECURITY.md` §5, Info).

### 5.3 Break-glass

There is no separate emergency account, and there should not be one — an unused privileged account is
an unmonitored one. The break-glass path *is* the Supabase dashboard, held by the account owner. What
that requires:

- The Supabase account owner's contact details are in the incident contact table
  ([`incident-response.md`](./incident-response.md) §2). **Fill it in.**
- Dashboard access must not depend on a mailbox that a HostelPro compromise could reach.
- Any dashboard action taken during an incident goes in the incident log — Supabase Auth logs record
  Admin API calls, but they will not record *why*.

---

## 6. Review cadence

| Cadence | Who | What | Evidence it happened |
|---|---|---|---|
| **Per change** | Author | Any PR touching `db/rls-policies.sql`, `db/schema.sql`, `lib/permissions.ts` or `middleware.ts` runs the checklist in §7 and the two attack suites | CI run + the suite output in the PR |
| **Weekly** | Platform operator | Every `sa.*`, `owner.staff.*` and `auth.mfa.unenrolled` in the last 7 days reconciles to something known | [`logging-and-monitoring.md`](./logging-and-monitoring.md) §5.2 |
| **Monthly** | Platform operator | `select role, status, count(*) from public.users where deleted_at is null group by 1,2;` — does the shape match reality? Exactly one active manager and one active warden per hostel? | Query output in the ops log |
| **Quarterly** | Platform operator + each hostel owner | **Full access review.** Every active account in the tenant, named, with a person still in that job behind it. Deactivate anything unrecognised on the spot | Signed-off list per tenant |
| **Quarterly** | Platform operator | Administrative access (§5): who holds the Supabase and Vercel logins, is MFA on for both, is `MFA_REQUIRED_ROLES` still set, when was the service-role key last rotated | Ops log |
| **On any role/policy change** | Author | Re-run all four suites against production | `SECURITY.md` §6 |
| **Annually** | Platform operator | Re-read §3 and ask whether each narrowing still matches the product. Grants drift outward; nobody notices | This document, dated |

The quarterly tenant review is the one that catches the failure this system is most exposed to: a
warden who left three months ago whose account is still active because deactivation is a human step
in a small business. Deactivation is the only control that removes access — nothing expires by
itself.

---

## 7. Checklist for changing access control

Run this whenever a policy, role, table or privileged action changes.

1. **What role needs this, and which page, query or action of theirs uses it?** If you cannot name
   one, do not grant it (§3.1).
2. **Which columns on the granted row are privileged?** If the policy grants a row to its own subject,
   a trigger must protect `role`, `hostel_id`, `status`, `id`, or anything else that decides
   authorization (§3.3).
3. **Does the new table or column reference a tenant-scoped row?** If it carries both a `hostel_id`
   and a foreign key to another tenant-scoped row, it needs an `assert_*_in_hostel`-style trigger in
   the same change (§3.4).
4. **Is the write gated on `app.hostel_writable()`?** Every tenant write must be, or the subscription
   paywall and the suspend-tenant containment step both leak.
5. **Does the privileged action call `audit()`?** Sixteen actions once did not
   ([`logging-and-monitoring.md`](./logging-and-monitoring.md) §2.1).
6. **Test it from PostgREST, not from the UI.** Add a case to `scripts/_qa-rls-attack.mjs` or
   `scripts/_qa-tenant-integrity.mjs`, then **canary-verify it**: plant the flaw, confirm the test
   fails, remove the flaw. A test that has never failed has not been shown to work.
7. **Run all four suites against production** and update the matrix in §2 in the same commit.
