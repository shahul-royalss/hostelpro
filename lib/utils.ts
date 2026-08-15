import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { format, parseISO, differenceInCalendarDays, isValid } from "date-fns";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/* ───────────────────────── Currency & numbers ───────────────────────── */

const inr = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 0,
});

/** ₹12,345 */
export function formatINR(amount: number | string | null | undefined): string {
  const n = Number(amount ?? 0);
  return inr.format(Number.isFinite(n) ? n : 0);
}

/** Compact: ₹2.45L / ₹18.5k / ₹1.2Cr — for stat cards */
export function formatINRCompact(amount: number | string | null | undefined): string {
  const n = Number(amount ?? 0);
  if (!Number.isFinite(n)) return "₹0";
  const abs = Math.abs(n);
  const sign = n < 0 ? "-" : "";
  if (abs >= 1_00_00_000) return `${sign}₹${trim(abs / 1_00_00_000)}Cr`;
  if (abs >= 1_00_000) return `${sign}₹${trim(abs / 1_00_000)}L`;
  if (abs >= 1_000) return `${sign}₹${trim(abs / 1_000)}k`;
  return `${sign}₹${Math.round(abs)}`;
}
function trim(v: number) {
  return v.toFixed(v >= 100 ? 0 : v >= 10 ? 1 : 2).replace(/\.?0+$/, "");
}

export function formatNumber(n: number | string | null | undefined): string {
  return new Intl.NumberFormat("en-IN").format(Number(n ?? 0));
}

export function percent(part: number, total: number): number {
  if (!total) return 0;
  return Math.round((part / total) * 100);
}

/* ───────────────────────── Dates ───────────────────────── */

export function toDate(value: string | Date | null | undefined): Date | null {
  if (!value) return null;
  const d = typeof value === "string" ? parseISO(value) : value;
  return isValid(d) ? d : null;
}

/** 12 Aug 2026 */
export function formatDate(value: string | Date | null | undefined, fmt = "d MMM yyyy"): string {
  const d = toDate(value);
  return d ? format(d, fmt) : "—";
}

/** 12 Aug, 09:41 */
export function formatDateTime(value: string | Date | null | undefined): string {
  const d = toDate(value);
  return d ? format(d, "d MMM, HH:mm") : "—";
}

/** YYYY-MM-DD for <input type="date"> and DB date columns */
export function toISODate(d: Date = new Date()): string {
  return format(d, "yyyy-MM-dd");
}

/** YYYY-MM for period_month */
export function toPeriodMonth(d: Date = new Date()): string {
  return format(d, "yyyy-MM");
}

/** "Aug 2026" from "2026-08" */
export function formatPeriodMonth(period: string): string {
  const d = toDate(`${period}-01`);
  return d ? format(d, "MMM yyyy") : period;
}

export function daysUntil(value: string | Date | null | undefined): number | null {
  const d = toDate(value);
  if (!d) return null;
  return differenceInCalendarDays(d, new Date());
}

/** Time-of-day greeting */
export function greeting(date = new Date()): string {
  const h = date.getHours();
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

/* ───────────────────────── Strings ───────────────────────── */

export function initials(name: string | null | undefined): string {
  if (!name) return "?";
  const parts = name.trim().split(/\s+/).filter(Boolean);
  const first = parts[0]?.[0] ?? "";
  const last = parts.length > 1 ? parts[parts.length - 1][0] : "";
  return (first + last).toUpperCase() || "?";
}

export function firstName(name: string | null | undefined): string {
  return (name ?? "").trim().split(/\s+/)[0] ?? "";
}

export function titleCase(s: string | null | undefined): string {
  return (s ?? "")
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

/** Normalise an Indian phone number to 10 digits (strips +91 / spaces / dashes). */
export function normalizePhone(input: string): string {
  const digits = input.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(2);
  if (digits.length === 11 && digits.startsWith("0")) return digits.slice(1);
  return digits;
}

export function isPhoneLike(input: string): boolean {
  return /^[\d\s+\-()]{8,16}$/.test(input.trim()) && normalizePhone(input).length >= 10;
}

/**
 * Students sign in with their phone number. Supabase Auth requires an email,
 * so we map phone → deterministic synthetic email (never shown to users).
 */
export const STUDENT_LOGIN_DOMAIN = "student.hostelpro.local";
export function studentLoginEmail(phone: string): string {
  return `${normalizePhone(phone)}@${STUDENT_LOGIN_DOMAIN}`;
}

/** Turn a login identifier (email or phone) into the email Supabase expects. */
export function resolveLoginEmail(identifier: string): string {
  const trimmed = identifier.trim();
  if (trimmed.includes("@")) return trimmed.toLowerCase();
  if (isPhoneLike(trimmed)) return studentLoginEmail(trimmed);
  return trimmed.toLowerCase();
}

/* ───────────────────────── Misc ───────────────────────── */

export function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

export function groupBy<T, K extends string | number>(arr: T[], key: (t: T) => K): Record<K, T[]> {
  return arr.reduce((acc, item) => {
    const k = key(item);
    (acc[k] ||= []).push(item);
    return acc;
  }, {} as Record<K, T[]>);
}

export function sumBy<T>(arr: T[], fn: (t: T) => number | string | null | undefined): number {
  return arr.reduce((s, t) => s + Number(fn(t) ?? 0), 0);
}
