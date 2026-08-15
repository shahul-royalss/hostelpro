import * as React from "react";
import { ArrowDownRight, ArrowUpRight, Receipt } from "lucide-react";
import type { FinanceEntry } from "@/lib/queries/owner";
import { cn, formatDate, formatINR, titleCase } from "@/lib/utils";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Chip } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { UserAvatar } from "@/components/ui/avatar";

/** OW-6 bottom table — latest expense + revenue entries merged, newest first. */
export function FinanceEntriesTable({ entries }: { entries: FinanceEntry[] }) {
  if (entries.length === 0) {
    return <EmptyState icon={Receipt} title="No entries this month" description="Expenses and revenue recorded by your manager will be listed here." />;
  }
  return (
    <Table>
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          <TableHead>Date</TableHead>
          <TableHead>Type</TableHead>
          <TableHead>Category / source</TableHead>
          <TableHead className="text-right">Amount</TableHead>
          <TableHead>Note</TableHead>
          <TableHead>Recorded by</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {entries.map((e) => {
          const revenue = e.kind === "revenue";
          return (
            <TableRow key={`${e.kind}-${e.id}`}>
              <TableCell className="whitespace-nowrap tabular text-muted">{formatDate(e.date)}</TableCell>
              <TableCell>
                <span className={cn("inline-flex items-center gap-1 text-[12px] font-semibold", revenue ? "text-teal" : "text-red")}>
                  {revenue ? <ArrowUpRight className="h-3.5 w-3.5" /> : <ArrowDownRight className="h-3.5 w-3.5" />}
                  {revenue ? "Revenue" : "Expense"}
                </span>
              </TableCell>
              <TableCell>
                <Chip tone={revenue ? "teal" : "red"}>{titleCase(e.label)}</Chip>
              </TableCell>
              <TableCell className={cn("whitespace-nowrap text-right font-semibold tabular", revenue ? "text-teal" : "text-red")}>
                {revenue ? "+" : "−"}
                {formatINR(e.amount)}
              </TableCell>
              <TableCell className="max-w-[260px]">
                <span className="line-clamp-1 text-[13px] text-charcoal">{e.note?.trim() || <span className="text-muted">—</span>}</span>
              </TableCell>
              <TableCell>
                {e.recorded_by ? (
                  <span className="inline-flex items-center gap-2 text-[13px] text-charcoal">
                    <UserAvatar name={e.recorded_by} size="xs" />
                    <span className="truncate">{e.recorded_by}</span>
                  </span>
                ) : (
                  <span className="text-muted">—</span>
                )}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}
