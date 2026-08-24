"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { ArrowLeft, Building2, KeyRound, LogOut, ShieldCheck } from "lucide-react";
import { cn } from "@/lib/utils";
import type { UserRole } from "@/lib/roles";
import { NAV, isActive } from "./nav-config";
import { NotificationBell } from "@/components/shared/notification-bell";
import { UserAvatar } from "@/components/ui/avatar";
import { signOut } from "@/lib/actions/session";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/**
 * Mobile shell — Warden / Student. This is the primary target: the Android app
 * is a TWA that loads this same deployment fullscreen, so everything here is
 * sized for a phone first and the 480px cap is only what keeps it honest on a
 * desktop browser.
 *
 * Three things it guarantees, because nothing else can:
 *
 *  • SAFE AREAS. Fullscreen means the window really does extend under the
 *    status bar and the gesture pill. `.app-bar` / `.tab-bar` / `.app-main` in
 *    globals.css read env(safe-area-inset-*) so the chrome grows into that
 *    strip and its contents stay out of it.
 *  • TAP TARGETS. Every control in the chrome is at least 44x44 (Apple HIG) —
 *    the tab bar rows clear Material's 48dp too.
 *  • NO LAYOUT SHIFT on navigation. Tabs are flex-1/basis-0 so their widths do
 *    not depend on the label, the selected pill is absolutely positioned, and
 *    the only thing that differs between selected and unselected is colour and
 *    stroke weight. Nothing in the bar reflows when the route changes.
 */
export function MobileShell({
  role,
  title,
  subtitle,
  avatarName,
  /** Account context for the avatar menu — where a pushed screen can still check which hostel it is looking at. */
  hostelName,
  unread = 0,
  banner,
  children,
  /** Show a back arrow instead of the avatar (sub-pages) */
  backHref,
  /** Right-side extra action(s) next to the bell */
  actions,
  /** Hide bottom nav (e.g. inside the multi-step register form) */
  hideNav = false,
  contentClassName,
}: {
  role: Extract<UserRole, "warden" | "student">;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  avatarName?: string;
  hostelName?: string | null;
  unread?: number;
  banner?: React.ReactNode;
  children: React.ReactNode;
  backHref?: string;
  actions?: React.ReactNode;
  hideNav?: boolean;
  contentClassName?: string;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const items = NAV[role];

  return (
    <div className="mx-auto min-h-dvh w-full max-w-[480px]">
      {/* ── Top app bar ─────────────────────────────────────────────────── */}
      <header className="app-bar material-chrome fixed inset-x-0 top-0 z-40 mx-auto flex max-w-[480px] items-center justify-between gap-2 border-b border-separator">
        <div className="flex min-w-0 flex-1 items-center gap-2">
          {backHref ? (
            <button
              type="button"
              aria-label="Back"
              onClick={() => (backHref === "back" ? router.back() : router.push(backHref))}
              className="-ml-3 flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-navy transition-colors hover:bg-fill-quaternary active:bg-fill-tertiary"
            >
              <ArrowLeft className="h-5 w-5" strokeWidth={2} />
            </button>
          ) : (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                {/* 32px avatar, 44x44 target — the avatar is not the hit area. */}
                <button
                  type="button"
                  aria-label="Account menu"
                  className="-ml-1.5 flex h-11 w-11 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-fill-quaternary active:bg-fill-tertiary"
                >
                  <UserAvatar name={avatarName} size="sm" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start" className="w-60">
                <DropdownMenuLabel className="font-normal">
                  <div className="text-sm font-semibold text-navy">{avatarName}</div>
                  {/*
                    The app bar only carries the hostel name on a tab root; from a
                    pushed screen this menu is where you check it. On demand, so
                    it never adds to the count of what is on screen at rest.
                  */}
                  {hostelName ? (
                    <div className="mt-0.5 flex items-center gap-1.5 text-xs text-muted">
                      <Building2 className="h-3.5 w-3.5 shrink-0" />
                      <span className="truncate">{hostelName}</span>
                    </div>
                  ) : null}
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem asChild>
                  <Link href="/change-password">
                    <KeyRound /> Change password
                  </Link>
                </DropdownMenuItem>
                <DropdownMenuItem asChild>
                  <Link href="/security/mfa">
                    <ShieldCheck /> Two-factor authentication
                  </Link>
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onSelect={() => signOut()} className="text-red focus:text-red">
                  <LogOut /> Log out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          )}
          <div className="min-w-0">
            <h1 className="truncate text-headline text-navy">{title}</h1>
            {subtitle ? <p className="truncate text-caption-2 text-muted">{subtitle}</p> : null}
          </div>
        </div>
        <div className="-mr-3 flex shrink-0 items-center">
          {actions}
          <NotificationBell initialUnread={unread} />
        </div>
      </header>

      {/* ── Content ─────────────────────────────────────────────────────── */}
      <main className={cn("app-main app-main-inline", hideNav ? "app-main-flat" : "app-main-tabs", contentClassName)}>
        {banner ? <div className="mb-4">{banner}</div> : null}
        <div className="animate-fade-in">{children}</div>
      </main>

      {/* ── Bottom tab bar ──────────────────────────────────────────────── */}
      {!hideNav && (
        <nav
          aria-label="Primary"
          className="tab-bar material-chrome fixed inset-x-0 bottom-0 z-40 mx-auto flex max-w-[480px] items-stretch rounded-t-card border-t border-separator shadow-nav"
        >
          {items.map((item) => {
            const active = isActive(pathname, item);
            const Icon = item.icon;

            if (item.center) {
              return (
                <div key={item.href} className="flex flex-1 basis-0 items-start justify-center">
                  <Link
                    href={item.href}
                    aria-label={item.label}
                    aria-current={active ? "page" : undefined}
                    className="press-scale [--press:0.9] relative -top-5 flex h-14 w-14 items-center justify-center rounded-full border-4 border-ivory bg-navy text-white shadow-elev-4 transition-transform"
                  >
                    <Icon className="h-6 w-6" strokeWidth={2} />
                  </Link>
                </div>
              );
            }

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  // flex-1/basis-0 → every tab is exactly 1/n of the bar, whatever
                  // the label says. min-h-12 = 48dp, above HIG's 44pt floor.
                  "group relative flex min-h-12 flex-1 basis-0 flex-col items-center justify-center gap-1 rounded-control transition-colors",
                  active ? "text-navy" : "text-muted hover:text-navy",
                )}
              >
                {/* Absolutely positioned: selection can never move the layout. */}
                <span aria-hidden className="tab-pill absolute inset-x-1 inset-y-1.5 rounded-control bg-navy/[0.09]" />
                <Icon className="relative h-[22px] w-[22px]" strokeWidth={active ? 2.25 : 1.75} />
                <span className="relative text-[11px] font-semibold leading-none">{item.label}</span>
              </Link>
            );
          })}
        </nav>
      )}
    </div>
  );
}
