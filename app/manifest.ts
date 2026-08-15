import type { MetadataRoute } from "next";

/** PWA manifest — Warden & Student apps are installable (CLAUDE_2.md §2). */
export default function manifest(): MetadataRoute.Manifest {
  const name = process.env.NEXT_PUBLIC_APP_NAME ?? "HostelPro";
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
      { src: "/icons/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
      { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
      { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
