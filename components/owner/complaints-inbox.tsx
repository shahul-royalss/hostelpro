"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { formatDistanceToNowStrict } from "date-fns";
import { ArrowLeft, Check, ChevronLeft, ChevronRight, Loader2, MessageSquareWarning, Phone, Search } from "lucide-react";
import type { ComplaintEventRow, ComplaintStatus } from "@/lib/types";
import type { ComplaintFilter, ComplaintListItem, ComplaintsInboxResult } from "@/lib/queries/owner";
import { updateComplaintStatus } from "@/lib/actions/complaints";
import { useAction } from "@/hooks/use-action";
import { cn, formatDateTime, formatNumber, titleCase } from "@/lib/utils";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { StatusPill, Chip } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { ComplaintTimeline } from "@/components/shared/complaint-timeline";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { ComplaintCategoryIcon } from "./complaint-icon";

export interface ComplaintsInboxParams {
  status: ComplaintFilter;
  q: string;
}

export interface SelectedComplaint {
  complaint: ComplaintListItem;
  events: ComplaintEventRow[];
  photoUrl: string | null;
}

function relative(iso: string) {
  try {
    return formatDistanceToNowStrict(new Date(iso), { addSuffix: true });
  } catch {
    return "";
  }
}

/**
 * OW-2 — two-pane complaints inbox. Status filter, search and page are URL params applied server-side
 * (true counts, no client-side cap); the selected id also lives in the URL.
 */
export function ComplaintsInbox({
  inbox,
  params,
  selected,
  writable,
}: {
  inbox: ComplaintsInboxResult;
  params: ComplaintsInboxParams;
  selected: SelectedComplaint | null;
  writable: boolean;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = React.useTransition();
  // On small screens the list hides only when the user explicitly opened a complaint (?id=…),
  // not when the server auto-selected the first one for the desktop layout.
  const explicitId = useSearchParams().get("id");
  const [query, setQuery] = React.useState(params.q);

  const { complaints, counts, total, page, pageSize } = inbox;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const filtered = params.status !== "all" || !!params.q;
  const selectedId = selected?.complaint.id ?? null;

  // Sync the input from the URL only for external changes (never overwrite in-flight typing).
  const lastPushedQ = React.useRef(params.q.trim());
  React.useEffect(() => {
    if (params.q.trim() !== lastPushedQ.current) {
      lastPushedQ.current = params.q.trim();
      setQuery(params.q);
    }
  }, [params.q]);

  const navigate = React.useCallback(
    (next: { status?: ComplaintFilter; q?: string; page?: number; id?: string | null }) => {
      const merged = { status: params.status, q: params.q, page, id: explicitId, ...next };
      const sp = new URLSearchParams();
      lastPushedQ.current = merged.q.trim();
      if (merged.status !== "all") sp.set("status", merged.status);
      if (merged.q.trim()) sp.set("q", merged.q.trim());
      if (merged.page > 1) sp.set("page", String(merged.page));
      if (merged.id) sp.set("id", merged.id);
      const qs = sp.toString();
      startTransition(() => router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false }));
    },
    [params.status, params.q, page, explicitId, pathname, router],
  );

  React.useEffect(() => {
    if (query.trim() === lastPushedQ.current) return;
    const t = setTimeout(() => navigate({ q: query, page: 1, id: null }), 350);
    return () => clearTimeout(t);
  }, [query, navigate]);

  function select(id: string) {
    navigate({ id });
  }

  return (
    <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(300px,400px)_1fr] lg:items-start">
      {/* Left: list */}
      <GlassCard padded={false} className={cn("flex flex-col lg:sticky lg:top-[84px] lg:max-h-[calc(100dvh-108px)]", explicitId && "hidden lg:flex")}>
        <div className="space-y-3 border-b border-line/70 p-4">
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search complaints, students, rooms…"
              className="pl-9"
              aria-label="Search complaints"
            />
          </div>
          <SegmentedPills<ComplaintFilter>
            size="sm"
            value={params.status}
            onChange={(v) => navigate({ status: v, page: 1, id: null })}
            ariaLabel="Filter by status"
            options={[
              { value: "all", label: "All", count: counts.all },
              { value: "open", label: "Open", count: counts.open, tone: "red" },
              { value: "in_progress", label: "In progress", count: counts.in_progress, tone: "sand" },
              { value: "resolved", label: "Resolved", count: counts.resolved, tone: "teal" },
            ]}
          />
        </div>
        <div className={cn("min-h-0 flex-1 overflow-y-auto transition-opacity", pending && "opacity-60")} aria-busy={pending}>
          {complaints.length === 0 ? (
            <EmptyState compact icon={MessageSquareWarning} title={filtered ? "No complaints match" : "No complaints yet"} description={filtered ? "Try another filter or search." : "Students haven't raised anything."} />
          ) : (
            <ul className="divide-y divide-line/60">
              {complaints.map((c) => {
                const active = c.id === selectedId;
                return (
                  <li key={c.id}>
                    <button
                      type="button"
                      onClick={() => select(c.id)}
                      aria-current={active ? "true" : undefined}
                      className={cn(
                        "flex w-full items-start gap-3 px-4 py-3 text-left transition-colors hover:bg-white/60",
                        active && "bg-navy/[0.06] hover:bg-navy/[0.08]",
                      )}
                    >
                      <ComplaintCategoryIcon category={c.category} size="sm" className="mt-0.5" />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-start justify-between gap-2">
                          <p className="truncate text-sm font-medium text-navy">{c.title}</p>
                          <span className="shrink-0 text-[11px] text-muted">{relative(c.created_at)}</span>
                        </div>
                        <div className="mt-0.5 flex flex-wrap items-center gap-1.5 text-[12px] text-muted">
                          <span className="truncate">{c.student?.full_name ?? "Student"}</span>
                          {c.student?.room?.room_number ? <Chip>Room {c.student.room.room_number}</Chip> : null}
                        </div>
                        <div className="mt-1.5">
                          <StatusPill status={c.status} size="sm" />
                        </div>
                      </div>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
        {total > pageSize ? (
          <div className="flex items-center justify-between gap-2 border-t border-line/70 px-4 py-2.5 text-[12px] text-muted">
            <span className="tabular">
              {(page - 1) * pageSize + 1}–{Math.min(page * pageSize, total)} of {formatNumber(total)}
            </span>
            <div className="flex items-center gap-1">
              <Button variant="ghost" size="icon-sm" aria-label="Previous page" disabled={page <= 1 || pending} onClick={() => navigate({ page: page - 1, id: null })}>
                <ChevronLeft />
              </Button>
              <span className="tabular">
                {page} / {totalPages}
              </span>
              <Button variant="ghost" size="icon-sm" aria-label="Next page" disabled={page >= totalPages || pending} onClick={() => navigate({ page: page + 1, id: null })}>
                <ChevronRight />
              </Button>
            </div>
          </div>
        ) : null}
      </GlassCard>

      {/* Right: detail */}
      <div className={cn(!explicitId && "hidden lg:block")}>
        {selected ? (
          <ComplaintDetail key={selected.complaint.id} selected={selected} writable={writable} />
        ) : (
          <GlassCard className="flex min-h-[420px] items-center justify-center">
            <EmptyState icon={MessageSquareWarning} title="Select a complaint" description="Pick a complaint from the list to see its details and update its status." />
          </GlassCard>
        )}
      </div>
    </div>
  );
}

function ComplaintDetail({ selected, writable }: { selected: SelectedComplaint; writable: boolean }) {
  const { complaint: c, events, photoUrl } = selected;
  const [note, setNote] = React.useState(c.resolution_note ?? "");
  const { run, pending } = useAction(updateComplaintStatus, { refresh: true });
  const noteDirty = (note.trim() || null) !== (c.resolution_note ?? null);

  const submit = (status: ComplaintStatus) => run({ complaintId: c.id, status, resolutionNote: note.trim() || null });

  return (
    <GlassCard className="space-y-6">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <Button asChild variant="ghost" size="sm" className="-ml-2 mb-2 lg:hidden">
            <Link href="/owner/complaints">
              <ArrowLeft /> All complaints
            </Link>
          </Button>
          <div className="flex flex-wrap items-center gap-2">
            <StatusPill status={c.status} dot />
            <span className="text-[12px] text-muted">
              {titleCase(c.category)} · raised {formatDateTime(c.created_at)}
            </span>
          </div>
          <h2 className="mt-2 text-title-sm text-navy">{c.title}</h2>
        </div>
        <ComplaintCategoryIcon category={c.category} />
      </div>

      {/* Student */}
      <div className="flex flex-wrap items-center gap-3 rounded-control bg-white/60 px-4 py-3">
        <div className="min-w-0 flex-1">
          <div className="label-caps">Raised by</div>
          <div className="mt-0.5 flex flex-wrap items-center gap-2">
            <span className="text-sm font-semibold text-navy">{c.student?.full_name ?? "Student"}</span>
            {c.student?.room?.room_number ? <Chip tone="navy">Room {c.student.room.room_number}</Chip> : null}
          </div>
        </div>
        {c.student?.phone ? (
          <a href={`tel:${c.student.phone}`} className="inline-flex items-center gap-1.5 text-sm text-navy hover:underline">
            <Phone className="h-3.5 w-3.5" /> {c.student.phone}
          </a>
        ) : null}
      </div>

      {/* Description */}
      <section>
        <div className="label-caps mb-1.5">Description</div>
        <p className="whitespace-pre-line text-sm leading-relaxed text-charcoal">{c.description?.trim() || <span className="text-muted">No description provided.</span>}</p>
      </section>

      {photoUrl ? (
        <section>
          <div className="label-caps mb-1.5">Photo</div>
          <a href={photoUrl} target="_blank" rel="noreferrer" className="block w-fit overflow-hidden rounded-control border border-line bg-white/60">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={photoUrl} alt={`Photo attached to "${c.title}"`} className="max-h-72 w-auto max-w-full object-contain" />
          </a>
        </section>
      ) : null}

      {/* Timeline */}
      <section>
        <div className="label-caps mb-3">Status timeline</div>
        <ComplaintTimeline events={events} />
      </section>

      {/* Resolution */}
      <section className="space-y-2">
        <Label htmlFor="resolution-note">Resolution note</Label>
        <Textarea
          id="resolution-note"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Add notes about the fix, parts used, or a message to the student…"
          disabled={!writable}
          rows={3}
        />
        <div className="flex flex-wrap items-center justify-end gap-2 pt-1">
          {noteDirty && (
            <Button variant="ghost" size="sm" disabled={!writable || pending} onClick={() => submit(c.status)}>
              Save note
            </Button>
          )}
          <Button variant="secondary" disabled={!writable || pending || c.status !== "open"} onClick={() => submit("in_progress")}>
            {pending ? <Loader2 className="animate-spin" /> : null}
            Mark in progress
          </Button>
          <Button disabled={!writable || pending || c.status === "resolved"} onClick={() => submit("resolved")}>
            <Check /> Mark resolved
          </Button>
        </div>
        {!writable ? <p className="text-right text-xs text-muted">Read-only — the subscription needs renewing before status changes can be saved.</p> : null}
      </section>
    </GlassCard>
  );
}
