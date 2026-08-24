"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Building2, ChevronsUpDown, LogOut, Menu, ShieldCheck, X } from "lucide-react";
import { cn, initials } from "@/lib/utils";
import { ROLE_LABEL, type UserRole } from "@/lib/roles";
import { NAV, isActive } from "./nav-config";
import { NotificationBell } from "@/components/shared/notification-bell";
import { UserAvatar } from "@/components/ui/avatar";
import { signOut, switchHostel } from "@/lib/actions/session";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { toast } from "sonner";

export interface ShellUser {
  id: string;
  name: string;
  role: UserRole;
  email?: string | null;
}
export interface ShellHostel {
  id: string;
  name: string;
}

/**
 * Desktop shell — Super Admin / Owner / Manager.
 * Fixed 232px frosted sidebar (logo top, nav, user card bottom) + top bar with page
 * title / bell / avatar. Collapses to a drawer below md.
 *
 * These roles are opened on a phone too (the TWA is the same deployment), so the
 * chrome reads env(safe-area-inset-*) via `.app-bar` / `.app-sidebar` in
 * globals.css and every control in it is at least 44x44.
 *
 * The hostel name appears exactly ONCE here: in the top bar, where it is also
 * the hostel switcher. It used to appear a second time under the logo in the
 * sidebar, which is why /manager rendered "Sunrise Residency" three times.
 */
export function DesktopShell({
  user,
  hostel,
  hostels = [],
  unread = 0,
  banner,
  children,
}: {
  user: ShellUser;
  hostel?: ShellHostel | null;
  hostels?: ShellHostel[];
  unread?: number;
  banner?: React.ReactNode;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const [drawer, setDrawer] = React.useState(false);
  const items = NAV[user.role];
  const appName = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";

  React.useEffect(() => setDrawer(false), [pathname]);

  const Sidebar = (
    <aside className="app-sidebar material-chrome flex h-full w-sidebar flex-col border-r border-separator">
      <div className="mb-6 px-6">
        <Link href={items[0].href} className="block">
          <div className="text-title-3 font-bold text-navy">{appName}</div>
          {/*
            A product descriptor, not the hostel name and not the role. The
            hostel name lives in the top bar (where it is also the switcher) and
            repeating it here was one of the three copies the owner counted on
            /manager; the role is already on the user card at the bottom of this
            same sidebar, so putting it here would only trade one dupe for another.
          */}
          <div className="text-caption-1 text-muted">Management Suite</div>
        </Link>
      </div>

      <nav className="flex flex-1 flex-col gap-1 px-3">
        {items.map((item) => {
          const active = isActive(pathname, item);
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                // min-h-11 = 44pt. py-2.5 alone left these rows at 40px.
                "press-scale [--press:0.98] flex min-h-11 items-center gap-3 rounded-control px-3.5 py-2.5 text-subhead font-medium transition-all",
                active ? "bg-navy text-white shadow-elev-2" : "text-charcoal/80 hover:bg-material-tint/60 hover:text-navy",
              )}
            >
              <Icon className="h-[18px] w-[18px] shrink-0" strokeWidth={active ? 2 : 1.75} />
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="mt-auto border-t border-separator px-3 pt-4">
        <UserMenu user={user} hostel={hostel} hostels={hostels} />
      </div>
    </aside>
  );

  return (
    <div className="min-h-dvh">
      {/* Sidebar (desktop) */}
      <div className="fixed inset-y-0 left-0 z-40 hidden md:block">{Sidebar}</div>

      {/* Drawer (mobile fallback for desktop roles) */}
      {drawer && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-navy/25 backdrop-blur-sm animate-fade-in" onClick={() => setDrawer(false)} />
          <div className="absolute inset-y-0 left-0 animate-fade-in">{Sidebar}</div>
          <button
            aria-label="Close menu"
            onClick={() => setDrawer(false)}
            className="absolute left-[calc(232px+var(--safe-left)+8px)] top-[calc(16px+var(--safe-top))] flex h-11 w-11 items-center justify-center rounded-full bg-material-tint/85 text-navy shadow-elev-3 backdrop-blur-xl"
          >
            <X className="h-5 w-5" />
          </button>
        </div>
      )}

      {/* Top bar */}
      <header className="app-bar app-bar-wide material-chrome fixed inset-x-0 top-0 z-30 flex items-center justify-between gap-2 border-b border-separator md:left-sidebar">
        <div className="flex min-w-0 items-center gap-1.5">
          <button
            aria-label="Open menu"
            onClick={() => setDrawer(true)}
            className="-ml-3 flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-navy transition-colors hover:bg-fill-quaternary active:bg-fill-tertiary md:hidden"
          >
            <Menu className="h-5 w-5" />
          </button>
          <div className="min-w-0 text-subhead font-semibold text-navy md:text-callout md:font-semibold">
            {hostels.length > 1 && user.role === "owner" ? (
              <HostelSwitcher hostel={hostel} hostels={hostels} />
            ) : (
              <span className="inline-flex min-w-0 items-center gap-2">
                <Building2 className="h-4 w-4 shrink-0 text-navy/50" />
                <span className="truncate">{hostel?.name ?? appName}</span>
              </span>
            )}
          </div>
        </div>
        <div className="-mr-1.5 flex shrink-0 items-center gap-1">
          <NotificationBell initialUnread={unread} />
          <UserAvatar name={user.name} size="sm" className="ml-1" />
        </div>
      </header>

      {/* Content */}
      <main className="app-main app-main-inline pb-[calc(48px+var(--safe-bottom))] md:pl-[calc(232px+24px)] md:pr-page-desktop">
        {banner ? <div className="mb-5">{banner}</div> : null}
        <div className="mx-auto max-w-[1400px] animate-fade-in">{children}</div>
      </main>
    </div>
  );
}

function UserMenu({ user, hostel, hostels }: { user: ShellUser; hostel?: ShellHostel | null; hostels: ShellHostel[] }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="flex min-h-11 w-full items-center gap-3 rounded-control px-2 py-2 text-left transition-colors hover:bg-material-tint/60">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-sand-soft text-xs font-semibold text-sand-deep">
            {initials(user.name)}
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate text-sm font-semibold text-navy">{user.name}</div>
            <div className="truncate text-[11px] text-muted">{ROLE_LABEL[user.role]}</div>
          </div>
          <ChevronsUpDown className="h-4 w-4 text-muted" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent side="top" align="start" className="w-56">
        <DropdownMenuLabel className="font-normal">
          <div className="text-sm font-semibold text-navy">{user.name}</div>
          <div className="text-xs text-muted">{user.email ?? ROLE_LABEL[user.role]}</div>
        </DropdownMenuLabel>
        {hostels.length > 1 && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuLabel>Switch hostel</DropdownMenuLabel>
            {hostels.map((h) => (
              <DropdownMenuItem
                key={h.id}
                onSelect={async () => {
                  const res = await switchHostel(h.id);
                  if (!res.ok) toast.error(res.error);
                  else window.location.assign("/owner");
                }}
                className={cn(h.id === hostel?.id && "font-semibold text-navy")}
              >
                <Building2 /> {h.name}
              </DropdownMenuItem>
            ))}
          </>
        )}
        <DropdownMenuSeparator />
        <DropdownMenuItem asChild>
          <Link href="/change-password">Change password</Link>
        </DropdownMenuItem>
        <DropdownMenuItem asChild>
          <Link href="/security/mfa">
            <ShieldCheck /> Two-factor authentication
          </Link>
        </DropdownMenuItem>
        <DropdownMenuItem onSelect={() => signOut()} className="text-red focus:text-red">
          <LogOut /> Log out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function HostelSwitcher({ hostel, hostels }: { hostel?: ShellHostel | null; hostels: ShellHostel[] }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button className="inline-flex min-h-11 max-w-full items-center gap-2 rounded-full border border-material-strong bg-material-tint/60 px-3.5 py-1.5 text-sm font-semibold text-navy backdrop-blur-md hover:bg-material-tint/80">
          <Building2 className="h-4 w-4 shrink-0 text-navy/60" />
          <span className="truncate">{hostel?.name}</span>
          <ChevronsUpDown className="h-3.5 w-3.5 shrink-0 text-muted" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="w-64">
        <DropdownMenuLabel>Your hostels</DropdownMenuLabel>
        {hostels.map((h) => (
          <DropdownMenuItem
            key={h.id}
            onSelect={async () => {
              const res = await switchHostel(h.id);
              if (!res.ok) toast.error(res.error);
              else window.location.assign("/owner");
            }}
            className={cn(h.id === hostel?.id && "font-semibold text-navy")}
          >
            <Building2 /> {h.name}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
