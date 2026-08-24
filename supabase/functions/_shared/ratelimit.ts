/**
 * Per-caller rate limiting, on the same durable counters the web app uses.
 *
 * public.rate_limit() is a fixed-window counter in Postgres (app.rate_limits). It is granted
 * to service_role only — an Edge Function isolate is short-lived and there may be many of
 * them, so an in-memory counter would reset on every cold start and limit nothing.
 *
 * Keys are hashed before they leave here, exactly as lib/rate-limit.ts does, so the limiter
 * table never becomes a list of user ids.
 *
 * FAIL CLOSED. The web app lets ordinary actions through when the limiter is unavailable;
 * these three endpoints do not, because every one of them mints a credential. A limiter that
 * opens under load is no limiter on the path that matters most.
 */
import { HttpError } from "./http.ts";
import { serviceClient } from "./supabase.ts";

/** Mirrors LIMITS.accountCreatePerUser in lib/rate-limit.ts. */
export const ACCOUNT_CREATE_LIMIT = { max: 20, windowSeconds: 3600 } as const;

async function hashKey(key: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 48);
}

export async function enforceRateLimit(
  key: string,
  limit: { max: number; windowSeconds: number } = ACCOUNT_CREATE_LIMIT,
): Promise<void> {
  let row: { allowed: boolean; retry_after_seconds: number } | null = null;
  try {
    const { data, error } = await serviceClient()
      .rpc("rate_limit", { p_key: await hashKey(key), p_max: limit.max, p_window_seconds: limit.windowSeconds })
      .maybeSingle();
    if (error || !data) throw error ?? new Error("rate_limit: no data");
    row = data as { allowed: boolean; retry_after_seconds: number };
  } catch (e) {
    console.error("[nivora] rate limiter unavailable:", e instanceof Error ? e.message : String(e));
    throw new HttpError(503, "Account creation is temporarily unavailable. Please try again in a minute.");
  }
  if (!row.allowed) {
    const wait = Number(row.retry_after_seconds) || 60;
    throw new HttpError(429, `Too many account operations in a short time. Try again in ${wait}s.`);
  }
}
