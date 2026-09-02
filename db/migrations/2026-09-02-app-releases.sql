-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-09-02 · APP RELEASES — the one row that says which build is current
-- ─────────────────────────────────────────────────────────────────────────────
--
-- WHAT THE OWNER ASKED FOR. "Create a link that they can install our application through, and
-- when I make changes they have to update through a notice on the old application." Those are
-- two halves of one fact — WHICH BUILD IS CURRENT AND WHERE IT IS — and this table is that
-- fact, written down once.
--
-- Both readers read THIS row:
--   · the Android app, on every cold start, through PostgREST (nivora_app/lib/core/version/)
--   · the public install page at /install on the Vercel app (app/install/page.tsx)
--
-- so the page and the phone can never disagree about what the latest build is. That mattered
-- enough to be the whole reason it is a row rather than a constant in two codebases.
--
-- ═══ WHY A ROW AND NOT A STATIC JSON FILE ═══
--
-- A JSON file on the Vercel app would need a git commit and a deploy to bump a version number
-- — and the moment publishing an update is a deploy, the version document drifts from reality
-- every time somebody uploads an APK and forgets the second step. This row is edited in the
-- Supabase dashboard's table editor (or with the one UPDATE in docs/app-distribution.md §4) and
-- takes effect on the next phone that opens the app. No deploy, nothing to forget.
--
-- ═══ ONE ROW, ENFORCED BY THE PRIMARY KEY ═══
--
-- `channel` is the primary key, so 'android' can only ever name one row. A releases table with
-- an id column and a `released_at desc limit 1` read has a failure mode this one cannot have:
-- two rows, one of them stale, and a client that picks the wrong one. Publishing is an UPSERT
-- that REPLACES the current release. The history is in `git log` and in the GitHub Releases /
-- storage bucket the binaries live in, which is where a history of binaries belongs.
--
-- ═══ ANON MAY READ IT, AND THAT IS DELIBERATE ═══
--
-- Nothing here is personal data: a version number, a public download URL, a file size, a
-- checksum. It is a PUBLIC release manifest — the whole point is that somebody with no account
-- can read it before they have installed anything. Two things follow:
--
--   · /install renders for a signed-out visitor (that route is added to PUBLIC_PATHS in
--     lib/supabase/middleware.ts — a page behind the auth redirect is invisible in production,
--     which has already happened once here with /verify-email);
--   · the phone can still check for an update when its access token has died and supabase is
--     therefore signing requests with the anon key (core/auth/session_standing.dart). An update
--     check that needs a live session is exactly the check that stops working on the phones
--     most likely to need a new build.
--
-- WRITES ARE SERVICE-ROLE ONLY. There is no INSERT/UPDATE/DELETE policy at all, so RLS denies
-- every write from `anon` and `authenticated` by default — and the explicit REVOKE below undoes
-- the blanket `alter default privileges ... grant all on tables to authenticated` from
-- schema.sql, which would otherwise hand `authenticated` table-level write privileges that only
-- RLS was standing in front of. Belt and braces, because a client that could write this row
-- could point every phone in the field at a binary of its choosing.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.app_releases (
  -- The store the build is for. Android only today; an 'ios' row is the natural extension and
  -- costs nothing but a value in this check.
  channel       text primary key check (channel in ('android')),

  -- What a person sees: "1.0.1". Matches pubspec.yaml's `version:` before the `+`.
  version_name  text not null check (version_name ~ '^[0-9]+(\.[0-9]+){1,2}$'),

  -- WHAT THE COMPARISON ACTUALLY USES, and the only field that decides whether a phone is out
  -- of date. It is pubspec.yaml's build number — the part after the `+` — which Flutter puts
  -- into the APK as android:versionCode. Android itself refuses to install an APK whose
  -- versionCode is not HIGHER than the installed one, so this is the same number the operating
  -- system is going to check; comparing anything else here would let the app promise an update
  -- that the installer then refuses.
  version_code  integer not null check (version_code > 0),

  -- Where the APK actually is. NULL until a binary has been uploaded somewhere public — which
  -- is a real state on the day the table is created, and both readers draw it as "not published
  -- yet" rather than as a dead button.
  download_url  text check (download_url ~ '^https://[^\s]+$'),

  -- Shown on the install page so somebody on a metered connection knows what they are about to
  -- spend, and so a download that stops early is visibly short.
  size_bytes    bigint check (size_bytes > 0),

  -- Lowercase hex sha256 of the exact file at download_url. Nobody is required to check it;
  -- it is here so that "is the file I have the file you published?" has an answer.
  sha256        text check (sha256 ~ '^[0-9a-f]{64}$'),

  -- TRUE turns the in-app banner from dismissible into blocking. Reserve it for a build that
  -- fixes something the old build gets WRONG — a bad rent calculation, a broken login — not for
  -- a build you would merely prefer people had.
  mandatory     boolean not null default false,

  -- One short paragraph of what changed, in the language a warden speaks. Shown on the install
  -- page and in the app's update sheet. NULL is fine and draws nothing.
  notes         text check (notes is null or length(notes) between 1 and 500),

  released_at   timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- A MANDATORY UPDATE WITH NOWHERE TO GET IT IS A LOCK-OUT. The blocking banner cannot be
  -- dismissed, so publishing `mandatory` before the binary is up would strand every phone in
  -- the field on a screen with no exit. The database refuses that arrangement outright rather
  -- than trusting whoever is typing at 1am to notice.
  constraint app_releases_mandatory_needs_url check (not mandatory or download_url is not null)
);

comment on table public.app_releases is
  'Public release manifest: which Android build is current and where to get it. One row per '
  'channel. Read by the app on cold start and by /install; written by the service role only.';

drop trigger if exists set_updated_at on public.app_releases;
create trigger set_updated_at before update on public.app_releases
  for each row execute function app.set_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.app_releases enable row level security;

drop policy if exists app_releases_select on public.app_releases;
-- `using (true)` and not `using (auth.role() = 'authenticated')`: see the header. A phone whose
-- token has expired asks as `anon`, and that is precisely the phone that needs a new build.
create policy app_releases_select on public.app_releases for select using (true);

-- No write policy, deliberately. RLS denies what it does not permit, so INSERT / UPDATE /
-- DELETE are closed to every role except the service role, which bypasses RLS entirely.

-- ── GRANTS ───────────────────────────────────────────────────────────────────
-- schema.sql runs `alter default privileges in schema public grant all on tables to
-- authenticated, service_role`, so this table was born with table-level write privileges for
-- `authenticated`. RLS was already the thing refusing those writes; this removes the privilege
-- as well, so the refusal does not depend on one policy staying correct.
grant select on public.app_releases to anon, authenticated;
revoke insert, update, delete, truncate on public.app_releases from anon, authenticated;

-- ── THE ROW ──────────────────────────────────────────────────────────────────
-- Seeded as the build that is in the field TODAY (pubspec.yaml says `version: 1.0.0+1`), with
-- no download URL, because no binary has been published yet. That combination is the correct
-- starting state and it is inert: every phone running build 1 compares 1 against 1, finds
-- nothing newer, and shows nothing. Publishing is the UPDATE in docs/app-distribution.md §4.
insert into public.app_releases (channel, version_name, version_code, mandatory, notes)
values ('android', '1.0.0', 1, false, null)
on conflict (channel) do nothing;

-- ── RETENTION: NOTHING TO DO, AND THAT IS ON PURPOSE ─────────────────────────
-- app.apply_retention() is not extended here. This table holds exactly one row for ever, it
-- carries no personal data, no IP and no user agent, and it does not grow. Adding a sweep for
-- it would be a step that can only ever report 0 rows.
