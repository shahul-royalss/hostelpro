-- UNDO 2026-11-04-legal-version-cashfree.sql. Only while nobody has accepted 2026-11-04.
delete from public.legal_versions v
 where v.version = '2026-11-04'
   and not exists (select 1 from public.legal_acceptances a where a.version = v.version);
