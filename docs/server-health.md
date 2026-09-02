# Server health — NIVORA

Whether the Supabase backend is actually unhealthy, how to tell, and which symptoms are the
**client** wearing a server costume.

This document exists because the backend has now twice been declared "down" when it was serving
every request it was given. Both times the evidence for "down" was a red badge and an error
message in the app. Neither is evidence. §7 is the runbook that replaces both.

Companion documents: [`logging-and-monitoring.md`](./logging-and-monitoring.md) (what is logged
and for how long), [`incident-response.md`](./incident-response.md) (what to do when something is
genuinely broken), [`backup-and-dr.md`](./backup-and-dr.md).

Project `nimxvgzscbanhtvgnjll`, region `ap-southeast-1`, Postgres 17.6, Free plan.

---

## 1. The short answer

**The backend is not unhealthy, and was not unhealthy during the window that prompted this
investigation.** Measured directly, at the times given in §2:

| Leg | Result |
|---|---|
| `POST /auth/v1/token` (password grant) | 400 `invalid_credentials` in 0.35 / 0.46 / 0.82 s |
| `GET /rest/v1/users` (PostgREST, service role) | 200 in 0.27 / 0.28 / 0.31 / 0.35 / 0.84 s |
| `POST /rest/v1/rpc/rpc_sa_dashboard` | 200 in 0.24 / 0.26 / 0.28 / 0.32 s |
| `POST /rest/v1/rpc/refresh_subscription_statuses` | 204 in 0.25 s |
| Platform status (Management API) | `ACTIVE_HEALTHY` |
| Connections | **12 of 60**, 1 active, 0 idle-in-transaction |
| Database size | Largest table `beds` = 45 rows; whole schema well under 1 MB |

The first call in any burst is ~0.6–0.85 s and every subsequent one is ~0.25–0.35 s. That is TLS
handshake plus connection setup, not the database. There is no latency problem here.

**But there was a real outage, and there is a real bug.** Both are in §3 and §4. Neither is
"the server is slow" and neither is fixed by upgrading the plan.

---

## 2. What was measured, and how

All figures in this document come from two places, both reproducible:

1. **Direct HTTP probes** against the live project, timing the full round trip with
   `curl -w '%{time_total}'`, reading the **response body** and not only the status code.
2. **The unified log stream**, queried over the **full 24-hour window**, not a 60-minute sample.

Both matter, for reasons that are the whole point of this document.

**Read the body, not the status.** A CAPTCHA rejection and a wrong password are *both*
`400 POST /auth/v1/token`. A probe that records only "400, as expected for bad credentials" cannot
tell a healthy auth server from one refusing every sign-in on the planet. §3 is exactly that
mistake, caught only because the body said `invalid_credentials` rather than
`captcha protection: request disallowed`.

**Use 24 hours, not 60 minutes.** This project is idle for most of the day and then does
everything at once. A 60-minute window sampled at 23:5x shows two stale-refresh-token 400s and one
OTP 429, and looks pristine. The same day contains a 4h17m total sign-in outage and 11,997 5xx
responses. Both fell outside the hour. The Free plan keeps exactly 24 hours of logs (§8), so 24
hours is simultaneously the correct window and the largest one available.

---

## 3. The real outage: CAPTCHA was switched on, and the app cannot answer a CAPTCHA

**Status: over. Verified off. Do not switch it back on.**

For **4 hours 17 minutes**, every password sign-in from every client failed:

```
400: captcha protection: request disallowed (no captcha_token found)
```

| | |
|---|---|
| First seen | 2026-08-31 **09:12:02** |
| Last seen | 2026-08-31 **13:29:08** |
| Occurrences | **64** on `/token`, plus 3 on `/otp` |
| Blast radius | Total. Not a subset of users — the token endpoint itself refused. |

The Edge Function said so in plain language, 28 times, and the line was in the logs the whole time:

```
[nivora] GoTrue refused the password grant for CAPTCHA — sign-in is down for every client.
```

**What happened.** CAPTCHA protection is an owner-facing toggle at **Authentication → Settings →
Bot and Abuse Protection → Enable CAPTCHA protection**. It guards the sign-up, **sign-in** and
password-reset endpoints. Once enabled, GoTrue requires a `captcha_token` on every one of those
calls. The Flutter client does not send one — there is no hCaptcha/Turnstile widget in the app, and
adding one to a native mobile sign-in screen is not a small change. So enabling that toggle takes
sign-in from "working" to "impossible" for 100% of users, instantly, with no gradual degradation.

**Current state, verified by live probe:** a password grant with a deliberately wrong password now
returns `{"code":400,"error_code":"invalid_credentials"}`. GoTrue is evaluating the password, which
means the CAPTCHA gate is off. Sign-in works.

**The rule.** Do not enable CAPTCHA protection until the Flutter client actually ships a CAPTCHA
token. It is not a hardening you can turn on and verify later — it is a full outage the moment it
is saved, and the only symptom is a `400` that looks exactly like a wrong password.

---

## 4. The real bug: the app DDoSes itself, then reports the server is down

This is the source of "the server is not responding". It is a **client** defect. The server was the
victim, not the cause.

One single query — the user-profile fetch —

```
GET /rest/v1/users?select=id,role,full_name,email,phone,hostel_id,status,
                          must_change_password,email_verified_at&id=eq.<uuid>
```

was issued **63,525 times in 24 hours** by `Dart/3.13 (dart:io)` — the Flutter app. For scale, the
app has **three** user accounts.

It arrives in bursts, and the peak is not a typo:

| Minute | Requests | 200 | 522 | 504 | 503 |
|---|---|---|---|---|---|
| 18:04 | 12,505 | 12,505 | — | — | — |
| 18:05 | 11,258 | 11,258 | — | — | — |
| **18:06** | **14,180** | 14,180 | — | — | — |
| 23:17 | 7,955 | 803 | 5,560 | 1,189 | 403 |
| 23:18 | 4,404 | 0 | 4,394 | 8 | 2 |

**14,180 requests in one minute is 236 requests per second from one phone.**

Read the two halves of that table together, because they are the entire argument:

- At 18:04–18:06 the backend absorbed **37,943 requests in three minutes and answered every single
  one with a 200.** That is the opposite of an unhealthy server.
- At 23:17–23:18 the same loop ran again and the edge finally shed load: 522 (Cloudflare could not
  reach the origin), then 504, then 503. By 23:18 the client was getting **zero** successful
  responses. That is when the app says "the server is not responding" — and it is telling the truth
  about what it received, while being the reason it received it.

**Every 5xx in 24 hours belongs to this loop.** Total 5xx: **11,997**. Inside the profile storm:
**11,989 (99.93%)**. Everywhere else: **8** — and seven of those eight are Supabase's own health
probes (`/auth/v1/health`, `/rest-admin/v1/ready`, `/admin/v1/network-bans`) timing out at
09:16:05, 18:08:27 and 23:23–23:24, i.e. during a container restart and inside the two storms.

**Which account loops worst is the clue.** Broken down by user:

| Account | Role | 200 | 5xx |
|---|---|---|---|
| `codewithshahul@gmail.com` | super_admin | 46,578 | 187 |
| `chudham20@gmail.com` | manager | 2,978 | **11,802** |
| `shahulroyals@gmail.com` | owner | 1,980 | — |

All three rows exist and are `active`, so this is not a missing-row retry. The account that
produces essentially every 5xx is the one sitting in the gate state: `must_change_password = TRUE`
and email not verified. The looping query selects `must_change_password` and `email_verified_at` —
precisely the two fields a router guard reads to decide whether to redirect. The shape of this is a
**redirect/refetch loop**: fetch profile → gate says "must change password" → navigate → the
destination refetches the profile → repeat, with no backoff and no de-duplication.

**Not fixed here.** `nivora_app/lib/**` is owned by other agents; this document does not touch it.
Handing it over: the fix is on the client, in whatever guard reads `must_change_password` /
`email_verified_at`. It needs (a) a single in-flight profile request rather than one per rebuild,
(b) a cached result, and (c) a redirect that cannot re-enter itself. Server-side rate limiting is
**not** the fix — it would convert an infinite loop into an infinite loop that gets 429s.

---

## 5. What was changed server-side

Two migrations, both small, both verified. Neither is a response to a latency problem, because
there is no latency problem.

**`db/migrations/2026-09-01-server-health-search-path.sql`** — pins `search_path` on
`app.mfa_required_roles()`, clearing the only SECURITY-category lint that was fixable in SQL
(`0011_function_search_path_mutable`). The function is `IMMUTABLE` and returns a constant array
whose type is already fully qualified, so the practical risk was nil; this is lint hygiene and
defence in depth. Verified after: returns `{super_admin,owner}`, `app.mfa_satisfied()` still
evaluates, lint gone.

**`db/migrations/2026-09-01-refresh-subscription-statuses-guard.sql`** — adds the internal
authorization check that [`../THREAT-MODEL.md`](../THREAT-MODEL.md) §4 already claimed every
`SECURITY DEFINER` RPC had. Found while working through advisor lint `0029`: of the 17 such RPCs
executable by `authenticated`, sixteen re-check authorization internally and
`public.refresh_subscription_statuses()` did not — no role check, no `raise` — while being granted
to `authenticated`, i.e. callable by any signed-in student.

Impact was **not** a privilege escalation and should not be written up as one: it returns `void`,
recomputes state purely from `end_date` (which the caller cannot influence, so it is idempotent),
and its only cross-tenant effect is a templated "subscription expiring" notice to an owner, already
capped at one per owner per hostel per 7 days. It was a least-privilege gap and a documentation
inaccuracy.

A guard rather than a `revoke`, because three call sites invoke it through the **user** client —
`app/super-admin/page.tsx`, `app/owner/page.tsx`, `lib/actions/super-admin.ts` — so revoking
`authenticated` would have broken all three. Two of them already swallow errors, and the third runs
only after `assertRole("super_admin")`, so no legitimate caller can reach the new `raise`.

The first version of that guard **failed open** and was caught in testing: `app.user_role()` returns
`NULL` when no active, non-deleted row matches, `false OR NULL` is `NULL`, and `if not NULL` never
fires — so an `anon` caller was **allowed**. It now wraps the predicate in `coalesce(..., false)`,
matching the fail-closed convention `app.mfa_satisfied()` uses for a missing `aal` claim. Verified:

| Caller | Result |
|---|---|
| `super_admin`, `owner`, `service_role` | ALLOWED |
| `manager` | REFUSED `42501` |
| `anon` (no `sub` claim) | REFUSED `42501` |
| authenticated, deleted/unknown user | REFUSED `42501` |

After both migrations: data unchanged (0 notifications created, subscription and hostel both still
`active`, all three accounts intact), REST 0.27–0.31 s, RPC 0.24–0.29 s.

---

## 6. Things that look broken and are not

### 6.1 The empty PostgREST log pane — expected, not a fault

The pane is not empty at source. `postgrest_logs` holds **273 rows** for the last 24 hours. Every
one of them is a lifecycle message:

```
Successfully connected to PostgreSQL 17.6 on x86_64-pc-linux-gnu
Connection Pool initialized with a maximum size of 10 connections
Schema cache loaded 21 Relations, 21 Relationships, 34 Functions, ...
Config reloaded
```

There is not a single HTTP request line, because **PostgREST does not log one**. It logs startup,
config reloads, and schema-cache reloads. Per-request records live in `edge_logs`, which holds
**64,774** rows for the same window — that is where "who called what and got which status" is
answered, and it is where every number in §4 came from.

The rows arrive in bursts (168, 28, 28, 7, 28, 14) separated by hours of nothing, clustered at
09:16, 10:02, 18:52, 19:17, 20:33–20:51 and 21:28 — because that is when a migration fired a
`pgrst` schema-cache reload or the container restarted. **A quiet PostgREST pane means nobody
changed the schema recently. It is the healthy state.**

### 6.2 The "Unhealthy" badge

The badge is not lying, but it is not reporting what it is being read as. It samples the same
infra probes listed in §4 — `/auth/v1/health`, `/rest-admin/v1/ready`,
`/admin/v1/network-bans/retrieve`. Those failed **eight times in 24 hours**, at exactly three
moments: 09:16:05 (a GoTrue container restart — the paired `DEPRECATION NOTICE` lines and a
PostgREST reconnect land in the same second, and a Dart token POST got a 502 at 09:16:42), and
18:08 and 23:23–23:24 (inside the two client storms in §4).

So the badge went red for ~40 seconds of genuine platform restart and for two windows in which the
origin was saturated **by our own client**. It is sticky and it lags. It is a summary of past
probe failures, not a live statement about whether the API is answering. `ACTIVE_HEALTHY` from the
Management API and a 250 ms round trip from an actual request both outrank it.

### 6.3 The `GOTRUE_JWT_DEFAULT_GROUP_NAME` / `_ADMIN_GROUP_NAME` deprecation notices

**Nobody can act on these. Do not file a task.** They are emitted by Supabase's own managed GoTrue
container at boot — note `"component":"api"` and the wording, "not supported by **Supabase's**
GoTrue". They refer to environment variables the **platform** sets, not ones this project supplies;
there is no dashboard control and no Management API field for them. They appear in pairs, once per
GoTrue start (09:16:13, 17:03:44, 21:24:23, 23:11:11, 23:11:53 — five restarts in 24 hours, which
is normal for shared Free-tier auth infrastructure). They are `warning` level, they are harmless,
and they will disappear when Supabase removes the variables. Their only real use is as a precise
marker of when the auth container last restarted.

### 6.4 The OTP `429` — correct behaviour, working as designed

```
429: For security purposes, you can only request this after 13 seconds.
```

**One** occurrence in 24 hours, at 23:01:01. That is a person tapping "resend code" twice. The
cooldown is not too aggressive; it is a standard resend interval doing its job, and it fired once.
Leave it alone.

More interesting on the same endpoint: **10 × `422: Signups not allowed for otp`** between 18:52
and 21:15 — a client asking for an OTP for an address with no account while sign-ups are disabled.
That is a client-side UX issue (it should say "no account with that email"), not a server fault.

### 6.5 The slowest queries on the database are the dashboard's own

The only statements over one second in 24 hours are three catalog introspections, all tagged
`-- source: dashboard`:

| Duration | Query |
|---|---|
| 13,716 ms | the `splinter` advisor lint (what powers Security/Performance Advisor) |
| 11,849 ms | `pg_available_extensions` listing |
| 11,536 ms | the `splinter` advisor lint again |

Not one application query appears. Opening the dashboard to check whether the database is slow is
itself the slowest thing that happens to the database. Expect the badge and the advisor pages to
feel sluggish on Free tier; it says nothing about the API.

### 6.6 `400: Current password required when setting new password.`

Three occurrences, 20:25–20:43. This is
`GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD`, which is **ON for this project by
design**. Every password update must send `current_password`. A client that omits it gets a 400.
Server correct; caller incomplete.

---

## 7. Runbook — the badge is red, or someone says "the server is down"

Work down this list. Stop at the first step that explains the symptom. **Do not start by changing
server settings**, and do not conclude anything from the badge alone.

1. **Ask what the client actually received.** A status code and a response **body**. "It didn't
   work" and "it says server not responding" are not data. A `400` with
   `invalid_credentials` and a `400` with `captcha protection` are the same colour and opposite
   problems.

2. **Probe the three legs yourself, and read the bodies.** Takes about fifteen seconds:

   ```bash
   set -a; . ./.env.local; set +a
   U="$NEXT_PUBLIC_SUPABASE_URL"; K="$NEXT_PUBLIC_SUPABASE_ANON_KEY"

   # auth — expect 400 invalid_credentials, NOT "captcha protection"
   curl -s -w '\n%{http_code} %{time_total}s\n' -X POST "$U/auth/v1/token?grant_type=password" \
     -H "apikey: $K" -H 'Content-Type: application/json' \
     -d '{"email":"probe@example.invalid","password":"wrong"}'

   # REST — expect 401 (RLS), reached in well under a second
   curl -s -o /dev/null -w '%{http_code} %{time_total}s\n' \
     "$U/rest/v1/hostels?select=id&limit=1" -H "apikey: $K"
   ```

   Two sub-second responses with sane bodies means the API is up, whatever the badge says. Ignore
   the first sample of a burst — that one pays for the TLS handshake.

3. **Count 5xx over 24 hours and find out whose they are.** This is the step that would have
   ended both previous investigations immediately:

   ```sql
   -- unified logs, 24h window
   select countIf(position(event_message,'| 5')>0) as fivexx, count(*) as total
   from logs where source='edge_logs';

   -- if fivexx is non-trivial, find the single caller responsible
   select substring(event_message,1,200) as msg, count(*) as n
   from logs where source='edge_logs' and position(event_message,'| 5')>0
   group by msg order by n desc limit 10;
   ```

   If one URL and one user-agent own the list, that is a client loop (§4), not a server fault.

4. **Check request volume against reality.** A three-user app should not make five-figure request
   counts. Requests per minute, worst first:

   ```sql
   select toStartOfMinute(timestamp) as m, count(*) as n
   from logs where source='edge_logs' group by m order by n desc limit 10;
   ```

   Anything above a few hundred per minute is a loop. Find it in the client before touching
   anything on the server.

5. **Only now look at the server.** Connections (`select count(*) from pg_stat_activity`, against
   `max_connections` = 60), advisors for security and performance, and `postgres_logs` for
   statements over a second — remembering §6.5, that the dashboard's own introspection dominates
   that list.

6. **Check whether an auth toggle changed.** If sign-in specifically is broken while REST is fine,
   suspect Authentication → Settings before suspecting the database. CAPTCHA (§3) is the one that
   has actually bitten, and its symptom is a `400` on `/token` for everyone at once.

---

## 8. What the Free plan genuinely cannot do

Kept deliberately separate from everything above, because **none of these caused any symptom in
this investigation** and none of them is fixed by spending money today.

- **No uptime SLA.** Shared infrastructure. The ~40-second GoTrue restart at 09:16 (§6.2) is
  normal and will happen again, unannounced, at some point during a demo.
- **Auto-pause after 7 days idle.** A paused project must be restored from the dashboard before it
  answers anything. Relevant if NIVORA sits unused between review cycles — the first request after
  a pause fails, and it looks exactly like an outage.
- **24 hours of log retention.** Confirmed against Supabase's retention table: Free gets "Last 24
  hours"; 7 / 14 / 28 days are Pro and above. **This is the real constraint.** Any incident not
  investigated the same day cannot be investigated at all — the 4h17m CAPTCHA outage in §3 would
  have been unrecoverable one day later. It also resolves the open "plan-dependent" item for the
  Supabase rows in [`logging-and-monitoring.md`](./logging-and-monitoring.md) §1.
- **No PITR.** Daily backups only; point-in-time recovery starts at Pro.

**What the Free plan is demonstrably not doing:** throttling this project or making it slow. 12 of
60 connections, sub-second responses, and 37,943 successful responses in three minutes under a
236 req/s hammering are not the numbers of a starved instance. If an upgrade is bought, buy it for
the SLA, the absence of auto-pause, and longer log retention — not for speed, and not because of
anything described in §3 or §4.

---

## 9. Open items

- **Client profile-fetch loop (§4)** — the one thing here that is actually broken and still
  broken. Owned by whoever owns `nivora_app/lib/**`. Until it is fixed, the app will keep
  generating its own 5xx and keep reporting them as a server outage.
- **CAPTCHA (§3)** — leave off. Revisit only together with a client that can produce a token.
- **Leaked-password protection is disabled** — advisor `auth_leaked_password_protection`. A
  dashboard toggle (Authentication → Settings) that checks new passwords against
  HaveIBeenPwned. Unlike CAPTCHA it does **not** break existing clients: it only rejects new or
  changed passwords that appear in a breach corpus. Worth enabling before launch, but as a
  deliberate change with a sign-in smoke test after, not on the eve of submission.
- **22 unindexed foreign keys** (advisor `unindexed_foreign_keys`, all INFO) — **deliberately not
  acted on.** The largest table in the database has 45 rows; Postgres will seq-scan a single page
  rather than use an index at this size, so all 22 would be pure write overhead and disk for zero
  measurable read benefit. The same advisor already reports five *existing* indexes as never used.
  Revisit when a table passes roughly 10,000 rows, or when a parent `DELETE` starts showing up in
  the slow-query log — not before.
- **4 tables with overlapping permissive policies** (`beds`, `floors`, `menus`, `subscriptions`) —
  each has a `*_select` policy and a `*_write` policy declared `FOR ALL`, so both are evaluated on
  every `SELECT`. The safe fix is to scope each `*_write` to `INSERT`/`UPDATE`/`DELETE`; this was
  verified to be semantics-preserving, because each `*_write` USING predicate is a strict subset of
  the matching `*_select` (e.g. `beds_write` admits `warden`, `beds_select` admits
  `manager, warden`). **Not applied**: Postgres has no `FOR INSERT, UPDATE, DELETE`, so it means
  replacing 4 policies with 12, and rewriting RLS days before a store submission to chase an
  unmeasurable win on a 45-row table is a bad trade. Do it deliberately, with tests, after launch.
- **[`../THREAT-MODEL.md`](../THREAT-MODEL.md) §4** states that every `SECURITY DEFINER` RPC
  "re-checks authorization internally". That is true as of §5 above, but it was not true when
  written. Left unedited here only because that file sits outside this document's ownership.
