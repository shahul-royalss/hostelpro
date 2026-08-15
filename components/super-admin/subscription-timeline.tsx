import { CalendarRange } from "lucide-react";
import type { SubscriptionRow } from "@/lib/types";
import { cn, daysUntil, formatDate, formatDateTime, formatINR, toISODate } from "@/lib/utils";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";

/** Live tone for one subscription period based on its dates (never trusts the stored status). */
function periodState(s: SubscriptionRow, today: string): "active" | "expiring" | "expired" | "upcoming" {
  if (s.start_date > today) return "upcoming";
  if (s.end_date < today) return "expired";
  const left = daysUntil(s.end_date) ?? 0;
  return left <= 15 ? "expiring" : "active";
}

/**
 * Subscription history timeline (SA-3 slide-over, SA-4 detail) — newest first.
 * Pure server-safe markup so it can be rendered inside a Sheet or a page.
 */
export function SubscriptionTimeline({ subscriptions, className }: { subscriptions: SubscriptionRow[]; className?: string }) {
  if (subscriptions.length === 0) {
    return <EmptyState compact icon={CalendarRange} title="No subscription periods yet" description="Renewals will appear here as a timeline." />;
  }
  const today = toISODate();
  const currentId = [...subscriptions].sort((a, b) => (a.end_date < b.end_date ? 1 : -1))[0]?.id;

  return (
    <ol className={cn("relative space-y-0", className)}>
      {subscriptions.map((s, i) => {
        const state = periodState(s, today);
        const isCurrent = s.id === currentId;
        const dotTone =
          state === "expired" ? "bg-red" : state === "expiring" ? "bg-sand-deep" : state === "upcoming" ? "bg-navy/40" : "bg-teal";
        const days = Math.max(1, Math.round((new Date(s.end_date).getTime() - new Date(s.start_date).getTime()) / 86_400_000) + 1);
        return (
          <li key={s.id} className="relative flex gap-4 pb-6 last:pb-0">
            {i < subscriptions.length - 1 ? <span className="absolute left-[7px] top-4 h-full w-px bg-line" aria-hidden /> : null}
            <span className={cn("relative mt-1 h-[15px] w-[15px] shrink-0 rounded-full border-[3px] border-white shadow-sm", dotTone)} aria-hidden />
            <div className="min-w-0 flex-1 rounded-card border border-line/70 bg-white/50 p-3.5">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="text-sm font-semibold text-navy tabular">
                  {formatDate(s.start_date)} <span className="text-muted">→</span> {formatDate(s.end_date)}
                </div>
                <div className="flex items-center gap-1.5">
                  {isCurrent ? <StatusPill tone="navy" label="Current" size="sm" /> : null}
                  <StatusPill status={state === "upcoming" ? undefined : state} tone={state === "upcoming" ? "muted" : undefined} label={state === "upcoming" ? "Upcoming" : undefined} size="sm" />
                </div>
              </div>
              <div className="mt-1.5 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted">
                <span>
                  Amount <span className="font-semibold text-navy tabular">{formatINR(s.amount)}</span>
                </span>
                <span>{days} days</span>
                <span>Recorded {formatDateTime(s.created_at)}</span>
              </div>
              {s.notes ? <p className="mt-2 text-[13px] leading-relaxed text-charcoal">{s.notes}</p> : null}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
