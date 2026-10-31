-- Undo 2026-10-31-legal-version-round5.sql: only while nobody has accepted the version.
do $$
declare
  n bigint;
begin
  select count(*) into n from public.legal_acceptances where version = '2026-10-31';
  if n > 0 then
    raise exception '% acceptance(s) of 2026-10-31 exist; this version can no longer be withdrawn', n;
  end if;
  delete from public.legal_versions where version = '2026-10-31';
end
$$;
