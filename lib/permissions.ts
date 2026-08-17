import "server-only";
import { cache } from "react";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ROLE_HOME, type UserRole } from "@/lib/roles";
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
 * Current signed-in user + profile row. Cached per request.
 * Returns null when signed out.
 */
export const getSessionUser = cache(async (): Promise<SessionUser | null> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("users")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  if (!profile) return null;
  return { ...(profile as UserRow), authEmail: user.email ?? null };
});

/**
 * True when the session has completed TOTP step-up (or the account has no factor).
 * Decodes the local session — no network call.
 */
async function mfaSatisfied(): Promise<boolean> {
  try {
    const supabase = await createClient();
    const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (!data) return true;
    return !(data.nextLevel === "aal2" && data.currentLevel !== "aal2");
  } catch {
    return true; // never lock the app out on a decode failure
  }
}

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
  if (!roles.includes(user.role)) redirect(ROLE_HOME[user.role]);
  return user;
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
  if (!roles.includes(user.role)) throw new PermissionError("You don't have permission to do that.");
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
 * Resolve the hostel the current session is bound to (Hard rule §3).
 *  • manager / warden / student → users.hostel_id
 *  • owner → active-hostel cookie (validated) or users.hostel_id or first owned hostel
 *  • super_admin → must pass hostelId explicitly (monitoring views)
 */
export const getHostelContext = cache(async (explicitHostelId?: string): Promise<HostelContext | null> => {
  const user = await getSessionUser();
  if (!user) return null;
  const supabase = await createClient();

  let hostelId: string | null = null;
  let hostels: Pick<HostelRow, "id" | "name" | "status">[] = [];

  if (user.role === "super_admin") {
    if (!explicitHostelId) return null;
    hostelId = explicitHostelId;
  } else if (user.role === "owner") {
    const { data: owned } = await supabase
      .from("hostels")
      .select("id, name, status")
      .eq("owner_user_id", user.id)
      .order("created_at", { ascending: true });
    hostels = (owned ?? []) as Pick<HostelRow, "id" | "name" | "status">[];
    if (hostels.length === 0) return null;

    const cookieStore = await cookies();
    const preferred = explicitHostelId ?? cookieStore.get(ACTIVE_HOSTEL_COOKIE)?.value ?? user.hostel_id;
    hostelId = hostels.find((h) => h.id === preferred)?.id ?? hostels[0].id;
  } else {
    hostelId = user.hostel_id;
  }
  if (!hostelId) return null;

  const [{ data: hostel }, { data: stats }] = await Promise.all([
    supabase.from("hostels").select("*").eq("id", hostelId).maybeSingle(),
    supabase.rpc("rpc_hostel_stats", { p_hostel_id: hostelId }).maybeSingle(),
  ]);
  if (!hostel) return null;

  const h = hostel as HostelRow;
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
});

/** Page guard: role + hostel context, redirects when missing. */
export async function requireHostelContext(...roles: UserRole[]) {
  const user = await requireRole(...roles);
  const ctx = await getHostelContext();
  if (!ctx) {
    // Owner without a hostel yet / staff without binding → nothing to show
    redirect("/login?error=no-hostel");
  }
  return { user, ctx };
}

/** Server-action guard: role + hostel context, throws PermissionError instead of redirecting. */
export async function assertHostelContext(...roles: UserRole[]) {
  const user = await assertRole(...roles);
  const ctx = await getHostelContext();
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
      throw new PermissionError("This hostel is suspended. Contact HostelPro support.");
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
