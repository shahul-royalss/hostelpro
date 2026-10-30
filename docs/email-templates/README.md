# Apnivaas auth email templates

Supabase Auth (GoTrue) sends these emails, not our code. The templates live in the Supabase dashboard; the files here are the source of truth. No images, no tracking pixels, no external resources: every style is inline, so the email reads well even as plain text.

## Subjects and files

| Dashboard template | Subject | File |
|---|---|---|
| Confirm signup | `Confirm your email for Apnivaas` | `confirm-signup.html` |
| Invite user | `You have been invited to Apnivaas` | `invite.html` |
| Magic link | `Confirm your email to continue in Apnivaas` | `magic-link.html` |
| Change email address | `Confirm your new email address for Apnivaas` | `change-email.html` |
| Reset password | `Reset your Apnivaas password` | `reset-password.html` |
| Reauthentication | `Your Apnivaas verification code` | `reauthentication.html` |

The app's "verify your email" step calls `signInWithOtp(shouldCreateUser: false)`. An unconfirmed address gets **Confirm signup**; a confirmed one gets **Magic link**. That is why the magic-link copy says "confirm and sign in".

Variables used, exactly as GoTrue spells them: `{{ .ConfirmationURL }}`, `{{ .Token }}` (reauthentication only), `{{ .SiteURL }}` (invite), `{{ .Email }}`, `{{ .NewEmail }}` (change email). Do not change them. `{{ .ConfirmationURL }}` already carries the app's redirect (`com.nivorasr.app://verify-email`, the Play package id, which is not shown to users).

## Dashboard steps (project nimxvgzscbanhtvgnjll)

1. Supabase → **Authentication** → **Emails** → **Templates**.
2. For each row above, open the template, paste the subject, switch the body to source/HTML, paste the whole file, and **Save**.
3. Supabase → **Authentication** → **Emails** → **SMTP settings**: set **Sender name** to `Apnivaas` and save. Keep the sender email and SMTP host as they are. Without custom SMTP the built-in sender's name cannot be changed.
4. Send yourself a test: sign up with a new address in the app, then use Forgot password. Check the sender name, the subject, and that the button opens the app.

Brand: forest `#174E43`, cream `#F6F2EA`.
