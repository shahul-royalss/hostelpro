# SECURITY.md — pre-release security sign-off

**Application:** HostelPro — multi-tenant PG/hostel management SaaS
**Stack:** Next.js 15 (App Router, Server Components + Server Actions) · React 19 · Supabase (Postgres + RLS + Auth + private Storage)
**Production:** https://hostelpro-three.vercel.app (Vercel) · Supabase project `nimxvgzscbanhtvgnjll`
**Audit date:** 2026-08-17 · **Method:** threat model → manual source review → automated sweeps → live exploitation (app + direct PostgREST) → adversarial verification of every serious finding.

---

## 1. Verdict

**No Critical and no High findings remain open.** One Critical and one High were found during this audit and are **fixed and re-tested** (details in §3). The remaining open items are Low, listed in §5 with owners.

Release-blocker checklist (§41 of the review standard) — all clear:

| Blocker | Status |
|---|---|
| Secrets exposed / in frontend / in git history | None — full-history scan clean; only `NEXT_PUBLIC_SUPABASE_URL/ANON_KEY` reach the browser |
| Broken access control · cross-user · cross-tenant | None — 80/80 direct-PostgREST attacks blocked |
| Privilege escalation | **Found & fixed** (§3.1) |
| Authentication bypass | **Found & fixed** (§3.2) |
| SQL/NoSQL/command injection · RCE | None — no raw SQL, no shell exec, no `eval`, no `dangerouslySetInnerHTML` |
| Unauthenticated admin endpoint | None |
| Public private-storage bucket | None — all three buckets private; anon GET → HTTP 400 |
| Critical SSRF | None — no server-side fetch of user-supplied URLs; image optimizer disabled |
| Payment/business-logic bypass | N/A (no payment provider); subscription read-only gate enforced in DB |
| Production debug mode / stack traces | None — prod build verified: no tokens, no `webpack-internal`, sanitized errors |
| Service-role credential in frontend | None — `server-only` guards + client-bundle greps clean |
| Secrets in logs | None — TS **and** DB-side scrubbing of credential-ish keys |

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

---

## 3. Findings fixed during this audit

### 3.1 CRITICAL — any user could make themselves Super Admin
**Root cause.** RLS gates *rows*, not *columns*. The `users_update` policy allowed `id = auth.uid()`, so any authenticated user could call PostgREST directly and rewrite their own privileged columns:

```
PATCH /rest/v1/users?id=eq.<self>   {"role":"super_admin"}
```

Confirmed live: a seeded student became `super_admin`, after which every other isolation control fell away (they could then read all tenants, all finances and the audit log — those cascading failures had a single root cause).

**Fix.** `app.users_update_guard` — a `BEFORE UPDATE` trigger on `public.users` that makes `role`, `hostel_id`, `status`, `created_by` and `id` privileged on **every** write path (app, PostgREST, SQL). Self-service is limited to `full_name`, `phone`, `email`, `must_change_password`; account status may only be changed by that account's administrator; the service role (used by authorized server actions) is exempt. Verified: escalation blocked, legitimate self-service still works.

### 3.2 HIGH — middleware bypass via a URL ending in an image extension
**Root cause.** The matcher excluded `.*\.(svg|png|jpg|jpeg|gif|webp|ico)$` — which matches *any* URL ending that way, including real dynamic routes such as `/warden/rooms/x.png`. Confirmed live: those requests ran with **no CSP/COOP**, and Server Actions posted to them still executed, while the forced-password-change and MFA step-up gates — which lived **only** in middleware — were skipped entirely.

**Fix, in two layers:**
1. The matcher now excludes only genuine asset prefixes (`_next/static/`, `_next/image/`, `favicon.ico`, `icons/`, `manifest.webmanifest`, `robots.txt`) — never by extension.
2. **Defense in depth:** `must_change_password` and MFA (AAL) are now re-checked in `requireUser()` and `assertRole()`, so every Server Component, Server Action and Route Handler enforces them independently of routing. An authentication control that exists in exactly one place, keyed off a hand-written regex, is one typo away from this exact bug.

### 3.3 Medium and Low, fixed
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

---

## 4. Controls in place

**Authorization (the checklist's #1 risk).** Every tenant table carries `hostel_id`; RLS policies gate SELECT/INSERT/UPDATE/DELETE via `SECURITY DEFINER` helpers with fixed `search_path`. Server Actions independently `zod`-validate → `assertWritableContext(role)` → use the RLS-enforced client, and **never** trust a client-supplied `hostel_id`. Business rules (bed uniqueness, role limits, subscription read-only, manager-may-only-change-task-status) are enforced by DB triggers, so they hold even against direct API calls.

**Authentication.** Single login for five roles; students authenticate by phone (mapped to a synthetic email). Session cookies are `httpOnly` + `SameSite=Lax` + `Secure` in production, and there is **no browser Supabase client**, so JavaScript never touches a token. Generated passwords are shown once and forced to be changed. TOTP MFA is available for every role and enforceable per role via `MFA_REQUIRED_ROLES`. `getUser()` (server-verified) is used for authorization — never `getSession()`, and never JWT `app_metadata`.

**Abuse.** Durable, DB-backed rate limiting (login per-IP and per-identifier, password change, MFA verify, account creation, uploads, general writes). Auth limiters fail **closed**.

**Uploads.** Magic-byte content sniffing (declared MIME ignored), server-generated UUID filenames, 8 MB cap, private buckets, tenant-scoped short-lived signed URLs.

**Headers.** Per-request nonce CSP with `strict-dynamic` (no `unsafe-eval` in production — verified), HSTS, `X-Frame-Options: DENY`, `nosniff`, Referrer-Policy, Permissions-Policy, COOP. Verified live on the deployed site; all 44 script tags carry the nonce and React hydrates cleanly.

**Audit.** `public.audit_log` records authentication events and every privileged action with actor, role, target, tenant, IP and user-agent. Readable by the Super Admin (all) and the owner (own hostel); **no** user INSERT/UPDATE/DELETE policy exists.

---

## 5. Open items (accepted for the demo release)

| Sev | Item | Owner / action |
|---|---|---|
| Low | Any authenticated user can read *any* hostel's subscription state via `rpc_hostel_stats` (counts are still RLS-filtered to zero) | Scope the subscription fields to the caller's hostel |
| Low | Raw storage object keys are included in the RSC payload next to the signed URL | Strip before serialization |
| Low | Over-8 MB uploads surface Next's body-size error rather than the friendly message | Add a client-side size check on the remaining upload forms |
| Low | No retention policy for `audit_log` IP/user-agent | Define retention + alerting before real tenants |
| Info | Supabase **leaked-password protection** is off | Enable in Dashboard → Authentication → Settings (dashboard-only) |
| Info | `npm audit`: 3 High in `postcss`/`sharp` **bundled inside Next** | Not reachable — `postcss` is build-time; `sharp` backs the image optimizer, which this app does not use. Re-evaluate on the next Next.js minor |
| Info | Two audit agents (input-validation, privacy/code-quality) died on network errors | Their areas are partly covered by the other five; re-run before onboarding real customers |

**Not done (out of scope for a demo, required before real customer data):** independent penetration test, CI security scanning (SAST/secret/dependency), backup restore drill, alerting owner for suspicious-activity monitoring.

---

## 6. Sign-off

The application is **approved for a client demonstration** on the deployed URL with seeded demo data. No Critical or High vulnerability is open; every fix in §3 was re-tested, and the 80-case attack suite passes.

Before onboarding **real** tenants and real personal data, complete the §5 open items plus a penetration test and CI security scanning.
