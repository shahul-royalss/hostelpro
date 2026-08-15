---
name: database-design
description: Senior-level database engineering judgment — engine selection (PostgreSQL default and when to deviate), schema design, indexing, migrations, transactions/isolation, ORM pitfalls, pooling, caching, scaling, and backups. Use when designing or reviewing a schema, choosing a database or cache, writing migrations, debugging slow queries/N+1/lock contention/replication lag, or planning a scaling or backup strategy.
---

# Database Design & Operations

## Core defaults

- **PostgreSQL for everything until a specific workload proves otherwise.** It does relational, JSONB documents, full-text search, pub/sub (LISTEN/NOTIFY), and queues (SKIP LOCKED) well enough to defer specialized stores for years.
- **Normalize to 3NF first; denormalize only with a profiler trace in hand.** Premature denormalization is a data-corruption engine with no undo.
- **Every table gets a primary key, `created_at`, `updated_at`.** Use bigint identity or UUIDv7 (time-ordered; random UUIDv4 fragments B-tree indexes at scale).
- **Constraints in the database, not only in app code.** FKs, NOT NULL, CHECK, UNIQUE — the DB is the last line of defense and the most reliable documentation.
- **Migrations are versioned, immutable once applied, and forward-only in spirit.** Down-migrations are for local dev; production rolls forward.
- **One connection pooler in front of Postgres in any serverless or many-process deployment.** PgBouncer (transaction mode) or RDS Proxy; app-side pools alone do not survive horizontal function scaling.
- **A backup you have never restored is a hope, not a backup.** PITR enabled, restores rehearsed.

## Choosing the engine

Default is PostgreSQL. Deviate only when the workload matches a row below — and usually *add* the specialized store next to Postgres rather than replacing it.

| Category | Reach for it when | Examples | Don't use it because |
|---|---|---|---|
| Document | Schema genuinely varies per record AND you rarely join; offline-first sync | MongoDB, DynamoDB (single-table) | "schemaless is faster to start" — Postgres JSONB covers 90% of this |
| Key-value | Sub-ms reads, ephemeral data: sessions, rate limits, hot counters, queues | Redis/Valkey | you need durability or queries — it's a cache/coordination layer, not a system of record |
| Wide-column | Write-heavy append streams at scale with known access paths (time-series, event logs, feeds) | Cassandra, ScyllaDB | you have relational queries — query-first modeling is mandatory and joins don't exist |
| Graph | Multi-hop traversals (3+ joins deep) are the *primary* access pattern: fraud rings, recommendations, dependency graphs | Neo4j | you have a few FK relationships — recursive CTEs handle shallow graphs fine |
| Search | Relevance ranking, fuzzy matching, faceting, log search | Elasticsearch/OpenSearch, Meilisearch, Typesense | you need "find rows containing X" — Postgres FTS + trigram indexes go far |
| OLAP | Aggregations over billions of rows, columnar scans, analytics dashboards | ClickHouse, BigQuery, Snowflake, DuckDB (embedded/local) | your OLTP reports are slow — try indexes/materialized views first; don't run analytics on the primary |

Rules of thumb:
- Every additional store adds an operational surface, a consistency boundary, and a sync pipeline. Two data stores means dual-write or CDC (e.g. Debezium) — budget for that before adopting.
- SQLite is a legitimate production choice for single-node, read-heavy, or embedded workloads (and via managed layers like Turso). Don't dismiss it; don't use it with many concurrent writers.
- MySQL is fine if the org already runs it well. Migrating a healthy MySQL fleet to Postgres is rarely worth it.

## Schema design

- Model the entities and relationships; let queries drive indexes, not table shape (that's the wide-column mindset — it comes with wide-column costs).
- **Natural vs surrogate keys:** surrogate PK by default; put a UNIQUE constraint on the natural key (email, slug, SKU). Natural keys as PKs propagate every business change into every FK.
- **CHECK constraints encode business rules cheaply:** `CHECK (price_cents >= 0)`, `CHECK (status IN (...))` or a Postgres enum (enums are cheap to add values to, awkward to remove — use a lookup table if the set churns).
- **Money:** integer minor units (cents) or `numeric`. Never float.
- **Time:** `timestamptz` always. Naive timestamps are a latent multi-region bug.
- **JSONB columns** are for genuinely variable attributes (user preferences, third-party payloads). The moment you filter or join on a JSONB field routinely, promote it to a real column. A JSONB column named `data` on every table is schema abdication.
- **Soft delete** (`deleted_at timestamptz`): default for user-facing data (recoverability, audit), but be honest about the tax — every query needs the filter (enforce via view or ORM default scope), unique constraints need partial indexes (`UNIQUE ... WHERE deleted_at IS NULL`), and FKs to soft-deleted rows still resolve. For high-volume or compliance-bound data, hard delete + audit/archive table is cleaner. GDPR erasure means soft delete alone is not enough.
- Denormalize with evidence: a measured slow join on a hot path, plus a plan to keep the copy correct (trigger, transactional dual-write, or acceptance of staleness — written down).

## Indexing

- Index: FK columns (Postgres does NOT auto-index them), columns in hot WHERE/JOIN/ORDER BY clauses. Don't index: low-cardinality flags alone, tiny tables, columns never queried.
- **Composite index column order: equality columns first, then the range/sort column.** An index on `(status, created_at)` serves `WHERE status = 'open' ORDER BY created_at`; `(created_at, status)` does not. Leftmost-prefix rule: that index also serves `WHERE status = ?` alone, but not `WHERE created_at > ?` alone.
- **Partial indexes** when queries always carry a predicate: `CREATE INDEX ... ON orders (user_id) WHERE status = 'pending'` — smaller, hotter, cheaper to maintain.
- **Covering indexes** (`INCLUDE (col)`) to get index-only scans on the hottest read paths. Verify with `EXPLAIN (ANALYZE, BUFFERS)`.
- Every index taxes every INSERT/UPDATE/DELETE and competes for cache and WAL. A table with 12 indexes is a write-amplification problem wearing a performance costume.
- Finding problems:
  - Missing: slow-query log / `pg_stat_statements` sorted by total time; look for seq scans on large tables in `EXPLAIN`.
  - Unused: `pg_stat_user_indexes` where `idx_scan = 0` over a representative window (include month-end jobs before dropping).
- `CREATE INDEX CONCURRENTLY` in production, always. It can't run inside a transaction — most migration tools need an explicit flag for this.

## Migrations

- Versioned files in the repo, applied in order, tracked in a schema table. Any mainstream tool (the framework's own, Flyway, dbmate, Alembic, Atlas...) — the discipline matters more than the tool.
- **Never edit an applied migration.** Checksums diverge, environments fork. Fix forward with a new migration.
- **Expand–contract for zero downtime.** Old code and new code run simultaneously during deploy; every migration must be compatible with both:
  1. *Expand:* add nullable column / new table / new index (CONCURRENTLY). Deploy code that writes both, reads old.
  2. *Migrate:* backfill in batches (thousands of rows per transaction, sleep between batches — one giant UPDATE locks the table and bloats WAL).
  3. *Contract:* switch reads, stop old writes, then — a release later — drop the old column.
- Renaming a column or changing its type in place is a breaking change; it's expand-contract with a new column. `NOT NULL` on an existing big table: add the constraint `NOT VALID`, then `VALIDATE CONSTRAINT` separately to avoid a long lock.
- Set a `lock_timeout` (a few seconds) in migration sessions so a DDL statement queued behind a long transaction fails fast instead of stalling every query behind it.
- Schema migrations ≠ data migrations. Long backfills run as scripts/jobs, not inside the deploy-blocking migration step.

## Transactions and isolation

| Level | Prevents | Notes |
|---|---|---|
| Read Committed (PG default) | dirty reads | Two reads in one txn can see different data; lost-update prone without row locks |
| Repeatable Read | + non-repeatable reads, phantoms (in PG) | PG implements as snapshot isolation; write-skew still possible |
| Serializable | + write skew, all anomalies | PG uses SSI: low overhead, but transactions can abort — **retry loop is mandatory** |

- Default Read Committed is fine for most CRUD. Escalate for invariants that span rows (account balances, seat inventory, uniqueness you can't express as a constraint).
- **`SELECT ... FOR UPDATE`** for read-modify-write on specific rows. Add `SKIP LOCKED` for job-queue patterns, `NOWAIT` to fail fast.
- Lock ordering: acquire rows in a consistent order (e.g. by id) across code paths or you will deadlock under load. Postgres detects and kills one — your app must retry.
- **Keep transactions short.** No network calls, no user waits inside a transaction. Long transactions hold locks, block VACUUM, and bloat tables — a 3-hour idle-in-transaction session can degrade the whole database.
- **Advisory locks** (`pg_advisory_xact_lock(key)`) for application-level mutual exclusion — cron singleton, per-tenant serialization — without locking rows. Prefer the `_xact_` variants; session-scoped ones leak through poolers.
- Optimistic concurrency (version column, `UPDATE ... WHERE version = ?`) beats pessimistic locking when contention is rare and holding locks across user think-time is impossible.

## ORM discipline

- **N+1 is the default ORM failure mode.** Detect: query log in dev (count queries per request; a list page should be O(1) queries, not O(rows)), APM in prod. Fix: eager-load the association (`select_related`/`prefetch_related`, `includes`, `JOIN FETCH`, dataloader in GraphQL).
- Lazy loading in a loop, in a serializer, or in a template is the same bug wearing three outfits. Some stacks let you disable lazy loading outside explicit opt-in — do it and make N+1 a loud error in tests.
- Don't hydrate full entities to read two columns; project (`values()`, `pluck`, DTO queries).
- **Drop to SQL** for: reporting/aggregation, window functions, CTEs, bulk UPDATE/INSERT...ON CONFLICT, anything where the ORM emits queries you can't predict. A parameterized SQL string in the repo is more maintainable than a 40-line query-builder chain that emits worse SQL.
- The ORM's migration autogenerate is a draft, not a decision. Read the generated DDL; it will happily rewrite a table or take an exclusive lock.
- Never interpolate user input into SQL — parameters only, even in "internal" scripts.

## Connection pooling

- Postgres connections are processes; each costs real memory and connection storms crush the server. `max_connections` is not the fix.
- App-side pool sizing: connections needed is closer to `cores * 2` than to concurrent users. Hundreds of app pool connections usually mean queueing at the DB instead of in the app.
- **Serverless breaks app-side pooling**: every function instance opens its own pool, and scale-out multiplies it. Fix: external pooler — PgBouncer in transaction mode, RDS Proxy, or the platform's pooled endpoint (Supabase/Neon expose one).
- Transaction-mode pooling caveats: session state (`SET`, prepared statements at session scope, session advisory locks, LISTEN) doesn't survive. Most modern drivers cope; verify yours.
- Set statement timeouts and idle-in-transaction timeouts at the role or pool level so one bad client can't camp on the pool.

## Caching

- Order of operations: **fix the query and indexes first.** A cache in front of a bad query converts a slow page into a stale, intermittently slow page.
- Layers, in order of preference: in-DB (materialized views, prepared plans) → app-level per-request memoization → shared cache (Redis/Valkey) → CDN/edge for anonymous reads.
- **Cache-aside with TTL is the default pattern.** Explicit invalidation is a distributed-systems problem; TTL is your safety net when (not if) invalidation misses a path.
- Key discipline: version your keys (`user:v2:{id}`) so a deploy that changes the cached shape doesn't have to flush; invalidate on write in the same code path that writes (or via CDC if writes have many entry points).
- Stampede protection on hot keys: per-key locking or probabilistic early refresh, or one expiring key takes the DB down at peak.
- Never cache what you can't afford to serve stale, and never treat the cache as the system of record: Redis persistence is a recovery convenience, not durability.

## Scaling path (in order — do not skip steps)

1. **Measure.** `pg_stat_statements`, slow-query log, APM. Most "we need to shard" conversations end at a missing index.
2. **Vertical scaling.** Boring, effective, buys years. A single modern Postgres node handles tens of thousands of TPS.
3. **Read replicas.** Offload reporting and read-heavy pages. **Replication lag is a correctness issue, not just latency**: read-your-own-writes breaks. Route by consistency need (session pinning after write, or read primary for the writing user) — not blindly by read/write.
4. **Partitioning** (declarative, by time or tenant) once tables hit hundreds of GB: partition pruning speeds queries, and dropping a partition beats `DELETE` for retention. Partition key must appear in most queries and in unique constraints.
5. **Sharding — last resort.** You lose cross-shard transactions and joins; resharding is a migration project. Before hand-rolling, consider extracting the one huge table to a purpose-built store, or a distributed-SQL engine (Citus, CockroachDB, Spanner-class) — accepting their own tradeoffs. If tenant-sharded is inevitable, pick the shard key (almost always tenant_id) early and put it in every table.

## Backups and recovery

- Automated daily base backups + WAL archiving = **PITR** (restore to any moment, which is what you need after `DELETE` without `WHERE` — the most common disaster is human, not hardware).
- **Test restores on a schedule.** Restore into a scratch instance, run row-count/checksum sanity queries, record how long it took. That duration is your real RTO; if it's 6 hours, say so in the incident plan.
- Replicas are not backups (they replicate the bad DELETE instantly). Snapshots in the same account/region are not disaster recovery — keep at least one copy in a separate account/region with independent credentials.
- Define RPO/RTO explicitly per system and check the backup design against them; "we have backups" is not a number.
- `pg_dump` is fine for small DBs and pre-migration safety copies; it is not a PITR strategy.

## Anti-patterns → failures

| Anti-pattern | Failure it causes |
|---|---|
| EAV / one `data` JSONB for everything | Unqueryable data, no constraints, silent corruption |
| UUIDv4 PK on high-insert table | Index fragmentation, cache-miss writes, bloated WAL |
| No FK indexes | Every parent DELETE/UPDATE seq-scans the child table |
| Editing applied migrations | Environments diverge; prod-only failures |
| DDL without lock_timeout | One queued `ALTER TABLE` stalls all traffic behind it |
| Giant single-transaction backfill | Lock storm, replication lag spike, WAL blowout |
| ORM lazy loading in serializers | N+1: page latency scales with row count |
| Pool per serverless instance | Connection exhaustion at first traffic spike |
| Cache without TTL | Permanent staleness after any missed invalidation |
| Blind read/write splitting | Users don't see their own writes (lag) |
| Untested backups | Discovered unrestorable during the actual incident |
| Analytics on the OLTP primary | Reporting scans evict the hot working set; app latency spikes |

## Pre-ship checklist

- [ ] Every table: PK, timestamps, FKs indexed, constraints for invariants
- [ ] Hot queries `EXPLAIN (ANALYZE, BUFFERS)`-checked; no seq scans on large tables
- [ ] Migrations expand-contract safe against currently-deployed code; indexes CONCURRENTLY; `lock_timeout` set
- [ ] Backfills batched and resumable, separate from deploy
- [ ] Transactions short; retry logic for serialization failures/deadlocks where escalated isolation or locks are used
- [ ] N+1 check on list endpoints (query count asserted in a test, not eyeballed)
- [ ] Pooler in place; statement + idle-in-transaction timeouts set
- [ ] Cache keys versioned, TTLs on everything, stampede plan for hot keys
- [ ] Read-after-write paths identified before enabling replica reads
- [ ] PITR enabled; restore tested this quarter; RPO/RTO written down
- [ ] Soft-delete filter enforced centrally; partial unique indexes where needed
