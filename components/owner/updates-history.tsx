"use client";

import * as React from "react";
import { Eye, Megaphone, Trash2 } from "lucide-react";
import type { AnnouncementRow } from "@/lib/types";
import { deleteAnnouncement } from "@/lib/actions/owner";
import { useAction } from "@/hooks/use-action";
import { formatDateTime } from "@/lib/utils";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

export interface SentUpdate extends AnnouncementRow {
  /** active users in the hostel matching the audience */
  reach: number;
}

/** OW-3 right card — "Sent history": audience pill, date, eye icon + reach, remove. */
export function UpdatesHistory({ updates, writable }: { updates: SentUpdate[]; writable: boolean }) {
  const [target, setTarget] = React.useState<SentUpdate | null>(null);
  const [expanded, setExpanded] = React.useState<string | null>(null);
  const { run, pending } = useAction(deleteAnnouncement, { onSuccess: () => setTarget(null) });

  return (
    <GlassCard as="section" padded={false} className="flex flex-col">
      <div className="p-5 pb-0 md:p-6 md:pb-0">
        <GlassCardHeader title="Sent history" description={`${updates.length} update${updates.length === 1 ? "" : "s"} sent`} />
      </div>
      {updates.length === 0 ? (
        <EmptyState icon={Megaphone} title="No updates sent yet" description="Your broadcasts will show up here with their audience and reach." />
      ) : (
        <ul className="divide-y divide-line/70">
          {updates.map((u) => {
            const open = expanded === u.id;
            return (
              <li key={u.id} className="px-5 py-4 md:px-6">
                <div className="flex items-start justify-between gap-3">
                  <button type="button" onClick={() => setExpanded(open ? null : u.id)} className="min-w-0 flex-1 text-left" aria-expanded={open}>
                    <div className="flex flex-wrap items-center gap-2 text-[11px] text-muted">
                      <StatusPill status={u.audience} size="sm" />
                      <span className="tabular">{formatDateTime(u.created_at)}</span>
                    </div>
                    <p className="mt-1.5 text-sm font-semibold text-navy">{u.title}</p>
                    <p className={open ? "mt-1 whitespace-pre-line text-[13px] leading-relaxed text-charcoal" : "mt-1 line-clamp-2 text-[13px] text-muted"}>{u.body}</p>
                  </button>
                  <div className="flex shrink-0 flex-col items-end gap-2">
                    <span className="inline-flex items-center gap-1 rounded-full bg-navy/5 px-2 py-1 text-[11px] font-medium text-navy tabular" title="Recipients">
                      <Eye className="h-3.5 w-3.5" /> {u.reach}
                    </span>
                    {writable ? (
                      <Button variant="ghost" size="icon-sm" aria-label="Remove update" className="text-muted hover:text-red" onClick={() => setTarget(u)}>
                        <Trash2 />
                      </Button>
                    ) : null}
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      )}

      <Dialog open={!!target} onOpenChange={(v) => (!v ? setTarget(null) : null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Remove this update?</DialogTitle>
            <DialogDescription>
              <span className="font-medium text-charcoal">{target?.title}</span> will disappear from every recipient&apos;s feed. Notifications already sent are kept.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setTarget(null)} disabled={pending}>
              Cancel
            </Button>
            <Button variant="destructive" loading={pending} onClick={() => target && run({ announcementId: target.id })}>
              Remove
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </GlassCard>
  );
}
