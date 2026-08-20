# Data retention and privacy — HostelPro

What personal data this application holds, on what basis, for how long, how a person gets a copy or
gets it erased, and who else touches it.

Companion documents: [`../THREAT-MODEL.md`](../THREAT-MODEL.md) §2 (assets),
[`access-control.md`](./access-control.md) (who can reach what),
[`logging-and-monitoring.md`](./logging-and-monitoring.md) §4 (log retention),
[`incident-response.md`](./incident-response.md) §6 (breach notification).

> **Not legal advice.** The statutory references below are the author's best understanding and must
> be confirmed with counsel before real residents' data is processed. What *is* authoritative here is
> the **data inventory in §4** — every column, table and bucket in it was read out of
> `db/schema.sql` and `lib/storage.ts`.

---

## 1. Why this document exists now

`SECURITY.md` §5 carries two open items that this document is the first half of:

- *"No GDPR/DPDP erasure path — `students_delete` is service-role only and there is no tooling behind
  it. **Build an erasure runbook before real personal data.**"* → §6.
- *"No retention policy for `audit_log` IP/user-agent."* →
  [`logging-and-monitoring.md`](./logging-and-monitoring.md) §4.

`THREAT-MODEL.md` §8 also lists "data-subject deletion tooling (soft-delete only today)" as an
explicit non-goal at this stage. This document does not change that: it documents the manual path and
the decisions, so that the gap is a known, bounded, operable one rather than a surprise on the day
someone asks.

---

## 2. Roles under the DPDP Act 2023

| Data set | Data Fiduciary | Data Processor | Data Principal |
|---|---|---|---|
| Resident (student) data, complaints, leaves, visitors, fee records | **The hostel / PG operator** — they decide to collect it and why | **HostelPro** | The resident (and the guardian and visitor, for their own contact details) |
| Owner and platform-staff accounts | **HostelPro** | Supabase / Vercel | The owner, manager, warden |
| `audit_log`, security telemetry | **HostelPro** — collected for HostelPro's own security purpose | Supabase / Vercel | Whoever the row is about |

**What follows from this split, and it is not cosmetic:**

1. The **consent notice, the lawful basis and the response to a resident's request are the hostel
   operator's obligations**, not HostelPro's. HostelPro's job is to make them possible.
2. HostelPro must have a **written contract** with each tenant covering processing (DPDP requires a
   valid contract for a Fiduciary to engage a Processor). It should state: processing only on the
   Fiduciary's instructions; the breach-notification duty to notify the tenant immediately
   ([`incident-response.md`](./incident-response.md) §6.1); the sub-processors in §7; and what happens
   to data on termination.
3. There is **no tenant contract in this repository.** It is a prerequisite for onboarding a real
   tenant, and it is not a document an engineer should draft alone.

---

## 3. Children

`THREAT-MODEL.md` §2 flags resident data as "High (minors possible)". PG and hostel residents in
India routinely include people under 18.

DPDP §9 attaches specific duties for a child's data: **verifiable parental consent** before
processing, and a prohibition on tracking, behavioural monitoring and targeted advertising directed
at children.

**The application cannot currently tell whether a resident is a child.** There is no
`date_of_birth` or age column anywhere in `db/schema.sql` — verified. `students` records
`date_of_joining` and nothing about age.

That has two consequences, and they should be a conscious choice rather than an accident:

- The **positive**: HostelPro does no tracking, no behavioural profiling, no advertising and no
  analytics of any kind (§7), so the §9 *prohibitions* are satisfied by construction and by the
  absence of an age field, not merely by policy.
- The **gap**: the §9 *consent* duty cannot be discharged through the product, because the product
  cannot identify which residents it applies to. The hostel operator must handle parental consent in
  their own registration paperwork.

**Decision required before real tenants:** either (a) leave age out of the system and make parental
consent a documented, out-of-band duty in the tenant contract — the current de facto position, and
the more privacy-preserving one because it avoids collecting a further identifier; or (b) add a
minor flag so the product can enforce §9 duties. Do not add a full date of birth to answer a
yes/no question. Record whichever is chosen, here, with a date.

---

## 4. Data inventory

Every location personal data is stored. Sources: `db/schema.sql`, `lib/storage.ts`.
Sensitivity: **H** = identity-theft or safety risk if exposed; **M** = privacy or commercial harm;
**L** = limited.

### 4.1 Application tables

| Table | Personal data | Subject | Sens. | Retention (§5) |
|---|---|---|---|---|
| `students` | `full_name`, `phone`, `email`, `photo_url`, `guardian_name`, `guardian_phone`, `permanent_address`, `id_proof_type`, `id_proof_url`, `date_of_joining`, `monthly_fee`, `room_id`/`bed_id`, `status`, `vacated_at` | Resident + **guardian** (a third party who never uses the app) | **H** | 12 months after `vacated_at`, then erase (§6) |
| `users` | `full_name`, `email`, `phone`, `role`, `hostel_id`, `status`, timestamps. One row per human, residents included | Everyone | M | With the account; erase with the linked student |
| `fee_payments` | `student_id`, `period_month`, amounts, `mode`, `paid_on`, free-text `notes`, `recorded_by` | Resident | M | Financial record — see §5 |
| `complaints` | `student_id`, `title`, `description` (free text, may name other residents or staff), `photo_url`, `resolution_note`, `updated_by` | Resident + whoever is named | M | 12 months after resolution |
| `complaint_events` | `actor_user_id`, `note`, status timeline | Resident + staff | M | With the complaint |
| `leaves` | `student_id`, dates, `reason` (free text — may reveal health or family circumstances), `decided_by`, `decision_note` | Resident | **H** — free-text reasons routinely contain sensitive context | 12 months |
| `visitors` | `visitor_name`, `visitor_phone`, `relation`, `check_in_at`/`check_out_at`, `student_id`, `logged_by` | **The visitor** — a third party with no account, no notice and no relationship with HostelPro — and, by inference, the resident's social contacts | **H** | 12 months (§5) |
| `beds` | `student_id` — occupancy, i.e. where a named person sleeps | Resident | M | With the student |
| `announcements` | `author_user_id`, `title`, `body` (free text, may name people) | Staff + anyone named | L | 24 months |
| `tasks` | `assigned_to`, `created_by`, `title`, `description` | Staff | L | 24 months |
| `expenses` / `revenues` | `note` (free text), `receipt_url`, `uploaded_by` | Staff + third parties named on receipts | M | Financial record — see §5 |
| `menus` | `updated_by` | Staff | L | Current only |
| `notifications` | `user_id`, `title`, `body` — bodies quote task and complaint text, so they carry copies of the above | Everyone | L | 90 days |
| `hostels` | `address`, `owner_user_id`, `rules` | Owner / business | L | Life of the tenant |
| `subscriptions` | `owner_user_id`, `amount`, `notes` | Owner | M | 8 years — commercial record (§5) |
| `audit_log` | `actor_user_id`, `target_id`, **`ip`**, **`user_agent`**, `meta` | Everyone who signs in | M | 400 days; `ip`/`user_agent` nulled at 90 days ([`logging-and-monitoring.md`](./logging-and-monitoring.md) §4) |
| `app.rate_limits` | SHA-256 hashed keys only — never a clear IP or identifier (`lib/rate-limit.ts`) | Pseudonymous | L | Hours |

### 4.2 Supabase Auth (`auth.users`, not an application table)

Email or synthetic email, phone, **bcrypt password hash** (never held by the application), TOTP
factors, sign-in timestamps, `app_metadata` (`must_change_password`, `hostel_id`). Managed by
Supabase; reachable only through the Auth Admin API with the service-role key. Deleting an auth user
cascades the `public.users` row (`id uuid primary key references auth.users(id) on delete cascade`).

Students authenticate by **phone**, mapped to a synthetic email (`THREAT-MODEL.md` §4) — so a
resident's phone number is also an authentication identifier, which is why changing it is an account
operation and not a profile edit.

### 4.3 Storage buckets — all private (`lib/storage.ts`)

| Bucket | Contents | Sens. | Signed-URL TTL |
|---|---|---|---|
| `student-docs` | **Resident photo and ID-proof scan** — the highest-value data in the system | **H** | 15 min |
| `receipts` | Expense receipts; may show third-party names and account details | M | 30 min |
| `complaint-photos` | Photos attached to complaints; may show people or interiors | M | 30 min |

Object keys are `<hostelId>/<folder>/<uuid>.<ext>`; `isPathInHostel()` refuses anything else, and
declared MIME types are ignored in favour of magic-byte sniffing. Documents are served
`Content-Disposition: attachment` so a PDF cannot render inside the viewer's origin
(`SECURITY.md` §3.3 item 6).

### 4.4 A specific warning about ID proofs

`students.id_proof_type` is an unconstrained `text` column, so nothing stops a warden uploading an
**Aadhaar** copy. Aadhaar is governed by its own statute and UIDAI guidance, which restricts storing
copies of the Aadhaar letter. Two recommendations, neither of which this document can implement on
its own:

1. Prefer a non-Aadhaar ID for residence verification, or a **masked** Aadhaar where one is
   unavoidable.
2. Consider verifying at registration and **storing only `id_proof_type` and the last four digits**,
   rather than the scan. It removes the single highest-consequence asset in the system. The schema
   already supports this — leave `id_proof_url` null.

Until that decision is taken, `student-docs` is the asset that sets the severity floor for any
incident touching a hostel ([`incident-response.md`](./incident-response.md) §1).

---

## 5. Lawful basis and retention

### 5.1 Lawful basis

DPDP §4 permits processing on **consent** or on one of the narrow "certain legitimate uses" in §7.
Unlike the GDPR, **there is no general "necessary for a contract" basis**, so the practical position
is:

- **Residents:** notice + consent at registration, taken by the hostel operator (§2). §7(a) — data
  voluntarily provided for a specified purpose — may cover part of it, but a resident handing details
  to a warden who types them in is a weaker fit than an explicit signed notice. Do not rely on it
  without advice.
- **Staff and owners:** employment / commercial relationship, again with notice.
- **Visitors:** the weakest link in the whole inventory. A visitor's name and phone are recorded by a
  warden; the visitor gets no notice and has no relationship with HostelPro. **The tenant must display
  a visible notice at the visitor log point** saying what is recorded, why, and for how long. Add this
  to the onboarding checklist.
- **`audit_log`:** HostelPro's own security purpose. It is retained for the shortest period that
  supports investigation and legal duty, and identifying columns age out first
  ([`logging-and-monitoring.md`](./logging-and-monitoring.md) §4).

### 5.2 Retention periods

Storage limitation means keeping data no longer than the purpose needs. These are defaults; a tenant's
own statutory duties override them upward, never downward.

| Data | Default | Reasoning |
|---|---|---|
| Active resident record | Life of the residency | Purpose is live |
| Vacated resident (`students` + linked `users` + child rows) | **12 months after `vacated_at`**, then erase (§6) | Covers a deposit dispute, a re-admission and one audit cycle. Beyond that the hostel has no purpose for a former resident's guardian phone and permanent address |
| **ID-proof scan and photo** (`student-docs`) | **Delete at vacate**, ahead of the record itself | Highest consequence, lowest ongoing purpose. Verification happened at registration; the scan earns nothing after departure |
| `visitors` | 12 months | Safety and dispute purpose is short-lived. This is a movement log about third parties — the least defensible thing here to keep indefinitely |
| `leaves` | 12 months | Free-text reasons carry sensitive context |
| `complaints` + `complaint_events` | 12 months after resolution | Pattern detection and dispute |
| `fee_payments`, `expenses`, `revenues`, `subscriptions` | **Per the tenant's statutory accounting duty; default 8 years** | Indian tax and company-law record-keeping periods differ by entity type and are longer than any privacy-driven period. **Confirm the applicable period with the tenant's accountant and record it per tenant** — do not delete financial records on a privacy schedule |
| `notifications` | 90 days | Transient UI state that quotes other records |
| `announcements`, `tasks` | 24 months | Operational history |
| `audit_log` | 400 days; `ip`/`user_agent` nulled at 90 days | [`logging-and-monitoring.md`](./logging-and-monitoring.md) §4 — and note the CERT-In 180-day floor discussed there |

**None of these are automated today** except the `audit_log` job (see its status note). Vacated
resident records accumulate until someone runs §6. That is a real, current gap: write the quarterly
purge into the ops calendar or it will not happen.

**A conflict you will hit:** a former resident's fee ledger must survive for the accounting period,
while their guardian's phone and permanent address should not. `fee_payments` references
`student_id` with `on delete cascade`, so deleting the student **deletes the fee history too**. The
resolution is §6.4 — anonymise rather than delete when a financial record must survive.

---

## 6. Data-subject requests and erasure

DPDP gives a Data Principal rights to information about processing, correction and completion, and
erasure. Requests come to the **hostel operator** (the Fiduciary); HostelPro executes them.

Log every request in an ops record with: who asked, how identity was verified, what was done, when.
Acknowledge within **72 hours** and complete within **30 days** as an operating standard, and confirm
the statutory period against the current DPDP Rules.

**Verify identity before acting**, and do it out of band — an "erase my data" request is also a
denial-of-service against the requester if someone else sends it. For a resident, the warden knows
them by sight; use that.

### 6.1 Access — give a copy

Run as the service role in the SQL editor. Redact `recorded_by` / `decided_by` / `logged_by` before
sending: those identify staff members, who are separate Data Principals.

```sql
-- Resolve the person first, and check there is exactly one
select id, hostel_id, user_id, full_name, phone, status, vacated_at
from public.students where phone = '<phone>';

-- The record itself
select full_name, phone, email, guardian_name, guardian_phone, permanent_address,
       id_proof_type, date_of_joining, monthly_fee, status, vacated_at
from public.students where id = '<student-uuid>';

select period_month, amount_due, amount_paid, status, paid_on, mode, notes
from public.fee_payments where student_id = '<student-uuid>' order by period_month;

select created_at, category, title, description, status, resolved_at, resolution_note
from public.complaints where student_id = '<student-uuid>' order by created_at;

select from_date, to_date, reason, status, decided_at, decision_note
from public.leaves where student_id = '<student-uuid>' order by from_date;

select check_in_at, check_out_at, visitor_name, visitor_phone, relation
from public.visitors where student_id = '<student-uuid>' order by check_in_at;

-- Their own account activity (not other people's)
select at, action, target_type, ip, user_agent
from public.audit_log where actor_user_id = '<their users.id>' order by at;
```

Files: download `students.photo_url` and `students.id_proof_url` from `student-docs`, plus any
`complaints.photo_url` from `complaint-photos`.

### 6.2 Correction

Do it **through the app**, not by SQL: Warden → the student's record. The write is validated, tenancy
guards fire, and it is audited. A direct `update` leaves no trail and bypasses
`students_identity_guard`.

### 6.3 Erasure — the runbook

> **Status: written, not executed.** This procedure has **not** been run against the production
> database. Dry-run it on a Supabase branch or a seeded copy and record the result here before using
> it on a real person's data. `students_delete` is service-role only (`db/rls-policies.sql`), so it
> cannot be done from the app — that is by design (`CLAUDE_2.md` §4.10, no hard deletes) and it is why
> this runbook exists.

**Step 0 — decide erase vs. anonymise.** If any financial record must survive its statutory period
(§5.2), go to §6.4 instead. Deleting the student cascades the fee ledger with it.

**Step 1 — vacate through the app first.** Warden → Vacate. This sets `students.status = 'vacated'`,
deactivates the linked account, and frees the bed correctly through the `students_bed_guard` /
`students_bed_sync` triggers. Doing it by SQL risks leaving `beds` inconsistent.

**Step 2 — capture the storage paths before the rows are gone.**

```sql
select s.id, s.user_id, s.photo_url, s.id_proof_url,
       (select array_agg(c.photo_url) from public.complaints c
         where c.student_id = s.id and c.photo_url is not null) as complaint_photos
from public.students s where s.id = '<student-uuid>';
```

**Step 3 — delete the objects** from `student-docs` and `complaint-photos` (Supabase Dashboard →
Storage, or `removeFromBucket()` in `lib/storage.ts`). Do this **before** the rows, or the keys are
lost and the files become unreferenced and immortal.

**Step 4 — delete the student row.** In a transaction, and check the counts before committing:

```sql
begin;
delete from public.students where id = '<student-uuid>';
-- Cascades: fee_payments, complaints (-> complaint_events), leaves, visitors.
-- Sets beds.student_id to null.
commit;
```

**Step 5 — delete the login.** Use the Auth Admin API (`auth.admin.deleteUser(userId)`); the
`public.users` row cascades from `auth.users`. If a foreign key blocks it — the `users` row is
referenced without cascade by `created_by`, `recorded_by`, `decided_by`, `logged_by`, `uploaded_by`,
`updated_by`, `actor_user_id`, `author_user_id`, `assigned_to` — **do not force it.** Anonymise the
`users` row instead (§6.4). A former resident is unlikely to be referenced by those columns; a former
staff member always is.

**Step 6 — leave `audit_log` alone.** `actor_user_id` carries **no foreign key** to `users`
(verified in `db/schema.sql`), so the trail survives erasure intact. This is deliberate: the audit
record is held on a separate legal basis (security, and a legal duty to be able to investigate), it
identifies a UUID rather than a name once the account is gone, and its own retention clock (§4.1)
disposes of it. Deleting audit rows to satisfy an erasure request destroys the evidence needed for
the next breach notification.

**Step 7 — record it** in the request log: what was deleted, what was retained and on what basis,
who ran it, when.

### 6.4 Anonymisation — when erasure would destroy a required record

Keep the row, remove the person from it:

```sql
begin;
update public.students set
  full_name         = 'Erased resident',
  phone             = 'erased-' || left(md5(id::text), 12),  -- unique: a partial index covers phone
  email             = null,
  photo_url         = null,
  guardian_name     = null,
  guardian_phone    = null,
  permanent_address = null,
  id_proof_type     = null,
  id_proof_url      = null
where id = '<student-uuid>';

update public.users set
  full_name = 'Erased user', email = null, phone = null
where id = '<their users.id>';
commit;
```

Note the `phone` value: `students_phone_active_key` is a unique index on `phone` where
`status <> 'vacated'`, so a constant would collide across multiple erasures. Delete the storage
objects (§6.3 step 3) separately — nulling the URL does not remove the file.

Then check the free-text fields for names the structured columns do not cover: `fee_payments.notes`,
`complaints.description` and `resolution_note`, `leaves.reason`, `expenses.note`. **Free text is where
anonymisation quietly fails.**

### 6.5 What HostelPro cannot do

- **Delete from backups.** Backups are point-in-time snapshots and are not selectively editable. The
  honest position, which should be in the tenant notice: erased data disappears from backups when
  those backups age out; it is not restored into live systems; and **any restore must be followed by
  re-running the erasure**, because a restore resurrects deleted rows. Take the backup retention
  period from [`backup-and-dr.md`](./backup-and-dr.md) — if that document is not yet in place, get it
  from the Supabase dashboard — and record it here.
- **Erase from vendor platform logs.** Supabase Auth logs and Vercel access logs are outside our
  control; they age out on the vendors' schedules (§7).
- **Un-send anything.** There is no email or SMS channel, so nothing has left the platform — which is
  one of the quiet advantages of the in-app-only design.

---

## 7. Sub-processors and data location

| Sub-processor | Purpose | Data | Notes |
|---|---|---|---|
| **Supabase** | Postgres, Auth, private Storage | Everything in §4 | Project `nimxvgzscbanhtvgnjll`. Holds the bcrypt password hashes; the app never does |
| **Vercel** | Application hosting, edge, runtime and access logs | Requests, IPs, user-agents; the runtime `console.error` output in [`logging-and-monitoring.md`](./logging-and-monitoring.md) §3.4 | Project `dhrishta/hostelpro`. Holds `SUPABASE_SERVICE_ROLE_KEY` as an encrypted env var |
| **GitHub** | Source and CI | Source code only — no resident data | `.github/workflows/security.yml` runs without secrets |

**That is the complete list**, and it is verifiable rather than asserted: `THREAT-MODEL.md` §1 and
§6D record no payment provider, no webhooks, no queues, no AI/LLM integration, no email or SMS
provider and no second backend; there is exactly one outbound HTTP call in the entire application
(`app/api/health/route.ts` → the Supabase health URL, built from an env var and never from user
input); and the 29 production dependencies in `package.json` contain **no analytics, telemetry,
error-reporting or session-replay package** — verified by reading the list.

Supabase and Vercel are the trust root: a compromise of either is total, and the mitigations are
least-privilege keys and the ability to rotate (`THREAT-MODEL.md` §6D).

### 7.1 Data location — open, and it needs answering

**Where the Supabase project and the Vercel functions physically run is not recorded anywhere in this
repository, and this document will not guess it.** Find out and write it here:

```
Supabase Dashboard -> Project Settings -> General -> Region:  ____________
Vercel Dashboard   -> Project Settings -> Functions -> Region: ____________
```

It matters for two separate reasons:

1. **CERT-In** directions require ICT system logs to be maintained within Indian jurisdiction for a
   rolling 180 days ([`incident-response.md`](./incident-response.md) §6.4). Whether they bind an
   operation of this size, and whether the region satisfies them, needs legal input.
2. **Tenant expectation.** Indian hostel operators will ask where residents' ID proofs are stored,
   and the answer must be a fact, not a reassurance.

DPDP permits cross-border transfer except to countries the Central Government restricts. Check the
current restricted list against the answer above.

---

## 8. Data minimisation already in place

Worth recording, because these are the decisions that reduce how much §6 ever has to do.

| Decision | Where | Effect |
|---|---|---|
| No date of birth or age collected | `db/schema.sql` — verified absent | One fewer identifier; §3 discusses the trade-off |
| Roommates expose **name and phone only** | `st_my_roommates()` (`photo_url` removed — `SECURITY.md` §3.7 item 18) | A resident cannot build a photo directory of the hostel |
| Students see only their own room's beds | `beds_select` (`SECURITY.md` §3.7 item 17) | No mapping of occupied beds to other residents' account UUIDs |
| The Manager cannot read resident data at all | `db/rls-policies.sql` ([`access-control.md`](./access-control.md) §3.1) | An entire role removed from the resident-PII blast radius |
| Login identifiers hashed in logs and rate-limit keys | `hashIdentifier()`, `hashKey()` | Emails and phones are not stored in security telemetry |
| Password hashes never touch the application | Supabase Auth | Database compromise does not yield credentials (`THREAT-MODEL.md` §6C) |
| No analytics, telemetry or error reporter | `package.json` — verified | Nothing leaves the two sub-processors |
| Private buckets + short-lived signed URLs | `lib/storage.ts` | No durable public link to an ID proof can exist |

**Known counter-example, recorded honestly:** `select("*")` is used in roughly 20 queries. All are
RLS-scoped and none of these tables hold secrets, but it over-fetches columns into the RSC payload —
an open Low in `SECURITY.md` §5, to be narrowed when those queries are next touched. Over-fetching is
a minimisation failure even when it is not an access-control failure.

---

## 9. Before onboarding a real tenant

A checklist, not a wish list. Each item has a home in this document or a companion.

1. **Tenant data-processing contract** in place (§2). Blocking.
2. **Resident consent notice** drafted by the hostel operator, and a **visitor notice** displayed at
   the log point (§5.1). Blocking.
3. **Children decision** taken and recorded (§3).
4. **ID-proof policy** decided — store the scan, or type + last four only (§4.4).
5. **Data location** established and written into §7.1, with the CERT-In question answered.
6. **`audit_log` retention job** verified as running
   ([`logging-and-monitoring.md`](./logging-and-monitoring.md) §4).
7. **Erasure runbook dry-run** on a branch, and §6.3 updated with the result.
8. **Quarterly vacated-record purge** on the ops calendar (§5.2), with a named owner.
9. **Service-role key rotated** (`SECURITY.md` §5, and
   [`incident-response.md`](./incident-response.md) §4.5 — read the login-outage warning first).
10. **Leaked-password protection enabled** and `MFA_REQUIRED_ROLES` set
    ([`access-control.md`](./access-control.md) §5.2).
11. **Incident contact table filled in** ([`incident-response.md`](./incident-response.md) §2).
12. **Independent penetration test** commissioned — `SECURITY.md` §6 is explicit that a green suite
    is not proof of absence.
