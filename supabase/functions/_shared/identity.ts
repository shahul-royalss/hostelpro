/**
 * Self sign-up and external identities (docs/self-signup-onboarding-spec.md, Flow 2).
 *
 * The create-or-sign-in core that mobile-auth's google, facebook and truecaller actions share,
 * plus the provider checks for Facebook and Truecaller. Pure helpers (persona, synthetic address,
 * phone, appsecret_proof) are exported on their own so they can be unit-tested without a network.
 *
 * WHAT THE DATABASE ENFORCES WHATEVER THIS FILE DOES
 *   - svc_create_self_signup_profile is service-role only and creates role owner or student only;
 *     users_self_signup_guard refuses any other self-created row (2026-10-25 migration).
 *   - external_identities is service-role only; app.guard_external_identity_link admits owner and
 *     student accounts only, so a Facebook or Truecaller profile can never be linked to staff.
 *
 * SECRETS: FACEBOOK_APP_ID, FACEBOOK_APP_SECRET, TRUECALLER_CLIENT_ID (Edge Function secrets only).
 * Optional overrides: TRUECALLER_TOKEN_URL, TRUECALLER_USERINFO_URL, FACEBOOK_GRAPH_VERSION.
 */
import { deleteAuthUser } from "./accounts.ts";
import { HttpError } from "./http.ts";
import { anonKey, projectUrl, serviceClient } from "./supabase.ts";

/** Mirrors app.email_is_reachable() and _shared/verification.ts. Never receives mail. */
export const SYNTHETIC_IDENTITY_DOMAIN = "identity.apnivaas.invalid";

export type Persona = "owner" | "tenant" | "staff";
export type SignupSource = "self_google" | "self_facebook" | "self_truecaller" | "self_email";
/** What svc_create_self_signup_profile takes. "staff" creates a staff applicant (role student, no access). */
export type SignupRole = "owner" | "student" | "staff";
export type ExternalProvider = "facebook" | "truecaller";

export const STAFF_ROLES = new Set(["super_admin", "manager", "warden"]);

/** Codes the app branches on. The message is still what it shows. */
export const ERROR_CODES = {
  noAccount: "no_account",
  staffRefused: "staff_refused",
  inactive: "inactive",
  phoneInUse: "phone_in_use",
  notConfigured: "not_configured",
  alreadyLinked: "already_linked",
  emailInUse: "email_in_use",
} as const;

export const NO_ACCOUNT_MESSAGE = "No account yet — create one";
export const BAD_PERSONA_MESSAGE = "Choose Owner, Tenant or Staff to create an account.";
export const EMAIL_IN_USE_MESSAGE = "An account already uses this email — sign in, or reset your password";
export const INACTIVE_MESSAGE = "This account has been deactivated. Contact your hostel owner.";
export const NO_PROFILE_MESSAGE = "Your account isn't set up yet. Contact your administrator.";
export const SIGNUP_UNAVAILABLE = "Sign-up is temporarily unavailable. Please try again in a minute.";

/**
 * The persona hint. Absent, null or "" means "sign in only". Anything else must be on the
 * allowlist; a value that is present and not on it is refused rather than ignored, so a client
 * bug cannot silently turn a sign-up into a sign-in refusal.
 */
export function parsePersona(value: unknown): Persona | null {
  if (value === undefined || value === null || value === "") return null;
  if (value === "owner" || value === "tenant" || value === "staff") return value;
  throw new HttpError(400, BAD_PERSONA_MESSAGE);
}

/** The persona maps onto the sign-up role. Never "manager", "warden" or "super_admin": staff start as applicants. */
export function personaRole(persona: Persona): SignupRole {
  return persona === "owner" ? "owner" : persona === "staff" ? "staff" : "student";
}

/** Mirrors apnivaas_app/lib/features/auth/password_policy.dart, in its order and words. */
export function passwordProblem(p: string): string | null {
  if (p.length > 200) return "That password is too long";
  if (p.length < 8) return "Use at least 8 characters";
  if (!/[a-z]/.test(p)) return "Include at least one letter";
  if (!/\d/.test(p)) return "Include at least one number";
  if (!/[A-Z]/.test(p)) return "Include at least one capital letter";
  if (!/[^A-Za-z0-9\s]/.test(p)) return "Include at least one symbol, like ! or @";
  return null;
}

/** `fb-<id>@identity.apnivaas.invalid` / `tc-<sub>@identity.apnivaas.invalid`. */
export function syntheticEmail(provider: ExternalProvider, subject: string): string {
  const safe = subject.toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 60);
  if (!safe) throw new HttpError(400, "Could not read the sign-in response.");
  return `${provider === "facebook" ? "fb" : "tc"}-${safe}@${SYNTHETIC_IDENTITY_DOMAIN}`;
}

/** An Indian mobile as 10 digits, or null. Accepts "+91 98765 43210", "919876543210", "09876543210". */
export function indianMobile(raw: unknown): string | null {
  if (typeof raw !== "string" && typeof raw !== "number") return null;
  let digits = String(raw).replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("91")) digits = digits.slice(2);
  else if (digits.length === 11 && digits.startsWith("0")) digits = digits.slice(1);
  return /^[6-9][0-9]{9}$/.test(digits) ? digits : null;
}

/** A display name the profile function accepts (2–80 characters), or the fallback. */
export function displayName(...candidates: unknown[]): string {
  for (const c of candidates) {
    if (typeof c !== "string") continue;
    const cleaned = c.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
    if (cleaned.length >= 2) return cleaned;
  }
  return "New member";
}

function randomPassword(): string {
  // Unusable by design: 48 random bytes, never shown, never stored anywhere but GoTrue's hash.
  const bytes = crypto.getRandomValues(new Uint8Array(48));
  return btoa(String.fromCharCode(...bytes));
}

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(message)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Graph API appsecret_proof: HMAC-SHA256(access_token, app_secret), lowercase hex. */
export function appSecretProof(accessToken: string, appSecret: string): Promise<string> {
  return hmacSha256Hex(appSecret, accessToken);
}

function env(name: string): string | null {
  const v = (Deno.env.get(name) ?? "").trim();
  return v.length > 0 ? v : null;
}

/** "We could not ask", never "the answer was no". */
export function providerUnavailable(message: string): HttpError {
  return new HttpError(503, message, { extra: { retryAfterSeconds: 60 }, headers: { "Retry-After": "60" } });
}

// ═══ ACCOUNTS ═══════════════════════════════════════════════════════════════════════════════

export interface LoginAccount {
  user_id: string;
  email?: string | null;
  role: string | null;
  status: string | null;
  deleted_at: string | null;
}

/** login_account_for_email (2026-10-17): every live auth user with this address, with its profile. */
export async function accountsForEmail(email: string, unavailableMessage: string): Promise<LoginAccount[]> {
  const { data, error } = await serviceClient().rpc("login_account_for_email", { p_email: email });
  if (error) {
    console.error("[apnivaas] account lookup failed:", error.message);
    throw providerUnavailable(unavailableMessage);
  }
  return (Array.isArray(data) ? data : []) as LoginAccount[];
}

/** svc_login_account_for_external: the account a (provider, subject) pair is linked to, or null. */
export async function accountForExternal(
  provider: ExternalProvider,
  subject: string,
  unavailableMessage: string,
): Promise<LoginAccount | null> {
  const { data, error } = await serviceClient().rpc("svc_login_account_for_external", {
    p_provider: provider,
    p_subject: subject,
  });
  if (error) {
    console.error("[apnivaas] external identity lookup failed:", error.message);
    throw providerUnavailable(unavailableMessage);
  }
  const rows = (Array.isArray(data) ? data : []) as LoginAccount[];
  return rows[0] ?? null;
}

/**
 * The same refusals the Google path has always made, in the same words. Throws; returns
 * nothing. `staffMessage` names the provider.
 */
export async function assertMaySignIn(account: LoginAccount, staffMessage: string, unavailableMessage: string): Promise<void> {
  if (!account.role) throw new HttpError(403, NO_PROFILE_MESSAGE);
  if (!(await externalSignInAllowed(account, unavailableMessage))) {
    throw new HttpError(403, staffMessage, { extra: { code: ERROR_CODES.staffRefused } });
  }
  if (account.deleted_at || account.status !== "active") {
    throw new HttpError(403, INACTIVE_MESSAGE, { extra: { code: ERROR_CODES.inactive } });
  }
}

/**
 * Social sign-in: owners and tenants yes; super_admin never; a manager/warden only when the
 * account was self-created (svc_external_signin_allowed, the same rule as the identities guard).
 */
export async function externalSignInAllowed(account: LoginAccount, unavailableMessage: string): Promise<boolean> {
  if (!account.role || !STAFF_ROLES.has(account.role)) return true;
  if (account.role === "super_admin") return false;
  const { data, error } = await serviceClient().rpc("svc_external_signin_allowed", { p_user: account.user_id });
  if (error) {
    console.error("[apnivaas] staff sign-in check failed:", error.message);
    throw providerUnavailable(unavailableMessage);
  }
  return data === true;
}

/**
 * A provider just matched an existing account by address. If it is a self_email account whose
 * address was never verified, its password and sessions go (svc_secure_unverified_account), so
 * whoever typed that password cannot keep a way in. `proved`: the provider verified the address.
 */
export async function secureUnverifiedAccount(userId: string, proved: boolean, unavailableMessage: string): Promise<void> {
  const { error } = await serviceClient().rpc("svc_secure_unverified_account", { p_user: userId, p_proved: proved });
  if (error) {
    console.error("[apnivaas] could not secure an unverified account:", error.message);
    throw providerUnavailable(unavailableMessage);
  }
}

/** Link (provider, subject) to the account. false = that account already carries another profile of the provider. */
export async function linkExternalIdentity(provider: ExternalProvider, subject: string, userId: string): Promise<boolean> {
  const { data, error } = await serviceClient().rpc("svc_link_external_identity", {
    p_provider: provider,
    p_subject: subject,
    p_user: userId,
  });
  if (error) {
    console.error("[apnivaas] could not link an external identity:", error.message);
    // The guard trigger raises for staff; anything else is ours.
    if (/owner and tenant|staff|not allowed/i.test(error.message ?? "")) {
      throw new HttpError(403, "This sign-in can't be used with this account.");
    }
    throw providerUnavailable(SIGNUP_UNAVAILABLE);
  }
  return data === true;
}

export class AccountExistsError extends Error {
  constructor() {
    super("account exists");
    this.name = "AccountExistsError";
  }
}

/**
 * Create the GoTrue user (address confirmed, random unusable password) and its profile through
 * svc_create_self_signup_profile. If the profile is refused, the GoTrue user is deleted again
 * so the address is not left taken. Throws AccountExistsError when the address is already
 * registered (two sign-ups racing, or a lookup that missed): the caller re-runs its lookup.
 */
export async function createSelfSignupAccount(args: {
  email: string;
  fullName: string;
  phone: string | null;
  role: SignupRole;
  source: SignupSource;
  /** signup_password only; otherwise an unusable random one. */
  password?: string;
  city?: string | null;
  pincode?: string | null;
}): Promise<string> {
  const admin = serviceClient();
  const { data, error } = await admin.auth.admin.createUser({
    email: args.email,
    password: args.password ?? randomPassword(),
    email_confirm: true,
    user_metadata: {},
  });
  if (error || !data?.user?.id) {
    const msg = error?.message ?? "";
    const code = (error as { code?: string } | null)?.code ?? "";
    if (code === "email_exists" || /already been registered|already registered|exists/i.test(msg)) {
      throw new AccountExistsError();
    }
    if (code === "weak_password" || /password/i.test(msg)) {
      throw new HttpError(400, "Choose a stronger password.", { fieldErrors: { password: ["Choose a stronger password."] } });
    }
    console.error("[apnivaas] self sign-up createUser failed:", msg.slice(0, 200));
    throw providerUnavailable(SIGNUP_UNAVAILABLE);
  }
  const userId = data.user.id;

  const { error: profileError } = await admin.rpc("svc_create_self_signup_profile", {
    p_user: userId,
    p_role: args.role,
    p_full_name: args.fullName,
    p_phone: args.phone,
    p_email: args.email,
    p_source: args.source,
    p_city: args.city ?? null,
    p_pincode: args.pincode ?? null,
  });
  if (profileError) {
    const rollback = await deleteAuthUser(userId);
    console.error(
      "[apnivaas] self sign-up profile refused:",
      (profileError.message ?? "").slice(0, 200),
      rollback.deleted ? "(login removed)" : `(ORPHANED auth user ${userId})`,
    );
    if (profileError.code === "22023" && profileError.message) throw new HttpError(400, profileError.message);
    throw providerUnavailable(SIGNUP_UNAVAILABLE);
  }
  return userId;
}

// ═══ SESSIONS WITHOUT OIDC (Facebook, Truecaller) ═══════════════════════════════════════════

export interface MintedSession {
  access_token: string;
  refresh_token: string;
  expires_at?: number;
  user_id: string;
}

/**
 * A session for an account whose identity this function has already proved, without an
 * OIDC provider GoTrue knows about: admin generateLink(magiclink) creates a one-time token for
 * the account's own email identity, and the token hash is verified here, server side. Nothing
 * is emailed and the link never leaves this function.
 */
export async function mintSessionForEmail(email: string, unavailableMessage: string): Promise<MintedSession> {
  const { data, error } = await serviceClient().auth.admin.generateLink({ type: "magiclink", email });
  const hashed = (data?.properties as { hashed_token?: string } | undefined)?.hashed_token;
  if (error || !hashed) {
    console.error("[apnivaas] generateLink failed:", (error?.message ?? "no token").slice(0, 200));
    throw providerUnavailable(unavailableMessage);
  }
  let res: Response;
  try {
    res = await fetch(`${projectUrl()}/auth/v1/verify`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: anonKey(), Authorization: `Bearer ${anonKey()}` },
      body: JSON.stringify({ type: "magiclink", token_hash: hashed }),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (e) {
    console.error("[apnivaas] verify unreachable:", e instanceof Error ? e.message : String(e));
    throw providerUnavailable(unavailableMessage);
  }
  let body: Record<string, unknown> = {};
  try {
    body = (await res.json()) as Record<string, unknown>;
  } catch { /* handled below */ }
  const access = body["access_token"];
  const refresh = body["refresh_token"];
  const userId = String((body["user"] as Record<string, unknown> | undefined)?.["id"] ?? "");
  if (res.status !== 200 || typeof access !== "string" || typeof refresh !== "string" || !userId) {
    console.error(`[apnivaas] magic-link verify refused: ${res.status} ${JSON.stringify(body).slice(0, 200)}`);
    throw providerUnavailable(unavailableMessage);
  }
  return {
    access_token: access,
    refresh_token: refresh,
    expires_at: typeof body["expires_at"] === "number" ? body["expires_at"] : undefined,
    user_id: userId,
  };
}

// ═══ FACEBOOK ═══════════════════════════════════════════════════════════════════════════════

export const FACEBOOK_NOT_SET_UP = "Facebook sign-in is not set up yet";
export const FACEBOOK_UNAVAILABLE = "Facebook sign-in is temporarily unavailable. Please try again in a minute.";
export const FACEBOOK_FAILED = "Facebook sign-in didn't go through. Please try again.";

export interface FacebookProfile {
  id: string;
  name: string | null;
  email: string | null;
}

/**
 * Facebook is "set up" once FACEBOOK_APP_ID exists. The app secret is optional: with it the token
 * is checked through debug_token plus appsecret_proof; without it, through Graph's /app endpoint,
 * which names the app a user token was issued to (see verifyFacebookToken).
 */
export function facebookConfig(): { appId: string; appSecret: string | null } | null {
  const appId = env("FACEBOOK_APP_ID");
  if (!appId || !/^[0-9]{5,30}$/.test(appId)) return null;
  return { appId, appSecret: env("FACEBOOK_APP_SECRET") ?? null };
}

async function getJson(url: string, init: RequestInit, unavailable: string): Promise<{ status: number; body: Record<string, unknown> }> {
  let res: Response;
  try {
    res = await fetch(url, { ...init, signal: AbortSignal.timeout(8_000) });
  } catch (e) {
    console.error("[apnivaas] provider unreachable:", e instanceof Error ? e.message : String(e));
    throw providerUnavailable(unavailable);
  }
  let body: Record<string, unknown> = {};
  try {
    const parsed = await res.json();
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) body = parsed as Record<string, unknown>;
  } catch { /* status decides */ }
  if (res.status >= 500 || res.status === 429) throw providerUnavailable(unavailable);
  return { status: res.status, body };
}

/**
 * Proves the token was issued to OUR app before trusting the profile it unlocks; a token minted
 * for any other app is refused (token substitution).
 * - With the app secret: debug_token with the app access token (is_valid, app_id ours), then /me
 *   with an appsecret_proof; the two user ids must agree.
 * - Without it: /app with the user token must name our app id, then /me with the same token.
 *   Equivalent for this check; it only fails closed if "Require app secret" is switched on.
 */
export async function verifyFacebookToken(accessToken: string): Promise<FacebookProfile> {
  const cfg = facebookConfig();
  if (!cfg) throw providerUnavailable(FACEBOOK_NOT_SET_UP);
  const graph = `https://graph.facebook.com/${env("FACEBOOK_GRAPH_VERSION") ?? "v19.0"}`;
  const token = encodeURIComponent(accessToken);

  let userId: string | null = null;
  let meUrl: string;
  if (cfg.appSecret) {
    const debug = await getJson(
      `${graph}/debug_token?input_token=${token}&access_token=${encodeURIComponent(`${cfg.appId}|${cfg.appSecret}`)}`,
      { method: "GET" },
      FACEBOOK_UNAVAILABLE,
    );
    const d = (debug.body["data"] ?? {}) as Record<string, unknown>;
    if (debug.status !== 200 || d["is_valid"] !== true || String(d["app_id"] ?? "") !== cfg.appId || !d["user_id"]) {
      throw new HttpError(400, FACEBOOK_FAILED);
    }
    userId = String(d["user_id"]);
    meUrl = `${graph}/me?fields=id,name,email&access_token=${token}&appsecret_proof=${await appSecretProof(accessToken, cfg.appSecret)}`;
  } else {
    const app = await getJson(`${graph}/app?access_token=${token}`, { method: "GET" }, FACEBOOK_UNAVAILABLE);
    if (app.status !== 200 || String(app.body["id"] ?? "") !== cfg.appId) {
      throw new HttpError(400, FACEBOOK_FAILED);
    }
    meUrl = `${graph}/me?fields=id,name,email&access_token=${token}`;
  }

  const me = await getJson(meUrl, { method: "GET" }, FACEBOOK_UNAVAILABLE);
  const meId = String(me.body["id"] ?? "");
  if (userId === null) userId = meId;
  if (me.status !== 200 || meId !== userId || !/^[0-9]{1,40}$/.test(userId)) {
    throw new HttpError(400, FACEBOOK_FAILED);
  }
  const email = typeof me.body["email"] === "string" ? me.body["email"].trim().toLowerCase() : "";
  return {
    id: userId,
    name: typeof me.body["name"] === "string" ? me.body["name"] : null,
    email: email && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 200 ? email : null,
  };
}

// ═══ TRUECALLER ═════════════════════════════════════════════════════════════════════════════

export const TRUECALLER_NOT_SET_UP = "Truecaller sign-in is not set up yet";
export const TRUECALLER_UNAVAILABLE = "Truecaller sign-in is temporarily unavailable. Please try again in a minute.";
export const TRUECALLER_FAILED = "Truecaller sign-in didn't go through. Please try again.";
export const PHONE_IN_USE_MESSAGE = "An account already uses this number — sign in with your password";

export interface TruecallerProfile {
  sub: string;
  phone: string | null;
  name: string | null;
}

export function truecallerClientId(): string | null {
  return env("TRUECALLER_CLIENT_ID");
}

/** RFC 7636: 43–128 characters of [A-Za-z0-9-._~]. */
export function isPkceVerifier(v: unknown): v is string {
  return typeof v === "string" && /^[A-Za-z0-9\-._~]{43,128}$/.test(v);
}

/** Authorization code + PKCE verifier → access token → userinfo (verified phone and name). */
export async function verifyTruecallerCode(code: string, codeVerifier: string): Promise<TruecallerProfile> {
  const clientId = truecallerClientId();
  if (!clientId) throw providerUnavailable(TRUECALLER_NOT_SET_UP);
  const tokenUrl = env("TRUECALLER_TOKEN_URL") ?? "https://oauth-account-noneu.truecaller.com/v1/token";
  const userinfoUrl = env("TRUECALLER_USERINFO_URL") ?? "https://oauth-account-noneu.truecaller.com/v1/userinfo";

  const token = await getJson(
    tokenUrl,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        client_id: clientId,
        code,
        code_verifier: codeVerifier,
      }).toString(),
    },
    TRUECALLER_UNAVAILABLE,
  );
  const accessToken = token.body["access_token"];
  if (token.status !== 200 || typeof accessToken !== "string" || !accessToken) {
    throw new HttpError(400, TRUECALLER_FAILED);
  }

  const info = await getJson(userinfoUrl, { method: "GET", headers: { Authorization: `Bearer ${accessToken}` } }, TRUECALLER_UNAVAILABLE);
  const sub = typeof info.body["sub"] === "string" || typeof info.body["sub"] === "number" ? String(info.body["sub"]) : "";
  if (info.status !== 200 || !sub || sub.length > 128) throw new HttpError(400, TRUECALLER_FAILED);
  const given = typeof info.body["given_name"] === "string" ? info.body["given_name"] : "";
  const family = typeof info.body["family_name"] === "string" ? info.body["family_name"] : "";
  return {
    sub,
    phone: indianMobile(info.body["phone_number"]),
    name: `${given} ${family}`.trim() || (typeof info.body["name"] === "string" ? info.body["name"] : null),
  };
}

/** svc_phone_in_use: does any live account (profile or login) already use this number? */
export async function phoneInUse(phone: string): Promise<boolean> {
  const { data, error } = await serviceClient().rpc("svc_phone_in_use", { p_phone: phone });
  if (error) {
    console.error("[apnivaas] phone lookup failed:", error.message);
    throw providerUnavailable(TRUECALLER_UNAVAILABLE);
  }
  return data === true;
}
