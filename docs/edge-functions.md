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
  "fullName": "…", "phone": "9876500042", "email": "optional", "dateOfJoining": "2026-08-25",
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

The student's **login id is their phone number**; `loginId` is what they type on the sign-in
screen.

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
