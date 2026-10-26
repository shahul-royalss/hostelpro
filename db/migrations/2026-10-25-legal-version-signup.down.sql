-- Undo 2026-10-25-legal-version-signup.sql.
--
-- Only safe while nobody has agreed to '2026-10-25': legal_acceptances.version references
-- legal_versions, and an acceptance is evidence that must not be destroyed to tidy a table.
-- So this refuses when any acceptance names the version. Roll back the website and every app
-- build carrying '2026-10-25' FIRST: with the row gone, those builds strand their users at the
-- consent gate (Agree fails with 22023).

do $$
declare
  n bigint;
begin
  select count(*) into n from public.legal_acceptances where version = '2026-10-25';
  if n > 0 then
    raise exception '% acceptance(s) of 2026-10-25 exist; this version can no longer be withdrawn', n;
  end if;
  delete from public.legal_versions where version = '2026-10-25';
end
$$;

-- Check: the newest row is '2026-10-17' again.
--   select version from public.legal_versions order by version desc limit 1;
