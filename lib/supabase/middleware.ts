import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { ROLE_HOME, roleForPath, type UserRole } from "@/lib/roles";
import { applySecurityHeaders, buildCsp, generateNonce } from "@/lib/security-headers";

// Google Play requires the privacy policy and the account-deletion route to be reachable by a
// reviewer who is NOT signed in — a policy URL behind a login is a rejection. /legal covers the
// policy, terms and the deletion-request page; they must stay signed-out-accessible.
const PUBLIC_PATHS = [
  "/login",
  "/legal",
  // Razorpay is not a signed-in user. Without this the webhook 307s to /login, Razorpay retries
  // until it gives up, and money that was actually captured is never credited to the student —
  // the app takes payment it cannot account for. This bypasses the SESSION check only: the route
  // verifies an HMAC over the raw body against RAZORPAY_WEBHOOK_SECRET and rejects anything else,
  // which is the real authentication for this endpoint.
  "/api/webhooks/razorpay",
  "/manifest.webmanifest",
  "/icons",
  "/api/health",
  "/robots.txt",
];
/** Paths a signed-in user may reach without completing MFA / password change */
const AUTH_STEP_PATHS = ["/mfa", "/change-password", "/api/health"];

function startsWithAny(pathname: string, list: string[]) {
  return list.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

/** Roles that MUST have a verified TOTP factor (env MFA_REQUIRED_ROLES, comma-separated). */
function mfaRequiredRoles(): Set<string> {
  return new Set(
    (process.env.MFA_REQUIRED_ROLES ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  );
}

/**
 * The `sub` claim of an access token, WITHOUT verifying its signature.
 *
 * This is a scheduling hint and nothing else — see the call site. It is duplicated in
 * lib/permissions.ts rather than shared, because everything in that module is Node-only
 * (`server-only`, `next/headers`, the audit client) and importing it here would drag all
 * of it into the Edge bundle.
 */
function unverifiedSubject(accessToken: string | undefined): string | null {
  const payload = accessToken?.split(".")[1];
  if (!payload) return null;
  try {
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4))) as { sub?: unknown };
    return typeof claims.sub === "string" && claims.sub ? claims.sub : null;
  } catch {
    return null; // malformed token → no hint, fall back to the serial path
  }
}

/**
 * A cookie-less Supabase client kept at MODULE scope, used for one thing: verifying the
 * signature of an access token we already hold.
 *
 * Why it has to outlive the request. `getClaims()` verifies an ES256/RS256 token locally
 * with WebCrypto against the project's published JWKS, and caches that key set on the
 * client instance for ten minutes. The request-scoped client above is discarded after every
 * request, so it would refetch the JWKS every time and we would have swapped one network
 * round trip for another. This instance is created once per isolate and keeps the cache.
 *
 * The only state it holds is the project's PUBLIC signing keys. It is never given cookies,
 * never holds a session, and `getClaims(token)` with an explicit token does not touch its
 * storage — so nothing about one request can leak into the next through it.
 */
let jwtVerifierClient: ReturnType<typeof createServerClient> | null = null;
function jwtVerifier() {
  jwtVerifierClient ??= createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => [], setAll: () => {} } },
  );
  return jwtVerifierClient;
}

/**
 * The user id this request is authenticated as, or null.
 *
 * This is the ONLY identity middleware acts on. Two modes, and the difference between them
 * is *liveness*, never *authenticity*:
 *
 *  • `askAuthServer` — `getUser()`, an HTTP round trip that asks the Auth server whether the
 *    session behind this token still exists. Used on /login (see needsLivenessCheck).
 *  • otherwise — `getClaims()`, which verifies the token's ES256 signature and `exp` locally
 *    against the cached JWKS. A forged, tampered, foreign-signed or expired token fails here
 *    exactly as it would at the Auth server; a token whose session was revoked in the last
 *    hour does not, and that is the whole of the difference.
 *
 * That difference is deliberate and it is safe HERE and only here, because middleware is not
 * the authority (SECURITY.md §3.2): requireUser() and assertRole() re-run the full getUser()
 * on every Server Component, Server Action and Route Handler, independently of routing. A
 * revoked-but-unexpired session therefore gets past middleware and is stopped by the page,
 * which redirects it to /login — where the liveness check above runs and it stays. It never
 * reaches data. Nothing that middleware checks has been removed; one round trip has.
 *
 * Fails closed in every direction: no token, an invalid token, or a verification the library
 * could not complete (symmetric signing key, no WebCrypto, JWKS unreachable) all end in either
 * `null` or the authoritative call. Never in "assume signed in".
 */
async function authenticatedSubject(
  supabase: ReturnType<typeof createServerClient>,
  accessToken: string | undefined,
  askAuthServer: boolean,
): Promise<string | null> {
  if (!accessToken) return null;

  const askTheAuthServer = async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    return user?.id ?? null;
  };
  if (askAuthServer) return askTheAuthServer();

  let data, error;
  try {
    ({ data, error } = await jwtVerifier().auth.getClaims(accessToken));
  } catch {
    // getClaims() converts the failures it recognises into `error`, but a token can be
    // malformed in ways that make it throw instead — `{"alg":"none"}` reaches getAlgorithm()
    // and raises a plain Error, which would otherwise leave middleware as a 500 on every
    // request carrying it. Hand those to the Auth server rather than deciding here: it is the
    // component that can always produce a verdict, and it is what this code path replaced.
    return askTheAuthServer();
  }
  if (error) {
    // A malformed, expired or wrongly-signed token is a verdict, not an outage — the Auth
    // server would say the same thing, so don't pay a round trip to hear it. (An expired
    // token is only ever seen here when getSession() already tried and failed to refresh it,
    // so the Auth server would reject it too.) Anything else — JWKS unreachable, WebCrypto
    // missing — is infrastructure failing to produce a verdict, so fall through to the one
    // that always can, rather than bouncing a live session to /login.
    if (error.name === "AuthInvalidJwtError" || error.code === "invalid_jwt") return null;
    return askTheAuthServer();
  }
  // A project signed with the legacy shared HS256 secret has no public key to verify against;
  // getClaims() detects that and calls getUser() itself, so this branch degrades to exactly
  // the previous behaviour rather than to a weaker one.
  const sub = data?.claims.sub;
  return typeof sub === "string" && sub ? sub : null;
}

/**
 * Paths where middleware must know the session is LIVE, not merely well-formed.
 *
 * /login is the terminus of every signed-out redirect in the app: requireUser() sends a
 * session it has just rejected there, and middleware would otherwise look at the still-valid
 * token, conclude "you're signed in", and bounce it back to the role home — which rejects it
 * again. That is an infinite redirect for as long as the token has left to live. Paying one
 * round trip on this one path breaks the cycle at its root, and every other path terminates
 * here, so no other path needs it.
 */
function needsLivenessCheck(pathname: string) {
  return pathname === "/login";
}

/** Session cookies are only ever read server-side → lock them down. */
function hardenCookie(options: Record<string, unknown> | undefined) {
  return {
    ...(options ?? {}),
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax" as const,
    path: "/",
  };
}

/**
 * Runs on every request (see /middleware.ts):
 *  0. sets a per-request CSP nonce + security headers on every response
 *  1. refreshes the Supabase session cookie (httpOnly/secure/lax)
 *  2. redirects unauthenticated users to /login
 *  3. blocks inactive/deleted accounts immediately (even with a valid token)
 *  4. forces password change on first login (pages AND server-action POSTs AND /api)
 *  5. enforces MFA step-up (aal2) when the account has a verified factor, and
 *     enrollment for roles listed in MFA_REQUIRED_ROLES
 *  6. makes sure the role matches the route group (/owner, /warden, …)
 * Hostel-scoping and subscription write-gating happen in RLS + server actions.
 *
 * Every one of those checks is ALSO enforced, independently of routing, by requireUser() /
 * assertRole() in lib/permissions.ts — see SECURITY.md §3.2 for the audit finding that made
 * that non-negotiable. This layer is navigation hygiene: it decides where to send a request,
 * it does not decide what a request may see.
 */
export async function updateSession(request: NextRequest) {
  const nonce = generateNonce();
  const csp = buildCsp(nonce, request.nextUrl.pathname);
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);

  let response = NextResponse.next({ request: { headers: requestHeaders } });
  const finish = (res: NextResponse) => {
    applySecurityHeaders(res.headers, csp);
    return res;
  };
  const redirectTo = (pathname: string, search = "") => {
    const url = request.nextUrl.clone();
    url.pathname = pathname;
    url.search = search;
    const res = finish(NextResponse.redirect(url));
    // Every redirect here is a function of *who is asking* — the role home, the login
    // bounce, the MFA step-up. Next defaults these to `public, max-age=0, must-revalidate`,
    // which authorizes a shared/CDN cache to store a per-user Location. Revalidation makes
    // that hard to exploit, but there is no reason to store it at all.
    res.headers.set("Cache-Control", "private, no-store, max-age=0, must-revalidate");
    return res;
  };

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request: { headers: requestHeaders } });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, hardenCookie(options as Record<string, unknown>)),
          );
        },
      },
    },
  );

  const { pathname } = request.nextUrl;

  // IMPORTANT: do not add logic between createServerClient and the two auth calls below.
  //
  // getSession() decodes the session out of the cookie locally; it only touches the network
  // when the access token has actually expired and has to be refreshed. Doing it first means
  // the token is settled before anything is issued against it, and it is the call that keeps
  // the refresh working now that getUser() no longer runs on most paths.
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const subjectHint = unverifiedSubject(session?.access_token);

  // Authenticating the token and reading public.users are two separate round trips that need
  // nothing from each other — only the *same* user id — so they are issued together. On every
  // path but /login the first of them no longer leaves the machine at all: the signature is
  // checked locally against the cached JWKS (see authenticatedSubject).
  //
  // SECURITY: `subjectHint` comes from an UNVERIFIED token and is used as nothing more than a
  // cache key for a read that is thrown away unless authenticatedSubject() independently
  // returns exactly that id. It cannot steer whose row is used:
  //  • the users_select policy has branches beyond `id = auth.uid()` — an owner may read staff
  //    in their own hostel — so a hint naming someone else is not automatically a dead read.
  //    It is dead anyway, because the only way to change the hint is to edit the token's
  //    payload, which breaks the signature that both the local verifier and PostgREST check;
  //  • the row is therefore only ever used when its id equals a subject that came out of a
  //    signature-verified token, i.e. the caller's own row;
  //  • any mismatch, error or missing hint falls through to the serial read below.
  const [userId, speculativeProfile] = await Promise.all([
    authenticatedSubject(supabase, session?.access_token, needsLivenessCheck(pathname)),
    subjectHint
      ? supabase
          .from("users")
          .select("role, status, must_change_password, deleted_at")
          .eq("id", subjectHint)
          .maybeSingle()
      : Promise.resolve(null),
  ]);

  if (!userId) {
    if (startsWithAny(pathname, PUBLIC_PATHS) || pathname === "/") {
      return finish(response);
    }
    // Only same-origin relative paths are ever used as a post-login target
    return redirectTo("/login", `?next=${encodeURIComponent(pathname)}`);
  }

  // Signed in — public.users is the source of truth for role / status / must_change_password
  // (JWT app_metadata can lag until the token refreshes; never trust it for authz, which is
  // why the verified claims are used for the id and for nothing else).
  //
  // The overlapped read above only counts now that the token has been authenticated, and only
  // for the id that came out of it. Anything else re-reads serially.
  const { data: profile } =
    speculativeProfile && !speculativeProfile.error && subjectHint === userId
      ? speculativeProfile
      : await supabase
          .from("users")
          .select("role, status, must_change_password, deleted_at")
          .eq("id", userId)
          .maybeSingle();

  const effectiveRole = profile?.role as UserRole | undefined;
  const mustChange = profile?.must_change_password === true;

  if (profile && (profile.status !== "active" || profile.deleted_at)) {
    await supabase.auth.signOut();
    return redirectTo("/login", "?error=inactive");
  }

  if (!effectiveRole) {
    if (pathname === "/login") return finish(response);
    return redirectTo("/login", "?error=no-profile");
  }

  const onAuthStep = startsWithAny(pathname, AUTH_STEP_PATHS);

  // MFA step-up (checklist §3): a verified factor exists but this session is still aal1.
  // getAuthenticatorAssuranceLevel() decodes the local session — no network call.
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  const hasVerifiedFactor = aal?.nextLevel === "aal2";
  const needsStepUp = hasVerifiedFactor && aal?.currentLevel !== "aal2";
  if (needsStepUp && !pathname.startsWith("/mfa") && pathname !== "/api/health") {
    return redirectTo("/mfa", `?next=${encodeURIComponent(pathname)}`);
  }

  // Forced password change (Hard rule §4.9) — applies to page loads, server-action POSTs and /api
  if (mustChange && !onAuthStep) {
    return redirectTo("/change-password");
  }

  // Required MFA enrollment for privileged roles (env MFA_REQUIRED_ROLES)
  if (mfaRequiredRoles().has(effectiveRole) && !hasVerifiedFactor && !onAuthStep && !pathname.startsWith("/security")) {
    return redirectTo("/security/mfa", "?required=1");
  }

  // Signed-in users shouldn't see /login or "/"
  if (pathname === "/login" || pathname === "/") {
    return redirectTo(ROLE_HOME[effectiveRole]);
  }

  // Role ↔ route-group check (also covers server-action POSTs to those paths)
  const required = roleForPath(pathname);
  if (required && required !== effectiveRole) {
    return redirectTo(ROLE_HOME[effectiveRole]);
  }

  return finish(response);
}
