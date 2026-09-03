# Terms, privacy policy and the consent gate

The two published documents, the in-app gate that makes people agree to them, and the record that
proves they did.

Companion documents: [`data-retention-and-privacy.md`](./data-retention-and-privacy.md) (the data
inventory every factual claim in the policy is drawn from) ·
[`account-deletion.md`](./account-deletion.md) (the erasure path the policy promises) ·
[`play-submission-pack.md`](./play-submission-pack.md) §7 (the Console fields these fill) ·
[`access-control.md`](./access-control.md) (who can reach what).

> **Not legal advice.** The statutory reasoning is the author's best understanding and must be
> confirmed with counsel before real residents' data is processed. What *is* authoritative here is
> the mechanism: the tables, the RPC, the gate and the version coupling, all of which were built
> and measured against the live project.

---

## 1. This is a Play Store requirement, not a preference

**Google Play will not list an app that handles personal data without a publicly reachable privacy
policy URL.** It is a field in Play Console (Store listing → Privacy policy), a reviewer fetches it
**while signed out**, and a listing submitted without it — or with one that contradicts the Data
safety form — is rejected.

NIVORA is squarely inside that rule. It handles, for people who never chose to install it:

- names, phone numbers and email addresses
- permanent addresses and guardian contact details
- **photographs and government-ID scans**
- a payment ledger, and online payment records
- visitor logs naming third parties with no account at all

So the privacy policy is not documentation. It is a **release blocker**, and so is the consent gate:
the DPDP Act 2023 requires notice and consent *before* that processing begins, and a consent nobody
recorded cannot be evidenced when it is questioned.

| Play Console field | URL |
|---|---|
| Store listing → Privacy policy | `https://hostelpro-three.vercel.app/legal/privacy` |
| App content → Data safety → account deletion | `https://hostelpro-three.vercel.app/legal/account-deletion` |
| (not a Console field, but linked from the app) | `https://hostelpro-three.vercel.app/legal/terms` |

---

## 2. What was actually built

### 2.1 The documents

Four public pages under `app/legal/`, all statically readable with no session:

| Page | File |
|---|---|
| Index | `app/legal/page.tsx` |
| Privacy Policy | `app/legal/privacy/page.tsx` |
| Terms of Use | `app/legal/terms/page.tsx` |
| Account deletion | `app/legal/account-deletion/page.tsx` |

The **same two documents are also bundled into the Android app** as structured data in
`nivora_app/lib/features/legal/legal_documents.dart`, rendered by
`nivora_app/lib/features/legal/legal_screen.dart`.

**Why bundled rather than fetched.** The gate has to show a person what they are agreeing to before
they have agreed to anything; making that a network fetch means the one screen nobody may skip is
also the one screen that can fail. `url_launcher` is deliberately not a dependency of the Flutter
app (pubspec.yaml records the same reasoning for four other packages), so handing the documents to
a browser would mean adding a package to display text the app already has. The published URL is
printed as selectable text instead.

### 2.2 The record

`db/migrations/2026-09-02-legal-consent.sql`, applied to `nimxvgzscbanhtvgnjll` on 2026-09-02 as
migrations `legal_consent_2026_09_02` and `legal_consent_audit_once_2026_09_02`.

| Object | What it is |
|---|---|
| `public.legal_versions` | Published versions of the Terms + Privacy pair. `version` is the PK; an acceptance may only name a version that exists here |
| `public.legal_acceptances` | Append-only: `(user_id, version, accepted_at, surface, app_version)`, unique on `(user_id, version)` |
| `public.accept_legal_terms(version, surface, app_version)` | SECURITY DEFINER. The only way a row gets in |

**RLS.** `legal_versions` is readable by any signed-in user (it is public text). `legal_acceptances`
is readable by its own subject and by the service role. There is **no INSERT, UPDATE or DELETE
policy on `legal_acceptances` at all — not even for the person the row is about.** That absence is
the design: if the subject of a consent record could write it, they could choose its timestamp,
name a surface they never used, or delete it and re-agree later with a fresh date. Each of those
destroys the only thing the record is for.

**What is deliberately not stored:** no IP address and no user-agent. Neither is needed to evidence
"this account agreed to this text at this time", and both are exactly the kind of identifier the
policy promises not to hoard. The RPC writes an `audit_log` row (`action = 'legal.accept'`) which
carries the platform's normal request context under its own retention rule.

### 2.3 The gate

`nivora_app/lib/features/legal/consent_gate.dart`, wired in `nivora_app/lib/core/router/router.dart`
by wrapping every role home in the route table:

```dart
for (final entry in roleHome.entries)
  entry.value: (_) => ConsentGate(child: RoleShell(role: entry.key)),
```

That one line is the whole signed-in surface — all five role subtrees render through their role
home. `/change-password` and `/mfa-setup` are deliberately **outside** it: somebody forced to change
a temporary password must not have to accept a privacy policy before being allowed to secure their
own account.

**It is not an arm in `resolveRedirect`.** Consent state is fetched rather than carried in the
session row, so a redirect arm would have to block sign-in on an extra round trip or invent a
spinner route to wait on. More importantly `resolveRedirect` is a pure function with an exhaustive
every-phase-against-every-route matrix in `test/router_redirect_test.dart`; folding a fetched
condition into it would have made that matrix's meaning depend on data it cannot see. **The router's
decision function is unchanged by this feature.**

---

## 3. The version is a contract between three files

One string covers **both** documents — they are presented together and agreed to together, so there
is no state in which somebody is half-agreed. It lives in three places and they must move together:

| # | Where | Symbol |
|---|---|---|
| 1 | `lib/legal-config.ts` | `LEGAL_VERSION` — the published web pages |
| 2 | `nivora_app/lib/features/legal/legal_documents.dart` | `kLegalVersion` — what the app shows and records against |
| 3 | `public.legal_versions.version` | a migration — what an acceptance may name |

**Change the wording of either document → bump all three → every user is asked again**, because the
gate compares the version it ships against the versions that user has accepted. This is why
acceptance is stored per version rather than as a boolean: a `has_accepted` flag would silently move
existing users onto a policy they never saw.

(1) and (2) are cross-checked by `nivora_app/test/legal_consent_test.dart`, which reads
`lib/legal-config.ts` off disk, so they cannot drift silently.

### 3.1 Deployment order is not optional

**Publish the version row (a migration) BEFORE releasing an app build that carries that version
string.** `accept_legal_terms()` refuses a version it has never heard of, and at the gate the only
thing a user may do is agree — so the wrong order locks every account out of the product. Nothing
in Dart can check this; it is a release step.

---

## 4. What the gate does, state by state

LOADING, EMPTY, FAILED and REFUSED are four distinct states everywhere in this app
(`nivora_app/lib/data/models/failure.dart`). The gate is the one screen every user meets, so
collapsing two of them here would be the rule broken in the most visible place there is.

| State | What is drawn |
|---|---|
| **Checking** | A spinner. We do not know yet and do not pretend to |
| **Agreed** | The product. The gate is invisible |
| **Not agreed** | Both documents, an unticked box, `Agree and continue`, `I do not agree` |
| **Failed** (offline / server) | "Cannot check your agreement", a `Try again`, and `Sign out` |
| **Refused** (dead session) | "Your session has ended", **no** retry button, and `Sign out` |

**It fails closed.** If we cannot establish that this person agreed, they do not get in — the
alternative would mean the gate stops existing the moment the network is bad. What must never happen
is that failing closed also *strands* them, so **every non-passing state carries Sign out.**

**Declining is a real option.** It does not silently do nothing (which reads as a broken button), it
does not sign the person out from under them (which loses them the chance to change their mind), and
it does not nag. It explains that the app cannot be used without agreeing, offers the way back to
the documents, and offers the door. **Nothing is written when somebody declines** — a decline is the
absence of a consent, not a second kind of record to keep about a person.

### 4.1 One bug this found

Written the obvious way — `consent.when(loading:, error:, data:)` — the gate showed a **spinner for
the whole ~38-second retry backoff** to a user whose only problem was no signal, and only then
admitted the check had failed. Riverpod 3 represents a failed read that it is still retrying as an
`AsyncLoading` that *carries* the error, and `when` dispatches on the runtime type. The gate now
asks `hasError` before `isLoading`. Caught by `FAILED offers a retry` in `legal_consent_test.dart`;
the same trap is documented at `features/student/widgets/rent.dart` and `features/common/refresh.dart`.

---

## 5. Reading the documents afterwards

A policy you can only read in the second before you agree to it is not a policy anyone has read, and
Play's guidance assumes the documents stay reachable.

**In the app:** the shield icon in every role's header → **Security** → **Terms & Privacy** at the
bottom. That screen was chosen because it is the one account screen **all five roles already
reach** — "More" and "Profile" exist for two roles between them.

**On the web:** the four public URLs in §1, which need no account at all.

---

## 6. PLACEHOLDERS THE OWNER MUST CONFIRM BEFORE SUBMISSION

Everything below is a real-world fact about the business that cannot be derived from the codebase.
All of them live in **`lib/legal-config.ts`** and are mirrored in
**`nivora_app/lib/features/legal/legal_documents.dart`** — change both.

These were set by an earlier pass and have **not been verified by this one.** They are not
placeholders in the `.invalid` sense any more — `isConfigured` reports true and the "not ready to
publish" banner is gone — which makes them *more* dangerous, not less: the page now looks finished
while possibly naming a mailbox nobody reads.

The two contact values were changed on **2026-09-04** from a personal name and a street-level
address to a role title and a locality. That was the owner's instruction and it is also the safer
reading of both rules: Play requires a *working* contact and DPDP requires a *grievance officer's*
contact, and neither is better served by publishing an individual's home address to the open web.
**Do not put a personal name or a street address back into these fields.**

| Value | Currently | What must be confirmed |
|---|---|---|
| `operatorName` | `NIVORA` | **This is a product name, not a legal entity.** DPDP requires a Data Fiduciary to identify itself. If a company or proprietorship is registered, use its registered name; if the operator is an individual, use their name |
| `grievanceEmail` / `legalEmail` | `support@nivora.dhrishtaerf.org` | **Send a test message and confirm somebody receives it.** A privacy policy's contact address is where erasure requests arrive; one that bounces is worse than none, because the request is lost silently |
| `postalAddress` | `Chittoor, Andhra Pradesh, India` | **Deliberately a locality, not a doorstep** (changed 2026-09-04). The published pages are read by anyone on the open web, and the monitored mailbox above is the channel that actually answers a request. If counsel says a fuller address is required, use a business or registered-office address — not a home one |
| `grievanceOfficer` | `The Grievance Officer` | **Deliberately a role, not a person** (changed 2026-09-04). DPDP requires the grievance officer's *contact*, and a role title plus a monitored role mailbox gives one that does not go stale the day somebody else takes the job. Confirm that whoever holds the role answers within 30 days |
| `jurisdiction` / `governingLaw` | Chittoor, Andhra Pradesh / laws of India | Confirm with counsel that this is where the operator wants disputes heard |

No company registration number, GST number or CIN appears anywhere, because none was supplied.
**Do not invent one.** If the operator is registered, add it to the policy's contact section.

---

## 7. Open items and cross-agent dependencies

1. **The retention periods in the policy now match the job — RESOLVED 2026-09-04.**
   `app.apply_retention()` (db/schema.sql, run nightly at 03:15 UTC by the `hostelpro-retention`
   pg_cron job) covers the audit trail, security alerts, rate limits, read notifications,
   complaints and notices at 2 months, and the deferred erasure of a departed resident 1 month
   after check-out. The rewritten §7 of the privacy policy publishes exactly those periods and
   nothing else: the 12-month visitor-log and leave-request periods and the 24-month staff-task
   period, which no code enforced, were **removed** rather than restated more softly — visitor
   entries and leave requests are now described as going with the resident record they belong to,
   which is what `app.erase_student()` actually does. Anything added to the job later must be
   added to the page in the same change, and vice versa.

2. **`firebase_core` and `firebase_messaging` are dependencies of the Flutter app but are never
   initialised** — no `Firebase.initializeApp`, no `FirebaseMessaging`, no `google-services` plugin,
   no usage anywhere in `lib/`. The policy therefore states that there are no push notifications and
   no device token, which is true of the running app. But a Play Data safety reviewer looking at the
   linked SDKs may ask, and an uninitialised messaging SDK is dead weight in the APK. **Recommend
   removing both from `pubspec.yaml`.**

3. **Age / minors.** Unchanged by this work and still the position in
   `data-retention-and-privacy.md` §3: the product cannot tell whether a resident is a child, so
   parental consent is an out-of-band duty the tenant must discharge in their own paperwork. The
   policy and the terms both say so.

4. **The web app has no consent gate.** The Flutter app does. A staff member who only ever uses the
   Next.js app will not have been asked. `legal_acceptances.surface` already distinguishes
   `'android'` from `'web'`, and `accept_legal_terms()` is reachable from the web client with no
   change — but the gate itself is not built there.

---

## 8. Verifying it

```sql
-- the published version, and who has accepted it
select * from public.legal_versions;
select version, count(*) from public.legal_acceptances group by version;

-- an acceptance cannot be forged: these must both fail
--   anonymous            -> 42501
--   unpublished version  -> 22023
```

Measured on the live project on 2026-09-02, in a transaction that was rolled back so no real
person was recorded as having agreed to anything:

| Check | Result |
|---|---|
| Anonymous call to `accept_legal_terms` | refused, `42501` |
| Unknown version | refused, `22023` |
| Two identical calls | **1** acceptance row, **1** audit row, same timestamp |
| The subject reads their own acceptance | 1 row |
| A different signed-in user reads it | **0 rows** |
| `legal_versions` signed in / anonymous | 1 row / **0 rows** |
| `legal_acceptances` anonymous | **0 rows**, cleanly — not an error |

Two of those rows are fixes rather than just results.

**The audit duplicate.** Before the early return in `accept_legal_terms()`, a double tap left one
acceptance and **two** `legal.accept` audit entries — harmless to the gate, and actively misleading
in the one record that exists to settle a dispute: a reader would see somebody agreeing twice,
seconds apart, and reasonably wonder what changed between them. Nothing did.

**The anonymous read.** `legal_acceptances_select` was first written as
`user_id = auth.uid() or app.is_service_role()`. That was wrong twice: `service_role` is a
`BYPASSRLS` role and never needed the disjunct, and `anon` holds no EXECUTE on
`app.is_service_role()` — so instead of evaluating to false it raised
`42501 permission denied for function is_service_role`, turning "no rows for a caller with no
session" into a hard error on the exact read that decides whether the gate appears. It is now a
bare `user_id = auth.uid()`, matching `notifications_select`.

> **Testing RLS from the SQL editor requires `set local role authenticated`.** That connection is
> `postgres`, which is `BYPASSRLS`, so setting `request.jwt.claims` alone changes what `auth.uid()`
> returns while every policy is still skipped — and every isolation check passes vacuously. The
> first run of the table above reported "another user sees 1 row" for exactly this reason.

```bash
# the app side
cd nivora_app && flutter analyze && flutter test
```
