-- UNDO 2026-11-01-legal-version-round6.sql. Only while nobody has accepted 2026-11-01.
delete from public.legal_versions v
 where v.version = '2026-11-01'
   and not exists (select 1 from public.legal_acceptances a where a.version = v.version);
