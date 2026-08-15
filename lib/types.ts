/**
 * Domain row types — mirror db/schema.sql exactly.
 * Keep in sync when the schema changes.
 */
import type { UserRole } from "@/lib/roles";
export type { UserRole };

export type UserStatus = "active" | "inactive";
export type HostelStatus = "active" | "readonly" | "suspended";
export type SubscriptionStatus = "active" | "expiring" | "expired";
export type BedStatus = "free" | "occupied";
export type StudentStatus = "active" | "on_leave" | "vacated";
export type FeeStatus = "paid" | "partial" | "unpaid";
export type PaymentMode = "cash" | "upi" | "bank";
export type ComplaintCategory = "food" | "cleaning" | "maintenance" | "wifi" | "roommate" | "other";
export type ComplaintStatus = "open" | "in_progress" | "resolved";
export type ExpenseCategory = "groceries" | "staff" | "electricity" | "water" | "maintenance" | "other";
export type RevenueSource = "fees" | "mess" | "other";
export type AnnouncementAudience = "all" | "manager" | "warden" | "students";
export type TaskStatus = "pending" | "in_progress" | "done";
export type LeaveStatus = "pending" | "approved" | "rejected";
export type DayOfWeek = "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun";
export type MealType = "breakfast" | "lunch" | "snacks" | "dinner";
export type NotificationType = "announcement" | "task" | "complaint" | "leave" | "subscription" | "fee" | "system";

export const COMPLAINT_CATEGORIES: ComplaintCategory[] = ["food", "cleaning", "maintenance", "wifi", "roommate", "other"];
export const EXPENSE_CATEGORIES: ExpenseCategory[] = ["groceries", "staff", "electricity", "water", "maintenance", "other"];
export const REVENUE_SOURCES: RevenueSource[] = ["fees", "mess", "other"];
export const PAYMENT_MODES: PaymentMode[] = ["cash", "upi", "bank"];
export const DAYS_OF_WEEK: DayOfWeek[] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
export const MEALS: MealType[] = ["breakfast", "lunch", "snacks", "dinner"];
export const AUDIENCES: AnnouncementAudience[] = ["all", "manager", "warden", "students"];

export const DAY_LABEL: Record<DayOfWeek, string> = {
  mon: "Monday", tue: "Tuesday", wed: "Wednesday", thu: "Thursday", fri: "Friday", sat: "Saturday", sun: "Sunday",
};
export const MEAL_LABEL: Record<MealType, string> = {
  breakfast: "Breakfast", lunch: "Lunch", snacks: "Snacks", dinner: "Dinner",
};
export const MEAL_TIMING: Record<MealType, string> = {
  breakfast: "7:30 – 9:30 AM", lunch: "12:30 – 2:30 PM", snacks: "5:00 – 6:00 PM", dinner: "8:00 – 10:00 PM",
};

/* ───────────────────────── Rows ───────────────────────── */

export interface UserRow {
  id: string;
  role: UserRole;
  full_name: string;
  email: string | null;
  phone: string | null;
  hostel_id: string | null;
  status: UserStatus;
  must_change_password: boolean;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface HostelRow {
  id: string;
  name: string;
  owner_user_id: string;
  total_floors: number;
  total_rooms: number;
  beds_per_room_default: number;
  address: string | null;
  rules: string | null;
  status: HostelStatus;
  created_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface SubscriptionRow {
  id: string;
  hostel_id: string;
  owner_user_id: string;
  start_date: string;
  end_date: string;
  amount: number;
  status: SubscriptionStatus;
  created_by: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface FloorRow {
  id: string;
  hostel_id: string;
  floor_number: number;
}

export interface RoomRow {
  id: string;
  hostel_id: string;
  floor_id: string;
  room_number: string;
  capacity: number;
  created_at: string;
  updated_at: string;
}

export interface BedRow {
  id: string;
  hostel_id: string;
  room_id: string;
  bed_number: number;
  status: BedStatus;
  student_id: string | null;
}

export interface StudentRow {
  id: string;
  hostel_id: string;
  user_id: string | null;
  full_name: string;
  phone: string;
  email: string | null;
  photo_url: string | null;
  guardian_name: string | null;
  guardian_phone: string | null;
  permanent_address: string | null;
  id_proof_type: string | null;
  id_proof_url: string | null;
  date_of_joining: string;
  room_id: string | null;
  bed_id: string | null;
  monthly_fee: number;
  status: StudentStatus;
  vacated_at: string | null;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface FeePaymentRow {
  id: string;
  hostel_id: string;
  student_id: string;
  period_month: string;
  amount_due: number;
  amount_paid: number;
  status: FeeStatus;
  paid_on: string | null;
  mode: PaymentMode | null;
  notes: string | null;
  recorded_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface ComplaintRow {
  id: string;
  hostel_id: string;
  student_id: string;
  category: ComplaintCategory;
  title: string;
  description: string | null;
  photo_url: string | null;
  status: ComplaintStatus;
  resolved_at: string | null;
  resolution_note: string | null;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface ComplaintEventRow {
  id: string;
  hostel_id: string;
  complaint_id: string;
  status: ComplaintStatus;
  note: string | null;
  actor_user_id: string | null;
  created_at: string;
}

export interface ExpenseRow {
  id: string;
  hostel_id: string;
  date: string;
  category: ExpenseCategory;
  amount: number;
  note: string | null;
  receipt_url: string | null;
  uploaded_by: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface RevenueRow {
  id: string;
  hostel_id: string;
  date: string;
  source: RevenueSource;
  amount: number;
  note: string | null;
  uploaded_by: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface AnnouncementRow {
  id: string;
  hostel_id: string;
  author_user_id: string;
  title: string;
  body: string;
  audience: AnnouncementAudience;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface TaskRow {
  id: string;
  hostel_id: string;
  assigned_to: string;
  title: string;
  description: string | null;
  due_date: string | null;
  status: TaskStatus;
  created_by: string;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface LeaveRow {
  id: string;
  hostel_id: string;
  student_id: string;
  from_date: string;
  to_date: string;
  reason: string | null;
  status: LeaveStatus;
  decided_by: string | null;
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
  updated_at: string;
}

export interface VisitorRow {
  id: string;
  hostel_id: string;
  student_id: string;
  visitor_name: string;
  visitor_phone: string | null;
  relation: string | null;
  check_in_at: string;
  check_out_at: string | null;
  logged_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface MenuRow {
  id: string;
  hostel_id: string;
  day_of_week: DayOfWeek;
  meal: MealType;
  items: string;
  updated_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface NotificationRow {
  id: string;
  hostel_id: string | null;
  user_id: string;
  type: NotificationType;
  title: string;
  body: string | null;
  link: string | null;
  read_at: string | null;
  created_at: string;
}

/* ───────────────────────── RPC result shapes ───────────────────────── */

export interface FeeLedgerRow {
  student_id: string;
  full_name: string;
  phone: string;
  photo_url: string | null;
  room_number: string | null;
  bed_number: number | null;
  monthly_fee: number;
  amount_due: number;
  amount_paid: number;
  status: FeeStatus;
  paid_on: string | null;
  mode: PaymentMode | null;
}

export interface RoomOccupancyRow {
  room_id: string;
  floor_id: string;
  floor_number: number;
  room_number: string;
  capacity: number;
  occupied: number;
}

export interface HostelStats {
  total_beds: number;
  occupied_beds: number;
  active_students: number;
  open_complaints: number;
  fees_collected: number;
  fees_pending: number;
  students_paid: number;
  students_unpaid: number;
  pending_leaves: number;
  visitors_today: number;
  pending_tasks: number;
  revenue_today: number;
  expenses_today: number;
  revenue_month: number;
  expenses_month: number;
  subscription_days_left: number | null;
  subscription_state: SubscriptionStatus;
}

export interface DailyFinanceRow {
  day: string;
  revenue: number;
  expense: number;
}

export interface SaDashboardStats {
  total_hostels: number;
  total_owners: number;
  total_students: number;
  active_subs: number;
  expiring_subs: number;
  expired_subs: number;
  monthly_subscription_revenue: number;
}

export interface SaOnboardingPoint {
  month: string;
  hostels: number;
}

export interface SaHostelRow {
  hostel_id: string;
  hostel_name: string;
  hostel_status: HostelStatus;
  address: string | null;
  owner_id: string;
  owner_name: string;
  owner_email: string | null;
  owner_phone: string | null;
  sub_start: string | null;
  sub_end: string | null;
  sub_amount: number | null;
  sub_state: SubscriptionStatus;
  days_left: number | null;
  total_beds: number;
  occupied_beds: number;
  active_students: number;
  open_complaints: number;
  created_at: string;
}

export interface ComplaintsPerWeekRow {
  week_start: string;
  complaints: number;
}

export interface RoommateRow {
  student_id: string;
  full_name: string;
  phone: string;
  bed_number: number | null;
  photo_url: string | null;
}

/* ───────────────────────── Server action result ───────────────────────── */

export type ActionResult<T = undefined> =
  | { ok: true; data: T; message?: string }
  | { ok: false; error: string; fieldErrors?: Record<string, string[]> };

export function ok<T>(data: T, message?: string): ActionResult<T> {
  return { ok: true, data, message };
}
export function fail<T = undefined>(error: string, fieldErrors?: Record<string, string[]>): ActionResult<T> {
  return { ok: false, error, fieldErrors };
}
