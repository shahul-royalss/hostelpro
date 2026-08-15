"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { CalendarPlus, ChevronLeft, ChevronRight, CreditCard, Eye, KeyRound, MoreHorizontal, Search, X } from "lucide-react";
import type { SaHostelRow, SubscriptionRow, SubscriptionStatus } from "@/lib/types";
import { cn, formatDate, formatINR, formatNumber, percent } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { RenewDialog, type RenewTarget } from "./renew-dialog";
import { HostelStatusButton, useRegenerateOwnerPassword } from "./hostel-actions";
import { DaysLeftPill } from "./days-left-pill";
import { SubscriptionTimeline } from "./subscription-timeline";

type Filter = "all" | SubscriptionStatus;
const PAGE_SIZE = 15;

/**
 * SA-3 — subscriptions table: filter chips + search, 15/page client pagination,
 * row actions (Renew · Suspend/Unsuspend · menu), row click → history slide-over.
 */
export function SubscriptionsTable({
  rows,
  history,
  initialFilter = "all",
}: {
  rows: SaHostelRow[];
  history: Record<string, SubscriptionRow[]>;
  initialFilter?: Filter;
}) {
  const router = useRouter();
  const [filter, setFilter] = React.useState<Filter>(initialFilter);
  const [query, setQuery] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [selectedId, setSelectedId] = React.useState<string | null>(null);
  const [renewTarget, setRenewTarget] = React.useState<RenewTarget | null>(null);
  const [renewOpen, setRenewOpen] = React.useState(false);
  const { regenerate, pending: regenPending, dialog: regenDialog } = useRegenerateOwnerPassword();

  const counts = React.useMemo(() => {
    const c: Record<Filter, number> = { all: rows.length, active: 0, expiring: 0, expired: 0 };
    for (const r of rows) c[r.sub_state] += 1;
    return c;
  }, [rows]);

  const filtered = React.useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((r) => {
      if (filter !== "all" && r.sub_state !== filter) return false;
      if (!q) return true;
      return [r.hostel_name, r.owner_name, r.owner_email ?? "", r.owner_phone ?? "", r.address ?? ""].some((v) => v.toLowerCase().includes(q));
    });
  }, [rows, filter, query]);

  const pageCount = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const safePage = Math.min(page, pageCount);
  const pageRows = filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE);
  const selected = selectedId ? rows.find((r) => r.hostel_id === selectedId) ?? null : null;

  const changeFilter = (f: Filter) => {
    setFilter(f);
    setPage(1);
  };
  const openRenew = (r: SaHostelRow) => {
    setRenewTarget({ hostelId: r.hostel_id, hostelName: r.hostel_name, currentEnd: r.sub_end, defaultAmount: r.sub_amount });
    setRenewOpen(true);
  };

  return (
    <>
      {/* Filters */}
      <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <SegmentedPills<Filter>
          ariaLabel="Filter by subscription status"
          value={filter}
          onChange={changeFilter}
          options={[
            { value: "all", label: "All", count: counts.all },
            { value: "active", label: "Active", count: counts.active, tone: "teal" },
            { value: "expiring", label: "Expiring", count: counts.expiring, tone: "sand" },
            { value: "expired", label: "Expired", count: counts.expired, tone: "red" },
          ]}
        />
        <div className="relative w-full md:w-72">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setPage(1);
            }}
            placeholder="Search hostels or owners…"
            className="pl-9 pr-9"
            aria-label="Search subscriptions"
          />
          {query ? (
            <button type="button" aria-label="Clear search" onClick={() => setQuery("")} className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded-full p-1 text-muted hover:bg-navy/5 hover:text-navy">
              <X className="h-3.5 w-3.5" />
            </button>
          ) : null}
        </div>
      </div>

      {/* Table */}
      <GlassCard padded={false}>
        {pageRows.length === 0 ? (
          <EmptyState
            icon={CreditCard}
            title={rows.length === 0 ? "No subscriptions yet" : "No subscriptions match"}
            description={rows.length === 0 ? "Create the first owner and hostel to start a subscription." : "Try a different filter or search term."}
            action={
              rows.length === 0 ? (
                <Button asChild>
                  <Link href="/super-admin/create">Create owner &amp; hostel</Link>
                </Button>
              ) : (
                <Button variant="secondary" onClick={() => { setQuery(""); changeFilter("all"); }}>
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
                <TableHead>Start</TableHead>
                <TableHead>End</TableHead>
                <TableHead>Amount</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="pr-6 text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {pageRows.map((r) => (
                <TableRow
                  key={r.hostel_id}
                  onClick={() => setSelectedId(r.hostel_id)}
                  className="cursor-pointer"
                  data-state={selectedId === r.hostel_id ? "selected" : undefined}
                >
                  <TableCell className="pl-6">
                    <div className="font-medium text-navy">{r.hostel_name}</div>
                    <div className="max-w-[220px] truncate text-xs text-muted">{r.address ?? `${formatNumber(r.active_students)} students`}</div>
                  </TableCell>
                  <TableCell>
                    <div className="text-charcoal">{r.owner_name}</div>
                    <div className="text-xs text-muted">{r.owner_email ?? r.owner_phone ?? "—"}</div>
                  </TableCell>
                  <TableCell className="tabular whitespace-nowrap">{formatDate(r.sub_start)}</TableCell>
                  <TableCell className="whitespace-nowrap">
                    <div className="tabular">{formatDate(r.sub_end)}</div>
                    <div className="mt-1">
                      <DaysLeftPill daysLeft={r.days_left} size="sm" />
                    </div>
                  </TableCell>
                  <TableCell className="tabular font-semibold text-navy">{r.sub_amount === null ? "—" : formatINR(r.sub_amount)}</TableCell>
                  <TableCell>
                    <div className="flex flex-col items-start gap-1">
                      <StatusPill status={r.sub_state} />
                      {r.hostel_status === "suspended" ? <StatusPill status="suspended" size="sm" /> : null}
                    </div>
                  </TableCell>
                  <TableCell className="pr-6">
                    <div className="flex items-center justify-end gap-1.5" onClick={(e) => e.stopPropagation()}>
                      <Button size="sm" onClick={() => openRenew(r)}>
                        <CalendarPlus />
                        Renew
                      </Button>
                      <HostelStatusButton hostelId={r.hostel_id} hostelName={r.hostel_name} status={r.hostel_status} />
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button variant="ghost" size="icon-sm" aria-label="More actions" disabled={regenPending}>
                            <MoreHorizontal />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem onSelect={() => router.push(`/super-admin/hostels/${r.hostel_id}`)}>
                            <Eye />
                            View hostel
                          </DropdownMenuItem>
                          <DropdownMenuItem onSelect={() => setSelectedId(r.hostel_id)}>
                            <CreditCard />
                            Subscription history
                          </DropdownMenuItem>
                          <DropdownMenuSeparator />
                          <DropdownMenuItem onSelect={() => regenerate(r.owner_id)}>
                            <KeyRound />
                            Regenerate owner password
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}

        {/* Pagination */}
        {filtered.length > 0 ? (
          <div className="flex flex-col gap-3 border-t border-line/70 px-6 py-3.5 text-xs text-muted sm:flex-row sm:items-center sm:justify-between">
            <span>
              Showing <span className="font-semibold text-navy tabular">{(safePage - 1) * PAGE_SIZE + 1}–{Math.min(safePage * PAGE_SIZE, filtered.length)}</span> of{" "}
              <span className="font-semibold text-navy tabular">{filtered.length}</span> subscriptions
            </span>
            {pageCount > 1 ? (
              <nav className="flex items-center gap-1" aria-label="Pagination">
                <Button variant="ghost" size="icon-sm" aria-label="Previous page" disabled={safePage <= 1} onClick={() => setPage(safePage - 1)}>
                  <ChevronLeft />
                </Button>
                {Array.from({ length: pageCount }, (_, i) => i + 1).map((p) => (
                  <button
                    key={p}
                    type="button"
                    aria-current={p === safePage ? "page" : undefined}
                    onClick={() => setPage(p)}
                    className={cn(
                      "h-8 min-w-8 rounded-[10px] px-2 text-xs font-medium tabular transition-colors",
                      p === safePage ? "bg-navy text-white" : "text-muted hover:bg-navy/5 hover:text-navy",
                    )}
                  >
                    {p}
                  </button>
                ))}
                <Button variant="ghost" size="icon-sm" aria-label="Next page" disabled={safePage >= pageCount} onClick={() => setPage(safePage + 1)}>
                  <ChevronRight />
                </Button>
              </nav>
            ) : null}
          </div>
        ) : null}
      </GlassCard>

      {/* Slide-over: subscription history */}
      <Sheet open={!!selected} onOpenChange={(v) => (v ? null : setSelectedId(null))}>
        <SheetContent side="right" className="flex flex-col gap-5">
          {selected ? (
            <>
              <SheetHeader className="pr-8">
                <div className="flex flex-wrap items-center gap-2">
                  <SheetTitle>{selected.hostel_name}</SheetTitle>
                  <StatusPill status={selected.hostel_status === "suspended" ? "suspended" : selected.sub_state} />
                </div>
                <SheetDescription>
                  Owned by <span className="font-medium text-charcoal">{selected.owner_name}</span>
                  {selected.owner_email ? ` · ${selected.owner_email}` : ""}
                  {selected.owner_phone ? ` · ${selected.owner_phone}` : ""}
                </SheetDescription>
              </SheetHeader>

              <div className="grid grid-cols-2 gap-3">
                <QuickStat label="Days left" value={<DaysLeftPill daysLeft={selected.days_left} />} />
                <QuickStat label="Current amount" value={selected.sub_amount === null ? "—" : formatINR(selected.sub_amount)} />
                <QuickStat label="Occupancy" value={`${percent(selected.occupied_beds, selected.total_beds)}%`} caption={`${selected.occupied_beds}/${selected.total_beds} beds`} />
                <QuickStat label="Students" value={formatNumber(selected.active_students)} caption={`${formatNumber(selected.open_complaints)} open complaints`} />
              </div>

              <div className="flex flex-wrap gap-2">
                <Button size="sm" onClick={() => openRenew(selected)}>
                  <CalendarPlus />
                  Renew subscription
                </Button>
                <HostelStatusButton hostelId={selected.hostel_id} hostelName={selected.hostel_name} status={selected.hostel_status} />
                <Button asChild size="sm" variant="secondary">
                  <Link href={`/super-admin/hostels/${selected.hostel_id}`}>
                    <Eye />
                    View hostel
                  </Link>
                </Button>
              </div>

              <div>
                <div className="label-caps mb-3">Subscription history</div>
                <SubscriptionTimeline subscriptions={history[selected.hostel_id] ?? []} />
              </div>
            </>
          ) : null}
        </SheetContent>
      </Sheet>

      <RenewDialog target={renewTarget} open={renewOpen} onOpenChange={setRenewOpen} />
      {regenDialog}
    </>
  );
}

function QuickStat({ label, value, caption }: { label: string; value: React.ReactNode; caption?: string }) {
  return (
    <div className="rounded-card border border-line/70 bg-white/50 p-3">
      <div className="label-caps">{label}</div>
      <div className="mt-1 text-[17px] font-bold text-navy tabular">{value}</div>
      {caption ? <div className="text-xs text-muted">{caption}</div> : null}
    </div>
  );
}
