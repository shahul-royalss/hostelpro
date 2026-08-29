# Security sign-off — NIVORA mobile release (nivora_app)

**Date:** 2026-08-29
**Scope:** the Flutter mobile app (`nivora_app/`) and the five Supabase Edge Functions it calls
(`supabase/functions/{owner-create-staff, razorpay-order, razorpay-webhook, sa-create-owner,
warden-register-student}` plus `_shared/`), at commit `7df8bca` on `main`.
**Method:** automated scanner run + manual client-side sweep + manual source review of the edge
functions. **No live/deployed system was exercised in this pass** — see §5, which is as much a
part of this sign-off as the verdict.
**Prior art:** `SECURITY.md` (audit rounds 1–3, 2026-08-17/20) covers the Next.js web app and the
live RLS attack suites. This document does not restate or re-verify those results.

---

## 1. Verdict, per the standing release rules

- **"Do not deploy to production while any Critical vulnerability is open."**
  → **No Critical vulnerability is open** in the scope above. The scanner reports 10 blockers;
  every one is classified in §3 with evidence, and none is a vulnerability in the deployed
  product (6 are test-fixture strings, 4 are a publishable test-mode key id).
- **"Do not deploy while any High vulnerability has no documented mitigation and owner."**
  → **No High vulnerability is open.** The two finding groups in §3 are Low/Informational and
  each carries a documented mitigation and a named owner anyway.
- **Deployment precondition that is NOT met yet:** the five edge functions are **not deployed**
  and their runtime secrets are not confirmed set (§5.1). Nothing in this sign-off attests to
  the live backend's behavior. Deploying the app before the functions (with the flags in §4.4)
  is a functional and security gap — the webhook that settles rent would not exist.

Sign-off holds **for the source at `7df8bca`**, conditional on the §5 items being closed by
their owners before or at release.

---

## 2. What was verified, with evidence

### 2.1 Scanner run (real output, unedited)

`node scripts/security-scan.mjs` from the repo root, 2026-08-29, exit code 1:

```
=== 2  SECRETS ===

  x BLOCKER  Hardcoded password assignment in a tracked file
      nivora_app/test/owner_staff_test.dart:572  password: 'Tx7-quiet-lamp',

  x BLOCKER  Hardcoded password assignment in a tracked file
      nivora_app/test/owner_staff_test.dart:689  password: 'Tx7-quiet-lamp',

  x BLOCKER  Hardcoded password assignment in a tracked file
      nivora_app/test/owner_staff_test.dart:773  password: 'Tx7-quiet-lamp',

  x BLOCKER  Hardcoded password assignment in a tracked file
      nivora_app/test/warden_register_student_test.dart:459  password: 'Sage-7413-Kite',

  x BLOCKER  Hardcoded password assignment in a tracked file
      nivora_app/test/warden_register_student_test.dart:631  password: 'Sage-7413-Kite',

  x BLOCKER  value of RAZORPAY_KEY_ID (.env) is committed in a tracked file
      docs/razorpay-in-app.md:128

  x BLOCKER  value of RAZORPAY_KEY_ID (.env) is committed in a tracked file
      nivora_app/test/payment_test.dart:35

  x BLOCKER  value of RAZORPAY_KEY_ID (.env) is committed in a tracked file
      nivora_app/test/receipt_test.dart:44
  . .env files are not tracked

  x BLOCKER  Hardcoded password assignment in git history
      +          password: 'Tx7-quiet-lamp',
      +      password: 'Tx7-quiet-lamp',
      +        password: 'Tx7-quiet-lamp',
      +              password: 'Sage-7413-Kite',
      +                  password: 'Sage-7413-Kite',

  x BLOCKER  value of RAZORPAY_KEY_ID (.env) appears in git history — rotate it
      +npx supabase secrets set RAZORPAY_KEY_ID=rzp_test_TTZjgz6pssJVJs

=== 13 CLIENT BUNDLE ===
  . no server secrets in client bundle (155 files scanned)

=== 15 AI-CODE / BACKDOOR AUDIT ===
  . no dangerous patterns across 247 source files
  . service-role client confined to 7 vetted modules
  . no client component imports a server-only module

=== 22 DEPENDENCIES ===
  . production dependency audit: none
  . dependency versions locked (package-lock.json)

==============================================================
  RESULT: 10 blocker(s), 0 warning(s)
==============================================================
```

The 10 blockers are dispositioned in §3. The scanner was **not** modified to make this pass
green; it still exits 1, and will until the fixture strings are allowlisted or renamed (§3.1).

### 2.2 Client-side sweep of `nivora_app/`

- **No Razorpay key SECRET anywhere.** `git grep` for `RAZORPAY_KEY_SECRET=<value>` patterns
  over tracked files: no hits. Full-history search (`git log -p --all -S "RAZORPAY_KEY_SECRET="`
  filtered to real-looking values): no hits. The only `rzp_…` string in the repo is the
  **key id** `rzp_test_TTZjgz6pssJVJs` (see §3.2). `nivora_app/scripts/release.sh:186` itself
  greps `lib/` for `RAZORPAY_KEY_SECRET` and aborts the build if found.
- **Every `eyJ…` literal decoded — none is service_role.** A repo-wide sweep of `nivora_app/`
  (all text files, excluding `build/`, `.dart_tool/`, `.git/`) finds JWT-shaped literals in
  exactly one file: `nivora_app/lib/core/config/env.dart:24`. Its payload base64-decodes to:
  `{"iss":"supabase","ref":"nimxvgzscbanhtvgnjll","role":"anon","iat":1785574366,"exp":2101150366}`
  — **`role":"anon"`**, the publishable anon key, safe in a client by design (RLS is the
  boundary). No other JWT literal exists in the app source.
- **No WebView, no url_launcher in app code.** Neither appears in `nivora_app/pubspec.yaml` as a
  direct dependency and neither is imported anywhere in `lib/` (the only grep hits are comments
  asserting their absence, e.g. `lib/features/student/pay_rent_sheet.dart:35-37`). Caveat:
  `url_launcher` **is present transitively** in `pubspec.lock` (pulled in by a plugin's
  dependency tree, not by app code); the plugin is compiled in but nothing calls it. Recorded as
  an open Low item (§3.3).
- **No secrets in `android/` gradle files.** Tracked files under `nivora_app/android/` include
  no keystore and no `key.properties` (`git ls-files` shows only `gradle.properties` — JVM args
  and two Flutter template flags — and the gradle wrapper). `android/app/build.gradle.kts:31-33`
  reads signing material from `NIVORA_KEYSTORE_*`/`NIVORA_KEY_*` environment variables or
  `~/.hostelpro-keys/keystore.properties`, both outside the repo.
- **No secret in `--dart-define` scripts.** The only build script is
  `nivora_app/scripts/release.sh`; it contains no key/secret values (and enforces the
  no-secret-in-lib rule itself, see above). `MIGRATION.md:118` shows `--dart-define` usage with
  placeholder `...` values only.

### 2.3 Server-side spot-check (source review — READ only, nothing deployed)

- **Caller verification is against `public.users`, not JWT claims.**
  `supabase/functions/_shared/caller.ts` (`requireCaller`, lines ~100-150): the bearer token is
  verified by GoTrue (`admin.auth.getUser(jwt)` — signature + expiry), then the **authoritative
  role/status/tenant is read from `public.users` with the service client**; `app_metadata`/role
  claims inside the JWT are explicitly never trusted. It also refuses the anon key and the
  service-role key presented as sessions by identity (`bearerToken()`), and gates on
  `status='active'`, `deleted_at`, and `must_change_password`. Used by:
  - `owner-create-staff/index.ts:81` → `requireCaller(req, "owner")`
  - `sa-create-owner/index.ts:140` → `requireCaller(req, "super_admin")`
  - `warden-register-student/index.ts:112` → `requireCaller(req, "warden")`
  - `razorpay-order/index.ts` (~lines 116-126) verifies the JWT with `auth.getUser(jwt)` and
    then does **all reads as the caller under RLS** (`callerClient(jwt)`); it does not read
    `public.users` directly — authorization comes from the `students_select` RLS policy
    (`user_id = auth.uid()`) plus the DB-side `rz_open_intent` re-check. Identity is still
    GoTrue-verified, never claim-derived.
  - `razorpay-webhook` has no JWT by design; its perimeter is the HMAC (next bullet).
- **The webhook refuses unverifiable HMACs.** `razorpay-webhook/index.ts` (~lines 120-160):
  with no `RAZORPAY_WEBHOOK_SECRET` configured it refuses **every** delivery with 503
  (fail-closed, audited as `payment.webhook.rejected`/`webhook_secret_missing`); the signature
  is computed over the **raw bytes** (`req.text()`, never a JSON round-trip), compared with
  `crypto.subtle.verify` (`_shared/razorpay.ts:134-141` — constant-time, not `===` on hex), and
  a bad signature is refused 401 and audited **before** the body is ever parsed as data.
- **`razorpay-order` never reads an amount from the request body.** The request body is never
  read at all — no `req.json()`/`req.text()`/`req.body` appears anywhere in
  `razorpay-order/index.ts` (grep: zero hits). The amount is derived server-side from
  `fee_payments.amount_due/amount_paid` for the current period, read **under the student's own
  RLS**, and then **re-derived by the database**: the `rz_open_intent` RPC recomputes the
  expected paise from the same ledger and raises `P0001` if the passed amount differs
  (index.ts ~lines 143-226). `RAZORPAY_KEY_SECRET` is used only inside this function's process
  and never appears in a response body.

### 2.4 Build health at the audited commit

- `flutter analyze` → `No issues found! (ran in 7.8s)`
- `flutter test` → `00:27 +467: All tests passed!`

---

## 3. Scanner blockers — disposition, owner, mitigation

### 3.1 Fixture passwords in widget tests (6 blockers: 5 tracked-file + 1 history) — **Informational / false positive**

`Tx7-quiet-lamp` and `Sage-7413-Kite` are values returned by in-test fake repositories
(`_FakeWrites` in `owner_staff_test.dart`, the fake `registerStudent` in
`warden_register_student_test.dart`) so the tests can assert the credentials dialog renders.
Evidence they are not real credentials: `Sage-7413-Kite` is literally the **documented example**
of the generated password format (`DECISIONS.md:16`, `docs/edge-functions.md:226/241/268`,
`supabase/functions/_shared/password.ts:3`, `lib/auth/password.ts:4`); neither string appears in
`db/`, `seed.ts`, or any SQL; they authenticate to nothing. Real passwords are generated
server-side per-creation and never stored in plaintext.

- **Owner:** dev team. **Mitigation/action:** teach `scripts/security-scan.mjs` an explicit
  allowlist for these two fixture strings (or rename the fixtures to something the scanner's
  heuristic skips) so the scanner can go green without loosening its rule. Until then the
  scanner will keep exiting 1 on these; that noise is the cost of not weakening the check in
  this pass.

### 3.2 `RAZORPAY_KEY_ID` committed (4 blockers: 3 tracked-file + 1 history) — **Low**

`rzp_test_TTZjgz6pssJVJs` appears in `docs/razorpay-in-app.md:128`,
`nivora_app/test/payment_test.dart:35`, `nivora_app/test/receipt_test.dart:44`, and git history.
Two facts bound the risk: (a) a Razorpay **key id** is the publishable merchant identifier —
it is shipped inside every client that opens Checkout, by design (`lib/core/config/env.dart:27`,
`lib/data/models/payment.dart:172`); (b) this one is **test mode** (`rzp_test_`), which can move
no real money. The corresponding **key secret** — the credential that actually matters — was
verified absent from all tracked files and from full git history (§2.2).

- **Owner:** product owner (holds the Razorpay dashboard). **Mitigation:** go-live uses a
  **live-mode** key pair that has never been in this repo, supplied via
  `--dart-define=RAZORPAY_KEY_ID=…` at build time and `supabase secrets set` server-side;
  optionally regenerate the test key at that point. No code change required.

### 3.3 Transitive `url_launcher` in the dependency tree — **Low** (found by this sweep, not the scanner)

The plugin arrives transitively (it is in `pubspec.lock`, not `pubspec.yaml`) and no app code
imports or calls it, so no user flow can leave the app through it; it is dead weight compiled
into the APK. **Owner:** dev team. **Mitigation:** none required for release; optionally pin a
`dependency_overrides`-free exclusion later or verify with `flutter pub deps` which direct
dependency drags it in.

---

### 3.3a Errata from adversarial verification of this document

An independent verifier was pointed at this sign-off with instructions to falsify it. Two
corrections it produced are applied above; recorded here so the document's own history is
honest:

- The signing fallback path was misnamed `~/.nivora-keys/`; the gradle file actually reads
  `~/.hostelpro-keys/keystore.properties` (nivora_app/android/app/build.gradle.kts:22). The
  load-bearing claim — no keystore or key.properties tracked in the repo — was verified true.
- A scanner output quoted in §6 was produced one commit earlier than the HEAD it was attributed
  to (634 vs 635 tracked files). The verifier re-ran the scanner at the true HEAD: still
  0 blockers / 0 warnings — the verdict stands; the quote's provenance was stale, and this note
  is the correction.
- The verifier also re-proved the §3.4 canary mechanism in an isolated scratch repository
  (planted dummy secret → fires; committed `rzp_test_`-shaped key id → correctly ignored),
  since re-planting the real secret was blocked by the session's permission layer. The
  real-value canary in §3.4 therefore stands as recorded by the pass that performed it.

### 3.4 Resolution — scanner refined, re-run clean, canary-verified

*Added after the dispositions above, same day.* Leaving a scanner permanently red teaches
people to ignore it, which is how the next REAL finding gets waved through. Both false-positive
classes were therefore closed at the source, narrowly:

- **Fixture passwords** (`Tx7-quiet-lamp`, `Sage-7413-Kite`) joined the scanner's existing
  demo-constant allowlist — the same mechanism that already carries `Owner@12345`. The
  shape-independent env-value check runs *independently* of that list, so allowlisting can
  never mask a string that matches a real `.env.local` value.
- **`RAZORPAY_KEY_ID`** gained the narrowest possible exemption in `envSecretValues()`: exact
  key name AND the value must match `^rzp_(test|live)_[A-Za-z0-9]+$` — the key-id shape. The
  Razorpay *secret* is a bare random string that never carries the `rzp_` prefix, so the
  exemption cannot mask it, and `RAZORPAY_KEY_SECRET` / `RAZORPAY_WEBHOOK_SECRET` remain fully
  enforced.

Re-run after refinement: **`RESULT: 0 blocker(s), 0 warning(s)`**.

Canary, because a refinement that is not proven to still catch a real leak is worse than none:
the actual `RAZORPAY_KEY_SECRET` value was appended to a tracked file, the scanner re-run —
**it fired** (`BLOCKER — value of RAZORPAY_KEY_SECRET (.env) is committed in a tracked file`) —
and the plant was removed, after which the scan is clean again. The refinement narrowed the
noise without dulling the blade.

---

## 4. Release-rule checklist

| Rule (product owner's words) | Status |
|---|---|
| "Do not deploy to production while any Critical vulnerability is open." | **Pass** — no Critical open (§1, §3) |
| "Do not deploy while any High vulnerability has no documented mitigation and owner." | **Pass** — no High open; all open items are Low/Info and carry owner + mitigation regardless |
| "Verify security on the server/backend, not only in frontend code." | **Partially met** — server-side *source* verified (§2.3); the **deployed** backend is not (§5.1). The authorization boundary (GoTrue verification + `public.users` + RLS + DB-side amount re-check) lives server-side, not in the client. |
| "No service-role/admin keys in browser code." / "Never store server secrets in frontend environment variables." | **Pass** — only the anon-role JWT ships in the app (§2.2); scanner: "no server secrets in client bundle (155 files scanned)"; signing secrets live outside the repo |
| "Keep a written security sign-off before release." | This document |

**4.4 Deploy flags the verdict depends on** (from the functions' own headers): deploy
`razorpay-webhook` with `--no-verify-jwt` (its HMAC is the perimeter; Razorpay sends no JWT);
deploy the other four **with** `verify_jwt` left ON as the outer gate.

---

## 5. What is NOT verified — read this before relying on §1

1. **The five edge functions are not deployed.** Everything in §2.3 is source review of the code
   in this repo. Whether the live project runs this code, with `RAZORPAY_KEY_ID`,
   `RAZORPAY_KEY_SECRET`, and `RAZORPAY_WEBHOOK_SECRET` set and the §4.4 verify_jwt flags
   correct, is **unverified**. **Owner action:** product owner deploys and confirms; until then
   the payment path does not exist in production.
2. **No live on-device round-trip has been possible from this machine.** Norton intercepts TLS
   on this workstation, so no end-to-end login/payment/webhook exchange against the live
   Supabase project was exercised in this pass. The webhook's refusal behavior, the platform
   gateway's verify_jwt behavior, and real Razorpay signature handling are attested by code
   reading only.
3. **The live RLS attack suites were not re-run.** The `scripts/_qa-*.mjs` suites (80/80 +
   32/32 attacks) were last executed in the 2026-08-17/20 rounds recorded in `SECURITY.md`;
   this pass did not repeat them (no service key available in this environment). Schema/RLS
   changes since 2026-08-20, if any, are outside what this document attests.
4. **The Next.js web app is out of scope here.** Its sign-off is `SECURITY.md`. Note that
   `SECURITY.md` predates the mobile Razorpay work (it says "no payment provider"); the payment
   surface is covered by this document's §2.3, not by that file.
5. **Play-side device checks** (assetlinks in production, actual APK contents of a store build)
   were not exercised; the no-secrets claims are about source and tracked files, backed by
   `release.sh`'s own build-time grep.

A sign-off that overclaims is worse than none. §1's verdict is exactly as strong as §2's
evidence and no stronger; the §5 items belong to their owners before this release is real.

---

## 6. Re-verification — second independent pass, same day

*2026-08-29, at HEAD `8586e39` (the commit that added §3.4 and the scanner refinement), with
the tab-warmup work in flight as uncommitted changes under `nivora_app/lib/` and new
`*_warmup_test.dart` suites.* Every load-bearing claim above was re-checked from scratch, not
trusted:

- **Scanner (current, refined):** `node scripts/security-scan.mjs` → all sections green,
  `RESULT: 0 blocker(s), 0 warning(s)`, exit 0. "no credentials in 634 tracked files",
  "no .env value appears in tracked files (5 secrets compared)" — the shape-independent
  env-value check is live and compared five real secret values, so the §3.4 allowlist cannot
  have blinded it.
- **Scanner (pre-refinement, replayed):** the scanner as it stood at `7df8bca`
  (`git show 7df8bca:scripts/security-scan.mjs`) run against today's tree fires **21**
  blockers — the original 10 plus 11 new ones, every added one caused by *this document*
  quoting the evidence in §2.1/§3. A sign-off that records scanner findings verbatim keeps a
  string-matching scanner red forever; that is the concrete demonstration that §3.4's
  refinement (allowlist the two fixture strings, exempt the key-id shape) was the correct fix
  rather than a whitewash.
- **JWT sweep re-done:** one JWT-shaped literal in all of `nivora_app/` (excluding
  `build/`, `.dart_tool/`) — `lib/core/config/env.dart:24`; payload re-decoded today:
  `{"iss":"supabase","ref":"nimxvgzscbanhtvgnjll","role":"anon",...}` — anon, as §2.2 states.
- **WebView / url_launcher re-checked:** zero matches in `pubspec.yaml`; the only `lib/`
  matches are the four comments asserting their absence; `url_launcher` remains
  transitive-only in `pubspec.lock` (§3.3 unchanged).
- **Edge-function claims re-read at source:** `_shared/caller.ts:106` (GoTrue verify) →
  `:112-116` (authoritative role from `public.users` via service client) → `:123-124`
  (active / not-deleted / must_change_password gates) → `:137-147` (role gate, audited);
  anon/service keys refused by identity at `:61-65`. Webhook: fail-closed 503 without secret,
  raw-body HMAC, 64-hex shape check then `crypto.subtle.verify`
  (`_shared/razorpay.ts:~120-147`), 401 + audit before any parse. `razorpay-order`: zero
  `req.json|text|body|formData|arrayBuffer` hits; amount from `fee_payments` under the
  caller's RLS, re-derived by `rz_open_intent`. All exactly as §2.3 records.
- **Build health, current tree:** `flutter analyze` → `No issues found! (ran in 19.3s)`;
  `flutter test` → `00:36 +482: All tests passed!` (482 vs §2.4's 467 — the delta is the
  in-flight warmup suites, which are outside this sign-off's pinned scope but do not break
  it).

Nothing in §1–§5 required correction. The §5 not-verified items remain open and remain the
product owner's.

---

*Prepared by the security checklist agent, 2026-08-29, at commit `7df8bca`; §3.4 and the
scanner refinement landed as `8586e39`; §6 re-verified at that HEAD. Scanner output, grep
evidence, and decoded JWT payloads reproduced verbatim above; nothing in `lib/` or
`supabase/` was modified by this pass.*
