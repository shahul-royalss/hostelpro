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
 *
 * 5. ASSURANCE. Since 2026-08-31 there is a fifth gate: a caller whose role is in
 *    MFA_REQUIRED_ROLES must have completed a second factor THIS SESSION. Until that date this
 *    file never read an assurance level, and an auditor signing in as super_admin with a
 *    password alone was issued a working token at aal1 and accepted here. See
 *    db/migrations/2026-08-31-mfa-enforcement.sql for the matching row-level-security gate;
 *    the two must agree, because the Flutter app reaches PostgREST directly for most reads and
 *    these functions only for the few privileged writes.
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
  /**
   * `users.email_verified_at` — when the holder proved control of [email] by opening a
   * confirmation link emailed to it, or null. NOT `auth.users.email_confirmed_at`, which every account-creation
   * path stamps at creation so the temporary password works and which therefore records
   * nothing about the person. See _shared/verification.ts.
   */
  emailVerifiedAt: string | null;
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
export function clientIp(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) {
    const chain = xff.split(",").map((s) => s.trim()).filter(Boolean);
    if (chain.length) return chain[chain.length - 1].slice(0, 64);
  }
  return req.headers.get("x-real-ip")?.slice(0, 64) ?? null;
}

export function clientUserAgent(req: Request): string | null {
  return req.headers.get("user-agent")?.slice(0, 300) ?? null;
}

/**
 * Roles that must carry a verified second factor.
 *
 * THREE COPIES OF THIS LIST EXIST and they must agree:
 *   · app.mfa_required_roles()          — Postgres, the authority for row-level security
 *   · MFA_REQUIRED_ROLES in .env.local  — read by lib/supabase/middleware.ts (the web app)
 *   · here                              — read by these Edge Functions
 *
 * An UNSET or EMPTY secret falls back to the default rather than to "nobody". That direction is
 * deliberate: a missing environment variable is the most likely deployment mistake, and the
 * version of this that reads `(Deno.env.get(...) ?? "").split(",")` would silently disable
 * enforcement everywhere the secret had not been pushed. Setting it to a real list narrows or
 * widens the set; there is no value that switches the check off by accident.
 */
const DEFAULT_MFA_REQUIRED_ROLES: UserRole[] = ["super_admin", "owner"];

function mfaRequiredRoles(): UserRole[] {
  const raw = Deno.env.get("MFA_REQUIRED_ROLES")?.trim();
  if (!raw) return DEFAULT_MFA_REQUIRED_ROLES;
  const parsed = raw.split(",").map((s) => s.trim()).filter(Boolean) as UserRole[];
  return parsed.length ? parsed : DEFAULT_MFA_REQUIRED_ROLES;
}

/**
 * The claims of a token whose signature has ALREADY been verified.
 *
 * This does not contradict the rule at the top of this file. That rule refuses `role` and
 * `app_metadata` because the service role can write them, so a stale or tampered mirror must
 * never authorise anything. `aal` is different in kind: GoTrue stamps it when it mints the
 * token, from the session's own step-up history, and nothing outside GoTrue can set it. Once
 * auth.getUser() has verified the signature and expiry, the payload bytes are authentic — and
 * this is only ever called AFTER that call has returned a user.
 *
 * Decoded through TextDecoder rather than atob() alone, because atob yields latin1 and a
 * multi-byte character anywhere in the payload would corrupt the JSON.
 */
function verifiedClaims(jwt: string): Record<string, unknown> | null {
  const payload = jwt.split(".")[1];
  if (!payload) return null;
  try {
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

interface ProfileRow {
  id: string;
  role: UserRole;
  status: "active" | "inactive";
  hostel_id: string | null;
  full_name: string;
  email: string | null;
  email_verified_at: string | null;
  must_change_password: boolean;
  deleted_at: string | null;
}

/**
 * Steps 1–3 above, plus the two gates that are true of every session: the account exists and
 * it is active. NOT the forced-password-change gate and NOT any role gate — those belong to
 * [requireCaller] and every existing endpoint still gets them.
 *
 * ── WHY THE PASSWORD-CHANGE GATE IS SEPARABLE ────────────────────────────────────────────
 *
 * The second factor is owed BEFORE the forced password change, not after: the web app routes
 * a fresh login to /mfa first and only then to /change-password (lib/actions/auth.ts). So a
 * user who has never signed in — every owner, every staff member, every student, on their
 * first day — holds must_change_password = true at the moment they are asked for their code.
 * Verifying that code through requireCaller() would answer 403 "Please set a new password
 * before continuing" to someone who cannot reach the password screen until the code is
 * accepted. That is a locked door with the key behind it.
 *
 * Lifting the gate here grants nothing: this function returns a verified identity, and the
 * only thing mobile-auth does with it is ask GoTrue to check a TOTP code for that same user.
 * `mustChangePassword` is returned rather than dropped so no future caller can forget it.
 */
export async function requireSession(req: Request): Promise<{ caller: Caller; mustChangePassword: boolean }> {
  const jwt = bearerToken(req);
  const admin = serviceClient();

  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  const authUser = authData?.user;
  if (authError || !authUser?.id) {
    throw new HttpError(401, "Your session has expired. Please sign in again.");
  }

  const { data, error } = await admin
    .from("users")
    .select("id, role, status, hostel_id, full_name, email, email_verified_at, must_change_password, deleted_at")
    .eq("id", authUser.id)
    .maybeSingle();
  if (error) {
    console.error("[nivora] profile lookup failed:", error.message);
    throw new HttpError(500, "Could not verify your account. Please try again.");
  }
  const profile = data as ProfileRow | null;
  if (!profile) throw new HttpError(403, "Your account is not set up. Contact NIVORA support.");
  if (profile.status !== "active" || profile.deleted_at) throw new HttpError(403, "Your account is inactive.");

  return {
    caller: {
      id: profile.id,
      role: profile.role,
      fullName: profile.full_name,
      email: profile.email,
      emailVerifiedAt: profile.email_verified_at,
      hostelId: profile.hostel_id,
      jwt,
      ip: clientIp(req),
      userAgent: clientUserAgent(req),
    },
    mustChangePassword: profile.must_change_password,
  };
}

/**
 * Verify the bearer token and load the authoritative profile. Throws HttpError on every
 * failure path with a message that does not distinguish "no such user" from "wrong role"
 * any more than it has to.
 */
export async function requireCaller(req: Request, ...roles: UserRole[]): Promise<Caller> {
  const { caller, mustChangePassword } = await requireSession(req);

  // Every privileged endpoint keeps this gate. It is lifted for exactly one caller —
  // mobile-auth's second-factor step — and the reason is spelled out on [requireSession].
  if (mustChangePassword) throw new HttpError(403, "Please set a new password before continuing.");

  if (roles.length && !roles.includes(caller.role)) {
    // Recorded before the throw: this is the point where a privileged operation is actually
    // refused, which is the event worth having in the trail (checklist §27).
    await audit("authz.denied", caller, {
      targetType: "edge_function",
      targetId: caller.id,
      hostelId: caller.hostelId,
      meta: { actorRole: caller.role, requiredRoles: roles, surface: "edge_function" },
    });
    throw new HttpError(403, "You don't have permission to do that.");
  }

  // Applied here and NOT in requireSession(), for the same reason the password gate is not
  // there: mobile-auth's second-factor step runs on requireSession(), and demanding aal2 in
  // order to reach the endpoint that grants aal2 is the locked door with the key behind it.
  await requireAssurance(caller);

  return caller;
}

/**
 * The second-factor gate, applied to the caller's ROLE rather than to the endpoint.
 *
 * An owner is an owner whichever function they call, so this does not consult the `roles`
 * argument: if the account is privileged it must have stepped up, full stop.
 *
 * THE THREE ARMS, and why the third exists. On the day this shipped the platform held exactly
 * one enrolled factor — an owner's, from 2026-08-23. The super admin had none and so did two of
 * the three owners. Refusing every privileged aal1 session outright would have locked the
 * platform's administrators out of their own platform, and enrolling a factor needs a working
 * session, so there would have been no way back in. A privileged account with NO factor is
 * therefore let through and told to enrol; the Flutter client routes it to the enrolment screen
 * (nivora_app/lib/core/auth/auth_controller.dart, mfaGate()).
 *
 * That third arm is a real hole and is audited every time it is used, so "how much longer is
 * this open, and for whom" is a query against public.audit_log rather than a guess. It closes
 * by itself, per account, the moment that account enrols.
 */
async function requireAssurance(caller: Caller): Promise<void> {
  if (!mfaRequiredRoles().includes(caller.role)) return;

  // caller.jwt is the token requireSession() already handed to auth.getUser(), so its signature
  // and expiry are verified before a single claim is read off it.
  // A missing or unreadable `aal` claim counts as aal1, never as a pass.
  const aal = verifiedClaims(caller.jwt)?.aal;
  if (aal === "aal2") return;

  // Only reached for a privileged caller who has not stepped up — so the extra round trip is
  // paid on the refusal path and on the shrinking grace path, never in the steady state.
  let hasVerifiedFactor: boolean;
  try {
    const { data, error } = await serviceClient().auth.admin.mfa.listFactors({ userId: caller.id });
    if (error) throw error;
    hasVerifiedFactor = (data?.factors ?? []).some((f) => f.status === "verified");
  } catch (e) {
    // Fail CLOSED. We know the caller is privileged and has not presented a code; what we
    // cannot determine is whether they own a factor at all. Refusing a privileged write on an
    // unanswerable question is safe here in a way it would not be on the client: enrolment runs
    // against GoTrue directly and does not pass through these functions, so nobody is stranded.
    console.error("[nivora] factor lookup failed:", e instanceof Error ? e.message : String(e));
    throw new HttpError(403, "Nivora could not confirm your two-factor status. Please sign in again.");
  }

  if (!hasVerifiedFactor) {
    await audit("authz.mfa_grace", caller, {
      targetType: "edge_function",
      targetId: caller.id,
      meta: { actorRole: caller.role, aal: typeof aal === "string" ? aal : null, surface: "edge_function" },
    });
    return;
  }

  // Deliberately NOT audited as "auth.mfa.failed": app.detect_suspicious_activity() raises a
  // high-severity bruteforce alert after three of those in ten minutes, and a session that
  // simply has not been stepped up yet is not an attack on the factor.
  await audit("authz.mfa_required", caller, {
    targetType: "edge_function",
    targetId: caller.id,
    meta: { actorRole: caller.role, aal: typeof aal === "string" ? aal : null, surface: "edge_function" },
  });
  throw new HttpError(403, "Enter your two-factor code before doing that.", {
    extra: { code: "mfa_required" },
  });
}
