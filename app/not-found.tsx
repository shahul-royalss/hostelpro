import Link from "next/link";
import { headers } from "next/headers";
import { Compass } from "lucide-react";
import { getSessionUser } from "@/lib/permissions";
import { ROLE_HOME } from "@/lib/roles";

/**
 * Branded 404.
 *
 * Reading headers() forces dynamic rendering on purpose: a statically prerendered page
 * carries no CSP nonce, and our `strict-dynamic` policy would then block every script on
 * it (no hydration, console full of violations). Rendering per-request keeps the nonce.
 */
export default async function NotFound() {
  await headers();
  const user = await getSessionUser().catch(() => null);
  const home = user ? ROLE_HOME[user.role] : "/login";

  return (
    <div className="relative flex min-h-dvh items-center justify-center overflow-hidden px-page-mobile py-10">
      <div className="ambient-glow" aria-hidden />
      <main className="relative z-10 w-full max-w-md">
        <div className="glass-card flex flex-col items-center gap-4 p-8 text-center md:p-10">
          <div className="flex h-12 w-12 items-center justify-center rounded-control bg-navy text-white">
            <Compass className="h-6 w-6" strokeWidth={1.75} />
          </div>
          <div>
            <h1 className="text-title text-navy">Page not found</h1>
            <p className="mt-1 text-sm text-muted">
              That link doesn&apos;t exist, or you don&apos;t have access to it.
            </p>
          </div>
          <Link
            href={home}
            className="mt-2 inline-flex h-10 items-center justify-center rounded-control bg-navy px-5 text-sm font-medium text-white transition-opacity hover:opacity-90"
          >
            {user ? "Back to your dashboard" : "Go to sign in"}
          </Link>
        </div>
      </main>
    </div>
  );
}
