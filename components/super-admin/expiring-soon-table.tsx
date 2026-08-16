"use client";

import * as React from "react";
import Link from "next/link";
import type { SaHostelRow } from "@/lib/types";
import { cn, formatDate, formatNumber } from "@/lib/utils";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { SegmentedPills } from "@/components/shared/segmented";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { RenewButton } from "./renew-dialog";
import { DaysLeftPill } from "./days-left-pill";

type Bucket = "all" | "7" | "15" | "30" | "expired";

const inBucket = (d: number | null, b: Bucket) => {
  if (d === null) return false;
  switch (b) {
    case "all":
      return d <= 30;
    case "expired":
      return d < 0;
    case "7":
      return d >= 0 && d <= 7;
    case "15":
      return d >= 0 && d <= 15;
    case "30":
      return d >= 0 && d <= 30;
  }
};

/**
 * SA-1 "Expiring soon" card body — Hard rule §4.4: flag hostels expiring in 7 / 15 / 30 days.
 * The three windows are cumulative (≤7 ⊂ ≤15 ⊂ ≤30); "Expired" lists lapsed subscriptions.
 */
export function ExpiringSoonTable({ rows }: { rows: SaHostelRow[] }) {
  const [bucket, setBucket] = React.useState<Bucket>("all");

  const counts = React.useMemo(() => {
    const c: Record<Bucket, number> = { all: 0, "7": 0, "15": 0, "30": 0, expired: 0 };
    for (const r of rows) for (const b of Object.keys(c) as Bucket[]) if (inBucket(r.days_left, b)) c[b] += 1;
    return c;
  }, [rows]);

  const shown = React.useMemo(
    () => rows.filter((r) => inBucket(r.days_left, bucket)).sort((a, b) => (a.days_left ?? 0) - (b.days_left ?? 0)),
    [rows, bucket],
  );

  return (
    <>
      {/* 7 / 15 / 30-day windows at a glance */}
      <div className="grid grid-cols-3 gap-3 px-5 pb-4 md:px-6">
        {(
          [
            { key: "7", label: "Within 7 days", tone: "red" },
            { key: "15", label: "Within 15 days", tone: "sand" },
            { key: "30", label: "Within 30 days", tone: "navy" },
          ] as const
        ).map((w) => {
          const active = bucket === w.key;
          return (
            <button
              key={w.key}
              type="button"
              onClick={() => setBucket(active ? "all" : w.key)}
              aria-pressed={active}
              className={cn(
                "rounded-card border px-3.5 py-3 text-left transition-colors",
                active ? "border-navy/30 bg-white/80 ring-1 ring-navy/20" : "border-line/70 bg-white/50 hover:bg-white/70",
              )}
            >
              <div className="label-caps">{w.label}</div>
              <div
                className={cn(
                  "mt-1 text-[24px] font-bold leading-none tabular",
                  w.tone === "red" && counts[w.key] > 0 ? "text-red" : w.tone === "sand" && counts[w.key] > 0 ? "text-sand-deep" : "text-navy",
                )}
              >
                {formatNumber(counts[w.key])}
              </div>
              <div className="mt-1 text-[11px] text-muted">hostel{counts[w.key] === 1 ? "" : "s"}</div>
            </button>
          );
        })}
      </div>

      <div className="px-5 pb-4 md:px-6">
        <SegmentedPills<Bucket>
          size="sm"
          ariaLabel="Filter expiring subscriptions by window"
          value={bucket}
          onChange={setBucket}
          options={[
            { value: "all", label: "All ≤ 30 days", count: counts.all },
            { value: "7", label: "7 days", count: counts["7"], tone: "red" },
            { value: "15", label: "15 days", count: counts["15"], tone: "sand" },
            { value: "30", label: "30 days", count: counts["30"], tone: "navy" },
            { value: "expired", label: "Expired", count: counts.expired, tone: "red" },
          ]}
        />
      </div>

      {shown.length === 0 ? (
        <EmptyState
          compact
          title={bucket === "all" ? "Nothing expiring in the next 30 days" : bucket === "expired" ? "No expired subscriptions" : `Nothing expiring within ${bucket} days`}
          description="All subscriptions are in good standing."
        />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="pl-6">Hostel</TableHead>
              <TableHead>Owner</TableHead>
              <TableHead>Ends on</TableHead>
              <TableHead>Days left</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="pr-6 text-right">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {shown.map((h) => (
              <TableRow key={h.hostel_id}>
                <TableCell className="pl-6">
                  <Link href={`/super-admin/hostels/${h.hostel_id}`} className="font-medium text-navy hover:underline">
                    {h.hostel_name}
                  </Link>
                </TableCell>
                <TableCell>
                  <div className="text-charcoal">{h.owner_name}</div>
                  <div className="text-xs text-muted">{h.owner_email ?? h.owner_phone ?? ""}</div>
                </TableCell>
                <TableCell className="tabular">{formatDate(h.sub_end)}</TableCell>
                <TableCell>
                  <DaysLeftPill daysLeft={h.days_left} />
                </TableCell>
                <TableCell>
                  <StatusPill status={h.hostel_status === "suspended" ? "suspended" : h.sub_state} />
                </TableCell>
                <TableCell className="pr-6 text-right">
                  <RenewButton size="sm" target={{ hostelId: h.hostel_id, hostelName: h.hostel_name, currentEnd: h.sub_end, defaultAmount: h.sub_amount }} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </>
  );
}
