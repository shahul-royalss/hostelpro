import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { format, startOfMonth, subMonths } from "date-fns";
import type {
  ComplaintsPerWeekRow,
  DailyFinanceRow,
  HostelRow,
  HostelStats,
  SaDashboardStats,
  SaHostelRow,
  SaOnboardingPoint,
  SubscriptionRow,
  UserRow,
} from "@/lib/types";
import { toISODate } from "@/lib/utils";

/**
 * Super Admin read helpers. All go through the RLS client — the SA policies /
 * SECURITY DEFINER RPCs already gate on app.is_super_admin().
 */

export async function fetchSaDashboard(supabase: SupabaseClient): Promise<SaDashboardStats> {
  const { data, error } = await supabase.rpc("rpc_sa_dashboard").maybeSingle();
  if (error) throw error;
  const d = (data ?? {}) as Partial<SaDashboardStats>;
  return {
    total_hostels: Number(d.total_hostels ?? 0),
    total_owners: Number(d.total_owners ?? 0),
    total_students: Number(d.total_students ?? 0),
    active_subs: Number(d.active_subs ?? 0),
    expiring_subs: Number(d.expiring_subs ?? 0),
    expired_subs: Number(d.expired_subs ?? 0),
    monthly_subscription_revenue: Number(d.monthly_subscription_revenue ?? 0),
  };
}

export async function fetchOnboardingSeries(supabase: SupabaseClient): Promise<SaOnboardingPoint[]> {
  const { data, error } = await supabase.rpc("rpc_sa_onboarding_series");
  if (error) throw error;
  return ((data ?? []) as SaOnboardingPoint[]).map((p) => ({ month: p.month, hostels: Number(p.hostels ?? 0) }));
}

export async function fetchSaHostels(supabase: SupabaseClient): Promise<SaHostelRow[]> {
  const { data, error } = await supabase.rpc("rpc_sa_hostels");
  if (error) throw error;
  return ((data ?? []) as SaHostelRow[]).map((r) => ({
    ...r,
    sub_amount: r.sub_amount === null ? null : Number(r.sub_amount),
    days_left: r.days_left === null ? null : Number(r.days_left),
    total_beds: Number(r.total_beds ?? 0),
    occupied_beds: Number(r.occupied_beds ?? 0),
    active_students: Number(r.active_students ?? 0),
    open_complaints: Number(r.open_complaints ?? 0),
  }));
}

/** One hostel summary row (same shape as the table) — null when not found. */
export async function fetchSaHostel(supabase: SupabaseClient, hostelId: string): Promise<SaHostelRow | null> {
  const rows = await fetchSaHostels(supabase);
  return rows.find((r) => r.hostel_id === hostelId) ?? null;
}

/** Raw hostels row (floors / rooms / beds-per-room defaults) — null when not found or not readable. */
export async function fetchHostelRow(supabase: SupabaseClient, hostelId: string): Promise<HostelRow | null> {
  const { data, error } = await supabase.from("hostels").select("*").eq("id", hostelId).maybeSingle();
  if (error) throw error;
  return (data as HostelRow | null) ?? null;
}

/** Subscription history for one hostel, newest first. */
export async function fetchSubscriptionHistory(supabase: SupabaseClient, hostelId: string): Promise<SubscriptionRow[]> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("*")
    .eq("hostel_id", hostelId)
    .order("end_date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) throw error;
  return ((data ?? []) as SubscriptionRow[]).map((s) => ({ ...s, amount: Number(s.amount) }));
}

/** All subscriptions on the platform grouped by hostel (for the SA-3 slide-over). */
export async function fetchAllSubscriptionsByHostel(supabase: SupabaseClient): Promise<Record<string, SubscriptionRow[]>> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("*")
    .order("end_date", { ascending: false })
    .order("created_at", { ascending: false });
  if (error) throw error;
  const out: Record<string, SubscriptionRow[]> = {};
  for (const raw of (data ?? []) as SubscriptionRow[]) {
    const s = { ...raw, amount: Number(raw.amount) };
    (out[s.hostel_id] ||= []).push(s);
  }
  return out;
}

export async function fetchHostelStats(supabase: SupabaseClient, hostelId: string): Promise<HostelStats | null> {
  const { data, error } = await supabase.rpc("rpc_hostel_stats", { p_hostel_id: hostelId }).maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const s = data as Record<string, unknown>;
  const num = (k: string) => Number(s[k] ?? 0);
  return {
    total_beds: num("total_beds"),
    occupied_beds: num("occupied_beds"),
    active_students: num("active_students"),
    open_complaints: num("open_complaints"),
    fees_collected: num("fees_collected"),
    fees_pending: num("fees_pending"),
    students_paid: num("students_paid"),
    students_unpaid: num("students_unpaid"),
    pending_leaves: num("pending_leaves"),
    visitors_today: num("visitors_today"),
    pending_tasks: num("pending_tasks"),
    revenue_today: num("revenue_today"),
    expenses_today: num("expenses_today"),
    revenue_month: num("revenue_month"),
    expenses_month: num("expenses_month"),
    subscription_days_left: s.subscription_days_left === null ? null : num("subscription_days_left"),
    subscription_state: (s.subscription_state as HostelStats["subscription_state"]) ?? "expired",
  };
}

export interface MonthlyFinancePoint {
  month: string; // "Aug"
  period: string; // "2026-08"
  revenue: number;
  expenses: number;
}

/** Revenue vs expenses per month for the last `months` months (SA-4 grouped bars) — rpc_daily_finance aggregated by month. */
export async function fetchMonthlyFinance(supabase: SupabaseClient, hostelId: string, months = 6): Promise<MonthlyFinancePoint[]> {
  const from = toISODate(startOfMonth(subMonths(new Date(), months - 1)));
  const to = toISODate(new Date());
  const { data, error } = await supabase.rpc("rpc_daily_finance", { p_hostel_id: hostelId, p_from: from, p_to: to });
  if (error) throw error;

  const buckets = new Map<string, MonthlyFinancePoint>();
  for (let i = 0; i < months; i++) {
    const d = subMonths(startOfMonth(new Date()), months - 1 - i);
    const period = format(d, "yyyy-MM");
    buckets.set(period, { period, month: format(d, "MMM"), revenue: 0, expenses: 0 });
  }
  for (const r of (data ?? []) as DailyFinanceRow[]) {
    const b = buckets.get(String(r.day).slice(0, 7));
    if (!b) continue;
    b.revenue += Number(r.revenue ?? 0);
    b.expenses += Number(r.expense ?? 0);
  }
  return [...buckets.values()];
}

export async function fetchComplaintsPerWeek(supabase: SupabaseClient, hostelId: string, weeks = 8): Promise<ComplaintsPerWeekRow[]> {
  const { data, error } = await supabase.rpc("rpc_complaints_per_week", { p_hostel_id: hostelId, p_weeks: weeks });
  if (error) throw error;
  return ((data ?? []) as ComplaintsPerWeekRow[]).map((r) => ({ week_start: r.week_start, complaints: Number(r.complaints ?? 0) }));
}

export interface SaOwnerOption {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  status: UserRow["status"];
  /** hostels currently under this owner account */
  hostel_count: number;
}

/**
 * Existing owner accounts (for the SA-2 wizard "Existing owner" mode — Hard rule §4.1:
 * a second hostel + subscription may sit under the same owner account).
 */
export async function fetchOwners(supabase: SupabaseClient): Promise<SaOwnerOption[]> {
  const [{ data: users, error }, { data: hostels, error: hErr }] = await Promise.all([
    supabase
      .from("users")
      .select("id, full_name, email, phone, status")
      .eq("role", "owner")
      .is("deleted_at", null)
      .order("full_name", { ascending: true }),
    supabase.from("hostels").select("owner_user_id"),
  ]);
  if (error) throw error;
  if (hErr) throw hErr;
  const counts = new Map<string, number>();
  for (const h of (hostels ?? []) as { owner_user_id: string }[]) counts.set(h.owner_user_id, (counts.get(h.owner_user_id) ?? 0) + 1);
  return ((users ?? []) as Omit<SaOwnerOption, "hostel_count">[]).map((u) => ({ ...u, hostel_count: counts.get(u.id) ?? 0 }));
}

/** Manager + warden accounts of a hostel (active first). */
export async function fetchHostelStaff(supabase: SupabaseClient, hostelId: string): Promise<UserRow[]> {
  const { data, error } = await supabase
    .from("users")
    .select("*")
    .eq("hostel_id", hostelId)
    .in("role", ["manager", "warden"])
    .is("deleted_at", null)
    .order("status", { ascending: true })
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as UserRow[];
}

/* ───────────────────────── Security console (SA-5) ───────────────────────── */

export interface SecurityAlertRow {
  id: number;
  at: string;
  severity: "low" | "medium" | "high" | "critical";
  kind: string;
  summary: string;
  hostel_id: string | null;
  actor_user_id: string | null;
  ip: string | null;
  details: Record<string, unknown>;
  acknowledged_at: string | null;
  acknowledged_by: string | null;
}

export interface AuditRow {
  id: number;
  at: string;
  actor_user_id: string | null;
  actor_role: string | null;
  action: string;
  target_type: string | null;
  target_id: string | null;
  hostel_id: string | null;
  ip: string | null;
  meta: Record<string, unknown>;
}

/**
 * The audit trail and the alerts it raises had no reader — the data existed but nothing
 * ever surfaced it, which is the difference between "logged" and "monitored".
 * RLS scopes both: Super Admin sees everything, an Owner sees only their own hostel.
 */
export async function fetchSecurityAlerts(
  supabase: SupabaseClient,
  { openOnly = false, limit = 100 }: { openOnly?: boolean; limit?: number } = {},
): Promise<SecurityAlertRow[]> {
  let q = supabase
    .from("security_alerts")
    .select("id,at,severity,kind,summary,hostel_id,actor_user_id,ip,details,acknowledged_at,acknowledged_by")
    .order("at", { ascending: false })
    .limit(limit);
  if (openOnly) q = q.is("acknowledged_at", null);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as SecurityAlertRow[];
}

export async function fetchAuditLog(
  supabase: SupabaseClient,
  { action, limit = 200 }: { action?: string; limit?: number } = {},
): Promise<AuditRow[]> {
  let q = supabase
    .from("audit_log")
    .select("id,at,actor_user_id,actor_role,action,target_type,target_id,hostel_id,ip,meta")
    .order("at", { ascending: false })
    .limit(limit);
  if (action) q = q.like("action", `${action}%`);
  const { data, error } = await q;
  if (error) throw error;
  return (data ?? []) as AuditRow[];
}
