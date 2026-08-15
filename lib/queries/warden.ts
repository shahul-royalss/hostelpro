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
  const { data } = await db.rpc("rpc_room_occupancy", { p_hostel_id: hostelId });
  return (data ?? []) as RoomOccupancyRow[];
}

export interface FreeBed {
  bed_id: string;
  bed_number: number;
  room_id: string;
  room_number: string;
  floor_number: number;
}

/** Every free bed in the hostel (for the register form + reassign sheet). */
export async function getFreeBeds(db: Db, hostelId: string): Promise<FreeBed[]> {
  const { data } = await db
    .from("beds")
    .select("id, bed_number, room_id, rooms!inner(room_number, floors!inner(floor_number))")
    .eq("hostel_id", hostelId)
    .is("student_id", null);
  type Raw = {
    id: string;
    bed_number: number;
    room_id: string;
    rooms: { room_number: string; floors: { floor_number: number } | { floor_number: number }[] } | null;
  };
  const rows = (data ?? []) as unknown as Raw[];
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
  const { data: room } = await db
    .from("rooms")
    .select("*, floors!inner(floor_number)")
    .eq("hostel_id", hostelId)
    .eq("id", roomId)
    .maybeSingle();
  if (!room) return null;
  const r = room as unknown as RoomRow & { floors: { floor_number: number } | { floor_number: number }[] };
  const floor = Array.isArray(r.floors) ? r.floors[0] : r.floors;

  const [{ data: beds }, { data: students }, { data: fees }] = await Promise.all([
    db.from("beds").select("id, bed_number, student_id").eq("room_id", roomId).order("bed_number"),
    db
      .from("students")
      .select("id, full_name, phone, photo_url, date_of_joining, monthly_fee, status, bed_id")
      .eq("hostel_id", hostelId)
      .eq("room_id", roomId)
      .neq("status", "vacated"),
    db.from("fee_payments").select("student_id, status, amount_due, amount_paid").eq("hostel_id", hostelId).eq("period_month", period),
  ]);

  type S = Pick<StudentRow, "id" | "full_name" | "phone" | "photo_url" | "date_of_joining" | "monthly_fee" | "status" | "bed_id">;
  const byBed = new Map<string, S>();
  for (const s of (students ?? []) as S[]) if (s.bed_id) byBed.set(s.bed_id, s);
  const feeByStudent = new Map<string, { status: FeeStatus; amount_due: number; amount_paid: number }>();
  for (const f of (fees ?? []) as { student_id: string; status: FeeStatus; amount_due: number; amount_paid: number }[]) {
    feeByStudent.set(f.student_id, f);
  }

  return {
    room: { ...r, floor_number: floor?.floor_number ?? 0 },
    beds: ((beds ?? []) as { id: string; bed_number: number; student_id: string | null }[]).map((b) => {
      const s = byBed.get(b.id);
      if (!s) return { id: b.id, bed_number: b.bed_number, student: null };
      const f = feeByStudent.get(s.id);
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
  const { data } = await db.rpc("rpc_fee_ledger", { p_hostel_id: hostelId, p_period_month: period });
  return ((data ?? []) as FeeLedgerRow[]).map((r) => ({
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

export async function getLeaves(db: Db, hostelId: string, limit = 60): Promise<LeaveWithStudent[]> {
  const { data } = await db
    .from("leaves")
    .select("*, students!inner(id, full_name, phone, photo_url, rooms(room_number))")
    .eq("hostel_id", hostelId)
    .order("created_at", { ascending: false })
    .limit(limit);
  type Raw = LeaveRow & {
    students: { id: string; full_name: string; phone: string; photo_url: string | null; rooms: { room_number: string } | { room_number: string }[] | null } | null;
  };
  return ((data ?? []) as unknown as Raw[]).map(({ students, ...l }) => {
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

export async function getVisitors(db: Db, hostelId: string, sinceISO: string, limit = 200): Promise<VisitorWithStudent[]> {
  const { data } = await db
    .from("visitors")
    .select("*, students!inner(id, full_name, rooms(room_number))")
    .eq("hostel_id", hostelId)
    .gte("check_in_at", sinceISO)
    .order("check_in_at", { ascending: false })
    .limit(limit);
  type Raw = VisitorRow & { students: { id: string; full_name: string; rooms: { room_number: string } | { room_number: string }[] | null } | null };
  return ((data ?? []) as unknown as Raw[]).map(({ students, ...v }) => {
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

/** Active students for pickers (visitor log). */
export async function getActiveStudents(db: Db, hostelId: string): Promise<StudentOption[]> {
  const { data } = await db
    .from("students")
    .select("id, full_name, phone, rooms(room_number)")
    .eq("hostel_id", hostelId)
    .neq("status", "vacated")
    .order("full_name");
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
