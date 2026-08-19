# SECURITY.md — pre-release security sign-off

**Application:** HostelPro — multi-tenant PG/hostel management SaaS
**Stack:** Next.js 15 (App Router, Server Components + Server Actions) · React 19 · Supabase (Postgres + RLS + Auth + private Storage)
**Production:** https://hostelpro-three.vercel.app (Vercel) · Supabase project `nimxvgzscbanhtvgnjll`
**Audit date:** 2026-08-17 (round 1) · 2026-08-20 (round 2) · **Method:** threat model → manual source review → automated sweeps → live exploitation (app + direct PostgREST) → adversarial verification of every serious finding.

---

## 1. Verdict

**No Critical and no High findings remain open.** Across two rounds, **three Critical and three High** findings were found and are **fixed and re-tested** (details in §3). The remaining open items are Low/Info, listed in §5 with owners.

> **Round 2 (2026-08-20) matters.** Round 1 signed off on "80/80 PostgREST attacks blocked". That was true and still is — but it was testing the wrong invariant. RLS gates **the row's own `hostel_id`**; it says nothing about **where that row's foreign keys point**. Two further Criticals lived in exactly that blind spot and were invisible to the round-1 suite. Both are fixed, and `scripts/_qa-tenant-integrity.mjs` now tests the invariant the old suite could not express.

Release-blocker checklist (§41 of the review standard) — all clear:

| Blocker | Status |
|---|---|
| Secrets exposed / in frontend / in git history | None — full-history scan clean; only `NEXT_PUBLIC_SUPABASE_URL/ANON_KEY` reach the browser |
| Broken access control · cross-user · cross-tenant | **Found & fixed** (§3.4, §3.5) — now 80/80 + 32/32 attacks blocked |
| Privilege escalation | **Found & fixed** (§3.1, §3.6) |
| Authentication bypass | **Found & fixed** (§3.2, §3.4) |
| SQL/NoSQL/command injection · RCE | None — no raw SQL, no shell exec, no `eval`, no `dangerouslySetInnerHTML` |
| Unauthenticated admin endpoint | None |
| Public private-storage bucket | None — all three buckets private; anon GET → HTTP 400 |
| Critical SSRF | None — no server-side fetch of user-supplied URLs; image optimizer disabled |
| Payment/business-logic bypass | N/A (no payment provider); subscription read-only gate enforced in DB |
| Production debug mode / stack traces | None — prod build verified: no tokens, no `webpack-internal`, sanitized errors |
| Service-role credential in frontend | None — `server-only` guards + client-bundle greps clean |
| Secrets in logs | None — TS **and** DB-side scrubbing of credential-ish keys |
| Vulnerable dependencies | None — `npm audit` 0 vulnerabilities (was 3 High; see §3.7) |

---

## 2. What was tested, and how

Testing was **live**, not just by reading code. Two independent paths were used for every authorization claim:

1. **Through the app** — real sessions via the login form and server actions over HTTP.
2. **Bypassing the app entirely** — signing in with the public anon key and hitting **PostgREST directly**. This is the decisive test: the anon key and REST endpoint are public, so any control that exists only in React or only in middleware is worthless here.

`scripts/_qa-rls-attack.mjs` is the committed, repeatable version of that second path: **80 attacks, 0 succeed.** Run it after any RLS/policy/trigger change:

```bash
node scripts/_qa-rls-attack.mjs
```

Coverage: student self-escalation (role/tenant/fee/status), cross-user reads and writes, cross-tenant reads and writes across all four tenant roles, owner privilege boundaries (super admin, other tenants, self-renewing a subscription), expired-subscription write gate, audit-log integrity, and full anonymous access to every table and RPC.

**Round 2 added the invariant that suite could not express.** Its every case asks *"does this row belong to my tenant?"* — a question `hostel_id` alone answers. It never asks *"do this row's **foreign keys** stay inside my tenant?"*, and two Criticals lived precisely there (§3.4, §3.5). `scripts/_qa-tenant-integrity.mjs` covers that, plus role least-privilege and input guards:

```bash
node scripts/_qa-tenant-integrity.mjs   # 32 cases, 0 succeed
```

Coverage: `students.user_id` repointing (cross-tenant account takeover), cross-tenant `student_id` on `fee_payments`/`visitors`/`complaints`/`leaves`, `tasks.assigned_to` validation, the Manager's resident-PII surface, the student's bed/roommate surface, numeric `NaN` and overflow through **direct PostgREST as well as the RPC**, and unbounded text.

Two further suites run against the **deployed site**, not localhost (§36):

```bash
node scripts/_qa-prod-authz.mjs   # 145 role x route checks: every role reaches its own pages, no role reaches another's
node scripts/_qa-mfa.mjs          # TOTP enrol -> wrong code rejected -> correct code -> aal2 -> replay -> unenrol
```

Each suite was **canary-verified**: a flaw was deliberately planted and the suite was confirmed to catch it, so a green run means the tests actually exercise the control rather than passing vacuously.

---

## 3. Findings fixed during this audit

### 3.1 CRITICAL — any user could make themselves Super Admin (round 1)
**Root cause.** RLS gates *rows*, not *columns*. The `users_update` policy allowed `id = auth.uid()`, so any authenticated user could call PostgREST directly and rewrite their own privileged columns:

```
PATCH /rest/v1/users?id=eq.<self>   {"role":"super_admin"}
```

Confirmed live: a seeded student became `super_admin`, after which every other isolation control fell away (they could then read all tenants, all finances and the audit log — those cascading failures had a single root cause).

**Fix.** `app.users_update_guard` — a `BEFORE UPDATE` trigger on `public.users` that makes `role`, `hostel_id`, `status`, `created_by` and `id` privileged on **every** write path (app, PostgREST, SQL). Self-service is limited to `full_name`, `phone`, `email`, `must_change_password`; account status may only be changed by that account's administrator; the service role (used by authorized server actions) is exempt. Verified: escalation blocked, legitimate self-service still works.

### 3.2 HIGH — middleware bypass via a URL ending in an image extension (round 1)
**Root cause.** The matcher excluded `.*\.(svg|png|jpg|jpeg|gif|webp|ico)$` — which matches *any* URL ending that way, including real dynamic routes such as `/warden/rooms/x.png`. Confirmed live: those requests ran with **no CSP/COOP**, and Server Actions posted to them still executed, while the forced-password-change and MFA step-up gates — which lived **only** in middleware — were skipped entirely.

**Fix, in two layers:**
1. The matcher now excludes only genuine asset prefixes (`_next/static/`, `_next/image/`, `favicon.ico`, `icons/`, `manifest.webmanifest`, `robots.txt`) — never by extension.
2. **Defense in depth:** `must_change_password` and MFA (AAL) are now re-checked in `requireUser()` and `assertRole()`, so every Server Component, Server Action and Route Handler enforces them independently of routing. An authentication control that exists in exactly one place, keyed off a hand-written regex, is one typo away from this exact bug.

### 3.3 Medium and Low, fixed in round 1
| # | Issue | Fix |
|---|---|---|
| 1 | `ow_update_hostel_rules` wrote to hostels whose subscription had expired (§4.4 bypass) | RPC now calls `app.hostel_writable()` like every other write |
| 2 | `audit_event` was executable by any authenticated user → forge/flood **another tenant's** audit trail | Service-role only; actor supplied by the server from the already-verified session |
| 3 | Secrets could be persisted into audit `meta` | Scrubbed in TypeScript **and** in the DB function |
| 4 | 1-manager/1-warden rule was a `count(*)` trigger — TOCTOU under concurrency | Added a partial unique index (race-proof at the storage layer) |
| 5 | `signedUrl()` echoed any stored `http(s)://` value verbatim → staff-writable `*_url` columns became arbitrary-URL injection into another user's page | Passthrough removed; only real objects under the caller's tenant prefix are signed |
| 6 | Uploaded PDFs rendered inline in the viewer's origin | `Content-Disposition: attachment` for documents (images stay inline) |
| 7 | Per-IP login limit bypassable by spoofing `X-Forwarded-For` | Prefer platform-set headers; otherwise take the **last** hop (`TRUSTED_PROXY_HOPS`) |
| 8 | Password change needed no reauth and left other sessions alive | Voluntary change requires the current password; other sessions revoked on success |
| 9 | Deactivated account kept PostgREST access to its own `users` row until token expiry | Active/not-deleted predicate added to the self branch of both users policies |
| 10 | Replaced/removed receipts and failed complaint photos were orphaned in storage | Cleaned up on replace, remove and rollback; upload rate limit added |
| 11 | CSV export returned raw exception text | Routed through the sanitizer; raw error logged server-side only |
| 12 | Login page indexable; no `robots.txt` | `robots.ts` + `noindex` metadata |
| 13 | `/_not-found` was statically prerendered → `strict-dynamic` CSP would block its scripts | Branded, dynamically-rendered 404 |
| 14 | `lib/supabase/server.ts` lacked the `server-only` guard | Added |

### 3.4 CRITICAL — a student record could be relinked to another tenant's account (round 2)
**Root cause.** RLS proved a `students` row belonged to the caller's hostel. Nothing proved that the row's **`user_id` foreign key** pointed at an account in that same hostel. `students.user_id` was freely writable:

```
PATCH /rest/v1/students?id=eq.<local student>   {"user_id":"<other tenant's account>"}
```

Confirmed live. `app.current_student_id()` resolves a session to a student row **through `user_id`**, so this silently moves a foreign account onto a local student record — that account then reads and writes the victim's fees, leaves, complaints and room as though they were its own. It is a cross-tenant account takeover that never touches `hostel_id`, so every `hostel_id`-based control (i.e. all of them) reports success.

**Fix.** `app.students_identity_guard` — a `BEFORE INSERT OR UPDATE` trigger that refuses to repoint `user_id` or `hostel_id` on an existing row, and on insert requires the linked account to be a **student of the same hostel**.

### 3.5 CRITICAL — cross-tenant `student_id` on four child tables (round 2)
**Root cause.** The same blind spot, one level down. `fee_payments`, `visitors`, `complaints` and `leaves` each carry both `hostel_id` and `student_id`. The RLS `WITH CHECK` validated only `hostel_id`. Setting `hostel_id` to your own hostel and `student_id` to **someone else's resident** passed every policy:

```
POST /rest/v1/fee_payments   {"hostel_id":"<mine>","student_id":"<their resident>","amount_due":99999}
```

Confirmed live for all four tables. A warden at one hostel could fabricate fee debt, visitor records, complaints and leave records against residents of a hostel they have no access to — and because the victim's own RLS matches on `student_id`, **the victim sees the forged rows in their own dashboard.**

**Fix.** `app.assert_student_in_hostel()` triggers on all four tables: if `student_id` is set, that student's `hostel_id` must equal the row's `hostel_id`.

### 3.6 HIGH — Manager could read every resident's PII; task assignment unbounded (round 2)
**Root cause (LMP-01).** `app.is_staff_of()` includes `manager`, and the resident-facing policies all used it. The Manager could therefore read every student's full PII, guardian phone, permanent address, fee ledger, leave history, visitor log and complaints. `CLAUDE_2.md` §6.3 scopes the Manager to expenses, revenue, tasks, mess menu and announcements — **no manager page, query or action touches a student table**, so this was pure over-grant.

**Root cause (IV-03).** `tasks.assigned_to` accepted any user id, including another tenant's staff, a student, or the Super Admin.

**Fix.** Resident reads are now `warden` + `owner` only (plus the student's own rows). The Manager keeps *staff* rows in `users` — needed to render tasks and announcements — but cannot enumerate residents. `app.tasks_assignee_guard` restricts `assigned_to` to this hostel's active manager. Verified the Manager dashboard still computes revenue/expense totals correctly afterwards.

### 3.7 Medium and Low, fixed in round 2
| # | Issue | Fix |
|---|---|---|
| 15 | **`wd_record_payment` was broken in production.** The round-1 hardening called `isnan()` — *not a Postgres builtin*. Every warden fee payment threw `function isnan(numeric) does not exist`. Caught by re-seeding, which is why seeding is part of the verification loop. | Correct test is `= 'NaN'::numeric`: Postgres numeric `NaN` compares **equal to itself**, so the IEEE `x <> x` idiom never fires |
| 16 | Money columns used a bare `amount >= 0` CHECK. Postgres numeric `NaN` sorts **above every number**, so `NaN >= 0` is `true` — a `NaN` inserted through PostgREST passed the constraint and poisoned every `sum()`, ledger and report | Finite upper bound added to all six money columns (`NaN <= cap` is `false`, so this rejects `NaN` *and* absurd values) |
| 17 | `beds_select` exposed every bed row in the hostel, including `beds.student_id` — a student could map each occupied bed to another resident's account UUID | Students see only their own room's beds |
| 18 | `st_my_roommates()` returned `photo_url`; §4.8 limits roommate data to name and phone | Column removed from the function and from `RoommateRow` |
| 19 | Unbounded text columns — a 200 KB complaint title was accepted | Length CHECKs on 7 tables |
| 20 | `npm audit`: 3 High (`postcss` arbitrary `.map` file read, `sharp`/libvips CVEs) | Pinned past both via `overrides`; **0 vulnerabilities**. Previously argued as unreachable — closing them outright is cheaper than defending the reachability argument |

---

## 4. Controls in place

**Authorization (the checklist's #1 risk).** Every tenant table carries `hostel_id`; RLS policies gate SELECT/INSERT/UPDATE/DELETE via `SECURITY DEFINER` helpers with fixed `search_path`. Server Actions independently `zod`-validate → `assertWritableContext(role)` → use the RLS-enforced client, and **never** trust a client-supplied `hostel_id`. Business rules (bed uniqueness, role limits, subscription read-only, manager-may-only-change-task-status) are enforced by DB triggers, so they hold even against direct API calls.

**Referential tenancy.** RLS answers *"is this row mine?"*; it cannot answer *"do this row's foreign keys stay inside my tenant?"*. That second question is enforced by triggers: `app.assert_student_in_hostel()` on `fee_payments`/`visitors`/`complaints`/`leaves`, `app.students_identity_guard` on `students` (no repointing `user_id`/`hostel_id`; a linked account must be a student of the same hostel) and `app.tasks_assignee_guard` on `tasks`. Any new table carrying both a `hostel_id` **and** a reference to a tenant-scoped row needs the same guard — RLS alone will not catch it.

**Authentication.** Single login for five roles; students authenticate by phone (mapped to a synthetic email). Session cookies are `httpOnly` + `SameSite=Lax` + `Secure` in production, and there is **no browser Supabase client**, so JavaScript never touches a token. Generated passwords are shown once and forced to be changed. TOTP MFA is available for every role and enforceable per role via `MFA_REQUIRED_ROLES`. `getUser()` (server-verified) is used for authorization — never `getSession()`, and never JWT `app_metadata`.

**Abuse.** Durable, DB-backed rate limiting (login per-IP and per-identifier, password change, MFA verify, account creation, uploads, general writes). Auth limiters fail **closed**.

**Uploads.** Magic-byte content sniffing (declared MIME ignored), server-generated UUID filenames, 8 MB cap, private buckets, tenant-scoped short-lived signed URLs.

**Headers.** Per-request nonce CSP with `strict-dynamic` (no `unsafe-eval` in production — verified), HSTS, `X-Frame-Options: DENY`, `nosniff`, Referrer-Policy, Permissions-Policy, COOP. Verified live on the deployed site; all 44 script tags carry the nonce and React hydrates cleanly.

**Audit.** `public.audit_log` records authentication events and every privileged action with actor, role, target, tenant, IP and user-agent. Readable by the Super Admin (all) and the owner (own hostel); **no** user INSERT/UPDATE/DELETE policy exists.

---

## 5. Open items

| Sev | Item | Owner / action |
|---|---|---|
| Low | **MFA-01 — TOTP codes are not single-use.** A code already consumed by one session can be replayed into a *second, fresh* session inside its 30-second window, stepping that session up to `aal2`. RFC 6238 §5.2 requires a verifier to reject second use. This is **Supabase GoTrue behaviour, not application code — we cannot patch it.** Exploiting it needs the password *and* a live code within 30 s (real-time phishing / shoulder-surfing); it does not weaken MFA against plain password compromise. | Accepted risk: treat MFA as defence-in-depth, not a sole control. Re-test with `node scripts/_qa-mfa.mjs` after Supabase upgrades; raise upstream if it persists |
| Low | Any authenticated user can read *any* hostel's subscription state via `rpc_hostel_stats` (counts are still RLS-filtered to zero) | Scope the subscription fields to the caller's hostel |
| Low | Raw storage object keys are included in the RSC payload next to the signed URL | Strip before serialization |
| Low | Over-8 MB uploads surface Next's body-size error rather than the friendly message | Add a client-side size check on the remaining upload forms |
| Low | No retention policy for `audit_log` IP/user-agent | Define retention + alerting before real tenants |
| Low | Audit coverage is partial — announcements, hostel rules, tasks, leaves, visitors, complaints, expenses and menu changes are not written to `audit_log`, and no UI surfaces the log | Extend `logAudit()` coverage; add a Super Admin log view |
| Low | Authentication audit rows carry `hostel_id = NULL`, so a hostel owner cannot see login events for their own staff | Resolve and stamp `hostel_id` on auth events |
| Low | No GDPR/DPDP erasure path — `students_delete` is service-role only and there is no tooling behind it | Build an erasure runbook before real personal data |
| Info | Supabase **leaked-password protection** is off | Enable in Dashboard → Authentication → Settings (dashboard-only; needs the account owner) |
| Info | Service-role key was used from a developer workstation throughout the build | Rotate before handing the project to a customer (Dashboard → Settings → API) |
| Info | No git remote, therefore no CI enforcement | `.github/workflows/security.yml` is committed and runs on push once a remote exists; enable branch protection + required checks + org MFA at that point |

**Not done (out of scope for a demo, required before real customer data):** independent penetration test, backup restore drill, alerting owner for suspicious-activity monitoring, and the erasure runbook above.

---

## 6. Sign-off

The application is **approved for a client demonstration** on the deployed URL with seeded demo data.

No Critical or High vulnerability is open. Every fix in §3 was re-tested, and the full verification suite passes against **production**, not only localhost:

```bash
node scripts/_qa-rls-attack.mjs        # 80/80  direct-PostgREST attacks blocked
node scripts/_qa-tenant-integrity.mjs  # 32/32  cross-tenant FK + least-privilege + input guards
node scripts/_qa-prod-authz.mjs        # 25/25  145 role x route checks on the deployed site
node scripts/_qa-mfa.mjs               #  6/6   TOTP enrol / verify / step-up (1 known upstream, MFA-01)
node scripts/security-scan.mjs         #  0 blockers, 0 warnings
npm audit                              #  0 vulnerabilities
```

**Caveat on scope.** Round 2 found two Criticals that round 1's 80-case suite structurally could not detect, because that suite only ever asked "does this row belong to my tenant?" — never "do this row's foreign keys stay inside my tenant?". Automated suites verify the invariants someone thought to write down. Before real tenants and real personal data, complete the §5 items and commission an **independent penetration test**; do not treat a green suite as proof of absence.

Before onboarding **real** tenants: rotate the service-role key, enable leaked-password protection, push to a remote so CI runs, and complete the §5 open items.
