# Account and data deletion — operator runbook

What the app does when somebody asks for their account to be deleted, and what a human then has
to do to actually fulfil it.

Companion documents: [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6 is the
**canonical erasure procedure** and the source of every retention period quoted here;
[`play-store.md`](./play-store.md) covers the Android wrapper;
[`access-control.md`](./access-control.md) covers who can reach what.

> **Not legal advice.** The retention reasoning is inherited from
> [`data-retention-and-privacy.md`](./data-retention-and-privacy.md), which is explicit that it must
> be confirmed with counsel before real residents' data is processed.

---

## 1. Why this exists

Google Play requires that an app which lets users create an account also let them **request
deletion of the account and its data**, from *both* inside the app *and* a publicly accessible web
URL. The web URL goes in Play Console under **Data safety → Account deletion URL**, and a reviewer
opens it **signed out** — a URL behind a login is a rejection.

There is a wrinkle specific to this product, and it changes the shape of the answer rather than
excusing it: **nobody creates their own account here.** The Super Admin creates hostel Owners,
Owners create the Manager and Warden, and the Warden registers Students. So the honest Play answer
is not "users can delete their account instantly", it is "any account holder can file a deletion
request in one tap, and it is fulfilled after their identity is confirmed" — which is what the
policy asks for.

**Why not a self-service hard delete.** `db/rls-policies.sql` gives no role a DELETE policy on
`students` or `users`; `students_delete` is service-role only, deliberately
([`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.3). If a resident could
delete their own row:

- `fee_payments` references `students(id)` **on delete cascade** — the hostel's fee ledger would go
  with them, and the hostel has a statutory duty to keep it (§5.2 of the retention doc).
- `beds.student_id` would be cleared while the bed is still physically occupied.
- A request in someone else's name would become a working denial-of-service against them.

---

## 2. The two surfaces

| | Where | File |
|---|---|---|
| In-app | Student → **More → My details**, below "Change password" | `app/student/profile/page.tsx` → `components/account/delete-account-card.tsx` |
| Public web URL | `https://hostelpro-three.vercel.app/legal/account-deletion` | `app/legal/account-deletion/page.tsx` |
| Server action | `requestAccountDeletion()` / `getMyDeletionRequest()` | `lib/actions/account.ts` |

The public page sits inside the shared legal shell (`app/legal/layout.tsx`) alongside the Privacy
Policy and Terms, and uses that shell's `DocHeader` / `Section` / `DataTable` / `Callout`
primitives so the three documents read as one set.

`/legal` is in `PUBLIC_PATHS` in `lib/supabase/middleware.ts`, so the page renders with no session;
nothing in it reads a cookie, a session or the database. It reads `headers()` to force dynamic
rendering — a statically prerendered page carries no CSP nonce and `strict-dynamic` would block
every script on it (the reason `app/not-found.tsx` does the same). The sibling legal pages opt into
`force-static` instead; this one is the URL Google actually loads, so it takes the per-request
nonce.

**Only the student profile carries the in-app control today.** The action itself accepts `student`,
`warden`, `manager` and `owner`, so the same card can be dropped into a staff profile screen when
one exists. The Super Admin is excluded: they have no hostel context and would use the email route.

### 2.1 Before the Play listing goes live

- [ ] Set the **grievance email** to a real, monitored mailbox. It appears in **two** files and
      both must be changed in the same commit: the `CONTACT` constant at the top of
      `app/legal/account-deletion/page.tsx`, and the `CONTACT` block in
      `app/legal/privacy/page.tsx` (which also carries the operator's legal name and postal
      address). Until they are set, each page shows an address on the reserved `.invalid`
      top-level domain **and renders a visible "before publishing this page" notice** — that is
      deliberate, so an unfinished contact cannot ship quietly. The notices remove themselves.
- [ ] Paste the public URL into Play Console → **Data safety → Account deletion URL**.
- [ ] Open the URL in a private window, signed out, and confirm it renders (see §6).
- [ ] Name the person who monitors that mailbox, and put the ops request log (§4.1) somewhere they
      can reach.

---

## 3. What the app does when a request is filed

`requestAccountDeletion()` in `lib/actions/account.ts`:

1. **Validates** (zod) that the user explicitly confirmed, plus an optional free-text reason
   (≤ 500 chars).
2. **Authorises** with `assertHostelContext(...)` — role, active account, forced-password-change and
   MFA gates all apply. It deliberately does **not** use `assertWritableContext()`: a data-subject
   request must not be refused because the tenant's subscription lapsed.
3. **Rate limits** to 3 per user per day, so a stuck button cannot flood inboxes.
4. **De-duplicates** against any request already on file in the last **30 days** and returns that
   one instead of filing a second.
5. **Notifies the people who can action it**, through the existing `notifications` table (inserted
   with the service role — `notifications_insert` is service-role only):

   | Requester | Notified | Link |
   |---|---|---|
   | student | the hostel's warden(s) **and** its owner | warden → `/warden/rooms`, owner → `/owner/students/<id>` |
   | warden / manager | the owner (who created the account) | `/owner/staff` |
   | owner | the Super Admin(s) | `/super-admin/hostels` |

   Wardens are matched on `users.hostel_id`, the owner on `hostels.owner_user_id` — the same rule
   `app.complaints_after_change()` uses, because an owner with several hostels may carry a
   different `hostel_id`. The requester is never notified about their own request.
6. **Records** it in `audit_log` as `account.deletion.requested`, with
   `meta = { requesterRole, studentId, notified, hasReason }`.
7. **Reads the audit row back** and fails honestly if it is not there. `audit()` swallows its own
   errors by design so it can never break the action it records — correct everywhere else, wrong
   here, because *the audit row is the request*. If it did not land, the user is told to speak to
   their warden or use the email route instead of being shown a false success.

**The free-text reason is not written to `audit_log`.** It goes only into the staff notification.
`audit_log` is kept 365 days and is readable by the owner and Super Admin; the reason is the
requester's own words and only the person actioning it needs them
([`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §8).

**There is no `deletion_requests` table.** The audit row is the record and the notification is the
work item. That was chosen over a new table because `db/schema.sql` is not editable from this work
and because the audit trail already has the right properties — append-only, service-role write,
owner-visible, retained a year. Its limitation is real and stated in §5: there is no *status*
field, so "requested" is recorded by the app and "completed" is recorded by you, in the ops log.

---

## 4. Fulfilling a request

### 4.1 Intake

Requests arrive in the warden's and owner's notification bell, and by email at the grievance
address for people who cannot sign in. List everything filed through the app, as the service role
in the SQL editor:

```sql
select at, actor_user_id, actor_role, target_id, hostel_id, meta
from public.audit_log
where action = 'account.deletion.requested'
order by at desc;
```

`meta->>'studentId'` is the `students.id` to work from when the requester was a resident.

Open a row in the **ops request log** (the same log §6 of the retention doc requires for any
data-subject request): who asked, how identity was verified, what was done, when, by whom. Keep it
outside the application — it must survive the deletion it describes.

### 4.2 Verify identity — before anything else

Do it **out of band**. For a resident the warden knows them by sight; otherwise call the phone
number already on the record. **Never accept ID documents by email**, and never verify using
details supplied in the request itself. An unverified erasure is a denial-of-service against the
person named in it.

### 4.3 Decide: erase or anonymise

| Situation | Do this |
|---|---|
| No financial record needs to survive | **Erase** — §4.4 |
| Any `fee_payments` row must be kept for the accounting period (the normal case for anyone who ever paid) | **Anonymise** — §4.5. Deleting the student cascades the fee ledger with it |
| The requester is **staff** (warden / manager / owner) | **Anonymise**, always. Their `users.id` is referenced without cascade by `created_by`, `recorded_by`, `decided_by`, `logged_by`, `uploaded_by`, `updated_by`, `actor_user_id`, `author_user_id` and `assigned_to` |

Confirm the applicable accounting period with the tenant's accountant and record it per tenant.
The default in [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §5.2 is **8
years**, and it is longer than any privacy-driven period.

### 4.4 Erase

The canonical procedure is
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.3. In short, and in this
order:

1. **Vacate through the app first.** Warden → the room → Vacate. This sets
   `students.status = 'vacated'`, deactivates the linked account and frees the bed through the
   `students_bed_guard` / `students_bed_sync` triggers. Doing it in SQL risks leaving `beds`
   inconsistent.
2. **Capture the storage keys before the rows go**, or the files become unreferenced and immortal:

   ```sql
   select s.id, s.user_id, s.photo_url, s.id_proof_url,
          (select array_agg(c.photo_url) from public.complaints c
            where c.student_id = s.id and c.photo_url is not null) as complaint_photos
   from public.students s where s.id = '<student-uuid>';
   ```

3. **Delete the objects** — `student-docs` (photo + ID proof) and `complaint-photos`. Dashboard →
   Storage, or `removeFromBucket()` in `lib/storage.ts`. Leave `receipts` alone: it holds expense
   receipts uploaded by staff, which are part of the accounts.
4. **Delete the student row**, in a transaction, checking counts before commit:

   ```sql
   begin;
   delete from public.students where id = '<student-uuid>';
   -- Cascades: fee_payments, complaints (-> complaint_events), leaves, visitors.
   -- Sets beds.student_id to null.
   commit;
   ```

5. **Delete the login** with the Auth Admin API — `auth.admin.deleteUser(userId)`. `public.users`
   cascades from `auth.users`, and `notifications` cascades from `public.users`. If a foreign key
   blocks it, **do not force it** — anonymise the `users` row instead (§4.5).
6. **Leave `audit_log` alone.** `actor_user_id` carries no foreign key to `users`, so the trail
   survives intact. It is held on a separate basis (security, and being able to investigate), it
   names a UUID once the account is gone, and its own 365-day clock disposes of it. Deleting audit
   rows to satisfy an erasure request destroys the evidence needed for the next breach
   notification — including one that affects the requester.

### 4.5 Anonymise

Keep the row, remove the person from it. Full SQL, including the `phone` uniqueness trap, is in
[`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §6.4 — use it rather than
retyping it here. The shape:

- `students`: `full_name` → `'Erased resident'`, `phone` → a unique `'erased-…'` marker (a constant
  collides with `students_phone_active_key`), and `email`, `photo_url`, `guardian_name`,
  `guardian_phone`, `permanent_address`, `id_proof_type`, `id_proof_url` → `null`.
- `users`: `full_name` → `'Erased user'`, `email` and `phone` → `null`. Then deactivate the account
  (`status = 'inactive'`) so the login cannot be used — `requireUser()` and the middleware both
  bounce an inactive session immediately.
- **Delete the storage objects separately** (§4.4 step 3). Nulling a URL does not remove the file.
- **Then sweep the free text**, which is where anonymisation quietly fails: `fee_payments.notes`,
  `complaints.description`, `complaints.resolution_note`, `leaves.reason`, `expenses.note`,
  `announcements.body`, `tasks.description`.

### 4.6 Close the loop

1. Tell the requester what was deleted, what was kept and on what basis. Keep it short and
   specific; §5 and §6 of the public page are the wording to reuse.
2. Write the outcome into the ops request log. **The app has no "completed" state** — nothing
   clears the audit row or the notification, so the ops log is the only place the closure exists.
   Mark the notification read so the next person does not action it twice.
3. If a database restore happens afterwards, **re-run the erasure**. A restore resurrects deleted
   rows; backups are point-in-time copies and are not selectively editable
   ([`backup-and-dr.md`](./backup-and-dr.md), 90-day artifact retention).

---

## 5. What this path does not do — read before promising anything

- **Nothing is deleted automatically.** Filing a request notifies people; a human does the rest.
  If nobody watches the notification bell and the grievance mailbox, the request dies there. That
  is the single biggest failure mode of this design.
- **No request status in the product.** There is no "pending / completed" field, no cancel button
  and no reminder. The audit row proves a request was made; closure lives in the ops log.
- **Vacated records are not purged on a schedule.** The 12-month post-`vacated_at` retention in
  [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) §5.2 still depends on somebody
  running the quarterly purge.
- **The erasure procedure has not been executed against production.** §6.3 of the retention doc is
  explicit about this. Dry-run it on a Supabase branch or a seeded copy and record the result there
  before the first real request.
- **Backups and vendor logs are out of reach.** Erased data leaves backups when they age out (up to
  90 days), and Supabase Auth / Vercel access logs age out on the vendors' own schedules.

---

## 6. Verifying the public URL

The page must return **200 to an anonymous request** — that is the whole Play requirement, and the
one thing worth re-checking after any middleware change:

```bash
# Local
npm run dev
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/legal/account-deletion    # expect 200

# Production, with no cookies at all
curl -s -o /dev/null -w '%{http_code}\n' https://hostelpro-three.vercel.app/legal/account-deletion
```

A `307` means the path stopped being public — check `PUBLIC_PATHS` in
`lib/supabase/middleware.ts` and the matcher in `middleware.ts`. Run a protected route through the
same anonymous client as a control (`/student/profile` must give `307 → /login`); a `200` on both
would mean middleware is not running at all, not that the exemption works.

## 6.1 Exercising the request itself

`scripts/_qa-action.mjs` invokes the server action over HTTP as a signed-in demo user. Action ids
come from `.next/server/server-reference-manifest.json` after the page has been visited once in
dev — see `scripts/README.md`.

```bash
# ids: warm /student/profile first, then read them out of the manifest
node -e "const m=require('./.next/server/server-reference-manifest.json');
for (const [id,v] of Object.entries(m.node||{}))
  if (JSON.stringify(v).includes('student/profile')) console.log(id)"

MSYS_NO_PATHCONV=1 node scripts/_qa-action.mjs 9000000001@student.hostelpro.local 'Student@12345' \
  /student/profile <requestAccountDeletion-id> '[{"confirm":true,"reason":"QA"}]'
```

**This writes to whatever database `.env.local` points at.** A successful run leaves one
`audit_log` row and one notification per recipient, and the demo student's profile then shows
"Request sent on …" for 30 days. Clean up as the service role:

```sql
-- Scope to the ONE account you tested with. The unscoped form of these statements
-- (where action = '...' with no user filter) would erase every deletion request in the
-- database, across every tenant, including real ones -- and audit_log is the evidence
-- trail those requests are proved by. Get the id first, then delete by it.
select id, at, actor_user_id, hostel_id
  from public.audit_log
 where action = 'account.deletion.requested'
 order by at desc limit 20;   -- find YOUR row, note its id

delete from public.audit_log     where id = <that id>;
delete from public.notifications where title = 'Account deletion requested'
   and hostel_id = '<the test hostel id>'
   and created_at > now() - interval '1 day';
```

`app/robots.ts` disallows crawling of the whole site, which is right for a private workspace.
`app/legal/layout.tsx` sets `robots: { index: true, follow: true }` on the legal pages, so the
page-level meta invites indexing while `robots.txt` still asks crawlers to stay away — resolve that
between the two if search visibility for the legal set is actually wanted. It does not affect Play
either way: a reviewer opens the URL directly, and the requirement is that the page is *reachable*,
not that it is indexed.
