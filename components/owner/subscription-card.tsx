import * as React from "react";
import { CalendarClock, Lock } from "lucide-react";
import type { HostelContext } from "@/lib/permissions";
import { cn } from "@/lib/utils";

/** OW-1 header card: "Subscription · 42 days left" (sand; red when expired / ≤ 7 days). */
export function SubscriptionCard({ ctx, className }: { ctx: HostelContext; className?: string }) {
  const { daysLeft, subscriptionState, hostel } = ctx;
  const expired = subscriptionState === "expired" || daysLeft === null || daysLeft < 0;
  const critical = expired || (daysLeft !== null && daysLeft <= 7) || hostel.status !== "active";
  const Icon = expired ? Lock : CalendarClock;

  const headline = expired
    ? "Expired"
    : daysLeft === 0
      ? "Ends today"
      : `${daysLeft} day${daysLeft === 1 ? "" : "s"} left`;

  return (
    <div
      className={cn(
        "flex items-center gap-3 rounded-card border px-4 py-3 shadow-glass backdrop-blur-md",
        critical ? "border-red/20 bg-red-soft/80" : "border-sand/40 bg-sand-soft/80",
        className,
      )}
    >
      <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-full", critical ? "bg-red/10 text-red" : "bg-sand/30 text-sand-deep")}>
        <Icon className="h-4 w-4" strokeWidth={1.75} />
      </span>
      <div className="min-w-0">
        <div className={cn("label-caps", critical ? "text-red/80" : "text-sand-deep/80")}>Subscription</div>
        <div className={cn("text-[15px] font-semibold leading-tight", critical ? "text-red" : "text-sand-deep")}>{headline}</div>
      </div>
    </div>
  );
}
