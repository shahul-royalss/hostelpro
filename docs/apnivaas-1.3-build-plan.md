# Apnivaas 1.3 and beyond: master build plan

Status: plan only. Nothing in this document has been built. Written 2026-10-18 from four read-only inventories (app, backend, RentOk teardown, Forest & Cream design canvas) and a check of the repository.

This document drives several implementation workflows. Each phase lists workstreams that own **disjoint files and directories**, so the workstreams inside a wave can be built in parallel without merge conflicts. Waves inside a phase run in order.

Contents

0. How long it takes (summary)
1. Ground rules and conventions every workstream follows
2. Gap matrix: every RentOk feature, our status, the decision
3. The new design system and the screen map per role
4. Phased roadmap (Phase A to Phase H)
5. Security and robustness requirements (definition of done)
6. Decisions for the owner, owner actions, deferred features
- Appendix A: Forest & Cream design tokens and component specs (the canonical design spec)
- Appendix B: new tables, retention and erasure
- Appendix C: new cron jobs

---

## 0. How long it takes

The estimates assume the way this project is already built: parallel agent workflows, each with tests, a review pass, and the owner's go-ahead before anything is applied to the live database or uploaded to Play.

"Build" counts working days with the phase's workstreams running in parallel. "Calendar" adds the live database apply, the legal-version row, the website push, the release gate (`scripts/release.sh`) and Play review (usually 1 to 3 days).

| Phase | What ships | Build (working days) | Calendar | Live DB change | Legal bump |
|---|---|---|---|---|---|
| A | Forest & Cream design system, new shells and tab bars, every existing screen reskinned, client-only fixes (change password, reset-password landing, force update) | 6 to 9 | about 2 weeks | No | No |
| B | Persona picker, owner and tenant self sign-up (email or Google), owner PG application with Super Admin approval, tenant join codes, Book a free demo | 5 to 7 | 1.5 to 2 weeks | Yes | Yes |
| C | Property and rent settings written as questions (due day, grace, late-fine rule, deposit, lock-in, notice, joining fee), tenancy notice flow, home blocks, pending inbox, global search, notification inbox and push-tap routing, daily snapshots | 5 to 7 | about 1.5 weeks | Yes | Yes |
| D | Money depth: charges by category, bulk charges, electricity meters, automatic late fines, deposits, joining fee, tenant passbook, collections, receipts for everything, reminders, expenses edit and receipt photo, staff cash passbook, UPI to owner with UTR, Razorpay F2 fix, optional proration | 10 to 14 | about 3 weeks | Yes | Yes |
| E | Operations: gate passes with codes, entry and exit log, curfew and late entry, who is inside, resident leave requests, guest stays, manual roll call, meal settings, meal confirmations, meal codes, food counts, food preference | 8 to 10 | about 2 weeks | Yes | Yes |
| F | People: richer tenant profile, document vault, KYC record, police verification tracking, rent agreement with signature pad, move-in and move-out checklists, move-out settlement, past tenants, bed swap, leads, bookings, owner-private tenant flags | 10 to 14 | about 3 weeks | Yes | Yes |
| G | Team and complaints: staff capabilities, off-boarding, team and tenant activity log, staff duty check-in, complaint assignment, comments, rating, reopen, escalation, costs, tasks edit and recurrence, targeted notices with read receipts | 6 to 8 | 1.5 to 2 weeks | Yes | Yes |
| H | Insight and growth: analytics, reports (PDF and CSV via share sheet), scheduled report notices, stay reviews, Play in-app review, referrals, help and support tickets | 6 to 8 | 1.5 to 2 weeks | Yes | Yes |

**Totals.** About 56 to 77 working days of build. Run strictly one after another that is 15 to 20 weeks. Starting the next phase's database and Edge Function work while the previous release is in Play review brings it to **about 12 to 16 weeks (3 to 4 months)** for everything marked "build now". Phase A alone, the new look with no backend change, is about 2 weeks.

The biggest uncertainties are:
- Test migration. About 1,330 test finders locate widgets by visible copy, so every renamed string moves tests with it.
- Turnaround on the owner's go-ahead for each live apply and Play upload.
- The money-path changes in Phase D (Razorpay F2, proration), which carry the heaviest SQL tests.

**Suggested release mapping** (each phase leaves `main` shippable; bundling is optional):

| Release | Phases | Note |
|---|---|---|
| 1.3.0 | A + B | Matches the owner's 1.3.0 plan (new look, personas, sign-up, book a demo). Phase A can go to the internal testing track first. |
| 1.4.0 | C + D | Settings plus money. One legal bump for both. |
| 1.5.0 | E | Operations |
| 1.6.0 | F | People |
| 1.7.0 | G + H | One legal bump for both |

A legal bump re-prompts every user at the consent gate. Ship one bump per public release: when two phases go out together, their legal text goes into one version row.

**Phase 0, a prerequisite and not part of this plan:** finish 1.2.0. Per the project notes, the 2026-10-17 legal row is live and the three local commits (41aec40, 9e645f4, b210089) wait for the website push and the Play upload. Phase A branches from that state.

---

## 1. Ground rules and conventions

### 1.1 Standing product rules (non-negotiable)

1. **Security is enforced server-side.** RLS, SECURITY DEFINER RPCs that authorise as their first statement, and Edge Functions with fail-closed rate limits and audit. The client is never trusted for role, hostel, amount, period or date.
2. **No service-role key or other secret in the client.** Only the anon key, the Razorpay key id and the Google web client id reach the phone.
3. **Nothing opens a browser.** No `url_launcher`, no web view, no custom tabs. Links are copied or shared through the share sheet.
4. **The Android merged manifest declares exactly ten permissions and no advertising ID.** No phase in this plan adds a permission. Every new package must be checked against the merged manifest before merge.
5. **Any new data collection, permission or recipient requires a privacy-policy change and a legal version bump**, with the `public.legal_versions` row live before the website push and before any app build that carries the new `kLegalVersion`.
6. **Managers and wardens are never self-sign-up.** This is enforced in the database, not just hidden in the UI.
7. **Managers never see resident data.** Every new table that holds resident data has no manager read path, and a SQL test proves it.
8. **Owner screens stay read-only for residents, payments and complaints** unless the owner decides otherwise (decision D1 in section 6). The server already admits owners to `wd_*` RPCs through `app.has_role_in(h,'warden','owner')`, so enabling owner desk actions is a product switch, not a security change.
9. **Gate order survives every change:** splash, then login (OnboardingGate), then /mfa or /mfa-setup, then ConsentGate, then /change-password (forced), then /verify-email (staff), then the role home. `resolveRedirect` stays pure. Routes stay built from `appScreens`. The `to == here` guard stays.
10. **Old clients keep working.** Play rollouts leave older app versions in use for weeks, so every database change is additive: new nullable columns or columns with defaults, new RPCs instead of changed signatures, and `RETURNS TABLE` columns only ever appended last.

### 1.2 Conventions addendum (on top of the backend inventory's conventions)

- **Migration names.** `db/migrations/{D}-<kebab>.sql`, where `{D}` is the authoring date (IST) at implementation time, plus `{D}-<kebab>.down.sql` and `{D}-<kebab>.test.sql` for anything that redefines a routine, changes a policy or touches money.
  - Body shape is the 2026-09-30 / 2026-10-17 form: `begin; set local lock_timeout='10s';`, a `$guard$` block (current_user, md5 of every routine being replaced as measured on live, preconditions), the changes, a `$verify$` block, the `schema_migrations` row, `notify pgrst,'reload schema'` when signatures change, then `commit;`.
  - Legal bumps are separate files: `{D}-legal-version-<topic>.sql`.
- **New status-like columns use `text` plus a `CHECK`, not new enums.** `ALTER TYPE ... ADD VALUE` cannot be used inside the transaction that adds it, so when an existing enum must grow (`payment_mode`, `notification_type`), it goes in its own small non-transactional file named `{D}-<enum>-values.sql`, applied before the main migration.
- **New RPC prefix `mg_*`** for manager desk actions, which also admit the owner through `app.has_role_in(h,'manager','owner')`. Every other prefix is unchanged: `sa_`, `ow_`/`owner_`, `wd_`, `st_`, `rpc_`, `rz_`, `svc_`, `my_`, `staff_`.
- **Idempotency key.** Every money write and every bulk write takes `p_request_id uuid`, generated once per form submission on the device and stored in a unique column. A replay returns the first result and writes nothing.
- **Dart money.** New code holds money as integer paise in a `Money` value type (`lib/data/models/money.dart`, created in Phase D wave 1). It parses the server's numeric string without passing through `double` and formats through `intl` `en_IN`.
- **Feature folders.** New Flutter features live in `apnivaas_app/lib/features/<area>/` with their own `data/` subfolder (models, repository, providers), following the existing `warden/data`, `manager/data` and `super_admin/data` pattern. This keeps `lib/data/` uncontended. Only shared models go in `lib/data/models/`, and each phase names the one workstream that may touch them.
- **One integrator per phase.** Router, role shells, `owner_tabs.dart`, `student_section.dart` and `pubspec.yaml` belong to that phase's Integration workstream. It runs in the last wave and wires in the entry widgets the feature workstreams export (for example `MoneyTab`, `RequestsTab`). Feature workstreams never edit those files.
- **One schema-sync owner per phase.** `db/schema.sql` and `db/rls-policies.sql` are edited only by the phase's platform-DB workstream, which copies every redefined routine there in its last step.
- **Legal workstream per phase.** It owns `db/migrations/{D}-legal-version-*.sql`, `app/legal/**`, `lib/legal-config.ts`, `apnivaas_app/lib/features/legal/legal_documents.dart`, `apnivaas_app/test/legal_consent_test.dart` and `docs/data-safety.md`.
- **Test keys.** New widgets that tests must find get a `ValueKey('<area>.<element>')` from a per-feature `keys.dart`. New tests find by key or by type, not by copy. Existing copy-based finders change only when their copy changes.
- **Edge Function tests.** The repository has no Deno tests today; QA lives in `scripts/_qa-*.mjs`. New functions add pure-module Deno tests (`supabase/functions/<fn>/*_test.ts`, run with `deno test`) for validators and decision logic, plus a `scripts/_qa-<fn>.mjs` script that exercises the deployed function. No test sends a real secret.

### 1.3 Deploy order for every phase that touches the backend

1. Run the migration's `.test.sql` on a local Postgres mirror. Then run it on live inside its own `begin ... rollback`, with the owner's go-ahead.
2. Apply the migration on live (owner's go-ahead), verifying with the `AFTER APPLYING` queries.
3. Deploy the Edge Functions (`verify_jwt` on), then set any new secrets.
4. Insert the legal-version row on live.
5. Push the website (legal text, `lib/legal-config.ts`, any web compatibility fixes).
6. Build the app with `scripts/release.sh`: full test suite, analyzer, merged-manifest check of exactly ten permissions, legal parity.
7. The owner uploads to Play.

The old app keeps working between steps 2 and 7. That is the old-client rule.

---

## 2. Gap matrix

Legend:
- **Have**: built and usable.
- **Partial**: some of it exists.
- **Missing**: none of it exists.
- **Build now**: a phase in this plan.
- **Build later**: worth doing, but blocked or low value now.
- **Will not build**: conflicts with a standing rule, needs a paid or regulated partner, a new permission, or a tracking SDK.

### 2.1 Onboarding

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 1 | Language picker before sign-in | Missing (English only) | Build later | Needs i18n plumbing (ARB, `flutter_localizations`) and native-speaker translations. Strings are hard-coded and about 1,330 test finders use copy. Do it after Phase A has moved tests onto keys. Owner decision D7. |
| 2 | Intro story slides | Have (4-page carousel) | Build now | A: reskin and replace the three hard-coded grounds. B: refresh the copy for personas. |
| 3 | Phone + OTP sign-in, OTP over WhatsApp | Partial (phone works as a login id with a password) | Will not build now | Needs a paid SMS provider with DLT registration, or the WhatsApp Business API. Phone plus password stays. Owner decision D2. |
| 4 | One-tap social sign-in (Truecaller, Google, Apple) | Partial (Google sign-in for existing owners and residents; staff refused) | Build now (Google sign-up), Will not build (Truecaller), Build later (Apple) | B: Google sign-up for owner and tenant. Truecaller is a partner SDK and a new data source. Sign in with Apple becomes mandatory when iOS ships with Google (App Store 4.8). |
| 5 | Multiple accounts on one phone | Missing | Will not build | One login is one role, keyed by a unique email. A person who owns one PG and works at another uses two addresses. |
| 6 | Persona cards | Missing | Build now | B: Owner, Tenant, Staff. Staff routes to sign-in only. The seeker persona stays removed. |
| 7 | Sign-up progress stepper | Missing | Build now | B |
| 8 | Four-tap first property wizard | Partial (Super Admin create wizard only) | Build now, without a map pin | B: name, type, address, locality, city, pincode, floors, rooms, beds, then Super Admin approval. A map pin or "use my location" needs a location permission and a paid Maps API, so it will not be built. |
| 9 | Coach-mark tour | Missing | Build now | C: a local marker file, the same pattern as `onboarding_seen` |
| 10 | Force update, soft update, plan-expired gates | Partial (soft update banner; `app_releases.mandatory` exists; billing refusals) | Build now | A: blocking update screen (client only; copies the link, opens nothing). B: plan-expired screen with "Request renewal". |

### 2.2 Home

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 11 | Server-assembled block dashboard | Partial (fixed role dashboards) | Build now, client-composed | C: independent blocks, each with its own provider, skeleton, empty state, error state and refresh, fed by per-role RPCs. No server-side CMS ordering, because there is nothing to A/B test and it adds a remote-config surface. |
| 12 | Pending tasks inbox | Partial (warden desk counts) | Build now | C: `rpc_pending_inbox`, extended by each later phase |
| 13 | Quick actions and customisable shortcuts | Partial (Tools grid) | Build now | A: QuickActionGrid. C: pin and unpin, stored locally. |
| 14 | Metric explanations | Missing | Build now | C: info sheets with static copy |
| 15 | Stories and campaign sheets | Missing | Build later | Super-Admin-authored image and text cards are possible. HTML slides in a web view will not be built. |
| 16 | Global search | Missing | Build now (no voice) | C: `rpc_global_search`. Voice search needs RECORD_AUDIO, so it will not be built. |
| 17 | Property switcher, floor selector, property groups | Partial (staff Switch PG; owner PG switcher on the dashboard) | Build now (switcher), Build later (groups) | A: switcher in the new header. Groups add little for owners with 1 to 3 PGs. |
| 18 | Birthdays today | Missing | Build now | F (needs date of birth, which needs the F legal bump) |
| 19 | In-app help entry | Missing | Build now | H: FAQ plus a support ticket to Super Admin |
| 20 | Paid-plan promo overlay | Missing | Will not build | There is no freemium tier; Super Admin manages subscriptions. |

### 2.3 Money

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 21 | Dues ledger with categories | Partial (rent only, virtual monthly dues) | Build now | D: `charges` table next to `fee_payments`. The rent ledger is not touched. |
| 22 | Due packages (recurring bundles) | Missing | Build later | After `charges` has proved itself. The bulk-charge flow covers the common case. |
| 23 | Add dues in bulk | Missing | Build now | D: `wd_add_charges_bulk` with an idempotency key |
| 24 | Bulk charges from CSV | Missing | Build later | Needs a document-picker package whose merged-manifest impact must be verified, or a website import first |
| 25 | Electricity meters (gas and water too) | Missing | Build now | D |
| 26 | Record a payment | Have (rent desk) | Build now | D: extend to charges and add cheque. A cash OTP needs SMS, so it will not be built. |
| 27 | Partial payments, advance and credit | Partial (desk top-ups) | Build later (credit auto-adjust) | Overpayment credit needs its own ledger. Deposits (the Indian "advance") are built in D. |
| 28 | Discounts | Missing | Build later | For now, edit the monthly fee |
| 29 | Automatic late fine | Missing | Build now | Rule in C, daily job in D |
| 30 | Security deposit lifecycle | Missing | Build now | D: collect, adjust, refund (recorded; money moves outside the app). F: refund can be blocked until the checklist is done. |
| 31 | Cashless (insured) deposit | Missing | Will not build | Deposit-bond partner; shares tenants' financial data |
| 32 | Rent cycle, frequency, proration | Partial (calendar months; `rent_due_day` exists but nothing calls it) | Build now (due day, grace, proration), Will not build (daily, half-yearly or joining-date cycles) | C: due day and grace. D: optional proration of the joining and leaving months. `period_month 'YYYY-MM'` runs through the ledger, Razorpay and reminders, so other cycle shapes are out. |
| 33 | Joining fee and renewal charges | Missing | Build now | D: joining fee. F: renewal charge with agreements. |
| 34 | Payment reminders | Partial (cron reminders at -3/0/+3 days, in-app and push) | Build now | D: remind one or many by push, plus a WhatsApp-formatted text through the share sheet. Automatic WhatsApp sends need a paid API, so they will not be built. |
| 35 | Online rent collection | Partial (Razorpay built, not operational) | Build now (fix), owner decision to go live | D: fix bug F2; show Pay only when the PG has a payout account. Going live needs the owner's live keys (D2). |
| 36 | Virtual bank account per tenant | Missing | Will not build | Paid Smart Collect product plus KYC |
| 37 | Autopay (UPI mandate, eNACH) | Missing | Will not build now | Paid mandate product plus a legal bump. Deferred. |
| 38 | Convenience-fee pass-through | Missing | Will not build | Surcharging UPI payments is restricted by NPCI and RBI rules; legal risk |
| 39 | Bank accounts and settlement settings | Partial (Super Admin sets the Route account) | Build later | Owner self-service needs Razorpay Route onboarding KYC. It stays Super-Admin-managed. |
| 40 | Wallet and transfer to bank | Missing | Will not build | Holding funds requires a payment-aggregator licence |
| 41 | Collections list | Partial ("who paid") | Build now | D: unified rent and charge events. "Delete" becomes a reversal row; nothing is ever deleted. |
| 42 | Receipts and GST invoices | Partial (rent receipts) | Build now (receipts), Build later (GST) | D: receipts for charges, deposits and refunds, with owner receipt terms. GST needs GSTIN data, invoice numbering rules and a legal review. |
| 43 | Property payment QR poster | Missing | Build now | D: UPI QR drawn on the device and shared as PNG, part of UPI with UTR |
| 44 | Expenses | Have | Build now | D: edit, void, vendor, paid-by, receipt photo through an Edge Function |
| 45 | Team passbook (staff cash) | Missing | Build now | D: cash handovers confirmed in the app by the owner (no OTP), petty cash |
| 46 | Reports and scheduled delivery | Partial (expense stats) | Build now (in-app), owner decision for email | H: PDF and CSV through the share sheet. Scheduled delivery is an in-app notice; email needs a paid provider (D2). |
| 47 | Early payout or rent advance | Missing | Will not build | Regulated lending |

### 2.4 People and tenants

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 48 | Tenant list with situation filters | Partial (paged search) | Build now | C: dues, on leave, under notice. F: documents missing, KYC pending, agreement unsigned, app not activated. |
| 49 | Add tenant flow | Have (warden registration with ID proof) | Build now | F: bed pre-filled from the bed board, deposit, joining fee, terms, lead source. Tenant self-fill by QR will not be built; B's self sign-up plus join code replaces it. |
| 50 | Bulk tenant import | Missing | Build later | Same picker question as #24 |
| 51 | Rent agreement wizard with e-signature | Missing | Build now (signature pad), Will not build now (e-stamp) | F. A drawn signature is a signed acknowledgement, not an Aadhaar eSign; owner decision D4. E-stamp needs a paid provider. |
| 52 | Rich tenant profile | Partial | Build now (minimised) | F: date of birth, gender, occupation, institution or company, emergency contact, vehicle number. Blood group, nationality, parents' IDs and bank details will not be collected (data minimisation). |
| 53 | Tenant passbook | Partial (fee history plus refunds) | Build now | D: rent, charges, deposit and refund timeline. H: statement PDF. |
| 54 | Document vault | Partial (ID scan at registration) | Build now | F |
| 55 | e-KYC and police verification | Partial (scan stored) | Build now (manual), Will not build now (API) | F: staff mark KYC verified after seeing the original; police-verification upload and status. No Aadhaar number is stored anywhere. API KYC is paid and Aadhaar-sensitive. |
| 56 | Invite tenant to the resident app | Partial (temporary password dialog) | Build now | B: share invite text (login id only, never the password). F: "app not activated" chip. |
| 57 | Notice period and notice handling | Missing | Build now | C |
| 58 | Move-out flow | Partial (vacate) | Build now | F: reason, date, charges, deposit settlement, checklist, rating and flag in one transaction |
| 59 | Move-in and move-out checklists | Missing | Build now | F |
| 60 | Change room, change property, swap beds | Partial (move bed) | Build now (swap), Build later (change property) | F: atomic swap. Moving between PGs means moving dues across PGs; later. |
| 61 | Past tenants | Partial (vacated rows until erasure one month after check-out) | Build now | F: list until erasure |
| 62 | Tenant activity log | Partial (server `audit_log`) | Build now | G |
| 63 | Leads CRM | Missing | Build now | F (prospect data needs the F legal bump) |
| 64 | Bookings | Missing | Build now (staff reservations), Will not build now (self-booking) | F: staff reserve a bed and record a token. Tenant self-booking needs public discovery, which is deferred with "PGs near me". |

### 2.5 Team

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 65 | Add team member | Have (owner-create-staff, up to 5 per role per PG) | Build now | G: custom job title. Staff stay owner-created only. |
| 66 | Granular access permissions | Partial (fixed roles) | Build now (small set) | G: six server-enforced capabilities. A full per-screen permission matrix would multiply the RLS surface. |
| 67 | Staff ID verification (Aadhaar OTP) | Missing | Will not build | Paid API plus Aadhaar data |
| 68 | Off-boarding | Partial (deactivate) | Build now | G: deactivate, revoke every session, reassign open items |
| 69 | Team activity log | Partial (server only) | Build now | G |
| 70 | Assign wardens to floors | Missing | Build later | Routing by floor. Wi-Fi mapping needs a new permission, so it will not be built. |

### 2.6 Property and rooms

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 71 | Multi-property and property types | Partial (multi-PG owners) | Build now | B collects type in the wizard. C: `property_type` and `gender_policy` on hostels. |
| 72 | Floors and wings | Have (floor plan with names) | Build later (copy layout) | Small, low value |
| 73 | Rooms (tags, per-bed rent, out of order, photos, publish) | Partial | Build now (tags, default rent, available flag), Build later (photos, publish) | C. Photos and publishing wait for a listing decision. |
| 74 | Bed grid with statuses | Partial (free and occupied) | Build now | A: reskinned grid. C: under notice. F: booked. |
| 75 | Occupancy counts | Have | Build now | A: reskin. C and F add counts. |
| 76 | Share room details | Missing | Build now | C: WhatsApp-ready text through the share sheet |
| 77 | Property settings hub | Partial (rules editor exists, nothing calls it) | Build now | C |

### 2.7 Complaints

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 78 | Raise complaint (tenant or staff) | Partial (tenant only, optional photo) | Build now | G: staff on behalf, room, priority. Video and voice notes will not be built (RECORD_AUDIO). |
| 79 | Assignment and @mentions | Missing | Build now | G |
| 80 | Status flow and resolution rating | Partial (open, in progress, resolved) | Build now | G: rating plus reopen; the three states stay |
| 81 | Costs linked to complaints | Missing | Build now | G |
| 82 | Proof-of-visit selfie | Missing | Will not build | New camera purpose plus staff selfies, for little value |
| 83 | Complaint filters, summary, report | Partial | Build now | G: filters and summary. H: export. |
| 84 | Platform support tickets, FAQs, tutorials | Missing | Build now | H (static guides; no video streaming, no web view) |

### 2.8 Food

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 85 | Meal settings | Missing | Build now | E |
| 86 | Weekly menu management | Have | Build now | E: copy a day, copy to another PG, share as image |
| 87 | Food preference | Missing | Build now | E (dietary data, E legal bump) |
| 88 | Meal confirmation and meal QR | Missing | Build now (confirmation plus code), Build later (camera QR scan) | E. A scanner SDK (ML Kit) brings Google telemetry that needs a Data safety review. |
| 89 | Food attendance and report | Missing | Build now | E: counts. H: report. |

### 2.9 Gate and attendance

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 90 | Gate setup and QR posters | Missing | Build now (gates and codes), Build later (QR scan) | E |
| 91 | Curfew and late entry | Missing | Build now | E. One curfew per PG; per-gender curfew waits for gender data (F). |
| 92 | Exit passes with warden or parent approval | Missing | Build now (warden), Will not build now (parent) | E. Parents have no app; reaching them needs SMS or WhatsApp (D2). |
| 93 | Gate verification by scan or code | Missing | Build now (code) | E |
| 94 | Who is inside now | Missing | Build now | E |
| 95 | Leave records | Partial (table and warden approval; no resident screen; `on_leave` never reverts) | Build now | E: resident requests, daily status sync, emergency flag, rate limit |
| 96 | Guest stays | Partial (warden visitor log) | Build now | E: resident pre-registers a guest, warden approves, optional nightly charge |
| 97 | Daily attendance (manual) | Missing | Build now | E: roll call. Parent summaries will not be built (D2). |
| 98 | Smart self-attendance | Missing | Will not build | Location, Wi-Fi state and face templates: new permissions plus biometric data |

### 2.10 Reports and analytics

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 99 | Analytics dashboard | Partial (owner charts) | Build now | H (needs C's daily snapshots for trends) |
| 100 | Natural-language assistant | Missing | Will not build now | Sends operators' data to an LLM vendor; legal bump plus a paid API. Deferred. |
| 101 | Report scheduler | Missing | Build now (in-app) | H |

### 2.11 Growth

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 102 | Property website | Missing | Build later | Public pages on the website. Ties to the "PGs near me" decision (D6). |
| 103 | Marketplace listing | Missing | Will not build now | Deferred with "PGs near me"; moderation burden |
| 104 | Surveys and reviews | Missing | Build now (stay rating), Build later (survey builder) | H |
| 105 | Referral programme | Missing | Build now (owner codes, attribution, manual reward), Will not build (tenant coins) | H. Coins are money-like value and need reward terms. |
| 106 | Book a demo | Missing | Build now | B |
| 107 | Paid plan, trial and credits | Partial (Super Admin subscriptions) | Build now (trial on approval), Build later (in-app plan purchase), Will not build (KYC and stamp credits) | B: trial when Super Admin approves (D3). Plan purchase needs a platform Razorpay account plus GST invoicing. |
| 108 | Add-on services marketplace | Missing | Will not build | Partner services |
| 109 | Announcements with read receipts | Partial (owner notices, no receipts) | Build now | G: room and person audiences, templates, read receipts |
| 110 | Ask for an app review | Missing | Build now | H: Play In-App Review API, after checking it adds no permission |
| 111 | WhatsApp-ready sharing | Partial (receipt shared as PNG) | Build now | C: a shared message formatter, used by C, D, F and H |

### 2.12 Settings

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 112 | Payment rules | Partial | Build now | C: receipt terms, due day, grace, late fine. D: reminders. |
| 113 | Renting and stay rules | Partial (rules text, unwired) | Build now | C: type, gender, lock-in, notice, rules |
| 114 | Move-out settings | Missing | Build now | F |
| 115 | Onboarding and KYC settings | Missing | Build now | F |
| 116 | Account security | Partial (MFA; change password broken) | Build now | A: fix change password, reset-password landing, "Sign out of all devices" (GoTrue global sign-out; no backend change). Phone change by OTP will not be built (SMS). |
| 117 | Business verification for settlements | Missing | Will not build now | Razorpay Route merchant KYC stays with Super Admin, offline |
| 118 | Notification preferences and contact details | Missing | Build now | C |
| 119 | Copy settings across properties | Missing | Build now | C |

### 2.13 Tenant app

| # | RentOk feature | Apnivaas today | Decision | Phase or reason |
|---|---|---|---|---|
| 120 | Pay and track rent | Have | Build now | A: reskin. D: charges, deposit, UPI with UTR. |
| 121 | Complaints from the resident app | Have | Build now | G: rating and reopen |
| 122 | Notices, menu, meal confirmation | Partial | Build now | A: menu reachable from Home and Requests. E: meal confirmation. |
| 123 | Gate passes, leave, guests | Missing | Build now | E |
| 124 | Self attendance | Missing | Will not build | See #98 |
| 125 | Find and book a PG | Missing | Will not build now | The seeker persona was removed in 1.3.0; deferred with "PGs near me" (D6) |
| 126 | Notice, extension, move-out checklist | Missing | Build now | C: notice. F: checklist and deposit refund tracking. |
| 127 | Rewards and surveys | Missing | Build now (surveys), Will not build (coins) | H |
| 128 | Parent touchpoints | Missing | Will not build now | Messages to `guardian_phone` need SMS or WhatsApp (D2) plus a new processing purpose |

### 2.14 Apnivaas-only gaps found in the inventories

| Gap | Fix | Phase |
|---|---|---|
| Voluntary Change password throws: `Navigator.pushNamed` at `features/student/profile_screen.dart:139` and `features/shell/staff_profile_sheet.dart:168`, and go_router has no `onGenerateRoute` | `context.push('/change-password')` or a pushed `MaterialPageRoute`, plus a test that taps it | A |
| A forgot-password link lands nowhere; the recovered session later signs the user in without a new password | New `AuthPasswordRecovery` phase and `/reset-password` screen: set the password, sign out globally, back to sign-in. A local marker survives a cold start. | A |
| Push taps do nothing | `NotificationLinkResolver` stores a pending intent that RoleShell consumes after every gate | C |
| Legal reader reachable only from SecurityScreen, while the consent copy says "from the header of any screen" | "Terms and privacy" row in the profile sheet and the resident Profile; fix the consent copy | A |
| Unwired repository methods: `NoticeRepository.update`, `TaskRepository.update`, `StudentRepository.update`, `HostelRepository.updateRules` | Notice edit and task edit in A if live RLS allows the UPDATE (check `pg_policy` first), otherwise RPCs in G. Resident detail edit in F. Rules in C. | A, C, F, G |
| Manager category breakdown still shows in/out bars although `rpc_expense_months/days` exist | Category breakdown block | A |
| `ow_set_rent_due_day` has no caller, so every PG is on the 5th | Settings hub question | C |
| Leaves never revert `on_leave` to `active`, and leaves that start later never set it | Daily `app.sync_leave_status()` | E |
| Razorpay F2: `rz_record_capture` cannot claim an `expired` intent | Claim `expired` too when the amount matches, then schedule `rz_expire_stale_intents` | D |
| Pay button shows even when the PG has no payout account, then always fails | `st_online_payment_available()` gates the button | D |
| `password_policy.dart` refers to a `reset_password_screen.dart` that does not exist | Created in A | A |

---

## 3. The new design system and the screen map

### 3.1 Forest & Cream in one page

The full, measured spec is **Appendix A** below. It is canonical until Phase A copies it over the old "liquid glass" document `docs/design-system.md`. Sources:
- the canvas boards Main, SignIn, RolePicker, BookDemo, OwnerHome and IconSet (`claude.ai/artifact/8N1pMvR2nb3WGU7KK7LRLJ`);
- the clay icons in `design-3d/icons-v3/`;
- the current `apnivaas_app/lib/core/theme/{tokens,theme,typography}.dart`.

**What changes**

| | Today | Forest & Cream |
|---|---|---|
| Colour | Violet and indigo "neel" brand, purple brow, aurora wash, per-domain hues (violet rooms, teal people, saffron food) | Forest `#174E43` primary on cream ground `#F6F2EA`, cream cards `#FFFDF9`, Mist `#DCE8DF` tonal tiles, Gold `#E2AE4A` only as a fill on forest. Domain hues are retired: the clay icon tells you what kind of thing you are looking at; colour is kept for status. |
| Type | Inter, bundled through `google_fonts` | Outfit (600, 700) for headings and figures, Manrope (400 to 700) for reading. Static TTFs bundled in `apnivaas_app/google_fonts/` with runtime fetching off (already in the working tree), sentence case, minimum 11sp, tabular Manrope for refreshing figures. Outfit has no ₹ glyph, so Manrope is its fallback. |
| Shape | Radii 6/12/16/20, flat and hairline-edged | control 14, button 16, CTA 18, well 22, card 24, sheet and hero 28, header 30, pill 999 |
| Depth | None (empty shadow lists) | Cards stay flat. Three named shadows only: e1 (selected lift), e2 (tab bar), e3 (sheets). Still no BackdropFilter anywhere. |
| Header | Purple brow with gold sweep, BeamCard and AuroraField loops | ApnivaasHeader: forest gradient `#10392F` to `#174E43` to `#1F6150`, bottom corners 30, static dot stars painted once, PG switcher, bell with gold unread dot, optional search field |
| Navigation | Material NavigationBar with a coloured pill | ApnivaasTabBar: 76dp bar, 58x40 Mist indicator, 36dp clay icons (greyscale ColorFilter when unselected), emphasis-curve pop, `selectionClick` haptic |
| Icons | Material Rounded | 41 clay feature icons plus 4 role arts, as WebP in `assets/clay/` (target 1.5 MB or less), decoded with `cacheWidth`. Material Rounded stays for small glyphs (chevrons, close, search). |
| Motion | 150/240/340ms, 40ms stagger, infinite Beam and Aurora loops | The same durations, plus exit 200ms and an emphasis curve. No decorative `repeat()`. Reduce motion means the final state on the first frame. |

**Accessibility fixes the canvas needed.** These are measured, and `theme_contrast_test.dart` asserts each one:

| Element | Canvas value | Ratio | Replacement | Ratio |
|---|---|---|---|---|
| Placeholder | `#7B8A83` | 3.56 | `#66756E` | 4.77 |
| Inactive nav label | `#6B7A73` | 4.44 | `#55655E` | 6.06 |
| Control borders | `#DDD5C8` / `#BFB6A8` | 1.43 / 1.97 | `#8F8679` | 3.53 |
| Header search placeholder | `#CFE0D4` | 3.95 | `#E6F0EA` | 4.66 |

Leaf `#3F7F68` is never text on the ground (4.23).

**Components** (each specified in Appendix A.10). Every one lives in `apnivaas_app/lib/shared/ui/`:
- ApnivaasHeader, HeaderSearchField
- StatCarousel, HeroStatTile, StatTile, LinkTile
- QuickActionGrid
- ListGroup, ListRow, SectionHeader
- StatusChip, count badge, unread dot
- Buttons: Primary, LargeCta, Secondary, Pill, Tonal, TextLink, IconButton. The Google button keeps its Google-compliant styling.
- TextInput, FloatingLabelField, ChoiceChipGrid
- `showApnivaasSheet`, EmptyState, SkeletonLoader
- ApnivaasTabBar, PersonaCard, OnboardingStepper
- ActionBanner, InfoBanner, InfoNote
- ClayIcon with the ClayIcons enum
- AuthTopBar, Snackbar theme
- Plus PagedList: one copy replacing the three `paged_list.dart` files.

**What stays.**
- Every visual constant lives in `tokens.dart`.
- A legacy token name keeps its meaning when its value changes, so unconverted screens move with the new look.
- `colorScheme.surface` is the card; the ground is `scaffoldBackgroundColor`.
- Canonical colours for shapes, resolved colours for text (`context.tones`).
- Dark theme fully built and tested but pinned off (`ThemeMode.light`, owner decision).
- Text scale clamped to 0.9–1.4 in production, but every component passes 2.0x at 320dp in tests.
- Phones locked to portrait.

### 3.2 Navigation model

Owner-side roles get RentOk-style **Home / Money / People / Property** tabs, each role keeping only what its permissions allow. Residents get their own tenant shell.

| Role | Tabs (left to right) | Shell file | Badges |
|---|---|---|---|
| Owner | Home · Money · People · Property · More | `features/owner/owner_tabs.dart` via `RoleShell` | More: open complaints (read-only) |
| Warden | Home · Money · People · Property · Requests | `features/warden/warden_shell.dart` | Money: unpaid count. Requests: open complaints, plus pending leave, passes and guests from E. |
| Manager | Home · Money · Tasks · Food | `features/manager/manager_shell.dart` | Tasks: overdue |
| Resident | Home · Rent · Requests · Notices · Profile | `features/student/student_section.dart` via `RoleShell` | Rent: due. Notices: unread. |
| Super admin | Overview · Hostels · Applications (from B) · Subscriptions · Security | `features/super_admin/sa_shell.dart` | Applications: pending. Security: open alerts. |

The manager has **no People and no Property tab**. Managers never see resident data. That is the existing RLS boundary, and Phase A must not add any screen that queries `students`, `fee_payments`, `complaints`, `leaves` or `visitors` for a manager.

Tab-to-icon map:
- Owner: Home → nav-home, Money → nav-money, People → nav-people, Property → nav-property, More → more [new art].
- Warden: Home → nav-home, Money → collect-payment, People → nav-people, Property → rooms, Requests → complaint.
- Manager: Home → nav-home, Money → expense, Tasks → tasks, Food → food.
- Resident: Home → nav-home, Rent → receipt, Requests → complaint, Notices → announcement, Profile → profile [new].
- Super admin: Overview → analytics, Hostels → hostels [new] (property until the art exists), Applications → kyc, Subscriptions → subscription [new], Security → security.

### 3.3 Screen map per role

The tag says which phase brings each screen: **[A]** reskin of an existing screen, **[B]** to **[H]** new in that phase.

**Signed out**
- Splash [A, unchanged]
- Onboarding carousel [A reskin; copy refresh in B]
- Sign in [A]: AuthTopBar (brand mark plus "Book a free demo" pill, hidden until B), hero card with owner role art, "Mobile number or email" plus password, Continue with Google, legal line opening the in-app legal screens
- Forgot password sheet [A]
- Reset password (`/reset-password`, reached from the recovery link) [A]
- Create account (`/signup`): persona picker, then the stepper [B]
- Book a free demo (`/book-demo`) [B]

**Owner**
- **Home** [A, then C]:
  - Header: PG switcher, bell, search.
  - StatCarousel: hero "Collected in <month>" with progress, Occupancy, Pending dues, Open complaints.
  - One ActionBanner, when something is time-bound.
  - Pending inbox [C].
  - Quick actions: Send notice, Assign task, Staff, Property settings [C]. Add tenant and Collect payment only if D1 allows.
  - Notices, 30-day cash flow, recent activity.
  - Coach marks [C].
- **Money** [A, then D], segmented:
  - Collections: today's "who paid" list plus refunds [A]; unified rent and charge events [D].
  - Dues by category, with due today, tomorrow and overdue chips [D].
  - Deposits held and refunded [D].
  - Meters [D].
  - Expenses: month by month and by category [A], with edit and receipts [D].
  - Staff cash passbook and handovers to confirm [D].
  - UPI details plus UTR claims to confirm [D].
  - Reminders [D].
  - Reports [H].
- **People** [A, then F]:
  - Residents: read-only roster, fee history, refunds [A]; situation chips [C/F]; quick view, then profile with Overview, Passbook, Documents, Agreement, Activity [F/G].
  - Team: staff accounts, PG access, capabilities [G], activity [G], off-boarding [G].
  - Leads and bookings [F].
  - Past tenants [F].
  - Flags [F].
- **Property** [A, then C]:
  - PG list, then PG detail (floor grid and bed board), then floor plan editor [A].
  - Property settings hub, written as questions [C].
  - Room tags, default rent and availability [C].
  - Share vacant bed [C].
  - Add another PG, sent for Super Admin approval [B].
- **More** [A]:
  - Notices (compose, edit, retract), Complaints (read-only), Tasks (assign, edit [A or G], recurrence [G]).
  - Analytics [H], Help and support [H], Refer an owner [H].
  - Account: Two-factor, Change password, Terms and privacy, Sign out of all devices, Delete my account, Sign out.
- **Owner setup**, shown when the owner has no approved PG [B]: application form, pending state, rejection with reason, resubmit.
- **Plan expired** [B]: read-only banner plus "Request renewal".

**Warden**
- **Home** [A, then C/E]:
  - Header with Switch PG.
  - Counts: Rent owed, Complaints, Leave requests, Visitors on site; later Inside now [E].
  - Pending inbox [C].
  - Quick actions: Add tenant, Collect payment, Assign bed, Resolve complaint; later Gate desk and Roll call [E].
  - Notices preview, occupancy band.
- **Money** [A, then D]:
  - Rent desk: ledger by month, paid/partial/unpaid filter, record and correct [A].
  - Charges, bulk charges, meter readings, deposits, collections, reminders, receipts [D].
- **People** [A, then F]:
  - Residents: search, register with ID proof, resident sheet (payment, bed, check out, email, reset password, erasure) [A].
  - Join-code linking at registration [B].
  - Give or accept notice [C].
  - Full profile, documents, KYC, agreement, checklists, move-out, swap beds [F].
  - Leads and bookings [F].
- **Property** [A, then C/F]:
  - Floor grid with one pip per bed, room sheet, floor plan [A].
  - Bed board with under-notice [C] and booked [F] statuses.
- **Requests** [A, then E/G]:
  - Complaints queue and sheet [A]; assignment, comments, internal notes [G].
  - Leave approvals [A, E], visitors [A].
  - Gate passes, gate desk and inside now [E]; guest stays [E].
  - Roll call [E]; serve meals by code [E].

**Manager**
- **Home** [A]: masthead, StaffHostelBar, task KPIs, money in and out today, today's tasks, category breakdown (replacing the in/out bars).
- **Money** [A, then D]: expenses and revenues ledger [A]; edit, void, receipt photo, vendor [D]; petty cash and handovers [D]; expense stats [A].
- **Tasks** [A, then G]: own tasks, status change.
- **Food** [A, then E]: weekly menu [A]; copy a day or to another PG, meal settings, food counts without names [E].

**Resident**
- **Home** [A, then C/E]:
  - Greeting header, verify-email banner, rent card, room and bed.
  - Today's menu (opens the menu screen) and contacts.
  - Quick actions: Pay rent, Raise complaint, Apply leave [E], Food menu.
  - Meal confirmation block [E].
  - Waiting-for-PG state with join code [B]; link request to accept [B].
- **Rent** [A, then D]:
  - This month, Pay (Razorpay only when available) [A/D], pay at the desk note, refunds, history, receipts [A].
  - Dues by category, deposit held, passbook, UPI pay with UTR [D].
- **Requests** [A, then C/E/F/G]:
  - Complaints [A]; rate and reopen [G].
  - Give notice [C]; leave [E]; gate pass with code [E]; guest stay [E]; checklist confirm and agreement sign [F].
- **Notices** [A, then G]: paged list; read receipts [G].
- **Profile** [A, then F]:
  - Own details, roommates.
  - Account: Change password (fixed), Two-factor, Terms and privacy, Delete my account, Sign out [A].
  - Edit allowed fields, documents, food preference [E/F].

**Super admin**
- **Overview** [A]: KPIs, subscription health, onboarding chart, security band.
- **Hostels** [A]: search, detail, controls, payout, create wizard.
- **Applications** [B]: owner PG applications to approve or reject (with trial dates), demo requests to confirm or close, referral attribution [H].
- **Subscriptions** [A].
- **Security** [A].
- **Support tickets** [H], reached from Overview.

---

## 4. Phased roadmap

Every phase below lists:
- its goal, estimate and release;
- waves, where the workstreams inside a wave run in parallel and own disjoint files;
- per workstream: its layers, the files it owns, whether it changes the live database, whether it needs a legal bump, and the spec;
- the deploy order and the exit criteria.

`{D}` means the authoring date at implementation time.

Phrasing used in the RPC specs:
- "auth:" is the first statement of the function.
- "writable" means `app.hostel_writable(hostel)` is checked.
- "spend(b, n, s)" means `perform app.spend('b', n, s, '<sentence>')`.
- "audit 'x'" means `public.audit_event('x', ...)` with `surface 'rpc'`.

Every RPC also does the following unless its spec says otherwise:
- is SECURITY DEFINER with `set search_path = ''`, every name schema-qualified;
- returns P0001 with a sentence a user can read for every refusal they can reach, and 42501 for authorisation;
- has EXECUTE revoked from public and anon by name, and granted to authenticated.

---

### Phase A: design system, new shells, reskin, client-only fixes

**Goal.** Every role sees the Forest & Cream look and the new tab structure. Three broken client paths are fixed. Nothing on the server changes and nothing new is collected, so there is no legal bump.

**Estimate.** 6 to 9 working days build, about 2 weeks calendar. **Release:** 1.3.0 (internal track first), or bundled with B.

**Rules for this phase**
- No live database change and no new data collection. Fonts and images are bundled assets only.
- Copy changes only where the design requires them: tab labels, sentence-case section headers, the Account rows. The honest error sentences that tests assert stay word for word.
- Test migration happens in the same workstream that changes the screen. The total test count must not fall; each workstream reports before and after counts.
- The gate suites stay green with no assertion weakened: `router_redirect_test`, `role_routing_test`, `auth_session_loop_test`, `auth_throttle_test`, `mfa_*`, `email_verification_test`, `legal_consent_test`, `startup_test`, `splash_*`, `retry_policy_test`, `data_deadline_test`, `repository_states_test`, `refusal_honesty_test`, `silent_controls_test`.
- These stay as they are:
  - TabWarmer and the IndexedStack of visited tabs;
  - the `ValueKey(hostelId)` on the warden and manager shells;
  - the lifecycle listener in RoleShell;
  - `apnivaasRetry`, `guard()` deadlines and `settleRefresh`;
  - the 0.9–1.4 text clamp and the portrait lock;
  - the release ErrorWidget replacement and `PlatformDispatcher.onError`.
- No BackdropFilter, no `repeat()`, no new package except the font and image assets.

#### Wave A1: tokens, type and assets (one workstream, lands first)

**A1. Design tokens, typography, fonts, clay assets**

> **State of the working tree when this plan was written (2026-10-18), uncommitted and not produced by this plan:**
> - `lib/core/theme/{tokens,theme,typography}.dart` are already rewritten for Outfit and Manrope (about 1,300 lines changed).
> - Outfit-Medium, Outfit-SemiBold, Outfit-Bold and Manrope Regular, Medium, SemiBold and Bold TTFs sit in `apnivaas_app/google_fonts/`. That is the design notes' fallback option: keep the `google_fonts` package with `allowRuntimeFetching = false`.
> - 54 WebPs are in `apnivaas_app/assets/clay/`, and a `ClayIcons` enum is at `apnivaas_app/lib/shared/clay/clay_icons.dart`.
> - The typography header records a measurement: **Manrope has ₹ and `tnum`; Outfit has `tnum` but no ₹.** So the Manrope fallback on Outfit styles is mandatory.
>
> **A1 therefore starts by reviewing and finishing that work, not redoing it.**
> - Adopt its paths: fonts in `google_fonts/` and the enum in `lib/shared/clay/`. Every later reference in this plan to `assets/fonts/` or `lib/shared/ui/clay_icon.dart` means those paths.
> - Decide whether Outfit-Medium (500) ships; the spec uses only 600 and 700.
> - Then complete the items below that are still missing: tests, platform edges, docs.

- Layers: Flutter theme, assets, Android and iOS resources, tests, docs.
- Owns:
  - `apnivaas_app/lib/core/theme/**`, `apnivaas_app/lib/shared/clay/**` (in progress), `apnivaas_app/lib/shared/ui/clay_icon.dart` (new widget wrapping the enum)
  - `apnivaas_app/google_fonts/**` (in progress), `apnivaas_app/assets/clay/**` (in progress)
  - `apnivaas_app/pubspec.yaml`, `apnivaas_app/lib/main.dart`
  - `apnivaas_app/android/app/src/main/res/values*/colors.xml`, `apnivaas_app/ios/Runner/Base.lproj/LaunchScreen.storyboard`
  - `scripts/clay-webp.mjs` (new), `docs/design-system.md`
  - Tests: `apnivaas_app/test/theme_contrast_test.dart`, `colour_and_motion_test.dart`, `fonts_test.dart` (new), `clay_assets_test.dart` (new)
- Live DB change: no. Legal bump: no.

Spec:
1. **Fonts.** The TTFs are already in `apnivaas_app/google_fonts/` (see the note above). Keep the `google_fonts` package with `allowRuntimeFetching = false` at line 32 of `main.dart`, which is the documented fallback, unless A1 chooses to move to plain `flutter: fonts:` families and remove the package. Either way, no runtime fetch is possible.
   - Add `OFL.txt` and register it with `LicenseRegistry.addLicense`.
   - If any file is missing, fetch it from the google/fonts repository with `curl`; the Norton TLS note in the project memory applies.
   - Delete the four Inter files and remove their mention from `pubspec.yaml`, unless they are kept as the ₹ fallback. Manrope covers ₹, so they should go.
   - `fonts_test.dart` parses the TTF tables from bytes, with no decoding of images. It asserts that `cmap` has U+20B9 (₹) in Manrope and, if present, in Outfit; that Manrope has the GSUB `tnum` feature; and that every file has a distinct `usWeightClass` and a distinct `glyf` hash.
   - If Manrope lacks ₹, keep Inter-SemiBold and Inter-Bold as a fallback-only family and say so in `typography.dart`.
2. **Typography.** Implement the slot table and the `ApnivaasTextRoles` extension from Appendix A.5.
   - Outfit styles use `fontFamilyFallback: ['Manrope']` and `leadingDistribution: even`.
   - Every slot keeps its current job.
   - Remove `.toUpperCase()` in `DashboardBand`, `GlassStatCard` and the `ToneSurface` status word. Those files are A2b's; A1 only changes the shared label style, and A2b removes the calls.
3. **Tokens.** Re-point the legacy names per Appendix A.11: background, surface, lightSheet, lightField, textPrimary, textSecondary, mutedInk, lightPrimary, indigo, brandInk, roomsInk, brandDeep, controlBorder, cardBorder, hairline, the status inks and the canonical colours. Domain tones fold into brand and status.
   - Add the new raw palette constants, the dark table, radii (control 14, button 16, buttonLarge 18, well 22, card 24, hero 28, header 30, pill 999), Shadows e1 to e3, Space hair 2 and tight 6, Motion exit 200ms and the emphasis curve, and component geometry constants (for example `StatTileInsets`).
   - Delete `Motion.glassFallback` and `_decideGlassBudget` in `main.dart`.
4. **Theme.**
   - FilledButton: Forest and white in light; Mist and Forest in dark.
   - Input fill is the card colour, with border `#8F8679` 1.5px, focus Forest 2px and error `#B3261E` 2px.
   - Snackbar is ink. `bottomSheetTheme` radius is 28. The page transitions are unchanged.
   - `systemBars()` gives light icons on the header.
5. **Clay assets.** `scripts/clay-webp.mjs` converts `design-3d/icons-v3/*.png` to WebP with alpha (quality about 90). Use `sharp` from the website's `node_modules` if present, otherwise `cwebp`.
   - Ship the 41 feature icons, the 4 nav-on icons, and role-owner, role-tenant, role-manager and role-warden.
   - Do not ship the `nav-*-off` files (runtime greyscale replaces them), role-seeker, role-owner-man, role-owner-mascot, any icon sheet, the mascot master or icons-v2.
   - Write to `assets/clay/` and declare that directory. Target 1.5 MB or less in total; measure it and record the number in `docs/design-system.md`.
   - Also add `assets/brand/apnivaas_mark_256.webp`, from `design-3d/apnivaas-mark-256.png`.
6. **`ClayIcon` and the `ClayIcons` enum** (Appendix A.10, ClayIcon).
   - `cacheWidth = size × devicePixelRatio`; `excludeFromSemantics` unless a label is given; a greyscale `ColorFilter.matrix` constant.
   - `clay_assets_test.dart` loads every enum value through `rootBundle` and asserts more than 1 KB, a `RIFF....WEBP` header, and the dimensions read from the VP8X or VP8L header bytes. It never decodes an image (machine hazard).
7. **Platform edges.**
   - Android `apnivaas_ground_light` changes from `#EEF0F8` to `#F6F2EA`. Keep `splash_ground #EBE3D8` and re-measure it against the WebP border the way `gen-icons.mjs` does.
   - `_BrokenScreen` and `StartupFailure` in `main.dart` use the literals ground `#F6F2EA`, ink `#1C2B26` and a Forest button. They stay theme-independent.
   - The iOS LaunchScreen matches.
8. **`theme_contrast_test.dart` rewrite.**
   - Keep the `_luminance` and `_ratio` helpers.
   - Replace the groups "Figma hex for hex", "filled button is cream", "light brand is violet" and "Inter only" with Appendix A's light and dark text pairs, the chip table, the 3:1 control table and the header inks measured on `#1F6150`.
   - Every ratio quoted in a comment in `tokens.dart` must be asserted.
9. **`docs/design-system.md`.** Replace it with Appendix A of this plan, plus the measured asset sizes.

#### Wave A2: shared components (two parallel workstreams)

**A2a. Navigation, surfaces and controls**
- Layers: Flutter shared UI, the four shells' navigation only, tests.
- Owns:
  - `apnivaas_app/lib/shared/ui/header/**`, `lib/shared/ui/nav/**`
  - `lib/shared/ui/sheet.dart`, `lib/shared/ui/buttons.dart`, `lib/shared/ui/inputs.dart`, `lib/shared/ui/choice_chips.dart`, `lib/shared/ui/persona_card.dart`, `lib/shared/ui/stepper.dart`
  - `lib/shared/glass/glass.dart`, `lib/shared/brow.dart`, `lib/shared/brow_header.dart`, `lib/shared/aurora.dart`, `lib/shared/beam_card.dart`, `lib/shared/wordmark.dart`
  - `lib/features/shell/role_shell.dart`, `lib/features/warden/warden_shell.dart`, `lib/features/manager/manager_shell.dart`, `lib/features/super_admin/sa_shell.dart`
  - Tests: `responsive_test.dart`, `brow_test.dart` (renamed `header_test.dart`), `brow_header_test.dart` (merged into it), `tab_bar_test.dart` (new), `controls_test.dart` (new)
- Live DB change: no. Legal bump: no.

Spec:
- **ApnivaasHeader**, all variants (dashboard, sub-page, sign-in hero card), with the stars `CustomPainter` in a `RepaintBoundary` that has `shouldRepaint` false.
  - The header resolves its own inks, keeping the BrowTitleBlock contract: callers pass strings.
  - Semantics: "<PG name>, switch property" and "Notifications, N unread".
- **HeaderSearchField** pushes the search route. In A that route is a placeholder `SearchComingSoon` sheet; C replaces it.
- **ApnivaasTabBar** per Appendix A.10, replacing NavigationBar in RoleShell (owner and student bars) and in the warden, manager and SA shells. A2a changes only the bar widget; the tab lists are changed by the role workstreams in wave A3.
  - Keep the badges.
  - Keep `responsive_test`'s "taller at 1.4x than at 1.0x, at most 88" assertions, pointed at `ApnivaasTabBar` instead of `NavigationBar`.
  - Precache the tab icons on shell mount.
- **`showApnivaasSheet`**. `showGlassSheet` becomes a thin wrapper over it, so about 40 call sites keep compiling. The sheet owns its grip. Keyboard insets come from `viewInsets`.
- **Buttons, inputs and ChoiceChipGrid** per Appendix A.10. The Google button is not restyled; only its height moves to 50.
- **PersonaCard and OnboardingStepper** are built here, for B to use.
- **Retire** BeamCard (an infinite 6-second loop) and AuroraField. Remove BrandBrow, BrowClipper, BrowMotif and BrowLightPainter.
  - GlassSurface, FlatSurface, ToneSurface and GlassCard keep their names and paint the new look: card fill plus a 1px `outlineVariant`, radius 24.
  - Keep exported names that other features import, as deprecated shims, until wave A3 removes the call sites. Delete the shims at the end of A3.
- **RoleShell**: swap the bar and the header only. The AppLifecycleListener calling `syncActiveHostel()` and UpdateBannerHost stay exactly where they are.
- **Tests.**
  - Tab bar at 320 and 412dp × 1.0, 1.3 and 2.0, light and dark.
  - Selected semantics; reduce motion means no animation controller ticks.
  - A header ink contrast test on `#1F6150`.
  - A no-pending-timers test after `pumpAndSettle` for every component.

**A2b. Content components**
- Layers: Flutter shared UI, tests.
- Owns:
  - `apnivaas_app/lib/shared/ui/{stat_tiles,quick_actions,list_group,section_header,status_chip,empty_state,skeleton,banners,info_sheet,paged_list}.dart`
  - `lib/shared/dashboard.dart`, `lib/shared/illustrations.dart`, `lib/shared/smiley.dart`, `lib/shared/meter.dart`, `lib/shared/motion/**`
  - Tests: `illustration_assets_test.dart`, `components_test.dart` (new), `paged_list_test.dart` (new)
- Live DB change: no. Legal bump: no.

Spec:
- **StatCarousel, HeroStatTile, StatTile and LinkTile.** At 1.6x or more on screens under 400dp the carousel becomes a 2-column Wrap. Figures sit in `FittedBox(scaleDown)`.
- **QuickActionGrid.**
  - Columns come from `LayoutBuilder` and text scale: 4 below 1.5x, 3 below 1.8x, otherwise an icon-left 2-column layout. Also 3 when the content width is under 300.
  - Press scales to 0.94 with a `selectionClick` haptic.
  - "View all" opens a sheet grouped Money / Documents and insight / Tenants and people / Property and rooms / Operations.
- **ListGroup and ListRow.** The trailing control is its own semantics target and wraps below the text when narrow.
- **SectionHeader**, sentence case.
- **StatusChip.** Mapping: paid, resolved and occupied are success; due, pending and expiring are warning; overdue, failed and rejected are error; refund, new and info are info; draft, sample and inactive are neutral. A chip always carries a word. Also the count badge and the unread dot (gold only on forest or dark surfaces).
- **EmptyState.** Variants: first run, no match (32dp glyph, no art), error (`errorGuidance` plus "Try again") and offline.
  - Until clay scenes exist, use a ClayIcon 96 on a 136 Mist disc.
  - The 4 flat PNGs in `assets/illustrations` stay declared until the clay scenes ship. Update `illustration_assets_test` accordingly.
- **SkeletonLoader.** One pulse controller per screen (1.0 to 0.55 opacity over 1200ms), disposed when data arrives. Static 0.8 under reduce motion.
- **ActionBanner, InfoBanner and InfoNote.** At most one ActionBanner per screen.
- **`info_sheet.dart`**: a metric-explanation sheet. It is only a component here; C writes the copy.
- **PagedList**: one implementation that keeps `PagedNotifier` returning loadMore failures inline and the bounded `settleRefresh`. The three `paged_list.dart` copies (warden, manager, student) migrate to it in wave A3.
- **`dashboard.dart`**: map `EssentialTile` and `ToolTile` onto StatTile and the QuickAction tile. Keep the names as shims until A3.

#### Wave A3: screens per role (six parallel workstreams)

Each role workstream does the same five things:
1. Rebuild its role kit (`warden_ui.dart`, `manager_ui.dart`, `sa_ui.dart`, `student/widgets/common.dart`, `owner/widgets/states.dart`) onto `lib/shared/ui`, keeping a re-export shim only while its own screens migrate. SectionLabel, EmptyNote, ErrorNote, ToneBadge, Skeleton and the pills come from the shared components.
2. Restructure its tabs to the map in section 3.2.
3. Reskin every screen and sheet it owns, including skeleton, empty, error, read-only and not-permitted states.
4. Add `keys.dart` keys and migrate its tests.
5. Remove its shim imports.

**A3-owner. Owner screens**
- Owns: `apnivaas_app/lib/features/owner/**`; tests `owner_test.dart`, `owner_dashboard_widget_test.dart`, `owner_layout_test.dart`, `owner_notices_test.dart`, `owner_floor_plan_test.dart`, `owner_rooms_widget_test.dart`, `owner_staff_test.dart`, `owner_shell_warmup_test.dart`.
- Layers: Flutter. Live DB change: no. Legal bump: no.
- Spec:
  - `owner_tabs.dart` becomes Home / Money / People / Property / More, with TabWarmer and IndexedStack kept.
    - Home is the dashboard: StatCarousel, notices, cash flow, insights, and quick actions that stay read-only (decision D1).
    - Money holds the payments list, refunds and ExpenseStats (pushed).
    - People holds the residents roster and fee history, plus Team: the staff screen moves out of More.
    - Property holds the PG list, PG detail, floor plan and the edit-room sheet.
    - More holds Notices, Complaints, Tasks and Account.
  - Notice edit UI and task edit UI: first read live `pg_policy` for `announcements` and `tasks` UPDATE (read-only query; ask the owner's go-ahead to run it). If an owner UPDATE of title and body is permitted, wire `NoticeRepository.update` and `TaskRepository.update` with tests. If not, leave them for G and record that.
  - The owner header shows the PG switcher (existing data).

**A3-warden. Warden screens and shared desk pieces**
- Owns: `apnivaas_app/lib/features/warden/**` except `warden_shell.dart`'s bar widget (A2a has finished with it by now, so the file passes to this workstream), `lib/features/common/**`, `lib/shared/rooms/**`; tests `warden_test.dart`, `warden_register_student_test.dart`, `warden_bed_picker_test.dart`, `warden_erasure_test.dart`, `warden_shell_warmup_test.dart`, `staff_hostel_switch_test.dart`.
- Layers: Flutter. Live DB change: no. Legal bump: no.
- Spec:
  - Tabs: Home / Money (rent desk) / People (students) / Property (rooms) / Requests (complaints queue, plus the leave and visitor sheets reachable from Requests and from the Home counts).
  - Badges: unpaid on Money, open complaints on Requests.
  - `wardenTabProvider` indexes are remapped, and every `ref.read(wardenTabProvider.notifier)` jump is updated.
  - StaffHostelBar keeps its behaviour.
  - Temporary-password dialogs stay hard to dismiss.

**A3-manager. Manager screens**
- Owns: `apnivaas_app/lib/features/manager/**`, `lib/shared/finance/**`; tests `manager_test.dart`, `manager_warmup_test.dart`.
- Layers: Flutter. Live DB change: no. Legal bump: no.
- Spec:
  - Tabs: Home / Money (expenses and revenues) / Tasks / Food (menu).
  - The Home categorized-expense slot uses `rpc_expense_months`, with category totals for the current month. It replaces the in/out bars in that slot; the in/out figures stay as tiles.
  - No resident data anywhere.

**A3-resident. Resident screens and payments UI**
- Owns: `apnivaas_app/lib/features/student/**`, `lib/features/payments/**`; tests `student_test.dart`, `student_screens_test.dart`, `student_menu_test.dart`, `student_warm_tabs_test.dart`, `pay_rent_test.dart`, `pay_at_desk_test.dart`, `receipt_test.dart`, `refund_legibility_test.dart`.
- Layers: Flutter. Live DB change: no. Legal bump: no.
- Spec:
  - Tabs: Home / Rent / Requests (complaints) / Notices / Profile.
  - The menu stays reachable from Home and from a Requests entry.
  - Profile's Change password moves to a pushed route (fix 1; see A3-auth).
  - Receipt paper keeps its own receipt tokens, which are legitimate literals, but restyles its frame.
  - PayRentButton behaviour is unchanged (D will gate it).

**A3-admin. Super admin screens**
- Owns: `apnivaas_app/lib/features/super_admin/**` (except `sa_shell.dart`'s bar, as with the warden); tests `super_admin_test.dart`, `super_admin_controls_test.dart`, `super_admin_warmup_test.dart`.
- Layers: Flutter. Live DB change: no. Legal bump: no.
- Spec: four tabs as today, reskinned. CreateWizard uses OnboardingStepper. The credentials dialog stays hard to dismiss.

**A3-auth. Auth, onboarding, legal, settings, router and core fixes**
- Owns:
  - `apnivaas_app/lib/features/auth/**`, `lib/features/onboarding/**`, `lib/features/splash/**`, `lib/features/legal/**`, `lib/features/settings/**`, `lib/features/shell/staff_profile_sheet.dart`
  - `lib/core/router/router.dart`, `lib/core/auth/**`, `lib/core/version/**`
  - Tests: `router_redirect_test.dart`, `role_routing_test.dart`, `auth_session_loop_test.dart`, `auth_throttle_test.dart`, `google_sign_in_test.dart`, `mfa_enforcement_test.dart`, `mfa_enroll_test.dart`, `email_verification_test.dart`, `legal_consent_test.dart`, `change_password_test.dart`, `change_password_finishes_test.dart`, `onboarding_test.dart`, `startup_test.dart`, `splash_opening_test.dart`, `splash_asset_bytes_test.dart`, `account_deletion_test.dart`, `reset_password_test.dart` (new), `force_update_test.dart` (new)
- Layers: Flutter (auth state, router), tests. Live DB change: no. Legal bump: no (no legal text changes; the consent copy fix is UI copy, not a policy change).

Spec:
1. **Reskin.**
   - Sign-in uses AuthTopBar and the hero card. The "Book a free demo" pill sits behind the constant `kBookDemoEnabled = false` until B.
   - The onboarding carousel uses the new grounds and clay art, replacing the hard-coded `#0F5F5B`, `#1B5E43` and `#8A3D12`.
   - MFA, SecurityScreen, change password, verify email, the consent gate, the legal reader and account deletion are reskinned.
   - The line "Accounts are created by your administrator." stays until B changes it.
2. **Fix: voluntary Change password.** Replace `Navigator.of(context).pushNamed(changePasswordRoute)` in `staff_profile_sheet.dart:168` and `student/profile_screen.dart:139` with a pushed `MaterialPageRoute(builder: (_) => ChangePasswordScreen(forced:false))`. A pushed route avoids interacting with the redirect.
   - Add a widget test that taps the row and finds the screen (the old test only checked that the label exists).
3. **Fix: password-recovery landing.**
   - Add `AuthPasswordRecovery extends AuthPhase`.
   - `actionForAuthEvent` maps `AuthChangeEvent.passwordRecovery` to a new action that writes a local marker file (`recovery_pending` in the app support directory) and sets the phase.
   - On cold start, `AuthController.build` checks the marker before resolving `AuthSignedIn`: a restored session with the marker present resolves to `AuthPasswordRecovery`.
   - `resolveRedirect` gets a new rule right after the value-less loading rule: `AuthPasswordRecovery` goes to `/reset-password`. The route is in `appScreens`, outside ConsentGate and not in `_publicRoutes`. The `to == here` guard still applies.
   - `ResetPasswordScreen` (create `lib/features/auth/reset_password_screen.dart`, the file `password_policy.dart` already refers to):
     - new password and confirm, with `PasswordStrengthMeter`;
     - calls `auth.updateUser(password)` once;
     - then `signOut(scope: global)`, deletes the marker, and goes to `/login` with the message "Password changed. Sign in with your new password.";
     - "Cancel" signs out and deletes the marker.
   - The recovery session never reaches a role home. MFA still applies at the next sign-in.
   - Tests: every redirect rule × `AuthPasswordRecovery`; a cold start with the marker present; that the marker is removed on success, cancel and sign-out.
4. **Fix: legal reader entry.** Add a "Terms and privacy" row in `staff_profile_sheet.dart` and in the resident Profile, opening `openLegal`. Change the consent copy "from the header of any screen" to "from your profile at any time"; `legal_consent_test` is updated.
5. **"Sign out of all devices"** in the profile sheet and the resident Profile:
   - confirmation sheet;
   - `pushService.stop()`;
   - `auth.signOut(scope: SignOutScope.global)`.
   - Tests use a fake client to count the call.
6. **Force update.** When `app_releases.mandatory` is true and the installed `versionCode` is lower than the manifest's, UpdateBannerHost shows a blocking screen: what changed, the build number, a "Copy download link" button and the words "Open the Play Store and update Apnivaas". No browser and no store intent.
   - The soft banner is unchanged.
   - Test: mandatory × version matrix.
7. **Router.**
   - Add `/reset-password` to `appScreens` and the matrix tests.
   - Leave placeholders for B's `/signup` and `/book-demo` out of A; B adds them.

#### Wave A4: release and store polish (one workstream)

**A4. Release, screenshots and docs**
- Owns: `scripts/release.sh`, `apnivaas_app/test/_shot.dart`, `apnivaas_app/test/_storeshot.dart`, `apnivaas_app/integration_test/**`, `docs/play-release-notes.md`, `docs/store-assets.md`, `docs/store-listing/**`.
- Layers: release tooling, docs. Live DB change: no. Legal bump: no.
- Spec:
  - `release.sh` fails the build unless the merged release manifest has exactly ten `uses-permission` entries and no `AD_ID`. Add the check if it is missing; keep it if it is present.
  - Update `_shot` and `_storeshot` for the new shells; the store screenshots stay at Play sizes.
  - `walkthrough_test.dart` walks the new tabs.
  - Release notes for 1.3.0.

**Phase A deploy order.** App only: `scripts/release.sh`, then internal track, then the owner's go-ahead for production.

**Phase A exit criteria.**
- `flutter analyze` is clean and `flutter test` is green.
- The test count is at least the pre-phase count (about 1,513).
- The contrast tests cover every new pair.
- The responsive matrix (320/375/412/430/800 × 1.0/1.3/2.0, light and dark) is green.
- The merged manifest has exactly ten permissions.
- No `Color(0x...)` literal remains in features except receipt tokens, the Google button and the two boot screens.
- No `BackdropFilter`, no `repeat()`.

---

### Phase B: onboarding, self sign-up (email and Google), owner PG applications, tenant join codes, book a demo

**Goal.** A new owner or tenant can create an account in the app; staff never can. An owner's first PG goes live only after Super Admin approval with a trial (decision D3, recorded in the project notes on 2026-10-12). A tenant who signed up is attached to their PG by the warden through a join code or a verified email, never a phone match alone, because phones are unverified without SMS. A prospect can book a free demo.

**Estimate.** 5 to 7 working days build, 1.5 to 2 weeks calendar. **Release:** 1.3.0, with A.

**Why join codes.** The owner's 2026-10-12 decision was that the warden links a self-signed-up tenant by phone or email match. Phone numbers are not verified, so anyone could sign up with someone else's number and be linked into that person's PG, seeing their rent and room. Linking therefore needs proof:
- a **join code** read from the tenant's own screen, which proves both possession of the account and presence; or
- a **verified email** match, followed by the tenant **accepting** the request.

A phone match only shows the warden a hint.

#### Wave B1

**B-db. Sign-up, applications, linking and demo schema**
- Layers: database (tables, RLS, RPCs, guards, retention).
- Owns: `db/migrations/{D}-self-signup.sql`, `.down.sql`, `.test.sql`; `db/schema.sql`; `db/rls-policies.sql`.
- Live DB change: **yes**. Legal bump: covered by B-legal.

Changes:
1. **`public.users`**
   - Add `signup_source text not null default 'admin' check (signup_source in ('admin','self_email','self_google'))`.
   - New trigger `users_self_signup_guard`, BEFORE INSERT OR UPDATE OF role, signup_source. It refuses (22023, "Only owner and tenant accounts can be created by sign-up.") any row with `signup_source <> 'admin'` and `role not in ('owner','student')`. It refuses any change to `signup_source` after insert, even from the service role.
   - This is the structural guarantee that managers and wardens are never self-sign-up.
2. **`public.hostels`**: add `property_type text not null default 'pg' check (property_type in ('pg','hostel','co_living','flats'))` and `gender_policy text null check (gender_policy in ('boys','girls','coed'))`.
3. **`public.hostel_applications`**
   - Columns:
     - id uuid pk, applicant_user_id uuid not null references public.users on delete cascade
     - pg_name text 2–120, property_type (as above), gender_policy
     - address text 5–500, locality text 2–120, city text 2–80, pincode text `^[1-9][0-9]{5}$`
     - floors smallint 1–50, rooms_per_floor smallint 1–100, beds_per_room smallint 1–20
     - referral_code text null (H wires it)
     - status text check (pending|approved|rejected|withdrawn) default pending
     - decided_by, decided_at, decision_note text ≤ 500
     - hostel_id uuid null references public.hostels
     - created_at, updated_at
   - Unique partial index: one pending row per applicant.
   - RLS: select own (`applicant_user_id = (select auth.uid())`) or `(select app.is_super_admin())`. Revoke all from anon and authenticated, then grant select. No write policy.
4. **`public.tenant_join_codes`**
   - Columns: user_id uuid pk references public.users on delete cascade; code text not null unique, 8 characters from an unambiguous 31-character alphabet with no 0, O, 1, I or L; expires_at timestamptz; created_at.
   - RLS: select own. No client writes.
5. **`public.student_link_requests`**
   - Columns: id, hostel_id, student_id (the roster row, `user_id` null), target_user_id, requested_by, method check (join_code|verified_email), status check (pending|accepted|declined|expired|cancelled), created_at, decided_at.
   - Unique partial indexes: (student_id) where pending, and (target_user_id) where pending.
   - Trigger `app.assert_student_in_hostel`.
   - RLS: target user selects own; `app.has_role_in(hostel_id,'warden','owner')` selects. No manager. No client writes.
6. **`public.demo_requests`**
   - Columns:
     - id, name text 2–80, phone `^[6-9][0-9]{9}$`, pg_name ≤ 120, city 2–80
     - bed_band check (1-20|21-50|51-100|100+), slot_start timestamptz
     - status check (requested|confirmed|done|no_show|cancelled)
     - ip_hash text, handled_by, handled_at, note ≤ 500, created_at
   - Unique partial index on slot_start where status in (requested, confirmed).
   - RLS: select for `(select app.is_super_admin())` only. Insert only by the service role, through the Edge Function.

RPCs (all return small rows or jsonb):
- **`svc_create_self_signup_profile(p_user, p_role, p_full_name, p_phone, p_email, p_source)`**
  - Service role only: revoked from public, anon and authenticated; granted to service_role; the body re-checks `app.is_service_role()`.
  - Validates: role in (owner, student) else 22023; name 2–80 on one line; phone shape; source in (self_email, self_google).
  - Inserts `public.users` with hostel_id null, status active, must_change_password false, created_by null.
  - Audit 'auth.signup.profile_created'.
- **`ow_submit_hostel_application(...)`**
  - auth: `app.user_role() = 'owner'` and `coalesce(app.mfa_satisfied(), false)` and `not app.email_verification_owed(auth.uid())`. The last one refuses with "Verify your email address before adding a PG."
  - Validates every field. spend('hostel_application', 5, 86400). At most one pending application.
  - Insert. Notify every active super admin: type 'system', title "New PG application", body "<PG>, <city>", link '/super-admin?tab=applications'.
  - Audit 'owner.hostel_application.submit'.
- **`ow_withdraw_hostel_application(p_id)`**: applicant only, pending only. Audit.
- **`sa_decide_hostel_application(p_id, p_approve, p_note, p_sub_start, p_sub_end, p_amount)`**
  - auth: `coalesce(app.is_super_admin(), false)`. Lock the row `for update`; it must be pending.
  - On approve:
    - validate the dates (start ≤ end, end ≥ `app.today()`) and the amount (0 to 1e8);
    - call `public.sa_create_hostel_with_subscription(...)`. **Read its live body with `pg_get_functiondef` first** and match its `rooms` parameter semantics (per floor or total);
    - set hostels.property_type and gender_policy;
    - store hostel_id;
    - notify the owner: "Your PG <name> is approved. Your plan runs until <date>.";
    - audit 'sa.hostel_application.approve'.
  - On reject: the note is required (3–500); notify the owner with it; audit.
- **`ow_request_renewal(p_hostel)`**
  - auth: `coalesce(app.owns_hostel(p_hostel), false)`. Deliberately not gated on writable: it is a request and creates no obligation.
  - spend('renewal_request', 3, 86400). Notify every active super admin. Audit 'owner.subscription.renewal_requested'.
- **`my_join_code()`**
  - auth: `app.user_role() = 'student'`, `users.hostel_id is null`, and no non-vacated students row for the caller.
  - Returns the unexpired code, or creates or rotates one valid for 7 days. spend('join_code', 10, 3600).
- **`wd_link_student_account(p_student, p_join_code)`**
  - auth: `app.has_role_in(student.hostel_id,'warden','owner')`; writable; the student row is non-vacated with `user_id is null`.
  - Resolves the code to a waiting student account. A wrong or expired code gets one generic P0001 for both: "That code is not valid. Ask the resident to open Apnivaas and read the code again."
  - spend('link_student', 30, 3600).
  - Calls `app.link_student_account`, inserts an accepted link-request row as the record, deletes the code, and notifies the tenant: "You have been added to <PG>."
  - Audit 'warden.student.linked'.
- **`wd_register_student_linked(<the wd_register_student fields minus p_user>, p_join_code)`**: the roster insert plus the link in one transaction, with the same auth and validation as `wd_register_student`.
- **`wd_register_student_pending_link(<the same fields>, p_target_user)`**: the roster insert plus a pending `verified_email` request. Callable only through the Edge Function, which matched the verified email with the service role.
  - Both register variants call a new internal `app.insert_student_roster(...)`. `wd_register_student` itself is not redefined.
- **`st_respond_link_request(p_request, p_accept)`**
  - auth: the request's target_user_id is `auth.uid()`, it is pending, and the caller's role is student.
  - Accept calls `app.link_student_account`. Decline notifies the requester. Audit either way.
- **`app.link_student_account(p_student, p_user)`** (schema `app`, not exposed)
  - Sets the transaction-local flag `app.linking_student = <student id>`.
  - Updates users.hostel_id, then students.user_id, then clears the flag.
- **`sa_update_demo_request(p_id, p_status, p_note)`**: super admin only. Audit.

Guard changes (md5-guarded against live):
- **`app.users_update_guard`** gets one new arm. A student's `hostel_id` may move from NULL to H only when all of these hold:
  - `current_setting('app.linking_student', true)` names a non-vacated students row in H whose `user_id` is null or equals the target;
  - a link-request row exists for that pair with status pending or accepted in this transaction;
  - the caller is that resident or has the warden/owner role in H.
  - A client cannot create that request row, so this arm cannot be reached directly.
- **`students_identity_guard`**: confirm on live that NULL to a same-hostel student account is allowed. If not, add that arm.

Retention (`app.apply_retention` redefinition, md5-guarded):
- Pending link requests older than 14 days become expired.
- Expired join codes are deleted.
- Demo requests are deleted 180 days after slot_start.
- Self-created accounts are deleted through `auth.users`, so the profile cascades:
  - a tenant with no students row ever linked and `last_sign_in_at` older than 90 days (or never);
  - an owner with no approved or pending application, inactive for 90 days;
  - any self-created account whose email is unverified 7 days after creation and that has never signed in.

`.test.sql` sections (the 2026-09-30 format):
- the profile function refuses manager, warden and super_admin with the exact sentence;
- the guard refuses a staff self-signup insert even as the service role;
- an owner without email proof is refused; an aal1 owner who has a factor is refused (MFA);
- the application lifecycle, including approve creating hostel, subscription and scaffold, and binding owner.hostel_id;
- another owner sees no application; a manager sees no link request;
- a join code that is wrong, expired or right; a direct `update users set hostel_id` by a student is refused;
- verified-email pending link, then accept, then decline;
- a waiting tenant calling every `st_*` RPC gets empty results and no error;
- demo slot uniqueness;
- every retention rule.

#### Wave B2 (parallel)

**B-edge. Edge Functions**
- Layers: Edge Functions, QA scripts.
- Owns: `supabase/functions/self-signup/**` (new), `supabase/functions/book-demo/**` (new), `supabase/functions/_shared/google.ts` (new), `supabase/functions/mobile-auth/index.ts`, `supabase/functions/warden-register-student/index.ts`, `scripts/_qa-signup.mjs` (new), `scripts/_qa-demo.mjs` (new).
- Live DB change: no (deploys Edge Functions). Legal bump: covered by B-legal.

Spec:
- **`_shared/google.ts`**: move the Google ID-token verification out of mobile-auth unchanged (jose, `GOOGLE_WEB_CLIENT_ID`, issuer check, nonce, `email_verified` required). Mobile-auth imports it with no behaviour change, and `_qa-login.mjs` must pass.
- **`self-signup`** (`verify_jwt` on, anon key in the header; POST JSON of 8 KB or less):
  - **Action `email`**, body {persona: owner|tenant, fullName, email, phone, password}:
    - Validator: the email must not end in `@student.hostelpro.local`; the password follows the `_shared/password.ts` policy.
    - Rate limits, fail closed: `signup:ip:` 5 per hour and 20 per day; `signup:email:<sha256>` 3 per day; `signup:global` 500 per day.
    - If `login_account_for_email` finds any row: respond `{ok:true, data:{next:'sign_in'}}` with "If this address can be used, sign in with it now." Create nothing; audit 'auth.signup.duplicate' with a hashed address. This avoids account enumeration.
    - Otherwise:
      - `auth.admin.createUser({email, password, email_confirm:true})`. `email_confirm` is true because "Confirm email" is on and the password grant needs it. The app-level proof `email_verified_at` stays null until the link is clicked, exactly as for staff today.
      - Then `svc_create_self_signup_profile`. On any failure, delete the auth user; if that rollback fails, audit the orphan id.
      - Audit 'auth.signup.created'.
    - The app then signs in through mobile-auth's `signin`.
  - **Action `google`**, body {persona, idToken, nonce, phone}:
    - Verify the token. Spend the per-address budget shared with sign-in.
    - If an account exists, refuse with "You already have an account. Use Continue with Google on the sign-in screen."
    - Otherwise:
      - `createUser({email, email_confirm:true})`;
      - create the profile with source self_google and the name clipped from the token;
      - set `email_verified_at = now()` with the service client (Google proved the address, as in `email_link_proof` arm C);
      - run the GoTrue id_token grant through the same code path as mobile-auth `google`, and return the session.
    - The identity guard trigger already admits Google for owner and student.
  - Persona values other than owner or tenant: 400. Errors are generic, carry a fieldErrors map, `Cache-Control: no-store`, and brand-free sentences.
- **`book-demo`** (`verify_jwt` on, anon key):
  - **Action `slots`**: the next 14 IST days excluding Sundays, 10:00 to 18:30 every 30 minutes, each with a `taken` flag. Per-IP 60 per 5 minutes.
  - **Action `book`**, body {name, phone, pgName, city, bedBand, slotStart}:
    - The slot must be one of the generated ones and more than 2 hours away.
    - Limits, fail closed: per-IP 3 per hour, per phone hash 2 per week, global 200 per day.
    - Service insert. A unique violation returns "That slot was just taken. Pick another time."
    - Notify each active super admin. Audit 'demo.requested' with the phone hashed.
    - Return {slotStart, reference}.
- **`warden-register-student`**:
  - With `joinCode` in the body: after the existing checks and the ID-proof upload, call `wd_register_student_linked` through `callerClient`. No auth user and no temporary password. The response is `{linked:true}`.
  - Without a join code: look up, with the service client, a waiting self-signup student whose `users.email = lower(email)` and whose `email_verified_at` is set. If found, call `wd_register_student_pending_link` and respond `{pendingLink:true}`, with no password.
  - Otherwise the existing flow runs.
  - A phone-only match never links. Uploaded files roll back on failure as today.
- **Tests.** Deno tests for the validators and the slot generator. QA scripts create and clean up throwaway accounts and run only with the owner's go-ahead against live.
- **Deploy:** self-signup and book-demo (new), mobile-auth and warden-register-student (changed). No new secrets. "Allow new users to sign up" stays OFF in Supabase; accounts are created by the admin API.

**B-signup-app. Personas, sign-up stepper, tenant waiting screen, book a demo**
- Layers: Flutter features, auth controller, tests.
- Owns: `apnivaas_app/lib/features/signup/**` (new), `apnivaas_app/lib/features/demo/**` (new), `apnivaas_app/lib/core/auth/**`, `apnivaas_app/test/signup_test.dart` (new), `book_demo_test.dart` (new), `tenant_waiting_test.dart` (new), `auth_session_loop_test.dart`, `google_sign_in_test.dart`.
- Live DB change: no. Legal bump: covered by B-legal.

Spec:
- **Persona picker.** Three PersonaCards (Owner, Tenant, Staff) as full-width rows, as a radio group.
  - Staff shows the InfoNote "Managers and wardens don't sign up here. The PG owner creates your account and gives you your login." and the CTA "Sign in with my staff login", which goes to `/login`.
  - There is no code path from Staff to any sign-up call.
- **Stepper.**
  - Owner: who you are, then account (full name, mobile, email, password, or Continue with Google), then submit.
  - Tenant: the same steps.
  - After submit:
    - email path: `AuthController.signIn` with the same credentials;
    - Google path: a new `AuthController.signUpWithGoogle(persona, phone)`, which uses `GoogleIdTokenSource` and the new self-signup action, then installs the session through the existing `_installingSelf` path.
  - From there the router's existing gates take over: /mfa-setup for owners, the consent gate, /verify-email for owners.
  - Sign-in progress must not move into `authControllerProvider` (the splash-flash rule).
- **TenantWaitingScreen**:
  - the join code from `my_join_code` in large type, with copy;
  - "Show this code to your warden";
  - pending link requests with Accept and Decline (`st_respond_link_request`);
  - the verify-email banner and Sign out;
  - a recheck on resume.
- **BookDemoScreen**:
  - fields: name, mobile, PG name, city; bed band (ChoiceChipGrid); day chips and time chips from `slots`, with taken slots disabled;
  - the line "By booking you agree to the privacy policy", opening the in-app reader;
  - a LargeCta that names the slot;
  - a success state with the reference.
  - The submit button is disabled while pending, and the request id is reused on retry. Honest offline, rate-limit and slot-taken messages.
- **Tests:** the persona routing invariants, validation, fake Edge Function clients that count round trips, the Google sign-up with a fake token source, the waiting-screen states, the booking flow. All by keys.

**B-owner-setup-app. Owner PG application and plan states**
- Layers: Flutter feature, tests.
- Owns: `apnivaas_app/lib/features/owner_setup/**` (new), `apnivaas_app/test/owner_setup_test.dart` (new).
- Live DB change: no. Legal bump: covered by B-legal.

Spec:
- **OwnerSetupScreen**, exported for B-integration to show when the owner owns no hostel. It reads the owner's `hostel_applications` through RLS:
  - none: the OnboardingStepper form, in four steps: Your PG (name, type, boys/girls/co-ed); Where (address, locality, city, pincode, typed with no map); Size (floors, rooms per floor, beds per room); Review. Submits with `ow_submit_hostel_application`.
  - pending: "We're reviewing <PG>. Apnivaas will call you on <phone>.", with Withdraw.
  - rejected: the reason, then edit and resubmit.
- **"Add another PG"**: the same form, exported for the Property tab.
- **PlanExpiredBanner**: shown when the PG's subscription state is expired or the hostel is read-only. "Your plan has ended. Everything is read-only." plus "Request renewal" (`ow_request_renewal`), with a confirmation and a disabled "Requested today" state.
- **Tests:** every state, the validation, and the billing-word refusal honesty.

**B-admin-warden-app. Super Admin approvals and the warden's linking UI**
- Layers: Flutter features, tests.
- Owns: `apnivaas_app/lib/features/super_admin/applications/**` (new), `apnivaas_app/lib/features/warden/actions/register_student_sheet.dart`, `apnivaas_app/lib/features/warden/actions/student_credentials_dialog.dart`, `apnivaas_app/lib/features/warden/students/student_sheet.dart`, `apnivaas_app/test/sa_applications_test.dart` (new), `warden_link_test.dart` (new), `warden_register_student_test.dart`.
- Live DB change: no. Legal bump: covered by B-legal.

Spec:
- **SA Applications screen**, with two segments:
  - Owner PGs: approve, with a sheet carrying the trial start, end and amount defaults from D3, calling `sa_decide_hostel_application`; or reject with a reason.
  - Demo requests: copy the number, set the status.
- **Register sheet**: an optional "Join code" field labelled "Resident already has Apnivaas? Enter the code from their screen."
  - The result dialog has three variants: credentials (existing, still hard to dismiss), "Linked to <name>'s account", and "Request sent; they must accept it".
  - Invite text through `share_plus` carries the login id and the PG name, and **never the password**.
- **Student sheet**: "Link app account", for roster rows with no login, calls `wd_link_student_account`.
- **Tests.**

**B-legal. Legal version "signup"**
- Layers: legal migration, website legal pages, in-app legal text, docs.
- Owns: `db/migrations/{D}-legal-version-signup.sql`, `app/legal/**`, `lib/legal-config.ts`, `apnivaas_app/lib/features/legal/legal_documents.dart`, `apnivaas_app/test/legal_consent_test.dart`, `docs/data-safety.md`, `docs/google-sign-in.md`.
- Live DB change: **yes** (a `legal_versions` row). Legal bump: **yes**.

Spec. The privacy policy and terms add:
- self-created owner and tenant accounts, and Google sign-up;
- PG application data (address, locality, city, pincode, size) and Super Admin review;
- trial and plan terms on approval;
- demo requests from people without an account: name, mobile, PG name, city and bed band, used only to call back, deleted after 180 days;
- join codes;
- deletion of inactive self-created accounts after 90 days.

The terms state that managers and wardens are created only by owners. Also update the Data safety evidence and the version parity test.

#### Wave B3

**B-integration. Routes, login, shells**
- Layers: Flutter router and shells, tests.
- Owns: `apnivaas_app/lib/core/router/router.dart`, `apnivaas_app/lib/features/auth/login_screen.dart`, `apnivaas_app/lib/features/owner/owner_tabs.dart`, `apnivaas_app/lib/features/super_admin/sa_shell.dart`, `apnivaas_app/lib/features/student/student_section.dart`, `apnivaas_app/test/router_redirect_test.dart`, `apnivaas_app/test/role_routing_test.dart`.
- Live DB change: no. Legal bump: no.

Spec:
- **Router.** Add `/signup` and `/book-demo` to `appScreens` and `_publicRoutes`. Signed-in users on them go home: extend rule 7's list. The matrix tests cover both routes for every phase.
- **Login.**
  - Add "Create an account".
  - Set `kBookDemoEnabled = true`.
  - Replace "Accounts are created by your administrator." with "Managers and wardens: your PG owner creates your login."
- **`owner_tabs.dart`**: an owner with no owned hostels sees OwnerSetupScreen instead of the tabs, and the Property tab gets "Add another PG".
- **`sa_shell.dart`**: an Applications tab with a pending badge.
- **`student_section.dart`**: a resident with no students row sees TenantWaitingScreen.

**Phase B deploy order.**
1. B-db test, then apply.
2. Deploy the four Edge Functions.
3. Legal row live.
4. Website push.
5. App build.

**Phase B exit criteria.**
- All SQL tests pass, and QA scripts pass against live with cleanup.
- The router matrix covers the new routes.
- Three independent checks prove staff cannot self-sign-up: the persona routing test (UI), the self-signup persona refusal (Edge Function), and the users guard (database).
- The merged manifest still has ten permissions.

---

### Phase C: property and rent settings as questions, tenancy notice, home blocks, inbox, search, push-tap routing

**Goal.**
- Owners answer plain questions that set the PG's rules: due day, grace, type, who stays, lock-in, notice, house rules, receipt terms and contact. The money rules (late fine, deposit, joining fee, proration) are stored now and switched on in D.
- Residents can give notice, and wardens can accept it.
- Homes become independent blocks with a pending inbox.
- Search, the notification inbox and push taps work.
- Daily aggregate snapshots start, so H has history.

**Estimate.** 5 to 7 working days build, about 1.5 weeks calendar. **Release:** 1.4.0, with D. It can ship alone; the money questions stay hidden behind `kMoneyDepthLive` until D.

#### Wave C1 (parallel)

**C-db-settings. Hostel settings, tenancy terms, bed board** (also the schema-sync owner for Phase C)
- Layers: database.
- Owns: `db/migrations/{D}-property-settings.sql`, `.down.sql`, `.test.sql`; `db/schema.sql`; `db/rls-policies.sql`.
- Live DB change: **yes**. Legal bump: covered by C-legal.

Changes:
1. **`public.hostel_settings`**: one row per hostel; hostel_id pk references hostels on delete cascade. An AFTER INSERT trigger on hostels creates the row, and existing hostels are backfilled. Columns:
   - `rent_grace_days smallint not null default 0 check 0–28`. One grace setting drives both the "overdue" status and the start of late fines.
   - `late_fine_enabled boolean not null default false`
   - `late_fine_kind text not null default 'fixed' check (fixed|percent)`
   - `late_fine_value numeric(10,2) not null default 0 check (>= 0 and (late_fine_kind <> 'percent' or late_fine_value <= 100))`
   - `late_fine_cap numeric(10,2) null check (> 0)`. The most that late fines may add up to for one resident in one month.
   - `late_fine_repeat text not null default 'once' check (once|daily|weekly)`
   - `deposit_default_kind text not null default 'none' check (none|fixed|months)`
   - `deposit_default_value numeric(10,2) not null default 0 check 0–1e7`
   - `joining_fee numeric(10,2) not null default 0 check 0–1e7`
   - `lock_in_months smallint not null default 0 check 0–24`
   - `notice_days smallint not null default 30 check 0–180`
   - `proration_on_join boolean not null default false`
   - `proration_on_leave boolean not null default false`
   - `receipt_terms text null check (length <= 1000)`
   - `contact_phone text null check ('^[6-9][0-9]{9}$')`
   - `contact_email text null check (length <= 254)`
   - `updated_by uuid`, `updated_at`
   - RLS select: `hostel_id in (select app.owned_hostel_ids())`, or `hostel_id = (select app.user_hostel_id())` for manager and warden, or `(select app.is_super_admin())`. No resident select. Revoke all from anon and authenticated, then grant select.
   - `rent_due_day` stays on `hostels`.
2. **`public.students` tenancy columns**
   - `lock_in_months smallint null check 0–24` and `notice_days smallint null check 0–180`. Null means the hostel default applies.
   - `notice_status text not null default 'none' check (none|given|accepted|withdrawn|completed)`
   - `notice_given_on date`, `planned_move_out date`, `notice_note text check (length <= 500)`, `notice_decided_by uuid`, `notice_decided_at timestamptz`
   - New trigger `students_tenancy_guard`, BEFORE UPDATE. It refuses changes to these columns unless `current_setting('app.tenancy_write', true) = 'on'` (set only by the RPCs below) or the status is moving to vacated, which sets `notice_status = 'completed'`. The message is 42501 "Use the notice actions to change notice details."
   - `StudentRepository.update` keeps working for every other column.
   - Partial index `(hostel_id) where notice_status in ('given','accepted')`.
3. **`public.rooms`**
   - `rent_default numeric(10,2) null check 0–1e7`
   - `available boolean not null default true`
   - `tags text[] not null default '{}' check (tags <@ array['ac','attached_bath','balcony','premium','large','ground_floor'])`
   - Written through the existing rooms update policy (owner and warden, writable). Verify that policy on live.
4. **Retention**: redefine `app.apply_retention` (md5-guarded) to delete snapshots older than 3 years. The snapshot table comes from C-db-home. Because the two migrations apply in order, this redefinition goes into the **later** file, C-db-home's, and this workstream copies it into `schema.sql`.

RPCs:
- **`ow_update_hostel_settings(p_hostel uuid, p_patch jsonb)`**
  - auth: `coalesce(app.owns_hostel(p_hostel) or app.is_super_admin(), false)`; writable.
  - Allow-listed keys only. An unknown key gets P0001 "Unknown setting: <key>"; each key has its own validation sentence.
  - Keys `rent_due_day`, `property_type` and `gender_policy` update `hostels`, reusing the `ow_set_rent_due_day` checks.
  - spend('hostel_settings', 60, 600). Audit 'owner.settings.update' with meta `{keys:[...]}`. Returns the full row.
- **`ow_copy_hostel_settings(p_from uuid, p_to uuid[], p_keys text[] default null)`**: owns all of them; at most 20 targets; writable for each target; audit.
- **`st_hostel_terms()`**
  - auth: `app.current_student_id()` is not null.
  - Returns the due day; grace; the effective lock-in and notice (student override or default); joining date; lock-in end; the earliest move-out if notice were given today; rules; contact; and a late-fine summary only when enabled.
- **`st_give_notice(p_move_out date, p_note text)`**
  - auth: a non-vacated resident whose `notice_status` is none or withdrawn.
  - `p_move_out` must be between `app.today()+1` and `app.today()+365`.
  - Computes earliest = greatest(today + notice_days, date_of_joining + lock_in months).
  - Sets status given, `notice_given_on = app.today()`, `planned_move_out = p_move_out`.
  - spend('notice', 5, 86400). Notify wardens with access (through `staff_hostel_access`) and the owner. Audit 'resident.notice.give'.
  - Returns `{earliest, short_notice}`. Short notice is not refused; it is flagged.
- **`st_withdraw_notice()`**: only from given.
- **`wd_decide_notice(p_student, p_accept boolean, p_move_out date default null, p_note text)`**
  - auth: `app.has_role_in(h,'warden','owner')`; writable; only from given.
  - Accept may adjust the date (`app.today()+1` or later). Decline needs a note of 3 characters or more and sets withdrawn.
  - Notify the resident. Audit.
- **`wd_record_notice(p_student, p_given_on date, p_move_out date, p_note)`**: staff record notice on a resident's behalf. `p_given_on` must be within the last 60 days and not after today. Goes straight to accepted. Audit.
- **`wd_cancel_notice(p_student, p_note)`**: accepted to withdrawn. Audit.
- **`wd_set_tenancy_terms(p_student, p_lock_in smallint, p_notice_days smallint)`**: auth warden or owner; writable. Audit.
- **`rpc_bed_board(p_hostel)`**
  - SECURITY INVOKER, so RLS shapes it.
  - One row per bed: floor, floor_name, room id, room number, room available, tags, rent_default, bed id, bed number, and status (free|occupied|under_notice|unavailable). Also resident first name and student id, which only owners and wardens can see because of RLS.
  - Columns are appended last in later phases (F adds `booked`).

`.test.sql` sections:
- the settings allow-list and every validation sentence;
- writes refused for a non-owner, a manager, a warden, the owner of another hostel, and on read-only or suspended hostels;
- copy settings across owned and unowned PGs;
- the notice flow across every role, including the guard refusing a direct UPDATE of `notice_status` by a warden;
- earliest-date arithmetic on lock-in boundaries, month ends and leap days;
- the bed board seen as owner, warden, manager (no names) and resident.

**C-db-home. Pending inbox, search, notification preferences, snapshots, push-send**
- Layers: database, Edge Function.
- Owns: `db/migrations/{D}-home-inbox-search.sql`, `.down.sql`, `.test.sql`; `supabase/functions/push-send/**`.
- Live DB change: **yes**. Legal bump: covered by C-legal.

Changes:
1. **`public.notification_prefs`**
   - Columns: user_id pk references public.users on delete cascade; `muted_types text[] not null default '{}'`, checked to contain only `notification_type` labels other than 'system'; updated_at.
   - RLS: select own.
   - `my_set_notification_prefs(p_muted text[])` is a definer function keyed on `auth.uid()`. 'system' (account and security notices) cannot be muted.
2. **`push-send`**: when claiming rows, skip the FCM send for types the recipient muted. Still set `pushed_at` so muted rows are never retried. The in-app row stays. Header doc updated. Deploy.
3. **`rpc_pending_inbox(p_hostel uuid)`**
   - SECURITY INVOKER. Returns `table(kind text, item_count int, sample jsonb)`. Version 1 kinds:
     - `unpaid_rent`: residents unpaid or partial this IST month, with the same semantics as `rpc_fee_ledger`;
     - `open_complaints`, `pending_leaves`;
     - `notices_to_accept` (`notice_status = 'given'`);
     - `link_requests_waiting` (pending verified-email links);
     - `tasks_overdue`;
     - `visitors_on_site`.
   - RLS returns zero rows to roles that cannot see a kind, so a manager sees no resident kinds.
   - Later phases append kinds with CREATE OR REPLACE and the same signature. Clients ignore kinds they do not know.
   - Budget: under 150ms at 10,000 residents (`explain analyze` on a mirror).
4. **`rpc_global_search(p_hostel uuid, p_q text, p_limit int default 20)`**
   - SECURITY INVOKER. `p_q` is trimmed and must be 2–60 characters; `%`, `_` and `\` are escaped; the limit is at most 50.
   - Searches students (name, phone, room number), rooms (room number) and complaints (title). Prefix matches rank first.
   - Returns `(kind, id, title, subtitle)`.
   - If `pg_trgm` is available on live (check `pg_extension`; ask before creating it), add `gin (lower(full_name) gin_trgm_ops)` on students. Otherwise use plain ilike under the hostel filter.
5. **`public.daily_hostel_snapshots`**
   - Columns: hostel_id, on_date date, beds, occupied, residents, under_notice int; rent_due, rent_collected, expenses, revenue numeric(12,2); open_complaints int. Primary key (hostel_id, on_date).
   - RLS: owner (`owned_hostel_ids`) and super admin only. Managers must not read rent figures.
   - Written by `app.snapshot_hostels()` (definer, revoked from everyone), which reuses `rpc_hostel_stats`'s IST-bounded queries.
   - Cron `apnivaas-hostel-snapshots` at `'25 18 * * *'` UTC (23:55 IST), idempotent through `on conflict (hostel_id, on_date) do update`.
6. **`app.apply_retention`** redefinition: snapshots older than 3 years are deleted (see the C-db-settings note).

`.test.sql`:
- the inbox kinds seen per role, with a manager getting no resident kinds;
- search escaping, and RLS isolation across hostels;
- 'system' cannot be muted;
- snapshot idempotency, and the IST boundary at 18:29 versus 18:31 UTC.

#### Wave C2 (parallel)

**C-settings-app. Settings hub and tenancy UI**
- Layers: Flutter features, tests.
- Owns: `apnivaas_app/lib/features/property_settings/**` (new), `apnivaas_app/lib/features/tenancy/**` (new), `apnivaas_app/test/property_settings_test.dart` (new), `tenancy_test.dart` (new).
- Live DB change: no. Legal bump: no.

Spec:
- **PropertySettingsHub**, exported: question cards, each showing the current answer and opening an edit sheet. The questions:
  - "Which day of the month is rent due?"
  - "How many days of grace before rent counts as late?"
  - "What kind of place is this?"
  - "Who stays here?"
  - "Is there a lock-in period?"
  - "How much notice must a resident give?"
  - "House rules" (`ow_update_hostel_rules`)
  - "Words printed on every receipt"
  - "How can residents reach the PG?"
  - "Copy these answers to my other PGs"
- **Hidden behind `kMoneyDepthLive`** until D: "Do you charge a late fine?" (fixed or percent, repeat, cap; it starts after the grace days above); "Do you take a security deposit?"; "Is there a joining fee?"; "Charge only for the days stayed in the first and last month?"
- Money questions carry an inline FAQ (static copy).
- Wardens see a read-only version.
- **TenancyActions**, exported:
  - resident: give notice (date picker showing the earliest date, with a short-notice warning) and withdraw;
  - warden: record, accept, decline and cancel notice, and edit terms.
- **TenancyTermsCard**, exported, for the resident Profile.
- Every write disables while pending and shows the server sentence on refusal.

**C-home-app. Home blocks, inbox, search, coach marks, push-tap routing**
- Layers: Flutter features, core notify and prefs, shared UI, tests.
- Owns: `apnivaas_app/lib/features/home_blocks/**` (new), `apnivaas_app/lib/features/search/**` (new), `apnivaas_app/lib/features/inbox/**` (new), `apnivaas_app/lib/core/notify/**`, `apnivaas_app/lib/core/prefs/**` (new), `apnivaas_app/lib/shared/ui/coach_mark.dart` (new), `apnivaas_app/lib/shared/ui/share_text.dart` (new), tests `home_blocks_test.dart`, `search_test.dart`, `inbox_test.dart`, `notification_links_test.dart`, `coach_mark_test.dart` (all new).
- Live DB change: no. Legal bump: no.

Spec:
- **`HomeBlock` contract.** Each block has its own autoDispose provider, skeleton, empty state, and error state with retry, and joins pull-to-refresh through `settleRefresh`. One slow block never blanks the screen.
  - The blocks: StatCarouselBlock, PendingInboxBlock, QuickActionsBlock, NoticesBlock, OccupancyBlock, CashflowBlock, TodayTasksBlock, MenuTodayBlock, RentCardBlock.
  - **Quick actions** have per-role defaults; pins are stored in a local JSON file in the app support directory and read inside try/catch, falling back to the defaults. Owner defaults follow decision D1.
  - **Metric explanations**: an info icon on every KPI opens an InfoSheet saying what the number counts and how it is calculated.
- **Coach marks.** A spotlight overlay with steps and Skip, stored as `coach_<role>_v1`. Never shown under reduce motion; the steps become a static list instead.
- **SearchScreen.** 300ms debounce, minimum 2 characters, results grouped by kind. Taps go through a `SearchResultRouter` interface that C-integration implements, so this feature imports no other feature.
- **InboxScreen.** The caller's paged notifications; marked read on open; mark all read; delete own.
  - The bell badge is `rpc_unread_count`, refreshed on resume and when a push arrives.
  - NotificationPrefsScreen has a toggle per type; 'system' is locked on.
- **Push-tap routing.** `notification_links.dart` parses each server `link` into a `PendingDestination(role, tab, detail, id)`. Known links: `/student?receipt=<id>`, `/owner`, `/warden?tab=<t>`, `/manager?tab=<t>`, `/super-admin?tab=applications`, plus the patterns later phases register.
  - `PushService._onTapped` and `getInitialMessage` write `pendingDestinationProvider`.
  - The destination is consumed only by RoleShell (C-integration), only when the phase is `AuthSignedIn`, consent is accepted and the role matches. Otherwise it is held (consent pending) or discarded (signed out, wrong role).
  - It never calls `router.go` with a path outside `appScreens`. Unknown links are ignored.
- **`share_text.dart`**: a WhatsApp-ready formatter (`*bold*` headings, bullet lines, a closing line), shared by C, D, F and H.

**C-rooms-app. Bed board and rooms**
- Layers: Flutter, tests.
- Owns: `apnivaas_app/lib/features/rooms_board/**` (new), `apnivaas_app/lib/shared/rooms/**`, `apnivaas_app/test/rooms_board_test.dart` (new).
- Live DB change: no. Legal bump: no.

Spec:
- **BedBoard**, exported, fed by `rpc_bed_board`:
  - floor segments, a room grid, bed pips coloured by status, each with a word in semantics;
  - a legend with counts;
  - callbacks `onVacantBed` and `onResident` for the integrator.
- **Room edit sheet** adds tags, default rent and the available toggle.
- **Share vacant bed**: room, sharing, default rent, tags, PG name and locality. Never the street address. Uses `share_text` and `share_plus`.

**C-legal. Legal version "tenancy"** (merge with D's if they ship together)
- Owns the standard legal files (section 1.2). Live DB change: **yes** (the row). Legal bump: **yes**.
- Spec: covers notice dates and tenancy terms, notification preferences, and receipt terms. Snapshots are aggregates and need only a sentence.

#### Wave C3

**C-integration. Compose homes, wire shells, chips, bed board**
- Layers: Flutter screens and shells, tests.
- Owns:
  - `apnivaas_app/lib/features/owner/owner_dashboard_screen.dart`, `owner_tabs.dart`, `owner_students_screen.dart`, `owner_pg_detail_screen.dart`
  - `apnivaas_app/lib/features/warden/home/warden_home_screen.dart`, `warden/students/warden_students_screen.dart`, `warden/students/student_sheet.dart`, `warden/rooms/warden_rooms_screen.dart`, `warden/warden_shell.dart`
  - `apnivaas_app/lib/features/manager/home/manager_home_screen.dart`, `manager/manager_shell.dart`
  - `apnivaas_app/lib/features/student/home_screen.dart`, `student/profile_screen.dart`, `student/student_section.dart`
  - `apnivaas_app/lib/features/super_admin/sa_shell.dart`
  - `apnivaas_app/lib/features/shell/role_shell.dart`
  - Tests: `owner_shell_warmup_test.dart`, `warden_shell_warmup_test.dart`, `manager_warmup_test.dart`, `super_admin_warmup_test.dart`, `student_warm_tabs_test.dart`
- Live DB change: no. Legal bump: no.

Spec:
- Compose each role home from HomeBlocks.
- Header bell and search open the inbox and search.
- RoleShell consumes `pendingDestinationProvider` after the gates.
- People lists get situation chips: pending dues (from `rpc_fee_ledger`), on leave, under notice. Chips are toggles with a result count.
- Room screens use BedBoard. For a warden, a vacant bed opens the register sheet with the bed pre-filled.
- The Property tab gets the settings hub.
- TenancyActions go into the resident Requests, Profile and the warden student sheet.
- Implement `SearchResultRouter`.
- Warm-up suites updated: tabs still land on drawn numbers.

**Phase C deploy order.** C-db-settings, then C-db-home (migrations in filename order), then push-send, then the legal row, then the website, then the app.

**Phase C exit criteria.**
- SQL tests pass; the inbox query budget is met.
- Push-tap tests cover signed out, consent pending, wrong role and unknown link.
- No new copy-based finders.
- Ten permissions.

---

### Phase D: money depth

**Goal.** Every charge a PG makes has a category, a due date and a receipt:
- electricity from meter readings;
- bulk charges;
- automatic late fines;
- deposits held, adjusted and refunded;
- a joining fee.

Every collection is an event with a receipt and a recorder. Residents see one passbook. Owners see collections, dues and staff cash. Residents can pay the owner's UPI ID and report the UTR for the owner to confirm. The Razorpay F2 bug is fixed. Optional proration ships off by default.

**Estimate.** 10 to 14 working days build, about 3 weeks calendar. **Release:** 1.4.0, with C.

**The model.**
- The rent ledger (`fee_payments`, one row per resident per month, never deleted) stays exactly as it is.
- Non-rent money lives in a new `charges` table, collected through append-only `charge_payments`.
- Rent collections become events through a trigger-written `fee_payment_events` table, so collections and receipts work per payment instead of per month row.
- Deposits are a charge of category `deposit`. What leaves the deposit (refund, adjustment, forfeit) goes to `deposit_ledger`.
- Corrections are always new reversal rows, never updates or deletes.
- Managers have no read path to any of this.

#### Wave D1

**D-ledger-db. Charges, payment events, deposits, late fines, shared Dart money models** (schema-sync owner for Phase D)
- Layers: database, cron, Dart shared models.
- Owns: `db/migrations/{D}-payment-mode-values.sql`, `db/migrations/{D}-charges-ledger.sql`, `.down.sql`, `.test.sql`; `db/schema.sql`; `db/rls-policies.sql`; `apnivaas_app/lib/data/models/money.dart` (new); `apnivaas_app/lib/data/models/ledger.dart` (new); `apnivaas_app/test/money_model_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by D-legal.

Changes:
1. **`{D}-payment-mode-values.sql`**: non-transactional and idempotent. `alter type public.payment_mode add value if not exists 'cheque'`, then `'deposit'`.
   - Old clients tolerate this: Flutter's `PaymentMode.tryParse` returns null for an unknown value. Add a test that shows "—" for a null mode.
   - The website is handled by D-web-compat.
2. **`public.fee_payment_events`**
   - Columns: id, hostel_id, fee_payment_id (references fee_payments), student_id, period_month, `delta numeric(10,2) not null check (delta <> 0)`, amount_paid_after, mode, paid_on, `kind text check (record|correction|online|deposit_adjustment|backfill)`, recorded_by, notes, created_at.
   - Written only by the trigger `fee_payments_event_log`, AFTER INSERT OR UPDATE OF amount_paid, whenever amount_paid changes.
   - kind comes from `current_setting('app.fee_event_kind', true)`, default 'record'; it is 'online' when `auth.uid()` is null (the service-role credit path).
   - `wd_correct_payment` is redefined with `execute replace(pg_get_functiondef(...))` to set `app.fee_event_kind = 'correction'`, with md5 proofs before and after.
   - Backfill one 'backfill' event per existing row where amount_paid > 0.
   - RLS mirrors `fee_payments` reads: warden and owner of the hostel; the resident reads their own. No client writes.
3. **`public.charges`**
   - Columns:
     - id, hostel_id, student_id
     - `category text check (deposit|electricity|water|gas|food|maintenance|joining_fee|late_fine|guest|booking_token|damage|move_out|renewal|other)`
     - description 1–200, `period_month` null with the period CHECK
     - `amount numeric(10,2) check (> 0 and <= 10000000)`, `amount_paid numeric(10,2) default 0 check (>= 0 and <= amount)`
     - `status text check (unpaid|partial|paid|void)`, maintained by trigger
     - due_date
     - `source text check (manual|bulk|meter|late_fine|registration|move_out|guest|booking)`, source_ref uuid
     - dedupe_key text unique, request_id uuid unique
     - `complaint_id uuid null references complaints on delete set null`
     - voided_at, voided_by, void_reason 3–300
     - created_by, created_at, updated_at
   - Indexes: (hostel_id, status, due_date) and (student_id, created_at desc).
   - Trigger `app.assert_student_in_hostel`.
   - RLS select: owner (`owned_hostel_ids`), warden (`user_hostel_id` and role warden), resident own (`current_student_id`). No manager. Revoke all, then grant select.
4. **`public.charge_payments`**
   - Columns: id, hostel_id, charge_id, student_id, `amount numeric(10,2) check (amount <> 0 and abs(amount) <= 10000000)`, `mode text check (cash|upi|bank|cheque|deposit)`, paid_on, reference ≤ 60, notes ≤ 500, recorded_by, created_at, `reverses_id uuid unique references charge_payments`, `request_id uuid unique`.
   - An AFTER INSERT trigger recomputes the charge's amount_paid and status.
   - Rate-limit trigger `app.rl_charge_payment`, 150 per hour per user.
   - Never updated or deleted. RLS as for charges.
5. **`public.deposit_ledger`**
   - Columns: id, hostel_id, student_id, `kind text check (refund|adjust|forfeit|reversal)`, `amount numeric(10,2) check (> 0 and <= 10000000)`, mode payment_mode null, target_charge_id, target_period_month, notes ≤ 500, recorded_by, created_at, request_id unique, reverses_id unique.
   - Held deposit = deposit-charge payments, minus refund, adjust and forfeit, plus reversals.
   - RLS as for charges.
6. **`public.bulk_operations`**: id (= the request id), hostel_id, kind, created_by, created_at, result jsonb. RLS: the creator and the owner select. No client writes.
7. **`public.students.late_fine_paused boolean not null default false`**, added to `students_tenancy_guard`'s RPC-only column list.
8. **`app.rent_due_for(p_student, p_month)`** returns numeric: the month's rent due. In D1 that is the recorded `amount_due`, or else `monthly_fee`. D-money-path redefines it to add proration. Every new money function calls this one helper.

RPCs:
- **`wd_add_charge(p_student, p_category, p_amount, p_description, p_due_date, p_period_month default null, p_request_id)`**
  - auth: `app.has_role_in(<student hostel>,'warden','owner')`; writable.
  - The resident must be non-vacated, or vacated within 30 days for `move_out`, `damage` and `deposit`.
  - Categories other than `booking_token` are allowed. Amount bounds and NaN are checked; description trimmed to 1–200; due_date within ±366 days of `app.today()`.
  - spend('charge_write', 300, 3600). A replay of the same request id returns the first row.
  - Notify the resident: type 'fee', "New charge", "<description>: ₹<amount>", link '/student?tab=rent'.
  - Audit 'warden.charge.add'.
- **`wd_add_charges_bulk(p_hostel, p_target jsonb, p_category, p_amount, p_description, p_due_date, p_request_id)`**
  - auth as above; writable.
  - target: `{kind:'all'}`, or `{kind:'rooms', ids:[...]}` or `{kind:'students', ids:[...]}`, with the ids verified to belong to the hostel. At most 500 non-vacated residents once resolved.
  - `pg_advisory_xact_lock` on the request id. A replay returns `bulk_operations.result`.
  - One charge per resident (source 'bulk'), batched notifications, one audit row 'warden.charge.bulk_add' with the count. spend('charge_bulk', 20, 3600).
- **`wd_void_charge(p_charge, p_reason)`**: only when amount_paid = 0; reason 3–300. Audit.
- **`wd_record_charge_payment(p_charge, p_amount, p_mode, p_paid_on, p_reference, p_notes, p_request_id)`**
  - auth warden or owner; writable; the charge is not void; the resident is not erased.
  - `0 < amount <= outstanding`, otherwise "This is more than the ₹x still due on this charge."
  - mode is one of cash, upi, bank, cheque. paid_on is within [today−366, today+1]. Idempotent.
  - Notify the resident and the owner. Audit.
- **`wd_reverse_charge_payment(p_payment, p_reason)`**: inserts the negative row once (`reverses_id` is unique). Audit.
- **`wd_refund_deposit(p_student, p_amount, p_mode, p_paid_on, p_notes, p_request_id)`**
  - auth warden or owner. **Not** writable-gated: settling a refund removes an obligation, like `wd_cancel_student_erasure`.
  - `amount <= held`, otherwise "Only ₹x of deposit is held."
  - Notify the resident. Audit.
- **`wd_adjust_deposit(p_student, p_target_kind ('charge'|'rent'), p_target text, p_amount, p_request_id)`**
  - The amount must not exceed either the held deposit or the target's outstanding.
  - Against a charge: a `charge_payments` row with mode 'deposit', plus a `deposit_ledger` 'adjust' row.
  - Against rent: `public.wd_record_payment(student, month, amount, 'deposit', app.today(), 'Adjusted from deposit')` with `app.fee_event_kind = 'deposit_adjustment'`, plus a ledger row.
  - One transaction. Audit.
- **`wd_forfeit_deposit(p_student, p_amount, p_reason, p_request_id)`** and **`wd_reverse_deposit_entry(p_entry, p_reason)`**. Audit both.
- **`wd_set_late_fine_paused(p_student, p_paused)`**. Audit.
- **`rpc_student_ledger(p_student, p_months int default 12)`** (at most 24)
  - SECURITY INVOKER.
  - Returns a timeline: `(at date, kind, ref_id, title, debit, credit, status, meta jsonb)`. It covers rent months (recorded rows plus virtual months, with the same semantics as `rpc_fee_ledger`), rent events, charges, charge payments, deposit entries and Razorpay refunds.
- **`rpc_student_balance(p_student)`**: rent outstanding, charges outstanding by category, deposit held, total.
- **`rpc_dues(p_hostel, p_as_of date default app.today(), p_category text default null)`**
  - SECURITY INVOKER, paged with `.range()`.
  - One row per open due: rent months outstanding (current month, plus earlier months with unpaid or partial rows, plus virtual months since joining, bounded to 24 months) and open charges.
  - Columns: student, room, category, label, amount, paid, outstanding, due_date (rent: the due day of that month), days_late (after `rent_grace_days`).
- **`rpc_collections(p_hostel, p_from, p_to)`**
  - SECURITY DEFINER with `app.has_role_in(p_hostel,'warden','owner')`, otherwise 42501. The range is at most 366 days.
  - Unions rent events (delta) and charge payments, reversals included as negative rows. Includes the recorder's name and role.
- **`rpc_receipt(p_kind ('rent_event'|'charge_payment'|'deposit_refund'), p_id)`**
  - SECURITY INVOKER: RLS decides who may see it.
  - Returns the header (PG name, address, contact), payer, room, items, amount, mode, reference, paid_on, recorder, `receipt_terms`, and `receipt_no = 'APV-' || upper(left(replace(id::text,'-',''),10))`.
  - Refuses with "There is no receipt for this entry." when the amount is 0 or less.
- **`wd_send_rent_reminder(p_hostel, p_students uuid[], p_request_id)`**
  - At most 200 residents. auth warden or owner; writable.
  - Only residents with a balance above 0 and an active login.
  - Notifications use `dedupe_key 'manual-remind:<student>:<IST date>'`, so at most one per resident per day.
  - spend('remind', 20, 3600). Audit. Returns `{sent, skipped}`.
- **`app.apply_late_fines()`** (service only)
  - Cron `apnivaas-late-fines` at `'50 3 * * *'` UTC (09:20 IST).
  - For each writable hostel with late fines enabled, current IST month only: start = make_date(month, rent_due_day) + rent_grace_days.
  - For each active or on_leave, non-vacated, unpaused resident who joined before the start and has `app.rent_due_for − paid > 0`:
    - seq = 1 for once, the day number since start for daily, the week number for weekly. At most 7 catch-up seqs.
    - amount = the fixed value, or round(outstanding × pct / 100, 2), minimum ₹1, clipped so the month's late fines do not exceed `late_fine_cap`.
    - Insert with `dedupe_key 'late_fine:<student>:<month>:<seq>'` and `on conflict do nothing`.
    - Notify the resident.
  - One audit row per hostel, 'system.late_fine.applied'.
  - An unpaid late fine can be voided by a warden or owner.
- **`rpc_pending_inbox`** gains `deposits_to_settle` (vacated residents still holding deposit) and `charges_overdue`.
- **`app.erase_student`** redefinition (md5-guarded): null out the free-text `notes` on that student's `charge_payments`, `deposit_ledger` and `fee_payment_events`. The ledger rows themselves stay, keyed to the tombstone; they are never deleted, exactly like `fee_payments`.

Dart (`lib/data/models`):
- **`Money`**: integer paise. It parses a numeric string exactly and a JSON number within the ±1e8 bounds with `(n*100).round()`. Arithmetic is integer-only. Formatting is `en_IN` with ₹.
- **`ledger.dart`**: Charge, ChargeCategory (`tryParse` falls back to other), ChargePayment, LedgerEntry, DuesRow, CollectionRow, ReceiptData, DepositSummary.

`.test.sql`:
- the authorisation matrix: owner, warden, the other hostel's owner, manager (zero rows on every table), resident (own only), anon;
- every validation sentence; idempotent replays; bulk at the 500 limit; reversal only once;
- deposit held arithmetic across collect, adjust, refund and reverse;
- `deposit` mode reaching `fee_payments`, with events written with the right kind;
- the event backfill;
- late fines: once, daily, weekly, cap, paused, an unwritable hostel, the IST boundary, and a second run in the same day adding nothing.

#### Wave D2 (parallel)

**D-meters. Electricity, water and gas meters** (database and app)
- Layers: database, Flutter feature, tests.
- Owns: `db/migrations/{D}-meters.sql`, `.down.sql`, `.test.sql`; `apnivaas_app/lib/features/money/meters/**` (new); `apnivaas_app/test/meters_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by D-legal.

Spec:
- **`public.meters`**
  - Columns: id, hostel_id, room_id null, student_id null (exactly one of the two, by CHECK), `kind text check (electricity|water|gas)`, label ≤ 40, `unit_rate numeric(10,4) check (> 0 and <= 1000)`, `opening_reading numeric(12,2) check (>= 0)`, opening_date, active, created_by, created_at.
- **`public.meter_readings`**
  - Columns: id, meter_id, hostel_id, `reading numeric(12,2)`, read_on, units, amount, `split jsonb` (student_id to amount), charges_created int, recorded_by, created_at, request_id unique, voided_at/by/reason.
- RLS select: owner and warden. Residents read through `st_my_meter_readings()`, limited to meters on their own room or themselves.
- **`wd_upsert_meter(...)`**: warden or owner; writable. Audit.
- **`rpc_meter_reading_preview(p_meter, p_reading, p_read_on)`**: SECURITY INVOKER; returns units, amount and split without writing.
- **`wd_record_meter_reading(p_meter, p_reading, p_read_on, p_request_id)`**
  - auth warden or owner; writable.
  - The reading must be at least the previous one, otherwise "This reading is lower than the last one (<value> on <date>)."
  - read_on must be after the previous reading's date and no later than `app.today()`. Units at most 100,000.
  - amount = round(units × rate, 2), split equally in paise among the residents occupying beds in the room on read_on (active or on_leave). The remainder paise go one each in bed-number order, so the parts add up exactly.
  - One `electricity`/`water`/`gas` charge per occupant: source 'meter', source_ref = the reading, description "Electricity <prev date> to <date>, <units> units".
  - With no occupants: store the reading, create no charges, and say so.
  - Notify the residents. Audit.
- **`wd_void_meter_reading(p_reading, p_reason)`**: only when every generated charge is still unpaid. It voids them atomically.
- **App**:
  - meter list per room, with the last reading and days since;
  - an "Enter reading" sheet with a numeric keypad, the preview, and confirm;
  - history; set-up questions ("Is there a meter for this room?", "Price per unit?").
  - Residents see their meter history on the Rent tab, exported as `ResidentMeterCard`.
- **Tests**: SQL for rounding (₹100.00 split three ways is 33.34 + 33.33 + 33.33), a lower reading, voiding a paid reading, and RLS. Dart widget tests with keys.

**D-expenses-cash. Expenses edit, void and receipts; staff cash passbook**
- Layers: database, Edge Function, Flutter.
- Owns: `db/migrations/{D}-expenses-and-cash.sql`, `.down.sql`, `.test.sql`; `supabase/functions/expense-receipt/**` (new); `apnivaas_app/lib/features/manager/expenses/**`; `apnivaas_app/lib/features/money/passbook/**` (new); `apnivaas_app/lib/shared/finance/**`; `apnivaas_app/test/manager_test.dart`; `apnivaas_app/test/passbook_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by D-legal.

Spec:
- **`expenses`**: add vendor ≤ 120, `paid_by text check (owner|manager|petty_cash) default 'manager'`, `mode text check (cash|upi|bank|cheque) null`, voided_by, void_reason. Voiding sets the existing `deleted_at`.
  - **First verify on live** that `rpc_expense_months`, `rpc_expense_days`, `rpc_daily_finance` and `rpc_hostel_stats` all filter `deleted_at is null`. Any that does not is redefined, md5-guarded.
  - `revenues` gets the same void columns.
- **`mg_update_expense(p_id, p_patch jsonb)`**
  - auth: the manager who uploaded it within 30 days, or the hostel's owner; writable.
  - Patch allow-list: date, category, kind, amount, note, vendor, paid_by, mode, receipt_url.
  - receipt_url must match `^<hostel>/receipts/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$`.
  - Audit with before and after values.
- **`mg_void_expense(p_id, p_reason)`** and **`mg_void_revenue(p_id, p_reason)`**: same auth. Audit.
- **`public.cash_handovers`**
  - Columns: id, hostel_id, from_user, to_user (the owner), `amount numeric(12,2) check (> 0 and <= 100000000)`, handed_on, notes ≤ 500, `status text check (pending|confirmed|disputed|cancelled)`, decided_by, decided_at, request_id unique.
- **`public.petty_cash_advances`**
  - Columns: id, hostel_id, to_user, amount, given_on, notes, created_by (the owner), request_id unique.
- RLS: the owner sees all rows in owned hostels; staff see their own.
- **`staff_record_handover(p_hostel, p_amount, p_handed_on, p_notes, p_request_id)`**
  - Caller is a manager or warden with access to the hostel. spend('handover', 20, 86400).
  - Notify the owner.
- **`ow_decide_handover(p_id, p_confirm boolean, p_note)`**: owner only. Notify the staff member. Audit.
- **`ow_give_petty_cash(...)`**: owner only. Audit.
- **`rpc_staff_cash_position(p_hostel)`**
  - SECURITY DEFINER. The owner sees every staff member; staff see themselves.
  - Per staff member: cash collected (rent events plus charge payments with mode cash and `recorded_by` = them), minus confirmed handovers, plus petty cash received, minus expenses paid from petty cash.
  - **Totals only, never resident names**, so it is safe for managers.
- **Edge Function `expense-receipt`**, actions upload, sign and discard:
  - `requireCaller('manager','owner')`; tenant from `requireOwnHostel` (manager) or `requireOwnedHostel` (owner); `assertWritable`.
  - Upload: at most 3 MB; JPEG, PNG, WebP or PDF, sniffed by content; path `<hostel>/receipts/<uuid>.<ext>` in the private `receipts` bucket; 40 per hour.
  - Sign: a 15-minute signed URL, only if the caller can SELECT the expense under their own JWT.
  - Discard: the uploader, within 1 hour, only if nothing references the file.
  - Deploy with `verify_jwt` on.
- **App**:
  - manager expenses: edit, void with a reason, receipt photo (camera or gallery through `image_picker` and the existing capture flow), vendor, paid-by.
  - Passbook screen: my cash position; record a handover; the owner's confirm queue; petty cash.
  - Expense stats exclude voided rows.

**D-upi. UPI to the owner with UTR confirmation**, following the design recorded in the project notes on 2026-10-01
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-upi-claims.sql`, `.down.sql`, `.test.sql`; `apnivaas_app/lib/features/money/upi/**` (new); `apnivaas_app/test/upi_test.dart` (new).
- Live DB change: **yes**. Legal bump: **yes**, through D-legal. The current policy says Apnivaas never stores a UPI ID.

Spec:
- **`public.hostel_upi_accounts`**: hostel_id pk, `vpa text check ('^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$')`, payee_name ≤ 100, owner_user_id (a snapshot of who set it), set_at, active.
  - It is a separate table because `hostels_select` exposes every hostels column to residents and managers.
  - RLS: owner only.
- **`public.upi_claims`**
  - Columns: id, hostel_id, student_id, period_month (the IST current month, derived on the server), amount, `utr text check ('^[0-9]{12}$')`, `status text check (pending|confirmed|rejected|cancelled|expired)`, decided_by, decided_at, `decision_source text check (staff|auto)`, reject_reason, fee_payment_event_id, created_at.
  - Unique partial index on (utr) where status in (pending, confirmed), across all PGs.
  - User foreign keys are ON DELETE SET NULL.
  - RLS: owner of the hostel; the resident reads their own.
- **`ow_set_upi_account(p_hostel, p_vpa, p_payee_name)`**: `app.owns_hostel` (which includes MFA); writable. Audit.
- **`st_upi_pay_details()`**: the resident's VPA, payee, current-month outstanding and period. It returns nothing if the owner snapshot no longer matches `hostels.owner_user_id`.
- **`st_submit_upi_claim(p_amount, p_utr)`**
  - spend('upi_claim', 5, 3600). The amount must be above 0 and no more than the current month's outstanding.
  - The same resident sending the same UTR again is idempotent. A duplicate UTR from anyone else gets the generic "This reference can't be used. Check the UTR and try again."
  - Notify the owner.
- **`ow_decide_upi_claim(p_claim, p_confirm, p_amount default null, p_reason default null)`**
  - Owner only. G adds wardens who hold `confirm_upi`.
  - **One definer transaction**: claim pending to confirmed under a claim predicate, then `wd_record_payment(mode 'upi', notes 'UPI · UTR <utr>')`, then store the event id, then audit.
  - Reject requires a reason.
  - Notify the resident.
- **`app.apply_retention`** redefinition (md5-guarded): pending claims older than 30 days become expired.
- **App**:
  - owner: UPI details (VPA, payee name, test QR) and the claims queue (confirm, adjust the amount, reject).
  - Property QR poster: a `RepaintBoundary` exported to PNG and shared through `share_plus`.
  - resident: a Pay by UPI sheet. The QR is drawn on the device with the `qr` 4.0.0 package (pure Dart, no permission) and a CustomPainter, from `upi://pay?pa=<vpa>&pn=<payee>&am=<amount>&cu=INR&tn=<PG month>` with `%20` encoding.
  - Then "I've paid": a UTR field with help text on where to find the 12-digit UTR, and the claim status.
  - **No intents, no collect requests, no app launching.**

**D-money-path. Razorpay F2, online-pay gating, optional proration** (the money path, the strictest tests)
- Layers: database, Flutter payments.
- Owns: `db/migrations/{D}-money-path.sql`, `.down.sql`, `.test.sql`; `apnivaas_app/lib/features/payments/pay_rent.dart`; `apnivaas_app/lib/features/payments/payments.dart`; `apnivaas_app/test/pay_rent_test.dart`.
- Live DB change: **yes**. Legal bump: no for F2 and gating; proration is covered by D-legal's terms text.

Spec:
1. **F2.** Redefine `rz_record_capture` from the **live** body, md5-guarded. It may claim an `expired` intent exactly as it claims a `created` one when the amount equals the intent; a capture is still claimed exactly once. After that, schedule `rz_expire_stale_intents('2 hours')` hourly (`'15 * * * *'`, job `apnivaas-expire-intents`) and update `docs/razorpay-money-path.md`.
2. **`st_online_payment_available()`** returns a boolean: the resident's hostel has a Route account or a valid direct approval. Read the live-only column `razorpay_direct_for_owner` from the live definition.
   - The app shows Pay online only when this is true.
   - A 503 from `razorpay-order` hides the button for the session with "Online payment isn't set up for this PG yet. Pay at the desk or by UPI."
3. **Proration**, used only when `hostel_settings.proration_on_join` or `proration_on_leave` is true (both off by default).
   - Redefine `app.rent_due_for`:
     - joining month: round(monthly_fee × (days_in_month − day(date_of_joining) + 1) / days_in_month, 2);
     - leaving month (accepted `planned_move_out` or `vacated_at` in that month): the days up to and including the move-out date;
     - both in one month: the inclusive span.
   - Redefine `rpc_fee_ledger`, the `amount_due` initialisation in `wd_record_payment`, the expected amount in `rz_open_intent`, and `app.send_rent_reminders` to call it. All md5-guarded against live.
   - Months already recorded keep their stored `amount_due`; turning the setting on changes virtual and future months only. Say so in the settings FAQ.
4. **`.test.sql`**:
   - month ends, leap February, joining on the 1st and on the last day, toggling the setting;
   - `rz_open_intent`'s expected amount equals the ledger's due;
   - an F2 late capture is credited exactly once; refund reversal still works;
   - the IST boundary.
5. **App**: PayRentButton gated as above; tests for each state.

**D-money-app. Money tabs, charges, deposits, collections, ledger, receipts, reminders**
- Layers: Flutter features, tests.
- Owns:
  - `apnivaas_app/lib/features/money/{dues,charges,collections,deposits,ledger,reminders,resident}/**` (new)
  - `apnivaas_app/lib/features/payments/receipt.dart`, `receipt_export.dart`, `receipt_paper.dart`, `receipt_printer.dart`, `receipt_screen.dart`, `receipt_tokens.dart`
  - Tests: `receipt_test.dart`, `money_dues_test.dart`, `charges_test.dart`, `bulk_charges_test.dart`, `deposits_test.dart`, `ledger_test.dart`, `reminders_test.dart`, `resident_rent_test.dart` (all new except `receipt_test`)
- Live DB change: no. Legal bump: no.

Spec:
- **MoneyTab**, exported per role. The owner's is read-only unless decision D1 allows; the warden's has actions.
  - **Dues**: category chips, status chips (due today, tomorrow, overdue), search, and rows that open the right payment sheet. Rent still uses the existing warden record-payment sheet, reached through a callback.
  - **Add charge** sheet.
  - **Bulk charge** stepper: pick the target (everyone, rooms or residents), then category, amount and due date, then a review with the count and total, then confirm, then a success screen with share text.
  - **Collections**: date range, mode filter, totals; rows open the receipt.
  - **Deposits**: the held list, and refund, adjust and forfeit sheets that require a reason where the server does.
  - **Reminders** stepper: pick residents with dues, preview, send push, and optionally share WhatsApp text.
- **LedgerScreen**: a balance header plus the timeline, opened from a resident's profile (staff) or the Rent tab (resident).
- **ReceiptScreen**, generalised to `rpc_receipt`: rent events, charge payments and deposit refunds. The printer animation stays. Share as PNG.
- **Resident Rent tab additions**: dues by category, deposit held, ledger, receipts list.
- Every money write: the button disabled while pending, `p_request_id` reused on retry, the server sentence shown on refusal, no optimistic updates.

**D-web-compat. Website compatibility for the new payment modes**
- Layers: website.
- Owns: `lib/types.ts`, plus the website files that render `payment_mode` (find them with a search for `'bank'` and payment-mode labels under `app/` and `lib/queries/`; list them in the PR).
- Live DB change: no. Legal bump: no.
- Spec: show "Cheque" and "Adjusted from deposit". `tsc` and lint stay clean. The website's own RPC callers are unaffected (no signature changes). The website's legal pages are D-legal's.

**D-legal. Legal version "money"** (combined with C's if they ship together)
- Owns the standard legal files plus `docs/store-listing/**`. Live DB change: **yes**. Legal bump: **yes**.
- Spec. Covers:
  - charges by category, meter readings and consumption per room and resident;
  - deposits and their refunds;
  - **the PG owner's UPI ID now being stored**, and UTR claims;
  - expense receipt photos (check the existing camera-purpose sentence);
  - staff cash handovers and petty cash;
  - automatic late fines and proration (terms).
- Update the store listing line "UPI IDs never reach…" and the Data safety evidence for financial info.

#### Wave D3

**D-integration**
- Layers: Flutter shells and wiring, `pubspec`.
- Owns:
  - `apnivaas_app/pubspec.yaml` (adds `qr: 4.0.0`; check the merged manifest)
  - `apnivaas_app/lib/features/owner/owner_tabs.dart`, `warden/warden_shell.dart`, `manager/manager_shell.dart`, `student/student_section.dart`
  - `warden/actions/register_student_sheet.dart` (deposit and joining-fee toggles calling `wd_add_charge` after registration, with the hostel defaults pre-filled)
  - `warden/students/student_sheet.dart` (ledger, deposit and late-fine pause entries)
  - `owner/owner_students_screen.dart` (ledger link)
  - `apnivaas_app/lib/features/property_settings/flags.dart` (`kMoneyDepthLive = true`)
  - `apnivaas_app/lib/features/home_blocks/inbox_kinds.dart` (the new kinds)
  - The warm-up tests.
- Live DB change: no. Legal bump: no.

**Phase D deploy order.**
1. `payment-mode-values`.
2. `charges-ledger`.
3. `meters`, `expenses-and-cash`, `upi-claims`, `money-path`, in filename order.
4. The `expense-receipt` Edge Function.
5. The legal row.
6. The website (D-web-compat plus legal).
7. The app.

**Phase D exit criteria.**
- Every money SQL test passes on a mirror and inside a rollback on live.
- No floating-point money in new Dart code: a lint-style test greps `double` in `lib/features/money/**`.
- Receipts only from server rows.
- Ten permissions after adding `qr`.

---

### Phase E: operations (gate, curfew, leave, guests, roll call, food)

**Goal.**
- Residents request gate passes, leave and guest stays in the app; wardens approve them.
- The gate desk logs entry and exit by a 6-digit pass code or by hand, against a curfew.
- Wardens see who is inside, and take a manual roll call.
- The kitchen gets meal settings, confirmations before a cutoff, meal codes at the counter and counts without names for the manager.

No camera scanning. Codes are typed, so there is no new SDK, no new camera purpose and no permission.

**Estimate.** 8 to 10 working days build, about 2 weeks calendar. **Release:** 1.5.0.

#### Wave E1

**E-ops-db-platform. Settings, enum values, leave status sync** (schema-sync owner for Phase E; also writes the last migration in wave E3)
- Layers: database, cron.
- Owns: `db/migrations/{D}-notification-types-ops.sql`, `db/migrations/{D}-ops-platform.sql` (+ `.down`/`.test`), `db/migrations/{D}-ops-retention-erasure.sql` (+ `.down`/`.test`, wave E3), `db/schema.sql`, `db/rls-policies.sql`.
- Live DB change: **yes**. Legal bump: covered by E-legal.

Spec:
1. **`{D}-notification-types-ops.sql`**: non-transactional. Add `gate`, `meal`, `attendance` and `guest` to `public.notification_type`.
   - Clients tolerate unknown types: check that the notification model's parse falls back, and add a test.
   - `notification_prefs`' check is rewritten to validate against `enum_range(null::public.notification_type)` minus 'system'.
2. **`hostel_settings`** gets these columns:
   - `curfew_time time null`
   - `late_entry_requires_pass boolean not null default false`
   - `gate_pass_max_days smallint not null default 3 check 1–14`
   - `guest_nightly_charge numeric(10,2) not null default 0 check 0–1e5`
   - `guest_max_nights smallint not null default 7 check 1–30`
   - `attendance_rounds jsonb not null default '[]'`: at most 2 entries of `{name 1–30, from 'HH:MM', to 'HH:MM'}`, validated by a CHECK function
   - `food_enabled boolean not null default false`
   - `ow_update_hostel_settings` is redefined (md5 against C's body) to accept these keys.
3. **`app.sync_leave_status()`**: cron `apnivaas-leave-status` at `'40 18 * * *'` UTC (00:10 IST). For non-vacated residents: an approved leave covering `app.today()` sets on_leave; on_leave with no covering approved leave sets active. Idempotent. One audit row with counts.
4. **`rpc_pending_inbox`** gains `gate_passes_pending`, `passes_overdue`, `guest_stays_pending` and `meal_counts_today` (manager and warden).
5. **Wave E3: `{D}-ops-retention-erasure.sql`**, which applies last.
   - `app.apply_retention`:
     - gate_events and gate_passes deleted after 6 months; passes never used expire 12 hours after return_by;
     - attendance_marks after 12 months;
     - meal_confirmations, meal_servings and meal_codes after 6 months;
     - guest_stays 2 months after to_date.
     - visitors after 6 months, **only if** E-legal confirms the policy allows adding a rule; it is an existing table with no retention rule today.
   - `app.erase_student`: delete the resident's gate passes and events, attendance, meal rows and guest stays.
   - Both md5-guarded against D's bodies.

#### Wave E2 (parallel verticals)

**E-gate. Gate passes, entry and exit log, curfew, who is inside**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-gate.sql`, `.down.sql`, `.test.sql`; `apnivaas_app/lib/features/ops/gate/**` (new); `apnivaas_app/test/gate_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by E-legal.

Spec:
- **`public.gates`**: id, hostel_id, name 1–40, `kind text check (main|internal)`, active, created_by. RLS: owner and warden select and write (writable).
- **`public.gate_passes`**
  - Columns: id, hostel_id, student_id, `kind text check (outing|late_entry|overnight)`, leave_at, return_by, reason ≤ 500, `status text check (pending|approved|rejected|cancelled|out|returned|expired)`, `code text check ('^[0-9]{6}$')`, decided_by, decided_at, decision_note, created_at.
  - CHECK `return_by > leave_at`.
  - Unique partial index (hostel_id, code) where status in (approved, out).
  - RLS: resident own; owner and warden. No manager. No client writes.
- **`st_request_gate_pass(p_kind, p_leave_at, p_return_by, p_reason)`**
  - A non-vacated resident; writable.
  - The span is at most `gate_pass_max_days`, and leave_at is no more than 1 hour in the past.
  - spend('gate_pass', 10, 86400). Notify wardens with access (type gate). Audit.
- **`st_cancel_gate_pass(p_id)`**: pending or approved only.
- **`wd_decide_gate_pass(p_id, p_approve, p_note)`**
  - `app.has_role_in(h,'warden','owner')`; writable.
  - Approve generates a random 6-digit code, retrying on collision.
  - The notification says "approved" and **never carries the code**, because pushes show on lock screens.
  - Audit.
- **`public.gate_events`**
  - Columns: id, hostel_id, student_id, gate_id, `direction text check (in|out)`, at default now(), `method text check (code|manual)`, pass_id, late boolean, reason ≤ 300, recorded_by, request_id unique, voided_at, voided_by, void_reason.
  - RLS: owner and warden; resident own. No client writes.
- **`wd_record_gate_event(p_hostel, p_student default null, p_code default null, p_direction, p_gate default null, p_reason default null, p_request_id)`**
  - auth warden or owner. Exactly one of student or code.
  - Code path: find an approved or out pass in this hostel with that code, valid now (going out between leave_at − 2h and return_by; coming in from out or approved). Moves the pass to out or returned. A wrong code gets "No active pass has that code."
  - Late is computed in Asia/Kolkata: direction in, `curfew_time` set, local time after curfew and before 05:00, and no covering pass. If late, `late_entry_requires_pass` is set and there is no pass, then a reason is required: "Add a reason for this late entry."
  - spend('gate_event', 600, 3600).
  - Audit manual events and voids only, to keep the log readable. Idempotent by request id.
- **`wd_void_gate_event(p_event, p_reason)`**: within 24 hours. Audit.
- **`rpc_inside_now(p_hostel, p_filter text default 'all')`**
  - SECURITY INVOKER: counts plus a paged list of inside, outside, overdue (out past return_by), on leave and unknown, from the last non-void event per resident.
- **App**:
  - resident: Gate pass request form, pass list, and an approved pass shown as a large 6-digit code with leave and return times.
  - warden: the Gate desk (a code keypad, an in/out toggle, a result card with name and room; a manual mode that searches a resident and asks for a reason when late); the Inside now board; the approvals queue.
  - Exports: `GateDeskScreen`, `InsideNowBoard`, `ResidentPassesSection`, `PassApprovalsSection`, `GateSettingsQuestions` (curfew, pass needed for late entry, longest pass).
- **Tests**:
  - SQL: the curfew boundary at 23:59 and 00:01 IST; passes overlapping midnight; a code reused after its pass returned; the manager seeing nothing; a code collision retried.
  - Dart: the keypad flow, offline retry with the same request id.

**E-leave-guests. Resident leave and guest stays**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-leave-and-guests.sql`, `.down.sql`, `.test.sql`; `apnivaas_app/lib/features/ops/leave/**` (new); `apnivaas_app/lib/features/ops/guests/**` (new); `apnivaas_app/lib/features/warden/home/desk_sheets.dart`; `apnivaas_app/test/leave_guests_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by E-legal.

Spec:
- **`leaves`**
  - Add `emergency boolean not null default false`.
  - Add a BEFORE INSERT trigger for every path, checking: from_date ≥ `app.today()` − 1; to_date between from_date and from_date + 90; reason 3–2000.
  - Add `app.rl_leave`, 5 per day per user.
  - **`st_request_leave(p_from, p_to, p_reason, p_emergency)`**: a definer wrapper with readable sentences. The existing resident insert policy stays for the website.
  - **`st_cancel_leave(p_id)`**: pending only.
- **`public.guest_stays`**
  - Columns: id, hostel_id, student_id, guest_name 2–120, `guest_phone '^[6-9][0-9]{9}$'`, relation ≤ 60, from_date, to_date (at most `guest_max_nights`), `status text check (pending|approved|rejected|cancelled|checked_in|checked_out|expired)`, nightly_charge (snapshot), charge_id, visitor_id, decided_by, decided_at, note, created_at.
  - RLS: resident own; owner and warden. No manager.
  - **`st_request_guest_stay(...)`**: spend('guest_stay', 5, 86400); writable; notify wardens.
  - **`st_cancel_guest_stay(p_id)`**.
  - **`wd_decide_guest_stay(p_id, p_approve, p_note)`**.
  - **`wd_guest_check_in(p_id)`**: inserts the `visitors` row and links it.
  - **`wd_guest_check_out(p_id)`**: sets `visitors.check_out_at`. If nightly_charge > 0, it creates a `guest` charge of nights × nightly_charge through the D charge insert path (source 'guest').
  - Audit all of them.
- **App**:
  - resident Requests: Leave (form with an emergency toggle, list, cancel) and Guest stay (form, list).
  - warden: leave and guest approvals; guest check-in and check-out; `desk_sheets.dart`'s leave and visitor sheets rebuilt onto these sections.
  - Exports: `ResidentLeaveSection`, `ResidentGuestSection`, `LeaveApprovalsSection`, `GuestApprovalsSection`, `GuestSettingsQuestions`.

**E-attendance. Manual roll call**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-attendance.sql`, `.down.sql`, `.test.sql`; `apnivaas_app/lib/features/ops/attendance/**` (new); `apnivaas_app/test/attendance_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by E-legal.

Spec:
- **`public.attendance_marks`**: id, hostel_id, student_id, on_date, `round smallint check 1–2`, `status text check (present|absent|on_leave|excused)`, marked_by, marked_at, unique (student_id, on_date, round). RLS: owner and warden; resident own.
- **`wd_mark_attendance(p_hostel, p_on_date, p_round, p_marks jsonb, p_request_id)`**
  - At most 500 marks. auth warden or owner; writable.
  - on_date is today or yesterday (IST), and the round exists in the settings.
  - Upsert. spend('attendance', 30, 3600). One audit row with counts.
- **`rpc_attendance_day(p_hostel, p_on_date, p_round)`**: SECURITY INVOKER. Non-vacated residents who had joined by that date, each with their mark, and on_leave pre-filled from approved leaves.
- **`st_my_attendance(p_month)`**: the resident's own month.
- **App**:
  - warden Roll call: round picker, list with present/absent toggles, "Mark the rest present", Save. The draft stays in memory and save retries with the same request id.
  - resident: an attendance calendar.
  - Exports: `RollCallScreen`, `ResidentAttendanceCard`, `AttendanceSettingsQuestions`.

**E-food. Meal settings, confirmations, codes, servings, counts, preference, menu copy**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-food.sql`, `.down.sql`, `.test.sql`; `apnivaas_app/lib/features/ops/food/**` (new); `apnivaas_app/lib/features/manager/menu/**`; `apnivaas_app/lib/features/student/menu_screen.dart`; `apnivaas_app/lib/features/student/widgets/menu.dart`; `apnivaas_app/test/student_menu_test.dart`; `apnivaas_app/test/food_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by E-legal.

Spec:
- **`students.food_preference text null check (veg|eggetarian|non_veg)`**.
  - **`st_set_food_preference(p_pref)`**.
  - Wardens set it through the existing student update path, validated by the CHECK.
- **`public.meal_settings`**
  - pk (hostel_id, meal). Columns: enabled, starts_at, ends_at, `confirm_cutoff_minutes smallint default 120 check 0–1440`, `allow_unconfirmed boolean default true`.
  - RLS: select for anyone who can read the hostel (residents need the times).
  - **`mg_set_meal_settings(p_hostel, p_meal, ...)`**: `app.has_role_in(h,'manager','owner')`; writable. Audit.
- **`public.meal_confirmations`**: id, hostel_id, student_id, on_date, meal, `status text check (confirmed|skipped)`, updated_at, unique (student_id, on_date, meal). RLS: resident own; owner and warden. **No manager.**
  - **`st_set_meal_confirmation(p_on_date, p_meal, p_status)`**
    - on_date between today and today + 7.
    - Refused after the cutoff, computed in IST, with "Confirmations for lunch closed at 10:30."
    - spend('meal_confirm', 60, 3600).
- **`public.meal_codes`**: pk (student_id, on_date), hostel_id, `code '^[0-9]{6}$'`, unique (hostel_id, on_date, code). Created lazily by **`st_my_meal_code(p_on_date default app.today())`**.
- **`public.meal_servings`**: id, hostel_id, student_id, on_date, meal, served_at, served_by, `method text check (code|manual)`, unique (student_id, on_date, meal).
  - **`wd_serve_meal(p_hostel, p_code default null, p_student default null, p_meal, p_request_id)`**
    - auth: `app.has_role_in(h,'warden','owner')`. G adds managers who hold `serve_meals`.
    - Returns the first name, preference and whether confirmed.
    - Refusals: "Already served at 13:05." and, when unconfirmed meals are not allowed, "Not confirmed for lunch."
- **`rpc_meal_counts(p_hostel, p_on_date)`**
  - SECURITY DEFINER, auth `app.has_role_in(h,'manager','warden','owner')`.
  - Per meal: confirmed, skipped, served, served without confirming, and veg/eggetarian/non-veg counts among the confirmed. **No names.**
- **`mg_copy_menu(p_from_hostel, p_from_day, p_to_hostel, p_to_days day_of_week[])`**: a manager with access to both PGs, or the owner of both; writable target; upsert menus. Audit.
- **App**:
  - manager Food: menu, meal settings questions per meal, today's counts, copy menu, share the menu as an image (`RepaintBoundary` to PNG).
  - resident: today's meals with confirm and skip until the cutoff, the meal code, preference in Profile.
  - warden: Serve meals (meal picker, code keypad, result card).
  - Exports: `ManagerFoodTab`, `ResidentMealBlock`, `ServeMealsScreen`, `FoodSettingsQuestions`.

**E-legal. Legal version "operations"**
- Owns the standard legal files. Live DB change: **yes**. Legal bump: **yes**.
- Spec. Covers:
  - residents' entry and exit times, gate passes and late-entry reasons;
  - roll-call marks;
  - meal confirmations, servings and dietary preference;
  - guest names and phone numbers (third-party data, deleted 2 months after the stay);
  - retention of each.
- Read the current visitor-log wording and decide whether a 6-month visitor retention can be added. Update Data safety (personal info, other).

#### Wave E3

- **E-ops-db-platform** writes `{D}-ops-retention-erasure.sql` (above).
- **E-integration**:
  - Owns:
    - `apnivaas_app/lib/features/warden/warden_shell.dart`, `warden/home/warden_home_screen.dart`
    - `apnivaas_app/lib/features/student/student_section.dart`, `student/home_screen.dart`, `student/profile_screen.dart`
    - `apnivaas_app/lib/features/manager/manager_shell.dart`, `manager/home/manager_home_screen.dart`
    - `apnivaas_app/lib/features/property_settings/questions_registry.dart`
    - `apnivaas_app/lib/features/home_blocks/inbox_kinds.dart`
    - `apnivaas_app/lib/core/notify/notification_links.dart` (registers `/student?tab=requests`, `/warden?tab=requests&section=<s>`)
    - The warm-up tests.
  - Layers: Flutter wiring. Live DB change: no. Legal bump: no.
  - Spec: place every exported section and screen in the warden Requests and Home quick actions (Gate desk, Roll call, Serve meals), the resident Requests and Home, and the manager Food tab; register the settings questions.

**Phase E deploy order.**
1. Notification types.
2. `ops-platform`.
3. `gate`, `leave-and-guests`, `attendance`, `food`.
4. `ops-retention-erasure`.
5. The legal row.
6. The website.
7. The app.

**Phase E exit criteria.**
- The SQL suites, including a manager seeing zero rows on every new resident table.
- IST curfew and cutoff boundary tests.
- No camera or scanner package.
- Ten permissions.

---

### Phase F: people (profile, documents, KYC record, agreements, checklists, move-out, leads, bookings, flags)

**Goal.** Each resident has:
- one profile with a passbook, documents, agreement, checklists and activity;
- a guided move-in and move-out, including deposit settlement in one transaction.

The PG also gets leads, bed bookings and owner-private "do not re-admit" flags.

**Estimate.** 10 to 14 working days build, about 3 weeks calendar. **Release:** 1.6.0.

**Data minimisation.**
- No Aadhaar, PAN or other ID numbers are stored anywhere; only scans, with a verification status.
- No blood group, nationality, parents' IDs or bank details.
- Flags never cross owners.

#### Wave F1

**F-people-db-platform. Profile columns, settings, last-seen** (schema-sync owner for Phase F; also writes the last migration in wave F3)
- Layers: database, Edge Function (`mobile-auth` last-seen write).
- Owns: `db/migrations/{D}-people-platform.sql` (+ `.down`/`.test`), `db/migrations/{D}-people-retention-erasure.sql` (+ `.down`/`.test`, wave F3), `db/schema.sql`, `db/rls-policies.sql`, `supabase/functions/mobile-auth/index.ts`.
- Live DB change: **yes**. Legal bump: covered by F-legal.

Spec:
1. **`students`** gets these columns:
   - `date_of_birth date`, `gender text check (male|female|other|undisclosed)`, `occupation text check (student|working|other)`, `institution text check (length <= 120)`
   - `emergency_contact_name` ≤ 80, `emergency_contact_phone '^[6-9][0-9]{9}$'`, `vehicle_number '^[A-Z0-9 -]{4,15}$'`
   - `kyc_status text not null default 'not_started' check (not_started|submitted|verified|rejected)`, `kyc_verified_by`, `kyc_verified_at`
   - `police_verification_status text not null default 'not_required' check (not_required|pending|submitted|verified)`
   - `lead_source text check (walk_in|phone|referral|website|broker|other)`, `onboarded_by uuid`
   - A validation trigger, `students_profile_validate`, requires date_of_birth to be after 1930-01-01 and at least 10 years before `app.today()`.
   - `kyc_*` and `police_*` change only through the RPCs below: they join the tenancy guard's flag list.
2. **`users.last_seen_at timestamptz`**, backfilled from `auth.users.last_sign_in_at`. `mobile-auth` sets it with the service client after every successful sign-in. "App not activated" means `students.user_id is null` or `last_seen_at is null`.
3. **`st_update_my_profile(p_patch jsonb)`**
   - Allow-list: date_of_birth, gender, occupation, institution, emergency_contact_name, emergency_contact_phone, vehicle_number, food_preference.
   - Validated. Audit with keys only.
4. **`rpc_birthdays_today(p_hostel)`**: SECURITY INVOKER, month and day of `app.today()`. Owner and warden through RLS.
5. **`hostel_settings`** gets `kyc_mandatory`, `checklist_before_agreement`, `guardian_signature_required` and `deposit_refund_requires_checklist` (all boolean, default false), `move_out_charges jsonb default '[]'` (at most 10 entries `{category, label, amount}`) and `move_out_terms text` ≤ 2000. `ow_update_hostel_settings` is redefined to accept them.
6. **Wave F3: `{D}-people-retention-erasure.sql`**
   - `app.apply_retention`:
     - leads marked junk or lost are deleted 90 days after `updated_at`; converted leads 30 days after conversion;
     - bookings past expected_move_in + 3 days become expired;
     - flags past `expires_at` are deleted.
   - `app.erase_student`: delete documents, agreements, signatures and checklists, and queue every storage key (documents, signature PNGs, agreement PDFs) through `app.enqueue_storage_erasure`. Signed agreements go with the resident's data, consistent with the owner's one-month erasure rule. Flags are pseudonymised and stay until expiry (decision D5).
   - Both md5-guarded against E's bodies.

#### Wave F2 (parallel verticals)

**F-documents-kyc. Document vault, KYC record, police verification**
- Layers: database, Edge Function, Flutter.
- Owns: `db/migrations/{D}-student-documents.sql` (+ `.down`/`.test`); `supabase/functions/student-documents/**` (new); `apnivaas_app/lib/features/people/documents/**` (new); `apnivaas_app/test/documents_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by F-legal.

Spec:
- **`public.student_documents`**
  - Columns: id, hostel_id, student_id, `doc_type text check (id_front|id_back|pan_card|college_or_work_id|police_verification|photo|other)`, storage_key, mime, size_bytes, `status text check (to_verify|verified|rejected)`, uploaded_by, verified_by, verified_at, reject_reason ≤ 300, created_at, deleted_at.
  - RLS: owner and warden of the hostel; resident own. No manager. No client writes.
  - Backfill rows from the existing `students.id_proof_url` and `photo_url` with status to_verify.
- **Edge Function `student-documents`**:
  - **upload**:
    - The caller is the resident, for themselves (`app.current_student_id`, checked under the caller's JWT), or a warden or owner, for a resident of their hostel (`requireOwnHostel` or `requireOwnedHostel`). `assertWritable`.
    - doc_type from the allow-list; at most 3 MB; JPEG, PNG, WebP or PDF, sniffed by content.
    - Path `<hostel>/documents/<uuid>.<ext>` in `student-docs`. 30 per hour.
    - The row is inserted with the service client after those checks.
  - **sign**: 15 minutes, only if the caller can SELECT the row under their own JWT.
  - **discard**: the uploader, within 1 hour, while still to_verify.
  - Deploy with `verify_jwt` on.
- **`wd_review_document(p_doc, p_verified, p_reason)`**: warden or owner. Notify the resident on rejection. Audit.
- **`wd_set_kyc_status(p_student, p_status, p_note)`**: `verified` requires at least one verified ID document. Audit.
- **`wd_set_police_verification(p_student, p_status)`**. Audit.
- **App**: a documents list with status chips; upload from camera or gallery through the existing capture flow; a viewer for the signed-URL image (PDFs are shared, not rendered); review actions; a KYC and police card.
  - Exports: `ResidentDocumentsTab`, `KycCard`.

**F-agreements. Rent agreement with signature pad**
- Layers: database, Edge Function, Flutter.
- Owns: `db/migrations/{D}-agreements.sql` (+ `.down`/`.test`); `supabase/functions/agreement-sign/**` (new); `apnivaas_app/lib/features/people/agreements/**` (new); `apnivaas_app/lib/shared/ui/signature_pad.dart` (new); `apnivaas_app/test/agreements_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by F-legal.

Spec:
- **`public.agreement_templates`**
  - Columns: id, hostel_id null (null is a platform default, managed by Super Admin), title 3–120, body 50–20,000 characters, version int, active, created_by.
  - Placeholders come only from an allow-list: `{{tenant_name}} {{owner_name}} {{pg_name}} {{pg_address}} {{room}} {{bed}} {{rent}} {{deposit}} {{lock_in_months}} {{notice_days}} {{start_date}} {{end_date}} {{rules}}`.
  - **`ow_save_agreement_template`** (owner) and **`sa_save_agreement_template`** (platform defaults) validate the placeholders.
- **`public.agreements`**
  - Columns: id, hostel_id, student_id, template_id, template_version, rendered_body, body_sha256, rent, deposit, lock_in_months, notice_days, start_date, end_date (after start, at most 36 months later), `status text check (draft|awaiting_tenant|awaiting_guardian|awaiting_owner|signed|void|expired)`, requires_guardian, pdf_key, renews_id, created_by, created_at, signed_at, voided_at, voided_by, void_reason.
  - RLS: owner and warden; resident own. No manager.
- **`public.agreement_signatures`**
  - Columns: id, agreement_id, hostel_id, `party text check (owner|tenant|guardian|witness)`, signer_user_id null, signer_name 2–80, signature_key, body_sha256, captured_by_user_id, signed_at, unique (agreement_id, party, signer_name).
- **`wd_create_agreement(p_student, p_template, p_overrides jsonb)`**
  - Warden or owner; writable.
  - Renders the body on the server, escaping the values, and stores `sha256` (pgcrypto).
  - The status becomes awaiting_tenant. Notify the resident. Audit.
- **`wd_void_agreement(p_id, p_reason)`**.
- **`wd_renew_agreement(p_id, p_new_end, p_renewal_charge default null)`**: a new agreement with `renews_id`, plus an optional `renewal` charge.
- **Edge Function `agreement-sign`**:
  - **Action `sign`**, body {agreementId, party, signerName, sha256, signaturePngBase64 of 200 KB or less}. Authorisation by party:
    - tenant: the caller is the resident's user, status awaiting_tenant;
    - guardian: the caller is the tenant or a warden or owner of the hostel, signing in person on that device; status awaiting_guardian;
    - witness: staff;
    - owner: the hostel owner at aal2 (`requireCaller` enforces MFA), status awaiting_owner.
  - The sha256 must equal the stored hash, otherwise 409 "This agreement changed. Open it again and read it before signing."
  - PNG sniffed. Uploaded to `student-docs` at `<hostel>/agreements/<uuid>.png`. The service client inserts the signature and advances the status. 20 per hour.
  - On the final signature: render the PDF with `npm:pdf-lib` (pinned exactly per `docs/dependency-policy.md`). It contains the body, the signature images with names and IST timestamps, and an audit page (agreement id, sha256, each signer, party, captured-by, time). Upload `<uuid>.pdf`, mark signed, notify the tenant and the owner, audit 'agreement.signed'.
  - **Action `pdf`**: a 15-minute signed URL if the caller can SELECT the agreement.
- **The UI and the PDF both say** "Signed in Apnivaas. This is not stamp paper and not an Aadhaar eSign." (decision D4).
- **App**:
  - create from a template (pick it, review the filled terms, send to the tenant);
  - a status timeline;
  - guardian capture ("hand the phone to the guardian");
  - owner signing;
  - the agreement text rendered natively;
  - "Share PDF" downloads the bytes and shares them. No PDF viewer package.
  - **SignaturePad**: a `CustomPainter` capturing strokes with clear and undo, exported through `PictureRecorder` to a 600x200 PNG.
  - Exports: `ResidentAgreementTab`, `AgreementTemplatesScreen`.

**F-checklists-moveout. Checklists, move-out settlement, bed swap, flags**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-checklists-moveout.sql` (+ `.down`/`.test`); `apnivaas_app/lib/features/people/checklists/**`, `apnivaas_app/lib/features/people/move_out/**`, `apnivaas_app/lib/features/people/flags/**` (all new); `apnivaas_app/test/move_out_test.dart`, `apnivaas_app/test/checklists_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by F-legal.

Spec:
- **`public.checklist_templates`**: hostel_id, `kind text check (move_in|move_out)`, items jsonb (1 to 50 entries `{key,label}`), updated_by. Saved with `ow_save_checklist_template` (owner or warden).
- **`public.checklists`**
  - Columns: id, hostel_id, student_id, kind, items jsonb (`{key,label,condition ok|damaged|missing|na,note ≤ 200}`), `status text check (draft|submitted|tenant_confirmed|approved)`, submitted_by, submitted_at, tenant_confirmed_at, tenant_note, approved_by, approved_at.
  - RLS: owner and warden; resident own.
  - **`wd_save_checklist(p_student, p_kind, p_items, p_submit)`**, **`st_confirm_checklist(p_id, p_note)`**, **`wd_approve_checklist(p_id, p_damage_charges jsonb default null)`**. Damage entries become `damage` charges.
- **`wd_refund_deposit`** is redefined (md5 against D's body) to refuse with "Finish the move-out checklist before refunding the deposit." when `deposit_refund_requires_checklist` is on and the move-out checklist is not approved.
- **`public.move_outs`**: id, hostel_id, student_id, `reason text check (course_completed|job_change|relocation|unhappy|evicted|other)`, move_out_date, key_returned, rating smallint 1–5 null, created_by, created_at, request_id unique. RLS: owner and warden.
- **`wd_move_out(p_student, p_reason, p_move_out_date, p_charges jsonb, p_deposit jsonb, p_key_returned, p_rating, p_flag jsonb, p_request_id)`**
  - auth warden or owner. The date is between today − 7 and today. At most 10 charges.
  - **One transaction**:
    1. add the move-out charges;
    2. compute the final month through `app.rent_due_for`;
    3. if `adjust_rent` is set, adjust the deposit against outstanding rent and charges, oldest first;
    4. refund and forfeit;
    5. insert the `move_outs` row;
    6. insert the optional flag;
    7. `perform public.wd_vacate_student(p_student)`, which deactivates the login and schedules erasure as today.
  - Idempotent. Audit 'warden.student.move_out'. Returns a settlement summary.
- **`wd_swap_beds(p_student_a, p_student_b)`**: same hostel, both non-vacated with beds, swapped atomically (null, set, set). The bed triggers maintain beds. Notify both residents. Audit.
- **Flags** stay switched off until the owner approves decision D5.
  - **`app.feature_flags`**: a singleton table, revoked from everyone, with `owner_flags boolean default false`.
    - While it is false, `wd_move_out` ignores `p_flag` and `rpc_flag_check` returns `{flagged:false}`.
    - The UI also hides flags behind the constant `kOwnerFlagsEnabled`.
    - Turning flags on takes a one-line migration plus a build, and both wait for D5.
  - **`app.flag_key`**: a singleton holding 32 random bytes generated by the migration, revoked from everyone.
  - **`public.owner_tenant_flags`**:
    - columns: id, owner_user_id, hostel_id, phone_hmac (hex `hmac(normalised phone, key, 'sha256')`), name_initials ≤ 10, `reason text check (unpaid_dues|property_damage|safety|rule_violation|other)`, note ≤ 300, rating, created_by, created_at, `expires_at default now() + interval '24 months'`;
    - RLS: owner only (`owner_user_id = (select auth.uid())` with MFA);
    - written only inside `wd_move_out`; `ow_delete_flag(p_id)` deletes one.
  - **`rpc_flag_check(p_hostel, p_phone)`**
    - SECURITY DEFINER, auth `app.has_role_in(p_hostel,'warden','owner')`.
    - Matches only flags whose owner is this hostel's owner. Returns `{flagged, reason, year}`.
    - spend('flag_check', 60, 3600). Audit with a hash. **Flags are never shared across owners.**
- **App**:
  - checklist editor and confirm;
  - the move-out stepper: reason and date, charges (pre-filled from `move_out_charges`), deposit settlement preview, key returned, rating and optional flag, review, confirm, then a summary with a shareable statement;
  - bed swap;
  - owner flags list.
  - Exports: `MoveOutFlow`, `ChecklistSection`, `SwapBedsSheet`, `OwnerFlagsScreen`.

**F-leads-bookings. Leads and bed bookings**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-leads-bookings.sql` (+ `.down`/`.test`); `apnivaas_app/lib/features/people/leads/**`, `apnivaas_app/lib/features/people/bookings/**` (new); `apnivaas_app/test/leads_bookings_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by F-legal.

Spec:
- **`public.leads`**
  - Columns: id, hostel_id, name 2–80, phone, `source text check (walk_in|phone|referral|website|broker|other)`, budget, preferred_sharing, move_in_date, `status text check (new|follow_up|visit_scheduled|visit_done|converted|junk|lost)`, next_follow_up_at, visit_at, `visit_kind text check (in_person|video|family)`, notes ≤ 2000, assigned_to, converted_student_id, created_by, created_at, updated_at, deleted_at.
  - RLS: owner and warden. G adds managers who hold `manage_leads`.
  - Direct insert and update are allowed through RLS, with writable in WITH CHECK plus the rate-limit trigger `app.rl_lead` (100 per day per user).
  - **`wd_delete_lead`**: soft delete.
  - **`wd_convert_lead(p_lead, p_student)`**.
  - `rpc_pending_inbox` gains `lead_follow_ups_due`.
- **`public.bed_bookings`**
  - Columns: id, hostel_id, bed_id, lead_id, name, phone, expected_move_in (today to today + 180), `token_amount numeric(10,2) default 0`, token_mode, token_collected_on, token_collected_by, `status text check (booked|converted|cancelled|expired|no_show)`, refunded_amount, cancel_reason, student_id, created_by, created_at, request_id unique.
  - Unique partial index (bed_id) where booked.
  - RLS: owner and warden.
  - **`wd_create_booking`**: the bed is free, or under notice with `planned_move_out` before expected_move_in; writable.
  - **`wd_cancel_booking(p_id, p_reason, p_refund_amount)`**: the refund is at most the token.
  - **`wd_convert_booking(p_booking, p_student)`**: creates a `booking_token` charge plus a matching `charge_payments` row with the token's mode, then marks it converted.
- **`rpc_bed_board`**: drop and create in the same transaction, appending `booking_id` and `booked_name` and the status `booked`, with grants restated. Old clients read by position, so the new columns go last.
- **`rpc_staff_cash_position`** is redefined (md5 against D's body) to count token cash.
- **App**:
  - a leads pipeline (status chips, list, detail, schedule a visit, follow-up date, copy number, convert to tenant, which opens the registration with the details pre-filled);
  - bookings from the bed board (vacant bed, then "Book this bed") and a list (cancel, convert).
  - Exports: `LeadsScreen`, `BookingSheet`, `BookingsList`.

**F-profile-app. Resident profile, add-tenant flow, past tenants, birthdays, resident self-edit**
- Layers: Flutter.
- Owns: `apnivaas_app/lib/features/people/profile/**`, `apnivaas_app/lib/features/people/past_tenants/**` (new); `apnivaas_app/lib/features/warden/actions/register_student_sheet.dart`; `apnivaas_app/test/warden_register_student_test.dart`; `apnivaas_app/test/resident_profile_test.dart` (new).
- Live DB change: no. Legal bump: no.

Spec:
- **QuickViewCard**: name, room, dues, chips, actions.
- **ResidentProfileScreen**, with tabs:
  - Overview: details, terms, contacts, KYC and police.
  - Passbook: D's LedgerScreen.
  - Documents, Agreement and Checklists: slots filled by the integrator.
  - Activity: a placeholder until G.
- **Add-tenant flow**, a stepper:
  1. bed, pre-filled from the bed board;
  2. person, with `rpc_flag_check` warning on the phone number;
  3. ID proof and photo;
  4. money: rent, deposit default, joining-fee toggle;
  5. terms: lock-in and notice;
  6. review.
  - Then `warden-register-student`, then follow-up writes, each with its own request id: charges, extra profile fields, lead conversion.
- **Past tenants**: vacated and not yet erased, with dues outstanding and a share-text reminder.
- **BirthdaysBlock**.
- **ResidentProfileEditScreen** (`st_update_my_profile`).

**F-legal. Legal version "people"**
- Owns the standard legal files. Live DB change: **yes**. Legal bump: **yes**.
- Spec. Covers:
  - date of birth, gender, occupation and institution, emergency contact, vehicle number;
  - document types and verification status;
  - KYC and police verification status (no ID numbers stored);
  - agreements and drawn signatures, with the not-stamp-paper statement;
  - checklists; move-out records and ratings;
  - **owner-private flags**: pseudonymised phone, 24 months, never shared across owners;
  - leads and bookings: prospect data and its retention;
  - last-seen time.
- Data safety: personal info (other), photos and files.

#### Wave F3

- **F-people-db-platform** writes `{D}-people-retention-erasure.sql`.
- **F-integration**:
  - Owns: `apnivaas_app/lib/features/owner/owner_tabs.dart`, `owner/owner_students_screen.dart`, `warden/students/warden_students_screen.dart`, `warden/students/student_sheet.dart`, `warden/warden_shell.dart`, `student/student_section.dart`, `student/profile_screen.dart`, `apnivaas_app/lib/features/rooms_board/bed_board_actions.dart`, `apnivaas_app/lib/features/home_blocks/inbox_kinds.dart`, `apnivaas_app/lib/features/property_settings/questions_registry.dart`, the warm-up tests.
  - Layers: Flutter wiring. Live DB change: no. Legal bump: no.
  - Spec:
    - People tab: Residents, Leads and bookings, Past tenants; for the owner, Flags.
    - Situation chips: documents missing, KYC pending, agreement unsigned, app not activated.
    - The profile tab slots get the documents, agreement and checklist exports.
    - The bed board gets "Book this bed" and "Add tenant here".
    - The resident Profile gets edit, documents, agreement signing and checklist confirmation.
    - The settings questions (KYC mandatory, checklist before agreement, guardian signature, refund needs checklist, move-out charges and terms) are registered.

**Phase F deploy order.**
1. `people-platform`.
2. `student-documents`, `agreements`, `checklists-moveout`, `leads-bookings`.
3. `people-retention-erasure`.
4. The Edge Functions: `student-documents`, `agreement-sign`, `mobile-auth`.
5. The legal row.
6. The website.
7. The app.

**Phase F exit criteria.**
- The SQL suites, including the manager seeing nothing.
- Erasure queues every new storage key: a test asserts `app.storage_erasures` rows after `app.erase_student`.
- Flags: a test proves an owner cannot match another owner's flags.
- The agreement sha256 mismatch path is tested.
- Ten permissions.

---

### Phase G: team, complaints, tasks and notices

**Goal.**
- Owners grant a few server-enforced capabilities to staff, off-board staff properly, and read team and tenant activity.
- Staff can mark themselves on duty.
- Complaints get assignment, comments, priority, rating, reopen, escalation and linked costs.
- Tasks become editable and recurring and can go to wardens.
- Notices can target rooms or people and show who read them.

**Estimate.** 6 to 8 working days build, 1.5 to 2 weeks calendar. **Release:** 1.7.0, with H.

**Migration order** is fixed by prefix, because later files use earlier objects: `{D}-g1-team.sql`, then `{D}-g2-complaints.sql`, then `{D}-g3-tasks-notices.sql`.

#### Wave G1 (parallel verticals)

**G-team. Capabilities, job titles, off-boarding, activity, duty log** (schema-sync owner for Phase G)
- Layers: database, Edge Function, Flutter.
- Owns: `db/migrations/{D}-g1-team.sql` (+ `.down`/`.test`), `db/schema.sql`, `db/rls-policies.sql`, `supabase/functions/owner-staff-account/**` (new), `apnivaas_app/lib/features/team/**` (new), `apnivaas_app/lib/features/owner/staff/**`, `apnivaas_app/test/owner_staff_test.dart`, `apnivaas_app/test/team_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by G-legal.

Spec:
- **`staff_hostel_access.capabilities text[] not null default '{}'`**, with a check that values come from (confirm_upi, correct_payments, post_notices, serve_meals, view_cash_positions, manage_leads).
  - Backfill `correct_payments` for every existing warden row, so today's behaviour is preserved.
- **`users.job_title text check (length <= 40)`**.
- **`owner_set_staff_capabilities(p_user, p_hostel, p_caps text[])`** and **`owner_set_staff_title(p_user, p_title)`**: the owner of the hostel; spend('staff_caps', 60, 600). Audit.
- **`app.staff_has_capability(p_hostel, p_cap)`**: true when the caller's `user_hostel_id` equals p_hostel and their access row holds the capability.
- **Redefinitions**, md5-guarded against the live and previous-phase bodies:
  - `wd_correct_payment`: a warden needs `correct_payments`; the owner is unchanged.
  - `ow_decide_upi_claim`: admits a warden holding `confirm_upi`.
  - `wd_serve_meal`: admits a manager holding `serve_meals`, who sees only the first name.
  - `leads` policies: admit a manager holding `manage_leads`.
  - `rpc_staff_cash_position`: a manager holding `view_cash_positions` sees every staff member's totals.
- **`public.staff_duty_log`**: id, hostel_id, user_id, `kind text check (on|off)`, at default now(), note ≤ 200. RLS: owner select; staff own.
  - **`staff_set_duty(p_hostel, p_on, p_note)`**: the caller is a manager or warden with access. "You're already on duty." when the state would not change. spend('duty', 20, 86400).
  - **`rpc_staff_on_duty(p_hostel)`**: owner.
- **`rpc_team_activity(p_hostel, p_actor default null, p_before default null, p_limit default 50)`** (limit at most 100)
  - SECURITY DEFINER: `app.owns_hostel` or super admin.
  - Reads `audit_log` for that hostel, limited to an allow-list of actions. Never returns ip, user agent or meta keys outside the allow-list.
- **`rpc_tenant_activity(p_student, ...)`**: the owner or a warden of the hostel. Rows whose target or meta student is that resident.
- **`ow_reassign_tasks(p_from, p_to)`**: owner.
- **`app.apply_retention`** redefinition: the duty log is deleted after 12 months.
- **Edge Function `owner-staff-account`**:
  - Common checks: `requireCaller('owner')`, `requireVerifiedEmail`, and the target must hold access to one of the caller's PGs (verified with `requireOwnedHostels`). Rate limited. Audited.
  - **offboard**: status inactive through `callerClient` (`users_update_guard` admits the owner); `svc_revoke_user_sessions`; `ow_reassign_tasks`.
  - **reset-password**: a temporary password returned once with no-store, `must_change_password`, pending tokens cleared, sessions revoked, and a security alert from the existing detection rule.
  - **set-email**: through a new `svc_set_staff_login_email` door built on `app.set_owner_login_email`'s pattern. Requires a verified email.
  - Deploy with `verify_jwt` on.
- **App**:
  - Team screen: staff list with job titles, PG access, capability toggles with plain explanations, off-board (a confirmation naming the person plus reassignment), reset password (a hard-to-dismiss dialog), set email, an on-duty board.
  - Activity screens: team, and per resident (exported for F's Activity tab).
  - A staff "On duty" toggle on warden and manager Home.

**G-complaints. Complaints upgrade**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-g2-complaints.sql` (+ `.down`/`.test`), `apnivaas_app/lib/features/warden/complaints/**`, `apnivaas_app/lib/features/student/complaints_screen.dart`, `complaint_detail_sheet.dart`, `raise_complaint_sheet.dart`, `apnivaas_app/lib/features/student/widgets/complaint.dart`, `apnivaas_app/lib/features/owner/owner_complaints_screen.dart`, `apnivaas_app/test/complaints_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by G-legal.

Spec:
- **`complaints`** gets:
  - `assigned_to uuid null`: an active warden with access, enforced by the trigger `complaints_assignee_guard`;
  - `priority text not null default 'normal' check (low|normal|high|urgent)`, `room_id uuid null`, `raised_by uuid null`;
  - `rating smallint check 1–5`, `rating_note ≤ 500`, `reopened_count smallint not null default 0`, `escalated_at`.
  - Residents write rating and reopen only through the RPCs below.
- **`expenses.complaint_id uuid null references complaints on delete set null`**. `charges.complaint_id` already exists from D.
- **`public.complaint_comments`**: id, complaint_id, hostel_id, author_id, body 1–2000, `mentions uuid[]` (validated as staff of the hostel), `internal boolean not null default true`, created_at, deleted_at.
  - RLS: owner and warden see everything; a resident sees `internal = false` comments on their own complaints.
- **RPCs**:
  - `wd_assign_complaint(p_id, p_user)`
  - `wd_add_complaint_comment(p_id, p_body, p_internal)`: notifies mentioned staff and, if not internal, the resident
  - `wd_set_complaint_priority`
  - `wd_raise_complaint_for(p_student, p_category, p_title, p_description, p_priority, p_room)`: staff on a resident's behalf; `raised_by` set; `app.rl_complaint` applies per staff member
  - `st_rate_complaint(p_id, p_rating, p_note)`: own complaint, resolved, once
  - `st_reopen_complaint(p_id, p_reason)`: within 7 days of resolution, at most 2 times; moves it back to open
  - `wd_link_complaint_cost(p_id, p_expense default null, p_charge default null)`
  - Audit all of them.
- **Trigger `users_offboard_unassign`**: when a staff member becomes inactive, clear `assigned_to` on their open complaints.
- **`hostel_settings.complaint_escalation_hours smallint not null default 48 check 4–336`**, with `ow_update_hostel_settings` redefined to accept it.
- **`app.escalate_complaints()`**: hourly cron `apnivaas-complaint-escalation` at `'20 * * * *'`. Open or in-progress complaints older than the threshold with `escalated_at` null: notify the owner once and stamp `escalated_at`.
- **App**:
  - warden queue filters (status, priority, assignee, category) and a summary sheet;
  - complaint sheet with assignment, priority, comments (internal and to the resident), cost link and timeline;
  - resident: rate a resolved complaint, reopen, see public replies;
  - staff raise on a resident's behalf.

**G-tasks-notices. Tasks edit and recurrence, warden tasks, targeted notices, read receipts**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-g3-tasks-notices.sql` (+ `.down`/`.test`), `apnivaas_app/lib/features/owner/notices/**`, `apnivaas_app/lib/features/owner/tasks/**`, `apnivaas_app/lib/features/manager/tasks/**`, `apnivaas_app/lib/features/student/notices_screen.dart`, `apnivaas_app/lib/features/student/widgets/notice.dart`, `apnivaas_app/lib/features/common/staff_notices.dart`, `apnivaas_app/lib/features/warden/notices/**`, `apnivaas_app/test/owner_notices_test.dart`, `apnivaas_app/test/tasks_notices_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by G-legal.

Spec:
- **Tasks**
  - `tasks.recurrence text not null default 'none' check (none|daily|weekly|monthly)`.
  - Redefine `app.tasks_assignee_guard` so the assignee may be an active manager **or warden** with access to the task's PG.
  - Redefine `app.tasks_before_update` so warden assignees, like managers, may change only the status.
  - Redefine `app.tasks_after_change`: when a recurring task is marked done, insert the next occurrence (due date plus the interval) if the assignee is still valid; otherwise notify the owner.
  - **`ow_update_task(p_id, p_title, p_description, p_due_date, p_assignee, p_recurrence)`** and **`ow_delete_task(p_id)`** (soft): owner. Audit.
- **Notices**
  - `announcements.audience_rooms uuid[] null` and `audience_students uuid[] null`.
  - Redefine the `announcements_select` policy: a resident sees a row when the audience is all or students **and** either both arrays are null, or their student id is in `audience_students`, or their room is in `audience_rooms`. Verify against live `pg_policy` first and keep the hoisted form.
  - Redefine `announcements_insert`: the owner as today, **or** a warden holding `post_notices`, with audience students or all, author = `auth.uid()`, the warden's own hostel, writable, and the existing `app.rl_announcement`.
  - **`ow_update_announcement(p_id, p_title, p_body)`**: the author or the owner, within 7 days. Audit.
  - **`public.announcement_reads`**: pk (announcement_id, user_id), read_at, cascading with the announcement.
    - **`my_mark_notice_read(p_id)`**: idempotent.
    - **`rpc_notice_reads(p_id)`**: the owner or the author; counts plus names of readers and non-readers among the audience.
- **App**:
  - compose with audience (everyone, residents, wardens, rooms, chosen residents) and templates (water cut, rent reminder, maintenance visit, holiday menu);
  - edit;
  - read counts with a "Seen by" list;
  - resident notices marked read on view;
  - owner tasks: edit, delete, recurrence, assign to a warden;
  - manager and warden task lists.

**G-legal. Legal version "team"**
- Owns the standard legal files. Live DB change: **yes**. Legal bump: **yes**.
- Spec: covers staff on-duty times, the team activity view, read receipts, complaint comments, ratings and assignment, and staff job titles.

#### Wave G2

**G-integration**
- Owns: `apnivaas_app/lib/features/owner/owner_tabs.dart`, `owner/more/owner_more_screen.dart`, `warden/warden_shell.dart`, `warden/home/warden_home_screen.dart`, `manager/manager_shell.dart`, `manager/home/manager_home_screen.dart`, `apnivaas_app/lib/features/people/profile/activity_slot.dart`, `apnivaas_app/lib/features/home_blocks/inbox_kinds.dart`, `apnivaas_app/lib/core/notify/notification_links.dart`, the warm-up tests.
- Layers: Flutter wiring. Live DB change: no. Legal bump: no.
- Spec:
  - People: a Team tab for the owner.
  - The Activity slot in the resident profile.
  - The duty toggle on staff Home.
  - The escalation and mention links registered.
  - Inbox kinds `complaints_escalated` and `tasks_due_today`.

**Phase G deploy order.** `g1`, then `g2`, then `g3`, then the `owner-staff-account` Edge Function, then the legal row, then the website, then the app.

**Phase G exit criteria.**
- SQL tests for every redefined policy and function, across every role.
- The capability backfill keeps existing wardens able to correct payments.
- Off-boarding revokes sessions: the QA script shows the refresh token fails afterwards.

---

### Phase H: insight and growth

**Goal.**
- Owners see analytics and export reports as PDF or CSV through the share sheet.
- Scheduled reports arrive as in-app notices.
- Residents rate their stay each quarter. Happy owners are asked for a Play review.
- Owners refer other owners.
- Staff can open support tickets that Super Admin answers.

**Estimate.** 6 to 8 working days build, 1.5 to 2 weeks calendar. **Release:** 1.7.0, with G.

**Migration order:** `{D}-h1-reports.sql`, then `{D}-h2-reviews.sql`, then `{D}-h3-growth.sql`.

#### Wave H1 (parallel verticals)

**H-reports. Analytics, reports, schedules** (schema-sync owner for Phase H)
- Layers: database, cron, Flutter.
- Owns: `db/migrations/{D}-h1-reports.sql` (+ `.down`/`.test`), `db/schema.sql`, `db/rls-policies.sql`, `apnivaas_app/lib/features/insights/**` (new), `apnivaas_app/test/insights_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by H-legal.

Spec:
- **Aggregate RPCs**, all SECURITY INVOKER (so RLS shapes them) except where noted. Bounded ranges: at most 24 months and at most 366 days for daily series.
  - `rpc_collection_report(p_hostel, p_from, p_to)`: per day and per mode, rent plus charges.
  - `rpc_dues_ageing(p_hostel, p_as_of)`: 0–30, 31–60, 61–90 and 90+ days.
  - `rpc_occupancy_trend(p_hostel, p_months)`: from `daily_hostel_snapshots`, owner only.
  - `rpc_expense_report(p_hostel, p_from, p_to)`: by category and kind.
  - `rpc_complaints_report(p_hostel, p_from, p_to)`: counts by category, median resolution hours, average rating.
  - `rpc_food_report(p_hostel, p_from, p_to)`: confirmed against served per meal; SECURITY DEFINER, with no names.
  - `rpc_attendance_report(p_hostel, p_month)`.
- **`public.report_schedules`**: id, hostel_id, owner_user_id, `report_kind text check (collections|dues|expenses|occupancy|complaints|food|attendance)`, `day_of_month smallint check 1–28`, `hour_ist smallint check 6–22`, recipients uuid[] (the owner plus that hostel's staff only, validated), active, last_sent_at.
  - RLS: owner.
  - **`ow_save_report_schedule(...)`** and **`ow_delete_report_schedule(p_id)`**.
- **`app.dispatch_report_schedules()`**: hourly cron `apnivaas-report-schedules` at `'5 * * * *'`. It writes an in-app notification "Your <report> for <month> is ready" linking to the report screen, deduplicated per schedule and month. **No email** (decision D2).
- **App**:
  - an Analytics dashboard of blocks: collections trend, dues ageing, occupancy trend, expenses by category, complaint resolution, food waste. Each block has a period picker, trend badges against the previous period, and an InfoSheet.
  - Reports: pick a report and period, preview, then "Share as PDF" (the `pdf` package, pure Dart, embedding the bundled Manrope TTF for the ₹ glyph) or "Share as CSV" (`share_plus` `XFile.fromData`).
  - Schedule editor.
  - A tenant statement PDF from the ledger.

**H-reviews. Stay reviews and Play in-app review**
- Layers: database, cron, Flutter.
- Owns: `db/migrations/{D}-h2-reviews.sql` (+ `.down`/`.test`), `apnivaas_app/lib/features/reviews/**` (new), `apnivaas_app/test/reviews_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by H-legal.

Spec:
- **`public.stay_reviews`**: id, hostel_id, student_id, `rating smallint check 1–5`, body ≤ 1000, `anonymous boolean not null default true`, `period text check ('^\d{4}-Q[1-4]$')`, created_at, unique (student_id, period).
  - RLS: resident own select only. **No owner select policy**: owners read through **`rpc_reviews(p_hostel, p_period)`**, SECURITY DEFINER for the owner, which returns the name only when the review is not anonymous, plus the average and distribution.
- **`st_submit_review(p_rating, p_body, p_anonymous)`**: the current quarter; spend('review', 3, 86400).
- **`app.prompt_stay_reviews()`**: daily at 04:30 UTC (10:00 IST). On a quarter's 1st and 15th day, notify active residents with a login who have not reviewed, deduplicated per quarter.
- `app.erase_student`: no change needed; reviews cascade with the student row, or a cascade is added.
- **In-app review**:
  - the `in_app_review` package (Play In-App Review API);
  - owners only, after success moments: the PG approved, the 10th payment recorded, the first month fully collected;
  - at most once every 120 days, tracked by a local marker;
  - **verify that the merged manifest still lists ten permissions** before merge.
- **App**: the resident rating sheet, and an owner Reviews screen.

**H-growth. Referrals, help and support tickets**
- Layers: database, Flutter.
- Owns: `db/migrations/{D}-h3-growth.sql` (+ `.down`/`.test`), `apnivaas_app/lib/features/referrals/**`, `apnivaas_app/lib/features/support/**`, `apnivaas_app/lib/features/super_admin/support/**` (all new), `apnivaas_app/test/growth_test.dart` (new).
- Live DB change: **yes**. Legal bump: covered by H-legal.

Spec:
- **Referrals**
  - **`public.referral_codes`**: owner_user_id pk, code (8 unambiguous characters) unique, created_at.
  - **`public.referrals`**: id, code, referrer_owner_id, referred_user_id unique, application_id, `status text check (signed_up|approved|rewarded|void)`, reward_note, rewarded_by, rewarded_at.
  - **`my_referral_code()`**: an owner; created lazily.
  - Trigger on `hostel_applications`: on insert with a `referral_code`, resolve it into a `referrals` row (self-referral refused silently). On approval, move it to approved.
  - **`sa_mark_referral_rewarded(p_id, p_note)`**: Super Admin grants the reward by hand, for example by extending a plan with `sa_renew_subscription` on the website. Tenant coins are not built.
- **Support**
  - **`public.support_tickets`**: id, hostel_id null, opened_by, subject 3–120, body ≤ 4000, `category text check (billing|bug|how_to|account|other)`, `status text check (open|answered|closed)`, created_at, updated_at.
  - **`public.support_messages`**: id, ticket_id, author_id, body 1–4000, created_at.
  - RLS: the opener and super admins.
  - **`staff_open_ticket`**: owner, manager or warden; spend('support', 5, 86400).
  - **`staff_reply_ticket`**, **`sa_reply_ticket`**, **`sa_set_ticket_status`**. Notifications both ways. Residents are not included: they contact their PG.
  - Retention: closed tickets deleted after 12 months, through an `app.apply_retention` redefinition owned here.
- **App**:
  - "Refer an owner": the code, plus share text through `share_plus`.
  - Help: static FAQ and illustrated how-to guides, bundled; no video streaming and no web view.
  - Tickets: list, thread, new ticket.
  - Super Admin: tickets inbox, and referral attribution in Applications.

**H-legal. Legal version "growth"**
- Owns the standard legal files. Live DB change: **yes**. Legal bump: **yes**.
- Spec. Covers:
  - stay reviews, including the anonymous option;
  - the referral linkage, with referral terms in the Terms;
  - support tickets;
  - report schedules;
  - the Play in-app review: Google's sheet, and no data from us.

#### Wave H2

**H-integration**
- Owns: `apnivaas_app/pubspec.yaml` (adds `pdf` and `in_app_review`; check the merged manifest), `apnivaas_app/lib/features/owner/owner_tabs.dart`, `owner/more/owner_more_screen.dart`, `apnivaas_app/lib/features/super_admin/sa_shell.dart`, `super_admin/sa_overview_screen.dart`, `apnivaas_app/lib/features/warden/warden_shell.dart`, `apnivaas_app/lib/features/manager/manager_shell.dart`, `apnivaas_app/lib/features/student/student_section.dart`, `apnivaas_app/lib/features/home_blocks/inbox_kinds.dart`, `apnivaas_app/lib/core/notify/notification_links.dart`, the warm-up tests.
- Layers: Flutter wiring. Live DB change: no. Legal bump: no.
- Spec:
  - Owner More: Analytics, Reports, Reviews, Refer an owner, Help.
  - Money: a Reports entry.
  - Staff: a Help entry.
  - Super Admin: Support from Overview.
  - Resident: the review prompt deep link.

**Phase H deploy order.** `h1`, then `h2`, then `h3`, then the legal row, then the website, then the app.

**Phase H exit criteria.**
- The SQL tests pass.
- Generated PDFs contain ₹. Tests check the bytes, not by rendering.
- Ten permissions after adding `pdf` and `in_app_review`.

---

## 5. Security and robustness requirements (definition of done for every workstream)

A workstream is not done until each applicable line below is true and its tests prove it. Reviewers reject anything that relies on the client for a rule that matters.

### 5.1 Authorisation lives on the server

1. **Every write is either an RLS policy with `app.hostel_writable(hostel_id)` in WITH CHECK, or a SECURITY DEFINER RPC that authorises as its first statement.** The check uses `if not coalesce(<check>, false) then raise exception ... using errcode = '42501'`, so a NULL fails closed. Service-only functions are revoked from public, anon and authenticated, and re-check `app.is_service_role()` in the body.
2. **Never trust the client** for role, hostel, student, owner, amount, period, date or status. Derive them on the server:
   - hostel from `app.user_hostel_id()`, `app.owned_hostel_ids()` or the target row's `hostel_id`;
   - period from `app.today()`;
   - amounts from the ledger.
   - Edge Functions take the tenant from `requireOwnHostel` or `requireOwnedHostel(s)`, never from the body.
3. **Role boundaries are tested on every new table and RPC**, with SQL tests impersonating each caller:
   - super admin, the owner, another hostel's owner, a warden with access, a warden whose access was removed, a manager, the resident, another resident, a waiting self-signup tenant, and anon.
   - A manager gets zero rows on every table holding resident data.
4. **MFA**: privileged reads and writes go through the app helpers, which AND `app.mfa_satisfied()`. Edge Functions use `requireCaller`, which enforces aal2 for owners and super admins.
5. **The billing-word contract.** Read-only refusals contain 'suspended', 'subscription', 'read-only' or 'expired'. No other error may contain those words.
6. **Errors.**
   - P0001 with a sentence the app shows verbatim, for every refusal a real user can reach.
   - 42501 for authorisation. 22023 for an invalid parameter. 23505 mapped to a friendly sentence.
   - One message for "missing" and "not yours", so there is no oracle.
   - Server sentences are brand-free.

### 5.2 Abuse controls

7. **Every new write path is rate-limited.**
   - Database paths: `app.spend` buckets as specified per RPC. These fail open by design.
   - Edge Functions: `enforceRateLimit` with keys `'<area>:<action>:' + id`. These fail closed with 503.
   - Anonymous endpoints (`self-signup`, `book-demo`) carry per-IP, per-identifier and global caps.
8. **Bodies are bounded.** JSON of 8 KB or less, except uploads (3 MB for images, 200 KB for signatures). Arrays are capped (500 residents, 200 reminders, 20 PGs, 10 charges). Text has length CHECKs on the column **and** validation in the RPC.
9. **No account enumeration.** Sign-up and password reset answer the same way whether or not an address exists.

### 5.3 Audit and idempotency

10. **Every privileged or money write is audited**:
    - action `<area>.<object>.<verb>`;
    - actor taken from the verified session;
    - meta never includes secrets, tokens, passwords, codes or full phone numbers (hash them);
    - `surface` of 'rpc' or 'edge_function'.
    - High-volume operational writes (gate events, meal servings, attendance) audit only manual overrides and voids, plus one summary row per batch.
11. **Idempotency.**
    - Every money or bulk write takes `p_request_id`, stored in a unique column; a replay returns the first result.
    - Cron outputs use `dedupe_key` with `on conflict do nothing`.
    - Status changes use claim predicates (`update ... where status = 'pending' returning`).
    - Reversals are new rows with a unique `reverses_id`.
    - **Nothing financial is ever updated in place or deleted.**
12. **Concurrency.** Use `select ... for update` or `pg_advisory_xact_lock(hashtextextended(key,0))`, taking several locks in a fixed uuid order. Partial unique indexes guard one-active-X rules: one pending application, one booked bed, one active pass code, one UTR.

### 5.4 Money and time

13. **Money.**
    - Rupees are `numeric(10,2)` (rent and charges, at most 1e7) or `numeric(12,2)` (expenses, handovers, subscriptions, at most 1e8), always with CHECKs.
    - Gateway amounts are paise `bigint`. NaN is refused (`= 'NaN'::numeric`).
    - Amounts are greater than zero except reversal rows.
    - Splits are exact: the remainder paise are distributed deterministically.
    - In Dart, money is `Money` (integer paise). Never `double`, never client-side arithmetic that the server does not repeat.
14. **IST.**
    - Every user-facing day and month comes from `app.today()` or `Asia/Kolkata` conversions. Never `current_date` or `now()::date`.
    - Ranges are sargable (`>= from and < to`).
    - Cron times are documented in UTC and IST (Appendix C).
    - Tests cover 18:29 and 18:31 UTC.
    - Dart never decides a business day from `DateTime.now()`; it displays server dates.

### 5.5 Navigation, state and rebuilds

15. **No navigation or auth loops.**
    - `resolveRedirect` stays pure and is the only gate.
    - Every new route is in `appScreens` and in the matrix test for every `AuthPhase`.
    - `to == here` returns null.
    - Never add `/splash` to `_publicRoutes`.
    - `!needsPasswordChange && mustVerifyEmail` stays.
    - Detail screens are imperative pushes.
    - Push taps and deep links go through `pendingDestinationProvider`, consumed after the gates.
    - Widgets never call `context.go` in `build`.
16. **No infinite rebuilds or leaks.**
    - Family providers are keyed by stable value types (ids and records), never by freshly built objects.
    - No `ref.watch` of a provider that `ref.invalidate`s itself.
    - No `setState` or `ref.read(...).state =` during build.
    - Controllers and listeners are disposed.
    - There is no decorative `repeat()`.
    - Every new screen has a test that pumps 5 seconds after settle and asserts `!tester.binding.hasScheduledFrame` and no pending timers.
    - The auth listener rules stay: `_eventsHandled` + `.skip()`, `_resolvedFor`, `_installingSelf`.

### 5.6 Network and screen states

17. **Offline and slow network.**
    - Every read goes through `guard()` with its 12-second deadline and maps into the `AppFailure` taxonomy, with a retry.
    - Writes disable their button while pending, show a specific progress line, and reuse the request id on retry.
    - No optimistic updates for money, status or access changes.
    - Pull-to-refresh uses `settleRefresh`.
    - `PagedNotifier` returns loadMore failures inline.
18. **Every screen and block has designed states, each with a widget test:**
    - loading (a skeleton shaped like the content);
    - empty, either first-run (art plus the next action) or no-match (a glyph);
    - error (an `errorGuidance` sentence plus Try again);
    - read-only (billing words);
    - not permitted ("Ask your owner for access").

### 5.7 Platform, privacy, storage, compatibility

19. **Platform rules.**
    - No new Android permission. `release.sh` checks the merged manifest for exactly ten permissions and no AD_ID.
    - No analytics, ads, crash-reporting or telemetry SDKs.
    - No `url_launcher`, web view or custom tabs.
    - Every new package is pinned exactly, checked against `docs/dependency-policy.md`, and its merged-manifest impact is recorded in the PR.
20. **Privacy.**
    - Collect the minimum.
    - Each new table has a retention rule and an erasure rule (Appendix B).
    - `fee_payments`, the new ledger tables and `legal_acceptances` are never deleted by retention.
    - Storage stays private: all uploads and signed URLs go through Edge Functions, content is sniffed, sizes are capped, TTLs are short, and erasure goes through `app.enqueue_storage_erasure`.
    - Push bodies never carry codes, amounts beyond the rupee figure, or third-party details.
21. **Legal order.** The `legal_versions` row goes live before the website push and before any build carrying the new `kLegalVersion`. Parity is tested against `lib/legal-config.ts`.
22. **Old-client compatibility.**
    - Changes are additive. `RETURNS TABLE` columns are appended last (drop and create in the same transaction with grants restated).
    - Enum growth is tolerated by the old clients' `tryParse`.
    - New notification types and links that old clients do not know are ignored.

### 5.8 Migrations and accessibility

23. **Migration discipline.**
    - Redefinitions are copied from live `pg_get_functiondef`. Each has a `$guard$` md5 check and a `$verify$` block (privileges, `prosecdef`, `proconfig`, triggers enabled).
    - `.down.sql` restores the exact live text. `.test.sql` runs in `begin ... rollback` and ends with `ALL <X> TESTS PASSED`.
    - Each phase's schema-sync owner updates `db/schema.sql`.
    - **Applying to live always needs the owner's explicit go-ahead.**
24. **Accessibility.**
    - Contrast pairs are asserted in `theme_contrast_test`.
    - Hit targets are 48dp or more. Status is never conveyed by colour alone.
    - Semantics labels are on every control, and art is excluded.
    - Reduce motion means no movement.
    - Layouts hold at 320dp and 2.0x text in tests.
25. **Performance.**
    - Indexes lead with `hostel_id`.
    - RPCs are bounded (limits, at most 24 months).
    - One RPC per block, with no N+1 loops.
    - Images decode with `cacheWidth`. Nav icons are precached.
    - The inbox stays under 150ms at 10,000 residents.

---

## 6. Decisions for the owner, owner actions, deferred features

### 6.1 Decisions only the owner can make (kept to the minimum)

| # | Decision | Why it is needed | Default if not answered |
|---|---|---|---|
| D1 | **Owner desk actions.** Should owners be able to add tenants, record payments, add charges and confirm complaints in the app? | Today the owner UI is read-only by design for residents, payments and complaints. RentOk owners do everything. The server already allows owners through `wd_*` (`has_role_in(h,'warden','owner')`), so this is a product switch, not a security change. | Owners stay read-only. Owner quick actions are Send notice, Assign task, Staff, Property settings. UPI claim confirmation (D) stays owner-only either way, because the money lands in the owner's bank. |
| D2 | **Paid services.** Pay for any of the following? An SMS OTP provider with DLT registration (phone OTP sign-in, cash OTP, parent approvals); the WhatsApp Business API (automatic WhatsApp reminders and OTP); transactional email (scheduled report emails, demo confirmations); e-KYC or e-stamp APIs. Also provide live Razorpay keys and payout accounts so card and UPI checkout goes live. | Each costs money and adds a data recipient, so each needs a legal bump. | None. Every feature that needs one is deferred. In-app notices and the share sheet replace messages. UPI to the owner with UTR (Phase D) works without any of them. |
| D3 | **Plan for an approved self-signed-up owner.** Trial length and price (for example 30 days at ₹0, then Super Admin renews by hand). | `sa_decide_hostel_application` creates the first subscription. | The approve sheet pre-fills start today, end today + 30 days, amount ₹0. Super Admin can change them per application. |
| D4 | **Rent agreement template text and wording.** Will you supply a lawyer-reviewed template, or approve a basic default? Do you accept the statement "Signed in Apnivaas. This is not stamp paper and not an Aadhaar eSign"? | Template content is a legal matter. A drawn signature is a signed acknowledgement, not a registered or stamped agreement. | Phase F ships the agreement feature with no platform default template; owners write their own. The statement is shown. |
| D5 | **Owner-private "do not re-admit" flags.** Approve them with a 24-month expiry, owner-scoped only and never shared across owners, or drop them? | This is data about a person, kept after their erasure (pseudonymised), with defamation and DPDP risk. | Built as specified in F, but switched off (`flags_enabled` false) until you say yes. |
| D6 | **"PGs near me" and the marketplace.** Keep deferred, or drop? | It needs a location permission (breaking the ten-permission rule), a Maps API, and public listing moderation. The seeker persona was removed in 1.3.0. | Deferred. |
| D7 | **Languages.** Which Indian languages first, and who translates? | Needs native-speaker translation and i18n plumbing. | English only. |

### 6.2 Owner actions (not decisions; each blocks only its own step)

- The go-ahead for every live migration apply, every Edge Function deploy that changes behaviour, and every Play upload.
- Set the `FCM_SERVICE_ACCOUNT` function secret if it is not already set. `push-send` is a no-op without it, so reminders, approvals and late-fine notices would be in-app only.
- For 1.3.0 on iOS: Sign in with Apple, because Google sign-in is offered (App Store 4.8). That is iOS-only and outside this Android plan.
- The Codemagic integration rename noted in the project memory, for iOS builds.

### 6.3 Deferred features and why

| Feature | Why deferred or not built |
|---|---|
| Language picker and translations | i18n plumbing plus professional translations; the tests are still copy-coupled (D7) |
| Phone OTP sign-in, WhatsApp OTP, cash-confirmation OTP, phone-change OTP | Paid SMS or WhatsApp provider with DLT registration (D2) |
| Truecaller one-tap | Partner SDK and a new data source |
| Sign in with Apple | Needed only when iOS ships |
| Map pin, "use my location", PGs near me, marketplace, public property website, tenant self-booking and web check-in | Location permission, paid Maps API, moderation (D6) |
| Server-ordered home banners, stories and campaign sheets | Remote-config surface with little value now; Super-Admin-authored image and text cards later |
| Voice search, voice notes, natural-language assistant | RECORD_AUDIO permission; an LLM or speech vendor gets operator data |
| Due packages (recurring bundles), credit auto-adjust, discounts | After the charges ledger proves itself |
| CSV import of charges or tenants | A document-picker package's merged-manifest impact must be verified first; website import is an option |
| Cashless deposit, virtual accounts, autopay and eNACH, wallet, early payout, settlement self-service, business verification | Regulated or paid partners, payment-aggregator licence, KYC |
| Convenience-fee pass-through | Surcharge rules for UPI (NPCI and RBI) |
| GST invoices | GSTIN data, invoice numbering compliance, legal review |
| Rent cycles other than calendar months (daily, half-yearly, joining-date anniversaries) | `period_month 'YYYY-MM'` runs through the ledger, Razorpay and reminders |
| e-KYC API, staff Aadhaar verification, e-stamp | Paid APIs and Aadhaar data (D2) |
| Parent approvals and summaries, and other messages to guardians | Parents have no app; SMS or WhatsApp needed (D2) |
| Camera QR scanning (gate, meals) | A scanner SDK (ML Kit) brings Google telemetry, which needs a Data safety review. Codes are typed instead. |
| Smart self-attendance (Wi-Fi, GPS, face) | New permissions plus biometric data |
| Proof-of-visit selfies | New camera purpose plus staff images, for little value |
| Assign wardens to floors, Wi-Fi mapping | Low value now; Wi-Fi needs a permission |
| Copy floor layout, room photos, publish to listing | Low value now; photos wait for the listing decision |
| Change property (move a resident across PGs with dues) | Moving dues across PGs; later |
| Survey builder, tenant reward coins | Survey builder later; coins are money-like value needing terms |
| In-app subscription purchase, KYC and stamp credits, add-on services | A platform Razorpay account plus GST invoicing; partner services |
| Paid-plan promo overlay, multiple accounts per phone | No freemium tier; one login is one role by design |
| Scheduled report emails | A transactional email provider (D2) |

---

## Appendix A: Forest & Cream design tokens and component specs

**Sources:**
- the canvas boards (Main, SignIn, RolePicker, BookDemo, OwnerHome, IconSet);
- the clay PNGs in `design-3d/icons-v3`;
- the current `lib/core/theme/*` and `lib/shared/*`.

Every ratio below is a WCAG 2.1 contrast ratio, computed with alpha fills composited first. Text needs 4.5:1; controls, borders and meaningful graphics need 3:1.

### A.1 Brand palette

| Name | Hex | Use |
|---|---|---|
| Forest | `#174E43` | Primary: filled button, links, focus, selected, hero tile, middle header stop |
| Forest deep | `#10392F` | Top header stop |
| Forest high | `#1F6150` | Bottom (lightest) header stop. Every header ink is measured on it. |
| Forest pressed | `#0F3A31` | Pressed filled button (white 12.58) |
| Forest track | `#2D6A5A` | Progress track inside the hero tile |
| Leaf | `#3F7F68` | Graphics. Text only on card or white (4.65 / 4.72); never on the ground (4.23). |
| Sage | `#7A9684` | Decoration only (3.17) |
| Mist | `#DCE8DF` | Tonal tiles, nav indicator, persona art panel, tonal button |
| Cream ground | `#F6F2EA` | Page ground |
| Cream card | `#FFFDF9` | Cards, sheets, nav bar, input fill |
| Gold | `#E2AE4A` | Fill or graphic on forest or dark only: unread dot (4.71 on forest), progress fill (3.13 on track). 1.99 on cream, so never on cream. Ink on gold 7.30. |
| Star core / halo | `#F6DFA0` / `#FFF6D8` | Header stars |
| Ink | `#1C2B26` | Primary text |
| Muted | `#55655E` | Secondary text |

### A.2 Light scheme

`colorScheme.surface` is the **card**; `scaffoldBackgroundColor` is the ground.

| Role | Hex | Material slot and measurements |
|---|---|---|
| ground | `#F6F2EA` | scaffoldBackgroundColor, surfaceDim (card on ground 1.10, so cards get a hairline) |
| card | `#FFFDF9` | surface, surfaceContainerLowest, surfaceContainerLow |
| well | `#EEF4EF` | surfaceContainer (quick-action well) |
| chipNeutral | `#EAE3D6` | surfaceContainerHighest |
| selected | `#F2F8F3` | extension `selectedSurface` |
| white | `#FFFFFF` | surfaceBright (Google button only) |
| primary | `#174E43` | on ground 8.52, card 9.36, well 8.53, mist 7.54, chip 7.46, white 9.51 |
| onPrimary | `#FFFFFF` | 9.51 |
| primaryContainer / onPrimaryContainer | `#DCE8DF` / `#174E43` | 7.54 (ink 11.70, muted 4.88) |
| secondary | `#3F7F68` | white on it 4.72 |
| secondaryContainer | `#EEF4EF` | ink 13.23 |
| tertiary / onTertiary | `#E2AE4A` / `#1C2B26` | 7.30 (fills only) |
| tertiaryContainer | gradient `#FFF5DF` to `#F8E3B6` | onTertiaryContainer `#3D2F0E` 10.34; body `#5C4A1E` 6.79 |
| onSurface (ink) | `#1C2B26` | ground 13.22, card 14.53, mist 11.70, chip 11.57 |
| inkStrong | `#3D4A44` | ground 8.32, card 9.14, chip 7.28, mist 7.36 |
| onSurfaceVariant (muted) | `#55655E` | ground 5.52, card 6.06, mist 4.88, chip 4.83 (worst) |
| mistSub | `#3F5C52` | on mist 5.81 |
| placeholder | `#66756E` | 4.77 on the field fill |
| outline | `#8F8679` | card 3.53, ground 3.21 |
| outlineVariant (card edge) | `#ECE4D8` | decorative |
| divider | `#EFE8DC` | decorative |
| barEdge / progress track | `#E6DED2` | Forest fill on it 7.13 |
| ruleOnGround | `#E2DACD` | decorative |
| error / onError | `#B3261E` / `#FFFFFF` | 6.54 |
| errorContainer / onErrorContainer | `#F7E8E3` / `#B3261E` | 5.01 |
| inverseSurface / onInverseSurface | `#1C2B26` / `#F3EFE6` | 12.86 |
| inversePrimary | `#86C9A9` | 7.69 on ink |
| scrim | `0x7A10392F` | |

Overlays: Forest 8% (`0x14174E43`, which composites to `#ECEFEA` on card) and Forest 12% (`0x1F174E43`, which composites to `#E3E8E3`).

**Header inks**, the same in both themes. The worst case is the lightest stop, `#1F6150`:

| Ink | Hex | Ratio |
|---|---|---|
| Title | `#FFFFFF` | 7.28 |
| Greeting | `#BFE0CC` | 5.11 |
| Sub / meta | `#CFE0D4` | 5.29 |
| Unread dot | `#E2AE4A` | 3.60 |

Header search field:
- fill is white at 12%, which composites to `#3A7465`; white text on it measures 5.43;
- placeholder `#E6F0EA` measures 4.66;
- borders (white at 22% and 24%) are decorative;
- the search glyph measures 5.43 and the bell glyph 5.96 on its 8% fill.

### A.3 Dark scheme

Built and tested, but pinned off. The header gradient, the hero tile and Gold are identical to light.

| Role | Hex | Measured |
|---|---|---|
| ground | `#0D1613` | |
| card | `#15221D` | 1.12 vs ground, so cards carry a hairline |
| raised (fields, sheets) | `#1B2B25` | |
| bright (skeleton, pressed) | `#22352E` | |
| well | `#1F302A` | |
| mist | `#1D3A31` | |
| chipNeutral | `#26342F` | |
| selected | `#1A3029` | |
| text | `#F3EFE6` | worst 10.75 on mist |
| secondary | `#B6C4BC` | worst 6.82 |
| muted | `#93A59C` | worst 4.76 |
| placeholder | `#8A9C93` | 5.11 |
| primary | `#86C9A9` | worst 6.43; onPrimary `#0D1613` 9.59 |
| filled button | `#DCE8DF` with label `#174E43` | 7.54 |
| mistText | `#CFE6D9` | 9.39 |
| outline | `#6E837A` | card 4.06, raised 3.66, ground 4.55 |
| outlineVariant / divider | `#2A3B34` | decorative |
| gold text | `#E2AE4A` | 8.12 on card |
| banner | `#2E2614` to `#3A2F15` | title `#F6DFA0` 10.00, body `#E6D4AA` 8.99 |
| error / onError | `#F08C82` / `#0D1613` | 7.69 |
| snackbar | `#F3EFE6` with ink text | 12.86 |
| scrim | `0x99000000` | |

### A.4 Status colours

Shapes use the canonical colour; text uses the resolved ink.

| Meaning | Light ink | Worst plain / chip | Dark ink | Worst plain / chip | Canonical graphic |
|---|---|---|---|---|---|
| success (paid, resolved, occupied) | `#256B45` | 5.76 / 5.03 | `#6FCB98` | 7.52 / 6.13 | `#3C8A5C` |
| warning (due, pending, expiring) | `#8A5A00` | 5.31 / 4.65 | `#E9B85C` | 8.09 / 6.57 | `#986A10` |
| error (overdue, failed) | `#B3261E` | 5.85 / 5.01 | `#F08C82` | 6.19 / 5.24 | `#C8443B` |
| info (refund, new) | `#2C5D8A` | 6.19 / 5.36 | `#8DB7E6` | 7.08 / 5.83 | `#3F76AD` |
| neutral (draft, sample) | `#55655E` on `#EAE3D6` | 4.83 | `#B6C4BC` on `#26342F` | 7.19 | n/a |

- Chip fill is the ink at 10% over the surface beneath, made opaque. Chips have no border.
  - Light fills on card: success `#E9EEE7`, warning `#F3EDE0`, error `#F7E8E3`, info `#EAEDEE`.
  - Dark fills on card: `#1E3329`, `#2A3123`, `#2B2D27`, `#213131`.
- A status always carries a word, and never sits on a surface tinted with its own tone.
- The domain hues are retired: violet `#8566BA`, teal `#35817E`, saffron `#AB6528`.

### A.5 Typography

Outfit (600, 700) is for headings and figures, with `fontFamilyFallback: ['Manrope']` and `leadingDistribution: even`. Manrope (400–700) is for everything you read. Sentence case. Minimum 11.

| Slot | Family | Size / line | Weight | Tracking | Job |
|---|---|---|---|---|---|
| displayLarge = headlineLarge | Outfit | 28/32 | 700 | −0.2 | The one hero figure |
| displayMedium | Outfit | 28/32 | 600 | 0 | Stepper or onboarding H1 |
| displaySmall | Outfit | 22/28 | 600 | 0 | Screen title |
| headlineMedium | Outfit | 22/28 | 700 | 0 | Stat value |
| titleLarge | Outfit | 20/26 | 600 | 0 | Page section heading |
| headlineSmall | Outfit | 18/24 | 600 | 0 | Card heading |
| titleMedium | Manrope | 14/20 | 700 | 0 | List row title |
| titleSmall | Manrope | 13/18 | 700 | 0 | Row figure (tabular), small button, field label |
| bodyLarge | Manrope | 15/22 | 400 | 0 | Reading text |
| bodyMedium | Manrope | 13/18 | 400 | 0 | Supporting text |
| bodySmall | Manrope | 12/16 | 400 | 0 | Meta, timestamps |
| labelLarge | Manrope | 15/20 | 700 | 0 | Outlined and text buttons |
| labelMedium | Manrope | 12/16 | 700 | 0 | Tile and nav labels, chips |
| labelSmall | Manrope | 11/14 | 700 | +0.2 | Floating field label |

`ApnivaasTextRoles`:
- `cta`: Outfit 17/22 600
- `tileTitle`: Outfit 17/22 600
- `heroHeadline`: Outfit 24/28 600
- `dateNumeral`: Outfit 19/22 600
- `fieldValue`: Manrope 15/22 500
- `formSection`: Outfit 15/18 600

Refreshing or columnar figures use Manrope 700 with `FontFeature.tabularFigures()`.

### A.6 Spacing

- Scale: hair 2, xxs 4, tight 6, xs 8, sm 12, md 16, lg 20, xl 24, xxl 32, xxxl 40, huge 48.
- Gutter: 16 on dashboards, 20 on auth, forms and steppers.
- Section gap 16; header to content 10–12.
- Off-grid canvas insets (14, 18, 22) are named geometry constants, never literals.
- Hit targets 48dp or more.

### A.7 Radii

control 14, button 16, buttonLarge 18, well 22, card 24, hero 28 (sheet top too), header 30, pill 999.

### A.8 Shadows (no blur filters)

| Token | Light | Dark | Use |
|---|---|---|---|
| e0 | none | none | Default card |
| e1 | `0x29174E43`, blur 20, offset (0,8) | `0x73000000`, blur 20, (0,8) | Selected persona, dragged item |
| e2 | `0x0F174E43`, blur 18, (0,−6) | `0x66000000`, blur 18, (0,−6) | Tab bar |
| e3 | `[0x2E10392F blur 32 (0,−8), 0x0F10392F blur 4 (0,−1)]` | `0x99000000`, blur 32, (0,−8) | Sheets, dialogs |

Focus ring: 2px primary at a 2dp offset (9.36 light, 7.71 dark).

### A.9 Motion and breakpoints

- Durations: press 100ms easeOut (scale 0.97; icon wells 0.94); release 150ms easeOutCubic; fast 150; base 240; slow 340; exit 200 easeInCubic.
- Curves: enter easeOutCubic; move easeInOutCubic; emphasis `Cubic(0.34, 1.36, 0.64, 1.0)`, only for the nav indicator and persona selection.
- Stagger 40ms, capped at 8 items.
- Skeleton pulse: opacity 1.0 to 0.55 over 1200ms.
- `readMessage` 5s.
- Haptics: `selectionClick` on a tab or choice; `lightImpact` on a confirmed payment.
- Reduce motion: the final state on the first frame. No decorative `repeat()`. The header is static.
- Breakpoints: 360 / 600 / 768; `maxContentWidth` 720. Layouts hold at 320.

### A.10 Components

**ApnivaasHeader**
- Full bleed, bottom corners r30, gradient `[#10392F, #174E43, #1F6150]`, stops 0 / .55 / 1, `GradientRotation(-pi/9)`.
- Padding: status inset + 18 at the top, 16 at the sides, 22 at the bottom.
- Leading: avatar disc 50 (`#FFFDF9`, 3px white@22% ring, brand mark 32x24 or initials), then greeting Manrope 12/16 w600 `#BFE0CC`, then the PG name Outfit 22/28 w600 white with an 18dp chevron that opens the switcher.
- Trailing: a 44 bell circle (white@8% fill, white@24% border, glyph 21) with a 9dp gold dot ringed 2px `#174E43`; hit area 48.
- Stars: one painter at a 390x170 reference size. x scales with width; y stays in dp.
  - Halos at (322,30), (268,72) and (360,104), plus tiny cores per the canvas.
  - Stars stay in the trailing half and at the edges, never behind text.
- Light status-bar icons.
- Variants: dashboard (with HeaderSearchField); sub-page (back 44 plus title); sign-in hero card (r28, min height 196, owner art 184).
- No fixed height. Below 360dp the avatar is 44.

**HeaderSearchField**
- Min height 48, r14, fill white@12%, border white@22%.
- Glyph 19 white; text Manrope 15/22 w500 white; placeholder `#E6F0EA`; gold cursor.
- A tap pushes the search screen.

**Stat tiles**
- StatCarousel: horizontal, gap 12, bleeding to the edges.
- HeroStatTile:
  - width 214 × clamp(scale, 1, 1.4), min height 150, r24, Forest background;
  - ClayIcon 78; label 12/16 w600 `#CFE0D4`; figure Outfit 28/32 w700 white in `FittedBox`; caption;
  - progress bar 7 high, track `#2D6A5A`, Gold fill, with the percentage also in text;
  - one semantics node.
- StatTile: 156 wide, card with a 1px `#ECE4D8` edge, ClayIcon 56, figure Outfit 22/28 w700, label 12/16 muted.
- LinkTile: Mist, title Outfit 17/22 w600 Forest, sub `#3F5C52`.
- At 1.6x or more under 400dp the carousel becomes a 2-column Wrap.

**QuickActionGrid**
- Card r24, padding 14 by 10. Header Outfit 18/24 with "View all" (Manrope 13/18 w700 Forest).
- Tile: well 64 r22 `#EEF4EF` with ClayIcon 54, then a label Manrope 12/16 w700 (2 lines, or 3 at 1.5x and above).
- Columns: 4, 3 or 2 by scale; 3 when the width is under 300.
- Press: scale 0.94, fill `#E3E8E3`, haptic.

**ListGroup and ListRow**
- Card r24, padding 4 by 14, dividers `#EFE8DC`.
- Row: min height 70; leading ClayIcon 46 or a Mist avatar; title 14/20 w700; subtitle 12/16 muted.
- Trailing: a PillButton, a chevron, or an amount with a StatusChip. It wraps below the text under 280dp.

**SectionHeader**: Outfit 20/26 w600 with `Semantics(header)`. In a card: 18/24. Form sections: 15/18.

**StatusChip**
- r999, min height 24, padding 10 by 3, Manrope 12/16 w700, optional 6dp dot.
- Count badge: min 18, `#B3261E`, white 11/14 w700.
- Unread dot: 9dp gold, only on forest or dark surfaces.

**Buttons**
- Primary: 52 high, r16, Forest with white Outfit 17/22 w600; pressed `#0F3A31` at scale 0.98; disabled `#E6DED2` / `#8A958F`; loading spinner 20.
- LargeCta: 56 high, r18. Dynamic labels get 2 lines at 1.3x and above.
- Secondary: 1.5px Forest outline.
- Pill: 36 visual, 48 hit, 1.5px Forest, Manrope 13/18 w700.
- Tonal: Mist with Forest.
- TextLink: Manrope 15/20 w600 Forest, min height 48.
- IconButton: 44 visual, 48 hit.
- Google: unchanged (white, `#747775` stroke, `#1F1F1F` 14/20 w500), height 50.
- Dark: the filled button is Mist with a Forest label.

**Inputs**
- Label 13/18 w700 `#3D4A44`, gap 6.
- Field: min 52, padding 14 by 15, r14, fill `#FFFDF9`, border 1.5px `#8F8679`; focus 2px Forest; error 2px `#B3261E` plus a helper line with a glyph.
- Value Manrope 15/22 w500. Placeholder `#66756E`.
- Floating-label variant: labelSmall inside.
- Phone keyboard with a +91 prefix; email keyboard.

**ChoiceChipGrid**
- Day chip: min 60. Time and bed chips: min 40. r14.
- Unselected: card with a 1.5px `#8F8679` border. Selected: Forest with white.
- Columns come from a minimum chip width × scale.
- Radio-group semantics.

**Sheet** (`showApnivaasSheet`)
- Top r28, card fill, e3, barrier `#10392F` at 48%.
- Grip 36x4 `#8F8679`, 10dp from the top.
- Padding 20, title Outfit 20/26, body scrolls up to 90% of the screen, footer Primary.
- Enter 340ms, exit 200ms.

**EmptyState**
- Max width 300, 160dp art (a ClayIcon 96 on a 136 Mist disc until clay scenes exist).
- Title Outfit 18/24, body 13/18 muted, one action.
- Variants: first run, no match (a glyph only), error, offline. Compact in-card version too.

**Skeleton**
- Shapes mirror the content (hero 214 / tile 156 × 150, list row 70, well 64).
- Blocks `#ECE6DB` on card, `#E9E2D5` on the ground; dark `#22352E`.
- One pulse controller per screen. Reduce motion: static at 0.8.
- One live region, e.g. "Loading overview".

**ApnivaasTabBar**
- Height 76 plus the safe inset; grows with scale, at most 88.
- Card fill, top border `#E6DED2`, e2.
- Indicator 58x40 r16 Mist.
- ClayIcon 36 when selected; 34 when unselected, greyscale at 0.85 opacity.
- Label 12/16, clamped to 1.3x: w700 Forest when selected, w600 `#55655E` when not.
- Selection: the indicator scales 0.8 to 1.0 on the emphasis curve over 240ms, the icon lifts 2dp, haptic.
- Semantics, e.g. "Payments, tab 4 of 5, 3 due".
- 5 tabs fit at 360dp (72dp each).

**PersonaCard**
- Min height 132, r24.
- Unselected: card with a 2px `#E6DED2` border. Selected: `#F2F8F3` with 2px Forest and e1.
- Radio 20 (`#8F8679`, or Forest when selected). Title Outfit 18/24. Description 13/18 muted.
- Art panel width clamp(0.32w, 96, 136) in Mist.
- At 1.6x and above the art moves above the text.
- Personas: Owner, Tenant, Staff (Staff routes to sign-in only).

**OnboardingStepper**
- Top bar 44: back button, "Step 2 of 4", spacer.
- Progress 6 high on track `#E6DED2`, Forest fill animated over 340ms.
- H1 Outfit 28/32, sub 15/21.
- Footer inside `SliverFillRemaining(hasScrollBody:false)`, holding a LargeCta and "I already have an account".

**ActionBanner**: r24, gold gradient, title `#3D2F0E`, body `#5C4A1E`, a filled Pill "Start", ClayIcon 96. At most one per screen.

**InfoBanner**: Mist r22, title Forest, ClayIcon 72.

**InfoNote**: r16 `#EAE3D6`, text `#3D4A44` 13/18.

**ClayIcon**
- `Image.asset` with `cacheWidth = size × dpr`, `filterQuality.medium`, `gaplessPlayback`.
- Sizes: 34/36 nav, 46 list, 54 quick action, 56 stat, 72 banner, 78 hero, 96 promo, 128 persona, 184 sign-in art.
- Never tinted (except the nav greyscale). Always seated on a surface; only role art sits directly on the gradient.

**AuthTopBar**: brand mark 34x25 plus "Apnivaas" Outfit 22/28 Forest, and the "Book a free demo" pill, which opens the in-app screen.

**Snackbar**: floating, r14, ink background, `#F3EFE6` text, `#86C9A9` action. 4 seconds; 5 for failures.

### A.11 Legacy token re-pointing (Phase A1)

| Legacy name | New value |
|---|---|
| background | `#F6F2EA` |
| surface | `#FFFDF9` |
| lightSheet | `#FFFDF9` |
| lightField | `#EAE3D6` |
| textPrimary | `#1C2B26` |
| textSecondary | `#3D4A44` |
| mutedInk | `#55655E` |
| lightPrimary / indigo / brandInk / roomsInk / brandDeep | `#174E43` |
| controlBorder | `#8F8679` |
| cardBorder | `#ECE4D8` |
| hairline | `#EFE8DC` |
| success / warning / error / info inks | `#256B45` / `#8A5A00` / `#B3261E` / `#2C5D8A` |
| canonical success / warning / error / info | `#3C8A5C` / `#986A10` / `#C8443B` / `#3F76AD` |

Domain tones (rooms, people, food, brand) re-point into brand and status. Radii move: control 12 to 14, card 16 to 24, sheet 20 to 28, surface 20 to 24.

### A.12 Icons

**Available** in `design-3d/icons-v3`: 256px RGBA, light from the top left.
- Money: money, collect-payment, receipt, expense, deposit, rent-reminder, late-fee, bank-transfer, invoice, discount.
- Documents and insight: reports, analytics, kyc, agreement, calendar, success, reviews.
- People: add-tenant, team, visitor, move-in, move-out, leave, attendance, announcement.
- Property and operations: rooms, beds, food, electricity, water, wifi, laundry, complaint, tasks, housekeeping, gate.
- Account: bell, settings, support, security, referral.
- Nav: nav-home, nav-money, nav-people, nav-property.
- Role art (320px): role-owner, role-tenant, role-manager, role-warden.
- **Never ship:** the `nav-*-off` files (runtime greyscale replaces them), role-seeker, role-owner-man, role-owner-mascot, any icon sheet, the mascot master, or icons-v2.

**Needed (new art)**:
- Account and navigation: profile, more, subscription, hostels, password-key, two-factor, sign-out, delete-account, privacy, settings variants as needed.
- Money: upi-qr, utr-reference, cash, refund.
- People and property: floor-plan, room-transfer, guardian, police-verification, documents.
- Utility: camera, share-export, search, filter, call, message, book-demo, offline, error.
- Empty-state scenes at 480px with alpha: no-tenants, no-payments, no-complaints, no-notices, no-search-results, offline, error, all-caught-up.
- Role art re-exported at 512–576px with alpha, from the source renders and not from `roles-clay-v3.png` (which has no alpha).

### A.13 Fonts and assets

- Six static TTFs (Outfit 600/700; Manrope 400/500/600/700) with `OFL.txt`, registered with `LicenseRegistry`. Estimated 0.4–0.6 MB; measure it.
- The working tree keeps the `google_fonts` package with runtime fetching off, which is the fallback option. Removing the package is optional.
- Verify ₹ (U+20B9) in `cmap`, the `tnum` feature, and distinct weight classes and glyph hashes, by reading bytes. Measured so far: Manrope has ₹ and `tnum`; Outfit has `tnum` but no ₹.
- Inter (1.51 MiB) is deleted unless needed as the ₹ fallback.
- The website uses `next/font/google`, which self-hosts at build time.
- Clay art as WebP with alpha: target 1.5 MB or less in total, versus about 4.1 MB as PNG.
- Decode with `cacheWidth` (otherwise the 45-icon View-all sheet costs about 11.5 MB decoded).
- No new permission, no network, no data collection. No legal change for assets.

---

## Appendix B: new tables, retention and erasure

| Table | Phase | Readers (RLS) | Writers | Retention | On resident erasure |
|---|---|---|---|---|---|
| hostel_applications | B | applicant, super admin | RPC | kept (business record) | n/a |
| tenant_join_codes | B | self | RPC | deleted on expiry | cascades with the user |
| student_link_requests | B | target user, warden/owner | RPC | pending expires after 14 days | cascades or deleted |
| demo_requests | B | super admin | Edge Function (service) | 180 days after the slot | n/a |
| hostel_settings | C | owner, staff, super admin; residents through an RPC | RPC | with the hostel | n/a |
| notification_prefs | C | self | RPC | with the user | cascades |
| daily_hostel_snapshots | C | owner, super admin | cron | 3 years | n/a (aggregates) |
| fee_payment_events | D | warden/owner, resident own | trigger | **never deleted** | notes nulled |
| charges | D | warden/owner, resident own | RPC, cron | **never deleted** | kept, keyed to the tombstone |
| charge_payments | D | warden/owner, resident own | RPC | **never deleted** | notes nulled |
| deposit_ledger | D | warden/owner, resident own | RPC | **never deleted** | notes nulled |
| bulk_operations | D | creator, owner | RPC | 1 year | n/a |
| meters, meter_readings | D | owner/warden; residents through an RPC | RPC | kept | the split jsonb keeps only the id |
| cash_handovers, petty_cash_advances | D | owner, staff own | RPC | kept | n/a |
| hostel_upi_accounts | D | owner | RPC | until replaced | n/a |
| upi_claims | D | owner, resident own | RPC | pending expires after 30 days; kept | UTR kept (financial), resident id nulled through the cascade rule |
| gates | E | owner/warden | RLS | kept | n/a |
| gate_passes, gate_events | E | owner/warden, resident own | RPC | 6 months | deleted |
| guest_stays | E | owner/warden, resident own | RPC | 2 months after to_date | deleted |
| attendance_marks | E | owner/warden, resident own | RPC | 12 months | deleted |
| meal_settings | E | anyone who can read the hostel | RPC | with the hostel | n/a |
| meal_confirmations, meal_codes, meal_servings | E | owner/warden, resident own (manager counts only) | RPC | 6 months | deleted |
| student_documents | F | owner/warden, resident own | Edge Function plus RPC | until erasure | rows deleted, files queued |
| agreement_templates | F | owner/warden; platform defaults | RPC | kept | n/a |
| agreements, agreement_signatures | F | owner/warden, resident own | RPC plus Edge Function | until erasure | deleted, PDFs and PNGs queued |
| checklist_templates, checklists | F | owner/warden, resident own | RPC | until erasure | deleted |
| move_outs | F | owner/warden | RPC | kept (tombstone id only) | kept, no personal fields |
| owner_tenant_flags | F | owner | RPC | 24 months | kept, pseudonymised (D5) |
| leads | F | owner/warden (manager with a capability) | RLS plus RPC | junk/lost 90 days; converted 30 days | n/a |
| bed_bookings | F | owner/warden | RPC | expires 3 days after the move-in date; kept | n/a |
| staff_duty_log | G | owner, staff own | RPC | 12 months | n/a |
| complaint_comments | G | owner/warden; resident sees non-internal | RPC | with the complaint (2 months) | deleted with the complaints |
| announcement_reads | G | self; owner and author through an RPC | RPC | with the announcement | cascades |
| report_schedules | H | owner | RPC | until deleted | n/a |
| stay_reviews | H | resident own; owner through an RPC | RPC | 2 years | deleted |
| referral_codes, referrals | H | owner own, super admin | RPC plus trigger | kept | n/a |
| support_tickets, support_messages | H | opener, super admin | RPC | 12 months after closing | n/a |

---

## Appendix C: new cron jobs

| Job | Schedule (UTC) | IST | Function | Phase |
|---|---|---|---|---|
| apnivaas-hostel-snapshots | `25 18 * * *` | 23:55 | `app.snapshot_hostels()` | C |
| apnivaas-late-fines | `50 3 * * *` | 09:20 | `app.apply_late_fines()` | D |
| apnivaas-expire-intents | `15 * * * *` | hourly | `public.rz_expire_stale_intents('2 hours')`, only after the F2 fix | D |
| apnivaas-leave-status | `40 18 * * *` | 00:10 | `app.sync_leave_status()` | E |
| apnivaas-complaint-escalation | `20 * * * *` | hourly | `app.escalate_complaints()` | G |
| apnivaas-report-schedules | `5 * * * *` | hourly | `app.dispatch_report_schedules()` | H |
| apnivaas-review-prompts | `30 4 * * *` | 10:00 | `app.prompt_stay_reviews()` | H |

Existing jobs stay: hostelpro-retention (08:45 IST), hostelpro-keepwarm, apnivaas-rent-reminders (09:00 IST) and apnivaas-drain-storage-erasures (09:10 IST).

Before relying on any job, confirm `cron.job` on live. The project notes say one doc lists only three live jobs. Every new job is created by its migration and removed by the `.down.sql`.

