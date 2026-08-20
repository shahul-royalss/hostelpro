# Supply chain and CI/CD controls

**Applies to:** the private GitHub repository backing HostelPro, and the Vercel project `dhrishta/hostelpro` that deploys from it.
**Companion:** [`docs/dependency-policy.md`](./dependency-policy.md) covers *which* dependencies are allowed and how fast advisories get fixed. This file covers *how a change gets from a laptop into production*, and what stands in its way.

`SECURITY.md` §5 carries an open Info item: *"No git remote, therefore no CI enforcement — `.github/workflows/security.yml` is committed and runs on push once a remote exists; enable branch protection + required checks + org MFA at that point."* That point is now. Everything in §1–§3 below is the settings work that item is asking for, and none of it lives in a file — it is repository configuration a human applies in the GitHub UI or API.

---


## Branch protection is NOT active — and cannot be, on this plan

This was attempted and **refused by GitHub**, twice:

```
PUT  /repos/shahul-royalss/hostelpro/branches/main/protection   -> 403
POST /repos/shahul-royalss/hostelpro/rulesets                   -> 403
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}
```

Branch protection and rulesets are paid features for **private** repositories. The repository is
private by choice (it is a commercial product with a client), so the only two ways to turn this on
are **GitHub Pro (~$4/month)** or making the source public. Until one of those happens:

| Intended control | Status | What actually stops a mistake today |
|---|---|---|
| Require PR before merge | **Not enforced** | Convention only. `git push` to `main` succeeds. |
| Require CI to pass before merge | **Not enforced** | CI still *runs* on every push and fails loudly — it just cannot *block*. |
| Require 1 approving review | **Not enforced** | Single-operator repo today; this becomes real the moment a second person commits. |
| Block force-push / deletion of `main` | **Not enforced** | Nothing prevents it. |
| Dependabot alerts | **Active** | Enabled via API. |
| Dependabot automated security fixes | **Active** | Enabled via API. |
| Delete branch on merge | **Active** | Enabled via API. |

**Do not read the CI badges as a merge gate.** They are a signal, not a guard. The distinction
matters: a green pipeline that cannot block a bad merge is exactly the false assurance this
document exists to prevent.

**To close this properly:** upgrade to GitHub Pro, then re-run the two API calls above — the exact
payloads are in this repo's history, and the required check names (`TypeScript`, `ESLint`,
`Next build`) match the job names in `.github/workflows/ci.yml`.


## 1. Repository settings

Apply these once, immediately after the first push. Settings → the named section.

| Setting | Value | Why |
|---|---|---|
| Repository visibility | **Private** | It is a multi-tenant SaaS with a live production database behind it. |
| Default branch | `main` or `master` | Both workflows already trigger on `branches: [main, master]`, so either is fine. Pick one and do not change it later — required-check history is per-branch-pattern. |
| **Dependabot alerts** | On | Without this, `dependabot.yml` still opens routine version PRs but nothing tells you about a *new advisory* between Mondays. This is the half that meets the Critical/24h SLA. |
| **Dependabot security updates** | On | Opens a fix PR automatically. These bypass the `open-pull-requests-limit: 5` in `dependabot.yml` — deliberately: routine bumps are rate-limited, vulnerability fixes are not. |
| **Secret scanning** | On | GitHub-side detection, independent of `scripts/security-scan.mjs`. Two detectors that fail differently are the point. |
| **Push protection** | On | Blocks a commit containing a recognised credential *at push time*. `security-scan.mjs` scans full history and catches it after the fact; push protection stops it reaching the remote at all, which matters because a pushed secret is a rotated secret even after you delete the commit. |
| **Private vulnerability reporting** | On | Gives a researcher somewhere to send a finding that is not a public issue. |
| Allow merge commits / squash / rebase | **Squash only** | One commit per reviewed PR keeps the full-history secret scan and `git log` legible. |
| Automatically delete head branches | On | Housekeeping. |
| **Require 2FA for all members** | On (org) / account-level 2FA (personal) | The realistic path to a compromised repo is a stolen maintainer credential, not a stolen `main`. |

## 2. Branch protection

Protect the default branch. Classic branch protection or a ruleset both work; the settings below are the classic names.

| Rule | Setting |
|---|---|
| Require a pull request before merging | **On** — no direct pushes to the default branch |
| Required approvals | **1** (raise to 2 when a second maintainer joins — see §6) |
| Dismiss stale approvals when new commits are pushed | **On** — an approval is of a diff, not of a branch name |
| Require review from **Code Owners** | **On** — this is what makes [`.github/CODEOWNERS`](../.github/CODEOWNERS) binding rather than advisory |
| Require approval of the most recent reviewable push | **On** — stops "approve early, push the real change after" |
| Require conversation resolution before merging | **On** |
| Require status checks to pass | **On** (list in §3) |
| Require branches to be up to date before merging | **On** — otherwise two individually-green PRs can merge into a broken `main` |
| Require signed commits | Optional. Turn it on if every contributor has signing configured; a rule people cannot satisfy gets disabled, which is worse than not having it. |
| Require linear history | **On** (pairs with squash-only merges) |
| **Do not allow bypassing the above settings** | **On** — this is the one that matters. Without it, admins bypass everything above, and on a small repo everyone is an admin. |
| Allow force pushes | **Off** — force-push to the default branch rewrites the history the secret scan walks |
| Allow deletions | **Off** |

> **`.github/` is self-referential.** Whoever can merge a change to `.github/workflows/` can delete a gate. That is why "Do not allow bypassing" is not optional here, and why `/.github/` has its own CODEOWNERS entry.

## 3. Required status checks

Add all seven. Names below are the job `name:` values — that string *is* the check context, which is why every job name in this repo is unique across all three workflows (`security.yml` already has a job called `Production build`, so the CI one is called `Next build`). Two jobs sharing a name are indistinguishable to branch protection, and either one passing would satisfy the rule. Keep new job names unique.

`backup.yml` contributes no required check: it runs on a schedule and on `workflow_dispatch`, never on a pull request, so it has no status to report against a PR head commit.

From **`ci.yml`** — does this commit compile, lint, build, and install cleanly?

| Check | Proves |
|---|---|
| `TypeScript` | `tsc --noEmit` passes under `strict` |
| `ESLint` | `next lint` passes across the whole project |
| `Next build` | A production build completes |
| `Lockfile integrity + SBOM` | `npm ci` succeeds, the lockfile did not drift, every package resolves to `registry.npmjs.org`, and a valid CycloneDX SBOM is produced |

From **`security.yml`** — is this commit safe?

| Check | Proves |
|---|---|
| `Types, lint, SAST` | `eslint-plugin-security` rules pass over `app components lib hooks db middleware.ts` |
| `Secret scan, backdoor audit, dependencies` | No credential in the working tree **or anywhere in git history**, backdoor audit clean, no Critical production advisory |
| `Production build` | No server secret reached `.next/static` |

A required check only becomes selectable in the UI after it has run at least once, so push a throwaway PR first, then add the checks.

## 4. What these gates actually prove — and what they do not

Being precise about this is the difference between a gate and a green badge.

**They prove:**

- The committed lockfile is the one `npm ci` resolves. The gate runs `npm ci` (which refuses outright when `package.json` and `package-lock.json` disagree) and then asserts `git diff` on both files is empty. *Canary-verified:* a one-field hand-edit to `package-lock.json` turns the job red with the offending hunk printed.
- Every package in the tree comes from `registry.npmjs.org`. The check parses each `resolved` URL and compares the **host**, so a look-alike domain such as `registry.npmjs.org.evil.example` fails — a substring grep would have passed it. *Canary-verified.*
- Every tarball matched its recorded integrity hash, because that is what `npm ci` does on install.
- Every third-party package is enumerated with version, license, integrity hash and dependency edges, in the SBOM artifact attached to each run.
- No secret is in the working tree or in any commit reachable from the branch.
- The app type-checks, lints, and builds for production, and no server secret reached the client bundle.

**They do not prove:**

- **That any authorization control works.** `_qa-rls-attack.mjs` (80 cases), `_qa-tenant-integrity.mjs` (32), `_qa-prod-authz.mjs` (145) and `_qa-mfa.mjs` all need live Supabase credentials and a deployed target, so **none of them run in CI** and none can. Every Critical in `SECURITY.md` §3 would have sailed through a green CI run. These suites are a human step, which is why the PR template asks for their output by name. Do not read a green tick as "authorization is fine".
- **That a dependency is not malicious.** Provenance is not verified, and install scripts run. Three packages in this tree run one — `esbuild`, `fsevents`, `unrs-resolver` (listed by `node scripts/sbom.mjs`). `npm ci --ignore-scripts` would close that hole and is worth revisiting, but it needs testing against those three first; it is not currently used, and pretending otherwise would be worse than the gap.
- **That the deployed artifact is the audited one.** See §5.
- **That the SBOM is signed or attested.** It is generated at build time and uploaded as a run artifact. It is an inventory, not evidence.

## 5. The Vercel gap — read this one

**GitHub Actions does not gate the Vercel deploy.** Vercel's Git integration builds and deploys on push, on its own, in parallel with CI. A commit whose CI is red still deploys unless something stops it. That is the largest hole in this pipeline and it is closed by configuration, not by a file in this repo:

- Require the pull-request flow (§2) so nothing lands on the default branch without passing checks first. This is the main mitigation: if only reviewed, green commits reach the branch Vercel deploys from, the ordering problem mostly disappears.
- In the Vercel project, restrict **Production** deployments to the default branch, and treat every other branch as a preview.
- Optionally set a **Ignored Build Step** command so Vercel skips the build for commits that should not deploy.
- Application production environment variables live only in Vercel's environment settings, never in GitHub.

### Repository secrets inventory

**Every gate in `ci.yml` and `security.yml` runs on public inputs alone and references no secret.** That is deliberate and worth preserving: it means pull requests from forks are fully covered by the same checks, and a compromised action inside a gate job has no token to steal. Keep it that way — a gate that needs a credential is a gate that silently stops running on exactly the PRs you trust least.

`backup.yml` is the exception, and legitimately so: it cannot dump a database without credentials.

| Secret | Referenced by | Exists in repo settings? |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `backup.yml` (mapped to the `SUPABASE_URL` env var the script reads) | Yes — created |
| `SUPABASE_SERVICE_ROLE_KEY` | `backup.yml` | **No — must be created.** This is the full-bypass key: it defeats every RLS policy in `db/schema.sql`. Treat it as the highest-value credential in the project. |
| `BACKUP_ENCRYPTION_KEY` | `backup.yml` | **No — must be generated and created.** Store the only other copy offline; losing it makes every backup unreadable. |
| `GITHUB_TOKEN` | implicit, all workflows | Automatic. Scoped to `contents: read` in `ci.yml` (§7). |

None of the three exist yet — the repository does not exist yet. Until they are added, **`backup.yml` will fail on its first run**, because GitHub substitutes an empty string for a missing secret rather than erroring: the job proceeds with a blank URL and a blank key and fails somewhere less obvious than "secret not set". Create all three at Settings → Secrets and variables → Actions before enabling the schedule, and verify with one manual `workflow_dispatch` run.

Two consequences of `backup.yml` holding a service-role key, both of which fall out of §2 and §7:

- **Anyone who can merge a workflow edit can exfiltrate that key.** A three-line change to any job in that file can print it, base64 it, or POST it somewhere. This is why `/.github/` has its own CODEOWNERS entry, why "Do not allow bypassing the above settings" is not optional, and why the repository must stay private.
- **Never make `backup.yml` trigger on `pull_request`.** That would expose the secrets to code proposed by an outside contributor. Scheduled and `workflow_dispatch` triggers only.

When a workflow gains or loses a secret, update this table in the same PR — the PR template asks for it. An undocumented secret reference is a workflow that fails mysteriously for the next person.

## 6. Action pinning

Every `uses:` in `ci.yml` is pinned to a full 40-character commit SHA with the release tag in a trailing comment:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

A tag is a mutable pointer. Whoever controls the action's repository — or anyone who steals a maintainer token, which is how the `tj-actions/changed-files` compromise worked — can repoint `v4` at new code, and every workflow that references it picks that up on its next run with no diff, no PR, and nothing to review. A commit SHA is content-addressed and cannot be repointed, so an upgrade becomes a visible commit in *this* repo that a human approves.

Pinning does not mean going stale: the `# v7.0.1` comment is what Dependabot reads, and the `github-actions` entry in `dependabot.yml` opens a weekly PR that moves the SHA and the comment together.

**All three workflows are pinned to full commit SHAs.** The three action SHAs were resolved
from the GitHub API and each verified to be the tagged commit of its release before being
used, rather than copied on trust:

- `actions/checkout` v7.0.1 → `3d3c42e5aac5ba805825da76410c181273ba90b1`
- `actions/setup-node` v7.0.0 → `820762786026740c76f36085b0efc47a31fe5020`
- `actions/upload-artifact` v7.0.1 → `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`

**Pin `backup.yml` first.** It is the only workflow holding `SUPABASE_SERVICE_ROLE_KEY` (§5), so a repointed tag there is not a broken build — it is a full-bypass database credential handed to whoever repointed it, on a schedule, with no diff in this repo. The SHAs in the table below are the ones to use.

The SHAs used in `ci.yml` were resolved from the GitHub API on 2026-08-20 and each is the tagged commit of its release:

| Action | Version | SHA |
|---|---|---|
| `actions/checkout` | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-node` | v7.0.0 | `820762786026740c76f36085b0efc47a31fe5020` |
| `actions/upload-artifact` | v7.0.1 | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |

## 7. Workflow token permissions

`ci.yml` declares `permissions: contents: read` at the top level, so every job gets a `GITHUB_TOKEN` that can read code and nothing else. Without an explicit block the token inherits the repository default, which on older repositories is read/write across every scope — meaning a compromised action in any job could push commits, open releases, or edit issues.

Set the repository default to match: **Settings → Actions → General → Workflow permissions → Read repository contents permission**, and leave "Allow GitHub Actions to create and approve pull requests" **off**. A workflow that legitimately needs more should widen it per-job, in a reviewed diff.

Checkouts also pass `persist-credentials: false`. No job here pushes, so the token should not be left sitting in `.git/config` where a later step — or a dependency's install script — could pick it up.

While in that settings page, restrict which actions can run at all: **Allow enterprise/organisation actions, and select non-organisation actions and reusable workflows** → allow `actions/*`. This repo uses nothing else, and the allowlist means a typo-squatted action cannot be introduced by a workflow edit alone.

## 8. The SBOM

`scripts/sbom.mjs` generates a CycloneDX 1.6 SBOM by parsing `package-lock.json`. It has no dependencies of its own — deliberately, since installing a third-party tool to inventory your third-party tools enlarges the thing you are measuring.

```bash
node scripts/sbom.mjs              # 549 components -> sbom.json
node scripts/sbom.mjs --omit=dev   # 266 components, production tree only
node scripts/sbom.mjs --print      # stdout
```

It exits non-zero on a malformed lockfile or an internally inconsistent graph, so the CI step is a real check and not just artifact production. Each component carries its purl, resolved version, SPDX license, SHA-512 integrity hash converted to hex, install-script and dev/optional flags, and its position in the dependency graph.

The serial number is derived from a SHA-256 of the lockfile rather than randomly generated, so re-running against an unchanged lockfile produces a byte-identical file (set `SOURCE_DATE_EPOCH` to freeze the timestamp too). That makes the SBOM diffable, and lets a future check compare a freshly generated SBOM against a stored one.

CI attaches `sbom.json` to every run as an artifact with 90-day retention rather than committing it — 600 KB of generated JSON churning on every dependency bump makes real diffs unreadable. **`sbom.json` is not currently in `.gitignore`**; add `/sbom.json` to it so a local run does not end up staged by accident.

## 9. Known gaps

Listed rather than quietly omitted.

| Gap | Impact | Would close it |
|---|---|---|
| Authorization suites cannot run in CI | The controls that actually protect tenant data are verified by hand | A dedicated test Supabase project whose credentials are safe to hold as repository secrets |
| Install scripts execute on `npm ci` | 3 packages run code during install, on every runner | `npm ci --ignore-scripts`, after verifying `esbuild`, `fsevents` and `unrs-resolver` still work without theirs |
| `security.yml` and `backup.yml` use floating action tags | Mutable-pointer risk — and `backup.yml` holds the service-role key, so there it is credential exfiltration, not a broken build | Pin both to the SHAs in §6 (owned elsewhere) |
| `backup.yml`'s three secrets do not exist yet | Its first scheduled run fails, and GitHub substitutes empty strings rather than erroring, so the failure is indirect | Create all three, then verify with one manual `workflow_dispatch` run (§5) |
| SBOM is unsigned | It is an inventory, not evidence | Sign it, or publish build provenance attestations |
| Vercel deploys independently of CI | A red commit can deploy if it reaches the deploy branch | Branch protection (§2), plus production restricted to the default branch |
| Single maintainer | Author and reviewer are the same person | A second maintainer; then raise required approvals to 2 |
