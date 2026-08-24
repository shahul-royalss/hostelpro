# Password reset

How a locked-out user gets back in, why the flow forks in two, and the one thing the owner must
do before this works in production.

**Status: the code is complete and verified; the flow is NOT reachable yet.** Two one-line
changes are still owed, both in files outside this change's scope — see §8. Until they land,
every reset link redirects to `/login`.

---

## 1. The constraint that shapes everything

Half the people in this app have no email address.

A student signs in with a **phone number**. Supabase Auth needs an email, so `lib/utils.ts` maps
the phone to a deterministic synthetic address:

```
9000000001  ->  9000000001@student.hostelpro.local
```

`student.hostelpro.local` is not a domain. It does not resolve, it has no MX record, and no mail
sent to it will ever be delivered anywhere. A password reset mailed there is not slow — it is
gone.

Staff (`super_admin`, `owner`, `manager`, `warden`) are created with **real** addresses
(`lib/auth/accounts.ts` → `createStaffAccount`), so for them a reset link works normally.

So the flow forks:

| What was typed | What happens |
|---|---|
| Anything containing `@` | `supabase.auth.resetPasswordForEmail()` — a real link to a real inbox |
| A phone number | Told plainly that their **warden** resets it. No mail is sent and none is claimed. |

**The fork is decided by the shape of the typed string, never by a database lookup.**
`resolveLoginEmail()` is a pure function; the branch asks "did you type a phone number?", which
the person at the keyboard already knows. That is what keeps the fork from being an enumeration
oracle — see §3.

### Why the student screen does not name their actual warden

The brief asked for the warden's contact details "if the app knows it". It is not shown, and
that is a decision rather than an omission.

Printing the warden for a typed phone number would require looking that number up, and the
answer would differ for a number that belongs to a resident and one that does not. That turns
the form into a public query: *"is this phone number a resident here, and of which hostel?"* —
asked about young people whose address is exactly the thing worth protecting, by anyone with a
phone-number list and a browser.

The screen therefore names the **role** ("ask your warden or the hostel office"), which is true
for every hostel and reveals nothing about any of them.

> **This flow tells students to ask their warden, and the warden currently has no button to
> press.** `regeneratePassword()` exists in `lib/auth/accounts.ts` and is wired up for
> Super Admin → owner and Owner → staff, but **nothing resets a student's password**. See §8.

---

## 2. The route map

```
/forgot-password              the form                       (app/forgot-password/page.tsx)
/reset-password/callback      where the email link lands     (app/reset-password/callback/route.ts)
/reset-password               choose the new password        (app/reset-password/page.tsx)
```

The full path for a member of staff:

1. `/forgot-password` → types their email → `requestPasswordReset()`
2. GoTrue mails a link to `.../auth/v1/verify?token=…&type=recovery&redirect_to=<app>/reset-password/callback`
3. Clicking it lands on `/reset-password/callback?code=…&sb_flow_id=…`
4. The callback exchanges the code for a session, issues a **recovery ticket** (§4), and
   redirects to a clean `/reset-password` — the one-time code never reaches the address bar, so
   it cannot leak through `Referer`, a screenshot, or a shared phone's history
5. `/reset-password` → new password → `completePasswordReset()` → other sessions revoked →
   role home

---

## 3. No user enumeration

The single most common bug in a forgot-password form is that it answers differently for an
address that exists. This one is built so it cannot.

**Same text.** The email branch returns one sentence, always:

> If an account exists for `wa••••@demo.hostelpro.app`, a reset link is on its way.

The masked address is echoed back from **what the visitor typed**, not read from the database.
It tells them nothing they did not already know.

**Same status.** `ok: true` whether the account exists, does not exist, is deactivated, or
whether GoTrue answered `200` or `429`. Every error from Supabase is deliberately swallowed.

**Same timing — and this one had to be fixed, not assumed.** Measured against the live project
with the send awaited:

| Identifier | Response |
|---|---|
| `warden@demo.hostelpro.app` (exists) | **2121 ms** |
| `no-such-person-4713@demo.hostelpro.app` (does not) | **1170 ms** |

Identical wording with a 950 ms tell underneath it. GoTrue really does hand the message to SMTP
in the first case and short-circuit in the second, so *awaiting the send leaks exactly what the
copy was written to hide.*

The fix: the send is **issued and then raced against a fixed floor** rather than awaited. The
response leaves at `RESPONSE_FLOOR_MS` (900 ms) regardless — see `requestPasswordReset()`. After
the change both cases measured **~950 ms** (§7).

Consequence worth knowing: on a serverless platform the instance may be frozen the moment the
action returns. The HTTP request to GoTrue is already on the wire by then, so the *mail* is
unaffected; what can be lost is the delivery status in the audit row, which is recorded as
`status: "pending"` when the send outlives the floor. That is the normal case for a real
delivery.

**One message does differ**, and deliberately: the rate-limit refusal. It varies with request
*volume*, never with existence — the limiter is keyed on a hash computed identically for a real
address and an invented one, and it is checked before anything looks the account up.

---

## 4. Why a signed-in user cannot just visit `/reset-password`

Once the callback exchanges a recovery link, the visitor holds an ordinary Supabase session,
indistinguishable to every later request from one obtained by typing a password.

If `/reset-password` accepted *any* signed-in user, it would be a documented bypass of a control
this codebase enforces on purpose. `changePassword()` (`lib/actions/auth.ts`) demands the
current password for a *voluntary* change, so that a stolen cookie or an unlocked phone cannot
be used to lock the real owner out (SECURITY.md §8). An attacker holding a session would simply
skip `/change-password` and use `/reset-password` instead.

So the page is gated on **two independent things**:

| Check | Answers |
|---|---|
| A live Supabase session | *who* |
| A signed **recovery ticket** cookie | *how the session was obtained* |

The ticket (`app/reset-password/ticket.ts`) is an HMAC over `userId.expiry`, keyed by a value
**derived** from `SUPABASE_SERVICE_ROLE_KEY` (same secret material, different purpose, so a
signature can never be confused with a credential). It is `httpOnly`, scoped to
`path=/reset-password`, lives 15 minutes, and is cleared on success. It is issued **only** when
GoTrue itself reports the redirect type as `recovery`, so a confirmation or magic link cannot
mint one.

Verified: a warden with a perfectly valid session who visits `/reset-password` gets
"This link has expired" and **zero password inputs** (§7).

> **`app/reset-password/ticket.ts` must not `import "server-only"`.** It looks like it belongs
> and it breaks the build — the file is under `app/` (RSC layer) but is also reachable from a
> client component through the action module, where `server-only` resolves to its poisoned entry
> and the module comes out empty. It surfaces as `TypeError: Cannot read properties of undefined
> (reading 'call')` while prerendering `/forgot-password`, a page whose source mentions none of
> it. `next/headers` in that file is the same guard by other means. The comment in the file says
> so; please leave it there.

---

## 5. Email delivery: read this before promising anything

**There is no third-party mail provider configured on this project.** Reset mail goes out
through Supabase's built-in SMTP, and that service is explicitly documented as being for
development and testing only.

What that means in practice:

- **A few messages per hour, project-wide.** Supabase's built-in sender is heavily rate-limited
  (single digits per hour on the free plan). It is a shared, best-effort sender, not a delivery
  service. A hostel with thirty staff accounts can exhaust the quota in an afternoon.
- **It lands in spam, often.** The mail is sent from a shared Supabase domain with no SPF, DKIM
  or DMARC alignment to the hostel's own domain. Gmail and Outlook treat that as unauthenticated
  bulk mail.
- **There is no bounce feedback.** If it does not arrive, nothing in this app will know.

**Do not describe this as working email delivery.** The in-app copy is written accordingly: it
tells the user to check spam and to fall back to asking their hostel owner.

### What the owner must do for production

1. Supabase dashboard → **Project Settings → Authentication → SMTP Settings** → enable **Custom
   SMTP** and enter the credentials of a real transactional provider (Resend, Postmark, SendGrid,
   Amazon SES — any of them). Set the sender to an address on a domain the hostel controls.
2. In that provider's dashboard, add the **SPF**, **DKIM** and **DMARC** DNS records it gives you
   for that domain. Without these the mail is authenticated as nobody and will keep landing in
   spam.
3. Supabase dashboard → **Authentication → URL Configuration** → add the callback to
   **Redirect URLs**:
   ```
   https://hostelpro-three.vercel.app/reset-password/callback
   http://localhost:3000/reset-password/callback     (development only)
   ```
   GoTrue refuses any `redirectTo` that is not on this list, so **the flow cannot work until
   this is done** — the link will bounce to the site root instead.
4. Set `NEXT_PUBLIC_APP_URL` in the Vercel project environment to
   `https://hostelpro-three.vercel.app`. Reset links are built from configuration and never from
   the `Host` header (a header-derived link is a phishing primitive), and `appOrigin()` refuses a
   `localhost` value in production, so getting this wrong fails visibly rather than silently.

### Optional: make links work across devices

Today the link must be opened **in the same browser that asked for it**. `@supabase/ssr` runs the
PKCE flow, and the code verifier is a cookie on the requesting browser — ask on a phone, open on
a laptop, and the exchange fails. The in-app copy says so.

To lift that restriction, change the **Reset Password** email template (Authentication → Email
Templates) from `{{ .ConfirmationURL }}` to a token-hash link:

```html
<a href="{{ .SiteURL }}/reset-password/callback?token_hash={{ .TokenHash }}&type=recovery">
  Reset your password
</a>
```

The callback already handles both shapes — `code` (PKCE) and `token_hash` + `type=recovery` — so
this is a template change with no code change.

---

## 6. Security summary

| Control | Where |
|---|---|
| No user enumeration — same text, same status, same timing | `requestPasswordReset()`, §3 |
| Rate limited per identifier (3/h), per IP (12/h), per completion (5/15min) | `RESET_LIMITS`; fails **closed**, matching `signIn()` |
| Request and completion both audited, identifier hashed | `auth.password.reset_requested` / `reset_rate_limited` / `reset_completed` |
| Password policy | `changePasswordSchema` reused verbatim — no second policy |
| Other sessions revoked on success | `signOut({ scope: "others" })`, as `changePassword()` does |
| Reauthentication not bypassable | recovery ticket, §4 |
| Link origin not attacker-controlled | `appOrigin()` — config only, never the `Host` header |
| No open redirect from the email | callback redirects to a hardcoded relative path; `?next=` is ignored |
| One-time code never reaches the address bar | callback consumes it and redirects clean |

Revoking other sessions matters more here than it does for a voluntary change: a reset is what
someone does when they have *lost control* of their password, which is exactly when a session an
attacker is already holding is most likely to exist.

---

## 7. What was verified, and how

Against a production build (`npx next build`) served by `next start`, and the live Supabase
project.

**Signed-out reachability — currently broken, see §8:**
```
$ curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}\n" http://localhost:3200/forgot-password
307 -> http://localhost:3200/login?next=%2Fforgot-password
```

**The reauthentication bypass is closed.** With a valid warden session but no recovery ticket:
```
$ curl -s -H "Cookie: $WARDEN" .../reset-password | grep -c 'name="password"'
0
```
The page renders "This link has expired" and no form.

**The callback fails closed in every direction** — bad code, expired-link error params, no
params, `type=magiclink`, and an injected `?next=https://evil.example.com` all produce
`307 -> /reset-password?error=link`, never an off-origin redirect, and set no cookie.

**Enumeration, after the timing fix** (360×800 viewport, real form submissions):

| Identifier | Heading | Time |
|---|---|---|
| `warden@demo.hostelpro.app` (exists) | Check your email | ~950 ms |
| `no-such-person-4713@demo.hostelpro.app` | Check your email | ~950 ms |
| `9000000001` (student) | Your warden resets this one | ~950 ms |

Before the fix these were 2121 ms / 1170 ms — see §3.

**Viewports:** 320×800, 360×800 and 390×844. No horizontal overflow on any of them; the submit
button is 48 px tall (above the 44 pt touch minimum) at every width.

---

## 8. Still owed — this flow is NOT live until these land

Both are in files outside this change's assigned paths.

**1. `lib/supabase/middleware.ts` — `PUBLIC_PATHS` (blocking).** Without this every reset link
redirects to `/login` and the whole flow is dead. Two entries; `PUBLIC_PATHS` is prefix-matched,
so `/reset-password` covers `/reset-password/callback` as well:

```ts
const PUBLIC_PATHS = [
  "/login",
  "/forgot-password",   // add
  "/reset-password",    // add — also covers /reset-password/callback
  "/legal",
  ...
];
```

**2. `components/auth/login-form.tsx` — the entry point (blocking).** "Forgot password?" is
currently a `<span>` with a tooltip, not a link, so there is no way into the flow from the UI:

```tsx
<span className="..." title="Ask your administrator to regenerate your password">
  Forgot password?
</span>
```

It should become `<Link href="/forgot-password">`.

**3. `lib/auth/accounts.ts` + a warden action — the student half (important).** The student
branch tells people their warden resets their password. Today no such capability exists:
`regeneratePassword()` is wired only for Super Admin → owner and Owner → staff. A warden needs
the equivalent for a student in their own hostel, audited as `warden.student.password_reset`.
Until then the student screen is advice the app cannot yet honour.

### Also worth fixing (found while measuring, not caused by this change)

`/change-password` ships **131 kB** of page JavaScript against `/login`'s 1.94 kB. Cause:
`components/auth/change-password-form.tsx` (a client component) imports `passwordStrength` from
`@/lib/auth/password`, whose `generatePassword()` uses `randomInt` from `node:crypto` — so
webpack ships a 325 kB `crypto-browserify` chunk to the browser for one strength label. Note that
`lib/validators/auth.ts` re-exports the same constant, so importing the zod schema into a client
component has the same effect.

The fix is to split the client-safe half (`PASSWORD_MIN_LENGTH`, `passwordStrength`) into its own
module. `/reset-password` avoids the problem by taking `minLength` as a prop from its server
component, and weighs **2.1 kB**.
