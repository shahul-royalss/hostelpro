import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import { Toaster } from "sonner";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";

export const metadata: Metadata = {
  // Private workspace — keep every screen out of search indexes (checklist §17).
  robots: { index: false, follow: false, nocache: true },
  title: {
    default: APP_NAME,
    template: `%s · ${APP_NAME}`,
  },
  description: "PG / hostel management for owners, managers, wardens and students.",
  applicationName: APP_NAME,
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: APP_NAME,
  },
  icons: {
    // The logo is raster artwork, so there is no honest SVG of it — pointing at a stale
    // hand-drawn placeholder was worse than pointing at the real thing in PNG.
    icon: [
      { url: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icons/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/icons/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
};

export const viewport: Viewport = {
  themeColor: "#F6F4EF",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  viewportFit: "cover",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={inter.variable} suppressHydrationWarning>
      <body className="min-h-dvh antialiased">
        {children}
        <Toaster
          position="top-center"
          richColors={false}
          toastOptions={{
            classNames: {
              toast: "!rounded-control !border !border-white/80 !bg-white/90 !backdrop-blur-xl !shadow-glass-lg !text-charcoal",
              title: "!text-sm !font-medium",
              description: "!text-xs !text-muted",
              success: "!text-teal",
              error: "!text-red",
            },
          }}
        />
      </body>
    </html>
  );
}
