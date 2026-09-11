-- ─────────────────────────────────────────────────────────────────────────────
-- THE NOTIFICATIONS ACTUALLY REACH THE PHONE
--
-- The product owner: "notifications has to sent through app notification... when the student due
-- date comes... when owner shares the notices... when owner receives the student amount who
-- paid... like all possibilities to send the important notifications... not unnecessary one's."
--
-- ── WHAT WAS ALREADY TRUE ───────────────────────────────────────────────────────────────────
--
-- public.notifications has been written by five triggers since the beginning — a notice fans out
-- to its audience, a complaint tells the wardens and the owner, a payment tells the resident, a
-- leave tells the warden and then the resident, a task tells the manager and then the owner. All
-- of that already happens. What has never existed is a way for any of it to LEAVE THE DATABASE:
-- no device tokens, no sender, and no client asking for either.
--
-- ── THE FOUR PIECES THIS ADDS ───────────────────────────────────────────────────────────────
--
--   1. public.push_devices          — which phones belong to which signed-in person.
--   2. hostels.rent_due_day         — the day of the month rent is expected. Without it there is
--                                     no such thing as "the due date came", and the schema had
--                                     no due-date column at all (features/student/widgets/rent.dart
--                                     says so out loud, and stops short of inventing one).
--   3. app.send_rent_reminders()    — a daily job that writes the due/overdue notifications.
--   4. app.notifications_dispatch_push() — one HTTP call per INSERT STATEMENT to the push-send
--                                     Edge Function, which is what turns a row into a banner.
--
-- Plus one more recipient: the owner is told when money arrives, which they asked for by name.
--
-- ── WHY A STATEMENT TRIGGER AND NOT A ROW TRIGGER ───────────────────────────────────────────
--
-- A notice to 300 residents is ONE insert of 300 rows. A row trigger would queue 300 HTTP calls
-- for one event; the statement trigger sends the ids in batches of 200 with a transition table.
-- It also filters to users who actually have a device registered, so a PG where nobody has
-- opened the app yet makes no calls at all.
--
-- pg_net queues the request inside this transaction and its background worker sends it AFTER the
-- commit — so a rolled-back write cannot produce a push, and a slow FCM cannot hold a lock on
-- public.notifications. Any failure inside the dispatcher is swallowed: a push that cannot be
-- sent must never take down the payment, the complaint or the notice that caused it.
--
-- ── NOT UNNECESSARY ONES ────────────────────────────────────────────────────────────────────
--
-- Rent reminders fire on exactly three days per resident per month — three days before, on the
-- day, three days after — and never for a resident who has already paid. notifications.dedupe_key
-- makes each of those at-most-once even if the job runs twice.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. DEVICES ──────────────────────────────────────────────────────────────
create table if not exists public.push_devices (
  token        text primary key,
  user_id      uuid not null references public.users(id) on delete cascade,
  platform     text not null check (platform in ('android', 'ios')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_devices_user_idx on public.push_devices (user_id);

alter table public.push_devices enable row level security;
drop policy if exists push_devices_select on public.push_devices;
drop policy if exists push_devices_delete on public.push_devices;
-- Read and delete your own; there is deliberately no insert or update policy, because a token
-- arrives through register_push_device() which also has to be able to MOVE a token off whoever
-- held it last (one phone, two people, one after the other).
create policy push_devices_select on public.push_devices for select
  using (user_id = (select auth.uid()));
create policy push_devices_delete on public.push_devices for delete
  using (user_id = (select auth.uid()));

create or replace function public.register_push_device(p_token text, p_platform text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sign in first.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.users u
                  where u.id = v_uid and u.status = 'active' and u.deleted_at is null) then
    raise exception 'This account is not active.' using errcode = '42501';
  end if;
  if p_token is null or char_length(p_token) < 20 or char_length(p_token) > 4096 then
    raise exception 'That does not look like a device token.' using errcode = 'P0001';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'Unknown platform.' using errcode = 'P0001';
  end if;

  insert into public.push_devices (token, user_id, platform)
  values (p_token, v_uid, p_platform)
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        last_seen_at = now();
end $$;

create or replace function public.unregister_push_device(p_token text)
returns void
language sql security definer set search_path = public as $$
  delete from public.push_devices where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_push_device(text, text) from public, anon;
revoke all on function public.unregister_push_device(text) from public, anon;
grant execute on function public.register_push_device(text, text) to authenticated;
grant execute on function public.unregister_push_device(text) to authenticated;

-- ── 2. WHEN RENT IS DUE ─────────────────────────────────────────────────────
alter table public.hostels add column if not exists rent_due_day smallint not null default 5;
alter table public.hostels drop constraint if exists hostels_rent_due_day_check;
alter table public.hostels add constraint hostels_rent_due_day_check
  check (rent_due_day between 1 and 28);

-- 28, not 31: a due day of the 30th does not exist in February, and a reminder that silently
-- never fires for one month a year is worse than a control that cannot express it.
create or replace function public.ow_set_rent_due_day(p_hostel_id uuid, p_day int)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (app.is_super_admin() or p_hostel_id in (select app.owned_hostel_ids())) then
    raise exception 'Only this hostel''s owner can set its rent day.' using errcode = '42501';
  end if;
  if not app.is_super_admin() and not app.hostel_writable(p_hostel_id) then
    raise exception 'This hostel is read-only until its subscription is renewed.' using errcode = 'P0001';
  end if;
  if p_day is null or p_day < 1 or p_day > 28 then
    raise exception 'Pick a day between 1 and 28.' using errcode = 'P0001';
  end if;
  update public.hostels set rent_due_day = p_day, updated_at = now() where id = p_hostel_id;
end $$;

revoke all on function public.ow_set_rent_due_day(uuid, int) from public, anon;
grant execute on function public.ow_set_rent_due_day(uuid, int) to authenticated;

-- ── 3. AT MOST ONCE ─────────────────────────────────────────────────────────
alter table public.notifications add column if not exists dedupe_key text;
alter table public.notifications add column if not exists pushed_at timestamptz;
create unique index if not exists notifications_dedupe_key_idx
  on public.notifications (dedupe_key) where dedupe_key is not null;

-- ── 4. THE OWNER HEARS ABOUT MONEY ──────────────────────────────────────────
create or replace function app.fee_payments_after_change() returns trigger
language plpgsql security definer set search_path to 'public' as $function$
declare
  v_student_user uuid;
  v_student_name text;
  v_owner        uuid;
  v_outstanding  numeric;
  v_delta        numeric;
  v_received     text;
  v_left         text;
  v_month        text;
  v_cleared      boolean;
begin
  if tg_op = 'INSERT' and new.amount_paid <= 0 then return new; end if;
  if tg_op = 'UPDATE' and new.amount_paid <= old.amount_paid then return new; end if;

  select user_id, full_name into v_student_user, v_student_name
    from public.students where id = new.student_id;
  v_outstanding := greatest(new.amount_due - new.amount_paid, 0);
  v_cleared     := new.status = 'paid';
  v_month       := to_char(to_date(new.period_month, 'YYYY-MM'), 'FMMonth YYYY');
  -- What arrived in THIS change, not the running total: an owner watching payments come in
  -- wants the size of the payment, and on a top-up the cumulative figure would overstate it.
  v_delta       := new.amount_paid - case when tg_op = 'UPDATE' then old.amount_paid else 0 end;

  v_received := '₹' || trim(to_char(new.amount_paid,
    case when new.amount_paid = trunc(new.amount_paid)
         then 'FM99,99,99,990' else 'FM99,99,99,990D00' end));
  v_left := '₹' || trim(to_char(v_outstanding,
    case when v_outstanding = trunc(v_outstanding)
         then 'FM99,99,99,990' else 'FM99,99,99,990D00' end));

  if v_student_user is not null then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (
      new.hostel_id, v_student_user, 'fee',
      case when v_cleared then 'Rent cleared' else 'Part payment received' end,
      v_received || ' received for ' || v_month || '. '
        || case when v_cleared then 'Your rent for this month is cleared.'
                else v_left || ' is still to pay.' end
        || ' Your receipt is on the Fees tab.',
      '/student?receipt=' || new.id
    );
  end if;

  select owner_user_id into v_owner from public.hostels where id = new.hostel_id;
  if v_owner is not null then
    insert into public.notifications (hostel_id, user_id, type, title, body, link)
    values (
      new.hostel_id, v_owner, 'fee', 'Payment received',
      '₹' || trim(to_char(v_delta, case when v_delta = trunc(v_delta)
                                        then 'FM99,99,99,990' else 'FM99,99,99,990D00' end))
        || ' from ' || coalesce(v_student_name, 'a resident') || ' for ' || v_month || '. '
        || case when v_cleared then 'That clears their month.'
                else v_left || ' still to come.' end,
      '/owner/payments'
    );
  end if;

  return new;
end $function$;

-- ── 5. THE DUE DATE ITSELF ──────────────────────────────────────────────────
create or replace function app.send_rent_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare
  v_today  date := app.today();
  v_month  text := to_char(v_today, 'YYYY-MM');
  v_due    date;
  v_stage  text;
  v_owing  numeric;
  v_count  int := 0;
  r        record;
begin
  for r in
    select s.id as student_id, s.user_id, s.hostel_id, h.rent_due_day,
           coalesce(fp.amount_due, s.monthly_fee) as due,
           coalesce(fp.amount_paid, 0)            as paid
      from public.students s
      join public.hostels h on h.id = s.hostel_id
      left join public.fee_payments fp
             on fp.student_id = s.id and fp.period_month = v_month
     where s.deleted_at is null
       and s.erased_at is null
       and s.status in ('active', 'on_leave')
       and s.user_id is not null
       and s.monthly_fee > 0
       and s.date_of_joining <= v_today
       and h.status = 'active'
  loop
    v_owing := r.due - r.paid;
    if v_owing <= 0 then continue; end if;

    v_due := make_date(extract(year from v_today)::int, extract(month from v_today)::int, r.rent_due_day);
    v_stage := case v_today - v_due
                 when -3 then 'soon'
                 when  0 then 'today'
                 when  3 then 'late'
                 else null end;
    if v_stage is null then continue; end if;

    insert into public.notifications (hostel_id, user_id, type, title, body, link, dedupe_key)
    values (
      r.hostel_id, r.user_id, 'fee',
      case v_stage when 'soon'  then 'Rent due in 3 days'
                   when 'today' then 'Rent is due today'
                   else              'Rent is overdue' end,
      '₹' || trim(to_char(v_owing, case when v_owing = trunc(v_owing)
                                        then 'FM99,99,99,990' else 'FM99,99,99,990D00' end))
        || ' for ' || to_char(v_today, 'FMMonth YYYY')
        || case v_stage when 'soon'  then ' is due on ' || to_char(v_due, 'DD Mon') || '.'
                        when 'today' then ' is due today.'
                        else              ' was due on ' || to_char(v_due, 'DD Mon') || '.' end
        || ' You can pay in the app or at the desk.',
      '/student',
      'rent:' || r.student_id || ':' || v_month || ':' || v_stage
    )
    on conflict (dedupe_key) do nothing;

    if found then v_count := v_count + 1; end if;
  end loop;

  -- A phone that has not checked in for three months is a phone somebody sold. Its token is
  -- long dead at FCM; pruning here keeps the fan-out from paying for it every time.
  delete from public.push_devices where last_seen_at < now() - interval '90 days';

  return v_count;
end $$;

select cron.schedule('nivora-rent-reminders', '30 3 * * *', $$select app.send_rent_reminders()$$);

-- ── 6. FROM A ROW TO A BANNER ───────────────────────────────────────────────
create table if not exists app.push_config (
  id            boolean primary key default true check (id),
  function_url  text not null,
  anon_key      text not null,
  enabled       boolean not null default true,
  updated_at    timestamptz not null default now()
);
revoke all on table app.push_config from public, anon, authenticated;

insert into app.push_config (id, function_url, anon_key, enabled)
values (true,
        'https://nimxvgzscbanhtvgnjll.supabase.co/functions/v1/push-send',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pbXh2Z3pzY2Jhbmh0dmduamxsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1NzQzNjYsImV4cCI6MjEwMTE1MDM2Nn0.AEFDIcHmli9QKx5pFbTGCTpwFuDykK212XJFTqvSMN4',
        true)
on conflict (id) do update
  set function_url = excluded.function_url,
      anon_key     = excluded.anon_key,
      updated_at   = now();

create or replace function app.notifications_dispatch_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_ids   uuid[];
  v_chunk uuid[];
  v_cfg   app.push_config%rowtype;
  i       int;
begin
  select * into v_cfg from app.push_config where id;
  if not found or not v_cfg.enabled then return null; end if;

  -- Only for people who have a phone registered. A PG where nobody has signed in on mobile
  -- yet makes no HTTP calls at all.
  select array_agg(n.id) into v_ids
    from new_rows n
   where exists (select 1 from public.push_devices d where d.user_id = n.user_id);

  if v_ids is null then return null; end if;

  i := 1;
  while i <= array_length(v_ids, 1) loop
    v_chunk := v_ids[i : i + 199];
    perform net.http_post(
      url     := v_cfg.function_url,
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || v_cfg.anon_key),
      body    := jsonb_build_object('notification_ids', to_jsonb(v_chunk)),
      timeout_milliseconds := 5000);
    i := i + 200;
  end loop;
  return null;
exception when others then
  -- A push that cannot be queued must never roll back the payment, complaint or notice that
  -- caused it. The row is written either way and the in-app list still shows it.
  return null;
end $$;

drop trigger if exists notifications_dispatch_push on public.notifications;
create trigger notifications_dispatch_push
after insert on public.notifications
referencing new table as new_rows
for each statement execute function app.notifications_dispatch_push();
