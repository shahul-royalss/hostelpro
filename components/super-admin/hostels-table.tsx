"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Building2, ChevronRight, Search, X } from "lucide-react";
import type { SaHostelRow } from "@/lib/types";
import { cn, formatDate, formatNumber, percent } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Progress } from "@/components/ui/misc";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { DaysLeftPill } from "./days-left-pill";

type Filter = "all" | "active" | "expiring" | "expired" | "suspended";

/** /super-admin/hostels — searchable, filterable hostel table; row → detail. */
export function HostelsTable({ rows }: { rows: SaHostelRow[] }) {
  const router = useRouter();
  const [filter, setFilter] = React.useState<Filter>("all");
  const [query, setQuery] = React.useState("");

  const counts = React.useMemo(() => {
    const c: Record<Filter, number> = { all: rows.length, active: 0, expiring: 0, expired: 0, suspended: 0 };
    for (const r of rows) {
      if (r.hostel_status === "suspended") c.suspended += 1;
      else c[r.sub_state] += 1;
    }
    return c;
  }, [rows]);

  const filtered = React.useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((r) => {
      if (filter === "suspended" && r.hostel_status !== "suspended") return false;
      if (filter !== "all" && filter !== "suspended" && (r.sub_state !== filter || r.hostel_status === "suspended")) return false;
      if (!q) return true;
      return [r.hostel_name, r.owner_name, r.owner_email ?? "", r.owner_phone ?? "", r.address ?? ""].some((v) => v.toLowerCase().includes(q));
    });
  }, [rows, filter, query]);

  return (
    <>
      <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <SegmentedPills<Filter>
          ariaLabel="Filter hostels by status"
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "All", count: counts.all },
            { value: "active", label: "Active", count: counts.active, tone: "teal" },
            { value: "expiring", label: "Expiring", count: counts.expiring, tone: "sand" },
            { value: "expired", label: "Expired", count: counts.expired, tone: "red" },
            { value: "suspended", label: "Suspended", count: counts.suspended, tone: "red" },
          ]}
        />
        <div className="relative w-full md:w-72">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search hostels or owners…" className="pl-9 pr-9" aria-label="Search hostels" />
          {query ? (
            <button type="button" aria-label="Clear search" onClick={() => setQuery("")} className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded-full p-1 text-muted hover:bg-navy/5 hover:text-navy">
              <X className="h-3.5 w-3.5" />
            </button>
          ) : null}
        </div>
      </div>

      <GlassCard padded={false}>
        {filtered.length === 0 ? (
          <EmptyState
            icon={Building2}
            title={rows.length === 0 ? "No hostels yet" : "No hostels match"}
            description={rows.length === 0 ? "Create the first owner and hostel to get started." : "Try a different filter or search term."}
            action={
              rows.length === 0 ? (
                <Button asChild>
                  <Link href="/super-admin/create">Create owner &amp; hostel</Link>
                </Button>
              ) : (
                <Button variant="secondary" onClick={() => { setQuery(""); setFilter("all"); }}>
                  Clear filters
                </Button>
              )
            }
          />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="pl-6">Hostel</TableHead>
                <TableHead>Owner</TableHead>
                <TableHead className="min-w-[160px]">Occupancy</TableHead>
                <TableHead>Students</TableHead>
                <TableHead>Subscription</TableHead>
                <TableHead>Days left</TableHead>
                <TableHead className="pr-6 text-right">
                  <span className="sr-only">Open</span>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((r) => {
                const occ = percent(r.occupied_beds, r.total_beds);
                return (
                  <TableRow
                    key={r.hostel_id}
                    className="cursor-pointer"
                    onClick={() => router.push(`/super-admin/hostels/${r.hostel_id}`)}
                    tabIndex={0}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") router.push(`/super-admin/hostels/${r.hostel_id}`);
                    }}
                  >
                    <TableCell className="pl-6">
                      <div className="flex items-center gap-3">
                        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px] bg-navy/5 text-navy">
                          <Building2 className="h-4 w-4" strokeWidth={1.75} />
                        </span>
                        <div className="min-w-0">
                          <div className="font-medium text-navy">{r.hostel_name}</div>
                          <div className="max-w-[240px] truncate text-xs text-muted">{r.address ?? `Created ${formatDate(r.created_at)}`}</div>
                        </div>
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="text-charcoal">{r.owner_name}</div>
                      <div className="text-xs text-muted">{r.owner_phone ?? r.owner_email ?? "—"}</div>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-3">
                        <Progress value={occ} className="h-1.5 w-20" indicatorClassName={cn(occ >= 90 ? "bg-teal" : "bg-navy")} aria-label={`${occ}% occupied`} />
                        <span className="text-sm font-semibold text-navy tabular">{occ}%</span>
                      </div>
                      <div className="mt-0.5 text-xs text-muted tabular">
                        {formatNumber(r.occupied_beds)}/{formatNumber(r.total_beds)} beds
                      </div>
                    </TableCell>
                    <TableCell className="tabular font-semibold text-navy">{formatNumber(r.active_students)}</TableCell>
                    <TableCell>
                      <div className="flex flex-col items-start gap-1">
                        <StatusPill status={r.hostel_status === "suspended" ? "suspended" : r.sub_state} />
                        <span className="text-xs text-muted tabular">ends {formatDate(r.sub_end)}</span>
                      </div>
                    </TableCell>
                    <TableCell>
                      <DaysLeftPill daysLeft={r.days_left} />
                    </TableCell>
                    <TableCell className="pr-6 text-right">
                      <ChevronRight className="ml-auto h-4 w-4 text-muted" />
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </GlassCard>
    </>
  );
}
