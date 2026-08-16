"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { ChevronLeft, ChevronRight, ExternalLink, Loader2, Search, Users } from "lucide-react";
import type { StudentFeeFilter, StudentListRow, StudentsDirectoryResult } from "@/lib/queries/owner";
import { getStudentProfile, type StudentProfilePayload } from "@/lib/actions/owner";
import { cn, formatDate, formatINR, formatNumber, formatPeriodMonth } from "@/lib/utils";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { StatusPill, Chip } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { UserAvatar } from "@/components/ui/avatar";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { StudentProfile } from "./student-profile";

export interface StudentsTableParams {
  q: string;
  floor: number | null;
  fee: StudentFeeFilter;
}

/**
 * OW-5 — students directory. Search / floor / fee filter / page are URL search params and are applied
 * server-side (one page of list columns per request); the slide-over loads the full profile on demand.
 */
export function StudentsTable({ result, params }: { result: StudentsDirectoryResult; params: StudentsTableParams }) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, startTransition] = React.useTransition();
  const [query, setQuery] = React.useState(params.q);
  const [selected, setSelected] = React.useState<StudentListRow | null>(null);

  const { students, floors, counts, total, page, pageSize } = result;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const filtered = !!params.q || params.floor != null || params.fee !== "all";

  // Keep the input in sync when the URL changes from outside (back/forward, header links) —
  // but not when the change is the one we just pushed, so fast typing is never overwritten.
  const lastPushedQ = React.useRef(params.q.trim());
  React.useEffect(() => {
    if (params.q.trim() !== lastPushedQ.current) {
      lastPushedQ.current = params.q.trim();
      setQuery(params.q);
    }
  }, [params.q]);

  const navigate = React.useCallback(
    (next: Partial<StudentsTableParams & { page: number }>) => {
      const merged = { q: params.q, floor: params.floor, fee: params.fee, page, ...next };
      const sp = new URLSearchParams();
      lastPushedQ.current = merged.q.trim();
      if (merged.q.trim()) sp.set("q", merged.q.trim());
      if (merged.floor != null) sp.set("floor", String(merged.floor));
      if (merged.fee !== "all") sp.set("fee", merged.fee);
      if (merged.page > 1) sp.set("page", String(merged.page));
      const qs = sp.toString();
      startTransition(() => router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false }));
    },
    [params.q, params.floor, params.fee, page, pathname, router],
  );

  // Debounced search → URL (filters reset paging to 1).
  React.useEffect(() => {
    if (query.trim() === lastPushedQ.current) return;
    const t = setTimeout(() => navigate({ q: query, page: 1 }), 350);
    return () => clearTimeout(t);
  }, [query, navigate]);

  return (
    <>
      <GlassCard padded={false}>
        {/* Toolbar */}
        <div className="flex flex-col gap-3 border-b border-line/70 p-4 md:flex-row md:items-center md:justify-between">
          <div className="relative w-full md:max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search name, phone or room…" className="pl-9 pr-9" aria-label="Search students" />
            {pending ? <Loader2 className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted" aria-hidden /> : null}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Select value={params.floor == null ? "all" : String(params.floor)} onValueChange={(v) => navigate({ floor: v === "all" ? null : Number(v), page: 1 })}>
              <SelectTrigger className="w-[140px]" aria-label="Floor">
                <SelectValue placeholder="All floors" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All floors</SelectItem>
                {floors.map((f) => (
                  <SelectItem key={f.id} value={String(f.floor_number)}>
                    Floor {f.floor_number}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <SegmentedPills<StudentFeeFilter>
              size="sm"
              ariaLabel="Fee status"
              value={params.fee}
              onChange={(v) => navigate({ fee: v, page: 1 })}
              options={[
                { value: "all", label: "All", count: counts.all },
                { value: "paid", label: "Paid", count: counts.paid, tone: "teal" },
                { value: "partial", label: "Partial", count: counts.partial, tone: "sand" },
                { value: "unpaid", label: "Unpaid", count: counts.unpaid, tone: "red" },
              ]}
            />
          </div>
        </div>

        {/* Table */}
        {students.length === 0 ? (
          <EmptyState icon={Users} title={filtered ? "No students match" : "No students yet"} description={filtered ? "Try a different search or filter." : "Students registered by your warden will appear here."} />
        ) : (
          <div className={cn("transition-opacity", pending && "opacity-60")} aria-busy={pending}>
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Student</TableHead>
                  <TableHead>Room</TableHead>
                  <TableHead>Phone</TableHead>
                  <TableHead>Joined</TableHead>
                  <TableHead className="text-right">Monthly fee</TableHead>
                  <TableHead>Fee status</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {students.map((s) => (
                  <TableRow
                    key={s.id}
                    role="button"
                    tabIndex={0}
                    onClick={() => setSelected(s)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === " ") {
                        e.preventDefault();
                        setSelected(s);
                      }
                    }}
                    className="cursor-pointer"
                  >
                    <TableCell>
                      <div className="flex items-center gap-3">
                        <UserAvatar name={s.full_name} src={s.photo_signed_url} size="sm" />
                        <div className="min-w-0">
                          <p className="truncate font-medium text-navy">{s.full_name}</p>
                          <p className="truncate text-[12px] text-muted">{s.email ?? (s.status === "on_leave" ? "On leave" : "Active")}</p>
                        </div>
                      </div>
                    </TableCell>
                    <TableCell>
                      {s.room_number ? (
                        <span className="inline-flex items-center gap-1.5">
                          <Chip tone="navy">{s.room_number}</Chip>
                          {s.floor_number != null ? <span className="text-[12px] text-muted">Floor {s.floor_number}</span> : null}
                        </span>
                      ) : (
                        <span className="text-muted">—</span>
                      )}
                    </TableCell>
                    <TableCell className="tabular">{s.phone}</TableCell>
                    <TableCell className="tabular text-muted">{formatDate(s.date_of_joining)}</TableCell>
                    <TableCell className="text-right font-medium text-navy tabular">{formatINR(s.monthly_fee)}</TableCell>
                    <TableCell>
                      <StatusPill status={s.fee_status} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}

        {/* Pagination */}
        <div className="flex flex-col gap-3 border-t border-line/70 px-4 py-3 text-[13px] text-muted sm:flex-row sm:items-center sm:justify-between">
          <span className="tabular">
            {total === 0 ? "0 students" : `Showing ${(page - 1) * pageSize + 1}–${Math.min(page * pageSize, total)} of ${formatNumber(total)}`}
            {filtered && total !== counts.all ? ` (filtered from ${formatNumber(counts.all)})` : ""}
          </span>
          {totalPages > 1 ? (
            <div className="flex items-center gap-1">
              <Button variant="ghost" size="icon-sm" aria-label="Previous page" disabled={page <= 1 || pending} onClick={() => navigate({ page: page - 1 })}>
                <ChevronLeft />
              </Button>
              {pageNumbers(page, totalPages).map((n, i) =>
                n === null ? (
                  <span key={`gap-${i}`} className="px-1">
                    …
                  </span>
                ) : (
                  <button
                    key={n}
                    type="button"
                    disabled={pending}
                    onClick={() => navigate({ page: n })}
                    aria-current={n === page ? "page" : undefined}
                    className={cn("h-8 min-w-8 rounded-[10px] px-2 text-xs font-medium tabular transition-colors", n === page ? "bg-navy text-white" : "text-navy hover:bg-navy/5")}
                  >
                    {n}
                  </button>
                ),
              )}
              <Button variant="ghost" size="icon-sm" aria-label="Next page" disabled={page >= totalPages || pending} onClick={() => navigate({ page: page + 1 })}>
                <ChevronRight />
              </Button>
            </div>
          ) : null}
        </div>
      </GlassCard>

      {/* Slide-over profile — full details fetched on demand */}
      <Sheet open={!!selected} onOpenChange={(v) => (!v ? setSelected(null) : null)}>
        <SheetContent side="right" className="sm:max-w-md">
          {selected ? <StudentSheetBody key={selected.id} row={selected} period={result.period} /> : null}
        </SheetContent>
      </Sheet>
    </>
  );
}

function StudentSheetBody({ row, period }: { row: StudentListRow; period: string }) {
  const [state, setState] = React.useState<{ loading: boolean; data: StudentProfilePayload | null; error: string | null }>({ loading: true, data: null, error: null });

  React.useEffect(() => {
    let cancelled = false;
    setState({ loading: true, data: null, error: null });
    getStudentProfile({ studentId: row.id })
      .then((res) => {
        if (cancelled) return;
        setState(res.ok ? { loading: false, data: res.data, error: null } : { loading: false, data: null, error: res.error });
      })
      .catch(() => {
        if (!cancelled) setState({ loading: false, data: null, error: "Could not load this profile." });
      });
    return () => {
      cancelled = true;
    };
  }, [row.id]);

  return (
    <div className="flex h-full flex-col">
      <SheetHeader className="pr-8">
        <SheetTitle>Student profile</SheetTitle>
        <SheetDescription>Read-only · fee status for {formatPeriodMonth(period)}. Contact your warden to correct details.</SheetDescription>
      </SheetHeader>
      <div className="mt-5 flex-1">
        {state.data ? (
          <StudentProfile student={state.data.student} photoUrl={state.data.photoUrl} idProofUrl={state.data.idProofUrl} />
        ) : state.loading ? (
          <div className="space-y-6" aria-busy>
            <div className="flex flex-col items-center text-center">
              <UserAvatar name={row.full_name} src={row.photo_signed_url} size="xl" className="h-24 w-24 text-2xl" />
              <h3 className="mt-3 text-lg font-semibold text-navy">{row.full_name}</h3>
              <p className="mt-0.5 text-sm text-charcoal tabular">{row.phone}</p>
              <div className="mt-2 flex flex-wrap items-center justify-center gap-2">
                <StatusPill status={row.status} dot />
                {row.room_number ? <Chip tone="navy">Room {row.room_number}</Chip> : <Chip>No room</Chip>}
              </div>
            </div>
            <div className="flex items-center justify-center gap-2 py-8 text-sm text-muted">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading full profile…
            </div>
          </div>
        ) : (
          <EmptyState compact icon={Users} title="Profile unavailable" description={state.error ?? "Try again in a moment."} />
        )}
      </div>
      <div className="mt-6 flex justify-end border-t border-line/70 pt-4">
        <Button asChild variant="secondary" size="sm">
          <Link href={`/owner/students/${row.id}`}>
            Open full page <ExternalLink className="h-3 w-3" />
          </Link>
        </Button>
      </div>
    </div>
  );
}

/** 1 … 4 5 [6] 7 8 … 12 */
function pageNumbers(current: number, total: number): (number | null)[] {
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const pages = new Set<number>([1, total, current - 1, current, current + 1]);
  const sorted = Array.from(pages)
    .filter((n) => n >= 1 && n <= total)
    .sort((a, b) => a - b);
  const out: (number | null)[] = [];
  for (let i = 0; i < sorted.length; i++) {
    if (i > 0 && sorted[i] - sorted[i - 1] > 1) out.push(null);
    out.push(sorted[i]);
  }
  return out;
}
