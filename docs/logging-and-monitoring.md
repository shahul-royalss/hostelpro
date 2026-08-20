# Logging and monitoring — HostelPro

What is recorded, what is deliberately not recorded, how long any of it survives, who looks at it,
and what fires an alert.

Companion documents: [`incident-response.md`](./incident-response.md) (what to do when one fires),
[`access-control.md`](./access-control.md) (who is allowed to do the things being logged),
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) (the logs themselves contain
personal data), [`../SECURITY.md`](../SECURITY.md), [`../THREAT-MODEL.md`](../THREAT-MODEL.md) §7.

---

## 1. Log sources

| Source | Contains | Read it at | Controlled by | Retention |
|---|---|---|---|---|
| `public.audit_log` | Authentication events and every privileged **write**, with actor, actor role, target, tenant, IP, user-agent, and a small `meta` object | Supabase SQL editor — **no UI exists** (`SECURITY.md` §5) | Us | §4 |
| `public.security_alerts` | Suspicious-pattern alerts derived from audit activity | Supabase SQL editor | Us | §4 |
| `app.rate_limits` | Live fixed-window counters, keyed by SHA-256 hash. Not a log — a control whose state is briefly observable | Supabase SQL editor | Us | Rows self-expire; stale windows GC'd opportunistically (`db/schema.sql`, `rate_limit()`) |
| Supabase **Auth** logs | Every sign-in attempt, token refresh, MFA event, and Admin API call — including ones the app never sees, e.g. dashboard actions | Supabase Dashboard → Logs | Supabase | Plan-dependent — **look this up and record it here** |
| Supabase **Postgres** logs | Statement errors, RLS denials, constraint violations | Supabase Dashboard → Logs | Supabase | Plan-dependent |
| Vercel **runtime** logs | `console.error` output from the four call sites in §3.4 | Vercel Dashboard → Logs | Vercel | Plan-dependent |
| Vercel **access** logs | Request path, status, source IP, user-agent | Vercel Dashboard | Vercel | Plan-dependent |
| GitHub Actions | Type-check, SAST, full-history secret scan, dependency audit, client-bundle assert (`.github/workflows/security.yml`) | Actions tab | Us | GitHub default |

> **Action:** the four "plan-dependent" values are the real limit on how far back any investigation
> can reach ([`incident-response.md`](./incident-response.md) §5). Check them in the dashboards and
> write the numbers into this table. Do not leave this as a to-do once real tenants exist.

---

## 2. `public.audit_log` — the one we control

Schema (`db/schema.sql`):

| Column | Notes |
|---|---|
| `id` | `bigserial` |
| `at` | `timestamptz`, defaults `now()` |
| `actor_user_id` | `uuid`, **no foreign key** — deliberate: the trail survives account deletion, including erasure under DPDP |
| `actor_role` | `public.user_role` snapshot at the time of the action, so a later role change does not rewrite history |
| `action` | One of the values in §2.1, truncated to 80 chars |
| `target_type` / `target_id` | What was acted on. `target_id` is a UUID, or a **hashed identifier** for pre-authentication events (§3.2) |
| `hostel_id` | The tenant. Defaults to the actor's own hostel when the caller does not pass one — this fix is why an owner can see their staff's login activity at all (`SECURITY.md` §3.7 item 22) |
| `ip`, `user_agent` | Forensics. **This is personal data** — see §4 and `data-retention-and-privacy.md` §5 |
| `meta` | `jsonb`, scrubbed twice (§3.1). Small scalars only in practice |

Indexes: `(hostel_id, at desc)`, `(actor_user_id, at desc)`, `(action, at desc)`. Any monitoring
query should filter on one of those leading columns.

**Integrity.** There is no INSERT / UPDATE / DELETE policy on `audit_log` for any user role, and
`audit_event()` is `revoke`d from `public`, `anon` and `authenticated` and granted only to
`service_role` (`db/schema.sql`). An application account — even a super-admin one — cannot forge,
edit or delete a row through PostgREST. This was not always true: `audit_event` was once executable
by any authenticated user, which allowed forging rows into another tenant's owner-visible trail
(`SECURITY.md` §3.3 item 2).

**Visibility.** `audit_log_select` grants read to the super admin (everything) and to an owner for
their own hostel. Managers, wardens and students cannot read the audit log at all.

**Availability.** Auditing never blocks the primary action: `audit()` and `auditSystem()` swallow
errors in TypeScript (`lib/audit.ts`), and `audit_event()` has an `exception when others then null`
handler in SQL. The trade-off is explicit and correct — a failing audit write must not fail a fee
payment — but it means **a silent audit outage is possible**. It is caught by the daily review in
§5 (a day with zero `auth.login.success` rows is not a quiet day).

### 2.1 Action catalogue

The complete list — 42 actions, from the `AuditAction` union in `lib/audit.ts`. Anything not on this
list is not recorded.

**Authentication (10)** — `auth.login.success`, `auth.login.failed`, `auth.login.rate_limited`,
`auth.logout`, `auth.password.changed`, `auth.password.reauth_failed`, `auth.mfa.enrolled`,
`auth.mfa.unenrolled`, `auth.mfa.verified`, `auth.mfa.failed`

**Authorization (1)** — `authz.denied`

**Super Admin (5)** — `sa.owner_hostel.create`, `sa.subscription.renew`, `sa.hostel.status`,
`sa.owner.password_reset`, `sa.hostel.structure`

**Owner (9)** — `owner.staff.create`, `owner.staff.password_reset`, `owner.staff.status`,
`owner.announcement.create`, `owner.announcement.delete`, `owner.hostel.rules`, `owner.task.create`,
`owner.task.update`, `owner.task.delete`

**Warden (8)** — `warden.student.register`, `warden.student.vacate`, `warden.student.reassign`,
`warden.payment.record`, `warden.room.update`, `warden.leave.decide`, `warden.visitor.log`,
`warden.visitor.checkout`

**Manager (8)** — `manager.expense.create/update/delete`, `manager.revenue.create/update/delete`,
`manager.task.status`, `manager.menu.save`

**Shared (1)** — `staff.complaint.status`

Sixteen of the role actions were added late, after an audit found that authentication was logged but
day-to-day privileged writes were not — so the trail could not answer *"who changed this"*
(`SECURITY.md` §3.7 item 21). If you add a privileged Server Action, adding an `audit()` call is part
of the change, not a follow-up.

### 2.2 `authz.denied` — the highest-signal action

Written by `denied()` in `lib/permissions.ts`, from both `requireRole()` (pages) and `assertRole()`
(Server Actions). `meta` carries `actorRole`, `requiredRoles` and `surface` (`"page"` or `"action"`).

It matters because **a legitimate user never generates one**. The UI only renders links a role can
use, so a denial means someone typed or posted a URL belonging to another role. A burst of them is
role probing.

Two properties to know before you interpret it:

- The logging happens **before** `redirect()`, deliberately — `redirect()` throws to unwind, so
  anything after it never runs. The comment in `lib/permissions.ts` records this.
- Middleware bounces are **not** logged. The reasoning is recorded on `denied()`: a middleware bounce
  runs in the Edge runtime, where reaching for the service-role client on every request would be both
  slow and the wrong place for that credential. A middleware bounce is navigation hygiene; an attempt
  to actually **execute** the privileged operation still lands here. This means the count
  under-reports curiosity and accurately reports intent — which is the more useful of the two.

---

## 3. What is deliberately not logged

### 3.1 Credentials and codes — scrubbed twice, verified

**Verified in TypeScript.** `lib/audit.ts`:

```ts
const SECRET_KEYS = /pass|secret|token|key|otp|code|authorization|cookie/i;
```

`sanitizeMeta()` drops any matching key before the RPC call and truncates string values to 200
characters.

**Verified again in SQL.** `public.audit_event()` in `db/schema.sql` re-applies the same list on the
server side, so no future caller can persist one:

```sql
if k ~* '(pass|secret|token|key|otp|code|authorization|cookie)' then
  v_meta := v_meta - k;
end if;
```

Doing it in both places is the point: the TypeScript scrubber protects today's callers; the SQL one
protects anything that ever calls `audit_event()` without going through `lib/audit.ts`.

**Two honest limitations of that design, so nobody over-trusts it:**

1. It matches on **key names, not values**. A password placed in a field called `note` is stored.
2. It walks **top-level keys only** — `Object.entries()` in TS, `jsonb_object_keys()` in SQL. A
   nested object such as `{ user: { password: "…" } }` would survive both. Verified that **no current
   caller passes a nested object**: all 30 `meta:` payloads across `lib/` are flat scalars or short
   string arrays. The gap is latent, not live — keep it that way by keeping `meta` flat.

### 3.2 Login identifiers — hashed, not stored

Emails and phone numbers used in failed sign-ins are stored as
`sha256(lower(trim(identifier)))` truncated to 24 hex characters (`hashIdentifier()`,
`lib/audit.ts`). Enough to correlate repeated attempts against one account; not enough to read the
account back out. `auth.login.failed` and `auth.login.rate_limited` therefore carry a hash in
`target_id`, never an address.

The same hashing protects the rate-limit table: `rateLimit()` hashes every key before it reaches
`app.rate_limits` (`lib/rate-limit.ts`), so IPs and identifiers are never stored in clear there
either.

### 3.3 Error internals

`errorMessage()` in `lib/permissions.ts` allow-lists what a user may see — our own `PermissionError`,
our friendly Postgres `raise` messages (SQLSTATE `P0001`), a fixed set of mapped constraint codes —
and sends everything else to a generic message. The raw error goes to the server console only, via
`logServerError()`, which logs `name: message` and never the request body. Returning raw exception
text to the user was a real finding (`SECURITY.md` §3.3 item 11).

### 3.4 Server console output — four call sites, all of them

Verified by grep over `lib/` and `app/`:

| File | What it prints |
|---|---|
| `lib/actions/auth.ts` | Sign-in failure status + message — **guarded by `NODE_ENV !== "production"`**, so it never runs in production |
| `lib/permissions.ts` | `logServerError()` — error name and message only |
| `lib/rate-limit.ts` | "rate limiter unavailable" + the error message |
| `app/api/manager/export/route.ts` | CSV export failure — error message only |

No request bodies, no form data, no headers, no tokens are printed anywhere.

### 3.5 What we do NOT have, and it is not an oversight

No third-party analytics, no error reporter, no session replay, no email or SMS provider
(`THREAT-MODEL.md` §1, §6D). Nothing ships user data off Supabase and Vercel. That is a deliberate
privacy posture, and it is also why the log sources in §1 are the complete list.

### 3.6 Personal data that IS in the logs

`audit_log` stores `ip`, `user_agent`, `actor_user_id` and `target_id`. Under DPDP that is personal
data about staff and residents, held for a security purpose. It is why §4 exists, and why the
retention job is a privacy control and not merely housekeeping.

---

## 4. Retention

| Data | Retention | Mechanism | Why |
|---|---|---|---|
| `audit_log` rows | **400 days** | Scheduled delete via `pg_cron` in the Supabase project | Long enough to investigate an incident discovered late and to cover an annual review cycle; short enough that the trail is not an indefinite archive of residents' movements. Deletion is by `at`, oldest first |
| `audit_log` `ip` / `user_agent` | **90 days**, then nulled in place while the row survives | Same scheduled job | This is the data-minimisation half. The forensic value of an IP decays within weeks; the value of "who changed this fee, and when" does not. Nulling the two identifying columns keeps the accountability record and drops the tracking record |
| `security_alerts` | Follows `audit_log` | Same job | An alert without the underlying events is not evidence |
| `app.rate_limits` | Hours | Opportunistic GC inside `rate_limit()` (`db/schema.sql`) deletes windows older than 1 day | Counters, not history |
| Supabase / Vercel platform logs | Vendor default for the plan | Vendor | Not ours to set — see the note in §1 |

**Status.** The scheduled job is delivered as part of the alerting change set, not by this document.
Verify it exists and is running before relying on it:

```sql
select jobid, schedule, command, active from cron.job;
select jobid, status, start_time, end_time from cron.job_run_details order by start_time desc limit 20;
```

If `cron.job` returns nothing, the retention policy is aspirational and `audit_log` is growing
without bound — which is the state `SECURITY.md` §5 records as an open Low
("No retention policy for `audit_log` IP/user-agent").

**Before you shorten these numbers, read §6.4 of [`incident-response.md`](./incident-response.md).**
The CERT-In directions require covered entities to maintain ICT system logs for a rolling **180
days** within Indian jurisdiction. 400/90 days satisfies the *duration* comfortably; the
*jurisdiction* half depends on where the Supabase project actually is. Check with:

```bash
# Supabase Dashboard → Project Settings → General → Region.
```

Record the answer in [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §7 and get
legal input on whether the directions bind an operation of this size. Do not shorten retention below
180 days until that is settled.

---

## 5. Review cadence

Reviewing logs only during an incident means nobody knows what normal looks like. Each row has one
owner and one query.

| Cadence | Who | What | Query / where |
|---|---|---|---|
| **Daily (5 min)** | Platform operator | New rows in `security_alerts`; any `authz.denied`; login-failure volume vs. yesterday. A day with **zero** `auth.login.success` rows means the audit path is broken, not that nobody logged in | §5.1 |
| **Weekly (20 min)** | Platform operator | Privileged-action review across all tenants: every `sa.*`, every `owner.staff.*`, every `auth.mfa.unenrolled`. Each one should map to something you know about | §5.2 |
| **Weekly (automatic)** | CI | GitHub Actions `Security` workflow — Mondays 03:17 UTC. Surfaces newly-disclosed CVEs with no commits (`.github/workflows/security.yml`) | Actions tab |
| **Monthly (30 min)** | Platform operator | Run the four QA suites against production; confirm the retention job ran; confirm platform log retention has not changed under you | `SECURITY.md` §6 |
| **Quarterly** | Platform operator + tenant owners | Access review — see [`access-control.md`](./access-control.md) §6 | — |
| **Per tenant, monthly** | Hostel owner | Their own hostel's trail: staff account changes, unexpected logins, fee-record edits. This is the audience `hostel_id` defaulting was fixed for (`SECURITY.md` §3.7 item 22) | §5.3 |
| **After every incident** | Incident Lead | Add an alert for whatever a human noticed first ([`incident-response.md`](./incident-response.md) §8) | §6 |

### 5.1 Daily

```sql
-- Anything the alerting raised
select * from public.security_alerts where created_at > now() - interval '1 day' order by created_at desc;

-- Authorization probing (a normal user never generates these)
select at, actor_user_id, actor_role, hostel_id, ip, meta
from public.audit_log
where action = 'authz.denied' and at > now() - interval '1 day'
order by at desc;

-- Auth volume, and proof the audit path is alive
select action, count(*)
from public.audit_log
where at > now() - interval '1 day' and action like 'auth.%'
group by 1 order by 2 desc;
```

### 5.2 Weekly

```sql
select at, actor_user_id, actor_role, action, target_id, hostel_id, meta
from public.audit_log
where at > now() - interval '7 days'
  and (action like 'sa.%' or action like 'owner.staff.%' or action = 'auth.mfa.unenrolled')
order by at;
```

### 5.3 Per-tenant, for an owner

An owner can run this only via SQL today — there is no UI (`SECURITY.md` §5, open Low). Until there
is, the platform operator runs it and sends the result:

```sql
select at, actor_role, action, target_type, target_id, ip
from public.audit_log
where hostel_id = '<hostel-uuid>' and at > now() - interval '30 days'
order by at desc;
```

---

## 6. Alert catalogue

Each alert names what fires it, why it is worth a human's attention, who responds, and what they do.
An alert nobody owns is noise, and noise trains people to ignore the next real one.

The sink is `public.security_alerts`; delivery today is **pull, not push** — the daily review (§5.1)
is what surfaces them. There is no email or SMS channel in this build (`THREAT-MODEL.md` §1), so an
alert is only as timely as the review cadence. **If you add a push channel, add it here.**

| # | Alert | Fires on | Why it matters | Owner | Response |
|---|---|---|---|---|---|
| A1 | **Credential attack on one identifier** | ≥5 `auth.login.failed` for the same `target_id` within 15 min | The per-identifier limiter caps at 8 per 15 min (`LIMITS.loginPerIdentifier`), so 5 means someone is close to the ceiling on one account | Platform operator | Identify the account by hashing the suspected identifier (§3.2). If any `auth.login.success` follows in the window, treat as SEV3 and freeze the account ([`incident-response.md`](./incident-response.md) §4.1) |
| A2 | **Distributed credential attack** | ≥20 `auth.login.failed` across ≥5 distinct `target_id` within 15 min | Credential stuffing against the tenant, rather than one account | Platform operator | Check for successes in the same window. Consider forcing MFA for staff roles (§`MFA_REQUIRED_ROLES`) |
| A3 | **Rate limiter engaged on login** | Any `auth.login.rate_limited` | The IP limiter (20/5 min) is generous; tripping it is abnormal for a hostel-sized user base | Platform operator | Correlate the IP against A1/A4. Note that per-IP keying is only as good as `getClientIp()` — platform headers first, otherwise the **last** XFF hop (`lib/rate-limit.ts`), so `TRUSTED_PROXY_HOPS` must match the real topology |
| A4 | **Role probing** | ≥3 `authz.denied` from one `actor_user_id` within 10 min | A legitimate user never hits a role gate (§2.2). This is the clearest signal of an account being explored rather than used | Platform operator | Pull that actor's full history. If `surface = "action"` in `meta`, they attempted to *execute*, not just navigate — escalate to SEV3 and freeze |
| A5 | **MFA turned off** | Any `auth.mfa.unenrolled` | A classic post-takeover step, and it silently weakens a role you may have chosen to require MFA for | Platform operator | Confirm with the account holder out of band. If not them: SEV2, freeze, reset, re-enrol |
| A6 | **Reauthentication failures** | ≥3 `auth.password.reauth_failed` for one user in 1 hour | A voluntary password change requires the current password (`SECURITY.md` §3.3 item 8). Repeated failures mean someone holds a session but not the password — i.e. a stolen token, not a stolen credential | Platform operator | SEV3. Freeze the account; the token dies with it (§4.1 of the IR doc) |
| A7 | **Privileged account change** | Any `owner.staff.create`, `owner.staff.password_reset`, `owner.staff.status`, `sa.owner.password_reset` | These mint or reset credentials. Every one should correspond to something a human knows about | Platform operator + affected hostel owner | Reconcile against the weekly review (§5.2). An unexplained one is SEV2 |
| A8 | **Tenant status changed** | Any `sa.hostel.status` or `sa.hostel.structure` | Only the super admin can do this; an unexpected occurrence means the SA account is compromised, which is SEV1 by definition | Platform operator | Verify with the SA holder out of band before anything else |
| A9 | **Off-hours super-admin activity** | Any `sa.*` outside declared working hours | Small blast radius by count, largest by consequence | Platform operator | Same as A8 |
| A10 | **Privileged login from an unfamiliar IP** | `auth.login.success` where `actor_role in ('super_admin','owner')` and the `(actor_user_id, ip)` pair is unseen in the previous 30 days | Cheap, high-yield takeover signal | Platform operator | Confirm with the account holder. Expect false positives from mobile networks — tune on `/24` or ASN if it gets noisy, and record the tuning here |
| A11 | **Audit path silent** | Zero `auth.login.success` rows in a 24-hour period during normal operation | `audit()` swallows its own failures by design (§2). This is the only way an audit outage becomes visible | Platform operator | Check Vercel runtime logs for `rate limiter unavailable`, and whether `SUPABASE_SERVICE_ROLE_KEY` is valid — the same credential backs both paths |

**Deliberately not alertable today, and you should know why:**

- **Bulk resident-data access.** Reads are not audited (§7). There is no signal to alert on. This is
  the single largest monitoring gap in the system.
- **CSV export.** `GET /api/manager/export` writes no audit row (`app/api/manager/export/route.ts`).
  The data is financial rather than resident PII, which is why it is a gap and not a hole.
- **Upload / write / MFA-verify limiter trips.** Only login limiter trips are audited.

---

## 7. Known gaps

Listed so they are decisions, not surprises.

1. **No read auditing.** The largest gap. Closing it means auditing resident-PII reads — the
   `students` table and `student-docs` signed-URL minting are the two that matter — and accepting the
   write volume that generates. Until then, a compromised staff account's confidentiality impact is
   **unmeasurable**, and [`incident-response.md`](./incident-response.md) §7 tells you to assume the
   worst rather than report a false negative.
2. **No log UI.** Everything here is SQL-editor work, which means owners cannot self-serve their own
   tenant's trail (`SECURITY.md` §5).
3. **No push delivery.** Alerts are pulled by the daily review; time-to-detect is bounded by cadence,
   not by seconds.
4. **Platform log retention is unknown and unrecorded.** See the note in §1.
5. **Storage access is not logged by us.** Signed-URL *minting* happens server-side and is not
   audited; the subsequent object fetch goes straight to Supabase Storage. TTLs are short — 15 min
   for `student-docs`, 30 for the others (`lib/storage.ts`) — which bounds the exposure but produces
   no record.
6. **`meta` scrubbing is key-name-based and shallow** (§3.1). Keep `meta` flat and never put free
   text in it.
