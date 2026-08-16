# scripts/

- `_qa-login.mjs <email|phone-login-email> <password>` — signs in against Supabase with the anon key
  and prints the cookie header the Next.js app expects. Used for curl-based QA of authenticated pages:

  ```bash
  COOKIE=$(node scripts/_qa-login.mjs warden@demo.hostelpro.app Warden@12345)
  curl -s -b "$COOKIE" http://localhost:3000/warden | grep -o "Occupancy"
  ```
  Student logins use `<10-digit-phone>@student.hostelpro.local` as the email.

- `_qa-action.mjs <email> <password> <page-path> <actionId> '<json-args>' | --form k=v … [--file field=path …]`
  — invokes a Server Action over HTTP as a signed-in user (JSON args via the `Next-Action`
  header; FormData actions via Next's no-JS `$ACTION_ID_<id>` multipart path, files supported).
  Action ids come from `.next/server/server-reference-manifest.json` (dev) — visit the page first
  so it's compiled. In Git Bash prefix with `MSYS_NO_PATHCONV=1` so `/manager/...` isn't rewritten.
