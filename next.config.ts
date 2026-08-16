import type { NextConfig } from "next";

const supabaseHost = (() => {
  try {
    return new URL(process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://example.supabase.co").hostname;
  } catch {
    return "*.supabase.co";
  }
})();

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Don't advertise the framework (checklist §17/§24)
  poweredByHeader: false,
  // Never emit browser source maps for production bundles (checklist §2)
  productionBrowserSourceMaps: false,
  experimental: {
    serverActions: {
      // receipt / photo uploads go through server actions
      bodySizeLimit: "8mb",
    },
  },
  images: {
    // Signed URLs from a private bucket must not be proxied/cached by the image
    // optimizer, and this removes the `sharp` dependency path entirely.
    unoptimized: true,
    remotePatterns: [{ protocol: "https", hostname: supabaseHost }],
  },
  // Security headers are set per-request in middleware (nonce-based CSP); the
  // static fallbacks below cover assets that bypass middleware.
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-DNS-Prefetch-Control", value: "off" },
          { key: "Permissions-Policy", value: "camera=(self), microphone=(), geolocation=(), payment=(), usb=(), browsing-topics=()" },
        ],
      },
    ];
  },
};

export default nextConfig;
