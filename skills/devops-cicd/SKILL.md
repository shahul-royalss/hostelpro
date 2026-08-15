---
name: devops-cicd
description: Senior DevOps/platform engineering judgment — CI/CD pipeline design (GitHub Actions, caching, matrices, OIDC), Docker image hygiene, Kubernetes vs PaaS decisions, environment promotion, secrets, release strategies, observability, SRE basics, and pipeline security. Use when building or reviewing CI/CD pipelines, writing Dockerfiles or workflow YAML, choosing deployment platforms, designing release/rollback strategy, setting up monitoring/alerting, or debugging slow/flaky/insecure pipelines.
---

# DevOps / CI-CD

## Core defaults

- **GitHub Actions** for CI/CD if code lives on GitHub — network effects, OIDC federation, and marketplace outweigh alternatives unless you have serious scale (then Buildkite) or self-host-everything constraints (then GitLab CI).
- **OIDC to cloud, never stored cloud keys** — short-lived tokens per job, nothing to rotate or leak.
- **Managed PaaS (Cloud Run, Fargate, Fly.io, Render) over Kubernetes** until you have a platform team or a concrete need K8s uniquely solves. K8s is an org commitment, not a deployment target.
- **Multi-stage Dockerfiles ending in slim or distroless, non-root** — smaller attack surface, faster pulls, most CVE scanners go quiet.
- **Trunk-based development with feature flags** — long-lived branches are where merge hell and stale environments come from.
- **Deploy ≠ release.** Ship dark behind flags; releasing is a config change, rollback is instant.
- **OpenTelemetry for instrumentation** — vendor-neutral; swap backends without re-instrumenting.
- **Alert on symptoms (SLO burn), not causes (CPU%)** — users don't page you about CPU.
- **Everything as code, PR-reviewed**: pipelines, infra (Terraform/OpenTofu or Pulumi), alerts, dashboards. Click-ops is unauditable and unreproducible.

## CI/CD pipeline design (GitHub Actions)

Pipeline shape: fast feedback first. Lint + typecheck + unit tests in parallel jobs (< 5 min), then build once, then deploy the *same artifact* through environments. Never rebuild per environment — you'd be testing one artifact and shipping another.

Concrete patterns:

- **Caching**: use the built-in cache options on setup actions (`setup-node`/`setup-python`/`setup-go` with `cache:` keyed on lockfile) before reaching for `actions/cache` manually. For Docker, use registry cache or BuildKit cache (`cache-from`/`cache-to: type=gha`). A cache keyed on something that changes every commit is worse than no cache — it uploads and never hits.
- **Matrices**: for version/OS coverage in libraries. For applications, test one pinned runtime — the one you deploy — and skip the matrix; it's cost without information.
- **Environments**: GitHub `environment:` gives you scoped secrets, required reviewers (manual prod gate), and deployment history. Put prod approval here, not in a bot comment convention.
- **OIDC**: `permissions: id-token: write` + the cloud vendor's credentials action, with a trust policy scoped to repo *and* environment/branch. A trust policy that accepts any repo in the org is a stored-key-sized hole.
- **Concurrency**: `concurrency:` group per branch with `cancel-in-progress: true` on CI; on deploy jobs, cancel-in-progress **false** — a cancelled half-applied deploy is worse than a queued one.
- **`workflow_dispatch`** on every deploy workflow. You will need to redeploy without a commit at 2am.

When GitHub Actions is wrong: monorepos needing fine-grained affected-target builds (use Bazel/Nx/Turborepo on top, or Buildkite), very long builds where hosted-runner pricing dominates (self-hosted runners — but treat them as production infra: ephemeral, patched, isolated from public PRs).

## Docker

Order layers by change frequency: base → system deps → dependency manifests + install → source → build. One inverted `COPY . .` before dependency install invalidates the dependency layer on every commit — most common cause of "Docker builds got slow".

```dockerfile
FROM node:22-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM gcr.io/distroless/nodejs22-debian12
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
USER nonroot
CMD ["dist/server.js"]
```

Rules:
- **Multi-stage always**; build toolchain never ships. Final stage: distroless or slim. Alpine is fine for Go/static binaries; musl bites Python/Node native deps.
- **Non-root user** in the final image. Required by hardened K8s admission policies anyway; free defense-in-depth everywhere else.
- **`.dockerignore`** with at least `.git`, `node_modules`/venvs, `.env*`, local build output. Missing it means slow contexts and secrets baked into layers.
- **Pin base images** by digest (or at minimum full version tag) and auto-bump via Renovate/Dependabot. `:latest` makes builds unreproducible.
- **Scan in CI** (Trivy or Grype) — fail on fixable critical/high in the final image, not the build stage. Also generate an SBOM at build time; retrofitting one during an incident is miserable.
- Never pass secrets as build args or ENV — they persist in layer history. Use BuildKit secret mounts for build-time credentials.

## Kubernetes — and when not to

Default: don't, until forced. Decision framework:

| Situation | Recommendation |
|---|---|
| < ~10 services, team has no dedicated platform engineer | Managed PaaS / serverless (Cloud Run, Fargate, Fly.io, Render) |
| Bursty/event-driven, tolerates cold starts | Serverless (Lambda, Cloud Run) |
| Need sidecars, custom operators, GPU scheduling, multi-tenant isolation, or vendor-portable workloads | Kubernetes (managed: EKS/GKE/AKS — never self-managed control planes) |
| "We might need K8s later" | PaaS now; containers make the migration cheap later |
| Stateful data services | Managed database/queue services, not StatefulSets, unless you operate databases for a living |

The honest test: K8s pays off when you're building an internal platform for many teams, or its ecosystem (operators, service mesh, custom schedulers) solves a problem you demonstrably have. If the driver is résumés or "industry standard", it's a tax: cluster upgrades, node patching, ingress/cert/DNS glue, RBAC sprawl — a standing platform-engineering cost.

If you are on K8s, non-negotiables: resource requests/limits on every workload, liveness *and* readiness probes (readiness gates traffic — wrong probes cause self-inflicted outages), PodDisruptionBudgets for anything with an SLO, GitOps delivery (Argo CD or Flux) rather than `kubectl apply` from CI — CI pushing kubectl commands means cluster state drifts the moment anyone hotfixes by hand.

## Environments and promotion

- Chain: **dev → staging → prod**, same artifact, config injected per environment. Staging must run the same infra shape as prod (same DB engine, same proxy) or it validates nothing; it will still differ in scale and data — accept that and rely on canaries for the rest.
- **Preview environments per PR** (PaaS previews, or ephemeral namespaces via Argo CD ApplicationSets) kill the "works on staging, three teams queued behind it" bottleneck. Tear down on merge; leaked previews become a surprise cloud bill and an unpatched attack surface.
- Promotion is moving an immutable version identifier (image digest) between environment configs — auditable, diffable, revertible. Not re-running a build.
- Config lives in the environment, not the image. Twelve-factor still holds.

## Secrets

- Runtime secrets in a cloud secret manager (AWS Secrets Manager, GCP Secret Manager, Vault), injected at deploy/runtime. GitHub Secrets only for what the pipeline itself needs — and OIDC removes most of those.
- No `.env` files in repos, images, or artifacts. Commit a `.env.example` with names only.
- Assume any secret that ever touched a log or layer is burned: rotate, don't debate.
- Prefer federation (OIDC) over any long-lived credential; prefer short-lived over long-lived; prefer scoped over broad. A "temporary" admin PAT in CI is permanent until it's an incident.
- Masking in CI logs is best-effort — encoded/transformed secrets slip through. Don't print config objects.

## Release strategies

**Instant rollback is a requirement, not a feature.** Any deploy design where rollback means "revert commit, rebuild, redeploy" (10+ min under pressure) fails this. Keep the previous artifact deployable at all times; database changes follow expand/contract (add nullable column → dual-write/backfill → cut over → drop later) so app rollback never needs a schema rollback.

| Strategy | Use when | Cost/catch |
|---|---|---|
| Rolling | Default for stateless services | Brief version mixing; ensure N and N-1 compatible (API + schema) |
| Blue-green | Cutover atomicity matters; instant full rollback | 2x capacity during deploy; in-flight connections and background jobs need draining |
| Canary | Enough traffic for signal; metrics-gated | Needs automated analysis (error rate, latency vs baseline) or it's theater |
| Feature flags | Decouple deploy from release; % rollouts; kill switches | Flag debt — expire flags aggressively; a 2-year-old flag is a config-driven fork of your codebase |

Low-traffic services can't canary meaningfully — use blue-green plus flags instead.

## Observability

- **Structured (JSON) logs** with trace/request ID on every line. Unstructured logs are grep-only; structured logs are queryable evidence.
- **Three signals via OpenTelemetry**: traces for "where is it slow/broken", metrics for cheap aggregates and alerting, logs for detail. Traces are the highest-leverage signal in distributed systems; add them before adding more logs.
- **Alert on symptoms**: SLO burn rate (fast + slow windows), user-facing error rate, latency. Cause-based alerts (CPU, memory, disk) become tickets/dashboards, not pages — with the exception of hard-ceiling predictions like "disk full in 4h".
- Every page must be **actionable and urgent**. A page someone acks and ignores trains the team to ignore pages; delete or demote it. Alert fatigue is how real incidents get missed.
- Instrument RED (rate, errors, duration) per service endpoint as the baseline; sample traces at the edge, always keeping errored and slow ones.

## SRE basics

- **SLOs** on user journeys (availability, latency), slightly stricter than what users notice, looser than perfection. 100% is not a target; every extra nine multiplies cost.
- **Error budget** = 1 − SLO. Budget healthy → ship fast. Budget burned → reliability work takes priority over features. This is the contract that ends the "move fast vs stability" argument — write it down with product, or the SLO is decoration.
- **Blameless postmortems** for every user-impacting incident: timeline, contributing causes (plural — single-root-cause thinking stops analysis early), action items with owners and dates. If postmortems assign blame, people hide information and you lose the only lasting value of an incident.

## Backup / DR

- **An untested backup is a hope, not a backup.** Schedule restore drills (quarterly minimum) that restore to a real environment and verify application-level correctness, not just "file exists".
- Define **RPO** (data loss tolerance) and **RTO** (downtime tolerance) per system, with the business, before choosing a strategy. These numbers pick the design: PITR replicas vs nightly snapshots vs cross-region failover.
- Backups must survive account compromise: separate account/project, immutability or delayed-delete. Ransomware that can delete your backups has already won.
- IaC + artifact registry + backups = you can rebuild the stack. If any step lives in someone's head, DR fails at the worst time. Config/state not in code (DNS, IdP, secret manager contents) needs its own backup story.

## Pipeline security

- **Least-privilege `GITHUB_TOKEN`**: set default `permissions: contents: read` at workflow level; grant per-job only what's needed. Default-writable tokens turn any compromised action into a repo-write.
- **Pin third-party actions to a full commit SHA** (`uses: some/action@<sha> # vX.Y.Z`), auto-updated by Renovate/Dependabot. Tags are mutable — tag-pinned actions have been hijacked in real supply-chain attacks. First-party `actions/*` at major tag is acceptable risk.
- **`pull_request_target` and untrusted input**: never check out and execute PR code under a privileged token, and never interpolate PR titles/branch names/issue text into `run:` scripts (shell injection) — pass via `env:`. Static-analyze workflows (e.g. zizmor) in CI.
- **Provenance**: generate signed build attestations (GitHub artifact attestations / SLSA-style provenance) linking artifact → commit → workflow, and verify at deploy time. This is what makes "where did this image come from" answerable during an incident.
- Self-hosted runners: never shared between public-PR workloads and privileged jobs; ephemeral per job.

## Pitfalls → failures they cause

- **Rebuilding per environment** → staging validated a different artifact than prod runs; "but it passed staging" incidents.
- **Shared mutable staging with manual pushes** → drift, queueing, and no one trusts it; testing moves to prod by default.
- **Stored cloud keys in CI secrets** → one leaked log or exfiltrating action away from full cloud compromise; keys outlive employees.
- **`COPY . .` before dependency install** → every commit is a cold build; teams start skipping CI.
- **Readiness probe checking downstream dependencies** → one flaky dependency marks every pod unready and takes the whole service down (self-inflicted cascading failure). Readiness = "can I serve", liveness = "am I deadlocked", nothing more.
- **Canary without automated analysis** → bad releases pass because a human glanced at a dashboard for 90 seconds.
- **Schema migration coupled to deploy** → rollback now requires a schema rollback; you've deleted your undo button.
- **Paging on CPU/memory** → alert fatigue; the real outage page gets acked on autopilot.
- **Flag debt** → hundreds of stale flags create untested code-path combinations; a "dead" flag flip causes an outage years later.
- **Backups never restored** → discovered corrupt/incomplete during the actual disaster; RPO becomes "everything since the last audit".
- **kubectl/ssh hotfixes outside GitOps/IaC** → drift; next deploy silently reverts the fix and the incident repeats.

## Pre-ship checklist

- [ ] CI: fast checks < 5 min; build once; same artifact promoted through all environments
- [ ] OIDC to cloud, trust policy scoped to repo + environment; no long-lived cloud keys in secrets
- [ ] Workflow `permissions:` least-privilege; third-party actions SHA-pinned
- [ ] Image: multi-stage, non-root, pinned base, `.dockerignore`, scanned, SBOM emitted
- [ ] Rollback path tested and < ~1 min (previous artifact redeploy or flag kill switch)
- [ ] DB migrations expand/contract; app N and N-1 both run against current schema
- [ ] Prod deploy gated (environment approval), `workflow_dispatch` escape hatch exists
- [ ] Health probes correct (readiness ≠ dependency check); resource limits set (if K8s)
- [ ] Structured logs with trace IDs; traces + RED metrics wired via OTel
- [ ] SLO defined, burn-rate alerts page, cause-alerts demoted to tickets
- [ ] Secrets in a secret manager, none in repo/image/logs; rotation story exists
- [ ] Backups scheduled *and a restore has actually been performed*; RPO/RTO written down
- [ ] Runbook link in the alert; postmortem template ready before you need it
