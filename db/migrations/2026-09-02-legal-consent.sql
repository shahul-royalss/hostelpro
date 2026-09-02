-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-09-02 · LEGAL CONSENT — the record behind the first-run agreement gate
-- ─────────────────────────────────────────────────────────────────────────────
--
-- OWNED BY THE LEGAL/CONSENT WORK. This file adds two tables and one RPC and touches nothing
-- else. It deliberately does NOT edit app.apply_retention(), which is owned by the retention
-- work and lives in its own migration — see the note in §5 below for what that job must and
-- must not do to these rows.
--
-- WHY THIS EXISTS AT ALL, and it is not a nicety. NIVORA processes residents' names, phone
-- numbers, permanent addresses, guardian contact details, government-ID scans and a payment
-- ledger. Google Play will not list an app that handles personal data without a publicly
-- reachable privacy policy, and the DPDP Act 2023 requires notice and consent before that
-- processing begins. A gate that shows the documents but records nothing is theatre: the whole
-- value of asking is being able to say afterwards WHO agreed, to WHICH TEXT, and WHEN. That
-- triple is what these two tables hold, and it is the only reason they are separate from a
-- boolean column on public.users.
--
-- ═══ 1. WHAT A "VERSION" IS ═══
-- One version string covers BOTH published documents — the Terms of Use and the Privacy
-- Policy — because they are presented, and agreed to, together. Splitting them would mean two
-- acceptances, two gates and two ways to be half-agreed, for no benefit anyone asked for.
-- The string is the publication date of the pair (e.g. '2026-09-02'), and it is the SAME string
-- in three places, which is the coupling that keeps them honest:
--
--   · lib/legal-config.ts            → LEGAL_VERSION      (the Next.js pages that publish them)
--   · nivora_app/lib/features/legal/legal_documents.dart → kLegalVersion (what the app shows)
--   · public.legal_versions.version  → here               (what an acceptance may point at)
--
-- Change the documents → bump all three → every user is asked again, because the gate compares
-- the version it ships against the versions this user has accepted.

create table if not exists public.legal_versions (
  version       text primary key,
  -- When this pair of documents took effect. NOT the time the row was inserted: a version may
  -- be staged before it is published.
  effective_at  timestamptz not null default now(),
  terms_url     text not null,
  privacy_url   text not null,
  -- Free text for whoever reads this table in two years wondering what changed.
  summary       text,
  created_at    timestamptz not null default now()
);

comment on table public.legal_versions is
  'Published versions of the Terms of Use + Privacy Policy pair. An acceptance may only name a '
  'version that exists here, so a client cannot invent one.';

-- ═══ 2. THE EVIDENCE ═══
--
-- Append-only, one row per (person, version). Re-agreeing to a version already agreed to is the
-- end state the caller asked for, so it is a no-op rather than a second row — which also means
-- a double-tap on the Agree button cannot produce two contradictory timestamps.
--
-- WHAT IS DELIBERATELY NOT STORED HERE: no IP address and no user-agent string. Neither is
-- needed to evidence "this account agreed to this text at this time", and both are exactly the
-- kind of identifier the privacy policy this table exists to support promises not to hoard.
-- The audit_log row written by the RPC below carries the request context that the rest of the
-- platform already keeps under its own retention rule; this table keeps the fact itself.

create table if not exists public.legal_acceptances (
  id           bigint generated always as identity primary key,
  -- ON DELETE CASCADE is the privacy-correct choice, not an oversight. When a person is erased
  -- there is no longer any processing for this consent to authorise, and keeping a row that
  -- names them would be retaining personal data for the sake of a record about retaining
  -- personal data. public.users already cascades from auth.users the same way.
  user_id      uuid        not null references public.users(id) on delete cascade,
  -- The FK is what makes the record trustworthy: an acceptance cannot name a text that was
  -- never published. No ON DELETE action — a published version must not be deletable while
  -- somebody's consent points at it.
  version      text        not null references public.legal_versions(version),
  accepted_at  timestamptz not null default now(),
  -- Where the person was standing when they agreed: 'android', 'web'. Not security-relevant,
  -- but it is the first question asked when an acceptance is ever disputed.
  surface      text,
  -- The build that drew the documents, so "what did they actually see" is answerable.
  app_version  text,
  unique (user_id, version)
);

comment on table public.legal_acceptances is
  'Append-only record of who accepted which version of the legal documents, and when. Written '
  'only by public.accept_legal_terms(); no INSERT/UPDATE/DELETE policy exists.';

create index if not exists legal_acceptances_user_idx
  on public.legal_acceptances (user_id, version);

-- ═══ 3. ROW-LEVEL SECURITY ═══

alter table public.legal_versions    enable row level security;
alter table public.legal_acceptances enable row level security;
select app.drop_policies('legal_versions');
select app.drop_policies('legal_acceptances');

-- Anyone signed in may read what the published versions are. This is public text — it is
-- literally on the open web — and the client needs to be able to tell that the version it is
-- about to ask about exists. No write policy: versions are published by a migration.
create policy legal_versions_select on public.legal_versions for select
  using (auth.uid() is not null);

-- A person may read their OWN acceptances and nobody else's. There is no staff branch on
-- purpose: a warden has no operational reason to see when a resident agreed, and the operator's
-- need to evidence consent in a dispute is a service-role question, not an in-app screen.
--
-- A BARE uid CHECK, exactly like notifications_select in rls-policies.sql, and deliberately NOT
-- `user_id = auth.uid() or app.is_service_role()` — which is what this was first written as, and
-- which was wrong twice over. Measured on the live project:
--
--   1. It is redundant. `service_role` is a BYPASSRLS role (pg_roles.rolbypassrls = true), so it
--      already reads every row without any policy naming it.
--   2. It BREAKS THE ANONYMOUS CASE. `anon` holds no EXECUTE on app.is_service_role(), so the
--      disjunct raised `42501 permission denied for function is_service_role` instead of
--      evaluating to false — turning "no rows for a caller with no session" into a hard error on
--      the one read that decides whether a consent gate appears.
create policy legal_acceptances_select on public.legal_acceptances for select
  using (user_id = auth.uid());

-- NO INSERT, UPDATE OR DELETE POLICY, ANYWHERE, INCLUDING FOR THE ROW'S OWN SUBJECT.
--
-- RLS is deny-by-default, so their absence is the rule: the only way a row gets in is
-- accept_legal_terms() below, running as definer. That is what makes the timestamp worth
-- something. Were there a self-INSERT policy, the person whose consent is being evidenced could
-- choose its `accepted_at`, name a surface they never used, or delete the row and re-agree
-- later with a fresh date — and every one of those defeats the point of writing it down.

-- ═══ 4. THE ONE WAY IN ═══

create or replace function public.accept_legal_terms(
  p_version     text,
  p_surface     text default null,
  p_app_version text default null
) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  v_user     uuid := auth.uid();
  v_accepted timestamptz;
begin
  if v_user is null then
    raise exception 'Not signed in.' using errcode = '42501';
  end if;

  -- The version must be one that was actually published. This is the check that makes the FK
  -- above a message rather than a constraint violation: a client shipped ahead of its migration
  -- would otherwise fail with 23503 and a screen would render it as "something went wrong".
  --
  -- DEPLOYMENT ORDER FOLLOWS FROM THIS: publish the version row (a migration) BEFORE releasing
  -- an app build that ships that version string. The other order locks every user out at the
  -- gate, because the only thing they may do is agree and agreeing is what raises.
  if not exists (select 1 from public.legal_versions lv where lv.version = p_version) then
    raise exception 'Unknown legal document version %.', p_version using errcode = '22023';
  end if;

  -- Idempotent by (user_id, version). The FIRST acceptance is the fact; a repeat — a double
  -- tap, a retry after a timeout whose write actually landed — must not move the timestamp.
  insert into public.legal_acceptances (user_id, version, surface, app_version)
  values (v_user, p_version, p_surface, p_app_version)
  on conflict (user_id, version) do nothing
  returning accepted_at into v_accepted;

  -- ALREADY ACCEPTED: return the ORIGINAL timestamp and write NOTHING further.
  --
  -- Measured on the live project before this early return existed: two calls in a row left one
  -- acceptance row and TWO `legal.accept` audit rows. Harmless to the gate, and actively
  -- misleading in the one record that exists to settle a dispute — a reader of the audit trail
  -- would see a person agreeing twice, seconds apart, and reasonably wonder what changed
  -- between the two. Nothing did. The second call was a double tap.
  if v_accepted is null then
    select la.accepted_at into v_accepted
      from public.legal_acceptances la
     where la.user_id = v_user and la.version = p_version;
    return v_accepted;
  end if;

  -- A second, independent trace in the platform's own audit trail, written only when an
  -- acceptance actually happened. The acceptance row is the durable evidence; this is what puts
  -- the event in the same timeline as the sign-in that preceded it, for anyone reading the log
  -- rather than the table.
  insert into public.audit_log (actor_user_id, actor_role, action, target_type, target_id, hostel_id, meta)
  select v_user, u.role, 'legal.accept', 'legal_version', p_version, u.hostel_id,
         jsonb_build_object('surface', p_surface, 'app_version', p_app_version)
    from public.users u
   where u.id = v_user;

  return v_accepted;
end $$;

-- The blanket grant/revoke pair in schema.sql runs before this function exists, so both halves
-- are restated. `anon` must not hold EXECUTE: a refused FUNCTION is how the app's failure
-- classifier tells a dead session apart from a role refusal.
--
-- NOTE THERE IS NO ASSURANCE (aal2) REQUIREMENT. Residents never enrol a second factor, and
-- consent is the gate that stands in front of the whole product for every role — requiring
-- aal2 here would make the app unusable for the majority of its users.
revoke execute on function public.accept_legal_terms(text, text, text) from public, anon;
grant  execute on function public.accept_legal_terms(text, text, text) to authenticated, service_role;

-- ═══ 5. A NOTE FOR THE RETENTION JOB ═══
--
-- app.apply_retention() must NOT sweep public.legal_acceptances on a time basis. A consent is
-- not operational exhaust that ages out; it is the lawful basis for everything else the
-- platform holds about that person, and it has to remain true for as long as the account it
-- authorises exists. It is already bounded correctly without a sweep: the ON DELETE CASCADE on
-- user_id means erasing a person erases their consent rows in the same statement, which is both
-- the right privacy outcome and the reason no dedicated retention step is needed here.
--
-- public.legal_versions must never be swept at all — a version row is the target of a foreign
-- key from every acceptance that names it, and it is published text, not personal data.

-- ═══ 6. THE CURRENT PUBLISHED VERSION ═══
--
-- Seeded here rather than in db/seed.ts because it is not demo data: it is the row without
-- which the live gate cannot be satisfied by anybody. Idempotent, so a re-run of this migration
-- does not disturb a version that is already published and already accepted.
insert into public.legal_versions (version, effective_at, terms_url, privacy_url, summary)
values (
  '2026-09-02',
  timestamptz '2026-09-02 00:00:00+05:30',
  'https://hostelpro-three.vercel.app/legal/terms',
  'https://hostelpro-three.vercel.app/legal/privacy',
  'First version presented behind the in-app consent gate. Adds the consent record itself to '
  'the privacy policy, and aligns the published retention periods with app.apply_retention().'
)
on conflict (version) do nothing;
