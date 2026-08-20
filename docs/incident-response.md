# Incident response — HostelPro

**Scope:** the production deployment at https://hostelpro-three.vercel.app, the Supabase project
`nimxvgzscbanhtvgnjll` (Postgres + Auth + Storage), and the source repository.

Companion documents: [`../SECURITY.md`](../SECURITY.md) (findings + sign-off),
[`../THREAT-MODEL.md`](../THREAT-MODEL.md) (assets, boundaries, adversary scenarios),
[`logging-and-monitoring.md`](./logging-and-monitoring.md) (what you can actually see),
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) (what personal data is at stake).

This document exists because "we would investigate and fix it" is not a plan. Every command below is
written against the controls that actually exist in this codebase — where a control does **not**
exist, that is stated instead of glossed over.

---

## 0. Read this before anything else

Three facts change how you triage almost every incident here. They are properties of this build,
not general advice.

**1. Reads are not audited.** `public.audit_log` records authentication events and *privileged
writes* — 46 `audit()` / `auditSystem()` call sites across `lib/` (`lib/audit.ts`,
`lib/permissions.ts`), all on mutations or auth. **No read path writes an audit row.** A compromised
warden or owner account that browses every resident profile, fee ledger, leave and visitor record
leaves **no trace in the application at all**. Therefore: when a staff account is compromised, the
correct default assumption is that **everything that account could read, was read**. Do not wait for
evidence of exfiltration that the system is structurally incapable of producing.

**2. Rotating the service-role key without redeploying takes login down for everyone.**
`lib/rate-limit.ts` calls the `rate_limit` RPC with the service-role client and is invoked with
`failClosed = true` for both login limiters (`lib/actions/auth.ts`, lines 46–47). If
`SUPABASE_SERVICE_ROLE_KEY` is invalid, the limiter throws, fails closed, and **every sign-in is
refused**. Rotation is a two-step operation (§4.5) and the order matters.

**3. Suspending a hostel stops writes, not reads.** `app.hostel_writable()` (`db/schema.sql`)
requires `hostels.status = 'active'`; `app.can_read_hostel()` does not look at status at all. A
suspended tenant is read-only, not locked out. To actually cut access you must deactivate the
accounts (§4.1).

---

## 1. Severity classification

Classify on **blast radius**, not on how alarming it feels. Pick the highest row that matches.

| Sev | Definition | HostelPro examples | Ack | Containment target |
|---|---|---|---|---|
| **SEV1** | Confidentiality or integrity of *multiple tenants* is lost, or platform credentials are exposed | `SUPABASE_SERVICE_ROLE_KEY` leaked or in a public repo/log; super-admin account compromised; a cross-tenant authorization defect confirmed exploitable in production (the class of bug in `SECURITY.md` §3.1, §3.4, §3.5); Supabase or Vercel account takeover | 15 min | 1 hour |
| **SEV2** | One tenant's personal data or money records are exposed or altered by someone not entitled to them | Owner/warden/manager account compromised; resident PII or ID-proof scans reachable by the wrong role; fee ledger tampered with; a private storage bucket found public | 30 min | 4 hours |
| **SEV3** | One user account is compromised or abused, contained within its own scope | Student account taken over; credential stuffing against one identifier; repeated `authz.denied` from one actor probing other roles' routes | 2 hours | 1 business day |
| **SEV4** | Security-relevant defect with no confirmed exploitation | New `npm audit` High; a missing tenancy guard found by review before anyone used it; suspicious traffic with no successful auth | 1 business day | Next release |

**Escalate one level if any of these is true:** minors' data is in the affected set (see
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §3 — under-18 residents attract
DPDP §9 duties); ID-proof scans (`student-docs` bucket) are in scope; more than one hostel is
affected; or you cannot establish scope within the containment target. **Uncertain scope is SEV+1**,
always.

---

## 2. Roles

This is a small operation. The point of naming roles is that at any moment during an incident
exactly one person owns each of these, and everyone knows who.

| Role | Owns | Default holder |
|---|---|---|
| **Incident Lead (IL)** | Declares severity, runs the clock, decides containment, single decision-maker | Project owner |
| **Technical Responder (TR)** | Executes containment and evidence capture; touches production | Project owner (may be the same person as IL — say so out loud when it is) |
| **Communications Owner (CO)** | Tenant notification, regulator notification, all external wording | Project owner, with legal support for anything regulatory |
| **Scribe** | Timestamped log of every action, decision and query run | Whoever is not doing the other three; if nobody, the IL keeps the log |

> **Fill in before you need it.** Names, phone numbers and the out-of-band channel — something that
> does not depend on this app or on the compromised account's mailbox — belong in the table below.
> It is deliberately empty rather than seeded with plausible-looking fake contacts.
>
> | Function | Name | Phone | Out-of-band channel |
> |---|---|---|---|
> | Incident Lead | | | |
> | Supabase account owner (only they can rotate keys / change auth settings) | | | |
> | Vercel account owner | | | |
> | Legal / DPDP advice | | | |
> | Tenant escalation (per hostel owner) | | | |

**Single-operator reality.** If one person holds every role, the failure mode is skipping the scribe
log and the notification clock. Mitigate by starting a timestamped file *first*
(`incidents/YYYY-MM-DD-<slug>.md`) and setting a literal 6-hour and 72-hour alarm (§6) before
touching anything.

---

## 3. Detection sources

You are notified by one of these. Know their latency before the incident, not during it.

| Source | What it shows | Where | Latency |
|---|---|---|---|
| `public.audit_log` | Auth events + every privileged write, with actor, role, tenant, IP, user-agent | `/super-admin/security` → Audit trail, or the Supabase SQL editor | Real time |
| `public.security_alerts` | Suspicious-pattern alerts raised from audit activity | Supabase SQL editor | Near real time — **see [`logging-and-monitoring.md`](./logging-and-monitoring.md) §6 for current status** |
| Supabase **Auth logs** | Sign-in attempts, token refreshes, admin API calls, MFA events — including ones the app never sees | Supabase Dashboard → Logs | Minutes |
| Supabase **Postgres logs** | Errors, RLS denials, statement failures | Supabase Dashboard → Logs | Minutes |
| Vercel **runtime logs** | Exactly four `console.error` sites: failed sign-in (non-production only), generic server errors, rate-limiter unavailable, CSV export failure (`lib/actions/auth.ts`, `lib/permissions.ts`, `lib/rate-limit.ts`, `app/api/manager/export/route.ts`) | Vercel Dashboard → Logs | Seconds |
| Vercel **access logs** | Request volume, paths, status codes, source IP | Vercel Dashboard | Minutes |
| `GET /api/health` | Liveness + whether the app can reach Supabase auth. Deliberately reveals nothing else (`app/api/health/route.ts`) | Public URL | Real time |
| GitHub Actions **Security** workflow | Secret scan over the full history, dependency audit, client-bundle assert (`.github/workflows/security.yml`) | Actions tab | Per push + weekly (Mon 03:17 UTC) |
| A human | A tenant reports "I can see another hostel's data"; a resident reports an account they don't recognise; a researcher emails | — | Unbounded |

**Blind spots — do not plan around evidence that does not exist:**

- No read auditing (§0.1).
- `GET /api/manager/export` writes **no** audit row: a manager or owner can download a month of
  expense/revenue CSV with no trace (`app/api/manager/export/route.ts` contains no `audit()` call).
  The exported data is financial, not resident PII.
- Rate-limit trips are audited only for login (`auth.login.rate_limited`). Upload, write,
  password-change and MFA-verify limiter trips are silent.
- Middleware role bounces are not logged — by design, with the reasoning recorded on `denied()` in
  `lib/permissions.ts`: the Edge runtime is the wrong place for the service-role credential. An
  attempt to actually *execute* a privileged operation still lands in `audit_log` as `authz.denied`.

---

## 4. The first 30 minutes

Work top to bottom. Do not skip step 0 — evidence is destroyed by containment, not by attackers.

**T+0 — Open the log.** Create `incidents/YYYY-MM-DD-<slug>.md`. First line: UTC timestamp, who is
IL, what was reported and by whom, verbatim. Every subsequent action gets a timestamped line.

**T+2 — Assign severity (§1) and say it out loud.** Write it in the log. If scope is unknown, it is
SEV+1 until it isn't.

**T+5 — Preserve evidence before you change anything (§5).** Snapshot the relevant `audit_log` slice
into an incident table. Containment mutates `users`, `hostels` and session state; the audit trail of
what the attacker *did* is append-only and safe, but the current state you are about to change is
not.

**T+10 — Establish blast radius.** Answer these three, in the log:

1. **Which identities?**
   `select distinct actor_user_id, actor_role, hostel_id from public.audit_log where at > now() - interval '48 hours' and ip = '<suspect ip>';`
2. **Which tenants?** The `hostel_id` values in that result. `null` means a platform-level or
   pre-profile event.
3. **Which data classes could that identity read?** Look it up in
   [`access-control.md`](./access-control.md) §2. Do not infer it from the UI — the UI is not the
   boundary, RLS is.

**T+15 — Contain (§4.1–§4.8).** Smallest effective action first. Freezing one account is almost
always right before suspending a tenant, which is almost always right before rotating platform keys.

**T+25 — Confirm containment held.** Re-run the exact query that showed the malicious activity and
confirm it stops. For an authorization defect, run the suites — they are the fastest confirmation
available and they run against production:

```bash
node scripts/_qa-rls-attack.mjs        # 80 direct-PostgREST attacks
node scripts/_qa-tenant-integrity.mjs  # 32 cross-tenant FK / least-privilege / input cases
node scripts/_qa-prod-authz.mjs        # 145 role x route checks on the deployed site
```

**T+30 — Start the notification clock (§6).** If personal data was or may have been accessed, the
CERT-In 6-hour window and the DPDP intimation duty are already running — from the moment you
*noticed*, not from the moment you finish investigating.

---

### 4.1 Containment — freeze one account

The verified, single lever. It does two things (`setAccountStatus()` in `lib/auth/accounts.ts`):
sets `public.users.status = 'inactive'`, and bans the auth user (`ban_duration: "876000h"`).

*From the app:* Owner → Staff → Deactivate (manager/warden only). There is no in-app control for
deactivating an **owner** or a **student**; use the SQL + Auth admin path below.

*From SQL* (Supabase SQL editor, which runs privileged):

```sql
update public.users set status = 'inactive' where id = '<user-uuid>';
```

**Why this bites immediately, even on an already-issued access token:** `app.user_role()` and
`app.user_hostel_id()` (`db/schema.sql`) select `from public.users where id = auth.uid() and
status = 'active' and deleted_at is null`. For an inactive account both return `NULL`, so every RLS
policy that depends on them fails closed on the very next PostgREST request. The `users_select`
self-branch also requires `status = 'active'`, so the attacker cannot even read their own profile
row. Middleware signs them out on their next page request (`lib/supabase/middleware.ts`).

**What SQL alone does not do:** it does not ban the auth user, so the refresh token can still mint
new access tokens. Those tokens resolve to a `NULL` role, so they buy nothing at the database — but
close it properly anyway: Supabase Dashboard → Authentication → Users → the user → ban; or the API
call the app itself makes, `auth.admin.updateUserById(id, { ban_duration: "876000h" })`.

**Reversing it:** set `status = 'active'` and `ban_duration: "none"`. Note that the role-limit
trigger fires on reactivation and refuses if the 1-manager / 1-warden slot has been refilled
(`CLAUDE_2.md` §4.3).

### 4.2 Containment — revoke sessions

| Need | How | Reality |
|---|---|---|
| The user revokes their own other sessions | Automatic on a voluntary password change — `signOut({ scope: "others" })`, `lib/actions/auth.ts` | Verified in code |
| Sign one user out everywhere | `signOut({ scope: "global" })` runs only for the *current* session (`lib/actions/session.ts`). There is **no admin "sign out this user" control** | Use §4.1 instead — deactivation is the admin lever |
| Kill every session on the platform | Rotate the project's JWT signing secret in the Supabase dashboard. Every issued access token becomes invalid and everyone re-authenticates | **Dry-run this in the dashboard before you need it** — confirm where the control lives for your project's key configuration. It also invalidates outstanding Storage signed URLs (§4.8) |

Access tokens live ~1 hour (`THREAT-MODEL.md` §6B). A stolen token stays valid for its remaining
lifetime against anything that does not re-check `users.status` — which, at the database layer in
this app, is nothing, because the RLS helpers fail closed (§4.1).

### 4.3 Containment — force a password reset

There is **no self-service password reset and no email provider** (`THREAT-MODEL.md` §8: no SMTP).
Every reset is administrator-driven and the new password is displayed once.

| Target | Path | Effect |
|---|---|---|
| Owner | Super Admin → Hostels → Regenerate owner password (`regenerateOwnerPassword`, `lib/actions/super-admin.ts`) | New password + `must_change_password = true` in both `app_metadata` and `public.users` |
| Manager / Warden | Owner → Staff → Reset password (`resetStaffPassword`, `lib/actions/owner.ts`) | Same |
| Student | **No path exists** — `regeneratePassword()` is not wired to any student action | Reset from the Supabase dashboard, or vacate and re-register the student (which issues fresh credentials). Record which you chose |
| Super Admin | No in-app path | Supabase Dashboard → Authentication → Users |

`regeneratePassword()` (`lib/auth/accounts.ts`) sets `must_change_password = true`, so the
middleware **and** `requireUser()` / `assertRole()` force a change on the next request, on every
surface. That gate is enforced in two independent places on purpose (`SECURITY.md` §3.2).

**Deliver the new password out of band.** It is shown once, in the browser, to the administrator. Do
not paste it into a channel the compromised account can read.

### 4.4 Containment — put a hostel read-only / suspend a tenant

```sql
update public.hostels set status = 'suspended' where id = '<hostel-uuid>';
```

or, from the app: Super Admin → Hostels → Suspend (`setHostelStatus`, `lib/actions/super-admin.ts`).

`app.hostel_writable()` requires `status = 'active'`, so **every** tenant write fails — through the
app, through Server Actions, and through direct PostgREST — because the RLS `WITH CHECK` clauses and
the RPC guards all call it. Reads are unaffected (§0.3).

The `hostel_status` enum also has `'readonly'` (`db/schema.sql`), which blocks writes identically but
reads as a softer state to the tenant. It is **not reachable from the UI** — the validator accepts
only `active | suspended` (`lib/validators/super-admin.ts`) — so set it by SQL if you want that
wording:

```sql
update public.hostels set status = 'readonly' where id = '<hostel-uuid>';
```

Reactivating through the app also re-runs `refresh_subscription_statuses()`, which flips the hostel
straight back to read-only if the subscription is still expired. That is correct behaviour, not a
failed unsuspend.

### 4.5 Containment — rotate the service-role key

**Read §0.2 first. Done in the wrong order this is a self-inflicted total outage: login fails closed
when the rate limiter cannot reach the database.**

1. Supabase Dashboard → Project Settings → API → rotate the `service_role` key. **Copy it once.**
2. Vercel → the `hostelpro` project → Settings → Environment Variables → update
   `SUPABASE_SERVICE_ROLE_KEY` for Production.
3. **Redeploy immediately.** Environment-variable changes do not reach running functions until a new
   deployment. Between steps 1 and 3, sign-in, account creation, uploads, rate limiting and audit
   writes are all broken.
4. Update your local `.env.local`. Do not print, echo or commit it.
5. Verify: `curl -s https://hostelpro-three.vercel.app/api/health` → `{"ok":true,"supabase":true,…}`,
   then sign in as one account of each role, then `node scripts/_qa-prod-authz.mjs`.
6. Confirm no copy of the old key survives: `node scripts/security-scan.mjs` (working tree **and**
   full git history).

Rotate the key whenever: it appears in any log, screenshot, chat, ticket, CI output or third-party
service; a workstation that held `.env.local` is compromised; or anyone who had it leaves.
`SECURITY.md` §5 already carries this as an Info item — the key has been used from a developer
workstation throughout the build and **must** be rotated before real tenant data exists.

### 4.6 Containment — the anon key

`NEXT_PUBLIC_SUPABASE_ANON_KEY` is **public by design** and is safe only because RLS holds
(`THREAT-MODEL.md` §5). Its appearance in a log or in page source is *not* an incident. Rotating it
breaks every browser session, requires a Vercel redeploy, and does not contain an attacker who
already holds a valid session. It is almost never the right containment step — if RLS is the thing
that failed, fix the policy or suspend the tenant instead.

### 4.7 Containment — take the application offline

Ranked least to most destructive:

1. **Suspend the affected tenants** (§4.4) — writes stop, reads continue, other tenants unaffected.
2. **Deactivate the affected accounts** (§4.1) — those identities lose everything.
3. **Vercel deployment protection / remove the production alias** — the app becomes unreachable. The
   database is still reachable via PostgREST with the public anon key, so this alone does **not**
   contain a data-access incident.
4. **Pause the Supabase project** (Dashboard → Settings) — total outage, database included. This is
   the only step that closes boundary **B3** in `THREAT-MODEL.md` (browser → PostgREST direct).
   Reserve it for a confirmed, unpatched cross-tenant read.

If the incident involved destroyed or altered data rather than only disclosure, recovery is a
separate procedure — see [`backup-and-dr.md`](./backup-and-dr.md). Note the interaction with erasure:
a restore resurrects rows that were deleted for a data-subject request
([`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.5), so re-run any erasure that
post-dates the restore point.

### 4.8 Containment — storage objects

All three buckets (`student-docs`, `receipts`, `complaint-photos`) are private; access is via
short-lived signed URLs — 15 minutes for `student-docs`, 30 for the others (`SIGNED_URL_TTL`,
`lib/storage.ts`). Signed URLs **cannot be individually revoked**. Options: wait out the TTL (bounded
and short — that is why the TTLs are short); delete or move the object (`removeFromBucket()` in
`lib/storage.ts`, or the dashboard); or rotate the JWT signing secret, which invalidates outstanding
signatures along with every session (§4.2 — dry-run first).

Object keys are `<hostelId>/<folder>/<uuid>.<ext>` and `isPathInHostel()` refuses anything else, so
the tenant prefix in a leaked key tells you which hostel is affected.

---

## 5. Evidence preservation

**Capture before you contain.** Containment changes `users`, `hostels` and session state.

`public.audit_log` is append-only from the application's side: there is no INSERT/UPDATE/DELETE
policy for any user role, and `audit_event()` is executable only by the service role
(`db/schema.sql`). An attacker holding an application account — even a super-admin one — cannot edit
or delete the trail through PostgREST. An attacker holding the **service-role key** can.

Snapshot into a table, not into a chat message:

```sql
create table if not exists app.incident_2026_08_20 as
select * from public.audit_log where at >= now() - interval '30 days';
```

Queries that answer the usual first questions. All three hit an index — `audit_log_actor_idx`,
`audit_log_action_idx`, `audit_log_hostel_idx`:

```sql
-- Everything one identity did
select at, action, target_type, target_id, hostel_id, ip, user_agent, meta
from public.audit_log
where actor_user_id = '<uuid>' and at > now() - interval '30 days'
order by at;

-- Everything from one IP, across identities (this is what finds the second compromised account)
select at, actor_user_id, actor_role, action, hostel_id, user_agent
from public.audit_log
where ip = '<ip>' and at > now() - interval '30 days'
order by at;

-- Authorization probing: a normal user does not hit role gates
select actor_user_id, actor_role, count(*), min(at), max(at),
       jsonb_agg(distinct meta -> 'requiredRoles')
from public.audit_log
where action = 'authz.denied' and at > now() - interval '7 days'
group by 1, 2
order by 3 desc;

-- Credential attack on one identifier (target_id is a SHA-256 prefix, not the email/phone)
select target_id, count(*), min(at), max(at), count(distinct ip)
from public.audit_log
where action in ('auth.login.failed', 'auth.login.rate_limited')
  and at > now() - interval '24 hours'
group by 1
having count(*) >= 5
order by 2 desc;

-- Privileged account changes in the window
select at, actor_user_id, actor_role, action, target_id, hostel_id, meta
from public.audit_log
where action in ('owner.staff.create', 'owner.staff.password_reset', 'owner.staff.status',
                 'sa.owner.password_reset', 'sa.hostel.status', 'auth.mfa.unenrolled')
  and at > now() - interval '30 days'
order by at desc;
```

**Also capture, because they age out and are outside your control:** the relevant Supabase Auth and
Postgres log windows, and the Vercel runtime and access log windows, exported to files. Vendor log
retention depends on your plan tier — check it **now** and write the number into this document,
because it is the real limit on how far back any investigation can reach.

**Correlating `audit_log` to a person.** `target_id` on failed logins is
`sha256(lower(trim(identifier)))` truncated to 24 hex characters (`hashIdentifier()`,
`lib/audit.ts`) — deliberately not reversible. To test whether a *specific known* account was the
target, hash that identifier the same way and compare. Do not try to reverse the hash.

**Chain of custody.** Note who ran each query, when, and where the output went. If law enforcement
or a regulator becomes involved, an unlabelled CSV on a laptop is not evidence.

---

## 6. Notification obligations

> **Not legal advice.** The author of this document is not a lawyer. The statutory positions below
> reflect the best understanding of the law as of this document's review date and **must be checked
> against the current text of the Act and Rules, and with counsel, at the time of an incident.** The
> deadlines are short enough that you will not have time to research them then — which is the entire
> reason this section exists now.

### 6.1 Who owes the duty

The DPDP Act 2023 puts breach-intimation duties on the **Data Fiduciary** — the entity that
determines the purpose and means of processing.

- For **resident (student) data**, the hostel/PG operator is the Data Fiduciary; HostelPro is a
  **Data Processor** acting on their instructions. HostelPro's duty is to notify the affected
  tenant(s) **immediately**, so that *they* can meet their statutory clock, and to support their
  notification. This belongs in the tenant contract — see
  [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §2.
- For **owner and platform-staff accounts** that HostelPro itself creates and controls, HostelPro is
  the Data Fiduciary and owes the duty directly.

Determine which case you are in **within the first 30 minutes** and write it in the incident log. It
decides who sends what.

### 6.2 The clocks

| Obligation | Clock starts | Deadline |
|---|---|---|
| **CERT-In** (Directions under s.70B(6) of the IT Act, 28 April 2022) — reportable types include unauthorised access to data/databases and data breach/leak | When you **notice** the incident | **6 hours** |
| **DPDP Act 2023 §8(6)** — intimate the Data Protection Board of India **and each affected Data Principal** | On becoming aware | Initial intimation **without delay**; the detailed report to the Board within the period prescribed by the DPDP Rules — treat **72 hours** as the working assumption and confirm against the current Rule text |
| **Affected tenants** (contractual) | On becoming aware | Immediately — they have their own regulatory clock |

The 6-hour CERT-In window is the binding constraint in practice. It runs from *noticing*, not from
*understanding*. **Report on partial information and update later.** Waiting for a complete picture
is how the deadline is missed.

### 6.3 What a Data Principal notice must contain

Write it for a resident or their guardian, not for a regulator, and in a language they read:

- what happened, in plain words, and when;
- **which of their data** was or may have been involved — be concrete: name, phone, guardian's
  phone, permanent address, photo, ID-proof scan, fee records;
- the likely consequences — for ID-proof scans, say plainly that identity fraud is the risk;
- what you have done about it;
- **what they should do** — specific actions, e.g. "your HostelPro password has been reset, collect
  the new one from the warden", "be sceptical of anyone phoning and claiming to be from the hostel";
- a named contact who can answer questions.

Do not minimise, do not speculate about who did it, and do not promise what you have not verified.

### 6.4 Log retention interacts with this

The CERT-In directions also require covered entities to enable ICT system logs and maintain them for
a rolling **180 days**, within Indian jurisdiction. HostelPro's logs live in Supabase and Vercel.
**Whether the project's region satisfies "within Indian jurisdiction", and whether the directions
bind an entity of this size, are open legal questions** — flagged in
[`logging-and-monitoring.md`](./logging-and-monitoring.md) §4 and
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §7, each with the exact way to
check the region. Resolve them before onboarding real tenants, not during an incident.

---

## 7. Worked example — a warden's account is compromised

Scenario: at 09:12 IST an owner reports that fee records for residents of their hostel were changed
overnight, and their warden says it wasn't them.

**T+0 (09:12) — open the log, page the IL.** Record the report verbatim, including who said it.

**T+3 (09:15) — classify.** A warden can read every resident's full PII, guardian contact, permanent
address, ID-proof scan, fee ledger, leave and visitor history for one hostel
([`access-control.md`](./access-control.md) §2). One tenant, personal data, integrity affected →
**SEV2**. ID-proof scans are in scope — a warden can sign `student-docs` URLs — so hold SEV2 but note
the escalation trigger if a second hostel appears.

**T+5 (09:17) — evidence first.** Before touching the account:

```sql
create table app.incident_warden_20260820 as
  select * from public.audit_log where at >= now() - interval '30 days';

select at, action, target_type, target_id, ip, user_agent, meta
from public.audit_log
where actor_user_id = '<warden-uuid>' and at > now() - interval '7 days'
order by at;
```

You are looking for: `auth.login.success` rows with an IP or user-agent the warden does not
recognise; `warden.payment.record` / `warden.student.*` / `warden.leave.decide` at implausible hours;
and `auth.password.changed` or `auth.mfa.unenrolled` — an attacker locking the real user out.

**T+8 (09:20) — establish the entry point.**

```sql
-- Did they brute-force, or arrive with the password already?
select at, action, target_id, ip, meta
from public.audit_log
where action in ('auth.login.failed', 'auth.login.rate_limited')
  and at > now() - interval '7 days'
order by at;

-- What else came from that IP? (finds a second compromised account fast)
select at, actor_user_id, actor_role, action, hostel_id
from public.audit_log
where ip = '<suspect ip>' and at > now() - interval '30 days'
order by at;
```

No failed attempts before the first suspect success means the password was already known — phishing,
reuse, or the once-shown temporary password being passed around. That changes the remediation
(T+60), and it changes whether other accounts are exposed.

**T+12 (09:24) — freeze the account.** Owner → Staff → Deactivate. Verify in SQL:

```sql
select id, role, status, must_change_password from public.users where id = '<warden-uuid>';
```

`status = 'inactive'` means `app.user_role()` now returns NULL for that session and every RLS policy
fails closed on the attacker's next request — including a request made with a still-valid access
token (§4.1). Confirm the ban is set at the auth layer too.

**T+15 (09:27) — decide whether to suspend the hostel.** Ask: is the attacker's access now closed, or
could they still be inside via another identity? If T+8 found only the one account, **do not
suspend** — the frozen account is contained, and suspending stops the hostel's legitimate work for no
security gain. If a second account or an unexplained IP appeared, suspend (§4.4) and reassess.

**T+20 (09:32) — establish the damage to integrity.** Every warden write is audited, so this is
answerable exactly:

```sql
select at, action, target_type, target_id, meta
from public.audit_log
where actor_user_id = '<warden-uuid>'
  and action like 'warden.%'
  and at between '<first suspect login>' and '<freeze time>'
order by at;
```

Reconcile each `warden.payment.record` against the physical receipt book and the resident. `meta`
carries `period`, `amount` and `mode` (`lib/actions/warden.ts`), which is enough to identify a forged
payment without guessing. Correct the ledger **through the app** after reactivation, so the
correction is itself audited — never by direct SQL, which leaves no trail and bypasses the
`assert_student_in_hostel()` guards.

**T+25 (09:37) — accept the confidentiality finding you cannot measure.** Reads are not audited
(§0.1). You cannot determine what was viewed. **Assume the entire hostel's resident dataset was
read**, and notify on that basis. Recording "no evidence of exfiltration" here would be
misrepresenting the absence of a capability as the absence of an event.

**T+30 (09:42) — start the notification clocks.** Personal data of identifiable residents was
accessible to an unauthorised party, so the CERT-In 6-hour clock runs from 09:12 (deadline 15:12
IST). Notify the hostel owner — the Data Fiduciary for resident data — **now**, in writing, with the
scope from T+25. Draft the resident notice per §6.3.

**T+45 — rebuild the identity, don't reuse it.** Deactivate the compromised warden account
permanently, then create a **new** warden account (`createStaff`), which issues fresh credentials
shown once. Reactivating the old one is possible, but it leaves you reasoning about an identity an
attacker has held. Note the 1-active-warden rule (`CLAUDE_2.md` §4.3): the old account must be
deactivated before the new one can be created — the trigger enforces it, and the app returns a clear
message if you get the order wrong.

**T+60 — close the door the attacker used.**

- Add the affected role class to `MFA_REQUIRED_ROLES` in Vercel and redeploy. Middleware and
  `lib/actions/mfa.ts` then force TOTP enrolment before the account can do anything
  (`lib/supabase/middleware.ts`). Note the accepted residual, MFA-01 in `SECURITY.md` §5: TOTP codes
  are replayable inside their 30-second window (upstream GoTrue behaviour). MFA here is defence in
  depth, not a sole control.
- If credential sharing was the entry point, reset every staff password in that hostel (§4.3) and fix
  the handover practice. Passwords are shown once, in the browser, and are meant to be read to the
  person — not forwarded.
- Check whether any other account logged in from the same IP or user-agent (T+8) and repeat for each.

**T+90 — verify, then reopen.** Reactivate the hostel if it was suspended. Then:

```bash
node scripts/_qa-prod-authz.mjs        # the new warden reaches warden routes, and nothing else
node scripts/_qa-rls-attack.mjs
node scripts/_qa-tenant-integrity.mjs
```

Confirm the old identity is dead: sign in with the old credentials and expect
`"This account has been deactivated. Contact your hostel owner."`

**Within 5 business days — post-incident review (§8).**

---

## 8. Post-incident review

Hold it within **5 business days**, while people still remember. Blameless: the question is what made
the failure possible and easy, not who typed it.

Cover, in this order:

1. **Timeline** — from the earliest attacker action visible in `audit_log` to closure. Include when
   you *could* have detected it versus when you *did*.
2. **Root cause, and the cause behind it.** "Password was shared over WhatsApp" is a symptom; the
   cause is that credential handover has no defined process.
3. **Detection** — which source caught it? If a human did, what would have caught it automatically?
   Every SEV1/SEV2 should produce an alert entry in
   [`logging-and-monitoring.md`](./logging-and-monitoring.md) §6.
4. **What the audit trail could not tell you**, and whether that gap is worth closing. Read auditing
   for resident PII is the standing candidate.
5. **Actions** — each with a named owner and a date. An action without both is a wish.

**The rule that makes this worth doing:** every incident must produce either a **test** or a
**control**, and preferably a test. The precedent is set in this repo — round 2 of the audit found
two Criticals that the round-1 suite structurally could not express, and the response was
`scripts/_qa-tenant-integrity.mjs`, a suite that can (`SECURITY.md` §2). Canary-verify any new test
the same way the existing ones were: plant the flaw, confirm the test catches it, remove the flaw. A
test that has never failed has not been shown to work.

Then update the affected documents in the same change: this file, `SECURITY.md` §5,
`THREAT-MODEL.md` §6, and the alert catalogue. An incident that changes nothing written down will
happen again.
