# THREAT-MODEL.md — NIVORA

GOD-MODE checklist **§1**. This is the inventory the rest of the security work is measured
against: if an asset, boundary or entry point is not listed here, it was not tested.

Companion documents: [`SECURITY.md`](./SECURITY.md) (findings + sign-off),
[`DECISIONS.md`](./DECISIONS.md) (rule → enforcement map).

---

## 1. System shape

Single Next.js 15 application (Vercel) + Supabase (Postgres, Auth, Storage), wrapped for Android
as a Trusted Web Activity (`app.nivora.twa`) that loads the same deployment. **No** background
workers/queues, **no** AI/LLM integration, **no** second backend.

Since 24 Aug 2026 there IS a payment provider and there IS a webhook, and both widen this model:
  * **Razorpay** processes online rent payments. Two server-side outbound calls now exist —
    `app/api/health/route.ts` → the Supabase health URL, and `lib/razorpay.ts` → the Razorpay
    orders API. Neither is built from user input.
  * **`POST /api/webhooks/razorpay`** is a new UNAUTHENTICATED entry point: Razorpay is not a
    signed-in user, so it is exempt from the session gate. Its authentication is an HMAC-SHA256
    over the RAW request body, compared with `timingSafeEqual`. That signature check is the only
    thing standing between the public internet and the fee ledger — treat it as the highest-value
    control in the application and see §6 for what was tested against it.
  * Razorpay's Checkout script runs in the browser, and the CSP grants its origins **only** on
    `/student` routes rather than app-wide (`lib/security-headers.ts`).

Trust boundaries, outermost first:

| # | Boundary | Crossing | Enforced by |
|---|---|---|---|
| B1 | Internet → Vercel edge | any HTTP request | middleware: session refresh, security headers, route-group role gate |
| B2 | Browser → Server Actions / Route Handlers | mutations, exports | `zod` → `assertWritableContext(role)` → RLS client |
| B3 | **Browser → PostgREST directly** | any authenticated user with the public anon key | **RLS policies + triggers only** |
| B4 | App server → Postgres as `service_role` | account creation, uploads, rate limit, audit | `server-only` modules, callers authorize first |
| B5 | Tenant ↔ Tenant | every row and file | `hostel_id` + RLS helpers + storage path prefix |
| B6 | Role ↔ Role inside a tenant | privileged columns/actions | RLS + `users_update_guard`, `tasks_before_update`, RPC guards |

> **B3 is the boundary that matters most.** The anon key and REST endpoint are public, so any
> control that lives only in React or only in middleware is worthless there. Every
> authorization claim in this project is therefore tested twice: through the app, and again
> straight against PostgREST (`scripts/_qa-rls-attack.mjs`).

---

## 2. Assets worth protecting

| Asset | Where | Sensitivity | Blast radius if lost |
|---|---|---|---|
| Student PII — name, phone, guardian name/phone, permanent address | `students` | **High** (minors possible) | Privacy harm, regulatory exposure |
| ID-proof scans & photos | Storage `student-docs` (private) | **High** | Identity theft |
| Fee ledger | `fee_payments` | High | Financial dispute, fraud |
| Hostel finances — expenses, revenues | `expenses`, `revenues` | Medium | Commercial confidentiality |
| Complaints (may name people) | `complaints`, `complaint_events` | Medium | Retaliation, privacy |
| Subscription & billing state | `subscriptions`, `hostels.status` | High | Free service, revenue loss |
| Credentials & sessions | Supabase Auth, cookies | **Critical** | Full account takeover |
| Audit trail | `audit_log` | High | Loss of forensic truth |
| `service_role` key | Vercel env, `.env.local` | **Critical** | Total DB compromise (bypasses RLS) |

## 3. Roles and privilege boundaries

`super_admin` → platform-wide, creates owners/hostels/subscriptions, read-only into tenants.
`owner` → one or more own hostels; creates/deactivates the 1 manager + 1 warden; cannot renew
own subscription (that is the paywall — SA only). `manager` → finance/ops for one hostel.
`warden` → students/rooms/fees for one hostel. `student` → own record only, plus roommates'
**name and phone** and shared hostel info.

Escalation paths explicitly tested and blocked: student→any role, owner→super_admin,
owner→another tenant, warden→another tenant, manager→task ownership, deactivated→still active,
`must_change_password`/MFA-pending→full session.

## 4. Entry points (complete inventory)

**Pages** (39 routes, all dynamic): `/login`, `/change-password`, `/mfa`, `/security/mfa`,
`/404`, and the five role groups `/super-admin/*`, `/owner/*`, `/manager/*`, `/warden/*`,
`/student/*`.
**Route handlers:** `GET /api/health` (public, no config disclosure), `GET /api/manager/export`
(cookie-auth, manager/owner, own hostel only, no tenant parameter).
**Server Actions:** `lib/actions/{auth,session,mfa,complaints,super-admin,owner,manager,warden,student}.ts`.
**Database RPCs** (`SECURITY DEFINER`, each re-checks authorization internally):
`sa_create_hostel_with_subscription`, `sa_renew_subscription`, `sa_update_hostel_structure`,
`wd_register_student`, `wd_vacate_student`, `wd_record_payment`, `ow_update_hostel_rules`,
`st_my_roommates`, `st_hostel_contacts`, `refresh_subscription_statuses`, the `rpc_*` read
helpers; plus `scaffold_hostel`, `rate_limit`, `audit_event` which are **not** user-executable.
**PostgREST:** every table in `public`, reachable with the public anon key — governed solely by RLS.
**Storage:** three private buckets — `student-docs`, `receipts`, `complaint-photos`.

## 5. Secrets

| Secret | Location | Exposure | Rotation |
|---|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Vercel env (encrypted) + local `.env.local` | server-only; `server-only` guards + CI bundle assert | Supabase dashboard → rotate → update Vercel |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | browser | **public by design**, safe because RLS | rotate with anon key |
| Supabase DB password | never in repo | not used by the app (PostgREST only) | dashboard |
| Vercel deploy token | local CLI auth | not in repo | `vercel logout` |

No SMTP, payment, cloud or signing keys exist. Verified by `npm run security:scan` over the
working tree **and all 81,914 lines of git history**.

## 6. Adversary scenarios

**A. Attacker registers/obtains a normal account (§36).** Cannot become admin, change own role
or tenant, read another user's or tenant's rows, mint a signed URL outside their tenant, call
SA/warden RPCs, or write while the subscription is expired. Verified live: 80/80 blocked.

**B. Attacker steals one session token (§37).** Token is `httpOnly`/`Secure`/`SameSite=Lax`
and no browser Supabase client exists, so script-level theft needs an XSS that the nonce CSP is
designed to prevent. With a stolen token the attacker gets exactly that user's scope — no
escalation, no tenant switch (the hostel cookie is re-validated against ownership server-side).
Mitigation: 1 h access-token lifetime; voluntary password change requires the current password
and revokes other sessions; deactivation is honoured on the next request and by RLS.
*Residual:* a stolen token remains valid for its lifetime — accepted, standard for JWT sessions.

**C. Database is compromised (§38).** Passwords are bcrypt hashes held by Supabase Auth, never
by the app. No secrets are stored in app tables. The audit trail supports investigation.
*Residual:* PII and ID-proof paths would be exposed — encryption-at-rest is the platform's;
field-level encryption is **not** implemented (accepted for this stage).

**D. Third-party (Supabase/Vercel) compromised (§39).** They are the trust root; compromise is
total. Mitigations are least-privilege keys and the ability to rotate. No other third-party
service receives user data — no analytics, no error reporter, no email/SMS provider.

**E. A dependency turns malicious (§22).** 29 production dependencies, all lockfile-pinned, all
used (verified — no unused packages). CI runs `npm audit` plus a bundle assert that no server
secret ships to the client. *Residual:* a malicious postinstall in a transitive package could
read build-time env — the standard supply-chain risk for any npm project.

## 7. Logging & data-at-rest posture

Sensitive information is deliberately **not** logged: `lib/audit.ts` strips credential-like keys
in TypeScript *and* `audit_event()` strips them again in SQL; failed-login identifiers are
SHA-256 hashed; `errorMessage()` allow-lists user-facing text and logs raw errors server-side
only. IP and user-agent are recorded in `audit_log` for forensics — this is PII and needs a
retention policy before real tenants (open item in `SECURITY.md` §5).

## 8. Explicit non-goals at this stage

Field-level encryption of PII; SOC2/ISO controls; independent penetration test; WAF/DDoS beyond
Vercel defaults; email/SMS notification channel (v1 is in-app only); data-subject deletion
tooling (soft-delete only today).
