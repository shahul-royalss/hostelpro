import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  AnnouncementRow,
  ComplaintEventRow,
  ComplaintRow,
  FeeLedgerRow,
  FeeStatus,
  FloorRow,
  HostelStats,
  LeaveRow,
  RoomOccupancyRow,
  RoomRow,
  StudentRow,
  VisitorRow,
} from "@/lib/types";
import { toPeriodMonth } from "@/lib/utils";

/**
 * Warden read helpers. All take the RLS-enforced server client + hostelId
 * (always ctx.hostel.id — never a client-provided value).
 */

type Db = SupabaseClient;

/**
 * PostgREST caps a single response at 1000 rows (Supabase `db-max-rows`), so
 * hostel-wide reads (10,000 students) page through with `.range()` until a
 * short page comes back. `build` must return a fresh builder each call.
 */
const PAGE = 1000;
export async function fetchAllRows<T>(build: (from: number, to: number) => PromiseLike<{ data: unknown; error: unknown }>): Promise<T[]> {
  const out: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data } = await build(from, from + PAGE - 1);
    const rows = (data ?? []) as T[];
    out.push(...rows);
    if (rows.length < PAGE) break;
  }
  return out;
}

/** Hostel timezone (v1: every hostel is in India). Used for "today" boundaries. */
export const HOSTEL_TIME_ZONE = "Asia/Kolkata";

/**
 * Start of the current calendar day in the hostel timezone, as an ISO string
 * (independent of the Node process's local timezone).
 */
export function hostelDayStart(now = new Date(), daysAgo = 0, timeZone = HOSTEL_TIME_ZONE): Date {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(now);
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
  // Midnight of that civil date in the zone: use the zone's UTC offset at `now`.
  const utcMidnight = Date.UTC(get("year"), get("month") - 1, get("day") - daysAgo);
  const offsetMs = zoneOffsetMs(now, timeZone);
  return new Date(utcMidnight - offsetMs);
}

function zoneOffsetMs(at: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(at);
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value);
  const asUTC = Date.UTC(get("year"), get("month") - 1, get("day"), get("hour"), get("minute"), get("second"));
  return asUTC - Math.floor(at.getTime() / 1000) * 1000;
}

/* ───────────────────────── home ───────────────────────── */

export async function getHostelStats(db: Db, hostelId: string, period = toPeriodMonth()): Promise<HostelStats | null> {
  const { data } = await db.rpc("rpc_hostel_stats", { p_hostel_id: hostelId, p_period_month: period }).maybeSingle();
  return (data as HostelStats | null) ?? null;
}

export async function getAnnouncements(db: Db, hostelId: string, limit = 5): Promise<AnnouncementRow[]> {
  const { data } = await db
    .from("announcements")
    .select("*")
    .eq("hostel_id", hostelId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(limit);
  return (data ?? []) as AnnouncementRow[];
}

/* ───────────────────────── rooms & beds ───────────────────────── */

export async function getFloors(db: Db, hostelId: string): Promise<FloorRow[]> {
  const { data } = await db.from("floors").select("id, hostel_id, floor_number").eq("hostel_id", hostelId).order("floor_number");
  return (data ?? []) as FloorRow[];
}

export async function getRoomOccupancy(db: Db, hostelId: string): Promise<RoomOccupancyRow[]> {
  return fetchAllRows<RoomOccupancyRow>((from, to) => db.rpc("rpc_room_occupancy", { p_hostel_id: hostelId }).range(from, to));
}

export interface FreeBed {
  bed_id: string;
  bed_number: number;
  room_id: string;
  room_number: string;
  floor_number: number;
}

/**
 * Free beds — for one room (`roomId`, register form step 4) or the whole
 * hostel (reassign sheet; paged past the 1000-row cap).
 */
export async function getFreeBeds(db: Db, hostelId: string, roomId?: string): Promise<FreeBed[]> {
  type Raw = {
    id: string;
    bed_number: number;
    room_id: string;
    rooms: { room_number: string; floors: { floor_number: number } | { floor_number: number }[] } | null;
  };
  const rows = await fetchAllRows<Raw>((from, to) => {
    let q = db
      .from("beds")
      .select("id, bed_number, room_id, rooms!inner(room_number, floors!inner(floor_number))")
      .eq("hostel_id", hostelId)
      .is("student_id", null);
    if (roomId) q = q.eq("room_id", roomId);
    return q.order("id").range(from, to);
  });
  return rows
    .map((b) => {
      const floors = b.rooms?.floors;
      const floor = Array.isArray(floors) ? floors[0] : floors;
      return {
        bed_id: b.id,
        bed_number: b.bed_number,
        room_id: b.room_id,
        room_number: b.rooms?.room_number ?? "—",
        floor_number: floor?.floor_number ?? 0,
      };
    })
    .sort((a, b) => a.floor_number - b.floor_number || a.room_number.localeCompare(b.room_number, undefined, { numeric: true }) || a.bed_number - b.bed_number);
}

export interface RoomDetail {
  room: RoomRow & { floor_number: number };
  beds: {
    id: string;
    bed_number: number;
    student: (Pick<StudentRow, "id" | "full_name" | "phone" | "photo_url" | "date_of_joining" | "monthly_fee" | "status"> & {
      fee_status: FeeStatus;
      amount_due: number;
      amount_paid: number;
    }) | null;
  }[];
}

export async function getRoomDetail(db: Db, hostelId: string, roomId: string, period = toPeriodMonth()): Promise<RoomDetail | null> {
  type FeeEmbed = { status: FeeStatus; amount_due: number | string; amount_paid: number | string };
  type S = Pick<StudentRow, "id" | "full_name" | "phone" | "photo_url" | "date_of_joining" | "monthly_fee" | "status" | "bed_id"> & {
    fee?: FeeEmbed | FeeEmbed[] | null;
  };

  // The room row, its beds and its occupants are three independent reads — one round trip, not
  // three. The period's fee row rides along on the students query as a left embed (fee_payments
  // is unique per student+period), replacing the `.in(studentIds)` follow-up. Still only this
  // room's occupants (≤ capacity rows) — never the whole hostel's ledger.
  // The beds read no longer waits on the room lookup to prove the tenant, so it carries its own
  // hostel_id filter (beds.hostel_id is denormalised for exactly this) on top of RLS.
  const [{ data: room }, { data: beds }, { data: students }] = await Promise.all([
    db.from("rooms").select("*, floors!inner(floor_number)").eq("hostel_id", hostelId).eq("id", roomId).maybeSingle(),
    db.from("beds").select("id, bed_number, student_id").eq("hostel_id", hostelId).eq("room_id", roomId).order("bed_number"),
    db
      .from("students")
      .select("id, full_name, phone, photo_url, date_of_joining, monthly_fee, status, bed_id, fee:fee_payments!left(status, amount_due, amount_paid)")
      .eq("hostel_id", hostelId)
      .eq("room_id", roomId)
      .neq("status", "vacated")
      .eq("fee.hostel_id", hostelId)
      .eq("fee.period_month", period),
  ]);
  if (!room) return null;
  const r = room as unknown as RoomRow & { floors: { floor_number: number } | { floor_number: number }[] };
  const floor = Array.isArray(r.floors) ? r.floors[0] : r.floors;

  const byBed = new Map<string, S>();
  for (const s of (students ?? []) as S[]) {
    if (s.bed_id) byBed.set(s.bed_id, s);
  }

  return {
    room: { ...r, floor_number: floor?.floor_number ?? 0 },
    beds: ((beds ?? []) as { id: string; bed_number: number; student_id: string | null }[]).map((b) => {
      const s = byBed.get(b.id);
      if (!s) return { id: b.id, bed_number: b.bed_number, student: null };
      const f = (Array.isArray(s.fee) ? s.fee[0] : s.fee) ?? null;
      return {
        id: b.id,
        bed_number: b.bed_number,
        student: {
          id: s.id,
          full_name: s.full_name,
          phone: s.phone,
          photo_url: s.photo_url,
          date_of_joining: s.date_of_joining,
          monthly_fee: Number(s.monthly_fee),
          status: s.status,
          fee_status: f?.status ?? "unpaid",
          amount_due: Number(f?.amount_due ?? s.monthly_fee),
          amount_paid: Number(f?.amount_paid ?? 0),
        },
      };
    }),
  };
}

/* ───────────────────────── fees ───────────────────────── */

export async function getFeeLedger(db: Db, hostelId: string, period: string): Promise<FeeLedgerRow[]> {
  const rows = await fetchAllRows<FeeLedgerRow>((from, to) => db.rpc("rpc_fee_ledger", { p_hostel_id: hostelId, p_period_month: period }).range(from, to));
  return rows.map((r) => ({
    ...r,
    monthly_fee: Number(r.monthly_fee),
    amount_due: Number(r.amount_due),
    amount_paid: Number(r.amount_paid),
  }));
}

/* ───────────────────────── leaves & visitors ───────────────────────── */

export type LeaveWithStudent = LeaveRow & {
  student: { id: string; full_name: string; phone: string; photo_url: string | null; room_number: string | null } | null;
};

/**
 * Leaves for the hostel. `status: "pending"` returns every open request
 * (paged, no cap — a pending request must never fall off the list);
 * `status: "decided"` returns the most recent `limit` approved/rejected rows.
 */
export async function getLeaves(db: Db, hostelId: string, opts: { status?: "pending" | "decided" | "all"; limit?: number } = {}): Promise<LeaveWithStudent[]> {
  const { status = "all", limit = 60 } = opts;
  type Raw = LeaveRow & {
    students: { id: string; full_name: string; phone: string; photo_url: string | null; rooms: { room_number: string } | { room_number: string }[] | null } | null;
  };
  const base = () => {
    let q = db.from("leaves").select("*, students!inner(id, full_name, phone, photo_url, rooms(room_number))").eq("hostel_id", hostelId);
    if (status === "pending") q = q.eq("status", "pending");
    if (status === "decided") q = q.neq("status", "pending");
    return q.order("created_at", { ascending: false });
  };
  const rows: Raw[] =
    status === "pending"
      ? await fetchAllRows<Raw>((from, to) => base().range(from, to))
      : (((await base().limit(limit)).data ?? []) as unknown as Raw[]);
  return rows.map(({ students, ...l }) => {
    const rooms = students?.rooms;
    const room = Array.isArray(rooms) ? rooms[0] : rooms;
    return {
      ...l,
      student: students
        ? { id: students.id, full_name: students.full_name, phone: students.phone, photo_url: students.photo_url, room_number: room?.room_number ?? null }
        : null,
    };
  });
}

export type VisitorWithStudent = VisitorRow & {
  student: { id: string; full_name: string; room_number: string | null } | null;
};

/**
 * Visitors since `sinceISO` (most recent first, capped at `limit`) **plus every
 * visitor still inside** regardless of check-in date, so an un-checked-out visit
 * older than the window can still be checked out. De-duplicated by id.
 */
export async function getVisitors(db: Db, hostelId: string, sinceISO: string, limit = 200): Promise<VisitorWithStudent[]> {
  type Raw = VisitorRow & { students: { id: string; full_name: string; rooms: { room_number: string } | { room_number: string }[] | null } | null };
  const select = () => db.from("visitors").select("*, students!inner(id, full_name, rooms(room_number))").eq("hostel_id", hostelId);
  const [{ data: recent }, open] = await Promise.all([
    select().gte("check_in_at", sinceISO).order("check_in_at", { ascending: false }).limit(limit),
    fetchAllRows<Raw>((from, to) => select().is("check_out_at", null).order("check_in_at", { ascending: false }).range(from, to)),
  ]);
  const seen = new Set<string>();
  const merged: Raw[] = [];
  for (const v of [...((recent ?? []) as unknown as Raw[]), ...open]) {
    if (seen.has(v.id)) continue;
    seen.add(v.id);
    merged.push(v);
  }
  merged.sort((a, b) => b.check_in_at.localeCompare(a.check_in_at));
  return merged.map(({ students, ...v }) => {
    const rooms = students?.rooms;
    const room = Array.isArray(rooms) ? rooms[0] : rooms;
    return { ...v, student: students ? { id: students.id, full_name: students.full_name, room_number: room?.room_number ?? null } : null };
  });
}

export interface StudentOption {
  id: string;
  full_name: string;
  phone: string;
  room_number: string | null;
}

/**
 * Server-side student search for pickers (visitor log): name/phone `ilike`,
 * capped at `limit` — never the whole hostel roster (10,000 students).
 * Empty query → first `limit` active students by name.
 */
export async function searchActiveStudents(db: Db, hostelId: string, query: string, limit = 20): Promise<StudentOption[]> {
  const q = query.trim().replace(/[%_,()\\]/g, " ").trim();
  let req = db.from("students").select("id, full_name, phone, rooms(room_number)").eq("hostel_id", hostelId).neq("status", "vacated");
  if (q) req = req.or(`full_name.ilike.%${q}%,phone.ilike.%${q.replace(/\D/g, "") || q}%`);
  const { data } = await req.order("full_name").limit(limit);
  type Raw = { id: string; full_name: string; phone: string; rooms: { room_number: string } | { room_number: string }[] | null };
  return ((data ?? []) as unknown as Raw[]).map((s) => {
    const room = Array.isArray(s.rooms) ? s.rooms[0] : s.rooms;
    return { id: s.id, full_name: s.full_name, phone: s.phone, room_number: room?.room_number ?? null };
  });
}

/* ───────────────────────── complaints ───────────────────────── */

export type ComplaintWithStudent = ComplaintRow & {
  student: { id: string; full_name: string; room_number: string | null } | null;
  events: ComplaintEventRow[];
};

export async function getComplaints(db: Db, hostelId: string, limit = 100): Promise<ComplaintWithStudent[]> {
  const { data } = await db
    .from("complaints")
    .select("*, students!inner(id, full_name, rooms(room_number)), complaint_events(*)")
    .eq("hostel_id", hostelId)
    .order("created_at", { ascending: false })
    .limit(limit);
  type Raw = ComplaintRow & {
    students: { id: string; full_name: string; rooms: { room_number: string } | { room_number: string }[] | null } | null;
    complaint_events: ComplaintEventRow[] | null;
  };
  return ((data ?? []) as unknown as Raw[]).map(({ students, complaint_events, ...c }) => {
    const room = Array.isArray(students?.rooms) ? students?.rooms[0] : students?.rooms;
    return {
      ...c,
      student: students ? { id: students.id, full_name: students.full_name, room_number: room?.room_number ?? null } : null,
      events: [...(complaint_events ?? [])].sort((a, b) => a.created_at.localeCompare(b.created_at)),
    };
  });
}
