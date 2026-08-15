---
name: cloud-architecture
description: Senior-level cloud architecture judgment across AWS, GCP, and Azure — service selection, compute/IaC/networking/data/security/reliability/cost decisions. Use when designing or reviewing cloud infrastructure, choosing between serverless/containers/VMs, writing Terraform/OpenTofu/CDK/Pulumi, setting up VPCs or load balancers, picking a database or queue, planning multi-region/DR, or debugging a surprise cloud bill.
---

# Cloud Architecture

## Core defaults

Opinionated starting points. Deviate only with a named reason.

- **Managed services over self-hosted** — undifferentiated ops work is where teams go to die. Self-host only when cost at scale or a hard feature gap forces it.
- **Terraform/OpenTofu for all infrastructure** — declarative, provider-agnostic ecosystem, largest module library. No console-clicking that outlives the incident that caused it.
- **Containers on a managed runtime (ECS Fargate / Cloud Run / Container Apps) for services** — serverless functions for event glue, VMs only when forced. Kubernetes only when you need its ecosystem, not as a default.
- **Postgres (managed: RDS/Aurora, Cloud SQL/AlloyDB, Azure Database for PostgreSQL) as the default database** — boring, portable, handles 95% of workloads. Reach for NoSQL by access pattern, not by scale anxiety.
- **Multi-AZ always; multi-region rarely** — multi-AZ is cheap insurance; multi-region is a program, not a checkbox.
- **IAM roles + OIDC federation, never long-lived keys** — static credentials are the number-one real-world breach vector.
- **One VPC per environment, private subnets for everything with a workload in it** — public subnets hold load balancers and NAT, nothing else.
- **Tag everything at the provider level from day one** — untagged infrastructure is unattributable spend and undeletable risk.
- **Single provider per system by default** — multi-cloud portability is a cost you pay up front for an option you rarely exercise. Provider-agnostic *thinking* (below) is free; provider-agnostic *runtime* is not.

## Service equivalence (the big three)

Use this to translate designs between providers, not to pretend they're interchangeable — semantics differ (noted where it bites).

| Capability | AWS | GCP | Azure | Watch out |
|---|---|---|---|---|
| VMs | EC2 | Compute Engine | Virtual Machines | ARM (Graviton/Axion/Cobalt) is the price-perf default when images support it |
| Managed containers | ECS on Fargate | Cloud Run | Container Apps | Cloud Run scales to zero natively; Fargate does not |
| Kubernetes | EKS | GKE | AKS | GKE Autopilot is the most managed; EKS leaves the most to you |
| Functions | Lambda | Cloud Run functions | Azure Functions | Cold starts, execution-time caps, payload limits all differ |
| Object storage | S3 | Cloud Storage | Blob Storage | Consistency is strong on all three now; egress pricing is not |
| Block storage | EBS | Persistent Disk | Managed Disks | EBS is AZ-locked; snapshots are the portability layer |
| Relational DB | RDS / Aurora | Cloud SQL / AlloyDB | Azure Database (Flexible Server) | Aurora/AlloyDB are Postgres-compatible, not Postgres — extensions differ |
| Serverless NoSQL | DynamoDB | Firestore / Bigtable | Cosmos DB | DynamoDB single-table design does not translate; Cosmos bills RUs |
| Queue | SQS | Pub/Sub | Service Bus / Storage Queues | Pub/Sub is pub-sub-first; SQS is queue-first — fan-out needs SNS on AWS |
| Event bus | EventBridge | Eventarc | Event Grid | Schema/filtering capabilities differ materially |
| Streaming | Kinesis / MSK | Pub/Sub / Managed Kafka | Event Hubs | Event Hubs speaks the Kafka protocol; Kinesis does not |
| CDN | CloudFront | Cloud CDN / Media CDN | Front Door / Azure CDN | Front Door bundles LB + WAF + CDN; CloudFront does not |
| L7 load balancer | ALB | Global External ALB | Application Gateway | GCP's LB is global by default; AWS/Azure are regional |
| L4 load balancer | NLB | Network LB (passthrough) | Azure Load Balancer | |
| DNS | Route 53 | Cloud DNS | Azure DNS | |
| Secrets | Secrets Manager | Secret Manager | Key Vault | Key Vault also holds keys/certs; AWS splits into KMS/ACM |
| KMS | KMS | Cloud KMS | Key Vault keys | |
| Private connectivity to services | VPC endpoints / PrivateLink | Private Service Connect | Private Endpoint / Private Link | |
| Identity for workloads | IAM roles | Service accounts + Workload Identity | Managed Identities | Same concept, wildly different policy languages |

## Compute selection: decide by workload shape

Fashion says serverless; the workload decides.

| Workload shape | Pick | Why |
|---|---|---|
| Spiky/event-driven, short tasks (<15 min), tolerates cold start | Functions (Lambda / Cloud Run functions / Azure Functions) | Pay-per-invocation wins; zero idle cost |
| Steady HTTP service, long-lived connections, custom runtime | Managed containers (Fargate / Cloud Run / Container Apps) | Predictable latency, no runtime caps, still no host management |
| High sustained utilization (>~60% around the clock) | VMs with commitments, or containers on committed capacity | Serverless premium is real; sustained load makes reserved VMs cheapest |
| Needs GPU, kernel modules, specific hardware, licensing tied to cores | VMs | Only tier with full host control |
| Large heterogeneous microservice fleet, needs operators/service mesh/custom schedulers | Kubernetes (EKS/GKE/AKS) | The ecosystem is the reason — not the orchestration itself |
| Batch/ETL | Managed batch (AWS Batch / Cloud Run jobs / Container Apps jobs) + spot | Spot/preemptible cuts 60–90% for interruptible work |

Decision rules:
- Functions become the wrong answer when: p99 latency matters and cold starts hurt; execution exceeds runtime caps; you're paying for high, steady concurrency (containers are cheaper); the code accretes into a monolith-per-function ("lambda pinball" architectures).
- Kubernetes is the wrong answer when the team is <~8 engineers or nobody owns the cluster. A managed container runtime does 90% of it with 10% of the ops. It's the right answer when you genuinely need multi-team platform primitives, custom controllers, or portable on-prem/cloud parity.
- VMs are not legacy. Databases you must self-host, stateful singletons, license-bound software, and GPU training all live here comfortably.

## IaC: non-negotiable

Everything that survives a week goes in code. Console changes are for experiments and incident response — then backported or destroyed.

- **Default: Terraform or OpenTofu.** OpenTofu (Linux Foundation fork, post-2023 license change) is a drop-in for standard usage; pick per org policy on the BSL license. HCL's constraint is a feature: reviewable diffs, no clever abstractions hiding a `for` loop that provisions 40 buckets.
- **CDK/Pulumi when**: the team is application engineers who own their infra, the constructs map to app concepts (a CDK construct wrapping "queue + DLQ + alarm" is genuinely good), or you need real testing of infra logic. Cost: state is CloudFormation (CDK) with its slower deploys and drift quirks, and general-purpose languages invite general-purpose complexity.
- **Never**: hand-written CloudFormation/ARM JSON for new work; click-ops as the source of truth; a single state file for the whole company.

Structure that scales:

```
live/
  prod/     # small root modules per env, per component
  staging/
modules/    # reusable, versioned; no env-specific values inside
```

- Remote state with locking (S3+DynamoDB or S3 native locking / GCS / Azure Blob). One state per env-per-component — blast radius of `terraform apply` should never be "everything".
- Plan in CI on every PR; apply only from CI via OIDC-federated role. Humans don't hold apply credentials.
- Pin provider and module versions. Unpinned providers are how Tuesday's no-op deploy destroys an ALB.
- Import or delete drift; never let it accumulate. Run scheduled `plan` to detect it.

## Networking fundamentals

- **VPC layout**: one VPC per environment (per region if multi-region). Plan CIDR blocks org-wide up front — overlapping CIDRs make peering/VPN impossible later and renumbering is a migration project. /16 per VPC, carve /20s per AZ-tier.
- **Subnets**: public subnets contain load balancers, NAT gateways, and bastion-replacements only. Every compute workload and database goes in private subnets. A "public EC2 instance with a security group" is one misconfigured rule from an incident.
- **Three tiers when it matters**: public (LB) / private-app / private-data, with security groups referencing security groups (not CIDRs) between tiers.
- **Load balancers**: L7 (ALB/App Gateway/GCP global ALB) for HTTP — routing, TLS termination, WAF attachment. L4 (NLB) for TCP passthrough, extreme throughput, or static IPs. Terminate TLS at the LB; re-encrypt to backends if compliance requires.
- **CDN in front of anything static or cacheable** — it's a cost play (egress via CDN is cheaper than direct) and a latency play. Put the WAF at the edge.
- **Private endpoints for cloud services**: traffic from your VPC to S3/DynamoDB/Secrets Manager etc. should use VPC endpoints (or PSC/Private Endpoint equivalents), not NAT → public internet. Gateway endpoints (S3/DynamoDB on AWS) are free and skipping them means paying NAT processing per-GB for S3 traffic — a classic five-figure mistake.
- **Egress control**: workloads that don't need internet egress shouldn't have a route to it. When they do, prefer one NAT gateway per AZ (cross-AZ NAT traffic costs money and couples AZ failure domains).
- **Cross-VPC**: peering for 2–3 VPCs; Transit Gateway / Network Connectivity Center / Virtual WAN once it's a mesh. Don't build a peering full-mesh past ~4 VPCs.

## Data layer: managed-first

Choose by access pattern, consistency need, and query shape:

- **Default: managed Postgres.** Relational integrity, rich queries, JSONB for the semi-structured parts. Aurora/AlloyDB when you need read-scaling and faster failover, accepting mild lock-in.
- **Key-value at scale with known access patterns** (session stores, high-write event data, single-digit-ms at any size): DynamoDB/Firestore/Cosmos. Commit to access-pattern-first modeling; these punish exploratory queries.
- **Cache**: managed Redis-compatible (ElastiCache/Valkey, Memorystore, Azure Cache). Cache-aside pattern; treat contents as losable.
- **Search**: managed OpenSearch/Elasticsearch or the provider's search service. Don't bolt full-text onto your OLTP database past small scale (Postgres FTS is fine until it isn't).
- **Analytics**: columnar warehouse (Redshift/BigQuery/Synapse or Snowflake/Databricks). Never point BI tools at the OLTP primary; replicate out (CDC or scheduled ELT).
- **Object storage is the system of record for blobs** — never store files in the database; store keys.

Self-host a database only when: a required extension/version is unavailable managed, at very large scale where managed markup dominates, or hard data-locality rules apply. Budget a real DBA-equivalent when you do.

## Security

- **IAM least privilege, enforced structurally**: scope roles to the workload, not the team. No `*:*` outside break-glass roles. Use permission boundaries / org policies / SCPs to cap what even admins can grant.
- **No long-lived credentials, anywhere**: humans use SSO with short sessions; CI uses OIDC federation (GitHub Actions → cloud role, no stored secrets); workloads use instance roles / Workload Identity / Managed Identities. An access key in an env var or repo is a finding, full stop.
- **Secrets in a secrets manager** (Secrets Manager / Secret Manager / Key Vault), injected at runtime, rotated. Not in env files, not in Terraform state as plaintext outputs (mark sensitive; prefer writing secrets *into* the manager and passing references).
- **Encryption defaults**: at-rest encryption on everything (it's free — turn on the checkbox and move on); customer-managed keys (CMK) only where compliance demands key control, because CMKs add rotation and access-management burden. TLS everywhere in transit, including service-to-service inside the VPC.
- **Network is a control, not the control**: private subnets + security groups + private endpoints, and IAM as the real perimeter. Assume the network is hostile.
- **Guardrails at the org level**: block public S3/storage by default at the account/org level, require encryption via policy, enable CloudTrail/audit logs org-wide, centralize logs to an account app teams can't write over.
- **Account/project separation is the strongest isolation primitive**: prod and non-prod in separate accounts/projects/subscriptions. Blast radius, billing clarity, and IAM simplicity all fall out of it.

## Reliability

- **Multi-AZ is the default, always**: LBs across ≥2 AZs, ASGs/services spread, databases with multi-AZ failover. The incremental cost is small; a single-AZ prod database is an outage with a scheduled date.
- **Multi-region is warranted only when** (need at least one, honestly assessed):
  - Contractual/revenue SLA that a single-region worst case (rare but real multi-hour regional events) genuinely breaks.
  - Data residency laws requiring data in specific geographies.
  - Latency: a global user base needing <~100ms — and then it's active-active by design, not DR.
  - Otherwise: backups + IaC that can rebuild in another region ("backup & restore" DR tier) covers most businesses at 1% of the cost.
- **Set RTO/RPO before designing DR, with the business, in writing**:
  - RTO (time to restore) and RPO (data-loss window) drive the tier: backup/restore (RTO hours-days) → pilot light (RTO tens of minutes–hours) → warm standby (minutes) → active-active (~zero, and 2x+ cost plus data-consistency complexity forever).
  - An unrehearsed DR plan is fiction. Game-day the failover at least annually or downgrade your claimed RTO.
- **Reliability basics that outrank multi-region**: health checks that check dependencies, graceful degradation, timeouts + retries with backoff and jitter, circuit breakers on downstream calls, DLQs on every queue consumer, idempotent handlers, and load-shedding. Most outages are self-inflicted (bad deploy, config change) — canary/rolling deploys with fast rollback buy more availability than a second region.

## Cost engineering

Treat cost as an architectural property, reviewed like performance.

- **Tag at creation, enforce by policy**: minimum set — `env`, `service`, `owner`, `cost-center`. Enforce with provider policy (tag policies / org policy / Azure Policy) and in Terraform:

```hcl
provider "aws" {
  default_tags {
    tags = { env = var.env, service = var.service, owner = var.owner }
  }
}
```

- **Budgets + anomaly alerts in week one**: per-account/project budgets with alerts at 50/80/100%, plus the provider's anomaly detection. Bill shock is a monitoring failure.
- **Rightsizing cadence**: monthly review of utilization; downsize anything under ~40% sustained. Prefer ARM instances where supported (~20-40% better price-perf). Commit (Savings Plans / CUDs / Reservations) only to the stable floor of usage — 1-year, then extend.
- **Spot/preemptible for anything interruptible**: CI runners, batch, stateless workers behind a queue.
- **The usual bill-shock traps**:
  - **NAT gateway data processing** — per-GB charge on all traffic through it. Fix: gateway VPC endpoints for S3/DynamoDB, private endpoints for chatty services, one NAT per AZ.
  - **Cross-AZ data transfer** — chatty microservices and Kafka replication across AZs add up silently.
  - **Egress to internet** — the tax on every architecture; CDN it, compress it, and question any design that ships bulk data out.
  - **Log ingestion** (CloudWatch/Cloud Logging/Log Analytics) — debug-level logs at scale can exceed compute cost. Sample, filter at the agent, set retention.
  - **Orphans**: unattached volumes, old snapshots, idle load balancers, unassociated static IPs, stopped-not-terminated VMs still billing disks.
  - **Storage without lifecycle policies** — set transitions to infrequent/archive tiers and expiry on day one; mind per-request and retrieval fees before archiving hot data.
  - **Forgotten non-prod** — schedule dev/staging to stop nights and weekends; that's ~70% of the hours.
  - **Serverless at sustained high volume** — per-invocation pricing crossed the container break-even long ago; re-check quarterly.

## Anti-patterns → failure they cause

- **Console-built prod ("it was urgent")** → unreproducible environment; the rebuild during an incident takes days instead of one apply.
- **Shared account for prod and dev** → a dev script deletes prod data; IAM can't cleanly separate; bill is unattributable.
- **One giant Terraform state** → every apply risks everything; state lock contention stalls all teams; a corrupt state is a company-wide incident.
- **Static access keys in CI** → key leaks via log or fork PR; attacker has durable credentials; you find out from the bill or a ransom note.
- **Public subnet workloads with "tight" security groups** → one rule change or SG misreference exposes the service; no defense in depth.
- **Kubernetes because resume/fashion** → team of four spends half its time on cluster upgrades, ingress, and IAM-for-pods instead of product.
- **Microservices sharing one database** → schema change requires cross-team lockstep; you have a distributed monolith with network latency added.
- **Multi-region active-active without a data strategy** → split-brain writes or a global-lock bottleneck; you get lower availability than one region.
- **DR plan never rehearsed** → failover fails at 3am over an expired cert/missing quota/stale AMI; actual RTO is 10x the documented one.
- **Overlapping VPC CIDRs across teams** → the acquisition/peering/VPN you need in year two requires renumbering production.
- **No lifecycle policy on logs/objects** → storage grows monotonically; the cleanup project costs more than the storage ever should have.
- **Premature multi-cloud abstraction** → lowest-common-denominator services, doubled ops surface, and you still can't actually fail over between providers.

## Pre-ship checklist

Infra review before production traffic:

- [ ] All resources in IaC, state remote + locked, plan/apply via CI with OIDC (no human apply creds)
- [ ] Separate account/project per environment; org guardrails (public-storage block, encryption required, audit logging) active
- [ ] Workloads in private subnets; SGs reference SGs; private/gateway endpoints for high-volume service traffic
- [ ] TLS at the edge (managed certs, auto-renew); WAF on internet-facing L7
- [ ] No static credentials: workload identities, OIDC-federated CI, SSO for humans; secrets in a secrets manager
- [ ] Multi-AZ: LB, compute, and database failover verified (actually kill an instance/AZ once)
- [ ] Backups automated, retention set, **restore tested** — an untested backup is a hope
- [ ] RTO/RPO written down and signed off by the business; DR tier matches them
- [ ] Health checks, timeouts/retries with jitter, DLQs on consumers, idempotent handlers
- [ ] Alarms on: error rate, p99 latency, saturation, queue depth/age, DLQ non-empty — paging a human who can act
- [ ] Logs centralized with retention + sampling policy; tracing on cross-service paths
- [ ] Tags enforced (`env`, `service`, `owner`, `cost-center`); budgets + anomaly alerts live
- [ ] Lifecycle policies on object storage and logs; non-prod auto-stop schedule
- [ ] Load-tested to 2–3x expected peak; autoscaling verified both directions; provider quotas raised ahead of need
- [ ] Rollback path for app and infra changes proven, not assumed
