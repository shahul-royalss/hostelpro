"use client";

import * as React from "react";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { formatINRCompact } from "@/lib/utils";

/**
 * Chart palette (DESIGN.md §1): navy main series, teal comparison, red for expenses,
 * sand for pending, sage for free. Rounded bars, no heavy gridlines.
 */
export const CHART = {
  navy: "#1C2B45",
  teal: "#3E7C74",
  red: "#C4574E",
  sand: "#D8B98A",
  sage: "#8CA687",
  stone: "#E5E1D8",
  muted: "#6E7480",
};

/** Muted categorical palette for donuts (expense categories etc.) */
export const CATEGORY_COLORS = ["#1C2B45", "#3E7C74", "#D8B98A", "#8CA687", "#C4574E", "#6E7480", "#8492B2", "#AA8E5F"];

const axisProps = {
  tick: { fontSize: 11, fill: CHART.muted },
  axisLine: false,
  tickLine: false,
} as const;

const tooltipStyle = {
  contentStyle: {
    borderRadius: 12,
    border: "1px solid rgba(255,255,255,0.8)",
    background: "rgba(255,255,255,0.92)",
    boxShadow: "0 8px 32px rgba(6,22,47,0.08)",
    fontSize: 12,
  },
  labelStyle: { color: CHART.navy, fontWeight: 600 },
  cursor: { fill: "rgba(28,43,69,0.04)" },
} as const;

export interface Series {
  key: string;
  label: string;
  color?: string;
}

const inr = (v: number) => formatINRCompact(v);

/** Area chart — e.g. Revenue vs Expenses last 30 days (OW-1) */
export function AreaTrend({
  data,
  xKey,
  series,
  height = 260,
  currency = true,
  showLegend = true,
}: {
  data: Record<string, unknown>[];
  xKey: string;
  series: Series[];
  height?: number;
  currency?: boolean;
  showLegend?: boolean;
}) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <AreaChart data={data} margin={{ top: 8, right: 8, left: -12, bottom: 0 }}>
        <defs>
          {series.map((s, i) => {
            const c = s.color ?? (i === 0 ? CHART.navy : CHART.red);
            return (
              <linearGradient key={s.key} id={`grad-${s.key}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={c} stopOpacity={0.18} />
                <stop offset="100%" stopColor={c} stopOpacity={0} />
              </linearGradient>
            );
          })}
        </defs>
        <CartesianGrid vertical={false} stroke={CHART.stone} strokeDasharray="3 3" />
        <XAxis dataKey={xKey} {...axisProps} minTickGap={24} />
        <YAxis {...axisProps} tickFormatter={currency ? inr : undefined} width={56} />
        <Tooltip {...tooltipStyle} formatter={(v: number) => (currency ? formatINRCompact(v) : v)} />
        {showLegend && <Legend iconType="circle" wrapperStyle={{ fontSize: 12, paddingTop: 8 }} />}
        {series.map((s, i) => {
          const c = s.color ?? (i === 0 ? CHART.navy : CHART.red);
          return (
            <Area key={s.key} type="monotone" dataKey={s.key} name={s.label} stroke={c} strokeWidth={2} fill={`url(#grad-${s.key})`} dot={false} activeDot={{ r: 4 }} />
          );
        })}
      </AreaChart>
    </ResponsiveContainer>
  );
}

/** Line chart — hostels onboarded, profit trend, complaints per week */
export function LineTrend({
  data,
  xKey,
  series,
  height = 260,
  currency = false,
}: {
  data: Record<string, unknown>[];
  xKey: string;
  series: Series[];
  height?: number;
  currency?: boolean;
}) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <LineChart data={data} margin={{ top: 8, right: 8, left: -12, bottom: 0 }}>
        <CartesianGrid vertical={false} stroke={CHART.stone} strokeDasharray="3 3" />
        <XAxis dataKey={xKey} {...axisProps} minTickGap={24} />
        <YAxis {...axisProps} tickFormatter={currency ? inr : undefined} width={56} allowDecimals={false} />
        <Tooltip {...tooltipStyle} formatter={(v: number) => (currency ? formatINRCompact(v) : v)} />
        {series.length > 1 && <Legend iconType="circle" wrapperStyle={{ fontSize: 12, paddingTop: 8 }} />}
        {series.map((s, i) => (
          <Line key={s.key} type="monotone" dataKey={s.key} name={s.label} stroke={s.color ?? (i === 0 ? CHART.navy : CHART.teal)} strokeWidth={2} dot={{ r: 3, strokeWidth: 0, fill: s.color ?? (i === 0 ? CHART.navy : CHART.teal) }} activeDot={{ r: 5 }} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  );
}

/** Grouped bars with rounded tops — Revenue vs Expenses (SA-4) */
export function GroupedBars({
  data,
  xKey,
  series,
  height = 260,
  currency = true,
}: {
  data: Record<string, unknown>[];
  xKey: string;
  series: Series[];
  height?: number;
  currency?: boolean;
}) {
  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: -12, bottom: 0 }} barGap={4} barCategoryGap="28%">
        <CartesianGrid vertical={false} stroke={CHART.stone} strokeDasharray="3 3" />
        <XAxis dataKey={xKey} {...axisProps} />
        <YAxis {...axisProps} tickFormatter={currency ? inr : undefined} width={56} />
        <Tooltip {...tooltipStyle} formatter={(v: number) => (currency ? formatINRCompact(v) : v)} />
        <Legend iconType="circle" wrapperStyle={{ fontSize: 12, paddingTop: 8 }} />
        {series.map((s, i) => (
          <Bar key={s.key} dataKey={s.key} name={s.label} fill={s.color ?? (i === 0 ? CHART.teal : CHART.red)} radius={[6, 6, 0, 0]} maxBarSize={28} />
        ))}
      </BarChart>
    </ResponsiveContainer>
  );
}

/** Donut — subscription status, expenses by category */
export function Donut({
  data,
  height = 240,
  currency = false,
  centerLabel,
  centerValue,
  colors = CATEGORY_COLORS,
}: {
  data: { name: string; value: number; color?: string }[];
  height?: number;
  currency?: boolean;
  centerLabel?: string;
  centerValue?: React.ReactNode;
  colors?: string[];
}) {
  const total = data.reduce((s, d) => s + d.value, 0);
  return (
    <div className="relative">
      <ResponsiveContainer width="100%" height={height}>
        <PieChart>
          <Pie data={data} dataKey="value" nameKey="name" innerRadius="62%" outerRadius="88%" paddingAngle={2} cornerRadius={6} stroke="none">
            {data.map((d, i) => (
              <Cell key={d.name} fill={d.color ?? colors[i % colors.length]} />
            ))}
          </Pie>
          <Tooltip {...tooltipStyle} formatter={(v: number) => (currency ? formatINRCompact(v) : v)} />
        </PieChart>
      </ResponsiveContainer>
      <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
        <div className="text-[22px] font-bold text-navy tabular">{centerValue ?? (currency ? formatINRCompact(total) : total)}</div>
        {centerLabel ? <div className="label-caps">{centerLabel}</div> : null}
      </div>
    </div>
  );
}

/** Legend rows for donuts (name • value • %) */
export function DonutLegend({ data, currency = false, colors = CATEGORY_COLORS }: { data: { name: string; value: number; color?: string }[]; currency?: boolean; colors?: string[] }) {
  const total = data.reduce((s, d) => s + d.value, 0) || 1;
  return (
    <ul className="space-y-2">
      {data.map((d, i) => (
        <li key={d.name} className="flex items-center justify-between gap-3 text-sm">
          <span className="flex items-center gap-2 text-charcoal">
            <span className="h-2.5 w-2.5 rounded-full" style={{ background: d.color ?? colors[i % colors.length] }} />
            {d.name}
          </span>
          <span className="tabular text-muted">
            <span className="font-medium text-navy">{currency ? formatINRCompact(d.value) : d.value}</span>
            <span className="ml-2 text-xs">{Math.round((d.value / total) * 100)}%</span>
          </span>
        </li>
      ))}
    </ul>
  );
}
