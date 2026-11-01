import { headers } from "next/headers";
import { Download } from "lucide-react";

export const metadata = { title: "Get Apnivaas" };

const PLAY_URL = "https://play.google.com/store/apps/details?id=com.nivorasr.app";

/**
 * Where the Android app sends someone whose phone has no Play Store app (round 6). Apnivaas is
 * distributed through Google Play; this page only points there. Public (lib/supabase/middleware).
 * headers() keeps it dynamic so the CSP nonce is present, as on not-found.tsx.
 */
export default async function InstallPage() {
  await headers();
  return (
    <div className="relative flex min-h-dvh items-center justify-center overflow-hidden px-page-mobile py-10">
      <div className="ambient-glow" aria-hidden />
      <main className="relative z-10 w-full max-w-md">
        <div className="glass-card flex flex-col items-center gap-4 p-8 text-center md:p-10">
          <div className="flex h-12 w-12 items-center justify-center rounded-control bg-navy text-white">
            <Download className="h-6 w-6" strokeWidth={1.75} />
          </div>
          <div>
            <h1 className="text-title text-navy">Get Apnivaas on Google Play</h1>
            <p className="mt-1 text-sm text-muted">
              Apnivaas for Android is installed and updated through Google Play. Open the link on
              your phone and tap Install or Update. Your account and data stay as they are.
            </p>
          </div>
          <a
            href={PLAY_URL}
            className="mt-2 inline-flex h-10 items-center justify-center rounded-control bg-navy px-5 text-sm font-medium text-white transition-opacity hover:opacity-90"
          >
            Open Google Play
          </a>
        </div>
      </main>
    </div>
  );
}
