import * as React from "react";
import type { LucideIcon } from "lucide-react";
import { TrendingDown, TrendingUp } from "lucide-react";
import { cn } from "@/lib/utils";
import { GlassCard } from "./glass-card";

export type StatTone = "navy" | "teal" | "sand" | "red" | "sage" | "muted";

const toneText: Record<StatTone, string> = {
  navy: "text-navy",
  teal: "text-teal",
  sand: "text-sand-deep",
  red: "text-red",
  sage: "text-sage",
  muted: "text-muted",
};
const toneIcon: Record<StatTone, string> = {
  navy: "text-navy/40",
  teal: "text-teal/50",
  sand: "text-sand",
  red: "text-red/50",
  sage: "text-sage",
  muted: "text-muted/50",
};

/**
 * Stat card: caption label + big number + optional caption / trend / icon.
 * Desktop 36px numbers, mobile 28px (DESIGN.md typography).
 */
export function StatCard({
  label,
  value,
  caption,
  icon: Icon,
  tone = "navy",
  trend,
  className,
  size = "md",
  children,
}: {
  label: string;
  value: React.ReactNode;
  caption?: React.ReactNode;
  icon?: LucideIcon;
  tone?: StatTone;
  /** e.g. { value: 12, label: "vs last month" } — positive → teal, negative → red */
  trend?: { value: number; label?: string };
  className?: string;
  size?: "sm" | "md";
  children?: React.ReactNode;
}) {
  return (
    <GlassCard className={cn("flex h-full flex-col justify-between", size === "sm" && "p-4", className)}>
      <div className="mb-2 flex items-start justify-between gap-2">
        <div className="label-caps">{label}</div>
        {Icon ? <Icon className={cn("h-5 w-5 shrink-0", toneIcon[tone])} strokeWidth={1.75} /> : null}
      </div>
      <div className="mt-auto">
        <div className={cn("tabular", size === "sm" ? "text-stat-sm" : "text-stat-sm md:text-stat", toneText[tone])}>
          {value}
        </div>
        {(caption || trend) && (
          <div className="mt-1 flex items-center gap-2 text-xs text-muted">
            {trend ? (
              <span className={cn("inline-flex items-center gap-1 font-medium", trend.value >= 0 ? "text-teal" : "text-red")}>
                {trend.value >= 0 ? <TrendingUp className="h-3.5 w-3.5" /> : <TrendingDown className="h-3.5 w-3.5" />}
                {Math.abs(trend.value)}%
              </span>
            ) : null}
            {trend?.label ? <span>{trend.label}</span> : null}
            {caption ? <span>{caption}</span> : null}
          </div>
        )}
        {children}
      </div>
    </GlassCard>
  );
}

/** Thin progress ring used in the Occupancy stat (OW-1). */
export function ProgressRing({
  percent,
  size = 48,
  stroke = 3,
  className,
  tone = "navy",
}: {
  percent: number;
  size?: number;
  stroke?: number;
  className?: string;
  tone?: "navy" | "teal";
}) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const p = Math.min(100, Math.max(0, percent));
  return (
    <div className={cn("relative shrink-0", className)} style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" strokeWidth={stroke} className="stroke-stone" />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c - (p / 100) * c}
          className={tone === "teal" ? "stroke-teal" : "stroke-navy"}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center text-[11px] font-bold text-navy tabular">
        {Math.round(p)}%
      </div>
    </div>
  );
}
