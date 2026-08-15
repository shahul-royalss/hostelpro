import "server-only";
import { createClient as createSupabaseClient, type SupabaseClient } from "@supabase/supabase-js";

let cached: SupabaseClient | null = null;

/**
 * Service-role client — BYPASSES RLS.
 *
 * Only use for operations that genuinely need it:
 *   • creating / deleting auth users (Supabase Auth admin API)
 *   • regenerating passwords
 *   • uploading files to private storage buckets
 *   • seeding
 *
 * Every call site must first authorise the caller with `requireRole(...)`
 * from `lib/permissions.ts`. Never import this into client components.
 */
export function createAdminClient(): SupabaseClient {
  if (cached) return cached;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY / NEXT_PUBLIC_SUPABASE_URL are not set. Copy .env.example to .env.local.",
    );
  }
  cached = createSupabaseClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  return cached;
}
