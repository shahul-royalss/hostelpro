import "server-only";
import * as React from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getHostelContext, requireRole } from "@/lib/permissions";
import type { UserRole } from "@/lib/roles";
import { DesktopShell } from "./desktop-shell";
import { MobileShell } from "./mobile-shell";
import { SubscriptionBanner } from "@/components/shared/subscription-banner";
import { firstName, greeting } from "@/lib/utils";

async function unreadCount() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("rpc_unread_count");
  return Number(data ?? 0);
}

/** true when the signed-in account has NO verified TOTP factor (decoded from the local session, no network). */
async function mfaMissing() {
  const supabase = await createClient();
  const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  return data?.nextLevel !== "aal2";
}

function MfaNudge() {
  return (
    <div role="status" className="flex flex-wrap items-center justify-between gap-3 rounded-control border border-sand/50 bg-sand-soft px-4 py-3 text-sm text-sand-deep">
      <span>
        <strong>Protect this account with two-factor authentication.</strong> Admin and owner accounts control money and personal data —
        add an authenticator app.
      </span>
      <Link href="/security/mfa" className="rounded-control bg-navy px-3 py-1.5 text-xs font-semibold text-white hover:bg-navy/90">
        Set up 2FA
      </Link>
    </div>
  );
}

/**
 * Desktop shell for Super Admin / Owner / Manager layouts.
 * Usage in app/<role>/layout.tsx:  return <DesktopRoleShell role="owner">{children}</DesktopRoleShell>
 */
export async function DesktopRoleShell({
  role,
  children,
}: {
  role: Extract<UserRole, "super_admin" | "owner" | "manager">;
  children: React.ReactNode;
}) {
  const user = await requireRole(role);
  const [ctx, unread, noMfa] = await Promise.all([role === "super_admin" ? null : getHostelContext(), unreadCount(), mfaMissing()]);
  const nudge = (role === "super_admin" || role === "owner") && noMfa;

  return (
    <DesktopShell
      user={{ id: user.id, name: user.full_name, role: user.role, email: user.email }}
      hostel={ctx ? { id: ctx.hostel.id, name: ctx.hostel.name } : null}
      hostels={ctx?.hostels.map((h) => ({ id: h.id, name: h.name })) ?? []}
      unread={unread}
      banner={
        ctx || nudge ? (
          <div className="space-y-3">
            {nudge ? <MfaNudge /> : null}
            {ctx ? <SubscriptionBanner ctx={ctx} role={role} /> : null}
          </div>
        ) : null
      }
    >
      {children}
    </DesktopShell>
  );
}

/**
 * Mobile page wrapper for Warden / Student pages.
 * Usage:  <MobilePage role="warden" title="Rooms" backHref="/warden">…</MobilePage>
 * Pass title="greeting" for the home screens ("Good morning, Priya").
 */
export async function MobilePage({
  role,
  title,
  subtitle,
  backHref,
  hideNav,
  actions,
  children,
  contentClassName,
}: {
  role: Extract<UserRole, "warden" | "student">;
  title: React.ReactNode | "greeting";
  subtitle?: React.ReactNode;
  backHref?: string;
  hideNav?: boolean;
  actions?: React.ReactNode;
  children: React.ReactNode;
  contentClassName?: string;
}) {
  const user = await requireRole(role);
  const [ctx, unread] = await Promise.all([getHostelContext(), unreadCount()]);

  const resolvedTitle = title === "greeting" ? `${greeting()}, ${firstName(user.full_name)}` : title;
  const resolvedSubtitle = subtitle ?? (title === "greeting" ? ctx?.hostel.name : undefined);

  return (
    <MobileShell
      role={role}
      title={resolvedTitle}
      subtitle={resolvedSubtitle}
      avatarName={user.full_name}
      unread={unread}
      backHref={backHref}
      hideNav={hideNav}
      actions={actions}
      contentClassName={contentClassName}
      banner={ctx ? <SubscriptionBanner ctx={ctx} role={role} /> : null}
    >
      {children}
    </MobileShell>
  );
}
