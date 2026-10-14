-- 2026-10-14 — the last places the LIVE database still used the product's old name.
--
-- Found by a read-only search of live on 2026-10-14 (pg_proc bodies, object and function
-- comments, cron jobs, storage buckets). Four of them change here; one deliberately does not:
--
--   cron job  nivora-rent-reminders            -> apnivaas-rent-reminders            (30 3 * * *)
--   cron job  nivora-drain-storage-erasures    -> apnivaas-drain-storage-erasures    (40 3 * * *)
--   public.password_verification_attempt       '[nivora]' log tag -> '[apnivaas]'
--   public.mfa_verification_attempt            '[nivora]' log tag -> '[apnivaas]'
--
--   NOT CHANGED: app.demo_review_email_verified matches the Play review logins by their
--   '@nivora.app' address. Those accounts are live and named in Play Console's App access, so the
--   address stays until they are replaced.
--
-- Nothing a user sees changes. The jobs keep their schedule, command, database and role; they run
-- as postgres in database postgres, which is what cron.schedule() records when this runs as
-- postgres (checked below, and the batch refuses to commit otherwise). The two GoTrue hooks are
-- re-created from their own live definition with only the tag replaced, and the batch proves that
-- (md5 before, md5 after, and the after-body with the tag put back equal to the before-body).
-- CREATE OR REPLACE keeps the function's grants, so supabase_auth_admin can still execute both.
--
-- Undo: 2026-10-14-apnivaas-live-names.down.sql.

begin;
set local lock_timeout = '10s';

do $guard$
begin
  if current_user <> 'postgres' then
    raise exception 'run as postgres, so the re-created cron jobs keep their role (got %)', current_user;
  end if;
  if (select count(*) from cron.job
       where (jobname, schedule, command, database, username, active) in (
         ('nivora-rent-reminders', '30 3 * * *', 'select app.send_rent_reminders()', 'postgres', 'postgres', true),
         ('nivora-drain-storage-erasures', '40 3 * * *', 'select app.drain_storage_erasures()', 'postgres', 'postgres', true))) <> 2 then
    raise exception 'the two cron jobs are not as measured on 2026-10-14; nothing changed';
  end if;
end
$guard$;

-- 1. The scheduled jobs: same schedule and command, new names.
select cron.schedule('apnivaas-rent-reminders', '30 3 * * *', $$select app.send_rent_reminders()$$);
select cron.unschedule('nivora-rent-reminders');
select cron.schedule('apnivaas-drain-storage-erasures', '40 3 * * *', $$select app.drain_storage_erasures()$$);
select cron.unschedule('nivora-drain-storage-erasures');

-- 2. The GoTrue hooks: the log tag, and nothing else.
do $hooks$
declare
  r      record;
  v_old  text;
  v_new  text;
begin
  for r in
    select * from (values
      ('password_verification_attempt', 'cd5bd7677abe52ec5756bb49c1adb7e5', '28fc6000d5a744f3eb3285d070c563bf'),
      ('mfa_verification_attempt',      'b8ac21772a3d2e8ffb1a7be95ed92284', '3e18931c4eebf9bc4e87061b8556fad7')
    ) v(fn, md5_before, md5_after)
  loop
    select p.prosrc into strict v_old
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if md5(v_old) <> r.md5_before then
      raise exception '% is not the body measured on 2026-10-14; nothing changed', r.fn;
    end if;

    execute replace(pg_get_functiondef(('public.' || r.fn || '(jsonb)')::regprocedure),
                    '''[nivora] ', '''[apnivaas] ');

    select p.prosrc into strict v_new
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if md5(v_new) <> r.md5_after or replace(v_new, '[apnivaas]', '[nivora]') <> v_old then
      raise exception '% changed by more than its log tag; nothing changed', r.fn;
    end if;
    if not has_function_privilege('supabase_auth_admin', ('public.' || r.fn || '(jsonb)')::regprocedure, 'execute') then
      raise exception '% lost its supabase_auth_admin grant; nothing changed', r.fn;
    end if;
  end loop;
end
$hooks$;

-- 3. What live looks like afterwards, or no commit.
do $verify$
begin
  if exists (select 1 from cron.job where jobname ~* 'nivora') then
    raise exception 'a cron job still carries the old name';
  end if;
  if (select count(*) from cron.job
       where (jobname, schedule, command, database, username, active) in (
         ('apnivaas-rent-reminders', '30 3 * * *', 'select app.send_rent_reminders()', 'postgres', 'postgres', true),
         ('apnivaas-drain-storage-erasures', '40 3 * * *', 'select app.drain_storage_erasures()', 'postgres', 'postgres', true))) <> 2 then
    raise exception 'the renamed cron jobs are not identical to the old ones';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema')
                and p.prosrc ~* 'nivora' and p.proname <> 'demo_review_email_verified') then
    raise exception 'a function body still carries the old name';
  end if;
end
$verify$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261014220000', 'apnivaas_live_names') on conflict (version) do nothing;

commit;
