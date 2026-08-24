import * as React from "react";
import { cn } from "@/lib/utils";

/**
 * Progress meters, server-rendered, zero JavaScript.
 *
 * Tracks use the Apple fill ladder (`bg-fill-tertiary`, docs/design-system.md
 * §2.3) rather than an opaque grey, so the meter sits *in* the material instead
 * of on top of it. Fills use `mark-*` / brand hues, which clear the 3:1
 * graphical-object floor (§2.5).
 */

export type MeterTone = "navy" | "teal" | "sand" | "red" | "sage";

const fillClass: Record<MeterTone, string> = {
  navy: "bg-navy",
  teal: "bg-teal",
  sand: "bg-mark-sand",
  red: "bg-red",
  sage: "bg-mark-sage",
};

const clamp = (n: number) => Math.min(100, Math.max(0, Number.isFinite(n) ? n : 0));

/** A single filled bar. `label` is what a screen reader hears instead of the geometry. */
export function Meter({
  percent,
  label,
  tone = "navy",
  size = "md",
  className,
}: {
  percent: number;
  label: string;
  tone?: MeterTone;
  size?: "sm" | "md";
  className?: string;
}) {
  const p = clamp(percent);
  return (
    <div
      role="img"
      aria-label={label}
      className={cn("w-full overflow-hidden rounded-full bg-fill-tertiary", size === "sm" ? "h-1.5" : "h-2", className)}
    >
      <div className={cn("h-full rounded-full", fillClass[tone])} style={{ width: `${p}%` }} />
    </div>
  );
}

export interface MeterSegment {
  /** Raw value; widths are computed as a share of the sum. */
  value: number;
  tone: MeterTone;
  label: string;
}

/**
 * A stacked bar — Apple's storage / Screen Time breakdown. Reads far better
 * than a donut at 320px, and costs no client JavaScript.
 */
export function SegmentMeter({
  segments,
  label,
  className,
}: {
  segments: MeterSegment[];
  label: string;
  className?: string;
}) {
  const total = segments.reduce((s, x) => s + Math.max(0, x.value), 0);
  if (total <= 0) return <div className={cn("h-2.5 w-full rounded-full bg-fill-tertiary", className)} aria-hidden />;
  return (
    <div role="img" aria-label={label} className={cn("flex h-2.5 w-full gap-0.5 overflow-hidden rounded-full", className)}>
      {segments
        .filter((s) => s.value > 0)
        .map((s) => (
          <div
            key={s.label}
            className={cn("h-full first:rounded-l-full last:rounded-r-full", fillClass[s.tone])}
            style={{ width: `${(s.value / total) * 100}%` }}
          />
        ))}
    </div>
  );
}
