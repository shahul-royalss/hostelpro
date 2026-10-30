# Round 4 spec (owner request, 2026-10-31)

Builds on rounds 2 and 3, which are live: docs/self-signup-api.md, docs/round3-api.md. The same rules apply:
- authorization lives on the server;
- every client value is attacker-controlled;
- no secrets go in the app;
- nothing opens a browser;
- the clay kit look is kept;
- comments stay short.

Usage budget: the whole round must finish under 30% of the weekly limit, so be economical.

**Left out of this round on purpose:** the YouPI pilot, and the security audit with its Dependabot fixes.

## R4.1 Warden sets each new tenant's monthly rent
- When the owner or a warden **accepts a join request**, the accept sheet asks for the tenant's **monthly rent (₹)**
  (required, 1–10,00,000) and an optional **due day of month** (1–28, default 5), and saves them on the roster row in the same
  server call. Extend `ow_decide_join_request` with optional params so old clients still work, or add a follow-up RPC. Prefer
  the single atomic call.
- **Warden home** gets a card, **"Set rent for N new residents"**, listing linked residents whose monthly rent is not set. It opens the
  rent editor. Dues are not generated for a resident until rent is set, so verify how dues and the fee ledger treat a
  null or zero fee, and make it consistent: no dues while rent is unset.
- The warden can **change** a resident's monthly rent and due day later from the resident sheet. "Monthly rent" exists in
  `features/warden/students/student_sheet.dart`. The change applies from the next unbilled month and never rewrites paid history.

## R4.2 Warden edits every tenant detail
- The warden, and the owner, can update every detail a tenant gives at sign-up: full name, phone, email shown, gender, date of
  birth, emergency contact name and phone, address, city, pincode, plus the roster fields they already edit.
- New RPC `wd_update_tenant_profile(...)`:
  - the caller is a warden or owner of the tenant's current hostel;
  - field validation copies `me_update_profile`;
  - it never changes the role, the hostel or the login email, so it cannot become a takeover vector;
  - audit and spend limit.
- UI: an **Edit details** sheet from the resident sheet, using the clay form parts.

## R4.3 UPI payments to the owner's own UPI ID — make every UPI app work
The owner's UPI ID is in More → UPI payments; it exists already. Make the tenant's payment as reliable as UPI allows:
- **Build the intent correctly.** `upi://pay?pa=<vpa>&pn=<payee name>&am=<amount with 2 decimals>&cu=INR&tn=<short note, at most 40 ASCII chars>`,
  every value URL-encoded.
  - Do NOT send `mc`, `tr`, `mode` or `orgid` for a personal UPI ID. They make PhonePe, Paytm and GPay decline P2P intents.
  - Validate the VPA (`^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$`).
- **Choose the app.** Show buttons for **PhonePe**, **Paytm**, **Google Pay** and **BHIM** where installed. Each uses a package-targeted intent
  (`com.phonepe.app`, `net.one97.paytm`, `com.google.android.apps.nbu.paisa.user`, `in.org.npci.upiapp`). Add a generic
  **Other UPI app** chooser, and a **Copy UPI ID** fallback so the tenant can pay from any app by hand. Use package visibility
  `<queries>` for those packages and the upi scheme in the manifest.
- **After returning**, read the intent's response string only as a *hint* (Status=SUCCESS / txnRef). Always ask for the **UTR**
  (12 digits), prefilled from the response if present, then file the payment claim. The owner or warden confirms it, as built in
  round 3. Never mark a payment paid on the device's word.
- **Owner guidance** in UPI settings, one short InfoNote: "For the smoothest payments, use a UPI ID from PhonePe for
  Business, Paytm for Business or BharatPe. Some apps limit payments to personal UPI IDs."
- Razorpay stays as it is.

## R4.4 Login must not show "Sign-in is temporarily unavailable" for a blip
- In `lib/core/auth/auth_endpoint.dart`, retry **once** automatically, after about 1 second, when the outcome is transient:
  a timeout, a relay or fetch failure, 408, or 5xx with no server message. Only then show the message. Never retry a 4xx.
- Raise the first-attempt timeout to 20 s, because cold starts on slow mobile data are slow.
- Tests cover the retry on 503 and the no-retry on 400.

## R4.5 Super Admin screens in the new design
Restyle every Super Admin screen in the clay kit, as the Phase A reskin did for the other roles:
- the dashboard;
- the hostels list and detail;
- the create owner and hostel wizard;
- owner account controls;
- security alerts;
- round 3's sign-ups and demos and deleted-accounts screens;
- SaShell on ClayNavBar.

Keep every behaviour and provider exactly as it is. Dense data uses clean cards or tables, not decoration.

## R4.6 Emails say Apnivaas, professionally
- The auth emails come from Supabase Auth and still say "Nivora". Write professional **Apnivaas** templates (subject + HTML,
  brand colours, a plain-text-friendly layout, no tracking) for every scenario:
  - Confirm signup
  - Invite user
  - Magic link
  - Change email address
  - Reset password
  - Reauthentication
- Save them as `docs/email-templates/<scenario>.html` plus `docs/email-templates/README.md`. The README has the exact subject lines and the
  dashboard steps: Supabase → Authentication → Emails → Templates, and SMTP settings → Sender name "Apnivaas".
  Use the GoTrue variables (`{{ .ConfirmationURL }}`, `{{ .Token }}`, `{{ .SiteURL }}`, `{{ .Email }}`, `{{ .NewEmail }}`) exactly.
- Also grep the repo, including the Edge Functions and the website, for any remaining user-visible "Nivora" in emails or
  notifications, and fix it.

## Done means
- One concise migration, `db/migrations/2026-10-31-round4.sql`, with `.down.sql` and `.test.sql`, passing on live inside a rolled-back transaction:
  `npx -y supabase db query --linked --project-ref nimxvgzscbanhtvgnjll --file <scratch>`, where the scratch file is the migration plus the test, ending in ROLLBACK.
  The parent applies it after the owner approves.
- A contract addendum in `docs/round4-api.md`.
- App: `flutter analyze` clean and the full suite green.
