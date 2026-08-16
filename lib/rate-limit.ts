import "server-only";
import { createHash } from "crypto";
import { headers } from "next/headers";
import { createAdminClient } from "@/lib/supabase/admin";

/**
 * Durable, DB-backed fixed-window rate limiter (checklist §19).
 * Counters live in Postgres (app.rate_limits) so limits hold across serverless
 * instances. Keys are hashed so identifiers/IPs are never stored in clear.
 *
 *   const rl = await rateLimit(`login:ip:${ip}`, 20, 300);
 *   if (!rl.allowed) return fail(`Too many attempts. Try again in ${rl.retryAfterSeconds}s.`);
 */
export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  retryAfterSeconds: number;
}

function hashKey(key: string) {
  return createHash("sha256").update(key).digest("hex").slice(0, 48);
}

/**
 * @param failClosed when true (auth flows) a limiter/DB error blocks the request;
 *                   when false (ordinary actions) it lets the request through.
 */
export async function rateLimit(key: string, max: number, windowSeconds: number, failClosed = false): Promise<RateLimitResult> {
  try {
    const admin = createAdminClient();
    const { data, error } = await admin
      .rpc("rate_limit", { p_key: hashKey(key), p_max: max, p_window_seconds: windowSeconds })
      .maybeSingle();
    if (error || !data) throw error ?? new Error("rate_limit: no data");
    const row = data as { allowed: boolean; remaining: number; retry_after_seconds: number };
    return { allowed: row.allowed, remaining: Number(row.remaining), retryAfterSeconds: Number(row.retry_after_seconds) };
  } catch (e) {
    console.error("[hostelpro] rate limiter unavailable:", e instanceof Error ? e.message : String(e));
    return failClosed
      ? { allowed: false, remaining: 0, retryAfterSeconds: 60 }
      : { allowed: true, remaining: max, retryAfterSeconds: 0 };
  }
}

/** Best-effort client IP (Vercel / proxies set x-forwarded-for; first hop is the client). */
export async function getClientIp(): Promise<string> {
  try {
    const h = await headers();
    const xff = h.get("x-forwarded-for");
    if (xff) return xff.split(",")[0]!.trim().slice(0, 64);
    return (h.get("x-real-ip") ?? h.get("cf-connecting-ip") ?? "unknown").slice(0, 64);
  } catch {
    return "unknown";
  }
}

export async function getUserAgent(): Promise<string> {
  try {
    const h = await headers();
    return (h.get("user-agent") ?? "").slice(0, 300);
  } catch {
    return "";
  }
}

/** Standard limits used across the app (per key, per window). */
export const LIMITS = {
  loginPerIp: { max: 20, windowSeconds: 300 },
  loginPerIdentifier: { max: 8, windowSeconds: 900 },
  passwordChangePerUser: { max: 5, windowSeconds: 900 },
  mfaVerifyPerUser: { max: 6, windowSeconds: 600 },
  accountCreatePerUser: { max: 20, windowSeconds: 3600 },
  uploadPerUser: { max: 40, windowSeconds: 3600 },
  writePerUser: { max: 240, windowSeconds: 600 },
} as const;
