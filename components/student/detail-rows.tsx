import * as React from "react";
import { GlassCard } from "@/components/shared/glass-card";

/** Frosted section of grouped read-only rows (ST-2 "Guardian", "Address", …). */
export function DetailSection({ title, children, className }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <GlassCard padded={false} className={className}>
      <div className="label-caps px-5 pt-4">{title}</div>
      <dl className="divide-y divide-line px-5">{children}</dl>
    </GlassCard>
  );
}

export function DetailRow({
  label,
  value,
  action,
  stacked = false,
}: {
  label: string;
  value?: React.ReactNode;
  action?: React.ReactNode;
  /** put the value under the label (long text like an address) */
  stacked?: boolean;
}) {
  const shown = value === null || value === undefined || value === "" ? <span className="text-muted">—</span> : value;
  if (stacked) {
    return (
      <div className="py-3.5">
        <dt className="text-[12px] text-muted">{label}</dt>
        <dd className="mt-1 text-sm leading-relaxed text-charcoal">{shown}</dd>
      </div>
    );
  }
  return (
    <div className="flex items-center justify-between gap-4 py-3.5">
      <dt className="shrink-0 text-[13px] text-muted">{label}</dt>
      <dd className="flex min-w-0 items-center justify-end gap-2 text-right text-sm font-medium text-navy">
        <span className="truncate">{shown}</span>
        {action}
      </dd>
    </div>
  );
}
