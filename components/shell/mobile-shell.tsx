"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { ArrowLeft, KeyRound, LogOut, ShieldCheck } from "lucide-react";
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
 * Mobile shell — Warden / Student (mobile-first, PWA-installable).
 * Top app bar (greeting or title + bell) + frosted bottom nav (4–5 items, active in navy,
 * optional raised center action). Content is capped at 480px and centered on larger screens.
 */
export function MobileShell({
  role,
  title,
  subtitle,
  avatarName,
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
      {/* Top app bar */}
      <header className="glass-bar fixed inset-x-0 top-0 z-40 mx-auto flex h-16 max-w-[480px] items-center justify-between border-b px-page-mobile">
        <div className="flex min-w-0 items-center gap-3">
          {backHref ? (
            <button
              type="button"
              aria-label="Back"
              onClick={() => (backHref === "back" ? router.back() : router.push(backHref))}
              className="-ml-2 rounded-full p-2 text-navy hover:bg-navy/5 active:scale-95"
            >
              <ArrowLeft className="h-5 w-5" />
            </button>
          ) : (
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button type="button" aria-label="Account menu" className="rounded-full active:scale-95">
                  <UserAvatar name={avatarName} size="sm" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start" className="w-56">
                <DropdownMenuLabel className="font-normal">
                  <div className="text-sm font-semibold text-navy">{avatarName}</div>
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
            <div className="truncate text-[16px] font-bold text-navy leading-tight">{title}</div>
            {subtitle ? <div className="truncate text-[11px] text-muted">{subtitle}</div> : null}
          </div>
        </div>
        <div className="flex items-center gap-1">
          {actions}
          <NotificationBell initialUnread={unread} />
        </div>
      </header>

      {/* Content */}
      <main className={cn("px-page-mobile pt-[80px]", hideNav ? "pb-8" : "pb-[104px]", contentClassName)}>
        {banner ? <div className="mb-4">{banner}</div> : null}
        <div className="animate-fade-in">{children}</div>
      </main>

      {/* Bottom nav */}
      {!hideNav && (
        <nav className="glass-bar pb-safe fixed inset-x-0 bottom-0 z-40 mx-auto flex h-[76px] max-w-[480px] items-center justify-around rounded-t-card border-t px-2 shadow-nav">
          {items.map((item) => {
            const active = isActive(pathname, item);
            const Icon = item.icon;
            if (item.center) {
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  aria-label={item.label}
                  className="relative -top-5 flex h-14 w-14 items-center justify-center rounded-full border-4 border-ivory bg-navy text-white shadow-lg transition-transform active:scale-90"
                >
                  <Icon className="h-6 w-6" strokeWidth={2} />
                </Link>
              );
            }
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "flex min-w-[56px] flex-col items-center justify-center gap-0.5 rounded-control px-2.5 py-1.5 transition-all active:scale-90",
                  active ? "bg-navy text-white shadow-sm" : "text-muted hover:text-navy",
                )}
              >
                <Icon className="h-5 w-5" strokeWidth={active ? 2 : 1.75} />
                <span className="text-[10px] font-semibold uppercase tracking-wide">{item.label}</span>
              </Link>
            );
          })}
        </nav>
      )}
    </div>
  );
}
