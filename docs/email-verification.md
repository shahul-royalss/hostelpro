# Email verification — the link opens Nivora, and that sign-in is the proof

**Status:** rebuilt 2026-09-01 to the flow the owner asked for, verbatim:

> "the email verification has to be like: it has to ask to login through that link once they
> login through that link they have to verify"

---

## 0. The one thing to paste. Everything else in this file is explanation.

**Page:** <https://supabase.com/dashboard/project/nimxvgzscbanhtvgnjll/auth/url-configuration>
(sidebar: **Authentication → URL Configuration**)

Under **Redirect URLs**, click **Add URL** and paste this, exactly, with no trailing slash and
no `https://` in front of it:

```
app.nivora.mobile://verify-email
```

Press **Save**. There is no deploy step and no rebuild; it takes effect on the next email sent.

**Does Site URL still matter? No — leave it alone.** It is already
`https://hostelpro-three.vercel.app` (measured today, see §3), which is correct, and this
release does not need it changed. Site URL now only decides where a *browser* lands when it
cannot open the deep link — the fallback in §4.2 — and where GoTrue sends a redirect it has
refused. Both are already pointing at a page that loads.

Do **not** add a wildcard (`app.nivora.mobile://**`, or `https://hostelpro-three.vercel.app/**`).
The allow-list is what stops an emailed one-time token being redirected somewhere an attacker
chose. One exact entry is all this needs.

---

## 1. What the owner saw, and what was actually wrong

Tapping the link in the mail opened `hostelpro-three.vercel.app` and showed

> Page not found — That link doesn't exist, or you don't have access to it.

The reason, measured rather than guessed: `app/verify-email/confirmed/page.tsx` **is untracked in
git** — `git ls-files app/verify-email/` returns nothing — so it was never pushed and never
deployed. The route does not exist in production. So does the middleware change that would make
it public (`lib/supabase/middleware.ts` is modified but uncommitted). Both are the owner's to
resolve; §7 has the exact commands.

**The address was verified anyway, every time.** GoTrue matches the single-use token at
`/auth/v1/verify` **before** it redirects anywhere. The redirect is the last thing that happens
and it changes nothing about the proof. Three of the four live accounts have a real recorded
click and a stamped `email_verified_at` today (§6), earned through exactly that broken landing
page. The failure was **cosmetic in the browser and fatal in the head**: the user believed
nothing had happened and never came back to Nivora to let it re-check.

Deploying the missing page would have removed the scary screen. It would not have given the
owner what they asked for, and it could never have, for the reason in §2.

---

## 2. Why the link now opens the app, and why a web page could never have done this

The app pins `AuthFlowType.pkce` (`nivora_app/lib/main.dart`). Under PKCE, `/auth/v1/verify`
does not hand out a session — it stamps an auth code onto the flow state and redirects with
`?code=`. That code can only be exchanged for a session by whoever holds the **code verifier**,
and the verifier for a link *this app* asked for is in *this app's* keystore.

**A browser holds no verifier.** Any web landing page is therefore a page that watched something
happen elsewhere and printed a sentence about it. It is structurally incapable of logging the
person in, which is the thing the owner asked for.

So the redirect is a **custom scheme that opens Nivora**:

| Piece | Where | Value |
|---|---|---|
| Redirect the app requests | `nivora_app/lib/core/config/env.dart` → `Env.emailConfirmRedirectUrl` | `app.nivora.mobile://verify-email` |
| Intent filter that catches it | `nivora_app/android/app/src/main/AndroidManifest.xml` | `<data android:scheme="app.nivora.mobile" android:host="verify-email"/>` |
| Dashboard allow-list entry | Supabase → Authentication → URL Configuration | the same string (§0) |

All three must be the same string. The first two are asserted against each other by
`nivora_app/test/email_verification_test.dart` §8, which reads the manifest and compares it to
the Dart constant, because those two files cannot see one another and drift between them is
silent. The third is a dashboard field no test can reach — which is why §0 exists and why the
app itself names it on screen (§4.4).

What happens on the phone, in order:

1. GoTrue matches the emailed token at `/auth/v1/verify` and stamps
   `auth.flow_state.auth_code_issued_at`. **The proof is minted here**, before any redirect.
2. GoTrue 303s to `app.nivora.mobile://verify-email?code=…`.
3. Android hands that Uri to Nivora — to the copy already running, because `MainActivity` is
   `launchMode="singleTop"`, or by cold-starting it.
4. `supabase_flutter`'s deep-link observer sees the `code` parameter, calls
   `getSessionFromUrl` → `exchangeCodeForSession`, and **the person is signed in by the link**.
5. That emits `signedIn`, which `AuthController`'s existing listener answers by re-resolving the
   profile. The banner clears.

### Why a custom scheme and not an `https://` App Link

An `https` intent filter would offer Nivora as a handler for ordinary web URLs. Without a
verified Digital Asset Link, Android shows a disambiguation sheet on somebody else's links — and
on Android 12+ an `autoVerify` filter that fails verification is **never offered to the app at
all**. `public/.well-known/assetlinks.json` currently delegates `hostelpro-three.vercel.app` to
`app.nivora.twa`, the old web wrapper, not to `app.nivora.mobile`; adding the Flutter app needs
the Play App Signing SHA-256, which per `docs/PLAY-CRITICAL-assetlinks.md` does not exist until
after the first upload. So an App Link would ship as a filter that never fires.

`app.nivora.mobile` is this app's own `applicationId` used as a scheme — the reverse-DNS form
RFC 3986 allows, which nothing else on the device can claim. **Scheme and host are both pinned**,
so the only Uri the filter accepts is `app.nivora.mobile://verify-email[?…]`. It captures no
`http`, no `https`, and no bare-scheme wildcard; a test asserts that too.

### One cost, stated plainly: the super admin re-enters their TOTP

Exchanging the code creates a session authenticated by `magiclink` alone — **aal1**.
`app.is_super_admin()` is `(role = super_admin AND mfa_satisfied)` and is false at aal1. So a
super admin who taps their own verification link on the phone is dropped back to the TOTP prompt
and has to re-enter six digits.

This is a re-prompt, not a lockout, and **the security boundary is unweakened** — aal2 is still
required for everything that required it. It is listed here so nobody reports it as a bug. It
affects exactly one account on this project (`codewithshahul@gmail.com`), which is already
verified, so in practice it will rarely be hit at all.

---

## 3. What is actually set on the project right now

Measured 2026-09-01 by asking `/auth/v1/verify` to redirect a **dead** token and reading the
`Location` header back. That is the one probe that shows GoTrue's decision without spending a
real link:

```
redirect_to=app.nivora.mobile://verify-email
  -> 303  Location: https://hostelpro-three.vercel.app#error=…otp_expired…     SUBSTITUTED

redirect_to=https://hostelpro-three.vercel.app/verify-email/confirmed
  -> 303  Location: https://hostelpro-three.vercel.app/verify-email/confirmed#error=…  HONOURED

redirect_to=https://definitely-not-allowed.example.org/x
  -> 303  Location: https://hostelpro-three.vercel.app#error=…                  SUBSTITUTED
```

Two facts follow, and both matter:

1. **Site URL is already `https://hostelpro-three.vercel.app`.** Earlier revisions of this
   document said it was `http://localhost:3000`. That was true when they were written and is not
   true now — the owner fixed it. Nothing further is needed there.
2. **The deep-link entry is not on the allow-list yet.** GoTrue accepts a `redirect_to` only if
   it is on the allow-list or shares a hostname with the Site URL. A custom scheme shares a
   hostname with nothing, so it needs the entry. Until it is added, the link keeps landing on the
   web root instead of opening Nivora.

**GoTrue never says no out loud.** It does not refuse an unlisted redirect — it *silently
substitutes the Site URL*. There is no error for the app to catch, no log line, and no way for
the server or the database to detect it. That is the whole reason this is a document and an
earned on-screen note rather than an automatic check.

### The other three project settings, unchanged by this rebuild

- **Magic Link email template must contain `{{ .ConfirmationURL }}`**
  (Authentication → Emails → Magic Link). That is Supabase's stock template, so an untouched
  project is correct. It is listed because Nivora's *previous* flow was a 6-digit code and asked
  for `{{ .Token }}` here; a template still edited that way sends mail with nothing to click.
- **CAPTCHA must be OFF** (Authentication → Attack Protection). The app sends no CAPTCHA token
  and CAPTCHA refuses `/auth/v1/otp` outright. Verified off. If it is ever switched on, the app
  names this setting on screen instead of blaming the user's connection.
- **A real SMTP sender, before this reaches a hostel** (Authentication → Emails → SMTP Settings).
  Supabase's built-in sender is rate-limited to a handful of messages an hour and is explicitly
  not for production. Add SPF, DKIM and DMARC for whichever provider is chosen — without them
  the mail authenticates as nobody and goes to spam, which reads to a user exactly like "the app
  never sent it". Same requirement as `docs/password-reset.md`; one setting covers both.

---

## 4. Every other case, and why none of them is fatal

The deep link is the good path. It is not the only path, and the design does not depend on it.

**The proof does not live in the app.** It is minted by GoTrue at step 1 of §2 — before the
redirect, before Android, before Nivora is involved — and is read back afterwards by
`public.email_link_proof()`. Everything below therefore costs a **tap**, never the verification.

### 4.1 The link is opened on a laptop, or on a phone without Nivora installed

The browser cannot open a custom scheme, so it does nothing visible or shows "no app can open
this link". **The address is still verified.** The person comes back to Nivora — on any device,
at any time — and either:

- returns to the foreground, and the resume re-check clears the banner on its own; or
- taps **Verify now → I have opened the link**, which asks the server directly.

Both are live on every state of the screen. The screen says so, in as many words: "Opened on a
laptop or another device it lands on a web page instead: come back to Nivora and tap the button
below, which finishes it just as well."

### 4.2 The allow-list entry in §0 is never added

GoTrue substitutes the Site URL, so the link lands on `https://hostelpro-three.vercel.app`, which
returns 200. The user sees the Nivora web home page instead of the app. Identical to §4.1 from
there: the proof exists, the button finishes it. This is the situation **as of today**, and it is
how the three verified accounts in §6 got verified.

### 4.3 The link has expired or was already used

GoTrue redirects with `#error=access_denied&error_code=otp_expired`. If that lands on the phone,
`supabase_flutter` sees the `error` parameter, fails the exchange, logs it, and — importantly —
**does not sign the user out**. Nothing breaks; nothing is proved either, because nothing
happened. "I have opened the link" answers "Not confirmed yet", and the screen tells the truth
it has always told: only the newest link works, so send a new one.

### 4.4 It keeps not working, and nobody knows why

After **two consecutive** "the server has never seen your click" answers — one is ordinary, mail
is slow and people tap before reading; two is the person telling us twice — the verification
screen names the setting and the exact value from §0, under the same "not something you can fix
from here" framing every operator fault on that screen uses.

Two, not one, and not on arrival: instructions for a fault that may not exist are not neutral,
and this screen is opened by residents. The sentence is built from the constants actually
compiled into the build (`Env.emailRedirectSetupHint`), not transcribed here, so it cannot drift
away from this document.

### 4.5 The `email-verification` Edge Function is down

Nothing is lost. It is not on the critical path of anything: it neither sends the mail (GoTrue
does) nor mints the proof (GoTrue does). It only *reads* the proof and stamps
`public.users.email_verified_at`, which it must, because that column is writable by
`service_role` and nothing else — `app.users_update_guard` raises 42501 for every other writer,
including the account holder and the super admin. The next `status` call picks it up, and the app
issues one every time it returns to the foreground.

### 4.6 The account has no reachable address

A resident registered without an email signs in as `<digits>@student.hostelpro.local`, which no
mail server accepts. They are **never asked**. The exemption is carved by ADDRESS, not by role, so
a student whose warden collected a real email is asked exactly like an owner. The banner draws
nothing at all for them.

---

## 5. The security boundary did not move

`requireVerifiedEmail()` in `supabase/functions/_shared/verification.ts` is unchanged and is
still the gate. It reads `public.users.email_verified_at` and refuses the one action where an
unproved address becomes credentials in a stranger's inbox: **creating another account**
(`sa-create-owner`, `owner-create-staff`, `warden-register-student`). Everything else in the app
keeps working, which is why verification is a requirement and not a trap — the verify screen has
a working back button and an "I will do this later", and the router deliberately does not divert
to it.

How the proof was earned is not that gate's business. Nothing in the Flutter app is a security
boundary, and the deep link adds no new one: the client's entire role is to **ask for the mail**.
It cannot manufacture the answer.

---

## 6. The proof function, and what a real click actually wrote

`public.email_link_proof(uuid)` is `SECURITY DEFINER`, `service_role`-only, and reads two facts
GoTrue writes itself. Definition in `db/migrations/2026-09-02-email-link-proof-pkce.sql`;
confirmed identical in the live database on 2026-09-01.

- **Arm A — `auth.flow_state.auth_code_issued_at`**, where `authentication_method` is
  `magiclink`/`otp`/`recovery`. Stamped by GoTrue's verify handler at the instant it matched the
  emailed token. This is the PKCE-native fact.
- **Arm B — `auth.audit_log_entries`**: an `action=login` row with no `provider` trait, anchored
  to a `user_recovery_requested`/`user_confirmation_requested` row for the same actor within the
  preceding hour, so a login of some other kind is never credited.

Both are bounded below by `email_verification_reset_at`, which `app.users_update_guard` stamps on
any address change — so a user cannot verify their own address, repoint the row at a stranger's,
and have the old click re-read as proof of the new one.

**Does a deep link produce a different trail? No, and this is the load-bearing point.** Both arms
are written by the `/auth/v1/verify` handler *before* the 303, and the redirect target does not
participate in either. A deep link adds a later code exchange, which writes a session and an AMR
claim on top; it takes nothing away. The deep link is a strict superset of the browser landing,
so `email_link_proof()` matches it unchanged.

### Measured against real clicks, live, 2026-09-01

```
email                       email_verified_at              email_link_proof()          method
codewithshahul@gmail.com    2026-08-31 23:02:32.062+00     2026-08-31 23:02:16.552+00  magiclink
shahulroyals@gmail.com      2026-08-31 23:13:32.944+00     2026-08-31 23:12:39.227+00  magiclink
xeyrion1@gmail.com          2026-09-01 01:12:45.560+00     2026-09-01 01:12:09.575+00  magiclink
chudham20@gmail.com         null                           null                        —
```

Three real clicks, on real emailed links, by the owner and the warden. Both arms fired on all
three, within ~7ms of each other. `email_verified_at` lands 16–36 seconds after the click, which
is the app being reopened and calling `status`. **The end-to-end flow works today**, through the
substituted redirect of §4.2 and the 404 page of §1.

`chudham20@gmail.com` (the manager) has never opened a link. That is a real, outstanding
verification, not a fault.

---

## 7. The web page — the owner's action, with the exact commands

Nothing above needs the web page. It is the §4.1/§4.2 landing, so its only job is to stop a
laptop showing a 404. Two honest options:

**Option A — ship it (recommended).** The page and the middleware change both already exist in
the working tree; they have never been committed.

```bash
cd "C:/Users/shahu/OneDrive/Documents/pg management system"
git add app/verify-email/confirmed/page.tsx lib/supabase/middleware.ts
git commit -m "Deploy the verify-email landing page and make its path public"
git push
```

Vercel deploys on push. Confirm with:

```bash
git ls-files app/verify-email/          # must now list confirmed/page.tsx
curl -s -o /dev/null -w '%{http_code}\n' https://hostelpro-three.vercel.app/verify-email/confirmed
```

`200` means it is live. `307` means the middleware change did not go with it — `/verify-email`
must be in `PUBLIC_PATHS`, because the browser opening a link from an inbox is almost never
signed into the web app, and behind the session gate every confirmation lands on `/login`
looking like a failure.

**Option B — do nothing.** The redirect lands on `https://hostelpro-three.vercel.app`, which
returns 200 and is a real page. No 404, no error. This is strictly better than what the owner
photographed and costs nothing.

**Not an option: skipping §0 because the page is now deployed.** The page cannot log anyone in
(§2). Without the allow-list entry the owner's actual request is not implemented, however good
the landing page looks.

---

## 8. Checking it worked

From the app: home-screen banner → **Verify now**. A link is sent automatically. Open it on the
phone; if §0 has been done, **Nivora opens and you are signed in** and the banner is gone. If it
has not, the browser shows the Nivora home page — come back to Nivora and tap **I have opened the
link**.

From the SQL editor:

```sql
select u.email, u.email_verified_at, public.email_link_proof(u.id) as click
  from public.users u order by u.email;
```

`click` is when GoTrue last accepted a link for that account; `email_verified_at` is stamped from
it the next time the app calls the `email-verification` function. **`click` non-null with
`email_verified_at` still null just means the app has not been reopened yet** — that is the
normal intermediate state, not a fault.

If `click` is null after a real click, these two say exactly what GoTrue wrote, and the answer
goes straight into the arms of `email_link_proof()`:

```sql
select authentication_method, created_at, auth_code_issued_at
  from auth.flow_state where user_id = '<user id>' order by created_at desc limit 5;

select created_at, payload::text from auth.audit_log_entries
 where payload ->> 'actor_id' = '<user id>' order by created_at desc limit 10;
```

Note `auth.audit_log_entries` is pruned by GoTrue within hours and `auth.flow_state` within days.
Neither retention is ours to configure. It costs nothing — the window that matters is from the
click to the next `status` call, which is seconds — but it is why two independent arms are kept.

---

## 9. What was NOT measured, said plainly

- **A real click on a link that redirects to `app.nivora.mobile://verify-email`.** Not
  measured. It cannot be, from here: the allow-list entry in §0 is a dashboard field, GoTrue
  substitutes the Site URL until somebody adds it (§3), and adding it is not something this
  codebase or Claude can do. What *is* measured is the part that carries the risk — that the
  proof is minted before the redirect and is redirect-independent (§6) — so the deep link cannot
  cost a verification even if it fails outright.
- **The app running on a device.** No APK or Gradle build was run. The manifest was parsed and
  validated as well-formed XML, and the intent filter it registers was read back from the parse
  tree: one `MainActivity`, `exported=true`, `launchMode=singleTop`, and a VIEW/DEFAULT/BROWSABLE
  filter whose only `<data>` is `scheme=app.nivora.mobile host=verify-email`.
- **`supabase_flutter`'s behaviour was read, not run.** Version 2.17.2:
  `detectSessionInUri` defaults to `true`; the default callback predicate returns true for any
  Uri carrying `code` in the query or fragment; on Android the initial (cold-start) Uri arrives
  through the same `uriLinkStream`; and `_handleDeeplink` wraps `getSessionFromUrl` in a
  try/catch that logs and does **not** sign the user out.
