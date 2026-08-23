import "server-only";
import { cache } from "react";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ROLE_HOME, type UserRole } from "@/lib/roles";
import { audit } from "@/lib/audit";
import type { HostelRow, SubscriptionStatus, UserRow } from "@/lib/types";

export const ACTIVE_HOSTEL_COOKIE = "hp_active_hostel";

export interface SessionUser extends UserRow {
  authEmail: string | null;
}

export interface HostelContext {
  hostel: HostelRow;
  /** live subscription state (computed from end_date) */
  subscriptionState: SubscriptionStatus;
  daysLeft: number | null;
  /** false when subscription expired or hostel not active → all writes blocked */
  writable: boolean;
  /** all hostels this owner can switch between (owner only; others = [hostel]) */
  hostels: Pick<HostelRow, "id" | "name" | "status">[];
}

/* ───────────────────────── Session ───────────────────────── */

/**
 * The `sub` claim of an access token, WITHOUT verifying its signature.
 *
 * A scheduling hint and nothing else — see getSessionUser(). Deliberately duplicated in
 * lib/supabase/middleware.ts, which runs in the Edge runtime and cannot import this module.
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
 * Both halves of session resolution, ISSUED TOGETHER and handed back still in flight.
 *
 * Kept separate from getSessionUser() so that a caller which only needs the profile row can
 * have it without waiting for the Auth server. Measured against the live project: getUser()
 * ~200ms, the profile read ~113ms — so the profile lands ~90ms early and that head start was
 * previously thrown away. getHostelContext() is the caller that spends it.
 *
 * cache() makes this once per request: the promises are shared, never re-issued.
 */
const sessionProbe = cache(async () => {
  const supabase = await createClient();

  // getSession() decodes the session out of the cookie locally; it reaches the network only
  // when the access token has expired and has to be refreshed.
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const subjectHint = unverifiedSubject(session?.access_token);

  // Both requests go on the wire here. A PostgREST builder is lazy — it is Promise.resolve()
  // that actually dispatches it, exactly as the previous Promise.all([...]) did.
  const verified = supabase.auth.getUser();
  const speculative = subjectHint
    ? Promise.resolve(supabase.from("users").select("*").eq("id", subjectHint).maybeSingle())
    : Promise.resolve(null);

  // Whichever of the two a given caller does not await must not surface as an unhandled
  // rejection; the caller that does await it still sees the real failure.
  verified.catch(() => {});
  speculative.catch(() => {});

  return { supabase, subjectHint, verified, speculative };
});

/**
 * Current signed-in user + profile row. Cached per request.
 * Returns null when signed out.
 */
export const getSessionUser = cache(async (): Promise<SessionUser | null> => {
  const { supabase, subjectHint, verified, speculative } = await sessionProbe();

  // getUser() is an HTTP round trip to the Auth server; the profile read is a second one to
  // PostgREST. Neither needs the other's result — only the same user id — so they run together
  // instead of in series.
  //
  // SECURITY: `subjectHint` comes from an UNVERIFIED token and is used as nothing more than a
  // cache key for a read that is discarded unless getUser() independently returns a user with
  // exactly that id. Nothing is trusted that was not trusted before:
  //  • a forged/tampered token yields no row — PostgREST verifies the JWT itself and the self
  //    branch of the users policy is `id = auth.uid()`, so the signature has to hold;
  //  • a validly signed but *revoked* session is still rejected, because getUser() is the call
  //    that asks the Auth server whether the session is alive, and its answer is what gates this;
  //  • a missing hint, a mismatch or a query error falls through to the original serial read.
  const [
    {
      data: { user },
    },
    speculativeProfile,
  ] = await Promise.all([verified, speculative]);
  if (!user) return null;

  const { data: profile } =
    speculativeProfile && !speculativeProfile.error && subjectHint === user.id
      ? speculativeProfile
      : await supabase.from("users").select("*").eq("id", user.id).maybeSingle();

  if (!profile) return null;
  return { ...(profile as UserRow), authEmail: user.email ?? null };
});

/**
 * The speculative profile row, available ~90ms before getUser() answers.
 *
 * THIS IS NOT AN AUTHORIZATION RESULT, and nothing may be returned to a caller on its strength.
 * Its only job is to decide which follow-up reads to *start* early — see getHostelContext(),
 * which discards everything derived from it unless getSessionUser() independently confirms the
 * same account. The row is itself RLS-scoped (the self branch of the users policy is
 * `id = auth.uid()`, and PostgREST verifies the JWT signature), so the worst case is a row
 * belonging to a validly signed session that getUser() then rejects as revoked — in which case
 * the work built on it is thrown away and the request is bounced to /login exactly as before.
 */
const provisionalProfile = cache(async (): Promise<UserRow | null> => {
  try {
    const { subjectHint, speculative } = await sessionProbe();
    const res = await speculative;
    if (!res || res.error || !res.data) return null;
    const row = res.data as UserRow;
    return row.id === subjectHint ? row : null;
  } catch {
    return null; // no head start; the verified path below still runs in full
  }
});

/**
 * True when the session has completed TOTP step-up (or the account has no factor).
 * Decodes the local session — no network call.
 *
 * Cached per request: a layout guard and its page guard both call requireUser(), and AAL
 * cannot change part-way through a single request.
 */
const mfaSatisfied = cache(async (): Promise<boolean> => {
  try {
    const supabase = await createClient();
    const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (!data) return true;
    return !(data.nextLevel === "aal2" && data.currentLevel !== "aal2");
  } catch {
    return true; // never lock the app out on a decode failure
  }
});

/**
 * Redirects to /login when signed out, and enforces the two "half-authenticated"
 * gates — forced password change (§4.9) and TOTP step-up.
 *
 * These are ALSO enforced in middleware. They are duplicated here deliberately: middleware
 * runs only on paths matched by a hand-written regex, and an audit found that a matcher
 * excluding `*.png` let any route ending in an image extension skip every middleware gate
 * while still executing Server Actions. An authentication control that exists in exactly
 * one place, keyed off a regex, is one typo away from being bypassable — so every Server
 * Component and Server Action re-checks it here, independently of routing.
 */
export async function requireUser(): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  if (user.status !== "active" || user.deleted_at) {
    redirect("/login?error=inactive");
  }
  if (!(await mfaSatisfied())) redirect("/mfa");
  if (user.must_change_password) redirect("/change-password");
  return user;
}

/**
 * Guard for pages + server actions.
 * Redirects to the user's own home if the role doesn't match.
 */
export async function requireRole(...roles: UserRole[]): Promise<SessionUser> {
  const user = await requireUser();
  if (!roles.includes(user.role)) {
    // Log BEFORE redirect(): redirect() throws to unwind, so anything after it never runs.
    await denied(user, roles, "page");
    redirect(ROLE_HOME[user.role]);
  }
  return user;
}

/**
 * Record an authorization failure (checklist §27).
 *
 * These are the points where a privileged operation is actually refused, so this is the
 * authoritative denial record. Note the deliberate gap: middleware also bounces a session
 * away from another role's route group, and that redirect is NOT logged here — it runs in
 * the Edge runtime, where reaching for the service-role client on every request would be
 * both slow and the wrong place to put that credential. A middleware bounce is navigation
 * hygiene; an attempt to actually execute the operation still lands here and is recorded.
 */
async function denied(user: SessionUser, roles: UserRole[], surface: "page" | "action") {
  await audit("authz.denied", {
    targetType: surface,
    targetId: user.id,
    hostelId: user.hostel_id,
    meta: { actorRole: user.role, requiredRoles: roles, surface },
  });
}

/**
 * Non-redirecting variant for server actions that return ActionResult.
 * Applies the same half-authenticated gates as requireUser() (see the note there) so a
 * Server Action can never run for a session that still owes a password change or a
 * second factor, regardless of which URL it was posted to.
 */
export async function assertRole(...roles: UserRole[]): Promise<SessionUser> {
  const user = await getSessionUser();
  if (!user) throw new PermissionError("You are signed out. Please sign in again.");
  if (user.status !== "active" || user.deleted_at) throw new PermissionError("Your account is inactive.");
  if (user.must_change_password) throw new PermissionError("Please set a new password before continuing.");
  if (!(await mfaSatisfied())) throw new PermissionError("Two-factor verification is required before continuing.");
  if (!roles.includes(user.role)) {
    await denied(user, roles, "action");
    throw new PermissionError("You don't have permission to do that.");
  }
  return user;
}

export class PermissionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PermissionError";
  }
}

/* ───────────────────────── Hostel context ───────────────────────── */

/**
 * Resolve the hostel a given profile row is bound to (Hard rule §3).
 *  • manager / warden / student → users.hostel_id
 *  • owner → active-hostel cookie (validated) or users.hostel_id or first owned hostel
 *  • super_admin → must pass hostelId explicitly (monitoring views)
 *
 * Takes the profile row as an argument instead of resolving the session itself, so that
 * getHostelContext() can decide when to call it. Not exported: every caller must go through
 * getHostelContext(), which is what enforces that the row has been verified.
 */
async function buildHostelContext(user: UserRow, explicitHostelId?: string): Promise<HostelContext | null> {
  const supabase = await createClient();

  let hostelId: string | null = null;
  let hostels: Pick<HostelRow, "id" | "name" | "status">[] = [];
  /** set on the owner branch, where the full row already came back with the list */
  let ownedHostel: HostelRow | null = null;

  if (user.role === "super_admin") {
    if (!explicitHostelId) return null;
    hostelId = explicitHostelId;
  } else if (user.role === "owner") {
    // select("*") rather than three columns: the previous version read id/name/status here and
    // then re-read the very same row in full a moment later. One round trip, whole row, and the
    // second hostels query below disappears for owners.
    const { data: owned } = await supabase
      .from("hostels")
      .select("*")
      .eq("owner_user_id", user.id)
      .order("created_at", { ascending: true });
    const all = (owned ?? []) as HostelRow[];
    if (all.length === 0) return null;
    hostels = all.map((h) => ({ id: h.id, name: h.name, status: h.status }));

    const cookieStore = await cookies();
    const preferred = explicitHostelId ?? cookieStore.get(ACTIVE_HOSTEL_COOKIE)?.value ?? user.hostel_id;
    // unchanged rule: a cookie naming a hostel this owner does not own falls back to the first
    // owned one, so the cookie can never widen access beyond `owner_user_id = user.id`
    ownedHostel = all.find((h) => h.id === preferred) ?? all[0];
    hostelId = ownedHostel.id;
  } else {
    hostelId = user.hostel_id;
  }
  if (!hostelId) return null;

  // rpc_hostel_stats is the most expensive call on the whole page-load path (~390ms measured —
  // it runs the fee ledger plus fifteen aggregates across nine tables), so it is dispatched
  // first and the hostel row rides alongside it rather than after it.
  const statsPromise = Promise.resolve(supabase.rpc("rpc_hostel_stats", { p_hostel_id: hostelId }).maybeSingle());
  const hostelPromise: Promise<HostelRow | null> = ownedHostel
    ? Promise.resolve(ownedHostel)
    : Promise.resolve(supabase.from("hostels").select("*").eq("id", hostelId).maybeSingle()).then(
        (r) => (r.data as HostelRow | null) ?? null,
      );
  const [h, { data: stats }] = await Promise.all([hostelPromise, statsPromise]);
  if (!h) return null;

  const s = (stats ?? {}) as { subscription_state?: SubscriptionStatus; subscription_days_left?: number | null };
  const subscriptionState: SubscriptionStatus = s.subscription_state ?? "expired";
  const writable = h.status === "active" && subscriptionState !== "expired";

  if (hostels.length === 0) hostels = [{ id: h.id, name: h.name, status: h.status }];

  return {
    hostel: h,
    subscriptionState,
    daysLeft: s.subscription_days_left ?? null,
    writable,
    hostels,
  };
}

/**
 * Hostel context for the current session. Cached per request.
 *
 * The hostel reads are started from the profile row the moment PostgREST returns it, instead of
 * waiting for the getUser() round trip running beside it. That is worth the whole of getUser()
 * on every hostel-scoped page: ~200ms of Auth-server latency now finishes inside the ~390ms
 * rpc_hostel_stats call rather than in front of it.
 *
 * SECURITY: the early start decides only what to ISSUE, never what to return.
 *  • nothing leaves this function until getSessionUser() has verified the session against the
 *    Auth server, and the early result is used only when the account it was built for is the
 *    one getUser() confirmed — on any mismatch it is discarded and rebuilt from the verified row;
 *  • every read involved is RLS-scoped to the caller's own session and no policy in this schema
 *    varies with assurance level, so a read issued early can see nothing a read issued 200ms
 *    later could not;
 *  • a revoked-but-unexpired session can therefore cause reads whose results are thrown away,
 *    and is still bounced to /login by requireUser()/assertRole() exactly as before.
 */
export const getHostelContext = cache(async (explicitHostelId?: string): Promise<HostelContext | null> => {
  const provisional = await provisionalProfile();
  const early = provisional ? buildHostelContext(provisional, explicitHostelId) : null;
  early?.catch(() => {}); // discarded on mismatch — must not become an unhandled rejection

  const user = await getSessionUser();
  if (!user) return null;

  if (
    early &&
    provisional &&
    provisional.id === user.id &&
    provisional.role === user.role &&
    provisional.hostel_id === user.hostel_id
  ) {
    return await early;
  }
  return await buildHostelContext(user, explicitHostelId);
});

/**
 * Page guard: role + hostel context, redirects when missing.
 *
 * The context is kicked off BEFORE the role check rather than after it. Both helpers are cached
 * per request, so nothing is resolved twice; the effect is that the hostel reads overlap the
 * getUser() round trip requireRole() is blocked on. requireRole() still decides whether this
 * request may proceed and still runs every gate — inactive account, forced password change, MFA
 * step-up, role↔route — before the context is read, and it redirects out of here on any of them.
 */
export async function requireHostelContext(...roles: UserRole[]) {
  const ctxPromise = getHostelContext();
  ctxPromise.catch(() => {}); // requireRole() may redirect first, abandoning this promise
  const user = await requireRole(...roles);
  const ctx = await ctxPromise;
  if (!ctx) {
    // Owner without a hostel yet / staff without binding → nothing to show
    redirect("/login?error=no-hostel");
  }
  return { user, ctx };
}

/** Server-action guard: role + hostel context, throws PermissionError instead of redirecting. */
export async function assertHostelContext(...roles: UserRole[]) {
  const ctxPromise = getHostelContext(); // see requireHostelContext() for why this starts first
  ctxPromise.catch(() => {});
  const user = await assertRole(...roles);
  const ctx = await ctxPromise;
  if (!ctx) throw new PermissionError("No hostel is linked to your account.");
  return { user, ctx };
}

/**
 * Hard rule §4.4 — subscription gate for writes.
 * Throws a friendly error the UI can toast. RLS enforces the same rule in the DB.
 */
export function assertWritable(ctx: HostelContext) {
  if (!ctx.writable) {
    if (ctx.hostel.status === "suspended") {
      throw new PermissionError("This hostel is suspended. Contact NIVORA support.");
    }
    throw new PermissionError("Subscription expired — the hostel is read-only until it is renewed.");
  }
}

/** Convenience for actions: role + hostel + writable in one call. */
export async function assertWritableContext(...roles: UserRole[]) {
  const res = await assertHostelContext(...roles);
  assertWritable(res.ctx);
  return res;
}

/**
 * Turn any thrown error into a user-facing message WITHOUT leaking internals
 * (checklist §18). Only allow-listed sources are shown verbatim:
 *   • PermissionError (ours)
 *   • Postgres `raise exception` from our triggers/RPCs (SQLSTATE P0001) — written to be friendly
 *   • our own thrown Error()s from lib/auth, lib/storage (plain-language messages)
 * Everything else (driver/PostgREST/network errors) maps to a generic message; the raw
 * error is logged server-side so it can still be investigated.
 */
export function errorMessage(err: unknown, fallback = "Something went wrong. Please try again."): string {
  if (err instanceof PermissionError) return err.message;

  if (err && typeof err === "object") {
    const e = err as { message?: string; code?: string; details?: string; hint?: string; name?: string };
    const msg = e.message ?? "";
    const code = e.code ?? "";

    // RLS / privilege violation (also our RPC 'Not allowed.' / read-only raises use 42501)
    if (code === "42501" || /row-level security/i.test(msg)) {
      if (/expired|read-only|Only the Super Admin|Only the warden|Not allowed/i.test(msg)) return msg;
      return "You don't have permission to do that (or the subscription has expired).";
    }
    if (code === "23505") {
      if (/students_phone_active_key/.test(msg)) return "A student with this phone number is already registered.";
      if (/users_email_key/.test(msg)) return "An account with this email already exists.";
      if (/students_one_active_per_bed|beds_student_key/.test(msg)) return "That bed is already occupied. Choose a free bed.";
      return "This record already exists.";
    }
    if (code === "23503") return "That record is linked to something that no longer exists.";
    if (code === "23514" || code === "22003") return "One of the values is out of the allowed range.";
    if (code === "22P02" || code === "22007" || code === "22008") return "One of the values has an invalid format.";
    if (code === "P0001" && msg) return msg; // our own friendly raises
    if (code === "PGRST116") return "Not found.";
    if (/^(P0|42|22|23|08|53|57|PGRST)/.test(code)) {
      logServerError(err);
      return fallback;
    }
    // Plain Error thrown by our own server code (accounts.ts, storage.ts, validators): safe to show
    if (err instanceof Error && !code && msg && msg.length <= 200 && !/at .*\.(ts|js):\d+|ECONN|ENOTFOUND|fetch failed|TypeError|ReferenceError/i.test(msg)) {
      return msg;
    }
    if (msg) logServerError(err);
  }
  return fallback;
}

function logServerError(err: unknown) {
  // Never log request bodies/credentials here — only the error itself.
  console.error("[hostelpro] server error:", err instanceof Error ? `${err.name}: ${err.message}` : JSON.stringify(err).slice(0, 500));
}
