"use client";

import * as React from "react";
import Image from "next/image";
import { Check, ChevronRight, CircleHelp, Loader2, MessageSquareWarning, Sparkles, Users, UtensilsCrossed, Wifi, Wrench, type LucideIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Field } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { Chip, StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { ComplaintTimeline } from "@/components/shared/complaint-timeline";
import { useAction } from "@/hooks/use-action";
import { updateComplaintStatus } from "@/lib/actions/complaints";
import type { ComplaintWithStudent } from "@/lib/queries/warden";
import type { ComplaintCategory, ComplaintStatus } from "@/lib/types";
import { cn, formatDateTime } from "@/lib/utils";

export type ComplaintItem = ComplaintWithStudent & { photoUrl: string | null };

const ICON: Record<ComplaintCategory, LucideIcon> = {
  food: UtensilsCrossed,
  cleaning: Sparkles,
  maintenance: Wrench,
  wifi: Wifi,
  roommate: Users,
  other: CircleHelp,
};
const CATEGORY_LABEL: Record<ComplaintCategory, string> = {
  food: "Food",
  cleaning: "Cleaning",
  maintenance: "Maintenance",
  wifi: "Wi-Fi",
  roommate: "Roommate",
  other: "Other",
};

type Filter = "all" | ComplaintStatus;

export function ComplaintsView({ complaints, writable }: { complaints: ComplaintItem[]; writable: boolean }) {
  const [filter, setFilter] = React.useState<Filter>("all");
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const selected = complaints.find((c) => c.id === selectedId) ?? null;

  const counts = React.useMemo(() => {
    const c: Record<Filter, number> = { all: complaints.length, open: 0, in_progress: 0, resolved: 0 };
    for (const x of complaints) c[x.status] += 1;
    return c;
  }, [complaints]);
  const visible = filter === "all" ? complaints : complaints.filter((c) => c.status === filter);

  return (
    <div className="flex flex-col gap-4">
      <SegmentedPills<Filter>
        ariaLabel="Filter complaints"
        size="sm"
        className="-mx-4 px-4"
        options={[
          { value: "all", label: "All", count: counts.all },
          { value: "open", label: "Open", count: counts.open, tone: "red" },
          { value: "in_progress", label: "In progress", count: counts.in_progress, tone: "sand" },
          { value: "resolved", label: "Resolved", count: counts.resolved, tone: "teal" },
        ]}
        value={filter}
        onChange={setFilter}
      />

      {visible.length === 0 ? (
        <GlassCard>
          <EmptyState
            icon={MessageSquareWarning}
            title={complaints.length === 0 ? "No complaints yet" : "Nothing here"}
            description={complaints.length === 0 ? "Complaints raised by students will appear here." : "Try another filter."}
          />
        </GlassCard>
      ) : (
        <ul className="flex flex-col gap-2.5">
          {visible.map((c) => {
            const Icon = ICON[c.category] ?? CircleHelp;
            return (
              <li key={c.id}>
                <button
                  type="button"
                  onClick={() => setSelectedId(c.id)}
                  className="glass-card flex w-full items-center gap-3 p-3.5 text-left transition-colors hover:bg-white/80 active:scale-[0.99]"
                  aria-label={`Open complaint: ${c.title}`}
                >
                  <span
                    className={cn(
                      "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
                      c.status === "open" ? "bg-red-soft text-red" : c.status === "in_progress" ? "bg-sand-soft text-sand-deep" : "bg-teal-soft text-teal",
                    )}
                  >
                    <Icon className="h-4 w-4" strokeWidth={1.75} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-semibold text-navy">{c.title}</p>
                    <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] text-muted">
                      <span className="truncate">{c.student?.full_name ?? "Student"}</span>
                      {c.student?.room_number ? <Chip tone="muted">Room {c.student.room_number}</Chip> : null}
                      <span>· {formatDateTime(c.created_at)}</span>
                    </div>
                  </div>
                  <StatusPill status={c.status} size="sm" />
                  <ChevronRight className="h-4 w-4 shrink-0 text-muted/70" />
                </button>
              </li>
            );
          })}
        </ul>
      )}

      <ComplaintSheet complaint={selected} writable={writable} onOpenChange={(o) => !o && setSelectedId(null)} />
    </div>
  );
}

/* ───────────────────────── detail sheet ───────────────────────── */

function ComplaintSheet({ complaint: c, writable, onOpenChange }: { complaint: ComplaintItem | null; writable: boolean; onOpenChange: (open: boolean) => void }) {
  const [note, setNote] = React.useState("");
  const { run, pending } = useAction(updateComplaintStatus, { onSuccess: () => onOpenChange(false) });
  React.useEffect(() => {
    if (c) setNote(c.resolution_note ?? "");
  }, [c]);

  const Icon = c ? ICON[c.category] ?? CircleHelp : CircleHelp;

  return (
    <Sheet open={!!c} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        {c ? (
          <>
            <SheetHeader>
              <div className="flex items-center gap-2">
                <Chip tone="navy">
                  <Icon className="mr-1 h-3 w-3" /> {CATEGORY_LABEL[c.category] ?? c.category}
                </Chip>
                <StatusPill status={c.status} size="sm" />
              </div>
              <SheetTitle className="pr-8">{c.title}</SheetTitle>
              <SheetDescription>
                {c.student?.full_name ?? "Student"}
                {c.student?.room_number ? ` · Room ${c.student.room_number}` : ""} · {formatDateTime(c.created_at)}
              </SheetDescription>
            </SheetHeader>

            <div className="mt-4 flex max-h-[52dvh] flex-col gap-4 overflow-y-auto pr-1">
              {c.description ? <p className="whitespace-pre-line text-sm text-charcoal">{c.description}</p> : <p className="text-sm text-muted">No description provided.</p>}

              {c.photo_url ? (
                c.photoUrl ? (
                  <a href={c.photoUrl} target="_blank" rel="noreferrer" className="relative block h-44 w-full overflow-hidden rounded-control bg-stone">
                    <Image src={c.photoUrl} alt="Complaint photo" fill unoptimized className="object-cover" sizes="(max-width: 480px) 100vw, 480px" />
                  </a>
                ) : (
                  <p className="rounded-control bg-stone px-3 py-2 text-[12px] text-muted">A photo was attached but can&apos;t be displayed right now.</p>
                )
              ) : null}

              <div>
                <div className="label-caps mb-2">Timeline</div>
                <ComplaintTimeline events={c.events} compact />
              </div>

              {writable && c.status !== "resolved" ? (
                <Field label="Note (optional)" htmlFor="complaint-note" hint="Shared with the student on the timeline.">
                  <Textarea id="complaint-note" rows={2} maxLength={2000} placeholder="What was done / next step" value={note} onChange={(e) => setNote(e.target.value)} />
                </Field>
              ) : c.resolution_note ? (
                <div className="rounded-control bg-teal-soft/60 p-3 text-[13px] text-charcoal">
                  <span className="label-caps mb-1 block text-teal">Resolution note</span>
                  {c.resolution_note}
                </div>
              ) : null}
            </div>

            {writable ? (
              c.status === "resolved" ? (
                <Button variant="secondary" size="xl" className="mt-4" loading={pending} onClick={() => run({ complaintId: c.id, status: "open", resolutionNote: note.trim() || null })}>
                  Reopen complaint
                </Button>
              ) : (
                <div className="mt-4 grid grid-cols-2 gap-2">
                  <Button
                    variant="secondary"
                    size="lg"
                    disabled={pending}
                    onClick={() => run({ complaintId: c.id, status: "in_progress", resolutionNote: note.trim() || null })}
                  >
                    <Loader2 className="h-4 w-4" /> {c.status === "in_progress" ? "Save note" : "In progress"}
                  </Button>
                  <Button variant="teal" size="lg" loading={pending} onClick={() => run({ complaintId: c.id, status: "resolved", resolutionNote: note.trim() || null })}>
                    <Check className="h-4 w-4" /> Resolve
                  </Button>
                </div>
              )
            ) : (
              <p className="mt-4 text-[12px] text-muted">Status updates are disabled while the hostel is read-only.</p>
            )}
          </>
        ) : null}
      </SheetContent>
    </Sheet>
  );
}
