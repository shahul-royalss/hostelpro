# Backup and disaster recovery

## Why this exists in this shape

The Supabase organisation is on the **free plan**. Point-in-time recovery and managed
scheduled backups are paid features — they are not disabled, they do not exist on this
plan and cannot be turned on. There is also no direct Postgres password provisioned for
CI, so `pg_dump` is not an option either.

What we do have is the service-role key, which reads every row through PostgREST
regardless of RLS. So the backup is a **logical, row-level dump over the REST API**,
encrypted at rest, taken on a schedule by GitHub Actions:

| | |
|---|---|
| Take a backup | `.github/workflows/backup.yml` → `scripts/backup-db.mjs` |
| Prove it is restorable | `scripts/verify-backup.mjs` |
| Put it back | `scripts/restore-db.mjs` |
| Where backups live | GitHub Actions artifacts, 90-day retention |
| Encryption | AES-256-GCM under `BACKUP_ENCRYPTION_KEY` |

This is strictly weaker than a physical backup. The gap is enumerated below rather than
glossed over, because a DR plan whose limits are undocumented is a plan that fails at
exactly the wrong moment.

## RPO and RTO

**RPO — 24 hours.** The workflow runs nightly at `40 19 * * *` (19:40 UTC / 01:10 IST).
Everything written after the last successful run is gone. For a PG management system that
means up to a day of fee payments, complaints and check-ins.

That number is a *policy choice, not a technical floor*. A full dump of production today
is **611 rows / 28 KB sealed / 6.3 seconds**. Running it every 6 hours would cost about
112 KB of artifact storage a day and four minutes of Actions time a month. If a 24-hour
RPO is not acceptable, change the one cron line — do not assume it is expensive. What this
design genuinely **cannot** do is get below a scheduled interval; continuous recovery needs
PITR, which needs a paid plan.

**RTO — about 30 minutes to a restored database,** against a Supabase project that already
exists. Measured and estimated components:

| Step | Time | Basis |
|---|---|---|
| Download artifact + `verify-backup.mjs` | < 1 min | measured, 28 KB file |
| Rebuild schema (only for a *new* project) | 5–10 min | `db/schema.sql` 1855 lines, `db/rls-policies.sql` 63 policies, run in the SQL editor |
| Recreate auth accounts | ~1 min | 25 accounts, one Admin API call each |
| Restore rows | ~1 min | 611 rows in ~60 round trips; the dump direction takes 6.3 s |
| Re-seed 2 identity sequences | < 1 min | two `setval` statements, by hand |
| Re-point the app (Vercel env, DNS) | 5–10 min | not automated |

**"Restored" is not "fully operational."** Passwords and MFA are not in any logical backup.
Every user must complete a password reset before they can sign in, and every MFA-enrolled
user must re-enrol. That tail is not bounded by us and is the honest reason the RTO above
is for the *database*, not for the service.

## What is backed up

All 20 application tables, **discovered from the live schema** rather than read off a
hardcoded list, so a table added tomorrow is captured tonight:

```
announcements  audit_log  beds  complaint_events  complaints  expenses
fee_payments   floors     hostels  leaves  menus  notifications
revenues       rooms      security_alerts  students  subscriptions
tasks          users      visitors
```

`scripts/backup-db.mjs` also carries a reviewed `EXPECTED_TABLES` manifest, which is used
**only as a drift check**. If the live set and the manifest disagree, the backup still
captures everything and the *job* fails afterwards — so a schema change is a loud reminder
to update `RESTORE_ORDER` and the FK map, never a silent data loss.

> **Why discovery rather than a hardcoded list:** the table set is read from the live
> OpenAPI schema on every run, and the reviewed `EXPECTED_TABLES` manifest is only a drift
> *check*. A table added in a migration is therefore backed up the same night, and the drift
> warning fires **after** the file is written — so a schema change never costs a night's data.
> There is no drift today: `db/schema.sql` and production both define the same 20 tables.

Also captured: the **auth user directory** (`auth.users` ids, emails, phones, metadata, and
which MFA factors existed). This is the directory, not the credentials — see below.

## What is NOT backed up, and what happens instead

| Not in the dump | Why | Recovery story |
|---|---|---|
| **`auth.users` credentials** — password hashes, MFA factor secrets, refresh tokens | The Admin API does not expose them, by design | The backup keeps each account's **original UUID**, which matters because `public.users.id` is an FK to `auth.users(id)`. `restore-db.mjs --recreate-auth-users` recreates the accounts under those UUIDs with **no password**; every user then does a "forgot password" flow, and MFA users re-enrol. Sessions do not survive. |
| **Storage objects** — the `student-docs`, `receipts` and `complaint-photos` private buckets | PostgREST does not expose Storage; objects would also dwarf the 28 KB dump | **Not covered. There is no automated recovery for uploaded files.** The DB rows keep their paths (`students.photo_url`, `students.id_proof_url`, `complaints.photo_url`, `expenses.receipt_url`), so after a restore those columns point at objects that may not exist and signed-URL generation will 404. Today exactly **1 row** across production references an object (one ID proof), so the present exposure is small — but it grows with usage. If uploads become material, this is the next gap to close. |
| **Schema, RLS policies, functions, triggers, roles** | A logical row dump carries data, not DDL | `db/schema.sql` (59 functions, 24 triggers) and `db/rls-policies.sql` (63 policies) are in the repo and rebuild the structure. They are version-controlled, which is a *better* guarantee than a nightly dump, because a reviewer can read the diff. Verified in sync with production: both define the same 20 tables. |
| **Realtime / queued jobs / rate-limit state** (`app.rate_limits`) | Ephemeral by nature | Rebuilds itself. Losing it means rate-limit counters reset, which is acceptable. |
| **Identity sequence positions** | `setval` is DDL-adjacent; PostgREST cannot run it | `restore-db.mjs` prints the exact `setval` statements for `audit_log` and `security_alerts` at the end of a restore. **Skipping them means the next insert collides with a restored id.** |

## Consistency caveat

This is **not a transactionally consistent snapshot.** Each table is read in a separate HTTP
request, so a write landing mid-dump can appear in one table and not another. Two things
reduce that to a non-issue in practice:

1. Tables are dumped **parents-first**, so the worst case is a child row that is simply
   absent (harmless) rather than a child pointing at a parent that was never read (fatal on
   restore).
2. `verify-backup.mjs` checks **38 foreign keys across the dump** and fails if any row
   references a parent the backup does not contain.

If verification reports dangling FKs, re-run the backup — you caught a torn snapshot. If it
repeats, the FK map in `verify-backup.mjs` is stale relative to the schema.

## Encryption and key handling

The dump is every tenant's PII: names, phone numbers, ID proof references, payment history.
GitHub Actions artifacts are downloadable by anyone with read access to the repository, so
the dump is never written in the clear.

- gzip → **AES-256-GCM**, random 96-bit IV per file, tag stored in the header.
- The header's identity fields (format, version, timestamp, project ref, cipher, compression)
  are fed in as **AAD**, so editing a backup's timestamp or project ref invalidates it instead
  of quietly producing a plausible file.
- Table names and row counts live **inside** the ciphertext, not in the header — possession
  of the file alone reveals nothing about tenant volumes.
- `BACKUP_ENCRYPTION_KEY` is 32 bytes, as 64 hex characters or base64. Generate one with:

  ```bash
  node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
  ```

**Two things about the key that are easy to get wrong:**

1. **Lose the key and every backup is landfill.** It must exist somewhere that is not
   GitHub — a password manager, an offline copy. There is no recovery path.
2. **Key and ciphertext currently live in the same place.** Both the artifacts and the
   secret sit inside the GitHub repository, so a repo-admin compromise gets both. Encryption
   here buys protection against *artifact* exposure, not against full account takeover. The
   real improvement is a periodic download of artifacts to storage outside GitHub. That is
   not automated today.

Rotating the key does **not** re-encrypt existing artifacts. Keep the old key for as long as
backups sealed with it are still within retention.

## Required repository secrets

Referenced by name only, in `.github/workflows/backup.yml`:

| Secret | What it is |
|---|---|
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | service-role key — bypasses RLS, reads every tenant |
| `BACKUP_ENCRYPTION_KEY` | 32-byte key, hex or base64 |

The workflow checks all three are present **before** touching the database, so a missing or
renamed secret fails with a message that names it rather than a cryptic runtime error.

## Runbook: taking a backup by hand

```bash
export BACKUP_ENCRYPTION_KEY=...          # or leave it in .env.local
node scripts/backup-db.mjs --out backups --strict
node scripts/verify-backup.mjs --latest --dir backups --min-rows 100
```

Do this before any migration. The output directory gets a self-contained `.gitignore`
containing `*`, so a dump can never be committed by accident.

Exit codes for `backup-db.mjs`: `0` clean, `1` the backup failed, `3` the backup **succeeded**
but the schema drifted from the manifest.

## Runbook: restoring

`restore-db.mjs` overwrites data, so it is **dry-run by default** and refuses to write unless
both `--execute` *and* `--confirm-overwrite <project-ref>` are given, with the ref matching the
target it resolved. Typing the ref by hand is the point: you cannot restore into the wrong
project by re-running a shell line whose target you forgot to change.

### 1. Get the artifact and prove it is good

Download from the Actions run (or `gh run download <run-id>`), then:

```bash
export BACKUP_ENCRYPTION_KEY=...
node scripts/verify-backup.mjs path/to/hostelpro-<ref>-<ts>.hpb
```

Do not proceed if this does not print `RESTORABLE`.

### 2. Prepare the target project

Only for a **new** project — skip if you are restoring in place:

1. Run `db/schema.sql` in the Supabase SQL editor.
2. Run `db/rls-policies.sql`.
3. Create the three private Storage buckets: `student-docs`, `receipts`, `complaint-photos`.
4. Confirm the rebuild produced all 20 tables before restoring
   (`select count(*) from information_schema.tables where table_schema = 'public'`).
   `db/schema.sql` creates every one of them, including `security_alerts`; a short count
   means the script did not run to completion, and restoring into a partial schema will
   fail on the first missing table.

### 3. Point the restore at the target

```bash
export RESTORE_SUPABASE_URL=https://<target-ref>.supabase.co
export RESTORE_SUPABASE_SERVICE_ROLE_KEY=...     # the TARGET's key, not production's
```

If `RESTORE_SUPABASE_URL` is unset the tool falls back to the app's own project and says so
loudly. It will also refuse to send `SUPABASE_SERVICE_ROLE_KEY` to a `--target-url` you typed
by hand, so the production key cannot leak to an arbitrary host.

### 4. Dry run, always

```bash
node scripts/restore-db.mjs backups/hostelpro-<ref>-<ts>.hpb
```

This reads the target and prints a per-table plan — rows in the backup vs rows in the target,
and what it would do to each. Nothing is written. Read it before continuing.

### 5. Execute

```bash
node scripts/restore-db.mjs backups/hostelpro-<ref>-<ts>.hpb \
  --execute --confirm-overwrite <target-ref> \
  --recreate-auth-users \
  --truncate                       # only for a clean rebuild; omit to merge by id
```

Ordering is handled for you. Rows go in parents-first, and the two FK cycles in the schema
(`users.hostel_id → hostels.owner_user_id → users`, `students.bed_id → beds.student_id →
students`) are broken by inserting those two columns as null and patching them in a second
pass. Without `--truncate` the restore is an idempotent upsert on `id` and can be re-run.

### 6. Finish by hand

The tool prints these; they are not optional.

```sql
select setval(pg_get_serial_sequence('public.audit_log','id'),       coalesce((select max(id) from public.audit_log), 1));
select setval(pg_get_serial_sequence('public.security_alerts','id'), coalesce((select max(id) from public.security_alerts), 1));
```

Then:

- Trigger password resets — **no one can sign in until they do.**
- Tell MFA users to re-enrol.
- Re-upload or accept the loss of Storage objects.
- Update `NEXT_PUBLIC_SUPABASE_URL` / keys in Vercel if the project ref changed.
- **Run `node scripts/_qa-rls-attack.mjs` against the restored project before letting anyone
  in.** A restore recreates rows, not confidence that the policies came back correctly.

## Restore drill

A backup nobody has restored is a hypothesis. Drill quarterly, and after any schema change.

**Procedure** (~30 minutes, costs one scratch project):

1. Create a second Supabase project. Do not reuse the production one.
2. Run `db/schema.sql`, then `db/rls-policies.sql`, then create the three Storage buckets
   (`student-docs`, `receipts`, `complaint-photos`). The SQL files create every table;
   only the buckets need doing by hand.
3. Download the most recent nightly artifact and `verify-backup.mjs` it.
4. Point `RESTORE_SUPABASE_URL` / `RESTORE_SUPABASE_SERVICE_ROLE_KEY` at the scratch project.
5. Dry run. Confirm every table shows `in target: 0`.
6. `--execute --confirm-overwrite <scratch-ref> --recreate-auth-users --truncate`.
7. Run the two `setval` statements.
8. Re-run `backup-db.mjs` **against the scratch project** and diff the row counts against the
   original backup's. They must match exactly. This is the actual pass/fail: a restore that
   silently dropped rows looks like a success otherwise.
9. Run `scripts/_qa-rls-attack.mjs` and `scripts/_qa-tenant-integrity.mjs` against the scratch
   project. Data back is not the same as tenancy back.
10. Set one user's password via the Admin API and sign in end-to-end.
11. **Delete the scratch project.** It holds a full copy of production PII.
12. Record the date, the artifact used, and the row-count diff below.

### Drill log

**2026-08-20 — partial drill. Read path and write logic verified; a real second Postgres was
not involved.**

What was actually run, against production project `nimxvgzscbanhtvgnjll`:

| Check | Result |
|---|---|
| `backup-db.mjs --strict` against production | **PASS** — 20 tables discovered, 611 rows + 25 accounts, 28,103 bytes sealed, 6.3 s, manifest matched |
| `verify-backup.mjs` on that file | **PASS** — decrypted, all 20 tables present, counts self-consistent, no core table empty, every `public.users` row had a matching auth account, **38 FK checks clean** |
| Wrong `BACKUP_ENCRYPTION_KEY` | **PASS (refused)** — exit 1, "decryption failed" |
| Header tampered (`createdAt` edited) | **PASS (refused)** — AAD mismatch, exit 1 |
| One ciphertext bit flipped | **PASS (refused)** — sha256 mismatch, exit 1 |
| File truncated by 500 bytes | **PASS (refused)** — length mismatch, exit 1 |
| Schema drift injected into the manifest | **PASS** — exit 3, both directions reported, **and the backup file was still written first** |
| `restore-db.mjs --execute` without `--confirm-overwrite` | **PASS (refused)** — exit 2, nothing written |
| `restore-db.mjs --execute --confirm-overwrite <wrong-ref>` | **PASS (refused)** — exit 2, nothing written |
| `restore-db.mjs --target-url <host>` with only the production key | **PASS (refused)** — exit 1, key not sent |
| Restore dry run against production | **PASS** — all 20 tables reported backup count == live count |
| Restore **write path**, end to end against a protocol-level PostgREST/GoTrue stand-in | **PASS** — 611 rows POSTed, parents-first order, `users` inserted without `hostel_id` and `students` without `bed_id`, 24 + 15 rows patched in pass 2, deletes issued children-first with filters, all upserts idempotent (`resolution=merge-duplicates`), no batch over 500 |

### Drill run 2026-08-20 — schema rebuild and production semantics, on a real Postgres

The earlier version of this section said a scratch project "costs money". **That was wrong.**
Supabase allows **two active free projects** per organisation, and `get_cost` for a new project
in this org returns **$0/month**. A staging project was created (`hostelpro-staging`, ref
`gtodjqlhdtvpnppulwgj`, `ap-southeast-1`, same region as production) and the drill was run.

**Rebuild from the repo alone — PASS, exact parity.** `db/schema.sql` and `db/rls-policies.sql`
were applied to the empty project and produced, byte-for-byte in count, what production has:

| | staging | production |
|---|---|---|
| public tables | 20 | 20 |
| RLS policies | 64 | 64 |
| functions (`public` + `app`) | 61 | 61 |
| triggers | 45 | 45 |
| `pg_cron` jobs | 1 | 1 |
| storage buckets | 3 | 3 |
| tables with RLS enabled | 20 | 20 |

This is the half of DR the backup file cannot give you, and it is now proven rather than assumed.

**Production semantics — PASS.** A restore-shaped object graph (explicit ids, parents first,
both FK cycles patched in a second pass) was inserted into the rebuilt schema inside a
transaction that then rolled itself back. Every trigger fired correctly on real Postgres:

| Behaviour | Result |
|---|---|
| `rooms_capacity_sync` auto-created beds | 3 beds |
| `students_bed_sync` set `beds.student_id` | true |
| `students_bed_guard` derived `students.room_id` | true |
| `fee_status_compute` derived fee status | `paid` |
| FK cycle 1 — `users.hostel_id` patched in pass 2 | true |
| FK cycle 2 — `students.bed_id` accepted | true |
| `fee_payments_after_change` notification | 1 row |
| Rollback left staging clean | 0 rows in every table |

That closes the "verified in logic, unverified in production semantics" caveat.

**What the drill found.** Run as an ordinary caller, the FK-cycle patch **fails**:

```
ERROR 42501: You cannot move an account to another hostel.
CONTEXT: app.users_update_guard() ... update public.users set hostel_id = ...
```

`app.users_update_guard` deliberately forbids repointing `users.hostel_id` — it is an
account-takeover primitive (SECURITY.md §3.4). Its only bypass is `app.is_super_admin()`, which
includes `app.is_service_role()`. So the restore's second pass works **only** when run with the
service-role key. It is, and the same run passed once the caller was the service role. But if
anyone ever runs a restore with a user JWT, it will fail halfway through with an error that
reads like a permissions bug rather than "you used the wrong key". Use the service-role key.

**Still not exercised:** `restore-db.mjs` writing to a real Postgres end to end. The Supabase
Management API exposes only publishable keys, so the staging **service-role** key has to be
copied from the dashboard by a human. To finish this last step:

1. Supabase dashboard → `hostelpro-staging` → Settings → API → copy the `service_role` key.
2. Put it in `.env.local` as `RESTORE_SUPABASE_SERVICE_ROLE_KEY` (never in a tracked file —
   `scripts/security-scan.mjs` compares tracked files against real `.env` values and will fail).
3. `RESTORE_SUPABASE_URL=https://gtodjqlhdtvpnppulwgj.supabase.co node scripts/restore-db.mjs       backups/<file>.hpb --execute --confirm-overwrite gtodjqlhdtvpnppulwgj --recreate-auth-users`
4. Then steps 3–12 of the drill above.

**Delete the staging project, or empty it, once the drill is done** — a completed restore leaves
it holding a full copy of production personal data.

## Failure modes to watch

- **Nightly job green but backups useless** — this is what `verify-backup.mjs` exists to
  prevent. If it is ever removed or its assertions weakened, the backup becomes decorative.
- **Every core table empty** — the dump ran with a key that could not read (an anon key
  instead of service-role). Verification fails on this explicitly.
- **A table in the dump that the rebuilt schema does not have** — means `db/schema.sql`
  drifted behind a migration applied straight to production. The nightly drift check is what
  catches this; treat that warning as a real defect, not noise.
- **`BACKUP_ENCRYPTION_KEY` known only to GitHub** — see the key section. One lost account
  and 90 days of backups are unreadable.
- **A new table added without updating the manifest** — the data *is* captured, but
  `RESTORE_ORDER` will not place it and the restore will skip it. The nightly job fails on
  drift specifically so this is noticed within a day.
