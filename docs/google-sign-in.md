# Google sign-in ("Continue with Google")

**State on 2026-10-17:** built and tested (app, Edge Function, migrations). The database guard
(`2026-10-17-google-sign-in.sql`) is **live** (schema_migrations `20261017100000`; its test file
passed on live, rolled back). Everything else is not live yet: switching it on is the ordered list in
§3. Facebook is the next step and is not built (§6).

---

## 1. What a person sees

- **On the sign-in screen**, under the password form: "or", then Google's white **Continue with Google**
  button. It is drawn only in a build that carries a Web client ID (`Env.googleWebClientId`), so a
  build made before §3 shows exactly the screen it shows today.
- **Tapping it** opens Android's own Google account sheet (Credential Manager). No browser, no web
  view: the rule is "nothing goes to the browser".
- **Automatic for returning users.** When the sign-in screen opens, the app quietly asks Google whether
  this phone has signed in with Google before. If so, the person is signed straight back in. After a
  deliberate **Sign out**, the app makes the phone forget the Google account, so they stay signed out.
- **Who can use it:** owners and residents whose login address is that Google account's address.
  Owners still enter their 2-step code afterwards (the server will not serve an owner at aal1).
- **Who cannot:** managers, wardens and the Super Admin. They are told: "Staff and administrator
  accounts sign in with the login they were given, not with Google." A person with no account is told
  "No account uses <their address> yet …". Self sign-up (new owners and tenants) is 1.3.0 work.

## 2. How it works, and where each rule is enforced

```
phone: Credential Manager ──ID token + raw nonce──▶ mobile-auth  { action: "google" }
                                                     1. IP budget (same as password)
                                                     2. verifies the token: Google's keys, issuer,
                                                        audience = GOOGLE_WEB_CLIENT_ID, expiry,
                                                        email_verified, nonce = sha256(raw)
                                                     3. per-address budget (SHARED with password)
                                                     4. public.login_account_for_email(): refuses
                                                        no account / staff / inactive, in words
                                                     5. GoTrue /token?grant_type=id_token ──▶ session
```

- **App:** `apnivaas_app/lib/core/auth/google_id_token.dart` (asks Google),
  `auth_controller.dart` `signInWithGoogle` (one fresh start, then the same `_accept` the password
  uses), `auth_endpoint.dart` `signInWithGoogle`, `features/auth/login_screen.dart` (the button).
- **Server:** `supabase/functions/mobile-auth/index.ts`, section GOOGLE.
- **Database:** `db/migrations/2026-10-17-google-sign-in.sql`:
  - `app.guard_external_identity()`, a trigger on `auth.identities`. GoTrue links a Google identity
    to any existing user with the same address **automatically**, on every path, including the public
    ones no Edge Function stands in front of. The trigger refuses google/facebook on super_admin,
    manager and warden accounts, and refuses every other provider outright (GitHub included).
  - `public.login_account_for_email(text)`: service role only.
  - `public.email_link_proof()` gains arm C: a Google sign-in on the account's current, Google-verified
    address counts as proving the address, so an owner is not sent to "verify your email" after Google
    has already verified it.
- **Tests:** `apnivaas_app/test/google_sign_in_test.dart` (20 tests) and
  `db/migrations/2026-10-17-google-sign-in.test.sql` (rolled-back, against a real database).

## 3. Switching it on — in this order

### Step 0 — now, and independent of everything else

Supabase dashboard → **Authentication → Sign In / Providers**:
- **GitHub → off.** It was found switched on (2026-10-17) and nothing uses it.
- **"Allow new users to sign up" → off.** Every Apnivaas account is created by the server. The
  email-verification link sends with "don't create users", so nothing that exists depends on this.
  Google sign-up (1.3.0) will also create accounts through the server, so it stays off then too.

### Step 1 — Google Cloud (about 15 minutes, your Google account)

Use the Google Cloud project that already holds Firebase for push (`nivorapg`), signed in with the
account that owns it. One project is simpler than two, and the consent screen shows the app name,
not the project id.

1. console.cloud.google.com → pick project **nivorapg** → **Google Auth Platform** → Get started.
   - App name **Apnivaas**, user support email, Audience **External**, developer contact email.
   - **Do not upload a logo yet.** A logo makes Google require brand verification before the
     name shows; the name alone needs none for the scopes used here (openid, email, profile).
   - **Audience → Publish app.** Left in "Testing", only listed test users can sign in.
2. **Clients → Create client → Web application**, name "Apnivaas server".
   - **Leave "Authorized redirect URIs" empty.** The app never uses the browser redirect, and with no
     redirect URI Google refuses to complete GoTrue's public `/auth/v1/authorize?provider=google`
     path, which closes that door entirely.
   - Copy the **Client ID** (it is public — send it over, or put it in `Env.googleWebClientId`).
   - Copy the **Client secret** and paste it **only** into Supabase in Step 4. Never into a chat,
     a file or the app.
3. Play Console → Apnivaas → **Test and release → App integrity → App signing**. Copy the SHA-1 of
   the **App signing key certificate** and of the **Upload key certificate**.
4. Back in Google Cloud: **Clients → Create client → Android**, package `com.nivorasr.app`, the
   first SHA-1. Then a second Android client with the other SHA-1. (For a locally built debug APK,
   a third with the debug keystore's SHA-1.)

### Step 2 — the database guard — DONE 2026-10-17

`db/migrations/2026-10-17-google-sign-in.sql` is applied to live and
`2026-10-17-google-sign-in.test.sql` passed there (it rolls itself back). It had to come before
Step 4: once the provider is on, GoTrue links by address on its public paths too. It also makes the
GitHub provider inert today, whatever the dashboard says: a GitHub sign-in has to write a `github`
identity, and the trigger refuses every one (no account had one when it went live).

### Step 3 — the Edge Function (you deploy)

```bash
npx supabase secrets set GOOGLE_WEB_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
npx supabase functions deploy mobile-auth
```

### Step 4 — the dashboard switch

Supabase → **Authentication → Sign In / Providers → Google → Enable**:
- **Client IDs:** the Web client ID (the same value as the secret above).
- **Client Secret:** the Web client's secret.
- **Skip nonce checks: off.** The app sends a nonce and the server checks it.

### Step 5 — the privacy policy, before any build that shows the button

Google sign-in is a new source of data (Google account ID, name, address, photo link), so the
privacy policy changes and the legal version moves. Same order as every bump
(`docs/play-console-submission.md`, Step 5): the `legal_versions` row live first, then the website
push, then the app build. Play Console's **Data safety** answers change with it (§5).

### Step 6 — the build

Put the Web client ID in `Env.googleWebClientId`'s default (it is public, like the anon key) or pass
`--dart-define=GOOGLE_WEB_CLIENT_ID=…`, then build with `scripts/release.sh` as usual.

### Step 7 — check on a real phone

- An owner whose login is a Gmail address → Continue with Google → 2-step code → home.
- A manager or warden → the staff sentence, and no session.
- A Gmail address with no account → "No account uses … yet".
- Sign out → reopen → still signed out (the phone forgot the Google account).

## 4. When it does not work

| What you see | Most likely cause |
|---|---|
| The sheet closes straight after choosing an account, nothing shown | Credential Manager reports some misconfigurations as "cancelled": a SHA-1 missing from the Android clients, a Web client ID from another project, or the app still in "Testing" |
| "Google sign-in isn't set up in this version of the app" | The build has no Web client ID, or Google reports a client configuration error |
| "Google sign-in isn't switched on yet" | `GOOGLE_WEB_CLIENT_ID` secret missing, or the provider is off in Supabase |
| "Google sign-in didn't go through" + function log "GoTrue refused a Google token mobile-auth accepted" | The dashboard's Client IDs and the `GOOGLE_WEB_CLIENT_ID` secret disagree |

## 5. Privacy and Play

- **New data:** Google account ID and the name, address and photo link Google shares; GoTrue keeps
  them in `auth.identities`. Nothing is posted to the Google account and nothing else is read.
- **Data safety:** "User IDs" (account management) and "Name"/"Email address" now also arrive from
  Google; account creation method gains Google sign-in.
- **iPhone:** Apple's App Store rule 4.8 requires Sign in with Apple wherever Google sign-in is
  offered. The iOS build needs it before Google ships there.

## 6. Facebook — the next step, and why it is different

Supabase's native path (`signInWithIdToken`) only accepts a Facebook **OpenID token**, and Facebook
issues those only to iPhone apps ("Limited Login"). An Android Facebook login yields an access token
GoTrue cannot read. So Facebook on Android = native login through the Facebook app
(`flutter_facebook_auth`, `loginBehavior: nativeOnly`, button shown only when the Facebook app is
installed — no browser) plus a new action on mobile-auth that checks the token with Facebook's Graph
API and mints the session itself. It needs a Meta developer app (App ID, client token, app secret as an
Edge Function secret) and the same guard, privacy and Data safety work as above.

## 7. Undo

Provider off in the dashboard first, then `2026-10-17-google-sign-in.down.sql`. Google identities
already linked stay linked (harmless once the provider is off); the down file says how it is checked.
