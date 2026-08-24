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
 * ONE HOME FOR THE HOSTEL NAME.
 *
 * Measured on production with an Android UA before this change: /manager
 * printed "Sunrise Residency" three times, /warden and /student twice each.
 *
 * The rule now, for the whole app:
 *
 *   The hostel name belongs to the CHROME, once per screen, and only on a root
 *   screen. On mobile that is the app-bar subtitle of the tab roots; on desktop
 *   it is the top bar, where it doubles as the hostel switcher. It is not
 *   repeated in page bodies, and it is not repeated on a pushed sub-page —
 *   once you have navigated into "Fees", you already know whose fees.
 *
 * Sub-pages kept passing it anyway ("Sunrise Residency", "Aug 2026 · Sunrise
 * Residency", "3 open · Sunrise Residency"), so the removal happens here, once,
 * rather than at a dozen call sites that a future page can quietly re-add to.
 * A subtitle that is *only* the hostel name disappears; one that carries it as
 * a "·" segment keeps everything else.
 */
function withoutHostelName(subtitle: React.ReactNode, hostel?: string | null): React.ReactNode {
  if (!hostel || typeof subtitle !== "string") return subtitle;
  const kept = subtitle
    .split("·")
    .map((part) => part.trim())
    .filter((part) => part.length > 0 && part !== hostel);
  return kept.length ? kept.join(" · ") : undefined;
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
  const hostelName = ctx?.hostel.name ?? null;
  // A screen with a back arrow is a pushed screen: it inherits its context from
  // the root it came from, so the hostel name is stripped there and kept here.
  const resolvedSubtitle = backHref
    ? withoutHostelName(subtitle, hostelName)
    : subtitle ?? (title === "greeting" ? hostelName ?? undefined : undefined);

  return (
    <MobileShell
      role={role}
      title={resolvedTitle}
      subtitle={resolvedSubtitle}
      hostelName={hostelName}
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
