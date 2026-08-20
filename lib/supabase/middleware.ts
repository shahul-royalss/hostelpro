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
 */
export async function updateSession(request: NextRequest) {
  const nonce = generateNonce();
  const csp = buildCsp(nonce);
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

  // IMPORTANT: do not add logic between createServerClient and getUser()
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;

  if (!user) {
    if (startsWithAny(pathname, PUBLIC_PATHS) || pathname === "/") {
      return finish(response);
    }
    // Only same-origin relative paths are ever used as a post-login target
    return redirectTo("/login", `?next=${encodeURIComponent(pathname)}`);
  }

  // Signed in — public.users is the source of truth for role / status / must_change_password
  // (JWT app_metadata can lag until the token refreshes; never trust it for authz).
  const { data: profile } = await supabase
    .from("users")
    .select("role, status, must_change_password, deleted_at")
    .eq("id", user.id)
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
