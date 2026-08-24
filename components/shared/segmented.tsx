"use client";

import * as React from "react";
import { cn } from "@/lib/utils";

export interface SegmentOption<T extends string> {
  value: T;
  label: React.ReactNode;
  count?: number;
  /** tone of the active pill; default navy */
  tone?: "navy" | "teal" | "sand" | "red" | "sage";
}

const activeTone = {
  navy: "bg-navy text-white",
  teal: "bg-teal text-white",
  sand: "bg-sand-deep text-white",
  red: "bg-red text-white",
  sage: "bg-sage text-white",
};

/**
 * Segmented pill filters (All / Active / Expiring / …) — horizontally scrollable on mobile.
 * Controlled component; use for status filters, month chips, audience selectors, payment mode.
 */
export function SegmentedPills<T extends string>({
  options,
  value,
  onChange,
  className,
  size = "md",
  fullWidth = false,
  ariaLabel,
}: {
  options: SegmentOption<T>[];
  value: T;
  onChange: (v: T) => void;
  className?: string;
  size?: "sm" | "md";
  fullWidth?: boolean;
  ariaLabel?: string;
}) {
  return (
    <div
      role="tablist"
      aria-label={ariaLabel}
      className={cn(
        "no-scrollbar flex gap-2 overflow-x-auto",
        fullWidth && "rounded-full bg-material-tint/60 border border-material-strong p-1 backdrop-blur-md",
        className,
      )}
    >
      {options.map((opt) => {
        const active = opt.value === value;
        return (
          <button
            key={opt.value}
            role="tab"
            type="button"
            aria-selected={active}
            onClick={() => onChange(opt.value)}
            className={cn(
              // .tap-target grows the hit area to 44x44 on touch without
              // changing the pill's size — a 28px filter chip is the design.
              "tap-target press-scale [--press:0.97] inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full font-medium transition-all",
              size === "sm" ? "px-3 py-1.5 text-xs" : "px-4 py-2 text-sm",
              fullWidth && "flex-1 justify-center",
              active
                ? cn(activeTone[opt.tone ?? "navy"], "shadow-sm")
                : cn("text-muted hover:text-navy", !fullWidth && "bg-material-tint/60 border border-material-strong backdrop-blur-md hover:bg-material-tint/80"),
            )}
          >
            {opt.label}
            {typeof opt.count === "number" ? (
              <span className={cn("rounded-full px-1.5 py-0.5 text-[10px] font-semibold tabular", active ? "bg-white/20" : "bg-navy/5 text-navy")}>
                {opt.count}
              </span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}
