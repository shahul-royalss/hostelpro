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

/**
 * Razorpay Checkout — the ONE third-party origin set this policy admits, and only
 * because a hosted card form cannot be self-hosted: PCI scope is the entire reason
 * to use it, and it only holds if the card fields belong to Razorpay's document,
 * not ours.
 *
 * What each entry buys, so a future reader can delete any of them and know what
 * breaks:
 *
 *   script-src  checkout.razorpay.com
 *       Strictly redundant in a CSP3 browser: 'strict-dynamic' makes the host
 *       allowlist in script-src inert, and checkout.js is injected at runtime by
 *       our own nonce-carrying bundle (components/payments/razorpay-checkout.ts),
 *       so it inherits trust from the script that appended it. It is here for
 *       CSP2-era browsers, which ignore 'strict-dynamic' and fall back to the
 *       host list — without it those users get a silently dead Pay button.
 *
 *   frame-src   api.razorpay.com, checkout.razorpay.com
 *       REQUIRED. Checkout renders the payment form in an iframe. There was no
 *       frame-src before this, so it fell back to `default-src 'self'` and the
 *       modal would have been blocked outright.
 *
 *   connect-src api.razorpay.com   (lumberjack telemetry deliberately NOT granted)
 *       REQUIRED. Checkout polls payment state over XHR; the lumberjack hosts are
 *       its own telemetry, and it retries noisily when they are blocked.
 *
 *   img-src     *.razorpay.com
 *       Bank and wallet logos drawn into the loader that Checkout puts in OUR
 *       document before the iframe takes over.
 *
 * NOT granted, deliberately: no `form-action` entry (the modal flow submits no
 * form from this document), and nothing is added to `default-src`, `style-src` or
 * `frame-ancestors`. connect-src stays 'self' + Supabase + these hosts, so the
 * exfiltration surface this policy exists to close is unchanged for every origin
 * except Razorpay's own API.
 *
 * If Checkout is switched to the redirect (`callback_url`) flow, `form-action`
 * will have to be widened too — that is a deliberate decision, not a config tweak.
 */
const RAZORPAY = {
  script: "https://checkout.razorpay.com",
  frame: "https://api.razorpay.com https://checkout.razorpay.com",
  connect: "https://api.razorpay.com",
  img: "https://*.razorpay.com",
} as const;

export function generateNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

/**
 * Razorpay's origins are granted ONLY on the routes that open Checkout.
 *
 * The first version of this widened script-src/frame-src/connect-src for EVERY request, because
 * buildCsp() had a single caller in middleware. That hands a third-party script origin to the
 * whole app - including the super-admin console and every page that renders resident PII - to
 * benefit one sheet on one student page. CSP is a blast-radius control; granting it globally to
 * save an argument defeats the point.
 */
function needsRazorpay(pathname: string): boolean {
  return pathname === "/student" || pathname.startsWith("/student/");
}

export function buildCsp(nonce: string, pathname = ""): string {
  const razorpay = needsRazorpay(pathname);
  const isDev = process.env.NODE_ENV !== "production";
  const supabase = SUPABASE_ORIGIN;
  const supabaseWs = supabase.replace(/^https/, "wss");
  const directives = [
    `default-src 'self'`,
    // Next.js inline scripts carry the nonce; 'strict-dynamic' trusts what they load.
    // Dev needs eval for React Refresh / webpack HMR.
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic' ${razorpay ? " " + RAZORPAY.script : ""}${isDev ? " 'unsafe-eval'" : ""}`,
    // Recharts (inline style attributes) and sonner (injected <style>) need inline styles.
    `style-src 'self' 'unsafe-inline'`,
    `img-src 'self' data: blob: ${razorpay ? " " + RAZORPAY.img : ""}${supabase ? ` ${supabase}` : ""}`,
    `font-src 'self' data:`,
    `connect-src 'self' ${razorpay ? " " + RAZORPAY.connect : ""}${supabase ? ` ${supabase} ${supabaseWs}` : ""}${isDev ? " ws: wss:" : ""}`,
    // Razorpay Checkout renders the payment form in an iframe of its own. Without
    // this directive it inherits `default-src 'self'` and never opens.
    `frame-src 'self' ${razorpay ? " " + RAZORPAY.frame : ""}`,
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
  // `payment` was fully disabled. Razorpay Checkout's iframe requests
  // allow="payment" for the Payment Request API paths (Google Pay, UPI intent on
  // Android); a top-level `payment=()` denies that before the iframe's own attribute
  // is even considered, and those methods silently disappear from the sheet. Scoped
  // to this document and Razorpay's origin — not opened to `*`.
  headers.set(
    "Permissions-Policy",
    'camera=(self), microphone=(), geolocation=(), payment=(self "https://api.razorpay.com"), usb=(), browsing-topics=()',
  );
  if (process.env.NODE_ENV === "production") {
    headers.set("Strict-Transport-Security", "max-age=63072000; includeSubDomains; preload");
  }
}
