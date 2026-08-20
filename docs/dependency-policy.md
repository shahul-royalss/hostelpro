# Dependency policy

**Scope:** every third-party npm package in `package.json` / `package-lock.json`, and every GitHub Action referenced from `.github/workflows/`.
**Owner:** the maintainer named in [`.github/CODEOWNERS`](../.github/CODEOWNERS) — today a single person, see §5.
**Enforced by:** [`.github/dependabot.yml`](../.github/dependabot.yml) (updates), [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) (lockfile integrity + SBOM), [`.github/workflows/security.yml`](../.github/workflows/security.yml) (`npm audit`, secret scan).
**Current state:** `npm audit` reports **0 vulnerabilities** (verified 2026-08-20, both with and without `--omit=dev`). 549 packages in the full tree, 266 in the production tree.

A dependency is code you did not write, cannot review in full, and ship to your users anyway. This document is about keeping that trade honest.

---

## 1. Adding a dependency

Adding a package is a security decision, not a build decision. `npm install left-pad` is a two-word command that can add three hundred packages, each of which can run arbitrary code on the machine of every developer and every CI runner that installs it.

Before adding one, answer these. Put the answers in the PR description — the template asks for them.

| Question | Why it matters | Where to look |
|---|---|---|
| **Can the platform already do this?** | Node 22 and modern browsers cover UUIDs, hashing, `fetch`, date formatting, deep clone, structured clone. The cheapest dependency is the one not added. | `node:crypto`, `Intl`, `URL`, `structuredClone` |
| **How many packages does it actually pull in?** | The blast radius is the transitive tree, not the one name you typed. | `npm install --dry-run <pkg>` before committing |
| **Is it maintained?** | Last publish date, open issue count, and how many humans can publish. A single-maintainer package is a single account compromise away from being malicious. | npm page, GitHub Insights |
| **Does it run an install script?** | `preinstall`/`install`/`postinstall` execute on every `npm ci`, on every developer machine and every CI runner, before any of your code runs. This is the primary npm supply-chain attack path. | `npm view <pkg> scripts`; `node scripts/sbom.mjs` lists them |
| **Is it published with provenance?** | A provenance attestation ties the tarball to the source commit and the workflow that built it, so you are not trusting the publisher's laptop. | the "Provenance" badge on the npm page |
| **Does it need network or filesystem access at runtime?** | A formatting library that opens sockets is a finding, not a feature. | read the source of the entry point — for a small package this takes minutes |
| **License** | The SBOM records the SPDX id for every package. A copyleft transitive dependency in a proprietary SaaS is a legal problem discovered at exactly the wrong time. | `node scripts/sbom.mjs` then read the `licenses` field |

Two hard rules:

- **The lockfile ships in the same PR.** CI fails otherwise (§ *Lockfile integrity*, `docs/supply-chain.md` §4). A dependency change without its lockfile is not reviewable — you cannot see what actually got installed.
- **No new dependency for something a script can do.** `scripts/sbom.mjs` generates a full CycloneDX SBOM by parsing `package-lock.json`, specifically to avoid adding `@cyclonedx/cyclonedx-npm` and its transitive tree to the very dependency graph it is supposed to describe.

## 2. Updating dependencies

Routine updates are automated. Dependabot opens PRs weekly (Monday 07:00 UTC), grouped so that one week produces a handful of readable PRs rather than thirty:

| Group | Contents | Why grouped |
|---|---|---|
| `next` | `next`, `eslint-config-next`, `@next/*` | Pinned to the same exact version. Bumping one alone breaks `next lint`. |
| `react` | `react`, `react-dom`, `@types/react`, `@types/react-dom` | A matched runtime pair; the types must follow. |
| `radix-ui` | `@radix-ui/*` | ~15 packages, one publisher, one cadence. The largest single source of PR noise. |
| `production-minor-patch` | everything else that ships to users | Reviewed as production code. |
| `development-minor-patch` | everything else that does not | Lighter review — but see §3, dev is not free. |

**Majors are never grouped.** Each arrives as its own PR, because a major is a breaking-change review: read the changelog, read the migration guide, run the QA suites. Five majors batched into one PR guarantees that none of them gets read.

Before merging any dependency PR:

1. CI is green — this is the part that is mechanical, so let the machine do it.
2. Skim the actual diff of `package-lock.json`, not just the title. Look for: packages appearing that the PR never mentions, a `resolved` URL that is not `registry.npmjs.org` (CI fails on this, but know why), and a new `hasInstallScript`.
3. For a production bump, ask what the changed code does at runtime. For a `next` or `@supabase/*` bump, re-run the authorization suites — those two packages sit directly on the authorization path.

## 3. Vulnerability response SLA

The clock starts when the advisory becomes **visible to us** — a Dependabot alert, a red `npm audit` in CI, or the Monday 03:17 UTC scheduled run of `security.yml` — not when it was published upstream. The scheduled run exists precisely so that a newly-disclosed CVE surfaces within a week even if nobody commits anything.

| Severity | Production dependency (ships to users) | Dev dependency / build tooling only |
|---|---|---|
| **Critical** | Patched or mitigated **within 24 hours**. If no upstream fix exists, apply §4 the same day or take the feature offline. | 7 days |
| **High** | **7 days** | 30 days |
| **Medium** | **30 days** | Next scheduled dependency update |
| **Low** | Next scheduled dependency update | Next scheduled dependency update |

**A dev-dependency advisory is not a free pass.** It cannot reach a user at runtime, but it can reach the *build* — and a compromised build tool rewrites the bundle that ships. That is the actual shape of a modern supply-chain attack, so dev advisories get a longer clock, not an exemption.

`security.yml` enforces the floor mechanically: `npm audit --omit=dev --audit-level=critical` fails the build on a Critical production advisory, so that one cannot be merged past regardless of anyone's intentions. Everything below Critical is enforced by this document and by review, which is a weaker control — say so out loud rather than pretending the CI gate covers it.

**Reachability does not stop the clock.** It informs the fix, not the deadline. See the sharp case in §4: the code path is disabled in `next.config.ts`, and the package was still upgraded, because an argument that "our configuration makes this unreachable" has to be re-litigated on every audit, every config change and every framework upgrade — while a version bump is true forever.

## 4. When there is no fix you can reach: the `overrides` escape hatch

The awkward case is an advisory in a package you never installed directly, where the parent has not bumped it. You cannot fix that by changing your own dependency ranges, because npm resolves *the parent's* declared range for the parent's subtree.

Decision order, cheapest first:

1. **Upstream has fixed it** → bump the parent. Done, no special handling.
2. **Upstream has not, but the parent's range permits the fixed version** → `npm update <pkg>` and commit the lockfile.
3. **Upstream has not, and the parent's range cannot reach the fix** → `overrides` in `package.json`. This is the case below.
4. **The fixed version genuinely breaks the parent** → pin, document the exposure in `SECURITY.md`, open an upstream issue, and set a review date. Never silently `npm audit fix --force`, which resolves advisories by downgrading or breaking your tree and reports success.

### Worked example: the two `overrides` in this repo

`package.json` carries exactly two:

```json
"overrides": {
  "postcss": "^8.5.26",
  "sharp": "^0.35.3"
}
```

Neither is arbitrary. Both exist because option 2 was impossible.

**`postcss` — the parent used an exact pin.** `next@15.5.23` declares `"postcss": "8.4.31"` in its `dependencies`. That is an exact version, not a range, so nothing you do to your own dependency list can move it. This repo *also* lists `postcss: ^8.5.26` as a direct devDependency for Tailwind — and without an override that changes nothing for Next: npm would hoist 8.5.26 for Tailwind and nest a second copy of 8.4.31 under `node_modules/next`, still vulnerable, still in the build. The advisories that copy sits under (GitHub Advisory Database, checked 2026-08-20):

| Advisory | Severity | Affected | Fixed in |
|---|---|---|---|
| GHSA-r28c-9q8g-f849 / CVE-2026-73646 — path traversal in previous-source-map auto-loading | High | `<= 8.5.17` | 8.5.18 |
| GHSA-6g55-p6wh-862q / CVE-2026-45623 — arbitrary file read and information disclosure | High | `<= 8.5.11` | 8.5.12 |
| GHSA-fxqj-rqcc-2cmp / CVE-2026-69153 — incomplete fix of the above | Medium | `<= 8.5.22` | 8.5.23 |

`^8.5.26` clears all three, including the follow-up to the incomplete fix — which is the reason the override targets 8.5.26 rather than the 8.5.18 that closes the highest-severity item.

**`sharp` — the parent's range could never reach the fix.** `next@15.5.23` declares `"sharp": "^0.34.3"` in its `optionalDependencies`. GHSA-f88m-g3jw-g9cj (High, inherited libvips CVEs) affects `< 0.35.0`. A caret range on `0.34.x` cannot cross a minor boundary, so no amount of upstream patch releases would ever have delivered the fix into this tree. Only an override does.

**Verify an override actually took effect** — a stale one is worse than none, because it reads as protection:

```bash
node scripts/sbom.mjs
# sbom: npm overrides in effect: postcss -> 8.5.26 | sharp -> 0.35.3
```

The SBOM's dependency graph shows the result directly: `pkg:npm/next@15.5.23` now depends on `pkg:npm/postcss@8.5.26` and `pkg:npm/sharp@0.35.3`, and there is exactly one copy of each in the tree. `npm ls postcss sharp` gives the same answer in a less machine-readable form.

**Two things this example is meant to teach.**

*Unreachable is not uninstalled.* `next.config.ts` sets `images.unoptimized: true`, and the comment there notes it "removes the `sharp` dependency path entirely". True at runtime — and sharp is still downloaded, still on disk in CI and on every developer machine, still counted by `npm audit`, still in the SBOM, and still able to run an install script. `SECURITY.md` §3.7 item 20 records the call that was made and why: *"Previously argued as unreachable — closing them outright is cheaper than defending the reachability argument."* That is the general rule, not a one-off.

*An override is a fork you did not review.* You are forcing a version the parent never tested against. It is the right call here — both parents are loose consumers of these packages and the versions are semver-compatible — but each one is a standing bet that needs an exit. Delete an override the moment the parent's own range covers the fix; `sbom.mjs` printing "not installed" for an override name is the signal that it has gone stale.

**Every new override needs a row here** — the package, the advisory, why options 1–3 failed, and what would let it be removed. An `overrides` block without that context becomes cargo cult within one maintainer handover.

## 5. Ownership, and an honest note about it

Dependency review, SLA tracking and override review belong to the maintainer in `.github/CODEOWNERS`.

Today that is **one person**, which means the author of a dependency change is also its reviewer. Branch protection can require a review, but it cannot manufacture a second pair of eyes. The compensating controls are mechanical and worth naming, because they are what is actually holding:

- `npm audit --omit=dev --audit-level=critical` fails the build — not a judgement call.
- The lockfile-drift and registry-pinning gates in `ci.yml` fail the build — not a judgement call.
- The secret scan runs over the **full git history** on every push — not a judgement call.
- The weekly scheduled scan surfaces new advisories with no human trigger.

What is *not* covered by any of that, and therefore genuinely depends on one person's discipline: judging whether a new package is trustworthy, reading a lockfile diff for packages nobody asked for, and honouring the High/Medium SLAs. When a second maintainer joins, the first thing to change is `.github/CODEOWNERS` and the required-approvals count in branch protection (`docs/supply-chain.md` §2).
