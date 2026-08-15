"use client";

import * as React from "react";
import Link from "next/link";
import { ChevronLeft, ChevronRight, ExternalLink, Search, Users } from "lucide-react";
import type { FeeStatus, FloorRow } from "@/lib/types";
import type { StudentDirectoryRow } from "@/lib/queries/owner";
import { getStudentFiles } from "@/lib/actions/owner";
import { cn, formatDate, formatINR, formatNumber, formatPeriodMonth, toPeriodMonth } from "@/lib/utils";
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

type FeeFilter = "all" | FeeStatus;
const PAGE_SIZE = 20;

/** OW-5 — searchable, filterable, paginated students directory with a read-only slide-over profile. */
export function StudentsTable({ students, floors }: { students: StudentDirectoryRow[]; floors: FloorRow[] }) {
  const [query, setQuery] = React.useState("");
  const [floor, setFloor] = React.useState<string>("all");
  const [fee, setFee] = React.useState<FeeFilter>("all");
  const [page, setPage] = React.useState(1);
  const [selectedId, setSelectedId] = React.useState<string | null>(null);

  const counts = React.useMemo(() => {
    const c: Record<FeeStatus, number> = { paid: 0, partial: 0, unpaid: 0 };
    for (const s of students) c[s.fee_status] += 1;
    return c;
  }, [students]);

  const filtered = React.useMemo(() => {
    const q = query.trim().toLowerCase();
    return students.filter((s) => {
      if (floor !== "all" && String(s.floor_number ?? "") !== floor) return false;
      if (fee !== "all" && s.fee_status !== fee) return false;
      if (!q) return true;
      const hay = `${s.full_name} ${s.phone} ${s.email ?? ""} ${s.room_number ?? ""} ${s.guardian_name ?? ""}`.toLowerCase();
      return hay.includes(q);
    });
  }, [students, query, floor, fee]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const pageRows = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const selected = selectedId ? students.find((s) => s.id === selectedId) ?? null : null;

  // Reset to first page whenever filters change
  React.useEffect(() => {
    setPage(1);
  }, [query, floor, fee]);

  return (
    <>
      <GlassCard padded={false}>
        {/* Toolbar */}
        <div className="flex flex-col gap-3 border-b border-line/70 p-4 md:flex-row md:items-center md:justify-between">
          <div className="relative w-full md:max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search name, phone or room…" className="pl-9" aria-label="Search students" />
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Select value={floor} onValueChange={setFloor}>
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
            <SegmentedPills<FeeFilter>
              size="sm"
              ariaLabel="Fee status"
              value={fee}
              onChange={setFee}
              options={[
                { value: "all", label: "All", count: students.length },
                { value: "paid", label: "Paid", count: counts.paid, tone: "teal" },
                { value: "partial", label: "Partial", count: counts.partial, tone: "sand" },
                { value: "unpaid", label: "Unpaid", count: counts.unpaid, tone: "red" },
              ]}
            />
          </div>
        </div>

        {/* Table */}
        {pageRows.length === 0 ? (
          <EmptyState icon={Users} title={students.length ? "No students match" : "No students yet"} description={students.length ? "Try a different search or filter." : "Students registered by your warden will appear here."} />
        ) : (
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
              {pageRows.map((s) => (
                <TableRow
                  key={s.id}
                  role="button"
                  tabIndex={0}
                  onClick={() => setSelectedId(s.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      setSelectedId(s.id);
                    }
                  }}
                  className="cursor-pointer"
                >
                  <TableCell>
                    <div className="flex items-center gap-3">
                      <UserAvatar name={s.full_name} src={/^https?:\/\//.test(s.photo_url ?? "") ? s.photo_url : null} size="sm" />
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
        )}

        {/* Pagination */}
        <div className="flex flex-col gap-3 border-t border-line/70 px-4 py-3 text-[13px] text-muted sm:flex-row sm:items-center sm:justify-between">
          <span className="tabular">
            {filtered.length === 0 ? "0 students" : `Showing ${(safePage - 1) * PAGE_SIZE + 1}–${Math.min(safePage * PAGE_SIZE, filtered.length)} of ${formatNumber(filtered.length)}`}
            {filtered.length !== students.length ? ` (filtered from ${formatNumber(students.length)})` : ""}
          </span>
          {totalPages > 1 ? (
            <div className="flex items-center gap-1">
              <Button variant="ghost" size="icon-sm" aria-label="Previous page" disabled={safePage <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>
                <ChevronLeft />
              </Button>
              {pageNumbers(safePage, totalPages).map((n, i) =>
                n === null ? (
                  <span key={`gap-${i}`} className="px-1">
                    …
                  </span>
                ) : (
                  <button
                    key={n}
                    type="button"
                    onClick={() => setPage(n)}
                    aria-current={n === safePage ? "page" : undefined}
                    className={cn("h-8 min-w-8 rounded-[10px] px-2 text-xs font-medium tabular transition-colors", n === safePage ? "bg-navy text-white" : "text-navy hover:bg-navy/5")}
                  >
                    {n}
                  </button>
                ),
              )}
              <Button variant="ghost" size="icon-sm" aria-label="Next page" disabled={safePage >= totalPages} onClick={() => setPage((p) => Math.min(totalPages, p + 1))}>
                <ChevronRight />
              </Button>
            </div>
          ) : null}
        </div>
      </GlassCard>

      {/* Slide-over profile */}
      <Sheet open={!!selected} onOpenChange={(v) => (!v ? setSelectedId(null) : null)}>
        <SheetContent side="right" className="sm:max-w-md">
          {selected ? <StudentSheetBody key={selected.id} student={selected} /> : null}
        </SheetContent>
      </Sheet>
    </>
  );
}

function StudentSheetBody({ student }: { student: StudentDirectoryRow }) {
  const [files, setFiles] = React.useState<{ photoUrl: string | null; idProofUrl: string | null } | null>(null);
  const [loading, setLoading] = React.useState(true);

  React.useEffect(() => {
    let cancelled = false;
    setLoading(true);
    getStudentFiles({ studentId: student.id })
      .then((res) => {
        if (cancelled) return;
        setFiles(res.ok ? res.data : { photoUrl: null, idProofUrl: null });
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [student.id]);

  return (
    <div className="flex h-full flex-col">
      <SheetHeader className="pr-8">
        <SheetTitle>Student profile</SheetTitle>
        <SheetDescription>Read-only · fee status for {formatPeriodMonth(toPeriodMonth())}. Contact your warden to correct details.</SheetDescription>
      </SheetHeader>
      <div className="mt-5 flex-1">
        <StudentProfile student={student} photoUrl={files?.photoUrl ?? null} idProofUrl={files?.idProofUrl ?? null} filesLoading={loading} />
      </div>
      <div className="mt-6 flex justify-end border-t border-line/70 pt-4">
        <Button asChild variant="secondary" size="sm">
          <Link href={`/owner/students/${student.id}`}>
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
