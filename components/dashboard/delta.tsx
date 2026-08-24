import * as React from "react";
import { ArrowDownRight, ArrowUpRight, Minus } from "lucide-react";
import { cx } from "./cx";

/**
 * "…and is that good?"
 *
 * A bare number is not information. Every headline figure on a dashboard is
 * paired with one of these: the same figure for the previous period, turned
 * into a direction, a magnitude and a verdict.
 *
 * Colour comes from the accessible ink ladder (docs/design-system.md §2.5) —
 * `ink-teal` 5.39:1 and `ink-red` 5.53:1 on ivory — never from `teal`/`red`,
 * which fail AA as text.
 */

export type DeltaVerdict = "good" | "bad" | "flat" | "unknown";

/** Percentage change, or null when there is no baseline to compare against. */
export function pctChange(current: number, previous: number): number | null {
  if (!Number.isFinite(current) || !Number.isFinite(previous)) return null;
  if (previous === 0) return current === 0 ? 0 : null;
  return Math.round(((current - previous) / Math.abs(previous)) * 100);
}

function verdictOf(change: number | null, lowerIsBetter: boolean): DeltaVerdict {
  if (change === null) return "unknown";
  if (change === 0) return "flat";
  const up = change > 0;
  return up !== lowerIsBetter ? "good" : "bad";
}

const verdictClass: Record<DeltaVerdict, string> = {
  good: "text-ink-teal",
  bad: "text-ink-red",
  flat: "text-ink-muted",
  unknown: "text-ink-muted",
};

/**
 * Past this much change, a percentage stops informing and starts looking broken
 * — a hostel that spent ₹4k in July and ₹50k in August is "up 1110%", which no
 * one reads as a fact. Above the threshold the line shows the previous figure
 * instead, which is the thing the reader actually wanted to know.
 */
const PCT_CEILING = 300;

/**
 * `▲ 12%  vs Jul` — direction arrow, magnitude, and what it is measured against.
 *
 * @param lowerIsBetter  expenses, complaints, unpaid students: a fall is good.
 * @param baselineLabel  what "previous" was, e.g. "Jul" — always shown, so the
 *                       comparison is never implicit.
 * @param emptyLabel     shown when there is no baseline (first month of data).
 * @param format         how to print the baseline when the percentage is off the
 *                       scale, e.g. `formatINRCompact`.
 */
export function Delta({
  current,
  previous,
  baselineLabel,
  lowerIsBetter = false,
  emptyLabel,
  format,
  className,
}: {
  current: number;
  previous: number | null | undefined;
  baselineLabel: string;
  lowerIsBetter?: boolean;
  emptyLabel?: string;
  format?: (n: number) => string;
  className?: string;
}) {
  const prev = previous == null ? null : Number(previous);
  const change = prev === null ? null : pctChange(current, prev);
  const verdict = verdictOf(change, lowerIsBetter);

  if (change === null || prev === null) {
    return (
      <p className={cx("text-footnote text-ink-muted", className)}>{emptyLabel ?? `No ${baselineLabel} figure to compare with`}</p>
    );
  }

  const Icon = change === 0 ? Minus : change > 0 ? ArrowUpRight : ArrowDownRight;
  const direction = change === 0 ? "no change" : change > 0 ? "up" : "down";
  const offScale = Math.abs(change) > PCT_CEILING;
  const baseline = format ? format(prev) : String(prev);

  return (
    <p className={cx("flex items-center gap-1 text-footnote font-medium", verdictClass[verdict], className)}>
      <Icon className="h-3.5 w-3.5 shrink-0" strokeWidth={2.25} aria-hidden />
      {offScale ? (
        <span className="font-normal text-label-secondary">
          {change > 0 ? "up" : "down"} from <span className="tabular font-medium">{baseline}</span> in {baselineLabel}
        </span>
      ) : (
        <>
          <span className="tabular">{Math.abs(change)}%</span>
          <span className="font-normal text-label-secondary">vs {baselineLabel}</span>
        </>
      )}
      <span className="sr-only">
        ({direction} {offScale ? `from ${baseline}` : `${Math.abs(change)} percent`} compared with {baselineLabel})
      </span>
    </p>
  );
}

/** The same verdict colouring for a hand-written comparison line. */
export function Verdict({
  verdict = "unknown",
  children,
  className,
}: {
  verdict?: DeltaVerdict;
  children: React.ReactNode;
  className?: string;
}) {
  return <p className={cx("text-footnote font-medium", verdictClass[verdict], className)}>{children}</p>;
}
