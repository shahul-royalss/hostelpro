"use client";

import * as React from "react";
import { usePathname, useRouter } from "next/navigation";
import { CalendarOff, CalendarRange, MessageSquare, Plus } from "lucide-react";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { Button } from "@/components/ui/button";
import type { LeaveRow } from "@/lib/types";
import { cn, formatDate, formatDateTime } from "@/lib/utils";
import { ApplyLeaveSheet } from "./apply-leave-sheet";

function dayCount(from: string, to: string): number {
  const a = new Date(from).getTime();
  const b = new Date(to).getTime();
  if (Number.isNaN(a) || Number.isNaN(b)) return 0;
  return Math.max(1, Math.round((b - a) / 86_400_000) + 1);
}

const READ_ONLY_MESSAGE = "Subscription expired — the hostel is read-only";

const ICON_TONE: Record<LeaveRow["status"], string> = {
  pending: "bg-sand-soft text-sand-deep",
  approved: "bg-teal-soft text-teal",
  rejected: "bg-red-soft text-red",
};

export function LeaveView({
  leaves,
  writable,
  openNew = false,
}: {
  leaves: LeaveRow[];
  writable: boolean;
  /** true when the page was reached via ?new=1 (home quick tile) */
  openNew?: boolean;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [open, setOpen] = React.useState(false);

  // ?new=1 opens the sheet once, then the query is dropped so a refresh doesn't reopen it.
  React.useEffect(() => {
    if (!openNew) return;
    if (writable) setOpen(true);
    router.replace(pathname, { scroll: false });
  }, [openNew, pathname, router, writable]);

  const pending = leaves.filter((l) => l.status === "pending").length;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Button size="xl" onClick={() => setOpen(true)} disabled={!writable} title={writable ? undefined : READ_ONLY_MESSAGE}>
          <Plus /> Apply for leave
        </Button>
        {!writable ? <p className="px-1 text-center text-[12px] text-muted">{READ_ONLY_MESSAGE}.</p> : null}
      </div>

      {leaves.length === 0 ? (
        <GlassCard>
          <EmptyState
            icon={CalendarOff}
            title="No leave requests yet"
            description="Going home for a few days? Apply here and your warden will respond."
          />
        </GlassCard>
      ) : (
        <section>
          <div className="mb-3 flex items-baseline justify-between px-1">
            <h2 className="text-card-title font-semibold text-navy">My requests</h2>
            <span className="text-[12px] text-muted">
              {pending ? `${pending} awaiting decision` : `${leaves.length} total`}
            </span>
          </div>
          <ul className="flex flex-col gap-3">
            {leaves.map((l) => {
              const days = dayCount(l.from_date, l.to_date);
              return (
                <li key={l.id} className="glass-card p-4">
                  <div className="flex items-start gap-3">
                    <span className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-full", ICON_TONE[l.status])}>
                      <CalendarRange className="h-[18px] w-[18px]" strokeWidth={1.75} />
                    </span>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <div className="text-sm font-semibold text-navy">
                            {formatDate(l.from_date, "d MMM")} → {formatDate(l.to_date, "d MMM yyyy")}
                          </div>
                          <div className="mt-0.5 text-[12px] text-muted">
                            {days} {days === 1 ? "day" : "days"} · Applied {formatDate(l.created_at)}
                          </div>
                        </div>
                        <StatusPill status={l.status} size="sm" />
                      </div>
                      {l.reason ? <p className="mt-2 text-[13px] leading-relaxed text-charcoal/90">{l.reason}</p> : null}
                      {l.status !== "pending" ? (
                        <div
                          className={cn(
                            "mt-3 rounded-control px-3.5 py-2.5",
                            l.status === "approved" ? "bg-teal-soft/60" : "bg-red-soft/60",
                          )}
                        >
                          <div className={cn("label-caps", l.status === "approved" ? "text-teal" : "text-red")}>
                            {l.status === "approved" ? "Approved" : "Rejected"}
                            {l.decided_at ? ` · ${formatDateTime(l.decided_at)}` : ""}
                          </div>
                          {l.decision_note ? (
                            <p className="mt-1 flex items-start gap-1.5 text-[13px] text-charcoal">
                              <MessageSquare className="mt-0.5 h-3 w-3 shrink-0 text-muted" />
                              <span>{l.decision_note}</span>
                            </p>
                          ) : (
                            <p className="mt-1 text-[12px] text-muted">No note from your warden.</p>
                          )}
                        </div>
                      ) : (
                        <p className="mt-2 text-[12px] text-sand-deep">Waiting for your warden&apos;s decision.</p>
                      )}
                    </div>
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      <ApplyLeaveSheet open={open} onOpenChange={setOpen} />
    </div>
  );
}
