"use client";

import * as React from "react";
import { CalendarDays, CalendarOff, Check, Info, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { UserAvatar } from "@/components/ui/avatar";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { Chip, StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { useAction } from "@/hooks/use-action";
import { decideLeave } from "@/lib/actions/warden";
import type { LeaveWithStudent } from "@/lib/queries/warden";
import { cn, formatDate, formatDateTime } from "@/lib/utils";
import { differenceInCalendarDays } from "date-fns";

function nights(l: LeaveWithStudent) {
  const d = differenceInCalendarDays(new Date(l.to_date), new Date(l.from_date));
  return Number.isFinite(d) ? d + 1 : 1;
}
function dateRange(l: LeaveWithStudent) {
  return l.from_date === l.to_date ? formatDate(l.from_date, "d MMM") : `${formatDate(l.from_date, "d MMM")} – ${formatDate(l.to_date, "d MMM")}`;
}

export function LeavesView({ leaves, writable }: { leaves: LeaveWithStudent[]; writable: boolean }) {
  const pending = leaves.filter((l) => l.status === "pending");
  const history = leaves.filter((l) => l.status !== "pending");
  const [decision, setDecision] = React.useState<{ leave: LeaveWithStudent; status: "approved" | "rejected" } | null>(null);
  const [showAllHistory, setShowAllHistory] = React.useState(false);
  const visibleHistory = showAllHistory ? history : history.slice(0, 8);

  return (
    <div className="flex flex-col gap-5">
      {/* Pending */}
      <section aria-labelledby="pending-title">
        <div className="mb-3 flex items-center justify-between px-1">
          <h2 id="pending-title" className="text-title-sm text-navy">
            Pending requests
          </h2>
          {pending.length > 0 ? <Chip tone="sand">{pending.length} new</Chip> : null}
        </div>
        {pending.length === 0 ? (
          <GlassCard>
            <EmptyState icon={CalendarOff} title="No pending leave requests" description="New requests from students will appear here." compact />
          </GlassCard>
        ) : (
          <ul className="flex flex-col gap-3">
            {pending.map((l) => (
              <GlassCard key={l.id} as="article" className="p-4" aria-label={`Leave request from ${l.student?.full_name ?? "student"}`}>
                <div className="flex items-center gap-3">
                  <UserAvatar name={l.student?.full_name} src={l.student?.photo_url} size="md" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[15px] font-semibold text-navy">{l.student?.full_name ?? "Student"}</p>
                    <div className="mt-1 flex items-center gap-1.5">
                      <Chip tone="sand">{l.student?.room_number ? `Room ${l.student.room_number}` : "No room"}</Chip>
                      <span className="text-[11px] text-muted">Requested {formatDateTime(l.created_at)}</span>
                    </div>
                  </div>
                </div>
                <div className="mt-3 flex flex-col gap-1.5 rounded-control bg-white/50 p-3 text-[13px]">
                  <p className="flex items-center gap-2 font-medium text-navy">
                    <CalendarDays className="h-4 w-4 text-navy/50" /> {dateRange(l)}
                    <span className="font-normal text-muted">
                      · {nights(l)} {nights(l) === 1 ? "day" : "days"}
                    </span>
                  </p>
                  <p className="flex items-start gap-2 text-charcoal">
                    <Info className="mt-0.5 h-4 w-4 shrink-0 text-navy/50" />
                    <span>Reason: {l.reason?.trim() || "—"}</span>
                  </p>
                </div>
                {writable ? (
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    <Button variant="outline-red" size="lg" onClick={() => setDecision({ leave: l, status: "rejected" })}>
                      <X className="h-4 w-4" /> Reject
                    </Button>
                    <Button variant="outline-sage" size="lg" onClick={() => setDecision({ leave: l, status: "approved" })}>
                      <Check className="h-4 w-4" /> Approve
                    </Button>
                  </div>
                ) : (
                  <p className="mt-3 text-[12px] text-muted">Decisions are disabled while the hostel is read-only.</p>
                )}
              </GlassCard>
            ))}
          </ul>
        )}
      </section>

      {/* History */}
      <section aria-labelledby="history-title">
        <h2 id="history-title" className="mb-3 px-1 text-title-sm text-navy">
          History
        </h2>
        {history.length === 0 ? (
          <GlassCard>
            <EmptyState icon={CalendarOff} title="No decided leaves yet" compact />
          </GlassCard>
        ) : (
          <GlassCard className="p-0">
            <ul className="divide-y divide-line">
              {visibleHistory.map((l) => (
                <li key={l.id} className="flex items-center gap-3 px-4 py-3">
                  <UserAvatar name={l.student?.full_name} src={l.student?.photo_url} size="sm" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-navy">{l.student?.full_name ?? "Student"}</p>
                    <p className="truncate text-[12px] text-muted">
                      {dateRange(l)}
                      {l.student?.room_number ? ` · Room ${l.student.room_number}` : ""}
                      {l.decision_note ? ` · “${l.decision_note}”` : ""}
                    </p>
                  </div>
                  <StatusPill status={l.status} size="sm" />
                </li>
              ))}
            </ul>
            {history.length > visibleHistory.length ? (
              <button type="button" onClick={() => setShowAllHistory(true)} className="w-full border-t border-line py-3 text-center text-[13px] font-medium text-navy hover:bg-white/50">
                Show all {history.length}
              </button>
            ) : null}
          </GlassCard>
        )}
      </section>

      <DecideDialog target={decision} onOpenChange={(o) => !o && setDecision(null)} />
    </div>
  );
}

function DecideDialog({ target, onOpenChange }: { target: { leave: LeaveWithStudent; status: "approved" | "rejected" } | null; onOpenChange: (open: boolean) => void }) {
  const [note, setNote] = React.useState("");
  const { run, pending } = useAction(decideLeave, { onSuccess: () => onOpenChange(false) });
  React.useEffect(() => {
    if (target) setNote("");
  }, [target]);
  const approve = target?.status === "approved";

  return (
    <Dialog open={!!target} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <div className={cn("mb-1 flex h-11 w-11 items-center justify-center rounded-full", approve ? "bg-sage-soft text-sage" : "bg-red-soft text-red")}>
            {approve ? <Check className="h-5 w-5" /> : <X className="h-5 w-5" />}
          </div>
          <DialogTitle>{approve ? "Approve" : "Reject"} leave?</DialogTitle>
          <DialogDescription>
            {target ? (
              <>
                <span className="font-medium text-charcoal">{target.leave.student?.full_name ?? "Student"}</span> · {dateRange(target.leave)}. The student is notified of your decision.
              </>
            ) : null}
          </DialogDescription>
        </DialogHeader>
        <Field label="Note (optional)" htmlFor="decision-note">
          <Textarea id="decision-note" rows={2} maxLength={300} placeholder={approve ? "e.g. Return by 8 PM" : "e.g. Exams next week"} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        <DialogFooter className="mt-2 gap-2">
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button
            variant={approve ? "teal" : "destructive"}
            loading={pending}
            onClick={() => target && run({ leaveId: target.leave.id, status: target.status, note: note.trim() || undefined })}
          >
            {approve ? "Approve" : "Reject"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
