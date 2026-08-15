"use client";

import * as React from "react";
import { usePathname, useRouter } from "next/navigation";
import { ChevronDown, ClipboardList, Plus } from "lucide-react";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { ComplaintTimeline } from "@/components/shared/complaint-timeline";
import { Button } from "@/components/ui/button";
import type { ComplaintEventRow, ComplaintRow } from "@/lib/types";
import { cn, formatDate } from "@/lib/utils";
import { COMPLAINT_CATEGORY_LABEL, COMPLAINT_ICON } from "./complaint-icons";
import { NewComplaintSheet } from "./new-complaint-sheet";

export interface ComplaintWithEvents extends ComplaintRow {
  events: ComplaintEventRow[];
  photoSrc: string | null;
}

export function ComplaintsView({
  complaints,
  writable,
  openNew = false,
}: {
  complaints: ComplaintWithEvents[];
  writable: boolean;
  /** true when the page was reached via ?new=1 (home quick tile) */
  openNew?: boolean;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [open, setOpen] = React.useState(false);
  const [expanded, setExpanded] = React.useState<string | null>(null);

  // ?new=1 opens the sheet once, then the query is dropped so a refresh doesn't reopen it.
  React.useEffect(() => {
    if (openNew && writable) {
      setOpen(true);
      router.replace(pathname, { scroll: false });
    }
  }, [openNew, pathname, router, writable]);

  return (
    <>
      {complaints.length === 0 ? (
        <GlassCard>
          <EmptyState
            icon={ClipboardList}
            title="No complaints yet"
            description="Something not right? Raise a complaint and track it here."
            action={
              writable ? (
                <Button onClick={() => setOpen(true)}>
                  <Plus /> Raise complaint
                </Button>
              ) : null
            }
          />
        </GlassCard>
      ) : (
        <ul className="flex flex-col gap-3">
          {complaints.map((c) => {
            const Icon = COMPLAINT_ICON[c.category];
            const isOpen = expanded === c.id;
            return (
              <li key={c.id} className="glass-card overflow-hidden">
                <button
                  type="button"
                  onClick={() => setExpanded(isOpen ? null : c.id)}
                  aria-expanded={isOpen}
                  className="flex w-full items-center gap-3 p-4 text-left"
                >
                  <span
                    className={cn(
                      "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
                      c.status === "open" ? "bg-red-soft text-red" : c.status === "in_progress" ? "bg-sand-soft text-sand-deep" : "bg-teal-soft text-teal",
                    )}
                  >
                    <Icon className="h-[18px] w-[18px]" strokeWidth={1.75} />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-semibold text-navy">{c.title}</span>
                    <span className="mt-0.5 block text-[12px] text-muted">
                      {COMPLAINT_CATEGORY_LABEL[c.category]} · {formatDate(c.created_at)}
                    </span>
                  </span>
                  <StatusPill status={c.status} size="sm" />
                  <ChevronDown className={cn("h-4 w-4 shrink-0 text-muted transition-transform", isOpen && "rotate-180")} />
                </button>

                {isOpen ? (
                  <div className="border-t border-line px-4 pb-4 pt-3">
                    {c.description ? <p className="mb-3 text-sm text-charcoal/90">{c.description}</p> : null}
                    {c.photoSrc ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={c.photoSrc} alt="Complaint photo" className="mb-3 max-h-56 w-full rounded-control object-cover" />
                    ) : null}
                    <div className="label-caps mb-2">Timeline</div>
                    <ComplaintTimeline events={c.events} compact />
                    {c.resolution_note ? (
                      <div className="mt-3 rounded-control bg-teal-soft/60 px-3.5 py-3">
                        <div className="label-caps text-teal">Resolution note</div>
                        <p className="mt-1 text-sm text-charcoal">{c.resolution_note}</p>
                      </div>
                    ) : null}
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}

      {writable ? (
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Raise a complaint"
          className="fixed bottom-[96px] right-4 z-30 flex h-14 w-14 items-center justify-center rounded-full bg-navy text-white shadow-lg transition-transform active:scale-90 md:right-[calc(50%-240px+16px)]"
        >
          <Plus className="h-6 w-6" strokeWidth={2.25} />
        </button>
      ) : null}

      <NewComplaintSheet open={open} onOpenChange={setOpen} />
    </>
  );
}
