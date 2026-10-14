-- Undo 2026-10-14-apnivaas-live-names.sql: the old cron job names and the old hook log tag.
-- Same guards as the forward file, mirrored.

begin;
set local lock_timeout = '10s';

select cron.schedule('nivora-rent-reminders', '30 3 * * *', $$select app.send_rent_reminders()$$);
select cron.unschedule('apnivaas-rent-reminders');
select cron.schedule('nivora-drain-storage-erasures', '40 3 * * *', $$select app.drain_storage_erasures()$$);
select cron.unschedule('apnivaas-drain-storage-erasures');

do $hooks$
declare
  r      record;
  v_old  text;
  v_new  text;
begin
  for r in
    select * from (values
      ('password_verification_attempt', '28fc6000d5a744f3eb3285d070c563bf', 'cd5bd7677abe52ec5756bb49c1adb7e5'),
      ('mfa_verification_attempt',      '3e18931c4eebf9bc4e87061b8556fad7', 'b8ac21772a3d2e8ffb1a7be95ed92284')
    ) v(fn, md5_before, md5_after)
  loop
    select p.prosrc into strict v_old
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if md5(v_old) <> r.md5_before then
      raise exception '% is not the forward migration''s body; nothing changed', r.fn;
    end if;
    execute replace(pg_get_functiondef(('public.' || r.fn || '(jsonb)')::regprocedure),
                    '''[apnivaas] ', '''[nivora] ');
    select p.prosrc into strict v_new
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = r.fn;
    if md5(v_new) <> r.md5_after then
      raise exception '% did not return to its 2026-10-14 body; nothing changed', r.fn;
    end if;
  end loop;
end
$hooks$;

delete from supabase_migrations.schema_migrations where version = '20261014220000';

commit;
