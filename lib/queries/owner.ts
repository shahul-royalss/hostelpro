import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { endOfMonth, parse, startOfMonth, subDays } from "date-fns";
import type {
  AnnouncementRow,
  ComplaintCategory,
  ComplaintEventRow,
  ComplaintStatus,
  DailyFinanceRow,
  ExpenseRow,
  FeeLedgerRow,
  FeeStatus,
  FloorRow,
  HostelStats,
  RevenueRow,
  StudentRow,
  TaskRow,
  UserRow,
} from "@/lib/types";
import { toISODate, toPeriodMonth } from "@/lib/utils";

/**
 * Owner data helpers — every function takes the RLS-enforced server client and
 * the active hostel id (always ctx.hostel.id, never a client-provided value).
 */

/* ───────────────────────── Dashboard (OW-1) ───────────────────────── */

export async function getHostelStats(supabase: SupabaseClient, hostelId: string): Promise<HostelStats | null> {
  const { data } = await supabase.rpc("rpc_hostel_stats", { p_hostel_id: hostelId }).maybeSingle();
  return (data as HostelStats | null) ?? null;
}

export async function getDailyFinance(supabase: SupabaseClient, hostelId: string, from: Date, to: Date): Promise<DailyFinanceRow[]> {
  const { data } = await supabase.rpc("rpc_daily_finance", {
    p_hostel_id: hostelId,
    p_from: toISODate(from),
    p_to: toISODate(to),
  });
  return ((data ?? []) as DailyFinanceRow[]).map((r) => ({ ...r, revenue: Number(r.revenue), expense: Number(r.expense) }));
}

export function getLast30DaysFinance(supabase: SupabaseClient, hostelId: string) {
  const today = new Date();
  return getDailyFinance(supabase, hostelId, subDays(today, 29), today);
}

export async function getLatestAnnouncements(supabase: SupabaseClient, hostelId: string, limit = 4): Promise<AnnouncementRow[]> {
  const { data } = await supabase
    .from("announcements")
    .select("*")
    .eq("hostel_id", hostelId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(limit);
  return (data ?? []) as AnnouncementRow[];
}

/* ───────────────────────── Complaints (OW-2) ───────────────────────── */

export interface ComplaintListItem {
  id: string;
  category: ComplaintCategory;
  title: string;
  description: string | null;
  photo_url: string | null;
  status: ComplaintStatus;
  created_at: string;
  resolved_at: string | null;
  resolution_note: string | null;
  student: {
    id: string;
    full_name: string;
    phone: string;
    room: { room_number: string } | null;
  } | null;
}

const COMPLAINT_SELECT =
  "id, category, title, description, photo_url, status, created_at, resolved_at, resolution_note, student:students(id, full_name, phone, room:rooms(room_number))";

/** Supabase returns to-one joins as objects but the loose client type can't tell — normalise defensively. */
function normalizeComplaint(row: Record<string, unknown>): ComplaintListItem {
  const rawStudent = row.student;
  const s = (Array.isArray(rawStudent) ? rawStudent[0] : rawStudent) as Record<string, unknown> | null | undefined;
  let student: ComplaintListItem["student"] = null;
  if (s) {
    const rawRoom = s.room;
    const room = (Array.isArray(rawRoom) ? rawRoom[0] : rawRoom) as { room_number: string } | null | undefined;
    student = {
      id: String(s.id),
      full_name: String(s.full_name ?? ""),
      phone: String(s.phone ?? ""),
      room: room ? { room_number: String(room.room_number) } : null,
    };
  }
  return {
    id: String(row.id),
    category: row.category as ComplaintCategory,
    title: String(row.title ?? ""),
    description: (row.description as string | null) ?? null,
    photo_url: (row.photo_url as string | null) ?? null,
    status: row.status as ComplaintStatus,
    created_at: String(row.created_at),
    resolved_at: (row.resolved_at as string | null) ?? null,
    resolution_note: (row.resolution_note as string | null) ?? null,
    student,
  };
}

export async function getComplaints(supabase: SupabaseClient, hostelId: string, limit = 300): Promise<ComplaintListItem[]> {
  const { data } = await supabase
    .from("complaints")
    .select(COMPLAINT_SELECT)
    .eq("hostel_id", hostelId)
    .order("created_at", { ascending: false })
    .limit(limit);
  return ((data ?? []) as Record<string, unknown>[]).map(normalizeComplaint);
}

export async function getRecentComplaints(supabase: SupabaseClient, hostelId: string, limit = 4) {
  return getComplaints(supabase, hostelId, limit);
}

export async function getComplaintEvents(supabase: SupabaseClient, complaintId: string): Promise<ComplaintEventRow[]> {
  const { data } = await supabase
    .from("complaint_events")
    .select("*")
    .eq("complaint_id", complaintId)
    .order("created_at", { ascending: true });
  return (data ?? []) as ComplaintEventRow[];
}

/* ───────────────────────── Updates (OW-3) ───────────────────────── */

export async function getAnnouncements(supabase: SupabaseClient, hostelId: string, limit = 100): Promise<AnnouncementRow[]> {
  return getLatestAnnouncements(supabase, hostelId, limit);
}

export interface AudienceCounts {
  manager: number;
  warden: number;
  student: number;
}

/** Active recipients per role — used to compute an announcement's reach. */
export async function getAudienceCounts(supabase: SupabaseClient, hostelId: string): Promise<AudienceCounts> {
  const count = async (role: "manager" | "warden" | "student") => {
    const { count: n } = await supabase
      .from("users")
      .select("id", { count: "exact", head: true })
      .eq("hostel_id", hostelId)
      .eq("role", role)
      .eq("status", "active")
      .is("deleted_at", null);
    return n ?? 0;
  };
  const [manager, warden, student] = await Promise.all([count("manager"), count("warden"), count("student")]);
  return { manager, warden, student };
}

export function reachFor(audience: AnnouncementRow["audience"], counts: AudienceCounts): number {
  switch (audience) {
    case "manager":
      return counts.manager;
    case "warden":
      return counts.warden;
    case "students":
      return counts.student;
    default:
      return counts.manager + counts.warden + counts.student;
  }
}

/* ───────────────────────── Staff & tasks (OW-4) ───────────────────────── */

export type StaffUser = Pick<UserRow, "id" | "role" | "full_name" | "email" | "phone" | "status" | "created_at" | "updated_at">;

/** Manager + warden accounts of the hostel (active first, newest first). */
export async function getStaff(supabase: SupabaseClient, hostelId: string): Promise<StaffUser[]> {
  const { data } = await supabase
    .from("users")
    .select("id, role, full_name, email, phone, status, created_at, updated_at")
    .eq("hostel_id", hostelId)
    .in("role", ["manager", "warden"])
    .is("deleted_at", null)
    .order("status", { ascending: true }) // 'active' < 'inactive'
    .order("created_at", { ascending: false });
  return (data ?? []) as StaffUser[];
}

export async function getActiveManager(supabase: SupabaseClient, hostelId: string): Promise<StaffUser | null> {
  const { data } = await supabase
    .from("users")
    .select("id, role, full_name, email, phone, status, created_at, updated_at")
    .eq("hostel_id", hostelId)
    .eq("role", "manager")
    .eq("status", "active")
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle();
  return (data as StaffUser | null) ?? null;
}

export async function getTasks(supabase: SupabaseClient, hostelId: string): Promise<TaskRow[]> {
  const { data } = await supabase
    .from("tasks")
    .select("*")
    .eq("hostel_id", hostelId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false });
  return (data ?? []) as TaskRow[];
}

/* ───────────────────────── Students (OW-5) ───────────────────────── */

export interface StudentDirectoryRow extends StudentRow {
  room_number: string | null;
  floor_number: number | null;
  fee_status: FeeStatus;
  amount_due: number;
  amount_paid: number;
}

function firstOf<T>(v: T | T[] | null | undefined): T | null {
  if (!v) return null;
  return Array.isArray(v) ? (v[0] ?? null) : v;
}

export async function getStudentsDirectory(supabase: SupabaseClient, hostelId: string): Promise<{ students: StudentDirectoryRow[]; floors: FloorRow[] }> {
  const period = toPeriodMonth();
  const [{ data: rows }, { data: floors }, { data: ledger }] = await Promise.all([
    supabase
      .from("students")
      .select("*, room:rooms(room_number, floor:floors(floor_number))")
      .eq("hostel_id", hostelId)
      .neq("status", "vacated")
      .is("deleted_at", null)
      .order("full_name", { ascending: true }),
    supabase.from("floors").select("id, hostel_id, floor_number").eq("hostel_id", hostelId).order("floor_number"),
    supabase.rpc("rpc_fee_ledger", { p_hostel_id: hostelId, p_period_month: period }),
  ]);

  const feeById = new Map<string, FeeLedgerRow>();
  for (const l of (ledger ?? []) as FeeLedgerRow[]) feeById.set(l.student_id, l);

  const students = ((rows ?? []) as Array<StudentRow & { room?: unknown }>).map((r) => {
    const room = firstOf(r.room as { room_number: string; floor: unknown } | { room_number: string; floor: unknown }[] | null);
    const floor = room ? firstOf(room.floor as { floor_number: number } | { floor_number: number }[] | null) : null;
    const fee = feeById.get(r.id);
    const { room: _room, ...student } = r;
    void _room;
    return {
      ...(student as StudentRow),
      monthly_fee: Number(student.monthly_fee),
      room_number: room?.room_number ?? null,
      floor_number: floor?.floor_number ?? null,
      fee_status: fee?.status ?? "unpaid",
      amount_due: Number(fee?.amount_due ?? student.monthly_fee ?? 0),
      amount_paid: Number(fee?.amount_paid ?? 0),
    } satisfies StudentDirectoryRow;
  });

  return { students, floors: (floors ?? []) as FloorRow[] };
}

export async function getStudentById(supabase: SupabaseClient, hostelId: string, studentId: string): Promise<StudentDirectoryRow | null> {
  const [{ data: row }, { data: ledger }] = await Promise.all([
    supabase
      .from("students")
      .select("*, room:rooms(room_number, floor:floors(floor_number))")
      .eq("hostel_id", hostelId)
      .eq("id", studentId)
      .maybeSingle(),
    supabase.rpc("rpc_fee_ledger", { p_hostel_id: hostelId, p_period_month: toPeriodMonth() }),
  ]);
  if (!row) return null;
  const r = row as StudentRow & { room?: unknown };
  const room = firstOf(r.room as { room_number: string; floor: unknown } | null);
  const floor = room ? firstOf(room.floor as { floor_number: number } | null) : null;
  const fee = ((ledger ?? []) as FeeLedgerRow[]).find((l) => l.student_id === studentId);
  const { room: _room, ...student } = r;
  void _room;
  return {
    ...(student as StudentRow),
    monthly_fee: Number(student.monthly_fee),
    room_number: room?.room_number ?? null,
    floor_number: floor?.floor_number ?? null,
    fee_status: fee?.status ?? "unpaid",
    amount_due: Number(fee?.amount_due ?? student.monthly_fee ?? 0),
    amount_paid: Number(fee?.amount_paid ?? 0),
  };
}

/* ───────────────────────── Finance (OW-6) ───────────────────────── */

export interface FinanceEntry {
  id: string;
  kind: "expense" | "revenue";
  date: string;
  created_at: string;
  label: string; // category or source
  amount: number;
  note: string | null;
  recorded_by: string | null;
}

export interface MonthFinance {
  period: string;
  expenses: ExpenseRow[];
  revenues: RevenueRow[];
  daily: DailyFinanceRow[];
  entries: FinanceEntry[];
  totalRevenue: number;
  totalExpense: number;
}

export async function getMonthFinance(supabase: SupabaseClient, hostelId: string, period: string): Promise<MonthFinance> {
  const start = startOfMonth(parse(`${period}-01`, "yyyy-MM-dd", new Date()));
  const end = endOfMonth(start);
  const from = toISODate(start);
  const to = toISODate(end);

  const [{ data: exp }, { data: rev }, daily] = await Promise.all([
    supabase.from("expenses").select("*").eq("hostel_id", hostelId).is("deleted_at", null).gte("date", from).lte("date", to).order("date", { ascending: false }).order("created_at", { ascending: false }),
    supabase.from("revenues").select("*").eq("hostel_id", hostelId).is("deleted_at", null).gte("date", from).lte("date", to).order("date", { ascending: false }).order("created_at", { ascending: false }),
    getDailyFinance(supabase, hostelId, start, end),
  ]);

  const expenses = ((exp ?? []) as ExpenseRow[]).map((e) => ({ ...e, amount: Number(e.amount) }));
  const revenues = ((rev ?? []) as RevenueRow[]).map((r) => ({ ...r, amount: Number(r.amount) }));

  // Resolve "recorded by" names with a second query (robust against FK-hint naming).
  const userIds = Array.from(new Set([...expenses, ...revenues].map((r) => r.uploaded_by).filter((v): v is string => !!v)));
  const names = new Map<string, string>();
  if (userIds.length) {
    const { data: users } = await supabase.from("users").select("id, full_name").in("id", userIds);
    for (const u of (users ?? []) as Pick<UserRow, "id" | "full_name">[]) names.set(u.id, u.full_name);
  }

  const entries: FinanceEntry[] = [
    ...expenses.map<FinanceEntry>((e) => ({
      id: e.id, kind: "expense", date: e.date, created_at: e.created_at, label: e.category, amount: e.amount, note: e.note,
      recorded_by: e.uploaded_by ? names.get(e.uploaded_by) ?? null : null,
    })),
    ...revenues.map<FinanceEntry>((r) => ({
      id: r.id, kind: "revenue", date: r.date, created_at: r.created_at, label: r.source, amount: r.amount, note: r.note,
      recorded_by: r.uploaded_by ? names.get(r.uploaded_by) ?? null : null,
    })),
  ].sort((a, b) => (a.date === b.date ? b.created_at.localeCompare(a.created_at) : b.date.localeCompare(a.date)));

  return {
    period,
    expenses,
    revenues,
    daily,
    entries,
    totalRevenue: revenues.reduce((s, r) => s + r.amount, 0),
    totalExpense: expenses.reduce((s, e) => s + e.amount, 0),
  };
}
