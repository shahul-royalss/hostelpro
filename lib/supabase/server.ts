import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/**
 * Server client bound to the current user's session cookies.
 * RLS is enforced — this is the client to use for all tenant reads/writes
 * inside Server Components, Server Actions and Route Handlers.
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Called from a Server Component — cookies can't be written here.
            // Middleware refreshes the session, so this is safe to ignore.
          }
        },
      },
    },
  );
}
