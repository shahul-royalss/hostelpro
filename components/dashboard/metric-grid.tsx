import * as React from "react";
import Link from "next/link";
import { ChevronRight, type LucideIcon } from "lucide-react";
import { cn } from "@/lib/utils";
import { cx } from "./cx";

/**
 * Secondary numbers, grouped into ONE surface.
 *
 * Four separate cards on a 360px phone become four full-width blocks of equal
 * weight — a wall of same-sized numbers with no hierarchy, which is the shape
 * every one of these dashboards had. A 2×2 group inside a single material keeps
 * them subordinate to the hero, fits above the fold, and gives the eye one
 * object instead of four.
 *
 * Values sit at `text-title-2` (22px) — deliberately two steps below the hero's
 * `text-stat` (36px).
 */

export type MetricTone = "navy" | "teal" | "red" | "sand" | "sage" | "muted";

const valueClass: Record<MetricTone, string> = {
  navy: "text-ink-navy",
  teal: "text-ink-teal",
  red: "text-ink-red",
  sand: "text-ink-sand",
  sage: "text-ink-sage",
  muted: "text-ink-muted",
};

const iconClass: Record<MetricTone, string> = {
  navy: "text-label-tertiary",
  teal: "text-ink-teal",
  red: "text-ink-red",
  sand: "text-ink-sand",
  sage: "text-ink-sage",
  muted: "text-label-tertiary",
};

export function MetricGrid({
  children,
  columns = 2,
  className,
}: {
  children: React.ReactNode;
  columns?: 2 | 3;
  className?: string;
}) {
  return (
    <section
      className={cn(
        "material-regular grid overflow-hidden rounded-card squircle",
        // A single hairline grid: each cell draws its own top/left rule and the
        // outer edges are clipped by the container, so there is no double line.
        columns === 2 ? "grid-cols-2" : "grid-cols-2 sm:grid-cols-3",
        className,
      )}
    >
      {children}
    </section>
  );
}

export function Metric({
  label,
  value,
  caption,
  icon: Icon,
  tone = "navy",
  href,
  className,
}: {
  label: React.ReactNode;
  value: React.ReactNode;
  /** The comparison, target or share — never omit it for a number that can be judged. */
  caption?: React.ReactNode;
  icon?: LucideIcon;
  tone?: MetricTone;
  href?: string;
  className?: string;
}) {
  const inner = (
    <>
      <div className="flex items-start justify-between gap-2">
        <div className="label-caps text-label-secondary">{label}</div>
        {Icon ? <Icon className={cn("h-4 w-4 shrink-0", iconClass[tone])} strokeWidth={1.9} aria-hidden /> : null}
      </div>
      {/* cx, not cn: tailwind-merge would delete text-title-2. See ./cx.ts. */}
      <div className={cx("mt-1.5 text-title-2 tabular", valueClass[tone])}>{value}</div>
      {caption ? (
        <div className="mt-0.5 flex items-center gap-0.5 text-caption-1 text-label-secondary">
          <span className="min-w-0 truncate">{caption}</span>
          {href ? <ChevronRight className="h-3 w-3 shrink-0 text-label-tertiary" aria-hidden /> : null}
        </div>
      ) : null}
    </>
  );

  const cell = cn(
    // `-mt-px -ml-px` + a container that clips means only the interior rules show.
    "relative -ml-px -mt-px block border-l border-t border-separator p-4",
    className,
  );

  if (!href) return <div className={cell}>{inner}</div>;
  return (
    <Link href={href} className={cn(cell, "transition-colors duration-quick ease-sys hover:bg-fill-quaternary active:bg-fill-tertiary")}>
      {inner}
    </Link>
  );
}
