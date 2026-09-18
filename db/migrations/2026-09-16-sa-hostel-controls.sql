-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- THE SUPER ADMIN CAN SUSPEND, CANCEL AND RENAME A HOSTEL FROM THE PHONE
--
-- Until now the console could create a hostel and renew its plan, and nothing else. Suspending
-- lived only in the web app, as a bare `update hostels set status = ...` through RLS: no audit
-- row the database wrote itself, no word to the owner, and no way to do it from Android at all.
-- Cancelling a plan did not exist in any form — the only way to stop a hostel writing was to
-- suspend it, which says "something is wrong with this account" when what happened is "the plan
-- ended early". Renaming meant a SQL console.
--
-- Three RPCs, each SECURITY DEFINER, each refusing everyone but the Super Admin with 42501, each
-- auditing and telling the owner:
--
--   public.sa_set_hostel_status(hostel, 'suspended' | 'active')  -> the resulting hostels.status
--   public.sa_cancel_subscription(hostel, reason)                -> how many periods were cancelled
--   public.sa_rename_hostel(hostel, name)                         -> the stored name
--
-- ── WHY A CANCELLED PLAN IS STAMPED AND NOT DELETED ─────────────────────────────────────────
--
-- A subscription row is a billing record: somebody agreed a period and an amount. Deleting it on
-- cancellation would erase the history the Super Admin reads to answer "what did this owner pay
-- for, and when did it stop". So the row stays, gains cancelled_at / cancelled_by /
-- cancel_reason, and EVERY place that derives "the hostel's current plan" from its periods is
-- taught to look past it. That last clause is the whole risk of this file: one reader left
-- behind and a cancelled hostel keeps writing, or a renewal starts its new period at the end of
-- the plan that was just cancelled. The readers, found by
--   select oid::regprocedure from pg_proc where prosrc ilike '%subscriptions%'
-- on the live database (2026-09-16) and by grep across db/, supabase/ and lib/queries, are:
--
--   app.subscription_state            the authority; hostel_writable() and every RLS write
--                                     policy read it, so this one change is what makes a
--                                     cancelled hostel read-only immediately
--   app.subscription_days_left        the countdown on both dashboards
--   app.subscription_status_compute   the per-row status column, so a cancelled row reads
--                                     'expired' in every history list instead of 'active'
--   public.refresh_subscription_statuses   its "latest period" pick and its status recompute
--   public.sa_renew_subscription      its v_prev_end, so a renewal after a cancellation starts today
--   public.rpc_sa_hostels             its latest-period lateral join
--   public.rpc_sa_dashboard           the Super Admin stats, including the month's revenue
--
-- Reached through those and therefore NOT redefined here: app.hostel_writable,
-- app.can_write_hostel, app.subscription_after_change, public.rpc_hostel_stats.
-- public.sa_create_hostel_with_subscription only inserts.
--
-- Readers outside the database that this file cannot change:
--   supabase/functions/_shared/tenant.ts   loadHostel() takes the newest end_date without looking
--       at cancelled_at and lets hostels.status = 'active' carry the rest. Before cancellation a
--       stale 'active' on a lapsed hostel still failed its date check; a cancelled period usually
--       ends in the future and passes it. The web console's setHostelStatus writes 'active'
--       straight through hostels_update and only then calls refresh_subscription_statuses, whose
--       error it never reads. So in that window, or for good if the refresh fails, tenant.ts would
--       let owner-create-staff, warden-register-student, warden-student-credentials and
--       complaint-photo write to a hostel RLS already refuses. Section 3 closes that at the table:
--       app.hostels_status_guard stores 'readonly' for any move into 'active' the plan does not
--       cover, so tenant.ts never sees a cancelled hostel as 'active'. tenant.ts should still
--       filter `.is("cancelled_at", null)`, and that belongs to whoever owns the file.
--   lib/queries/super-admin.ts with components/super-admin/subscription-timeline.tsx, and the
--       Flutter SaRepository, read the raw history. Showing cancelled rows is right for a history,
--       but they must be labelled 'Cancelled' and never picked as 'Current'.
--
-- Also here, for supabase/functions/sa-owner-account (section 6): the owner's login address,
-- pending tokens and sessions move in ONE transaction, so a Super Admin taking a login back
-- cannot leave an address change or recovery link redeemable, or sessions alive.
--
-- Each redefinition below is copied from pg_get_functiondef() on the live database, not from
-- db/schema.sql: rpc_sa_hostels there is still the zero-argument version, and rpc_sa_dashboard
-- there still compares months in UTC rather than with app.today().
--
-- ── AUTHORIZATION, AND THE NULL THAT WOULD HAVE FAILED OPEN ─────────────────────────────────
--
-- Modelled on public.sa_set_hostel_payout_account (2026-09-06, locked down 2026-09-07):
-- app.is_super_admin() carries the second factor through app.mfa_satisfied(), so an aal1
-- session of a super admin who has enrolled a factor is refused here exactly as it is in RLS
-- and in _shared/caller.ts. Two deliberate differences from that function:
--   · the refusal is 42501, not P0001. The app maps 42501 to its generic "no access" and shows
--     P0001 text verbatim; a refusal of WHO you are is the first kind, a refusal of WHAT you
--     typed is the second.
--   · the check is `not coalesce(app.is_super_admin(), false)`. app.is_service_role() is
--     `coalesce(...)` today and app.mfa_satisfied() never returns NULL today, but `false or
--     NULL` is NULL and `if not NULL` does not raise. A guard whose correctness depends on two
--     other functions never changing shape is the guard refresh_subscription_statuses already
--     had to be rewritten for.
--
-- The grants revoke from anon BY NAME. Supabase grants EXECUTE on new public functions to anon
-- explicitly, and a revoke from PUBLIC does not reach it — 2026-09-07-lock-payout-rpc.sql is
-- the record of that lesson.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══ 1. THE CANCELLATION COLUMNS ═══════════════════════════════════════════════════════════

alter table public.subscriptions
  add column if not exists cancelled_at  timestamptz,
  add column if not exists cancelled_by  uuid references public.users(id),
  add column if not exists cancel_reason text;

-- A cancellation is all three facts or none of them. cancelled_by may be NULL on its own: a
-- service-role repair has no person behind it, and inventing one would be worse than saying so.
alter table public.subscriptions drop constraint if exists subscriptions_cancellation_shape;
alter table public.subscriptions
  add constraint subscriptions_cancellation_shape
  check (
    (cancelled_at is null and cancelled_by is null and cancel_reason is null)
    or (cancelled_at is not null and cancel_reason is not null
        and char_length(cancel_reason) between 3 and 300)
  );

comment on column public.subscriptions.cancelled_at is
  'When the Super Admin cancelled this period (public.sa_cancel_subscription). A cancelled row is '
  'history only: app.subscription_state and every other reader of the current plan ignore it. '
  'See db/migrations/2026-09-16-sa-hostel-controls.sql.';
comment on column public.subscriptions.cancelled_by is
  'The Super Admin who cancelled this period. NULL on an uncancelled row, or on a service-role repair.';
comment on column public.subscriptions.cancel_reason is
  'Why the period was cancelled, 3-300 characters. The owner can read it (subscriptions_select) '
  'and is sent it in the cancellation notice, so it is written for them, not as an internal note.';

-- A cancellation cannot be quietly undone. subscriptions_write lets the Super Admin update any
-- column through PostgREST, so without this a plan could be reinstated with one PATCH and no
-- audit row, and the notice the owner already received would be a lie nobody corrected. The way
-- back from a cancellation is sa_renew_subscription, which writes a new period and tells the
-- owner. Only the three cancellation columns are frozen: refresh_subscription_statuses still
-- rewrites `status` on these rows, and the service role can still repair a genuine mistake.
create or replace function app.subscriptions_cancellation_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.cancelled_at is not null
     and (new.cancelled_at  is distinct from old.cancelled_at
       or new.cancelled_by  is distinct from old.cancelled_by
       or new.cancel_reason is distinct from old.cancel_reason)
     and not app.is_service_role() then
    raise exception 'A cancelled plan stays cancelled. Renew the hostel to start a new plan.'
      using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists subscriptions_cancellation_guard on public.subscriptions;
create trigger subscriptions_cancellation_guard before update on public.subscriptions
  for each row execute function app.subscriptions_cancellation_guard();


-- ═══ 2. EVERY READER OF THE CURRENT PLAN LOOKS PAST A CANCELLED ROW ═════════════════════════

-- The authority. hostel_writable() -> every tenant write policy reads this, so a cancelled
-- period stops counting the moment it is stamped. No new index: a hostel has a handful of
-- periods and subscriptions_hostel_end_desc_idx already narrows to them.
create or replace function app.subscription_state(p_hostel_id uuid)
returns public.subscription_status
language sql stable security definer set search_path = public as $$
  select case
    when max(end_date) is null then 'expired'::public.subscription_status
    when max(end_date) < current_date then 'expired'::public.subscription_status
    when max(end_date) - current_date <= 15 then 'expiring'::public.subscription_status
    else 'active'::public.subscription_status end
  from public.subscriptions
  where hostel_id = p_hostel_id
    and cancelled_at is null
$$;

create or replace function app.subscription_days_left(p_hostel_id uuid)
returns integer
language sql stable security definer set search_path = public as $$
  select (max(end_date) - current_date)::int
  from public.subscriptions
  where hostel_id = p_hostel_id
    and cancelled_at is null
$$;

-- The stored per-row status. Without the first arm a cancelled period that still had months to
-- run would sit in the history list as 'active', beside a hostel the same screen calls expired.
create or replace function app.subscription_status_compute() returns trigger
language plpgsql set search_path = public as $$
begin
  new.status := case
    when new.cancelled_at is not null then 'expired'
    when new.end_date < current_date then 'expired'
    when new.end_date - current_date <= 15 then 'expiring'
    else 'active' end;
  return new;
end $$;

-- Live body, three changes: the expiry notice never goes out for a cancelled period (outer
-- predicate) and never picks one as "the latest" (inner), and the status recompute agrees with
-- subscription_status_compute above.
create or replace function public.refresh_subscription_statuses()
returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  -- The coalesce is load-bearing: app.user_role() is NULL for a caller with no active,
  -- non-deleted users row, and `false or NULL` = NULL, which would slip past `if not (...)`
  -- and fail OPEN. Fail closed, as app.mfa_satisfied() does with a missing aal claim.
  if not coalesce(
    app.is_service_role()
    or app.user_role() = any (array['super_admin', 'owner']::public.user_role[]),
    false
  ) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;

  for r in
    select s.id, s.hostel_id, s.owner_user_id, h.name, s.end_date
    from public.subscriptions s join public.hostels h on h.id = s.hostel_id
    where s.status in ('active', 'expiring')
      and s.cancelled_at is null
      and s.end_date >= current_date and s.end_date - current_date <= 15
      and s.owner_user_id is not null
      and s.id = (select x.id from public.subscriptions x
                   where x.hostel_id = s.hostel_id and x.cancelled_at is null
                   order by x.end_date desc limit 1)
      and not exists (
        select 1 from public.notifications n
         where n.user_id = s.owner_user_id
           and n.hostel_id = s.hostel_id
           and n.type = 'subscription'
           and n.created_at > now() - interval '7 days'
      )
  loop
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (r.hostel_id, r.owner_user_id, 'subscription', 'Subscription expiring soon',
            format('%s subscription ends on %s. Contact support to renew.', r.name, to_char(r.end_date, 'DD Mon YYYY')), '/owner');
  end loop;

  update public.subscriptions
     set status = case when cancelled_at is not null then 'expired' when end_date < current_date then 'expired' when end_date - current_date <= 15 then 'expiring' else 'active' end::public.subscription_status
   where status is distinct from (case when cancelled_at is not null then 'expired' when end_date < current_date then 'expired' when end_date - current_date <= 15 then 'expiring' else 'active' end::public.subscription_status);
  update public.hostels h set status = 'readonly' where h.status = 'active' and app.subscription_state(h.id) = 'expired';
  update public.hostels h set status = 'active'   where h.status = 'readonly' and app.subscription_state(h.id) <> 'expired';
end $$;

comment on function public.refresh_subscription_statuses() is
  'Recomputes stored subscription/hostel status and sends owner expiry notices (DECISIONS #14). Cancelled periods count as expired and never receive a notice. Callable by super_admin, owner and service_role only — the owner and super-admin dashboards invoke it as themselves.';

-- Live body, two changes. v_prev_end ignores cancelled periods: without that, renewing a hostel
-- whose plan was cancelled with eight months left would start the "new" period eight months from
-- now and refuse any end date before it. And the hostel row is locked, so a cancellation and a
-- renewal of the same hostel cannot interleave between reading v_prev_end and inserting.
create or replace function public.sa_renew_subscription(
  p_hostel_id uuid, p_new_end_date date, p_amount numeric, p_notes text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_owner uuid; v_prev_end date;
begin
  if not app.is_super_admin() then raise exception 'Only the Super Admin can renew subscriptions.' using errcode = '42501'; end if;
  select owner_user_id into v_owner from public.hostels where id = p_hostel_id for update;
  select max(end_date) into v_prev_end from public.subscriptions where hostel_id = p_hostel_id and cancelled_at is null;
  if p_new_end_date <= coalesce(v_prev_end, current_date - 1) then
    raise exception 'New end date must be after the current end date (%).', v_prev_end using errcode = 'P0001';
  end if;
  insert into public.subscriptions (hostel_id, owner_user_id, start_date, end_date, amount, created_by, notes)
  values (p_hostel_id, v_owner, greatest(coalesce(v_prev_end, current_date), current_date), p_new_end_date, p_amount, auth.uid(), p_notes) returning id into v_id;
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (p_hostel_id, v_owner, 'subscription', 'Subscription renewed', 'Your subscription now runs until ' || to_char(p_new_end_date, 'DD Mon YYYY') || '.', '/owner');
  return v_id;
end $$;

-- Live body (the 2026-08-31 pushdown version), one change: the lateral picks the newest period
-- that was not cancelled, so sub_start / sub_end / sub_amount describe the same plan sub_state
-- and days_left describe. A hostel whose only current plan was cancelled shows no plan dates.
create or replace function public.rpc_sa_hostels(
  p_hostel_id     uuid                       default null,
  p_search        text                       default null,
  p_sub_state     public.subscription_status default null,
  p_hostel_status public.hostel_status       default null,
  p_limit         integer                    default null,
  p_offset        integer                    default null
)
returns table (
  hostel_id uuid, hostel_name text, hostel_status public.hostel_status, address text,
  owner_id uuid, owner_name text, owner_email text, owner_phone text,
  sub_start date, sub_end date, sub_amount numeric, sub_state public.subscription_status, days_left int,
  total_beds int, occupied_beds int, active_students int, open_complaints int, created_at timestamptz
)
language sql stable security definer set search_path = public as $$
  with pat as (
    select case
             when nullif(btrim(p_search), '') is null then null
             else '%' || replace(replace(replace(btrim(p_search), '\', '\\'), '%', '\%'), '_', '\_') || '%'
           end as like_pattern
  )
  select h.id, h.name, h.status, h.address,
         u.id, u.full_name, u.email, u.phone,
         ls.start_date, ls.end_date, ls.amount, app.subscription_state(h.id), app.subscription_days_left(h.id),
         (select count(*)::int from public.beds b where b.hostel_id = h.id),
         (select count(*)::int from public.beds b where b.hostel_id = h.id and b.student_id is not null),
         (select count(*)::int from public.students s where s.hostel_id = h.id and s.status <> 'vacated'),
         (select count(*)::int from public.complaints c where c.hostel_id = h.id and c.status <> 'resolved'),
         h.created_at
  from public.hostels h
  join public.users u on u.id = h.owner_user_id
  left join lateral (
    select * from public.subscriptions s
     where s.hostel_id = h.id and s.cancelled_at is null
     order by s.end_date desc limit 1
  ) ls on true
  cross join pat
  where app.is_super_admin()
    and (p_hostel_id is null or h.id = p_hostel_id)
    and (p_hostel_status is null or h.status = p_hostel_status)
    and (pat.like_pattern is null
         or h.name      ilike pat.like_pattern
         or u.full_name ilike pat.like_pattern
         or u.email     ilike pat.like_pattern
         or h.address   ilike pat.like_pattern)
    and (p_sub_state is null or app.subscription_state(h.id) = p_sub_state)
  order by h.created_at desc, h.id desc
  limit p_limit offset coalesce(p_offset, 0)
$$;

-- Live body, one change. The three plan counts already go through subscription_state. The
-- month's revenue now leaves out cancelled periods: a plan recorded and cancelled in the same
-- month is not revenue the platform can point to, and counting it would make the headline
-- figure disagree with every per-hostel screen that no longer shows that plan.
create or replace function public.rpc_sa_dashboard()
returns table (
  total_hostels int, total_owners int, total_students int,
  active_subs int, expiring_subs int, expired_subs int,
  monthly_subscription_revenue numeric
)
language sql stable security definer set search_path = public as $$
  select (select count(*)::int from public.hostels),
    (select count(*)::int from public.users where role = 'owner' and deleted_at is null),
    (select count(*)::int from public.students where status <> 'vacated'),
    (select count(*)::int from public.hostels h where app.subscription_state(h.id) = 'active'),
    (select count(*)::int from public.hostels h where app.subscription_state(h.id) = 'expiring'),
    (select count(*)::int from public.hostels h where app.subscription_state(h.id) = 'expired'),
    coalesce((select sum(amount) from public.subscriptions
               where to_char(created_at, 'YYYY-MM') = to_char(app.today(), 'YYYY-MM')
                 and cancelled_at is null), 0)
  where app.is_super_admin()
$$;


-- ═══ 3. SUSPEND / REACTIVATE ═══════════════════════════════════════════════════════════════
--
-- Suspending is a decision about the ACCOUNT and is independent of the plan: a suspended hostel
-- stays suspended through a renewal (subscription_after_change and refresh_subscription_statuses
-- only ever move between 'active' and 'readonly'). Reactivating therefore cannot simply write
-- 'active' — a hostel whose plan ran out or was cancelled while it was suspended must come back
-- read-only, or lifting a suspension would hand a lapsed customer a working hostel.
--
-- Returns the status the hostel actually ended up in, so the console can say "reactivated, but
-- read-only until renewed" instead of assuming. Asking for the status a hostel already has is
-- not an error and writes nothing — no audit row, no second notice.
create or replace function public.sa_set_hostel_status(p_hostel_id uuid, p_status text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_hostel public.hostels%rowtype;
  v_result public.hostel_status;
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Only the Super Admin can suspend or reactivate a hostel.' using errcode = '42501';
  end if;

  if p_status is null or p_status not in ('suspended', 'active') then
    raise exception 'Choose whether to suspend or reactivate the hostel.' using errcode = 'P0001';
  end if;

  select * into v_hostel from public.hostels where id = p_hostel_id for update;
  if not found then
    raise exception 'No such hostel.' using errcode = 'P0001';
  end if;

  if p_status = 'suspended' then
    v_result := 'suspended';
  elsif app.subscription_state(p_hostel_id) = 'expired' then
    v_result := 'readonly';
  else
    v_result := 'active';
  end if;

  if v_result = v_hostel.status then
    return v_result::text;
  end if;

  update public.hostels
     set status = v_result,
         updated_at = now()
   where id = p_hostel_id;

  perform public.audit_event(
    'sa.hostel.status',
    'hostel',
    p_hostel_id::text,
    p_hostel_id,
    jsonb_build_object('from', v_hostel.status, 'to', v_result, 'requested', p_status, 'surface', 'rpc'),
    null, null, null, null
  );

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (
    p_hostel_id, v_hostel.owner_user_id, 'subscription',
    -- Worded from where the hostel ENDED UP, and titled from where it started: a hostel that was
    -- 'active' only because nobody had refreshed it since its plan lapsed was never suspended,
    -- and telling its owner it was "reactivated" would be the wrong story.
    case
      when v_result = 'suspended'         then 'Hostel suspended'
      when v_hostel.status = 'suspended'  then 'Hostel reactivated'
      else                                     'Hostel is read-only'
    end,
    case v_result
      when 'suspended' then format('Nivora has suspended %s. Your team can still open the app and read records, but nothing can be added or changed until it is reactivated. Contact Nivora support.', v_hostel.name)
      when 'readonly'  then format('%s is not suspended, but its plan has ended, so it is read-only until the plan is renewed. Contact Nivora support to renew.', v_hostel.name)
      else                  format('%s is active again. Your team can add and change records as usual.', v_hostel.name)
    end,
    '/owner'
  );

  return v_result::text;
end $$;

comment on function public.sa_set_hostel_status(uuid, text) is
  'Super Admin only. Suspend a hostel, or lift a suspension (the hostel returns read-only if its plan has lapsed or was cancelled). Returns the resulting hostels.status. Audits sa.hostel.status and notifies the owner. db/migrations/2026-09-16-sa-hostel-controls.sql.';


-- ── A MOVE INTO 'active' THAT THE PLAN DOES NOT COVER IS STORED AS 'readonly' ──────────────
--
-- sa_set_hostel_status above, subscription_after_change and refresh_subscription_statuses only
-- ever write 'active' when subscription_state agrees. The web console's setHostelStatus does not:
-- it PATCHes 'active' through hostels_update, then calls refresh_subscription_statuses without
-- reading its error. For RLS that was only ever a wrong label, because every write policy reads
-- subscription_state itself. It is not only a label for _shared/tenant.ts, which trusts
-- status = 'active' plus a date check that a cancelled period passes (see the header). Enforcing
-- the rule on the table closes that for every writer, present and future.
--
-- It stores exactly what refresh_subscription_statuses would store a moment later, so no writer
-- can reach a state it could not already reach; the window just closes. Only moves INTO 'active'
-- are touched. A hostel already 'active' whose plan lapsed overnight is still the refresh's job,
-- as before, and 'suspended' is never changed.
create or replace function app.hostels_status_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'active'
     and old.status is distinct from new.status
     and app.subscription_state(new.id) = 'expired' then
    new.status := 'readonly';
  end if;
  return new;
end $$;

drop trigger if exists hostels_status_guard on public.hostels;
create trigger hostels_status_guard before update of status on public.hostels
  for each row execute function app.hostels_status_guard();


-- ═══ 4. CANCEL THE CURRENT PLAN ════════════════════════════════════════════════════════════
--
-- "Current" is every period that has not ended: the one running today AND any renewal already
-- booked to start after it. Cancelling only today's would leave the booked one to switch the
-- hostel back on when its start date arrived — a cancellation that expires.
--
-- The hostel goes read-only in the same transaction: stamping the rows fires
-- subscription_after_change, which re-reads subscription_state. The explicit update after it
-- restates that, so this function's promise does not rest on a trigger a later migration could
-- drop. A suspended hostel stays suspended.
create or replace function public.sa_cancel_subscription(p_hostel_id uuid, p_reason text)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_reason text := regexp_replace(coalesce(p_reason, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_hostel public.hostels%rowtype;
  v_count  int;
  v_ends   date;
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Only the Super Admin can cancel a plan.' using errcode = '42501';
  end if;

  if char_length(v_reason) < 3 or char_length(v_reason) > 300 then
    raise exception 'Give a reason for cancelling, between 3 and 300 characters.' using errcode = 'P0001';
  end if;

  -- The same lock sa_renew_subscription takes, so the two cannot interleave on one hostel.
  select * into v_hostel from public.hostels where id = p_hostel_id for update;
  if not found then
    raise exception 'No such hostel.' using errcode = 'P0001';
  end if;

  with cancelled as (
    update public.subscriptions
       set cancelled_at  = now(),
           cancelled_by  = auth.uid(),
           cancel_reason = v_reason
     where hostel_id = p_hostel_id
       and cancelled_at is null
       and end_date >= current_date
    returning end_date
  )
  select count(*)::int, max(end_date) into v_count, v_ends from cancelled;

  if v_count = 0 then
    raise exception 'There is no current plan to cancel.' using errcode = 'P0001';
  end if;

  update public.hostels
     set status = 'readonly',
         updated_at = now()
   where id = p_hostel_id
     and status = 'active'
     and app.subscription_state(p_hostel_id) = 'expired';

  perform public.audit_event(
    'sa.subscription.cancel',
    'hostel',
    p_hostel_id::text,
    p_hostel_id,
    jsonb_build_object('periods', v_count, 'latest_end', v_ends, 'reason', v_reason, 'surface', 'rpc'),
    null, null, null, null
  );

  -- The reason is included because the owner can already read it on the row
  -- (subscriptions_select), and a notice that says "cancelled" without saying why sends them to
  -- support to ask the one question the Super Admin has already answered.
  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (
    p_hostel_id, v_hostel.owner_user_id, 'subscription', 'Plan cancelled',
    format('Nivora has cancelled the plan for %s. From today your team can still read records, but nothing can be added or changed until a new plan starts. Reason: %s', v_hostel.name, v_reason),
    '/owner'
  );

  return v_count;
end $$;

comment on function public.sa_cancel_subscription(uuid, text) is
  'Super Admin only. Stamps cancelled_at/cancelled_by/cancel_reason on every uncancelled period of the hostel that has not ended, which makes it read-only immediately. Returns the number of periods cancelled; P0001 when there were none. Audits sa.subscription.cancel and notifies the owner.';


-- ═══ 5. RENAME ═════════════════════════════════════════════════════════════════════════════
--
-- 2-120 characters after trimming — the bounds sa-create-owner already holds a new hostel's name
-- to, so a name that could be created can be restored. One line only: the name is printed into
-- notification titles and receipts, where a line break is a layout bug the owner sees.
-- Renaming to the current name is not an error and writes nothing.
create or replace function public.sa_rename_hostel(p_hostel_id uuid, p_name text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_name   text := regexp_replace(coalesce(p_name, ''), '^[[:space:]]+|[[:space:]]+$', '', 'g');
  v_hostel public.hostels%rowtype;
begin
  if not coalesce(app.is_super_admin(), false) then
    raise exception 'Only the Super Admin can rename a hostel.' using errcode = '42501';
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 120 then
    raise exception 'Enter a hostel name between 2 and 120 characters.' using errcode = 'P0001';
  end if;
  if v_name ~ '[[:cntrl:]]' then
    raise exception 'A hostel name has to fit on one line.' using errcode = 'P0001';
  end if;

  select * into v_hostel from public.hostels where id = p_hostel_id for update;
  if not found then
    raise exception 'No such hostel.' using errcode = 'P0001';
  end if;

  if v_hostel.name = v_name then
    return v_hostel.name;
  end if;

  update public.hostels
     set name = v_name,
         updated_at = now()
   where id = p_hostel_id;

  perform public.audit_event(
    'sa.hostel.rename',
    'hostel',
    p_hostel_id::text,
    p_hostel_id,
    jsonb_build_object('from', v_hostel.name, 'to', v_name, 'surface', 'rpc'),
    null, null, null, null
  );

  insert into public.notifications (hostel_id, user_id, type, title, body, link)
  values (
    p_hostel_id, v_hostel.owner_user_id, 'system', 'Hostel renamed',
    format('Nivora has renamed %s to %s. Your team will see the new name the next time they open the app.', v_hostel.name, v_name),
    '/owner'
  );

  return v_name;
end $$;

comment on function public.sa_rename_hostel(uuid, text) is
  'Super Admin only. Renames a hostel (trimmed, 2-120 characters, one line). Returns the stored name. Audits sa.hostel.rename and notifies the owner.';


-- ═══ 6. THE OWNER'S LOGIN, FOR sa-owner-account ═════════════════════════════════════════════
--
-- The first version of that function moved an owner's address with GoTrue's admin API, then wrote
-- public.users, then ended sessions in a separate best-effort call. Review found that this left two
-- ways back into an account the Super Admin was taking back:
--
--   · Neither the admin API's address change nor its password change clears email_change or its
--     two tokens. An address change the account had already started stays redeemable at
--     /auth/v1/verify: PUT /auth/v1/user needs only an owner access token and the anon key in the
--     APK. verify needs only the token, so ending sessions does not stop it. The login would then
--     move to a third address while public.users shows the one the Super Admin typed, and a
--     recovery email to that address takes the account. A recovery or magic link already mailed to
--     the old address is the same hole, and that is often the very mailbox the owner is being moved
--     away from. app.set_student_login_email closed the first half for residents on 2026-09-02;
--     owners had nothing equivalent.
--   · GoTrue ends no sessions on an address change, so the separate call was the whole job, and
--     when it failed the response still said the login had moved.
--
-- So the move is one transaction, as it is for residents: address, identity, profile, pending
-- tokens and sessions all land or none do. Measured on the live database 2026-09-16: this
-- project's GoTrue keeps each token both as a column on auth.users and as a row in
-- auth.one_time_tokens, and postgres, which owns these functions, may write both.

-- Every token that lets somebody without the password move this login or sign in to it: an
-- address change in flight (both halves) and a recovery or magic link. Both copies of each go,
-- because either may be the one /verify reads. The signup confirmation link is left to
-- set_owner_login_email, which replaces the address it was issued for. GoTrue spends that token
-- when it confirms, and no owner account is unconfirmed (0 of 3, 2026-09-16). Returns whether
-- anything was pending.
create or replace function app.clear_pending_login_tokens(p_user_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_columns integer;
  v_rows    integer;
begin
  update auth.users
     set email_change                = '',
         email_change_token_new      = '',
         email_change_token_current  = '',
         email_change_confirm_status = 0,
         email_change_sent_at        = null,
         recovery_token              = '',
         recovery_sent_at            = null,
         updated_at                  = now()
   where id = p_user_id
     and (coalesce(email_change, '') <> ''
       or coalesce(email_change_token_new, '') <> ''
       or coalesce(email_change_token_current, '') <> ''
       or coalesce(recovery_token, '') <> '');
  get diagnostics v_columns = row_count;

  delete from auth.one_time_tokens
   where user_id = p_user_id
     and token_type in ('email_change_token_new', 'email_change_token_current', 'recovery_token');
  get diagnostics v_rows = row_count;

  return v_columns > 0 or v_rows > 0;
end $$;

comment on function app.clear_pending_login_tokens(uuid) is
  'Cancel an account''s pending address-change, recovery and magic-link tokens, in auth.users and auth.one_time_tokens. Returns whether any were pending. Service role only.';

-- The owner's twin of app.set_student_login_email, narrower: owners have no phone mapping to fall
-- back to, so there is no "clear the address" case, and the target must be a live owner row.
create or replace function app.set_owner_login_email(p_user_id uuid, p_email text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email    text := lower(btrim(coalesce(p_email, '')));
  v_user     public.users%rowtype;
  v_auth     text;
  v_prev     text;
  v_tokens   boolean;
  v_sessions integer;
begin
  -- The shape and length the Edge Function's Validator accepts, so an address is not taken there
  -- and refused here. HINT 'email' tells the function the refusal belongs under the address box.
  if char_length(v_email) > 200 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Enter a valid email address' using errcode = 'P0001', hint = 'email';
  end if;
  -- The phone-mapping namespace: an address there would take some resident's login id for good.
  if not app.email_is_reachable(v_email) then
    raise exception 'Enter a real email address' using errcode = 'P0001', hint = 'email';
  end if;

  -- Locked, so a demotion or deactivation cannot land between this check and the writes.
  select * into v_user from public.users where id = p_user_id for update;
  if not found or v_user.role <> 'owner' then
    raise exception 'Only an owner''s login can be changed here.' using errcode = 'P0001';
  end if;
  if v_user.deleted_at is not null or v_user.status <> 'active' then
    raise exception 'That owner account is inactive. Reactivate it before changing its login.'
      using errcode = 'P0001';
  end if;

  select au.email into v_auth from auth.users au where au.id = p_user_id for update;
  if v_auth is null then
    raise exception 'That owner has no login to change.' using errcode = 'P0001';
  end if;

  -- Nothing to do, and nothing written: saving the same address costs no verification.
  if lower(v_auth) = v_email then
    return jsonb_build_object('loginEmail', lower(v_auth), 'changed', false,
                              'verificationCleared', false, 'sessionsEnded', 0,
                              'pendingTokensCleared', false);
  end if;

  -- 23505, what either unique index would raise, so the caller answers 409 whichever speaks first.
  if exists (select 1 from auth.users au where lower(au.email) = v_email and au.id <> p_user_id)
     or exists (select 1 from public.users u where lower(u.email) = v_email and u.id <> p_user_id) then
    raise exception 'That email address already belongs to another account.' using errcode = '23505';
  end if;

  -- users_update_guard lets an update through only for a caller it recognises, and this session
  -- carries no JWT it can read. Execution is granted to service_role alone, so asserting that role
  -- for the rest of THIS transaction restates who already got in, as set_student_login_email does.
  v_prev := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  v_tokens := app.clear_pending_login_tokens(p_user_id);

  -- email_confirmed_at is what GoTrue's email_confirm: true writes. "Confirm email" is on, so an
  -- unconfirmed address could not sign in at all. The signup confirmation link goes too, because it
  -- was issued for the address being replaced.
  update auth.users
     set email              = v_email,
         email_confirmed_at = now(),
         confirmation_token = '',
         updated_at         = now()
   where id = p_user_id;
  delete from auth.one_time_tokens where user_id = p_user_id and token_type = 'confirmation_token';

  -- auth.identities.email is generated from identity_data->>'email', so the JSON is what moves.
  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_email), true),
         updated_at    = now()
   where user_id = p_user_id
     and provider = 'email';

  -- users_update_guard nulls email_verified_at on the way through: the owner proves the new mailbox.
  update public.users set email = v_email where id = p_user_id;

  -- GoTrue ends no sessions on an address change. Here it is part of the same commit.
  v_sessions := app.revoke_user_sessions(p_user_id);

  perform set_config('request.jwt.claims', coalesce(v_prev, ''), true);

  return jsonb_build_object(
    'loginEmail', v_email,
    'changed', true,
    'verificationCleared', v_user.email_verified_at is not null,
    'sessionsEnded', v_sessions,
    'pendingTokensCleared', v_tokens
  );
end $$;

comment on function app.set_owner_login_email(uuid, text) is
  'Move an owner''s login address in auth.users, auth.identities and public.users, cancel the account''s pending tokens and end its sessions, in one transaction. Email verification is cleared by users_update_guard. Service role only.';

-- The PostgREST doors, service role only. The grant is the lock and the check is the bolt, as for
-- svc_set_student_login_email: a grant to authenticated added by accident later still refuses.
create or replace function public.svc_set_owner_login_email(p_user_id uuid, p_email text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  return app.set_owner_login_email(p_user_id, p_email);
end $$;

comment on function public.svc_set_owner_login_email(uuid, text) is
  'PostgREST door onto app.set_owner_login_email(). Service role only — called by supabase/functions/sa-owner-account.';

create or replace function public.svc_clear_owner_login_tokens(p_user_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not app.is_service_role() then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  -- Owners only, here as well as in the Edge Function, so this door cannot be pointed at any other
  -- account whatever id a later caller passes.
  if not exists (select 1 from public.users u where u.id = p_user_id and u.role = 'owner') then
    raise exception 'Only an owner''s login can be changed here.' using errcode = 'P0001';
  end if;
  return app.clear_pending_login_tokens(p_user_id);
end $$;

comment on function public.svc_clear_owner_login_tokens(uuid) is
  'PostgREST door onto app.clear_pending_login_tokens() for an owner account. Service role only — called by supabase/functions/sa-owner-account before and after a password reset.';

revoke all on function app.clear_pending_login_tokens(uuid) from public, anon, authenticated;
grant execute on function app.clear_pending_login_tokens(uuid) to service_role;
revoke all on function app.set_owner_login_email(uuid, text) from public, anon, authenticated;
grant execute on function app.set_owner_login_email(uuid, text) to service_role;
revoke all on function public.svc_set_owner_login_email(uuid, text) from public, anon, authenticated;
grant execute on function public.svc_set_owner_login_email(uuid, text) to service_role;
revoke all on function public.svc_clear_owner_login_tokens(uuid) from public, anon, authenticated;
grant execute on function public.svc_clear_owner_login_tokens(uuid) to service_role;


-- ═══ 7. GRANTS ═════════════════════════════════════════════════════════════════════════════
--
-- Signed-in callers only; each function refuses everyone but the Super Admin itself. anon is
-- named explicitly — see the header. The redefined readers keep the grants they already had,
-- because CREATE OR REPLACE on an unchanged signature does not touch proacl.

revoke all on function public.sa_set_hostel_status(uuid, text) from public, anon;
grant execute on function public.sa_set_hostel_status(uuid, text) to authenticated;

revoke all on function public.sa_cancel_subscription(uuid, text) from public, anon;
grant execute on function public.sa_cancel_subscription(uuid, text) to authenticated;

revoke all on function public.sa_rename_hostel(uuid, text) from public, anon;
grant execute on function public.sa_rename_hostel(uuid, text) to authenticated;

notify pgrst, 'reload schema';


-- ═══ AFTER APPLYING ════════════════════════════════════════════════════════════════════════
--
-- 1. The three RPCs exist, are SECURITY DEFINER with a pinned search_path, and anon cannot run them:
--      select p.oid::regprocedure, p.prosecdef, p.proconfig, array_to_string(p.proacl, ' | ')
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('sa_set_hostel_status', 'sa_cancel_subscription', 'sa_rename_hostel');
--    Three rows, prosecdef true, {search_path=public}, `authenticated=X` present, `anon=X` absent.
--
-- 2. No reader of the current plan was left behind:
--      select p.oid::regprocedure
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname in ('public', 'app')
--         and p.prosrc ilike '%subscriptions%'
--         and p.prosrc not ilike '%cancelled_at%';
--    Exactly one row: sa_create_hostel_with_subscription, which only inserts. Anything else is a
--    new reader that has to learn about cancellation before it ships.
--
-- 3. The overridden signatures are the ones that were live (a changed signature would have
--    created an overload beside the old function instead of replacing it):
--      select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where (n.nspname, p.proname) in (('app','subscription_state'), ('app','subscription_days_left'),
--             ('public','sa_renew_subscription'), ('public','rpc_sa_hostels'),
--             ('public','rpc_sa_dashboard'), ('public','refresh_subscription_statuses'));
--    Six rows, one per name.
--
-- 4. A non-Super-Admin is refused with 42501, not a message (run as a real owner's id):
--      begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<owner-user-id>","role":"authenticated","aal":"aal2"}';
--      select public.sa_rename_hostel('<their-hostel-id>', 'Mine now');   -- ERROR 42501
--      rollback;
--
-- 5. Rehearse a cancellation and throw it away (as the Super Admin, stepped up):
--      begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<super-admin-id>","role":"authenticated","aal":"aal2"}';
--      select public.sa_cancel_subscription('<hostel-id>', 'Rehearsal');   -- 1 (or more)
--      select app.subscription_state('<hostel-id>'),                        -- expired
--             app.hostel_writable('<hostel-id>'),                           -- false
--             (select status from public.hostels where id = '<hostel-id>'); -- readonly (or suspended)
--      select public.sa_cancel_subscription('<hostel-id>', 'Again');       -- ERROR P0001 no current plan
--      rollback;
--
-- 6. The status guard stores 'readonly' for a move into 'active' that the plan does not cover. The
--    web console's PATCH, as the Super Admin, stepped up, on a hostel whose plan is cancelled or lapsed:
--      begin;
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<super-admin-id>","role":"authenticated","aal":"aal2"}';
--      update public.hostels set status = 'active' where id = '<hostel-id>' returning status;  -- readonly
--      rollback;
--
-- 7. The owner-login functions exist, and only the service role can run them:
--      select p.oid::regprocedure, p.prosecdef, p.proconfig, array_to_string(p.proacl, ' | ')
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where p.proname in ('clear_pending_login_tokens', 'set_owner_login_email',
--                           'svc_set_owner_login_email', 'svc_clear_owner_login_tokens');
--    Four rows, prosecdef true, {search_path=public}, `service_role=X` present, and neither
--    `anon=X` nor `authenticated=X`.
--
-- 8. Rehearse an owner's address move and throw it away (as the service role):
--      begin;
--      set local request.jwt.claims = '{"role":"service_role"}';
--      select public.svc_set_owner_login_email('<owner-user-id>', 'rehearsal.owner@example.com');
--        -- {"changed": true, "sessionsEnded": <n>, "pendingTokensCleared": <bool>, ...}
--      select email, email_change, email_change_token_new, recovery_token, email_confirmed_at
--        from auth.users where id = '<owner-user-id>';                  -- new address, '' tokens, now
--      select identity_data->>'email' from auth.identities where user_id = '<owner-user-id>';  -- new
--      select email, email_verified_at from public.users where id = '<owner-user-id>';   -- new, NULL
--      select count(*) from auth.sessions where user_id = '<owner-user-id>';             -- 0
--      select count(*) from auth.one_time_tokens where user_id = '<owner-user-id>'
--         and token_type in ('email_change_token_new', 'email_change_token_current',
--                            'recovery_token', 'confirmation_token');                  -- 0
--      select public.svc_set_owner_login_email('<super-admin-id>', 'x@example.com');     -- ERROR P0001
--      rollback;
