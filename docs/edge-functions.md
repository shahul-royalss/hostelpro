# Edge Functions — deploy runbook

**No secret value appears in this file, or anywhere else in this repository.** Everything below
tells you which secret to set and how to set it; the values come from the Supabase and Razorpay
dashboards and go straight into Supabase's secret store. Nothing is committed.

---

## 1. Why these functions exist

The Flutter app has to create accounts: a Super Admin creates an owner, an owner creates a
manager or warden, a warden registers a student. Creating a login means calling
`auth.admin.createUser`, and that requires the **service-role key**, which bypasses Row Level
Security for the entire project.

An APK is a zip file. Anything compiled into it — `env.dart`, a `--dart-define`, a string
constant, a `.env` asset — is readable by anyone who downloads it. A service-role key inside an
APK is a *published* service-role key, and there is no way to un-publish it.

So the key never goes near the phone. It lives in Supabase's secret store, is injected into the
Edge Function process at runtime, and the phone holds nothing but an ordinary user session. The
phone asks; the server decides and acts. The only Supabase credential in the app is the **anon
key**, which is meant to be public, and the only Razorpay credential in the app is the
**key id** (`rzp_test_…` / `rzp_live_…`), which is also meant to be public.

This is also why there is no WebView and no browser hand-off anywhere in the flow. An Edge
Function is a server, not a browser. Every screen completes inside the app.

---

## 2. The functions

| Function | Caller must be | What it does | `verify_jwt` |
|---|---|---|---|
| `sa-create-owner` | `super_admin` | Creates an owner login + their hostel, subscription and room scaffold | **on** (default) |
| `owner-create-staff` | `owner` | Creates the manager or warden login for a hostel that owner owns | **on** (default) |
| `warden-register-student` | `warden` | Creates a student login, uploads photo + ID proof, writes the students row and assigns a bed | **on** (default) |
| `razorpay-order` | `student` | Opens a Razorpay order for the caller's own outstanding rent | **on** (default) |
| `razorpay-webhook` | Razorpay (no user) | Receives payment webhooks, signature-verified | **off** — see §5 |
| `email-verification` | any signed-in user | Reports whether the caller's address is proved — and records the proof when GoTrue says the confirmation link was opened | **on** (default) |

`email-verification` is the only one of these that is **not** on the critical path of anything.
It does not send mail: the app asks GoTrue for the confirmation link directly. If this function
is down, no link is lost and none stops working — see §7.4.

`verify_jwt` is a platform-level gate, and it is **not** the authorisation check. The anon key is
itself a valid project JWT and sails straight through it. Every function above re-derives who the
caller is by verifying the bearer token with GoTrue and then reading that user's row from
`public.users` — the role and the tenant come from the **database row**, never from a field in
the request body and never from the JWT's `app_metadata` (which the service role can write, and
which is therefore a mirror, not a fact).

---

## 3. One-time setup

Install and authenticate the CLI. The repo already has it as a dev dependency, so `npx` works
without a global install.

```bash
npx supabase --version          # 2.115.0 at the time of writing
npx supabase init               # ONLY if supabase/config.toml is missing — see below
npx supabase login              # opens a browser once, stores an access token locally
npx supabase link --project-ref <YOUR-PROJECT-REF>
```

**About `init`:** this repo currently has `supabase/functions/` but **no `supabase/config.toml`**,
and that file is how the CLI recognises the project root. Run `npx supabase init` once, from the
repo root, before the first deploy. Without `--force` it refuses to overwrite an existing
config, and it does not touch `supabase/functions/` — it only adds the config file. Commit the
generated `config.toml`; it holds no secrets.

If you would rather not link at all, every command below also accepts
`--project-ref <YOUR-PROJECT-REF>` instead.

`<YOUR-PROJECT-REF>` is the subdomain of your project URL: for
`https://abcdefghijkl.supabase.co` the ref is `abcdefghijkl`. It is also in the dashboard under
**Project Settings → General → Reference ID**.

> `login` and `link` require a Supabase access token. They are the product owner's to run — no
> automated agent should hold that token.

---

## 4. Set the secrets

### 4.1 The service-role key

Get it from **Dashboard → Project Settings → API keys → `service_role` → Reveal**. Treat it like
a root password: it bypasses RLS on every table in the project.

```bash
npx supabase secrets set NIVORA_SERVICE_ROLE_KEY=<paste-the-service_role-key-here>
```

**Why `NIVORA_` and not `SUPABASE_`:** the CLI rejects secret names beginning with `SUPABASE_` —
that prefix is reserved for the values the platform injects itself. `supabase/functions/_shared/supabase.ts`
therefore reads `NIVORA_SERVICE_ROLE_KEY` first and falls back to the platform-injected
`SUPABASE_SERVICE_ROLE_KEY`. Setting `NIVORA_SERVICE_ROLE_KEY` explicitly is what lets you pin or
rotate the key on your own schedule instead of depending on the platform default.

`SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected by the platform into every deployed function.
Do not set them by hand.

### 4.2 The Razorpay secrets (payments path)

```bash
npx supabase secrets set RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxxxx
npx supabase secrets set RAZORPAY_KEY_SECRET=<razorpay-key-secret>
npx supabase secrets set RAZORPAY_WEBHOOK_SECRET=<razorpay-webhook-secret>
```

`RAZORPAY_KEY_ID` is publishable and is also shipped in the app. `RAZORPAY_KEY_SECRET` and
`RAZORPAY_WEBHOOK_SECRET` must never leave the server, for the same reason as §4.1.

### 4.3 All at once, and how to check

```bash
# One command, several secrets:
npx supabase secrets set \
  NIVORA_SERVICE_ROLE_KEY=<service_role-key> \
  RAZORPAY_KEY_ID=rzp_test_xxxxxxxxxxxxxx \
  RAZORPAY_KEY_SECRET=<razorpay-key-secret> \
  RAZORPAY_WEBHOOK_SECRET=<razorpay-webhook-secret>

# Lists NAMES and digests only — never the values:
npx supabase secrets list
```

Prefer typing the command into a terminal over pasting it into a chat, a ticket, or a file.
Shell history keeps what you type: on bash, prefixing the command with a space keeps it out of
`~/.bash_history` when `HISTCONTROL=ignorespace` is set.

If you would rather use a file, `npx supabase secrets set --env-file ./supabase/.env` works, and
`.gitignore` already ignores `.env*` at any depth — but delete the file once the secrets are set.
A file is one `git add -f` away from being committed forever.

---

## 5. Deploy

```bash
npx supabase functions deploy sa-create-owner
npx supabase functions deploy owner-create-staff
npx supabase functions deploy warden-register-student
npx supabase functions deploy razorpay-order
npx supabase functions deploy razorpay-webhook --no-verify-jwt
```

`--no-verify-jwt` on the webhook only. Razorpay's servers do not hold a project JWT, so with the
gate on, every delivery would 401 before the function ran. That function authenticates its caller
by verifying Razorpay's HMAC signature instead — which is stronger than a shared bearer token,
because it also proves the *body* was not altered. Do not add that flag to any of the other four.

Secrets take effect on the next invocation; you do not have to redeploy after `secrets set`.
But if you deploy *before* setting the service-role key, the three account functions will return
`500 Something went wrong` and log
`No service-role key in the function environment`. Set the secret, then retry — no redeploy needed.

---

## 6. Verify it works

Nothing here needs a service-role key, so it is safe to run from a laptop.

```bash
# 1. Are they deployed?
npx supabase functions list

# 2. Do they refuse an anonymous caller? (must be 401, NOT 500)
curl -i -X POST "https://<PROJECT-REF>.supabase.co/functions/v1/sa-create-owner" \
  -H "Content-Type: application/json" -d '{}'

# 3. Do they refuse the anon key? (must also be 401 — the anon key is a valid JWT
#    but carries no user, and bearerToken() rejects it by identity)
curl -i -X POST "https://<PROJECT-REF>.supabase.co/functions/v1/sa-create-owner" \
  -H "Authorization: Bearer <ANON-KEY>" \
  -H "Content-Type: application/json" -d '{}'

# 4. Do they refuse the wrong role? Sign in as a warden, then:
curl -i -X POST "https://<PROJECT-REF>.supabase.co/functions/v1/sa-create-owner" \
  -H "Authorization: Bearer <WARDEN-ACCESS-TOKEN>" \
  -H "Content-Type: application/json" -d '{}'
# → 403, and an `authz.denied` row appears in public.audit_log.
```

Logs while you test from the app: **Dashboard → Edge Functions → `sa-create-owner` → Logs**.
CLI 2.115.0 has no `functions logs` subcommand (`npx supabase functions --help` lists only
`list`, `delete`, `download`, `deploy`, `new`, `serve`) — the dashboard is the way.

A 403 in step 4 with an `authz.denied` audit row is the check that actually matters. It proves
the role gate is reading the database and not the token.

---

## 7. Request and response contracts

Every function answers with the same envelope the web app's `ActionResult<T>` uses, so a Dart
client and a React client read identical JSON:

```jsonc
{ "ok": true,  "data": { }, "message": "Sunrise PG created" }
{ "ok": false, "error": "Enter a valid email address", "fieldErrors": { "owner.email": ["Enter a valid email address"] } }
```

From Flutter — `supabase_flutter` attaches the signed-in user's access token automatically:

```dart
final res = await Supabase.instance.client.functions.invoke(
  'sa-create-owner',
  body: { /* see below */ },
);
```

### `sa-create-owner`

```jsonc
// new owner
{
  "owner":        { "mode": "new", "name": "Asha Rao", "email": "asha@example.com", "phone": "9876500001" },
  "hostel":       { "name": "Sunrise PG", "floors": 3, "rooms": 30, "bedsPerRoom": 3, "address": "optional, ≤500 chars" },
  "subscription": { "startDate": "2026-09-01", "endDate": "2027-08-31", "amount": 24000, "notes": "optional" }
}
// second hostel for an owner who already exists — no login is created, so no credentials come back
{ "owner": { "mode": "existing", "ownerUserId": "<uuid>" }, "hostel": { }, "subscription": { } }
```

```jsonc
"data": {
  "hostelId": "<uuid>",
  "credentials": { "name": "Asha Rao", "loginId": "asha@example.com", "password": "Sage-7413-Kite" } // null in "existing" mode
}
```

### `owner-create-staff`

```jsonc
{ "role": "manager" | "warden", "fullName": "…", "email": "…", "phone": "optional", "hostelId": "optional uuid" }
```

`hostelId` may be omitted when the owner has one hostel (`users.hostel_id` is used). An owner
with several must send it — and whichever id arrives is checked against `hostels.owner_user_id`
before anything is created.

```jsonc
"data": { "userId": "<uuid>", "name": "…", "role": "Warden", "loginId": "…", "password": "Sage-7413-Kite" }
```

### `warden-register-student`

```jsonc
{
  "fullName": "…", "phone": "9876500042", "email": "optional — see below", "dateOfJoining": "2026-08-25",
  "guardianName": "…", "guardianPhone": "9876500043", "permanentAddress": "…",
  "idProofType": "Aadhaar" | "PAN" | "Passport" | "Driving licence" | "Voter ID" | "Other",
  "bedId": "<uuid>", "monthlyFee": 7500,
  "photoBase64": "optional, base64 or data: URL",
  "idProofBase64": "required, base64 or data: URL"
}
```

There is no `hostelId` field, deliberately. A warden belongs to one hostel and that is the one
used — for the login, the uploads and the rows.

Files travel as base64 inside the JSON body (3 MB per file after decoding; JPG, PNG, WEBP or
PDF). The real content type is sniffed from the leading bytes, so a `.jpg` that is actually an
HTML document is rejected rather than stored. Compress camera photos on the device first.

```jsonc
"data": {
  "studentId": "<uuid>",
  "roomId": "<uuid|null>",
  "credentials": { "name": "…", "loginId": "9876500042", "password": "Sage-7413-Kite" }
}
```

`loginId` is what the resident types on the sign-in screen, and **which of the two it is depends
on `email`**:

| `email` in the request | auth user's address | `loginId` returned | duplicate message on 409 |
|---|---|---|---|
| omitted / empty | `<phone>@student.hostelpro.local` | the phone number | "A student with this **phone number** already has an account." |
| present | that address, lowercased | that address | "A student with this **email address** already has an account." |

`email` is optional and stays optional: a hostel resident may genuinely not have one, which is
the reason the phone mapping exists. It is not a second way in — an account has exactly one
login id, because resolving both would need a phone→account lookup on an unauthenticated
endpoint, which is an account-enumeration oracle. Read `loginId` rather than deriving it; the
server is the only party that knows which box the login came from.

An address ending in `@student.hostelpro.local` is **rejected** (`fieldErrors.email`,
"Enter a real email address"). That namespace belongs to the phone mapping, and an address
inside it would claim the login id of whoever holds that number — permanently, because GoTrue
never releases a registered address.

`public.users` carries a UNIQUE index on `lower(email) WHERE email IS NOT NULL`, and it is
**global, not per hostel**. Two residents at two different hostels therefore cannot share one
address — which matches GoTrue's own one-account-per-address rule, so the two agree. Residents
with no email are unaffected: the index is partial.

To give an already-registered, phone-mapped resident a real email login, see
`db/migrations/2026-08-31-student-email-login.sql` → `app.attach_student_login_email()`. It
renames the login in auth.users, auth.identities, public.users and public.students in one
transaction; the password and any live session survive, and the phone number stops working as a
login.

### `email-verification`

```jsonc
{ "action": "status" }
```

```jsonc
"data": { "email": "…", "verified": true, "verifiedAt": "2026-09-01T…Z", "required": false }
```

One action, and it is a **question that sometimes writes**. For a caller who has already proved
their address it is a plain read. For one who has not, it asks
`public.email_link_proof(<caller>)` whether GoTrue has recorded the confirmation link being
opened, and stamps `public.users.email_verified_at` if it has.

That is why the app calls it on every return to the foreground: the user opens the link in a
browser or a mail app, and nothing else tells this system when that happened.

**Why there is a server here at all, when the mail is sent by GoTrue.** Only the service role
may write `email_verified_at` — `app.users_update_guard` raises `42501` for every other writer,
including the account holder and the super admin. Something that has *seen* GoTrue accept the
link has to be the thing that writes it, and that cannot be the phone.

**What breaks if it is down:** the banner stays on screen for a little longer. The click is
already recorded in GoTrue's own tables (`auth.flow_state.auth_code_issued_at` and
`auth.audit_log_entries`), so the next `status` call picks it up. Contrast with the flow this
replaced, where the same function *sent* the code and a timeout meant no code at all — that is
the whole reason for the change. Full argument:
`db/migrations/2026-09-02-email-link-proof-pkce.sql`, which also records why the first attempt
read `auth.mfa_amr_claims` and why that table can never gain a row for a PKCE link click.

#### What the project owner must have set, or no link ever arrives

1. **Authentication → Emails → Magic Link template must contain `{{ .ConfirmationURL }}`.**
   That is Supabase's stock template, so an untouched project is already correct. It is listed
   because the previous, code-based flow asked for `{{ .Token }}` in that template; a template
   edited to show only the six digits now sends mail with nothing to click.
2. **Authentication → Attack Protection → CAPTCHA must be OFF** (or the app must supply a
   token, which it does not). CAPTCHA refuses `/auth/v1/otp` outright. Checked live on
   2026-09-01 and it is currently **off** — `POST /auth/v1/otp` reaches user lookup and answers
   `otp_disabled` rather than `captcha_failed`. If it is ever switched on, the app says so in
   those words rather than blaming the user's connection.
3. **A working mail sender.** Supabase's built-in SMTP is rate-limited to a handful of messages
   an hour and is not for production; a real SMTP provider belongs in
   Authentication → Emails → SMTP Settings before this ships to a hostel.
4. **Authentication → URL Configuration → Redirect URLs — ONE ENTRY IS STILL MISSING.** The app
   asks for `app.nivora.mobile://verify-email`, a custom scheme whose intent filter opens
   Nivora, so that the link signs the person in and that sign-in *is* the proof. GoTrue accepts
   a `redirect_to` only if it is on the allow-list or shares a hostname with the Site URL, and a
   custom scheme shares a hostname with nothing — so it needs the allow-list entry.

   Site URL itself is **already correct** (`https://hostelpro-three.vercel.app`); earlier
   revisions of this file said `http://localhost:3000`, which the owner has since fixed. It does
   not need to change again.

   Measured 2026-09-01 by asking `/auth/v1/verify` to redirect a dead token and reading the
   `Location` header: `app.nivora.mobile://verify-email` and a deliberately bogus URL are both
   **silently substituted** with the Site URL, while a same-host URL is honoured. GoTrue never
   refuses an unlisted redirect out loud, so there is no error for the app to catch and no way
   for this server to detect the condition.

   It costs the sign-in-by-link, **never the verification** — GoTrue matches the token at
   `/auth/v1/verify` before it redirects, and `public.email_link_proof()` reads that back from
   GoTrue's own tables afterwards. The exact string to paste, and every fallback, are in
   `docs/email-verification.md` §0 and §4.

---

## 8. The temporary password

Every one of these endpoints returns a generated password **once**, in the response body, and
never writes it anywhere. It is not in a table, not in a log line, not in the audit row —
`public.audit_event()` strips password-ish keys out of `meta` as a second line of defence — and
every response carries `Cache-Control: no-store` so nothing on the way back to the phone keeps a
copy.

If the password is lost, there is nowhere to look it up. Issue a new one instead (the web app's
"reset password" action on the same account). Every new account also carries
`must_change_password = true`, so the person is forced to set their own password at first sign-in
and the temporary one stops working.

---

## 9. When a rollback fails — the one message you must not ignore

Creating an account touches two systems that cannot share a transaction: the login lives in
GoTrue, the profile and hostel rows live in Postgres. If the second half fails, the first half is
deleted again.

If **that deletion also fails**, the response says so, explicitly:

```jsonc
{
  "ok": false,
  "error": "Could not create the hostel. The half-created login could NOT be removed automatically — delete auth user 3f2a…  in the Supabase dashboard before retrying, or the email address stays taken.",
  "rollback": { "failed": true, "orphanedAuthUserId": "3f2a…", "detail": "…" }
}
```

The web app swallows this case; these functions report it, on purpose. What is left behind is an
auth user with no `public.users` row: it cannot sign in usefully, nobody is told it exists, and it
holds its email address — or, for a student, their **phone number** — hostage, because GoTrue will
refuse to register that address again. Retrying then fails with "already exists" for a reason
nobody can see.

**What to do:** Dashboard → **Authentication → Users**, search the id from `orphanedAuthUserId`,
delete that user, then retry the operation. A `[nivora] ROLLBACK FAILED for auth user <id>` line is
in the function logs too.

---

## 10. Rotating the service-role key

If the key is ever exposed — pasted into a chat, committed, or shipped in a build:

1. **Dashboard → Project Settings → API keys → `service_role` → Rotate.** The old key stops
   working immediately.
2. `npx supabase secrets set NIVORA_SERVICE_ROLE_KEY=<new-key>` — takes effect on the next
   invocation, no redeploy.
3. Update the same key wherever the Next.js deployment holds it (Vercel project env
   `SUPABASE_SERVICE_ROLE_KEY`) and redeploy that.
4. Read `public.audit_log` for the exposure window. Rotation stops future use; it does not undo
   past use.

`docs/incident-response.md` has the full procedure.

---

## 11. Local development (optional)

```bash
npx supabase functions serve sa-create-owner --env-file ./supabase/.env
```

Needs Docker. `--env-file` points at a **local, git-ignored** file holding the same names as §4.
Delete it when you are done — it is a plaintext service-role key on your disk.
