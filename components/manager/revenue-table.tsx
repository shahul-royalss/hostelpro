"use client";

import * as React from "react";
import { Download, IndianRupee, Pencil, Trash2 } from "lucide-react";
import { deleteRevenue } from "@/lib/actions/manager";
import { useAction } from "@/hooks/use-action";
import type { RevenueRow } from "@/lib/types";
import { formatDate, formatINR, formatPeriodMonth, sumBy, titleCase } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { Chip } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { MonthNav } from "./month-nav";
import { RevenueForm } from "./revenue-form";
import { ConfirmDialog } from "./confirm-dialog";

const SOURCE_TONE: Record<RevenueRow["source"], "teal" | "sand" | "muted"> = {
  fees: "teal",
  mess: "sand",
  other: "muted",
};

export function RevenueTable({ rows, month, writable }: { rows: RevenueRow[]; month: string; writable: boolean }) {
  const [editing, setEditing] = React.useState<RevenueRow | null>(null);
  const [deleting, setDeleting] = React.useState<RevenueRow | null>(null);
  const total = sumBy(rows, (r) => r.amount);

  const del = useAction(deleteRevenue, { onSuccess: () => setDeleting(null) });

  return (
    <GlassCard padded={false}>
      <div className="p-5 pb-0 md:p-6 md:pb-0">
        <GlassCardHeader
          title="This month"
          description={`${rows.length} ${rows.length === 1 ? "entry" : "entries"} in ${formatPeriodMonth(month)}`}
          action={<MonthNav value={month} />}
        />
      </div>

      {rows.length === 0 ? (
        <EmptyState icon={IndianRupee} title="No revenue recorded" description={`Nothing has been logged for ${formatPeriodMonth(month)} yet. Add today's collections above.`} />
      ) : (
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="pl-5 md:pl-6">Date</TableHead>
              <TableHead>Source</TableHead>
              <TableHead className="text-right">Amount</TableHead>
              <TableHead>Note</TableHead>
              <TableHead className="pr-5 text-right md:pr-6">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="whitespace-nowrap pl-5 text-charcoal md:pl-6">{formatDate(r.date)}</TableCell>
                <TableCell>
                  <Chip tone={SOURCE_TONE[r.source]}>{titleCase(r.source)}</Chip>
                </TableCell>
                <TableCell className="whitespace-nowrap text-right font-semibold text-teal tabular">{formatINR(r.amount)}</TableCell>
                <TableCell className="max-w-[360px]">
                  <span className="line-clamp-2 text-muted" title={r.note ?? undefined}>
                    {r.note || <span className="text-muted/50">—</span>}
                  </span>
                </TableCell>
                <TableCell className="pr-5 text-right md:pr-6">
                  {writable ? (
                    <div className="inline-flex items-center gap-1">
                      <Button type="button" variant="ghost" size="icon-sm" aria-label="Edit revenue" onClick={() => setEditing(r)}>
                        <Pencil className="h-4 w-4" />
                      </Button>
                      <Button type="button" variant="ghost" size="icon-sm" aria-label="Delete revenue" className="text-red hover:text-red" onClick={() => setDeleting(r)}>
                        <Trash2 className="h-4 w-4" />
                      </Button>
                    </div>
                  ) : (
                    <span className="text-xs text-muted">—</span>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      <div className="flex flex-col gap-3 border-t border-line/70 p-5 sm:flex-row sm:items-center sm:justify-between md:px-6">
        <div>
          <div className="label-caps">Total this month</div>
          <div className="text-stat-sm text-teal tabular">{formatINR(total)}</div>
        </div>
        <Button asChild variant="ghost">
          <a href={`/api/manager/export?type=revenue&month=${month}`} download aria-disabled={rows.length === 0} className={rows.length === 0 ? "pointer-events-none opacity-50" : undefined}>
            <Download /> Export CSV
          </a>
        </Button>
      </div>

      <Dialog open={!!editing} onOpenChange={(o) => !o && setEditing(null)}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle>Edit revenue</DialogTitle>
            <DialogDescription>Update the date, source, amount or note.</DialogDescription>
          </DialogHeader>
          {editing ? <RevenueForm key={editing.id} mode="edit" initial={editing} onDone={() => setEditing(null)} /> : null}
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={!!deleting}
        onOpenChange={(o) => !o && setDeleting(null)}
        title="Delete this revenue entry?"
        description={deleting ? `${titleCase(deleting.source)} · ${formatINR(deleting.amount)} on ${formatDate(deleting.date)}. It will be removed from totals and reports.` : undefined}
        pending={del.pending}
        onConfirm={() => deleting && del.run({ id: deleting.id })}
      />
    </GlassCard>
  );
}
