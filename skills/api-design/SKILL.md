---
name: api-design
description: Senior-level API design judgment — REST resource modeling, status codes and RFC 9457 errors, pagination, protocol selection (REST/GraphQL/gRPC/webhooks/SSE), versioning and backward compatibility, OAuth2/OIDC and JWT pitfalls, idempotency keys, rate limiting, OpenAPI-first workflow, and webhook delivery. Use when designing or reviewing an HTTP/gRPC API, choosing between REST and GraphQL/gRPC/WebSockets, adding pagination or versioning, debugging auth/token/429/retry behavior, or building webhook producers or consumers.
---

# API Design

## Core defaults

Reach for these unless a listed exception applies. Every default has a one-line reason; the exceptions are in the sections below.

- **REST + JSON over HTTP** for anything consumed by more than one team. Ubiquitous tooling, cacheable, debuggable with curl.
- **OpenAPI 3.1 spec written first**, code generated or validated against it. The spec is the contract; code drift is caught by CI, not by consumers.
- **Cursor pagination** for any list that grows. Offset pagination breaks under concurrent writes and gets slow at depth.
- **RFC 9457 `application/problem+json`** for every error body. One error shape across the whole surface; clients write one handler.
- **URL path versioning (`/v1/`)** with additive-only changes inside a version. Boring, visible in logs, trivially routable.
- **OAuth2 client credentials or scoped API keys** for machine-to-machine; **Authorization Code + PKCE** for anything with a human. Never invent auth.
- **Idempotency-Key header** on every unsafe endpoint that a client might retry (payments, provisioning, sends). Retries happen whether you plan for them or not.
- **`RateLimit-*` headers + 429 + `Retry-After`** on every public surface. Clients cannot back off from limits they cannot see.
- **HMAC-signed webhooks with at-least-once delivery and exponential backoff.** Consumers must dedupe; you must retry.

## REST resource modeling

- URLs are **nouns**, plural, at most two levels of nesting: `/orders/{id}/items`. Deeper nesting means the child probably deserves a top-level collection with a filter (`/items?order_id=`).
- Verbs in URLs are a smell with one legitimate exception: operations that are genuinely not CRUD get a sub-resource action, e.g. `POST /orders/{id}/cancel`. Do not contort "cancel" into `PATCH {status: canceled}` if cancellation has side effects, validation, or its own failure modes — an action endpoint documents that.
- Method semantics are load-bearing: GET/HEAD safe and cacheable; PUT full replace, idempotent; PATCH partial update (use JSON Merge Patch, RFC 7396, unless you truly need JSON Patch's array surgery); POST for create and for actions; DELETE idempotent (second delete returns 404 or 204 — pick one, document it).
- Return the full resource on create (201 + `Location` header) and on update. Forcing a follow-up GET doubles latency for every writer.
- Model state transitions explicitly. A `status` field with documented transitions beats booleans (`is_active`, `is_deleted`, `is_archived`) that multiply into contradictory combinations.

### Status code discipline

| Situation | Code | Not |
|---|---|---|
| Created | 201 + Location | 200 |
| Accepted for async processing | 202 + status URL | 200 |
| Success, no body | 204 | 200 with `{}` |
| Malformed request (unparseable, bad types) | 400 | 422 |
| Well-formed but semantically invalid | 422 | 400 |
| Missing/invalid credentials | 401 | 403 |
| Valid credentials, insufficient permission | 403 | 401 |
| Resource absent, or hidden for authz reasons | 404 | 403 (403 leaks existence) |
| Conflict with current state (duplicate, version clash) | 409 | 400 |
| Rate limited | 429 + Retry-After | 503 |
| Upstream/dependency failure | 502/504 | 500 |

Never return 200 with `{"error": ...}` in the body — it defeats monitoring, retry logic, and caching all at once.

### Error format (RFC 9457)

```json
{
  "type": "https://api.example.com/errors/insufficient-funds",
  "title": "Insufficient funds",
  "status": 422,
  "detail": "Balance is 30.00, transfer requires 55.00.",
  "instance": "/transfers/abc123",
  "balance": 30.00
}
```

`type` is a stable identifier clients switch on — never make them parse `detail`, which you will reword. Extension members (like `balance` above) are legal and encouraged. For validation, add an `errors` array of `{field, message}` objects. Do not leak stack traces, SQL, or internal hostnames in `detail`.

## Pagination, filtering, sorting

- **Cursor** (opaque token encoding the last-seen sort key): default. Stable under inserts/deletes, O(1) at any depth. Cost: no "jump to page 7", no total count without a separate estimate.
- **Offset** (`?offset=200&limit=50`): acceptable only for small, mostly-static, admin-facing datasets where page numbers are a real UX requirement.
- Make cursors **opaque** (base64 of the key material). The moment a client can decode your cursor, its structure is your public API forever.
- Response envelope: `{ "data": [...], "next_cursor": "...", "has_more": true }`. Absent/null `next_cursor` means end. Always enforce a max `limit` (100 is a sane cap) — an unbounded limit is a self-DoS endpoint.
- Filtering: flat query params for the common cases (`?status=active&created_after=2026-01-01`). Resist a generic query language until multiple consumers demand it; if they do, that is a signal to consider GraphQL rather than inventing a worse one in query strings.
- Sorting: `?sort=-created_at,name` (leading `-` for descending). The sort field must be part of the cursor key or pagination breaks silently.
- Every paginated sort needs a **unique tiebreaker** (append `id`). Sorting on `created_at` alone skips or duplicates rows with equal timestamps.

## Protocol selection

Choose per consumer and workload, not per fashion. Mixing (REST public API + gRPC internally + webhooks for events) is normal and correct.

| Protocol | Pick when | Avoid when |
|---|---|---|
| REST | Public/partner APIs, CRUD-shaped domains, many heterogeneous consumers, cache-friendly reads | Real-time push; extremely chatty internal call graphs |
| GraphQL | One team owns a BFF for UIs with diverse view needs; underfetch/overfetch is a measured problem | Public API for third parties (rate limiting, caching, and abuse control get much harder); simple CRUD |
| gRPC | Service-to-service inside your perimeter; low latency, streaming, strong typed contracts via protobuf | Browser consumers (needs a proxy layer); public APIs for arbitrary third parties |
| Webhooks | Server-to-server event notification where the consumer runs a server | Consumers behind NAT/firewalls that cannot expose endpoints — offer polling too |
| SSE | Server-to-browser one-way push (feeds, progress, LLM token streams). Plain HTTP, auto-reconnect built in | Bidirectional needs |
| WebSockets | Genuinely bidirectional, low-latency (chat, collaborative editing, gaming) | Anything one-way — SSE is simpler to operate and load-balance |

Default trap: choosing GraphQL because the frontend team likes it, then discovering you own N+1 resolvers, query-depth limiting, persisted queries, and a bespoke caching story. That price is worth paying for a genuine BFF; it is not worth paying for a settings page.

## Versioning and backward compatibility

- Version in the URL path (`/v1/`). Header-based versioning is cleaner in theory and invisible in every access log, cache key, and support ticket in practice.
- Plan to almost never ship v2. A global v2 forks your docs, SDKs, tests, and support surface. Nearly everything can be done additively within v1.
- **Additive-only rules inside a version** — safe: new optional fields in responses, new optional request params, new endpoints, new enum values *only if you told clients to tolerate unknowns from day one*. Breaking: removing/renaming fields, changing types or formats, tightening validation, changing defaults, changing error `type` URIs, reordering enum semantics.
- **Expand–contract** for unavoidable field migrations: (1) expand — write both old and new fields; (2) migrate — clients move over, you watch usage metrics per field/per caller; (3) contract — remove the old field only when telemetry shows zero traffic, after the published deprecation window.
- Deprecation policy: announce with a date, emit `Deprecation` and `Sunset` headers on affected endpoints, log caller identity so you can email the stragglers by name. A deprecation nobody was told about is an outage you scheduled.
- Contract rule for clients you control: **be lenient in what fields you read (ignore unknowns), strict in what you send.** Put "ignore unknown fields" in your SDK docs on day one; it is what makes additive evolution safe.

## Auth

- **Authorization Code + PKCE**: every flow with a human — web apps, SPAs, mobile. The implicit grant is dead; do not use it.
- **Client credentials**: service-to-service where the caller is the principal.
- **Device authorization flow**: input-constrained devices (TVs, CLIs that pop a browser).
- **API keys**: fine for M2M when you need low ceremony — but scope them, prefix them for secret-scanner detectability (`sk_live_`-style), store only a hash, and support rotation with an overlap window (two keys valid at once) or every rotation becomes an outage.
- ROPC (password grant): never in new designs.

### JWT pitfalls (each has caused real incidents)

- **Expiry**: access tokens short (minutes to ~1h), refresh via the OAuth flow. There is no cheap revocation for a stateless JWT — if you need instant revocation, keep tokens short and/or check a denylist for high-value operations.
- **Audience**: validate `aud` (and `iss`) on every service. Without it, a token minted for service A replays against service B — a full privilege-escalation class.
- **Algorithm confusion**: never accept the token header's `alg` as authoritative. Pin the expected algorithm server-side and reject everything else, especially `none`, and reject RS256 tokens verified as HS256-with-the-public-key — the classic confusion attack.
- Validate on every request in every service; do not trust a gateway to have done it unless the gateway strips and re-mints internal identity.
- Don't put PII or secrets in claims — JWTs are readable by anyone who holds them.

## Idempotency for unsafe retries

Any POST a client might retry (timeout, crash, network blip) needs an `Idempotency-Key` header:

- Client generates a UUID per logical operation, reuses it on retry.
- Server stores `key -> (request_hash, response)` with a TTL (24h is a common choice). Same key + same request hash: replay the stored response, don't re-execute. Same key + different body: 422 — the client has a bug and must know.
- Concurrent duplicate (first request still in flight): 409 or block until the first completes; never run both.
- The dedupe store must be shared across instances (database or Redis with persistence) — per-instance memory silently fails behind a load balancer.
- PUT and DELETE are idempotent by definition; do not bother keying them. POST-that-creates and POST-actions with side effects are the targets.

## Rate limiting and quotas

- Return 429 with `Retry-After` (seconds) and rate-limit headers on **every** response, not just rejections — clients should self-throttle before hitting the wall. The IETF RateLimit header fields are standardizing; until your tooling emits them, the `X-RateLimit-Limit/Remaining/Reset` trio is the de facto convention. Pick one shape and keep it consistent.
- Limit per principal (key/token), not per IP — IPs are shared (NAT, corporate egress) and spoofable at the edge.
- Layer two mechanisms: short-window rate limits (protect infrastructure, token bucket allowing bursts) and long-window quotas (billing/fairness, e.g. requests per month). They fail differently and clients need to distinguish them — use the problem `type` to say which.
- Separate buckets for reads vs. expensive writes; one runaway report generator should not starve the client's normal traffic.
- Document limits publicly. Undocumented limits generate support tickets and retry storms instead of well-behaved backoff.

## OpenAPI-first and contract testing

- Write the spec before the handler. Review API changes as spec diffs — a reviewer can see a breaking change in a 10-line YAML diff that is invisible in a 400-line handler diff.
- CI gates: (1) lint the spec (Spectral or equivalent) with rules for naming, error shapes, pagination envelope; (2) **breaking-change detection** against the base branch (oasdiff or equivalent) — this is the single highest-value automation in API governance; (3) validate real request/response traffic against the spec in integration tests, so the spec cannot rot.
- Generate server stubs/validators and client SDKs from the spec rather than hand-maintaining both sides.
- For consumer-driven contracts between internal teams, Pact-style testing catches "provider changed, consumer broke" before deploy. It is heavier-weight; reserve it for service pairs where breakage is expensive and teams are decoupled.
- Exception to spec-first: genuinely exploratory internal prototypes. Write the spec when the second consumer appears — that is the moment it becomes a contract.

## Webhook delivery design

Producer side:

- **Sign every delivery**: HMAC-SHA256 over `timestamp + "." + raw_body` with a per-endpoint secret; send signature and timestamp in headers; receiver rejects skewed timestamps (>5 min) to kill replays. Sign the raw bytes — receivers must verify **before** JSON parsing, because parse/re-serialize changes the bytes.
- **At-least-once + retries**: exponential backoff with jitter over hours to ~a day (e.g. 1m, 5m, 30m, 2h, 8h, 24h). Treat only 2xx as success; treat a timeout as failure. After exhaustion, park in a dead-letter state visible in a dashboard with manual redrive.
- **Do not promise ordering.** Deliveries race and retries reorder. Instead: include the full current resource state (or a `fetch this resource` pointer) plus a monotonic sequence/updated-at, so a stale event is detectable and harmless. Consumers apply "ignore if sequence older than what I have."
- Include a unique `event_id` for consumer-side dedupe, and an event `type` namespaced like `invoice.paid`.
- Disable endpoints that fail for days, and notify the owner — hammering a dead endpoint forever wastes your queue and their logs.
- Offer a polling/list-events endpoint as a fallback; webhooks are an optimization over polling, not a replacement for it.

Consumer guidance (when you're building the receiving side): verify signature, enqueue, return 200 immediately, process async. Doing real work inline in the webhook handler causes timeout → retry → duplicate-processing loops.

## Anti-patterns and the failures they cause

| Anti-pattern | Failure it causes |
|---|---|
| 200 + error in body | Monitors show green during outages; client retry logic never fires |
| Offset pagination on hot tables | Skipped/duplicated rows during writes; DB melts at page 10,000 |
| Client-decodable cursors | Cursor internals become unremovable public API |
| Enum returned to clients that crash on unknown values | Every enum addition is a breaking change forever |
| No `Idempotency-Key` on payment/provision POSTs | Double charges and duplicate resources on every network blip |
| Validating JWT `exp` but not `aud`/`iss` | Cross-service token replay; privilege escalation |
| Accepting the JWT header's `alg` | `none`/HS256 confusion — full auth bypass |
| Rate limiting by IP only | One corporate NAT's traffic blocks a thousand innocent users |
| Webhook handler does work inline before responding | Timeouts trigger retries; events processed 2–5x |
| Promising webhook ordering | Consumers build on a guarantee retries physically cannot honor |
| Breaking-change detection absent from CI | Consumers discover your "minor release" in their pager |
| Hand-written docs separate from spec | Docs drift; every integration starts with a support ticket |

## Pre-ship checklist

- [ ] Every endpoint in the OpenAPI spec; CI runs lint + breaking-change diff against main
- [ ] All errors are `application/problem+json` with stable `type` URIs; no stack traces or internals in `detail`
- [ ] Status codes audited: 201/202/204 where applicable, 401 vs 403 vs 404 correct, no 200-with-error
- [ ] Every list endpoint: cursor pagination, enforced max limit, unique sort tiebreaker
- [ ] Unsafe POSTs accept `Idempotency-Key`; dedupe store is shared, TTL'd, and detects key-reuse-with-different-body
- [ ] AuthN/AuthZ: PKCE for humans, client-credentials or scoped hashed keys for machines; JWT validation pins alg and checks `aud`, `iss`, `exp` in every service
- [ ] Rate limits per principal; headers on all responses; 429 + `Retry-After`; limits documented
- [ ] Compatibility: clients told to ignore unknown fields; `Deprecation`/`Sunset` headers wired; per-caller field usage telemetry exists before you ever contract
- [ ] Webhooks (if any): HMAC-signed raw body + timestamp, retries with backoff + DLQ, `event_id` for dedupe, no ordering promise, polling fallback exists
- [ ] Timeouts, and retry-with-jitter guidance published for clients — an API without documented retry semantics gets whatever retry storm its clients improvise
