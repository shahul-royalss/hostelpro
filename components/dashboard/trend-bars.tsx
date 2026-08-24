import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * A bar strip, rendered on the server with flexbox and percentage heights.
 *
 * It replaces the Recharts area chart and donut that used to sit on these
 * dashboards. Two reasons, in this order:
 *
 *  1. A 30-point area chart with an axis, a legend and a tooltip is unreadable
 *     on a 360px phone, and the phone is the primary target.
 *  2. Recharts is a client component. Every dashboard that renders one pays for
 *     the library in First Load JS and a hydration pass before the page settles.
 *     This costs zero bytes of JavaScript.
 *
 * Bars are graphical objects, so the fills are the 3:1-clearing tokens
 * (docs/design-system.md §2.5), not the raw brand hues.
 */

export type BarTone = "navy" | "teal" | "red" | "sand" | "sage";

const barClass: Record<BarTone, string> = {
  navy: "bg-navy",
  teal: "bg-teal",
  red: "bg-red",
  sand: "bg-mark-sand",
  sage: "bg-mark-sage",
};

const dotClass: Record<BarTone, string> = {
  navy: "bg-navy",
  teal: "bg-teal",
  red: "bg-red",
  sand: "bg-mark-sand",
  sage: "bg-mark-sage",
};

export interface TrendPoint {
  label: string;
  a: number;
  b?: number;
}

function Legend({ tone, label }: { tone: BarTone; label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 text-caption-1 text-label-secondary">
      <span className={cn("h-2 w-2 rounded-xs", dotClass[tone])} aria-hidden />
      {label}
    </span>
  );
}

export function TrendBars({
  points,
  aLabel,
  bLabel,
  aTone = "teal",
  bTone = "red",
  summary,
  className,
}: {
  points: TrendPoint[];
  aLabel: string;
  bLabel?: string;
  aTone?: BarTone;
  bTone?: BarTone;
  /** What a screen reader hears instead of the bars. */
  summary: string;
  className?: string;
}) {
  const max = Math.max(1, ...points.flatMap((p) => [p.a, p.b ?? 0]));
  const paired = bLabel !== undefined;
  const first = points[0]?.label;
  const last = points[points.length - 1]?.label;

  return (
    <div className={className}>
      <div className="mb-3 flex flex-wrap items-center gap-x-4 gap-y-1">
        <Legend tone={aTone} label={aLabel} />
        {paired ? <Legend tone={bTone} label={bLabel} /> : null}
      </div>

      <div role="img" aria-label={summary} className="flex h-24 items-end gap-[3px] md:h-32">
        {points.map((p, i) => (
          <div key={`${p.label}-${i}`} className="flex h-full flex-1 items-end gap-px">
            <div
              className={cn("min-h-px w-full rounded-t-xs", barClass[aTone], p.a === 0 && "bg-fill-tertiary")}
              style={{ height: `${Math.max(p.a > 0 ? 3 : 1.5, (p.a / max) * 100)}%` }}
            />
            {paired ? (
              <div
                className={cn("min-h-px w-full rounded-t-xs", barClass[bTone], (p.b ?? 0) === 0 && "bg-fill-tertiary")}
                style={{ height: `${Math.max((p.b ?? 0) > 0 ? 3 : 1.5, ((p.b ?? 0) / max) * 100)}%` }}
              />
            ) : null}
          </div>
        ))}
      </div>

      <div className="mt-2 flex justify-between text-caption-2 text-label-secondary tabular">
        <span>{first}</span>
        <span>{last}</span>
      </div>
    </div>
  );
}
