/**
 * Security response headers (checklist §7, §17).
 * Applied to every response by the middleware; the CSP is nonce-based so Next.js'
 * inline RSC bootstrap scripts run without 'unsafe-inline' for scripts.
 * Safe to import from middleware (edge runtime) — no Node APIs.
 */

const SUPABASE_ORIGIN = (() => {
  try {
    return new URL(process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").origin;
  } catch {
    return "";
  }
})();

export function generateNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

export function buildCsp(nonce: string): string {
  const isDev = process.env.NODE_ENV !== "production";
  const supabase = SUPABASE_ORIGIN;
  const supabaseWs = supabase.replace(/^https/, "wss");
  const directives = [
    `default-src 'self'`,
    // Next.js inline scripts carry the nonce; 'strict-dynamic' trusts what they load.
    // Dev needs eval for React Refresh / webpack HMR.
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ""}`,
    // Recharts (inline style attributes) and sonner (injected <style>) need inline styles.
    `style-src 'self' 'unsafe-inline'`,
    `img-src 'self' data: blob:${supabase ? ` ${supabase}` : ""}`,
    `font-src 'self' data:`,
    `connect-src 'self'${supabase ? ` ${supabase} ${supabaseWs}` : ""}${isDev ? " ws: wss:" : ""}`,
    `media-src 'self' blob:`,
    `worker-src 'self' blob:`,
    `manifest-src 'self'`,
    `object-src 'none'`,
    `base-uri 'self'`,
    `form-action 'self'`,
    `frame-ancestors 'none'`,
    ...(isDev ? [] : [`upgrade-insecure-requests`]),
  ];
  return directives.join("; ");
}

export function applySecurityHeaders(headers: Headers, csp: string) {
  headers.set("Content-Security-Policy", csp);
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  headers.set("X-Frame-Options", "DENY");
  headers.set("X-DNS-Prefetch-Control", "off");
  headers.set("Cross-Origin-Opener-Policy", "same-origin");
  headers.set("Permissions-Policy", "camera=(self), microphone=(), geolocation=(), payment=(), usb=(), browsing-topics=()");
  if (process.env.NODE_ENV === "production") {
    headers.set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload");
  }
}
