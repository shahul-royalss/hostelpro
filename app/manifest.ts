import type { MetadataRoute } from "next";
import { LEGAL } from "@/lib/legal-config";

/**
 * PWA manifest — Warden & Student apps are installable (CLAUDE_2.md §2).
 *
 * `name` and `short_name` are the product name from lib/legal-config.ts, the same constant the
 * page titles (app/layout.tsx) and the legal pages read. It is deliberately not
 * NEXT_PUBLIC_APP_NAME any more: that variable was set in Vercel, inlined at build time, and is
 * how the live manifest kept saying the old name whatever the code's fallback said. "Apnivaas"
 * is eight letters, short enough for a home-screen label, so the two fields are the same.
 *
 * The colours are the existing app ground, unchanged by the rename: only the name, the logo and
 * the icons changed.
 */
export default function manifest(): MetadataRoute.Manifest {
  const name = LEGAL.productName;
  return {
    name,
    short_name: name,
    description: "Hostel management — rooms, fees, complaints, leaves and more.",
    start_url: "/",
    display: "standalone",
    background_color: "#F6F4EF",
    theme_color: "#F6F4EF",
    orientation: "portrait",
    icons: [
      { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
      // scripts/gen-icons.mjs makes 192 rounded-with-alpha (the "any" icon) and 512
      // full-bleed and opaque, which is what purpose "maskable" requires.
      { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
