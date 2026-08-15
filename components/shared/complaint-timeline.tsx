import * as React from "react";
import { Check, Clock, Loader2, MessageSquare } from "lucide-react";
import type { ComplaintEventRow, ComplaintStatus } from "@/lib/types";
import { formatDateTime, cn } from "@/lib/utils";
import { STATUS_LABEL } from "./status-pill";

const icon: Record<ComplaintStatus, React.ReactNode> = {
  open: <Clock className="h-3.5 w-3.5" />,
  in_progress: <Loader2 className="h-3.5 w-3.5" />,
  resolved: <Check className="h-3.5 w-3.5" />,
};
const tone: Record<ComplaintStatus, string> = {
  open: "bg-red-soft text-red",
  in_progress: "bg-sand-soft text-sand-deep",
  resolved: "bg-teal-soft text-teal",
};

/**
 * Vertical status timeline built from complaint_events (oldest → newest).
 * Used by Owner (OW-2 right pane), Warden (complaints), Student (ST-4 expanded card).
 */
export function ComplaintTimeline({
  events,
  className,
  compact = false,
}: {
  events: ComplaintEventRow[];
  className?: string;
  compact?: boolean;
}) {
  if (!events.length) return <p className="text-sm text-muted">No activity yet.</p>;
  return (
    <ol className={cn("relative", className)}>
      {events.map((e, i) => {
        const last = i === events.length - 1;
        return (
          <li key={e.id} className="relative flex gap-3 pb-4 last:pb-0">
            {!last && <span className="absolute left-[11px] top-6 h-[calc(100%-8px)] w-px bg-line" aria-hidden />}
            <span className={cn("relative z-10 flex h-6 w-6 shrink-0 items-center justify-center rounded-full", tone[e.status])}>
              {icon[e.status]}
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-baseline justify-between gap-x-3">
                <span className={cn("font-medium text-navy", compact ? "text-[13px]" : "text-sm")}>
                  {STATUS_LABEL[e.status] ?? e.status.charAt(0).toUpperCase() + e.status.slice(1)}
                </span>
                <span className="text-[11px] text-muted tabular">{formatDateTime(e.created_at)}</span>
              </div>
              {e.note ? (
                <p className={cn("mt-1 flex items-start gap-1.5 text-muted", compact ? "text-[12px]" : "text-[13px]")}>
                  <MessageSquare className="mt-0.5 h-3 w-3 shrink-0" />
                  <span>{e.note}</span>
                </p>
              ) : null}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
