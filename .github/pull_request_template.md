# What and why

<!-- One paragraph. What changes, and what problem it solves. If it fixes an issue, "Closes #N". -->

## How it was verified

<!--
Say what you actually ran, and paste the real output. "Tested locally" is not verification.
CI proves the code compiles, lints, builds and installs from a clean lockfile — it does NOT
prove an authorization control works, because none of the QA suites can run in CI (they need
live Supabase credentials). Whatever CI cannot check, you have to check here.
-->

---

## Checklist

- [ ] `npm run typecheck` and `npm run lint` are clean locally
- [ ] No credential, token or key is in the diff — including in a test fixture, a comment or a commit message
- [ ] Anything new that reads user input validates it **server-side**, not only in the form

**If this PR touches RLS policies, triggers, or anything under `db/`:**

- [ ] `node scripts/_qa-rls-attack.mjs` — 80/80 blocked
- [ ] `node scripts/_qa-tenant-integrity.mjs` — 32/32 blocked
- [ ] The new policy was tested against **PostgREST directly**, not just through the app. The anon key and REST endpoint are public, so a control that exists only in React or only in middleware is worth nothing (SECURITY.md §2)

**If this PR changes roles, routes, or middleware:**

- [ ] `node scripts/_qa-prod-authz.mjs` — 145/145, run against the deployed site after the preview deploy is up

**If this PR adds, removes or upgrades a dependency:**

- [ ] `package-lock.json` is committed in the same PR (CI fails otherwise)
- [ ] `npm audit` is still 0 vulnerabilities
- [ ] I read what the new package actually is: weekly downloads, last publish date, maintainer count, whether it has an install script, and how many transitive packages it drags in — see `docs/dependency-policy.md` §1
- [ ] If this uses an `overrides` entry to force a transitive version, the reason and the upstream issue link are recorded in `docs/dependency-policy.md` §4

**If this PR changes a GitHub Actions workflow:**

- [ ] Every `uses:` is pinned to a full 40-character commit SHA with a `# vX.Y.Z` comment — never a tag (`docs/supply-chain.md` §3)
- [ ] The `permissions:` block is still the minimum the job needs
- [ ] No workflow references a secret that does not exist in repository settings

## Risk

<!--
What breaks if this is wrong, and how would you find out? If the answer is "nothing, it is a
copy change", write that. If the answer involves other people's data, say so explicitly and
name the blast radius: one user, one tenant, or every tenant.
-->
