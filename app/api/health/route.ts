import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

/**
 * Liveness probe. Unauthenticated, so it deliberately reveals nothing about
 * configuration — only that the app is up and can reach its database/auth.
 * (Set HEALTH_VERBOSE=1 locally to see the TLS/env diagnostics.)
 */
export async function GET() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  let supabase = false;
  let detail: string | undefined;
  if (url && key) {
    try {
      const res = await fetch(`${url}/auth/v1/health`, { headers: { apikey: key }, cache: "no-store" });
      supabase = res.ok;
    } catch (e) {
      const err = e as Error & { cause?: { code?: string } };
      detail = err.cause?.code ?? err.message;
    }
  }
  const verbose = process.env.HEALTH_VERBOSE === "1" && process.env.NODE_ENV !== "production";
  return NextResponse.json(
    {
      ok: true,
      supabase,
      time: new Date().toISOString(),
      ...(verbose ? { detail, serviceRoleKey: !!process.env.SUPABASE_SERVICE_ROLE_KEY, nodeExtraCaCerts: !!process.env.NODE_EXTRA_CA_CERTS } : {}),
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
