/**
 * The two Supabase clients an Edge Function is allowed to build.
 *
 * WHY THERE ARE TWO, AND WHICH ONE DECIDES WHAT.
 *
 *   serviceClient()  bypasses RLS. It exists for exactly three things the caller's own
 *                    session cannot do: create/delete an auth user, insert the public.users
 *                    row for a brand-new account, and read the caller's own profile row as
 *                    the authoritative answer to "who is this". It is NEVER used to perform
 *                    a tenant write on the caller's behalf where an RLS-checked path exists.
 *
 *   callerClient()   carries the caller's JWT, so PostgREST and every SECURITY DEFINER RPC
 *                    see auth.uid() = the real person. The hostel/subscription/scaffold RPC
 *                    and wd_register_student are invoked through THIS client on purpose: the
 *                    database re-checks app.is_super_admin() / app.has_role_in(...) itself,
 *                    and created_by lands on the actual actor instead of NULL. Calling them
 *                    with the service key would satisfy app.is_service_role() and silently
 *                    skip that second opinion.
 *
 * The service-role key is never returned, logged, or echoed into a response.
 */
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

function env(name: string): string | undefined {
  const v = Deno.env.get(name);
  return v && v.length > 0 ? v : undefined;
}

export function projectUrl(): string {
  const url = env("SUPABASE_URL");
  if (!url) throw new Error("SUPABASE_URL is not set in the function environment.");
  return url;
}

export function anonKey(): string {
  const key = env("SUPABASE_ANON_KEY");
  if (!key) throw new Error("SUPABASE_ANON_KEY is not set in the function environment.");
  return key;
}

/**
 * The service-role key.
 *
 * NIVORA_SERVICE_ROLE_KEY is checked first because that is the name the key can actually be
 * pushed under: `supabase secrets set` refuses names beginning with SUPABASE_, which is
 * reserved for the platform's own injected values. SUPABASE_SERVICE_ROLE_KEY is the fallback
 * and is present in every deployed function by default, so a deployment with no secrets set
 * at all still works. See docs/edge-functions.md.
 */
export function serviceRoleKey(): string {
  const key = env("NIVORA_SERVICE_ROLE_KEY") ?? env("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) {
    throw new Error(
      "No service-role key in the function environment. Set NIVORA_SERVICE_ROLE_KEY with `supabase secrets set` (see docs/edge-functions.md).",
    );
  }
  return key;
}

let cachedService: SupabaseClient | null = null;

/** RLS-bypassing client. Every call site must have authorised the caller first. */
export function serviceClient(): SupabaseClient {
  if (cachedService) return cachedService;
  cachedService = createClient(projectUrl(), serviceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  });
  return cachedService;
}

/**
 * Client that acts AS the caller. Not cached — one per request, because it carries that
 * request's bearer token and must never be reused for a different person.
 */
export function callerClient(jwt: string): SupabaseClient {
  return createClient(projectUrl(), anonKey(), {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
}
