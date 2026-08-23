import * as React from "react";
import { AlertTriangle, CalendarClock, Lock } from "lucide-react";
import type { HostelContext } from "@/lib/permissions";
import { cn } from "@/lib/utils";

/**
 * Persistent renewal banner (Hard rule §4.4).
 *  • expired / read-only → red, "all changes are disabled"
 *  • suspended → red
 *  • expiring (≤15 days) → sand
 * Only Owner sees the expiring warning; every tenant role sees the read-only lock.
 */
export function SubscriptionBanner({ ctx, role, className }: { ctx: HostelContext; role: string; className?: string }) {
  const { hostel, subscriptionState, daysLeft, writable } = ctx;

  if (hostel.status === "suspended") {
    return (
      <Banner tone="red" icon={Lock} className={className}>
        <strong>This hostel is suspended.</strong> All changes are disabled — please contact NIVORA support.
      </Banner>
    );
  }
  if (!writable || subscriptionState === "expired") {
    return (
      <Banner tone="red" icon={Lock} className={className}>
        <strong>Subscription expired — read-only mode.</strong> You can view everything, but no changes can be saved until
        the subscription is renewed{role === "owner" ? ". Contact NIVORA to renew." : " by the owner."}
      </Banner>
    );
  }
  if (role === "owner" && subscriptionState === "expiring") {
    return (
      <Banner tone="sand" icon={CalendarClock} className={className}>
        <strong>Subscription ends in {daysLeft} day{daysLeft === 1 ? "" : "s"}.</strong> Renew soon to avoid read-only mode.
      </Banner>
    );
  }
  return null;
}

function Banner({
  tone,
  icon: Icon,
  children,
  className,
}: {
  tone: "red" | "sand";
  icon: typeof AlertTriangle;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      role="status"
      className={cn(
        "flex items-start gap-3 rounded-control border px-4 py-3 text-sm",
        tone === "red" ? "border-red/30 bg-red-soft text-red" : "border-sand/50 bg-sand-soft text-sand-deep",
        className,
      )}
    >
      <Icon className="mt-0.5 h-4 w-4 shrink-0" />
      <p>{children}</p>
    </div>
  );
}
