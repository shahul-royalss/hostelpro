import * as React from "react";
import type { LucideIcon } from "lucide-react";
import { cn, formatINR, formatINRCompact } from "@/lib/utils";
import { cx } from "./cx";

/**
 * The one number this role opens the app for.
 *
 * Rules this component exists to enforce:
 *   1. It is the largest thing on the screen — `text-stat` (36px, the top of the
 *      ramp) and nothing else on the page is allowed above `text-title-2` (22px).
 *   2. It never appears alone. `verdict` is required-by-convention: a comparison,
 *      a target or a rate, so the number answers "…and is that good?".
 *   3. Numbers are tabular, so a figure that updates does not jitter.
 */

export type HeroTone = "navy" | "teal" | "red" | "sand";

const valueClass: Record<HeroTone, string> = {
  navy: "text-ink-navy",
  teal: "text-ink-teal",
  red: "text-ink-red",
  sand: "text-ink-sand",
};

const iconClass: Record<HeroTone, string> = {
  navy: "bg-navy/10 text-ink-navy",
  teal: "bg-teal-soft text-ink-teal",
  red: "bg-red-soft text-ink-red",
  sand: "bg-sand-soft text-ink-sand",
};

/**
 * Money at hero size. `formatINR` is exact and that is what an owner wants to
 * read — but at 36px a crore-scale figure overflows a 320px phone, so anything
 * at or above ₹10,00,000 falls back to the compact form and the exact figure is
 * handed to the caller for the caption line.
 */
export function heroAmount(n: number): { display: string; exact: string; compacted: boolean } {
  const exact = formatINR(n);
  const compacted = Math.abs(n) >= 10_00_000;
  return { display: compacted ? formatINRCompact(n) : exact, exact, compacted };
}

export function HeroStat({
  eyebrow,
  value,
  unit,
  icon: Icon,
  tone = "navy",
  verdict,
  caption,
  meter,
  footer,
  className,
  size = "lg",
  headingLevel: H = "h2",
}: {
  eyebrow: React.ReactNode;
  value: React.ReactNode;
  /** Trailing unit or denominator, set two steps down so the value still leads. */
  unit?: React.ReactNode;
  icon?: LucideIcon;
  tone?: HeroTone;
  /** The comparison line — a <Delta />, a <Verdict />, or a rate. */
  verdict?: React.ReactNode;
  /** Neutral supporting detail: "of ₹63,000 billed", "12 of 36 beds". */
  caption?: React.ReactNode;
  meter?: React.ReactNode;
  /** Full-bleed rows below the hairline — usually an InsetRow-style link. */
  footer?: React.ReactNode;
  className?: string;
  /**
   * `lg` is the top of the ramp (36px) and there should be exactly one per
   * screen. `md` (28px) is the runner-up on a dashboard that genuinely has two
   * headline figures — it still outranks every `Metric` (22px) below it.
   */
  size?: "lg" | "md";
  headingLevel?: "h1" | "h2";
}) {
  return (
    <section className={cn("material-regular overflow-hidden rounded-card squircle", className)}>
      <div className="p-5 md:p-6">
        <div className="flex items-start justify-between gap-3">
          <H className="label-caps text-label-secondary">{eyebrow}</H>
          {Icon ? (
            <span className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-control squircle", iconClass[tone])} aria-hidden>
              <Icon className="h-5 w-5" strokeWidth={1.9} />
            </span>
          ) : null}
        </div>

        {/* cx, not cn: tailwind-merge would delete the ramp class here. See ./cx.ts. */}
        <p className={cx("mt-2 flex flex-wrap items-baseline gap-x-2 tabular", size === "lg" ? "text-stat" : "text-title-1", valueClass[tone])}>
          <span>{value}</span>
          {unit ? (
            <span className={cx("font-semibold text-label-secondary", size === "lg" ? "text-title-3" : "text-headline")}>{unit}</span>
          ) : null}
        </p>

        {verdict ? <div className="mt-1.5">{verdict}</div> : null}
        {meter ? <div className="mt-4">{meter}</div> : null}
        {caption ? <p className="mt-2 text-footnote text-label-secondary">{caption}</p> : null}
      </div>
      {footer}
    </section>
  );
}
