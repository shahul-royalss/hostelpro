-- Undo 2026-10-26-legal-version-round3.sql: only while nobody has accepted the version.
do $$
declare
  n bigint;
begin
  select count(*) into n from public.legal_acceptances where version = '2026-10-26';
  if n > 0 then
    raise exception '% acceptance(s) of 2026-10-26 exist; this version can no longer be withdrawn', n;
  end if;
  delete from public.legal_versions where version = '2026-10-26';
end
$$;
