"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { assertHostelContext, assertWritableContext, errorMessage } from "@/lib/permissions";
import { createStudentAuthUser, deleteAuthUser } from "@/lib/auth/accounts";
import { uploadToBucket } from "@/lib/storage";
import { fail, ok, type ActionResult } from "@/lib/types";
import { getFreeBeds, type FreeBed } from "@/lib/queries/warden";
import {
  checkOutVisitorSchema,
  decideLeaveSchema,
  logVisitorSchema,
  reassignBedSchema,
  recordPaymentSchema,
  registerStudentSchema,
  updateRoomSchema,
  vacateStudentSchema,
} from "@/lib/validators/warden";

function flatten(err: { flatten: () => { fieldErrors: Record<string, string[] | undefined> } }) {
  const fe = err.flatten().fieldErrors;
  const out: Record<string, string[]> = {};
  for (const [k, v] of Object.entries(fe)) if (v) out[k] = v;
  return out;
}

/* ───────────────────────── register student (WD-2) ───────────────────────── */

export interface RegisterStudentResult {
  studentId: string;
  roomId: string | null;
  credentials: { name: string; loginId: string; password: string };
}

/**
 * Creates the student login (service role) → uploads photo / ID proof →
 * wd_register_student RPC (users + students rows, bed occupied, RLS-checked).
 * If the DB half fails the auth user is deleted again (no orphan logins).
 */
export async function registerStudent(formData: FormData): Promise<ActionResult<RegisterStudentResult>> {
  const raw = {
    fullName: formData.get("fullName"),
    phone: formData.get("phone"),
    email: formData.get("email") ?? "",
    dateOfJoining: formData.get("dateOfJoining"),
    guardianName: formData.get("guardianName"),
    guardianPhone: formData.get("guardianPhone"),
    permanentAddress: formData.get("permanentAddress"),
    idProofType: formData.get("idProofType"),
    bedId: formData.get("bedId"),
    monthlyFee: formData.get("monthlyFee"),
  };
  const parsed = registerStudentSchema.safeParse(raw);
  if (!parsed.success) return fail("Please check the highlighted fields.", flatten(parsed.error));
  const input = parsed.data;

  const photo = formData.get("photo");
  const idProof = formData.get("idProof");
  const photoFile = photo instanceof File && photo.size > 0 ? photo : null;
  const idProofFile = idProof instanceof File && idProof.size > 0 ? idProof : null;

  let userId: string | null = null;
  try {
    const { ctx } = await assertWritableContext("warden");
    const hostelId = ctx.hostel.id;

    let account: Awaited<ReturnType<typeof createStudentAuthUser>>;
    try {
      account = await createStudentAuthUser({ fullName: input.fullName, phone: input.phone, hostelId });
    } catch (e) {
      const msg = errorMessage(e);
      if (/SERVICE_ROLE_KEY/i.test(msg)) {
        return fail("Student accounts can't be created yet — the server is missing its Supabase service key. Ask the administrator to configure it.");
      }
      return fail(msg);
    }
    userId = account.userId;

    const [photoPath, idProofPath] = await Promise.all([
      uploadToBucket("student-docs", hostelId, "photos", photoFile),
      uploadToBucket("student-docs", hostelId, "id-proofs", idProofFile),
    ]);

    const supabase = await createClient();
    const { data: studentId, error } = await supabase.rpc("wd_register_student", {
      p_user_id: userId,
      p_hostel_id: hostelId,
      p_full_name: input.fullName,
      p_phone: input.phone,
      p_email: input.email || null,
      p_photo_url: photoPath,
      p_guardian_name: input.guardianName,
      p_guardian_phone: input.guardianPhone,
      p_permanent_address: input.permanentAddress,
      p_id_proof_type: input.idProofType,
      p_id_proof_url: idProofPath,
      p_date_of_joining: input.dateOfJoining,
      p_bed_id: input.bedId,
      p_monthly_fee: input.monthlyFee,
    });
    if (error) {
      await deleteAuthUser(userId);
      return fail(errorMessage(error));
    }

    const { data: bed } = await supabase.from("beds").select("room_id").eq("id", input.bedId).maybeSingle();

    revalidatePath("/warden");
    revalidatePath("/warden/rooms");
    revalidatePath("/warden/fees");
    revalidatePath("/owner/students");
    return ok({
      studentId: String(studentId),
      roomId: (bed as { room_id: string } | null)?.room_id ?? null,
      credentials: { name: input.fullName, loginId: account.loginId, password: account.password },
    });
  } catch (e) {
    if (userId) await deleteAuthUser(userId);
    return fail(errorMessage(e));
  }
}

/** Free beds across the hostel (used by the register form + reassign sheet to refresh). */
export async function fetchFreeBeds(): Promise<ActionResult<FreeBed[]>> {
  try {
    const { ctx } = await assertHostelContext("warden");
    const supabase = await createClient();
    return ok(await getFreeBeds(supabase, ctx.hostel.id));
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── rooms (WD-3 / WD-4) ───────────────────────── */

export async function updateRoom(input: { roomId: string; roomNumber: string; capacity: number }): Promise<ActionResult> {
  const parsed = updateRoomSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the room details.", flatten(parsed.error));
  try {
    const { ctx } = await assertWritableContext("warden");
    const supabase = await createClient();
    const { error } = await supabase
      .from("rooms")
      .update({ room_number: parsed.data.roomNumber, capacity: parsed.data.capacity })
      .eq("id", parsed.data.roomId)
      .eq("hostel_id", ctx.hostel.id);
    if (error) {
      if (error.code === "23505") return fail(`Room ${parsed.data.roomNumber} already exists on this hostel.`);
      return fail(errorMessage(error));
    }
    revalidatePath("/warden/rooms");
    revalidatePath(`/warden/rooms/${parsed.data.roomId}`);
    revalidatePath("/warden");
    return ok(undefined, "Room updated");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function reassignBed(input: { studentId: string; bedId: string }): Promise<ActionResult> {
  const parsed = reassignBedSchema.safeParse(input);
  if (!parsed.success) return fail("Pick a free bed.");
  try {
    const { ctx } = await assertWritableContext("warden");
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("students")
      .update({ bed_id: parsed.data.bedId })
      .eq("id", parsed.data.studentId)
      .eq("hostel_id", ctx.hostel.id)
      .neq("status", "vacated")
      .select("id, room_id")
      .maybeSingle();
    if (error) return fail(errorMessage(error));
    if (!data) return fail("Student not found.");
    revalidatePath("/warden/rooms", "layout");
    revalidatePath("/warden");
    revalidatePath("/warden/fees");
    return ok(undefined, "Bed reassigned");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function vacateStudent(input: { studentId: string }): Promise<ActionResult> {
  const parsed = vacateStudentSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid student.");
  try {
    await assertWritableContext("warden");
    const supabase = await createClient();
    const { error } = await supabase.rpc("wd_vacate_student", { p_student_id: parsed.data.studentId });
    if (error) return fail(errorMessage(error));
    revalidatePath("/warden/rooms", "layout");
    revalidatePath("/warden");
    revalidatePath("/warden/fees");
    revalidatePath("/owner/students");
    return ok(undefined, "Student checked out — bed is now free");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── fees (WD-5) ───────────────────────── */

export async function recordPayment(input: {
  studentId: string;
  periodMonth: string;
  amount: number;
  mode: "cash" | "upi" | "bank";
  paidOn: string;
  notes?: string;
}): Promise<ActionResult> {
  const parsed = recordPaymentSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the payment details.", flatten(parsed.error));
  try {
    await assertWritableContext("warden");
    const supabase = await createClient();
    const { error } = await supabase.rpc("wd_record_payment", {
      p_student_id: parsed.data.studentId,
      p_period_month: parsed.data.periodMonth,
      p_amount: parsed.data.amount,
      p_mode: parsed.data.mode,
      p_paid_on: parsed.data.paidOn,
      p_notes: parsed.data.notes || null,
    });
    if (error) return fail(errorMessage(error));
    revalidatePath("/warden/fees");
    revalidatePath("/warden");
    revalidatePath("/warden/rooms", "layout");
    revalidatePath("/owner");
    revalidatePath("/owner/students");
    revalidatePath("/student");
    return ok(undefined, "Payment recorded");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── leaves (WD-6) ───────────────────────── */

export async function decideLeave(input: { leaveId: string; status: "approved" | "rejected"; note?: string }): Promise<ActionResult> {
  const parsed = decideLeaveSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.", flatten(parsed.error));
  try {
    const { user, ctx } = await assertWritableContext("warden");
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("leaves")
      .update({
        status: parsed.data.status,
        decided_by: user.id,
        decided_at: new Date().toISOString(),
        decision_note: parsed.data.note || null,
      })
      .eq("id", parsed.data.leaveId)
      .eq("hostel_id", ctx.hostel.id)
      .eq("status", "pending")
      .select("id")
      .maybeSingle();
    if (error) return fail(errorMessage(error));
    if (!data) return fail("This request was already decided.");
    revalidatePath("/warden/leaves");
    revalidatePath("/warden");
    revalidatePath("/student/leave");
    return ok(undefined, parsed.data.status === "approved" ? "Leave approved" : "Leave rejected");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── visitors (WD-6) ───────────────────────── */

export async function logVisitor(input: {
  studentId: string;
  visitorName: string;
  visitorPhone?: string;
  relation?: string;
  checkInAt: string;
}): Promise<ActionResult> {
  const parsed = logVisitorSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the visitor details.", flatten(parsed.error));
  try {
    const { user, ctx } = await assertWritableContext("warden");
    const supabase = await createClient();
    const checkIn = new Date(parsed.data.checkInAt);
    if (Number.isNaN(checkIn.getTime())) return fail("Pick a valid check-in time.");
    const { error } = await supabase.from("visitors").insert({
      hostel_id: ctx.hostel.id,
      student_id: parsed.data.studentId,
      visitor_name: parsed.data.visitorName,
      visitor_phone: parsed.data.visitorPhone || null,
      relation: parsed.data.relation || null,
      check_in_at: checkIn.toISOString(),
      logged_by: user.id,
    });
    if (error) return fail(errorMessage(error));
    revalidatePath("/warden/visitors");
    revalidatePath("/warden");
    return ok(undefined, "Visitor logged");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function checkOutVisitor(input: { visitorId: string }): Promise<ActionResult> {
  const parsed = checkOutVisitorSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid visitor.");
  try {
    const { ctx } = await assertWritableContext("warden");
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("visitors")
      .update({ check_out_at: new Date().toISOString() })
      .eq("id", parsed.data.visitorId)
      .eq("hostel_id", ctx.hostel.id)
      .is("check_out_at", null)
      .select("id")
      .maybeSingle();
    if (error) return fail(errorMessage(error));
    if (!data) return fail("This visitor was already checked out.");
    revalidatePath("/warden/visitors");
    revalidatePath("/warden");
    return ok(undefined, "Visitor checked out");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
