/**
 * WHO IS CALLING — the only place these functions decide that.
 *
 * The rule this file exists to enforce: nothing the client says about itself is believed.
 * Not a role field in the JSON body, not a hostel id, and not the `role` / `app_metadata`
 * claims inside the JWT either. A JWT body is base64, not a fact: app_metadata is writable
 * by the service role and is a convenience mirror, so a stale or tampered copy must never be
 * what authorises a privileged write.
 *
 * So the sequence is:
 *   1. pull the bearer token off the Authorization header;
 *   2. hand it to GoTrue (auth.getUser(token)) — that VERIFIES the signature and expiry and
 *      returns the subject. A forged or expired token dies here, as does the project's anon
 *      key, which is a JWT but carries no user;
 *   3. read public.users for that verified id with the SERVICE client — RLS cannot hide or
 *      re-colour the row, so this is the authoritative role/status/tenant;
 *   4. apply the same gates the web app's assertRole() applies: active, not soft-deleted, no
 *      outstanding forced password change, and role ∈ the allowed set.
 *
 * Step 3 is the one that matters. The platform's own verify_jwt gate is satisfied by the anon
 * key alone, and every user of every role holds a valid JWT — being authenticated says nothing
 * about being allowed.
 */
import { audit } from "./audit.ts";
import { HttpError } from "./http.ts";
import { anonKey, serviceClient, serviceRoleKey } from "./supabase.ts";

export type UserRole = "super_admin" | "owner" | "manager" | "warden" | "student";

export interface Caller {
  id: string;
  role: UserRole;
  fullName: string;
  email: string | null;
  /** users.hostel_id — the tenant the account is bound to. null for super_admin. */
  hostelId: string | null;
  /** The verified bearer token, for RPCs that must run as this person. */
  jwt: string;
  ip: string | null;
  userAgent: string | null;
}

/** Read an env-derived key without letting a missing-config error masquerade as an auth failure. */
function keyOrNull(read: () => string): string | null {
  try {
    return read();
  } catch {
    return null;
  }
}

function bearerToken(req: Request): string {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization");
  const match = header?.match(/^Bearer\s+(.+)$/i);
  const token = match?.[1]?.trim();
  if (!token) throw new HttpError(401, "You are signed out. Please sign in again.");

  // Defence in depth: the anon key is published inside the APK and the service key must never
  // be on a device at all. Neither is a user session; refuse them by identity, not by luck.
  // (auth.getUser() would also refuse both — this makes the refusal deliberate and loggable.)
  if (token === keyOrNull(anonKey)) throw new HttpError(401, "You are signed out. Please sign in again.");
  if (token === keyOrNull(serviceRoleKey)) {
    console.error("[nivora] refused: service-role key presented as a user session");
    throw new HttpError(401, "You are signed out. Please sign in again.");
  }
  return token;
}

/**
 * Client IP for the audit trail and rate-limit keys.
 *
 * `x-forwarded-for` is a chain the client can seed: a caller may send their own value and the
 * platform proxy appends what it actually saw. Taking the FIRST hop would let anyone mint a
 * fresh identity per request; the LAST hop is the one written by the proxy in front of us.
 * Same reasoning as lib/rate-limit.ts getClientIp() with TRUSTED_PROXY_HOPS=1.
 */
function clientIp(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    const chain = xff.split(",").map((s) => s.trim()).filter(Boolean);
    if (chain.length) return chain[chain.length - 1].slice(0, 64);
  }
  return req.headers.get("x-real-ip")?.slice(0, 64) ?? null;
}

interface ProfileRow {
  id: string;
  role: UserRole;
  status: "active" | "inactive";
  hostel_id: string | null;
  full_name: string;
  email: string | null;
  must_change_password: boolean;
  deleted_at: string | null;
}

/**
 * Verify the bearer token and load the authoritative profile. Throws HttpError on every
 * failure path with a message that does not distinguish "no such user" from "wrong role"
 * any more than it has to.
 */
export async function requireCaller(req: Request, ...roles: UserRole[]): Promise<Caller> {
  const jwt = bearerToken(req);
  const admin = serviceClient();

  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  const authUser = authData?.user;
  if (authError || !authUser?.id) {
    throw new HttpError(401, "Your session has expired. Please sign in again.");
  }

  const { data, error } = await admin
    .from("users")
    .select("id, role, status, hostel_id, full_name, email, must_change_password, deleted_at")
    .eq("id", authUser.id)
    .maybeSingle();
  if (error) {
    console.error("[nivora] profile lookup failed:", error.message);
    throw new HttpError(500, "Could not verify your account. Please try again.");
  }
  const profile = data as ProfileRow | null;
  if (!profile) throw new HttpError(403, "Your account is not set up. Contact NIVORA support.");
  if (profile.status !== "active" || profile.deleted_at) throw new HttpError(403, "Your account is inactive.");
  if (profile.must_change_password) throw new HttpError(403, "Please set a new password before continuing.");

  const caller: Caller = {
    id: profile.id,
    role: profile.role,
    fullName: profile.full_name,
    email: profile.email,
    hostelId: profile.hostel_id,
    jwt,
    ip: clientIp(req),
    userAgent: req.headers.get("user-agent")?.slice(0, 300) ?? null,
  };

  if (roles.length && !roles.includes(profile.role)) {
    // Recorded before the throw: this is the point where a privileged operation is actually
    // refused, which is the event worth having in the trail (checklist §27).
    await audit("authz.denied", caller, {
      targetType: "edge_function",
      targetId: profile.id,
      hostelId: profile.hostel_id,
      meta: { actorRole: profile.role, requiredRoles: roles, surface: "edge_function" },
    });
    throw new HttpError(403, "You don't have permission to do that.");
  }

  return caller;
}
