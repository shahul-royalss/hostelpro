import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { ROLE_HOME, roleForPath, type UserRole } from "@/lib/roles";

const PUBLIC_PATHS = ["/login", "/manifest.webmanifest", "/icons", "/api/health"];

function isPublic(pathname: string) {
  return PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

/**
 * Runs on every request (see /middleware.ts):
 *  1. refresh the Supabase session cookie
 *  2. redirect unauthenticated users to /login
 *  3. force password change on first login
 *  4. make sure the role matches the route group (/owner, /warden, …)
 * Hostel-scoping and subscription write-gating happen in RLS + server actions.
 */
export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

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
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
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
    if (isPublic(pathname) || pathname === "/") {
      // "/" is handled by the page (redirects to /login)
      return response;
    }
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  // Signed in — the public.users row is the source of truth for role / status /
  // must_change_password (JWT app_metadata can lag behind until the token refreshes).
  const { data: profile } = await supabase
    .from("users")
    .select("role, status, must_change_password, deleted_at")
    .eq("id", user.id)
    .maybeSingle();

  const effectiveRole = profile?.role as UserRole | undefined;
  const mustChange = profile?.must_change_password === true;

  if (profile && (profile.status !== "active" || profile.deleted_at)) {
    await supabase.auth.signOut();
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.search = "?error=inactive";
    return NextResponse.redirect(url);
  }

  if (!effectiveRole) {
    // Auth user without a profile row — treat as signed out
    if (pathname === "/login") return response;
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("error", "no-profile");
    return NextResponse.redirect(url);
  }

  // Forced password change (Hard rule §4.9)
  if (mustChange && pathname !== "/change-password" && !pathname.startsWith("/api/")) {
    const url = request.nextUrl.clone();
    url.pathname = "/change-password";
    url.search = "";
    return NextResponse.redirect(url);
  }

  // Signed-in users shouldn't see /login or "/"
  if (pathname === "/login" || pathname === "/") {
    const url = request.nextUrl.clone();
    url.pathname = ROLE_HOME[effectiveRole];
    url.search = "";
    return NextResponse.redirect(url);
  }

  // Role ↔ route-group check
  const required = roleForPath(pathname);
  if (required && required !== effectiveRole) {
    const url = request.nextUrl.clone();
    url.pathname = ROLE_HOME[effectiveRole];
    url.search = "";
    return NextResponse.redirect(url);
  }

  return response;
}
