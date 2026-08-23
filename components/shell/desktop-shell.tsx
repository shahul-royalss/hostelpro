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
    <aside className="glass-bar flex h-full w-sidebar flex-col border-r py-6">
      <div className="mb-6 px-6">
        <Link href={items[0].href} className="block">
          <div className="text-[20px] font-bold tracking-tight text-navy">{appName}</div>
          <div className="text-xs text-muted">{hostel?.name ?? "Management Suite"}</div>
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
                "flex items-center gap-3 rounded-control px-3.5 py-2.5 text-[15px] font-medium transition-all active:scale-[0.98]",
                active ? "bg-navy text-white shadow-sm" : "text-charcoal/80 hover:bg-white/60 hover:text-navy",
              )}
            >
              <Icon className="h-[18px] w-[18px]" strokeWidth={active ? 2 : 1.75} />
              {item.label}
            </Link>
          );
        })}
      </nav>

      <div className="mt-auto border-t border-white/60 px-3 pt-4">
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
          <div className="absolute inset-0 bg-navy/20 backdrop-blur-sm" onClick={() => setDrawer(false)} />
          <div className="absolute inset-y-0 left-0">{Sidebar}</div>
          <button
            aria-label="Close menu"
            onClick={() => setDrawer(false)}
            className="absolute left-[244px] top-4 rounded-full bg-white/80 p-2 text-navy shadow-glass"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      )}

      {/* Top bar */}
      <header className="glass-bar fixed inset-x-0 top-0 z-30 flex h-16 items-center justify-between border-b px-4 md:left-sidebar md:px-page-desktop">
        <div className="flex items-center gap-3">
          <button
            aria-label="Open menu"
            onClick={() => setDrawer(true)}
            className="rounded-full p-2 text-navy hover:bg-navy/5 md:hidden"
          >
            <Menu className="h-5 w-5" />
          </button>
          <div className="text-[15px] font-semibold text-navy md:text-base">
            {hostels.length > 1 && user.role === "owner" ? (
              <HostelSwitcher hostel={hostel} hostels={hostels} />
            ) : (
              <span className="inline-flex items-center gap-2">
                <Building2 className="h-4 w-4 text-navy/50" />
                {hostel?.name ?? appName}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <NotificationBell initialUnread={unread} />
          <UserAvatar name={user.name} size="sm" className="ml-1" />
        </div>
      </header>

      {/* Content */}
      <main className="px-4 pb-12 pt-[84px] md:pl-[calc(232px+24px)] md:pr-page-desktop">
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
        <button className="flex w-full items-center gap-3 rounded-control px-2 py-2 text-left transition-colors hover:bg-white/60">
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
        <button className="inline-flex items-center gap-2 rounded-full border border-white/70 bg-white/60 px-3 py-1.5 text-sm font-semibold text-navy backdrop-blur-md hover:bg-white/80">
          <Building2 className="h-4 w-4 text-navy/60" />
          {hostel?.name}
          <ChevronsUpDown className="h-3.5 w-3.5 text-muted" />
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
