import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { endOfMonth, format, parse } from "date-fns";
import type {
  AnnouncementRow,
  ExpenseCategory,
  ExpenseRow,
  HostelStats,
  MenuRow,
  RevenueRow,
  TaskRow,
} from "@/lib/types";
import { EXPENSE_CATEGORIES } from "@/lib/types";
import { titleCase } from "@/lib/utils";

/** Validate a `?month=YYYY-MM` search param; falls back to the current month. */
export function resolvePeriod(raw: string | string[] | undefined): string {
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (value && /^\d{4}-(0[1-9]|1[0-2])$/.test(value)) return value;
  return format(new Date(), "yyyy-MM");
}

/** First and last ISO dates of a "YYYY-MM" period. */
export function monthRange(period: string): { from: string; to: string } {
  const start = parse(`${period}-01`, "yyyy-MM-dd", new Date());
  return { from: format(start, "yyyy-MM-dd"), to: format(endOfMonth(start), "yyyy-MM-dd") };
}

export async function getManagerStats(supabase: SupabaseClient, hostelId: string, period: string): Promise<HostelStats | null> {
  const { data, error } = await supabase
    .rpc("rpc_hostel_stats", { p_hostel_id: hostelId, p_period_month: period })
    .maybeSingle();
  if (error) throw error;
  return (data as HostelStats | null) ?? null;
}

export async function getExpenses(supabase: SupabaseClient, hostelId: string, period: string): Promise<ExpenseRow[]> {
  const { from, to } = monthRange(period);
  const { data, error } = await supabase
    .from("expenses")
    .select("*")
    .eq("hostel_id", hostelId)
    .is("deleted_at", null)
    .gte("date", from)
    .lte("date", to)
    .order("date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as ExpenseRow[];
}

export async function getRevenues(supabase: SupabaseClient, hostelId: string, period: string): Promise<RevenueRow[]> {
  const { from, to } = monthRange(period);
  const { data, error } = await supabase
    .from("revenues")
    .select("*")
    .eq("hostel_id", hostelId)
    .is("deleted_at", null)
    .gte("date", from)
    .lte("date", to)
    .order("date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as RevenueRow[];
}

export interface CategorySlice {
  name: string;
  category: ExpenseCategory;
  value: number;
}

/** This-month expenses grouped by category (for the dashboard donut). Categories with zero spend are omitted. */
export async function getExpensesByCategory(supabase: SupabaseClient, hostelId: string, period: string): Promise<CategorySlice[]> {
  const { from, to } = monthRange(period);
  const { data, error } = await supabase
    .from("expenses")
    .select("category, amount")
    .eq("hostel_id", hostelId)
    .is("deleted_at", null)
    .gte("date", from)
    .lte("date", to);
  if (error) throw error;
  const totals = new Map<ExpenseCategory, number>();
  for (const row of (data ?? []) as Pick<ExpenseRow, "category" | "amount">[]) {
    totals.set(row.category, (totals.get(row.category) ?? 0) + Number(row.amount));
  }
  return EXPENSE_CATEGORIES.filter((c) => (totals.get(c) ?? 0) > 0).map((c) => ({
    name: titleCase(c),
    category: c,
    value: Math.round(totals.get(c) ?? 0),
  }));
}

/** Tasks assigned to this manager (RLS already restricts to assigned_to = auth.uid()). */
export async function getMyTasks(supabase: SupabaseClient, hostelId: string, userId: string, opts: { openOnly?: boolean; limit?: number } = {}): Promise<TaskRow[]> {
  let q = supabase
    .from("tasks")
    .select("*")
    .eq("hostel_id", hostelId)
    .eq("assigned_to", userId)
    .is("deleted_at", null)
    .order("due_date", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: false });
  if (opts.openOnly) q = q.neq("status", "done");
  if (opts.limit) q = q.limit(opts.limit);
  const { data, error } = await q;
  if (error) throw error;
  const rows = (data ?? []) as TaskRow[];
  // In-progress first, then pending, then done; the DB order (due date) is kept within each group.
  const rank = { in_progress: 0, pending: 1, done: 2 } as const;
  return rows.sort((a, b) => rank[a.status] - rank[b.status]);
}

/** Owner announcements visible to the manager — audience `all` / `manager` (RLS enforces the same rule; filtered here too as defence in depth). */
export async function getAnnouncementsForManager(supabase: SupabaseClient, hostelId: string, limit = 5): Promise<AnnouncementRow[]> {
  const { data, error } = await supabase
    .from("announcements")
    .select("*")
    .eq("hostel_id", hostelId)
    .in("audience", ["all", "manager"])
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as AnnouncementRow[];
}

export async function getMenu(supabase: SupabaseClient, hostelId: string): Promise<MenuRow[]> {
  const { data, error } = await supabase.from("menus").select("*").eq("hostel_id", hostelId);
  if (error) throw error;
  return (data ?? []) as MenuRow[];
}
