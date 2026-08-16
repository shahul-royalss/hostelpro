import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  AnnouncementRow,
  ComplaintEventRow,
  ComplaintRow,
  FeePaymentRow,
  LeaveRow,
  MenuRow,
  RoommateRow,
  StudentRow,
} from "@/lib/types";

/**
 * Student-side data helpers. Every call goes through the RLS client, so a
 * student only ever receives their own rows (Hard rule §4.8); roommates come
 * from the st_my_roommates() RPC (name / phone / bed only).
 */

export interface MyStudent extends StudentRow {
  room: { room_number: string; capacity: number; floor: { floor_number: number } | null } | null;
  bed: { bed_number: number } | null;
}

export async function getMyStudent(supabase: SupabaseClient, userId: string): Promise<MyStudent | null> {
  const { data } = await supabase
    .from("students")
    // beds↔students have two FKs (beds.student_id and students.bed_id) → disambiguate
    .select("*, room:rooms(room_number, capacity, floor:floors(floor_number)), bed:beds!students_bed_id_fkey(bed_number)")
    .eq("user_id", userId)
    .neq("status", "vacated")
    .maybeSingle();
  return (data as MyStudent | null) ?? null;
}

export async function getMyFeeForPeriod(supabase: SupabaseClient, studentId: string, periodMonth: string): Promise<FeePaymentRow | null> {
  const { data } = await supabase
    .from("fee_payments")
    .select("*")
    .eq("student_id", studentId)
    .eq("period_month", periodMonth)
    .maybeSingle();
  return (data as FeePaymentRow | null) ?? null;
}

export interface FeeSummary {
  status: "paid" | "partial" | "unpaid";
  due: number;
  paid: number;
  remaining: number;
}

/** Current-month fee status; no fee_payments row → the whole monthly fee is due. */
export function summariseFee(fee: FeePaymentRow | null, monthlyFee: number): FeeSummary {
  if (!fee) {
    // A zero / waived monthly fee has nothing outstanding — don't show "Due ₹0".
    if (monthlyFee <= 0) return { status: "paid", due: 0, paid: 0, remaining: 0 };
    return { status: "unpaid", due: monthlyFee, paid: 0, remaining: monthlyFee };
  }
  // A legitimate 0 amount_due must not fall back to monthly_fee — only null/undefined does.
  const due = fee.amount_due == null ? monthlyFee : Number(fee.amount_due);
  const paid = Number(fee.amount_paid) || 0;
  if (due <= 0) return { status: "paid", due: 0, paid, remaining: 0 };
  return { status: fee.status, due, paid, remaining: Math.max(0, due - paid) };
}

export async function getAnnouncements(supabase: SupabaseClient, hostelId: string, limit = 5): Promise<AnnouncementRow[]> {
  const { data } = await supabase
    .from("announcements")
    .select("*")
    .eq("hostel_id", hostelId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(limit);
  return (data ?? []) as AnnouncementRow[];
}

export async function getMyRoommates(supabase: SupabaseClient): Promise<RoommateRow[]> {
  const { data } = await supabase.rpc("st_my_roommates");
  return (data ?? []) as RoommateRow[];
}

export async function getMenus(supabase: SupabaseClient, hostelId: string): Promise<MenuRow[]> {
  const { data } = await supabase.from("menus").select("*").eq("hostel_id", hostelId);
  return (data ?? []) as MenuRow[];
}

export async function getMyComplaints(supabase: SupabaseClient, studentId: string): Promise<ComplaintRow[]> {
  const { data } = await supabase
    .from("complaints")
    .select("*")
    .eq("student_id", studentId)
    .order("created_at", { ascending: false });
  return (data ?? []) as ComplaintRow[];
}

export async function getComplaintEvents(supabase: SupabaseClient, complaintIds: string[]): Promise<ComplaintEventRow[]> {
  if (!complaintIds.length) return [];
  const { data } = await supabase
    .from("complaint_events")
    .select("*")
    .in("complaint_id", complaintIds)
    .order("created_at", { ascending: true });
  return (data ?? []) as ComplaintEventRow[];
}

export async function getMyLeaves(supabase: SupabaseClient, studentId: string): Promise<LeaveRow[]> {
  const { data } = await supabase
    .from("leaves")
    .select("*")
    .eq("student_id", studentId)
    .order("created_at", { ascending: false });
  return (data ?? []) as LeaveRow[];
}

/** Result of st_hostel_contacts() — hostel card + staff contacts (security definer RPC). */
export interface HostelContacts {
  hostel_name: string;
  address: string | null;
  rules: string | null;
  warden_name: string | null;
  warden_phone: string | null;
  manager_name: string | null;
  manager_phone: string | null;
  owner_name: string | null;
}

export async function getHostelContacts(supabase: SupabaseClient): Promise<HostelContacts | null> {
  const { data } = await supabase.rpc("st_hostel_contacts").maybeSingle();
  return (data as HostelContacts | null) ?? null;
}
