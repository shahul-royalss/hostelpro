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
  FeeStatus,
  FloorRow,
  HostelStats,
  RevenueRow,
  StudentRow,
  TaskRow,
  UserRow,
} from "@/lib/types";
import { signedUrl } from "@/lib/storage";
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

export type ComplaintFilter = "all" | ComplaintStatus;
export const COMPLAINT_PAGE_SIZE = 50;
/** Upper bound on the student ids a search resolves to — they travel in a `student_id.in.(…)` filter. */
const STUDENT_ID_CAP = 200;

export interface ComplaintsInboxParams {
  status?: ComplaintFilter;
  /** search: title / description / category / student name / phone / room number */
  q?: string;
  page?: number;
  pageSize?: number;
}

export interface ComplaintsInboxResult {
  complaints: ComplaintListItem[];
  /** rows matching the current status filter + search */
  total: number;
  page: number;
  pageSize: number;
  /** true hostel-wide counts (independent of search / paging) */
  counts: { all: number; open: number; in_progress: number; resolved: number };
}

/**
 * Inbox listing (OW-2) — status filter, search and paging all run in Postgres so the header,
 * filter pills and results are correct beyond any client-side cap.
 */
export async function getComplaintsInbox(supabase: SupabaseClient, hostelId: string, params: ComplaintsInboxParams = {}): Promise<ComplaintsInboxResult> {
  const status: ComplaintFilter = params.status && ["all", "open", "in_progress", "resolved"].includes(params.status) ? params.status : "all";
  const q = sanitizeSearch(params.q);
  const pageSize = Math.min(Math.max(1, params.pageSize ?? COMPLAINT_PAGE_SIZE), 200);
  const requestedPage = Math.max(1, params.page ?? 1);

  const countFor = (s: ComplaintStatus | null) => {
    let query = supabase.from("complaints").select("id", { count: "exact", head: true }).eq("hostel_id", hostelId);
    if (s) query = query.eq("status", s);
    return query;
  };
  // The four pill counts are hostel-wide — they ignore the status filter, the search and paging —
  // so they never need to wait for the student-id lookup below. Start them now and join later.
  const countsPromise = Promise.all([countFor(null), countFor("open"), countFor("in_progress"), countFor("resolved")]);

  // Search terms that hit the embedded student (name / phone / room) are resolved to student ids first.
  // Name/phone and room-number matches are independent, so both run in one round trip instead of
  // resolving room ids and then feeding them into a second students query. The room half joins
  // `rooms` inline rather than pre-fetching ids, which also drops the old 50-room ceiling.
  const studentIds: string[] = [];
  if (q) {
    const [{ data: byNameOrPhone }, { data: byRoom }] = await Promise.all([
      supabase.from("students").select("id").eq("hostel_id", hostelId).or(`full_name.ilike.%${q}%,phone.ilike.%${q}%`).limit(STUDENT_ID_CAP),
      supabase.from("students").select("id, rooms!inner(room_number)").eq("hostel_id", hostelId).ilike("rooms.room_number", `%${q}%`).limit(STUDENT_ID_CAP),
    ]);
    // One combined list, name/phone matches first, capped exactly as the single query was: these ids
    // go into a `student_id.in.(…)` filter and the request URL has to stay a sane length.
    const seen = new Set<string>();
    for (const s of [...((byNameOrPhone ?? []) as { id: string }[]), ...((byRoom ?? []) as { id: string }[])]) {
      if (seen.has(s.id)) continue;
      seen.add(s.id);
      studentIds.push(s.id);
      if (studentIds.length >= STUDENT_ID_CAP) break;
    }
  }

  const build = (head = false) => {
    let query = supabase.from("complaints").select(COMPLAINT_SELECT, { count: "exact", head }).eq("hostel_id", hostelId);
    if (status !== "all") query = query.eq("status", status);
    if (q) {
      const parts = [`title.ilike.%${q}%`, `description.ilike.%${q}%`];
      const cat = q.toLowerCase().replace(/\s+/g, "");
      if (["food", "cleaning", "maintenance", "wifi", "roommate", "other"].includes(cat)) parts.push(`category.eq.${cat}`);
      if (studentIds.length) parts.push(`student_id.in.(${studentIds.join(",")})`);
      query = query.or(parts.join(","));
    }
    return query.order("created_at", { ascending: false }).order("id", { ascending: true });
  };

  const from = (requestedPage - 1) * pageSize;
  const [pageRes, [{ count: all }, { count: open }, { count: inProgress }, { count: resolved }]] = await Promise.all([
    build().range(from, from + pageSize - 1),
    countsPromise,
  ]);

  let rows = pageRes.data;
  let total = pageRes.count ?? 0;
  // 416 from PostgREST when ?page= is past the end → recover the total, clamp, refetch.
  if (pageRes.error || pageRes.count == null) total = (await build(true)).count ?? 0;
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  let page = requestedPage;
  if (page > totalPages) {
    page = totalPages;
    const start = (page - 1) * pageSize;
    rows = (await build().range(start, start + pageSize - 1)).data;
  }

  return {
    complaints: ((rows ?? []) as Record<string, unknown>[]).map(normalizeComplaint),
    total,
    page,
    pageSize,
    counts: { all: all ?? 0, open: open ?? 0, in_progress: inProgress ?? 0, resolved: resolved ?? 0 },
  };
}

/** One complaint by id (for ?id= deep links that fall outside the current page/filter). */
export async function getComplaintById(supabase: SupabaseClient, hostelId: string, complaintId: string): Promise<ComplaintListItem | null> {
  const { data } = await supabase.from("complaints").select(COMPLAINT_SELECT).eq("hostel_id", hostelId).eq("id", complaintId).maybeSingle();
  return data ? normalizeComplaint(data as Record<string, unknown>) : null;
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

/** Full student profile (slide-over / detail page). Loaded one at a time — never in bulk. */
export interface StudentProfileRow extends StudentRow {
  room_number: string | null;
  floor_number: number | null;
  fee_status: FeeStatus;
  amount_due: number;
  amount_paid: number;
}

/** Directory list row — list columns only (no guardian / address / ID-proof PII). */
export interface StudentListRow {
  id: string;
  full_name: string;
  phone: string;
  email: string | null;
  /** short-lived signed URL (or null) — resolved server-side for the visible page only */
  photo_signed_url: string | null;
  date_of_joining: string;
  monthly_fee: number;
  status: StudentRow["status"];
  room_number: string | null;
  floor_number: number | null;
  fee_status: FeeStatus;
  amount_due: number;
  amount_paid: number;
}

export type StudentFeeFilter = "all" | FeeStatus;

export interface StudentsDirectoryParams {
  /** free-text search: name / phone / email / room number */
  q?: string;
  /** floor_number filter (null = all floors) */
  floor?: number | null;
  fee?: StudentFeeFilter;
  page?: number;
  pageSize?: number;
}

export interface StudentsDirectoryResult {
  students: StudentListRow[];
  /** total rows matching the current search + filters (for pagination) */
  total: number;
  page: number;
  pageSize: number;
  floors: FloorRow[];
  /** hostel-wide fee counts for the period (independent of search/filters) */
  counts: { all: number; paid: number; partial: number; unpaid: number };
  period: string;
}

export const STUDENT_PAGE_SIZE = 20;
const STUDENT_MAX_PAGE_SIZE = 100;

const STUDENT_LIST_COLUMNS = "id, full_name, phone, email, photo_url, date_of_joining, monthly_fee, status, room_id";
const FEE_EMBED_COLUMNS = "status, amount_due, amount_paid";

type FeeEmbed = { status: FeeStatus; amount_due: number | string; amount_paid: number | string };
type RoomEmbed = { room_number: string; floor: { floor_number: number } | { floor_number: number }[] | null };

function firstOf<T>(v: T | T[] | null | undefined): T | null {
  if (!v) return null;
  return Array.isArray(v) ? (v[0] ?? null) : v;
}

/** Strip PostgREST filter syntax characters from a user search term. */
function sanitizeSearch(q: string | undefined): string {
  return (q ?? "").replace(/[,()"'\\%*]/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
}

/**
 * Paginated, server-filtered students directory. Search / floor / fee filters and paging all run in
 * Postgres (`.ilike()` / embedded filters / `.range()`), so only one page of list columns reaches the client.
 * Fee status for the period comes from a left join on fee_payments (same semantics as rpc_fee_ledger:
 * no row → unpaid, amount_due = monthly_fee).
 */
export async function getStudentsDirectory(supabase: SupabaseClient, hostelId: string, params: StudentsDirectoryParams = {}): Promise<StudentsDirectoryResult> {
  const period = toPeriodMonth();
  const q = sanitizeSearch(params.q);
  const floor = Number.isInteger(params.floor) ? (params.floor as number) : null;
  const fee: StudentFeeFilter = params.fee && ["all", "paid", "partial", "unpaid"].includes(params.fee) ? params.fee : "all";
  const pageSize = Math.min(Math.max(1, params.pageSize ?? STUDENT_PAGE_SIZE), STUDENT_MAX_PAGE_SIZE);
  const requestedPage = Math.max(1, params.page ?? 1);

  const activeBase = () => supabase.from("students").select("id", { count: "exact", head: true }).eq("hostel_id", hostelId).neq("status", "vacated").is("deleted_at", null);
  const feeCount = (status: "paid" | "partial") =>
    supabase
      .from("students")
      .select("id, fee:fee_payments!inner(status)", { count: "exact", head: true })
      .eq("hostel_id", hostelId)
      .neq("status", "vacated")
      .is("deleted_at", null)
      .eq("fee.period_month", period)
      .eq("fee.status", status);
  // The floor list and the three fee counts are hostel-wide — independent of the search, the
  // filters and paging — so they never need to wait for the room-id lookup below.
  const sidecarPromise = Promise.all([
    supabase.from("floors").select("id, hostel_id, floor_number").eq("hostel_id", hostelId).order("floor_number"),
    activeBase(),
    feeCount("paid"),
    feeCount("partial"),
  ]);

  // Search across the embedded room number: resolve matching room ids first (rooms are few; students are many).
  let roomIds: string[] = [];
  if (q) {
    const { data: rooms } = await supabase.from("rooms").select("id").eq("hostel_id", hostelId).ilike("room_number", `%${q}%`).limit(50);
    roomIds = ((rooms ?? []) as { id: string }[]).map((r) => r.id);
  }

  const buildBase = (head = false) => {
    // !inner on rooms/floors only when filtering by floor, so unassigned students still list otherwise.
    const roomEmbed = floor != null ? "room:rooms!inner(room_number, floor:floors!inner(floor_number))" : "room:rooms(room_number, floor:floors(floor_number))";
    const feeEmbed = fee === "paid" || fee === "partial" ? `fee:fee_payments!inner(${FEE_EMBED_COLUMNS})` : `fee:fee_payments!left(${FEE_EMBED_COLUMNS})`;
    let query = supabase
      .from("students")
      .select(`${STUDENT_LIST_COLUMNS}, ${roomEmbed}, ${feeEmbed}`, { count: "exact", head })
      .eq("hostel_id", hostelId)
      .neq("status", "vacated")
      .is("deleted_at", null)
      .eq("fee.period_month", period);
    if (fee === "paid" || fee === "partial") {
      query = query.eq("fee.status", fee);
    } else if (fee === "unpaid") {
      // unpaid = no paid/partial row for the period (covers "no row" and stored status='unpaid')
      query = query.in("fee.status", ["paid", "partial"]).is("fee", null);
    }
    if (floor != null) query = query.eq("room.floor.floor_number", floor);
    if (q) {
      const parts = [`full_name.ilike.%${q}%`, `phone.ilike.%${q}%`, `email.ilike.%${q}%`];
      if (roomIds.length) parts.push(`room_id.in.(${roomIds.join(",")})`);
      query = query.or(parts.join(","));
    }
    return query;
  };

  const from = (requestedPage - 1) * pageSize;
  const [pageRes, [{ data: floors }, { count: allCount }, { count: paidCount }, { count: partialCount }]] = await Promise.all([
    buildBase().order("full_name", { ascending: true }).order("id", { ascending: true }).range(from, from + pageSize - 1),
    sidecarPromise,
  ]);

  let rows = pageRes.data;
  let total = pageRes.count ?? 0;
  // PostgREST answers 416 (no data, no count) when the offset is past the last row — e.g. a stale ?page= after a
  // filter change. Recover the true total with a head count, clamp to the last page and refetch.
  if (pageRes.error || pageRes.count == null) {
    total = (await buildBase(true)).count ?? 0;
  }
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  let page = requestedPage;
  if (page > totalPages) {
    page = totalPages;
    const start = (page - 1) * pageSize;
    const res = await buildBase().order("full_name", { ascending: true }).order("id", { ascending: true }).range(start, start + pageSize - 1);
    rows = res.data;
  }

  type Raw = Pick<StudentRow, "id" | "full_name" | "phone" | "email" | "photo_url" | "date_of_joining" | "monthly_fee" | "status" | "room_id"> & {
    room?: RoomEmbed | RoomEmbed[] | null;
    fee?: FeeEmbed | FeeEmbed[] | null;
  };
  const raw = (rows ?? []) as Raw[];

  // Signed photo URLs for just this page (private bucket, DECISIONS #15).
  const photoUrls = await Promise.all(raw.map((r) => signedUrl("student-docs", r.photo_url, hostelId)));

  const students: StudentListRow[] = raw.map((r, i) => {
    const room = firstOf(r.room);
    const floorRow = room ? firstOf(room.floor) : null;
    const f = firstOf(r.fee);
    const monthlyFee = Number(r.monthly_fee);
    return {
      id: r.id,
      full_name: r.full_name,
      phone: r.phone,
      email: r.email,
      photo_signed_url: photoUrls[i] ?? null,
      date_of_joining: r.date_of_joining,
      monthly_fee: monthlyFee,
      status: r.status,
      room_number: room?.room_number ?? null,
      floor_number: floorRow?.floor_number ?? null,
      fee_status: f?.status ?? "unpaid",
      amount_due: Number(f?.amount_due ?? monthlyFee),
      amount_paid: Number(f?.amount_paid ?? 0),
    };
  });

  const all = allCount ?? 0;
  const paid = paidCount ?? 0;
  const partial = partialCount ?? 0;

  return {
    students,
    total,
    page,
    pageSize,
    floors: (floors ?? []) as FloorRow[],
    counts: { all, paid, partial, unpaid: Math.max(all - paid - partial, 0) },
    period,
  };
}

/** One student's full profile (excludes soft-deleted rows; vacated students render with a neutral fee tile). */
export async function getStudentById(supabase: SupabaseClient, hostelId: string, studentId: string): Promise<StudentProfileRow | null> {
  const period = toPeriodMonth();
  const [{ data: row }, { data: fee }] = await Promise.all([
    supabase
      .from("students")
      .select("*, room:rooms(room_number, floor:floors(floor_number))")
      .eq("hostel_id", hostelId)
      .eq("id", studentId)
      .is("deleted_at", null)
      .maybeSingle(),
    supabase.from("fee_payments").select(FEE_EMBED_COLUMNS).eq("hostel_id", hostelId).eq("student_id", studentId).eq("period_month", period).maybeSingle(),
  ]);
  if (!row) return null;
  const r = row as StudentRow & { room?: RoomEmbed | RoomEmbed[] | null };
  const room = firstOf(r.room);
  const floor = room ? firstOf(room.floor) : null;
  const f = (fee ?? null) as FeeEmbed | null;
  const { room: _room, ...student } = r;
  void _room;
  const monthlyFee = Number(student.monthly_fee);
  const vacated = student.status === "vacated";
  return {
    ...(student as StudentRow),
    monthly_fee: monthlyFee,
    room_number: room?.room_number ?? null,
    floor_number: floor?.floor_number ?? null,
    // Vacated students are outside the fee ledger — nothing is due.
    fee_status: vacated ? "paid" : f?.status ?? "unpaid",
    amount_due: vacated ? 0 : Number(f?.amount_due ?? monthlyFee),
    amount_paid: Number(f?.amount_paid ?? 0),
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

  // The uploader's name rides along as a to-one embed instead of a follow-up `.in("id", userIds)`
  // lookup, so "recorded by" costs no second round trip. `uploaded_by` is the only FK from either
  // table to users, so the relationship resolves without an FK hint (no constraint name to drift).
  // The embed is still read through RLS on `users` exactly as the separate query was: a row the
  // caller may not read comes back null, and `recorded_by` is null — the same value as before.
  const RECORDER = "recorder:users(full_name)";
  const [{ data: exp }, { data: rev }, daily] = await Promise.all([
    supabase.from("expenses").select(`*, ${RECORDER}`).eq("hostel_id", hostelId).is("deleted_at", null).gte("date", from).lte("date", to).order("date", { ascending: false }).order("created_at", { ascending: false }),
    supabase.from("revenues").select(`*, ${RECORDER}`).eq("hostel_id", hostelId).is("deleted_at", null).gte("date", from).lte("date", to).order("date", { ascending: false }).order("created_at", { ascending: false }),
    getDailyFinance(supabase, hostelId, start, end),
  ]);

  // Lift the embedded name out by row id and drop it from the row: `expenses` / `revenues` are
  // returned to the page as ExpenseRow / RevenueRow and must not grow an extra property.
  type Recorder = Pick<UserRow, "full_name"> | Pick<UserRow, "full_name">[] | null;
  const names = new Map<string, string | null>();
  const expenses: ExpenseRow[] = ((exp ?? []) as (ExpenseRow & { recorder?: Recorder })[]).map(({ recorder, ...e }) => {
    names.set(e.id, firstOf(recorder)?.full_name ?? null);
    return { ...e, amount: Number(e.amount) };
  });
  const revenues: RevenueRow[] = ((rev ?? []) as (RevenueRow & { recorder?: Recorder })[]).map(({ recorder, ...r }) => {
    names.set(r.id, firstOf(recorder)?.full_name ?? null);
    return { ...r, amount: Number(r.amount) };
  });

  const entries: FinanceEntry[] = [
    ...expenses.map<FinanceEntry>((e) => ({
      id: e.id, kind: "expense", date: e.date, created_at: e.created_at, label: e.category, amount: e.amount, note: e.note,
      recorded_by: names.get(e.id) ?? null,
    })),
    ...revenues.map<FinanceEntry>((r) => ({
      id: r.id, kind: "revenue", date: r.date, created_at: r.created_at, label: r.source, amount: r.amount, note: r.note,
      recorded_by: names.get(r.id) ?? null,
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
