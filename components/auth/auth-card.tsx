import * as React from "react";
import Image from "next/image";
import { LEGAL } from "@/lib/legal-config";
import apnivaasLockup from "@/public/brand/apnivaas-lockup.png";

/**
 * Centered frosted card over the ivory background with a subtle navy→teal glow (A-1 / A-2).
 *
 * ═══ THE LOGO IS A STATIC IMPORT, NOT A /brand/… URL ═══
 *
 * A plain `<img src="/brand/apnivaas-lockup.png">` looks equivalent and is not. /brand is not in
 * the middleware's matcher exclusions or in PUBLIC_PATHS (lib/supabase/middleware.ts), so for
 * the people this card is FOR — signed out on /login, mid-MFA on /mfa, owing a password on
 * /change-password — the request for the picture would be answered with a 307 to a page, and the
 * sign-in screen would show a broken image to every user and every Play reviewer. Importing the
 * file makes Next copy it to /_next/static/media/<name>.<hash>.png, which middleware never runs
 * on, which is cached immutably because the name changes with the bytes, and which gives
 * next/image the intrinsic width and height so the card does not jump when the picture arrives.
 * `images.unoptimized` is on (next.config.ts), so this is the file as committed — no optimizer.
 *
 * The lockup already contains the mark AND the word "Apnivaas", so it replaces all three things
 * that used to sit here: a generic building icon standing in for a logo, the product name in
 * small caps, and a handwritten wordmark traced from a font. Repeating the name as text under a
 * picture of the name would only make a screen reader say it twice; the picture's alt text is
 * the one announcement.
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
  return (
    <div className="relative flex min-h-dvh items-center justify-center overflow-hidden px-page-mobile py-10 md:px-page-desktop">
      <div className="ambient-glow" aria-hidden />
      <main className="relative z-10 w-full max-w-md">
        <div className="glass-card flex flex-col gap-7 p-7 md:p-10">
          <div className="flex flex-col items-center gap-2 text-center">
            {/* Height-led: width follows the artwork's own aspect ratio, capped at the card's
                width with object-contain so a wider lockup shrinks inside its box instead of
                overflowing a 360 px phone or being squashed. `priority` because on /login this
                is the largest thing above the fold — fetch it with the HTML, not after
                hydration. */}
            <Image
              src={apnivaasLockup}
              alt={LEGAL.productName}
              priority
              draggable={false}
              className="mb-1 h-24 w-auto max-w-full select-none object-contain"
            />
            <h1 className="text-title text-navy">{title}</h1>
            {subtitle ? <p className="text-sm text-muted">{subtitle}</p> : null}
          </div>
          {children}
        </div>
        <div className="mt-6 text-center">
          {footer ?? (
            <div className="space-y-2">
              {/* The copyright belongs to the operator, the same holder the legal pages name
                  (LEGAL.operatorName). Not upper-cased: CSS `uppercase` would print a name
                  whose capitals are part of its spelling in letters it does not have. */}
              <p className="text-caption text-muted/80">
                © {new Date().getFullYear()} {LEGAL.operatorName}. Accounts are created by your
                administrator.
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
