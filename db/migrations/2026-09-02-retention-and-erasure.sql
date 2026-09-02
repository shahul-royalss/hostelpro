-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-09-02 · TIME-LIMITED DATA, AND A RESIDENT'S RIGHT TO BE FORGOTTEN
-- ─────────────────────────────────────────────────────────────────────────────
--
-- The owner asked for three things, in their own words:
--
--   (a) "that student complaints and notices data has to deleted after 2 months"
--   (b) "student data deletion request has to sent while he is leaving hostel and that
--        student data will be deleted after 1 month"
--   (c) "the fee history of student never has to be deleted"
--
-- (a) and (c) are a retention policy. (b) is not: it is a DEFERRED, CANCELLABLE ERASURE, and
-- the deferral is the whole point. A PG resident who leaves in March and comes back in April
-- is an ordinary week in this business, so the erasure has to be a standing request with a
-- date on it that a warden can withdraw — not an action that fires at the desk.
--
-- ═══ (c) CONSTRAINS (b), AND THE SCHEMA MAKES THAT SHARP ═══════════════════════════════════
--
--     fee_payments.student_id → students(id) ON DELETE CASCADE
--
-- So `delete from students` IS `delete from fee_payments`. There is no version of "delete the
-- student row" that keeps the money. A PG owner's rent ledger is the book they are assessed on;
-- a missing year is not a tidy database, it is an unexplainable gap in front of a tax officer.
--
-- THE DECISION: erasure ANONYMISES the students row and never deletes it. The row survives as
-- an id and a monthly_fee — a hook the ledger hangs on — with every identifying column emptied
-- and `erased_at` stamped so the tombstone is self-describing. fee_payments is not read, not
-- written and not referenced by any statement below.
--
-- The alternative (re-key fee_payments onto a synthetic "payer" id, then hard-delete the
-- student) buys nothing: the payer row would have to carry the same id and the same nullable
-- columns, and it would cost a migration of every fee row plus a second table for the next
-- person to get wrong. A money record with no name attached is already the thing we want.
--
-- ═══ FILES DO NOT DISAPPEAR WHEN A ROW DOES, AND SQL CANNOT DELETE THEM ════════════════════
--
-- Storage is where a "deletion" quietly fails. Three private buckets hold personal data —
-- student-docs (resident photo, ID proof), complaint-photos, receipts — and `*_url` columns
-- hold a KEY into them, `<hostelId>/<folder>/<uuid>.<ext>`, not a URL. Dropping the row that
-- held the key does not touch the object; it only makes the object unfindable by us and still
-- perfectly readable by anyone who can enumerate the bucket.
--
-- And this database CANNOT delete those objects. Supabase installs a guard for exactly this:
--
--     storage.protect_delete()  BEFORE DELETE ON storage.objects  (FOR EACH STATEMENT)
--     → "Direct deletion from storage tables is not allowed. Use the Storage API instead."
--       HINT: "This prevents accidental data loss from orphaned objects."
--
-- Deleting the metadata row leaves the bytes in the S3 backend forever. Supabase blocks it, and
-- it is right to. Which leaves one honest shape: the database records the OBLIGATION, and a
-- process holding the service role discharges it through the Storage API.
--
-- That is `app.storage_erasures` — the one new table in this migration, and the only thing here
-- that could not be a column. It has to be a table because its rows outlive the rows they came
-- from: the key must survive the complaint that referenced it, or there is nothing left to name
-- the file with. `app.apply_retention()` reports the pending depth as its last step, so a queue
-- nobody is draining shows up as a number that climbs every night instead of as silence.
--
-- ═══ WHAT "STUDENT DATA" MEANS HERE (§4, stated plainly) ═══════════════════════════════════
--
-- ERASED — everything that identifies a person or describes their private life:
--   students     full_name, phone, email, guardian_name, guardian_phone, permanent_address,
--                id_proof_type, id_proof_url, photo_url
--   storage      the resident's photo and ID-proof objects in student-docs, and the photos on
--                any complaint they raised, in complaint-photos  (queued — see above)
--   complaints   their complaints and the complaint_events timeline under them, free text and
--                all: "the food in room 3 made me ill" is health data about a named person
--   leaves       where they went and why
--   visitors     who came to see them
--   notifications everything ever addressed to them (cascades with the account)
--   auth.users   the login itself — address, phone, password hash, MFA factors, sessions.
--                Leaving GoTrue holding the email while calling the resident erased would be
--                the same lie as leaving the file in the bucket.
--   audit_log    actor_user_id on their own rows is nulled: keep the EVENT, drop the PERSON.
--                Same two-stage rule the audit retention below has always used.
--
-- KEPT — the hostel's own records, which are not the resident's to erase:
--   fee_payments   every row, untouched, forever  (c)
--   students       id, hostel_id, monthly_fee, date_of_joining, vacated_at, status — the shape
--                  of a tenancy with nobody's name on it
--   audit_log      the rows themselves, under the existing 90d/365d policy
--   beds / rooms   occupancy history carries no personal data
--
-- ═══ WHAT THIS MIGRATION DOES NOT DO ═══════════════════════════════════════════════════════
--
-- It does not drain app.storage_erasures. Draining needs the service role and the Storage HTTP
-- API; the only way to do that from inside Postgres is to keep a service-role key in the
-- database and fire it with pg_net, and a permanently readable service-role credential is a
-- worse privacy problem than the one it solves — it is a key to every bucket and every row,
-- sitting where any SECURITY DEFINER function can read it. The queue is the deliberate seam.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────────────
-- 1 · THE STORAGE ERASURE LEDGER
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists app.storage_erasures (
  id           bigint generated always as identity primary key,
  bucket       text        not null,
  object_path  text        not null,
  -- No FK. The hostel may itself be gone by the time this is drained, and an ON DELETE CASCADE
  -- here would delete the record of an obligation as a side effect of the obligation's subject
  -- disappearing — which is the exact failure this table exists to prevent.
  hostel_id    uuid,
  reason       text        not null,
  enqueued_at  timestamptz not null default now(),
  purged_at    timestamptz,
  attempts     int         not null default 0,
  last_error   text,
  unique (bucket, object_path)
);

create index if not exists storage_erasures_pending_idx
  on app.storage_erasures (enqueued_at) where purged_at is null;

comment on table app.storage_erasures is
  'Objects that must be destroyed through the Storage API. Postgres cannot delete them itself: '
  'storage.protect_delete() refuses direct DELETEs on storage.objects because they orphan the '
  'bytes in the S3 backend. Rows here outlive the rows whose keys they carry.';

-- app is not a PostgREST-exposed schema, but `authenticated` does hold USAGE on it, so be
-- explicit rather than relying on that.
revoke all on app.storage_erasures from public, anon, authenticated;

/**
 * Queue one object for destruction. Returns true when a NEW obligation was recorded.
 *
 * Refuses anything that is not a real storage key. `*_url` columns are writable by staff
 * through PostgREST, so their contents may be an absolute https:// URL or junk; queueing that
 * would be a purge request for an object that does not exist, and the drain would burn its
 * retries on it. Same shape lib/storage.ts and supabase/functions/_shared/storage.ts accept.
 */
create or replace function app.enqueue_storage_erasure(
  p_bucket text, p_path text, p_hostel uuid, p_reason text
) returns boolean
language plpgsql security definer set search_path = public as $fn$
begin
  if p_path is null
     or p_path !~ '^[0-9a-f-]{36}/[a-z-]{1,32}/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$' then
    return false;
  end if;
  insert into app.storage_erasures (bucket, object_path, hostel_id, reason)
  values (p_bucket, p_path, p_hostel, p_reason)
  on conflict (bucket, object_path) do nothing;
  return found;
end $fn$;

revoke all on function app.enqueue_storage_erasure(text, text, uuid, text)
  from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2 · THE ERASURE REQUEST — four columns, no new table
--
-- One column (erasure_requested_at) plus a hardcoded interval would have worked, and would
-- have put "+1 month" in the Flutter client, the web client and here, to drift apart on the
-- day somebody changes it. The DATE is the thing the resident is told and the thing the warden
-- cancels, so the date is stored.
--
--   erasure_requested_at  when the request was raised (at check-out, or by hand afterwards)
--   erasure_due_at        when the purge may run. Stored, not derived, so it can be extended
--                         or brought forward without a code change
--   erasure_requested_by  who raised it, for the audit trail
--   erased_at            when it actually ran. Non-null means this row is a tombstone
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.students
  add column if not exists erasure_requested_at timestamptz,
  add column if not exists erasure_due_at       timestamptz,
  add column if not exists erasure_requested_by uuid references public.users(id) on delete set null,
  add column if not exists erased_at            timestamptz;

alter table public.students drop constraint if exists students_erasure_pair;
alter table public.students add constraint students_erasure_pair
  check ((erasure_requested_at is null) = (erasure_due_at is null));

create index if not exists students_erasure_due_idx
  on public.students (erasure_due_at)
  where erasure_due_at is not null and erased_at is null;

comment on column public.students.erasure_due_at is
  'When the deferred erasure may run. Visible to the hostel (warden/owner) and to the resident '
  'themselves through students_select. Cancel with public.wd_cancel_student_erasure().';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3 · COMING BACK IS A CANCELLATION
--
-- The scenario this whole design is built around: a resident checks out in March and is back
-- in a bed in April. Re-admitting them moves students.status off 'vacated' — and if the
-- pending request survived that, the retention job would erase a person who is asleep in the
-- building. So reactivation withdraws the request, without anybody having to remember.
--
-- The reverse is closed too: an erased row is a tombstone the ledger hangs on, not a resident
-- record with the name rubbed off. It cannot be brought back into service.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.students_erasure_guard() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if old.erased_at is not null and new.status <> 'vacated' then
    raise exception 'This record was erased at the resident''s request. Register them as a new resident instead.'
      using errcode = 'P0001';
  end if;

  if old.status = 'vacated' and new.status <> 'vacated'
     and new.erasure_requested_at is not null and new.erased_at is null then
    new.erasure_requested_at := null;
    new.erasure_due_at       := null;
    new.erasure_requested_by := null;
  end if;

  return new;
end $fn$;

drop trigger if exists students_erasure_guard on public.students;
create trigger students_erasure_guard before update on public.students
  for each row execute function app.students_erasure_guard();

revoke all on function app.students_erasure_guard() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4 · UNLINKING AN ACCOUNT IS NOT RE-LINKING ONE
--
-- app.students_identity_guard refused every change to students.user_id, because repointing a
-- student record at another account is an account-takeover primitive. Setting it to NULL is
-- not that — it is the record forgetting a login, which is what erasing the login requires.
--
-- Paired with ON DELETE SET NULL below: deleting auth.users cascades to public.users, which
-- now releases students.user_id instead of blocking the delete. Without both halves, the login
-- cannot be erased at all, and the "erasure" would leave GoTrue holding the email address.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.students_identity_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_role public.user_role; v_hostel uuid;
begin
  if app.is_super_admin() then return new; end if;
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id then
      raise exception 'Not allowed.' using errcode = '42501';
    end if;
    -- NULL is a release, anything else is a takeover. Only the first is allowed.
    if new.user_id is distinct from old.user_id and new.user_id is not null then
      raise exception 'A student record cannot be re-linked to another account.' using errcode = '42501';
    end if;
    if new.hostel_id is distinct from old.hostel_id then
      raise exception 'You cannot move a student to another hostel.' using errcode = '42501';
    end if;
  end if;
  if new.user_id is not null then
    select role, hostel_id into v_role, v_hostel from public.users where id = new.user_id;
    if v_role is null then
      raise exception 'Linked account not found.' using errcode = 'P0001';
    end if;
    if v_role <> 'student' or v_hostel is distinct from new.hostel_id then
      raise exception 'A student record can only be linked to a student account in the same hostel.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

alter table public.students drop constraint if exists students_user_id_fkey;
alter table public.students add constraint students_user_id_fkey
  foreign key (user_id) references public.users(id) on delete set null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5 · THE ERASURE ITSELF
--
-- Idempotent (erased_at short-circuits it) and safe to call twice on the same night.
-- NOTHING BELOW READS OR WRITES public.fee_payments. Do not add it. See the header.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.erase_student(p_student_id uuid) returns boolean
language plpgsql security definer set search_path = public as $fn$
declare
  s        public.students%rowtype;
  v_user   uuid;
  v_note   text := null;
begin
  select * into s from public.students where id = p_student_id for update;
  if not found or s.erased_at is not null then
    return false;
  end if;
  -- Only a departed resident is erasable. app.students_erasure_guard withdraws the request the
  -- moment somebody is re-admitted, so reaching here with an active resident means an
  -- assumption broke; refuse rather than empty a living record.
  if s.status <> 'vacated' then
    return false;
  end if;

  v_user := s.user_id;

  -- ── FILES FIRST, WHILE THE KEYS ARE STILL READABLE ──────────────────────────────────────
  perform app.enqueue_storage_erasure('student-docs', s.photo_url,    s.hostel_id, 'erasure.student_photo');
  perform app.enqueue_storage_erasure('student-docs', s.id_proof_url, s.hostel_id, 'erasure.student_id_proof');
  perform app.enqueue_storage_erasure('complaint-photos', c.photo_url, c.hostel_id, 'erasure.complaint_photo')
    from public.complaints c
   where c.student_id = p_student_id and c.photo_url is not null;

  -- ── THEIR PRIVATE LIFE IN THIS BUILDING ─────────────────────────────────────────────────
  delete from public.complaints where student_id = p_student_id;   -- complaint_events cascade
  delete from public.leaves     where student_id = p_student_id;
  delete from public.visitors   where student_id = p_student_id;

  -- ── THE ROW: EMPTIED, NOT DELETED. THE LEDGER HANGS ON THIS ID ──────────────────────────
  -- phone is NOT NULL and unique among non-vacated residents; keying the placeholder on the
  -- row's own id keeps it unique whatever else happens.
  update public.students set
      full_name         = 'Erased resident',
      phone             = 'erased-' || replace(p_student_id::text, '-', ''),
      email             = null,
      photo_url         = null,
      guardian_name     = null,
      guardian_phone    = null,
      permanent_address = null,
      id_proof_type     = null,
      id_proof_url      = null,
      erased_at         = now()
    where id = p_student_id;

  -- ── THE LOGIN ───────────────────────────────────────────────────────────────────────────
  if v_user is not null then
    -- Release the NO ACTION references a resident account can legitimately hold, so the delete
    -- below is not refused by a row that carries no personal data anyway.
    update public.complaint_events set actor_user_id = null where actor_user_id = v_user;
    if to_regclass('public.payment_intents') is not null then
      execute 'update public.payment_intents set created_by = null where created_by = $1' using v_user;
    end if;

    begin
      -- Cascades: public.users → notifications, and students.user_id is released by the FK
      -- changed in §4. GoTrue's own identities / sessions / refresh_tokens / mfa_factors all
      -- cascade off auth.users, which is why this one statement is the whole account.
      delete from auth.users where id = v_user;
    exception when foreign_key_violation then
      -- Do not fail the night's run, and do not start nulling columns blind. app.users_update_guard
      -- refuses every UPDATE to public.users from a context with no JWT, so this job cannot
      -- anonymise the account either — the only honest move is to say so, loudly, where a human
      -- looks. The resident's own data above is already gone.
      v_note := 'account retained: still referenced by another record';
      perform app.raise_security_alert(
        'medium', 'privacy.erasure.account_retained',
        'A resident was erased but their login could not be deleted — it is still referenced elsewhere.',
        s.hostel_id, null::uuid, null::text, jsonb_build_object('student_id', p_student_id, 'user_id', v_user));
    end;
  end if;

  -- ── THE TRAIL: KEEP THE EVENT, DROP THE PERSON ──────────────────────────────────────────
  -- Same two-stage rule the audit retention below has always used. audit_log has no FK to
  -- users, so the uuid would otherwise outlive the account it names.
  if v_user is not null then
    update public.audit_log set actor_user_id = null where actor_user_id = v_user;
  end if;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (null, null, 'student.erased', 'student', p_student_id::text, s.hostel_id,
          jsonb_build_object(
            'requested_at', s.erasure_requested_at,
            'due_at',       s.erasure_due_at,
            'requested_by', s.erasure_requested_by,
            'note',         v_note));

  return true;
end $fn$;

revoke all on function app.erase_student(uuid) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6 · RETENTION — EXTENDED, NOT REPLACED
--
-- Every step that was here before is here still, in the same order, returning the same
-- (step, rows_affected) pair, so the job stays auditable and the diff is additive.
--
-- ╔═══════════════════════════════════════════════════════════════════════════════════════╗
-- ║  public.fee_payments IS NOT IN THIS FUNCTION AND MUST NEVER BE.                        ║
-- ║  "the fee history of student never has to be deleted" — the owner, 2026-09.            ║
-- ║  It is the book the PG is assessed on. A row missing from it is not tidiness, it is an ║
-- ║  unexplainable gap in front of a tax officer. If a future policy seems to require      ║
-- ║  touching it, that policy is wrong; anonymise the STUDENT (app.erase_student) instead  ║
-- ║  — the ledger keeps its id and loses its name, which is what erasure actually asks for.║
-- ╚═══════════════════════════════════════════════════════════════════════════════════════╝
--
-- COMPLAINTS AGE FROM created_at, RESOLVED OR NOT. Ageing from resolved_at would let a hostel
-- defeat the policy by never pressing "Resolved" — the rows a resident would most want gone
-- are exactly the ones nobody closed. Two months is the owner's number, and a food complaint
-- from two months ago is not being actioned out of the archive.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function app.apply_retention()
returns table (step text, rows_affected bigint)
language plpgsql security definer set search_path = public as $fn$
declare n bigint; v_student uuid;
begin
  update public.audit_log set ip = null, user_agent = null
   where at < now() - interval '90 days' and (ip is not null or user_agent is not null);
  get diagnostics n = row_count;
  step := 'audit_log pseudonymised (>90d)'; rows_affected := n; return next;

  delete from public.audit_log where at < now() - interval '365 days';
  get diagnostics n = row_count;
  step := 'audit_log deleted (>365d)'; rows_affected := n; return next;

  delete from public.security_alerts
   where acknowledged_at is not null and at < now() - interval '365 days';
  get diagnostics n = row_count;
  step := 'security_alerts deleted (ack + >365d)'; rows_affected := n; return next;

  delete from app.rate_limits where window_start < now() - interval '1 day';
  get diagnostics n = row_count;
  step := 'rate_limits swept (>1d)'; rows_affected := n; return next;

  delete from public.notifications
   where read_at is not null and created_at < now() - interval '90 days';
  get diagnostics n = row_count;
  step := 'notifications deleted (read + >90d)'; rows_affected := n; return next;

  -- ── (a) COMPLAINTS AND NOTICES, 2 MONTHS ────────────────────────────────────────────────
  -- Photos are queued BEFORE their complaints go, or the key is unrecoverable.
  select count(*) into n from (
    select app.enqueue_storage_erasure('complaint-photos', c.photo_url, c.hostel_id,
                                       'retention.complaint_photo') as queued
      from public.complaints c
     where c.created_at < now() - interval '2 months' and c.photo_url is not null
  ) q where q.queued;
  step := 'complaint photos queued for erasure (>2mo)'; rows_affected := n; return next;

  -- Explicit, though complaint_events would cascade, so the count is reportable rather than
  -- invisible inside somebody else's DELETE.
  delete from public.complaint_events e
   using public.complaints c
   where e.complaint_id = c.id and c.created_at < now() - interval '2 months';
  get diagnostics n = row_count;
  step := 'complaint_events deleted (>2mo)'; rows_affected := n; return next;

  delete from public.complaints where created_at < now() - interval '2 months';
  get diagnostics n = row_count;
  step := 'complaints deleted (>2mo)'; rows_affected := n; return next;

  -- "notices" is what the owner calls announcements. Soft-deleted ones go too: deleted_at was
  -- a retraction from the feed, not an erasure.
  delete from public.announcements where created_at < now() - interval '2 months';
  get diagnostics n = row_count;
  step := 'announcements deleted (>2mo)'; rows_affected := n; return next;

  -- ── (b) DEFERRED ERASURES THAT HAVE COME DUE ────────────────────────────────────────────
  n := 0;
  for v_student in
    select id from public.students
     where erasure_due_at is not null and erasure_due_at <= now()
       and erased_at is null and status = 'vacated'
     order by erasure_due_at
     limit 500
  loop
    if app.erase_student(v_student) then n := n + 1; end if;
  end loop;
  step := 'residents erased (requested + 1mo)'; rows_affected := n; return next;

  -- ── THE GAUGE ───────────────────────────────────────────────────────────────────────────
  -- Not a delete. Postgres cannot destroy a storage object (see the header); this is the depth
  -- of the queue that a service-role drain has to work through. A number that climbs every
  -- night is the alarm that nothing is draining it.
  select count(*) into n from app.storage_erasures where purged_at is null;
  step := 'storage objects awaiting purge (queue depth)'; rows_affected := n; return next;
end $fn$;

revoke all on function app.apply_retention() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7 · THE RPCs
-- ─────────────────────────────────────────────────────────────────────────────

-- Warden: check a resident out. Frees the bed, deactivates the login, AND raises the erasure
-- request. Signature unchanged, so every existing caller keeps working.
create or replace function public.wd_vacate_student(p_student_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_user uuid; v_erased timestamptz; v_actor uuid := auth.uid();
begin
  select hostel_id, user_id, erased_at into v_hostel, v_user, v_erased
    from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;

  -- One UPDATE, so app.students_bed_guard fires once and the check-out and the request cannot
  -- come apart if the connection drops. coalesce() keeps a second check-out from resetting a
  -- clock that is already running.
  update public.students
     set status               = 'vacated',
         erasure_requested_at = case when v_erased is null
                                     then coalesce(erasure_requested_at, now())
                                     else erasure_requested_at end,
         erasure_due_at       = case when v_erased is null
                                     then coalesce(erasure_due_at, now() + interval '1 month')
                                     else erasure_due_at end,
         erasure_requested_by = case when v_erased is null
                                     then coalesce(erasure_requested_by, v_actor)
                                     else erasure_requested_by end
   where id = p_student_id;

  if v_user is not null then
    update public.users set status = 'inactive' where id = v_user;
  end if;
end $$;

/**
 * Withdraw a pending erasure. The returning-resident path.
 *
 * NOT gated on app.hostel_writable(). Every other write in this schema stops when a
 * subscription lapses, and that is right for writes that create obligations — but this one
 * REMOVES one. A hostel that cannot pay its bill must still be able to stop a resident's
 * record being destroyed; the alternative is data loss as a billing consequence.
 */
create or replace function public.wd_cancel_student_erasure(p_student_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_requested timestamptz; v_erased timestamptz;
begin
  select hostel_id, erasure_requested_at, erased_at
    into v_hostel, v_requested, v_erased
    from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if v_erased is not null then
    raise exception 'This record has already been erased. It cannot be restored.' using errcode = 'P0001';
  end if;
  if v_requested is null then
    raise exception 'No deletion is scheduled for this resident.' using errcode = 'P0001';
  end if;

  update public.students
     set erasure_requested_at = null, erasure_due_at = null, erasure_requested_by = null
   where id = p_student_id;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), app.user_role(), 'student.erasure_cancelled', 'student',
          p_student_id::text, v_hostel, jsonb_build_object('was_requested_at', v_requested));
end $$;

/**
 * Raise the request by hand, for a resident who left before this shipped — or one whose
 * request was cancelled and who has now really gone. Same one-month deferral as check-out.
 */
create or replace function public.wd_request_student_erasure(p_student_id uuid) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare v_hostel uuid; v_status public.student_status; v_erased timestamptz; v_due timestamptz;
begin
  select hostel_id, status, erased_at into v_hostel, v_status, v_erased
    from public.students where id = p_student_id;
  if v_hostel is null then raise exception 'Student not found.' using errcode = 'P0001'; end if;
  if not app.has_role_in(v_hostel, 'warden', 'owner') then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  if not app.hostel_writable(v_hostel) then
    raise exception 'Subscription expired — hostel is read-only.' using errcode = '42501';
  end if;
  if v_erased is not null then
    raise exception 'This record has already been erased.' using errcode = 'P0001';
  end if;
  if v_status <> 'vacated' then
    raise exception 'Check this resident out first — a deletion cannot be scheduled for someone still in a bed.'
      using errcode = 'P0001';
  end if;

  update public.students
     set erasure_requested_at = coalesce(erasure_requested_at, now()),
         erasure_due_at       = coalesce(erasure_due_at, now() + interval '1 month'),
         erasure_requested_by = coalesce(erasure_requested_by, auth.uid())
   where id = p_student_id
  returning erasure_due_at into v_due;

  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  values (auth.uid(), app.user_role(), 'student.erasure_requested', 'student',
          p_student_id::text, v_hostel, jsonb_build_object('due_at', v_due));

  return v_due;
end $$;

revoke execute on function public.wd_cancel_student_erasure(uuid)  from public, anon;
revoke execute on function public.wd_request_student_erasure(uuid) from public, anon;
grant  execute on function public.wd_cancel_student_erasure(uuid)  to authenticated, service_role;
grant  execute on function public.wd_request_student_erasure(uuid) to authenticated, service_role;
