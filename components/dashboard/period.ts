import { differenceInCalendarDays, endOfMonth, format, getDate, getDaysInMonth, parseISO, subMonths } from "date-fns";

/**
 * Month arithmetic the dashboards share.
 *
 * Every "…and is that good?" line on these pages is either a comparison with the
 * previous period or a position within the current one, so both live here rather
 * than being re-derived in five pages.
 */

/** "2026-08" → "2026-07" */
export function previousPeriod(period: string): string {
  return format(subMonths(parseISO(`${period}-01T00:00:00`), 1), "yyyy-MM");
}

/** "2026-07" → "Jul" — the short form used as a delta baseline label. */
export function shortMonth(period: string): string {
  return format(parseISO(`${period}-01T00:00:00`), "MMM");
}

/** "2026-08" → "August" */
export function longMonth(period: string): string {
  return format(parseISO(`${period}-01T00:00:00`), "MMMM");
}

export interface MonthProgress {
  /** The month this describes, e.g. "August". */
  name: string;
  /** Days elapsed including today, 1-based; equals the month length once past. */
  elapsed: number;
  total: number;
  /** Whole days remaining after today. 0 on the last day, 0 for a past month. */
  remaining: number;
  /** True when `period` is not the month `now` falls in. */
  past: boolean;
  /** Days since the month ended; 0 when it has not. */
  daysSinceEnd: number;
  /** 0–100, how far through the month we are. */
  percent: number;
}

/**
 * Where we are inside a billing period. This is what turns "₹50,400 spent" into
 * "₹50,400 spent, 8 days still to go" — the DB has no due-date column, so the
 * month itself is the only honest deadline to measure against.
 */
export function monthProgress(period: string, now = new Date()): MonthProgress {
  const start = parseISO(`${period}-01T00:00:00`);
  const total = getDaysInMonth(start);
  const name = format(start, "MMMM");
  const end = endOfMonth(start);
  const past = format(now, "yyyy-MM") !== period;
  const future = now < start;

  if (future) {
    return { name, elapsed: 0, total, remaining: total, past: false, daysSinceEnd: 0, percent: 0 };
  }
  if (past) {
    const daysSinceEnd = Math.max(0, differenceInCalendarDays(now, end));
    return { name, elapsed: total, total, remaining: 0, past: true, daysSinceEnd, percent: 100 };
  }
  const elapsed = getDate(now);
  return {
    name,
    elapsed,
    total,
    remaining: total - elapsed,
    past: false,
    daysSinceEnd: 0,
    percent: Math.round((elapsed / total) * 100),
  };
}

/** "8 days left in August" / "August ended 3 days ago" / "Last day of August". */
export function monthDeadline(p: MonthProgress): string {
  if (p.past) {
    if (p.daysSinceEnd === 0) return `${p.name} has ended`;
    return `${p.name} ended ${p.daysSinceEnd} day${p.daysSinceEnd === 1 ? "" : "s"} ago`;
  }
  if (p.remaining === 0) return `Last day of ${p.name}`;
  return `${p.remaining} day${p.remaining === 1 ? "" : "s"} left in ${p.name}`;
}

/**
 * The same fact without the month name, for lines that already say which month
 * they are about — "August so far · 8 days to go". Lower-casing `monthDeadline`
 * would have produced "…left in august".
 */
export function monthDeadlineShort(p: MonthProgress): string {
  if (p.past) {
    if (p.daysSinceEnd === 0) return "just ended";
    return `ended ${p.daysSinceEnd} day${p.daysSinceEnd === 1 ? "" : "s"} ago`;
  }
  if (p.remaining === 0) return "last day of the month";
  return `${p.remaining} day${p.remaining === 1 ? "" : "s"} to go`;
}

export const plural = (n: number, one: string, many = `${one}s`) => (n === 1 ? one : many);
