import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

/** Liveness + Supabase reachability check (no secrets). */
export async function GET() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  let supabase: { ok: boolean; status?: number; error?: string; cause?: string } = { ok: false };
  if (url && key) {
    try {
      const res = await fetch(`${url}/auth/v1/health`, { headers: { apikey: key }, cache: "no-store" });
      supabase = { ok: res.ok, status: res.status };
    } catch (e) {
      const err = e as Error & { cause?: { code?: string; message?: string } };
      supabase = { ok: false, error: err.message, cause: err.cause?.code ?? err.cause?.message };
    }
  }
  return NextResponse.json({
    ok: true,
    env: {
      supabaseUrl: !!url,
      anonKey: !!key,
      serviceRoleKey: !!process.env.SUPABASE_SERVICE_ROLE_KEY,
      proxy: {
        HTTPS_PROXY: process.env.HTTPS_PROXY ?? process.env.https_proxy ?? null,
        HTTP_PROXY: process.env.HTTP_PROXY ?? process.env.http_proxy ?? null,
        NO_PROXY: process.env.NO_PROXY ?? process.env.no_proxy ?? null,
      },
      nodeOptions: process.env.NODE_OPTIONS ?? null,
    },
    supabase,
    time: new Date().toISOString(),
  });
}
