"use client";

import * as React from "react";
import { addMonths, format, parse, subMonths } from "date-fns";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { SegmentedPills } from "./segmented";

/** "YYYY-MM" helpers */
export function periodToDate(period: string) {
  return parse(`${period}-01`, "yyyy-MM-dd", new Date());
}
export function dateToPeriod(d: Date) {
  return format(d, "yyyy-MM");
}

/**
 * Month selector — desktop: ‹ Aug 2026 › control; mobile: chip row of recent months.
 * Controlled with a "YYYY-MM" value.
 */
export function MonthSelector({
  value,
  onChange,
  variant = "arrows",
  monthsBack = 5,
  className,
  allowFuture = false,
}: {
  value: string;
  onChange: (period: string) => void;
  variant?: "arrows" | "chips";
  monthsBack?: number;
  className?: string;
  allowFuture?: boolean;
}) {
  const current = periodToDate(value);
  const now = new Date();
  const atLimit = !allowFuture && dateToPeriod(current) >= dateToPeriod(now);

  if (variant === "chips") {
    const base = allowFuture ? current : now;
    const options = Array.from({ length: monthsBack + 1 }, (_, i) => {
      const d = subMonths(base, monthsBack - i);
      return { value: dateToPeriod(d), label: format(d, "MMM") };
    });
    if (!options.some((o) => o.value === value)) {
      options.unshift({ value, label: format(current, "MMM yy") });
    }
    return <SegmentedPills options={options} value={value} onChange={onChange} size="sm" className={className} ariaLabel="Select month" />;
  }

  return (
    <div className={cn("inline-flex items-center rounded-full border border-white/70 bg-white/60 p-1 backdrop-blur-md", className)}>
      <button
        type="button"
        aria-label="Previous month"
        onClick={() => onChange(dateToPeriod(subMonths(current, 1)))}
        className="rounded-full p-1.5 text-navy transition-colors hover:bg-navy/5"
      >
        <ChevronLeft className="h-4 w-4" />
      </button>
      <span className="min-w-[96px] px-2 text-center text-sm font-semibold text-navy tabular">{format(current, "MMM yyyy")}</span>
      <button
        type="button"
        aria-label="Next month"
        disabled={atLimit}
        onClick={() => onChange(dateToPeriod(addMonths(current, 1)))}
        className="rounded-full p-1.5 text-navy transition-colors hover:bg-navy/5 disabled:opacity-30"
      >
        <ChevronRight className="h-4 w-4" />
      </button>
    </div>
  );
}
