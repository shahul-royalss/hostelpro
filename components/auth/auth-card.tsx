import * as React from "react";
import { Building2 } from "lucide-react";

/**
 * Centered frosted card over the ivory background with a subtle navy→teal glow (A-1 / A-2).
 */
export function AuthCard({
  title,
  subtitle,
  children,
  footer,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
}) {
  const appName = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";
  return (
    <div className="relative flex min-h-dvh items-center justify-center overflow-hidden px-page-mobile py-10 md:px-page-desktop">
      <div className="ambient-glow" aria-hidden />
      <main className="relative z-10 w-full max-w-md">
        <div className="glass-card flex flex-col gap-7 p-7 md:p-10">
          <div className="flex flex-col items-center gap-2 text-center">
            <div className="mb-1 flex h-12 w-12 items-center justify-center rounded-control bg-navy text-white shadow-sm">
              <Building2 className="h-6 w-6" strokeWidth={1.75} />
            </div>
            <div className="text-caption uppercase tracking-[0.12em] text-muted">{appName}</div>
            <h1 className="text-title text-navy">{title}</h1>
            {subtitle ? <p className="text-sm text-muted">{subtitle}</p> : null}
          </div>
          {children}
        </div>
        <div className="mt-6 text-center">
          {footer ?? (
            <div className="space-y-2">
              <p className="text-caption uppercase tracking-[0.05em] text-muted/80">
                © {new Date().getFullYear()} {appName}. Accounts are created by your administrator.
              </p>
              {/*
                Google Play expects the privacy policy to be reachable from inside the app, not
                only from the store listing. The sign-in screen is the one page every user and
                every reviewer sees, and it is reachable without a session.
              */}
              <p className="text-caption text-muted/80">
                <a href="/legal/privacy" className="underline underline-offset-2 hover:text-navy">
                  Privacy
                </a>
                <span aria-hidden="true"> · </span>
                <a href="/legal/terms" className="underline underline-offset-2 hover:text-navy">
                  Terms
                </a>
                <span aria-hidden="true"> · </span>
                <a
                  href="/legal/account-deletion"
                  className="underline underline-offset-2 hover:text-navy"
                >
                  Delete my data
                </a>
              </p>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}
