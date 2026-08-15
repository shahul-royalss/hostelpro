# scripts/

- `_qa-login.mjs <email|phone-login-email> <password>` — signs in against Supabase with the anon key
  and prints the cookie header the Next.js app expects. Used for curl-based QA of authenticated pages:

  ```bash
  COOKIE=$(node scripts/_qa-login.mjs warden@demo.hostelpro.app Warden@12345)
  curl -s -b "$COOKIE" http://localhost:3000/warden | grep -o "Occupancy"
  ```
  Student logins use `<10-digit-phone>@student.hostelpro.local` as the email.
