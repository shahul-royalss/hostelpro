"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { assertHostelContext, assertWritableContext, errorMessage } from "@/lib/permissions";
import { createStaffAccount, regeneratePassword, setAccountStatus } from "@/lib/auth/accounts";
import { signedUrl } from "@/lib/storage";
import { fail, ok, type ActionResult, type AnnouncementAudience } from "@/lib/types";
import { ROLE_LABEL } from "@/lib/roles";
import { audit } from "@/lib/audit";
import { LIMITS, rateLimit } from "@/lib/rate-limit";
import { getActiveManager, getStudentById, type StudentProfileRow } from "@/lib/queries/owner";
import {
  announcementIdSchema,
  createAnnouncementSchema,
  createStaffSchema,
  createTaskSchema,
  hostelRulesSchema,
  staffIdSchema,
  staffStatusSchema,
  studentIdSchema,
  taskIdSchema,
  updateTaskSchema,
} from "@/lib/validators/owner";

/**
 * Owner server actions. Every write:
 *   validate (zod) → assertWritableContext('owner') → RLS client → revalidate.
 * hostel_id is always ctx.hostel.id (never trusted from the client).
 */

function firstIssue(fieldErrors: Record<string, string[] | undefined>, fallback: string) {
  for (const v of Object.values(fieldErrors)) if (v?.length) return v[0];
  return fallback;
}

/* ───────────────────────── Announcements (OW-3) ───────────────────────── */

export async function createAnnouncement(input: { title: string; body: string; audience: AnnouncementAudience }): Promise<ActionResult<{ id: string }>> {
  const parsed = createAnnouncementSchema.safeParse(input);
  if (!parsed.success) {
    const fe = parsed.error.flatten().fieldErrors;
    return fail(firstIssue(fe, "Check the form and try again."), fe as Record<string, string[]>);
  }
  try {
    const { user, ctx } = await assertWritableContext("owner");
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("announcements")
      .insert({
        hostel_id: ctx.hostel.id,
        author_user_id: user.id,
        title: parsed.data.title,
        body: parsed.data.body,
        audience: parsed.data.audience,
      })
      .select("id")
      .single();
    if (error) return fail(errorMessage(error));
    revalidatePath("/owner/updates");
    revalidatePath("/owner");
    revalidatePath("/manager");
    revalidatePath("/warden");
    revalidatePath("/student");
    await audit("owner.announcement.create", { targetType: "announcement", targetId: String((data as { id: string }).id), hostelId: ctx.hostel.id, meta: { audience: parsed.data.audience } });
    return ok({ id: String((data as { id: string }).id) }, "Update sent");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Soft-delete an announcement the owner sent (it disappears from every feed). */
export async function deleteAnnouncement(input: { announcementId: string }): Promise<ActionResult> {
  const parsed = announcementIdSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { ctx } = await assertWritableContext("owner");
    const supabase = await createClient();
    const { error } = await supabase
      .from("announcements")
      .update({ deleted_at: new Date().toISOString() })
      .eq("id", parsed.data.announcementId)
      .eq("hostel_id", ctx.hostel.id);
    if (error) return fail(errorMessage(error));
    revalidatePath("/owner/updates");
    revalidatePath("/owner");
    await audit("owner.announcement.delete", { targetType: "announcement", targetId: parsed.data.announcementId, hostelId: ctx.hostel.id });
    return ok(undefined, "Update removed");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── Staff (OW-4) ───────────────────────── */

export interface StaffCredentials {
  userId: string;
  name: string;
  role: string;
  loginId: string;
  password: string;
}

/**
 * Create the hostel's Manager or Warden. The DB trigger enforces "max 1 active"
 * (Hard rule §4.3) and returns a friendly message; the auth user is rolled back on failure.
 */
export async function createStaff(input: { role: "manager" | "warden"; fullName: string; email: string; phone?: string }): Promise<ActionResult<StaffCredentials>> {
  const parsed = createStaffSchema.safeParse(input);
  if (!parsed.success) {
    const fe = parsed.error.flatten().fieldErrors;
    return fail(firstIssue(fe, "Check the form and try again."), fe as Record<string, string[]>);
  }
  try {
    const { user, ctx } = await assertWritableContext("owner");
    const rl = await rateLimit(`owner:staff:${user.id}`, LIMITS.accountCreatePerUser.max, LIMITS.accountCreatePerUser.windowSeconds);
    if (!rl.allowed) return fail("Too many account operations in a short time. Please wait a bit and try again.");
    const supabase = await createClient();

    // Friendly pre-check (the trigger is the real guard)
    const { count } = await supabase
      .from("users")
      .select("id", { count: "exact", head: true })
      .eq("hostel_id", ctx.hostel.id)
      .eq("role", parsed.data.role)
      .eq("status", "active")
      .is("deleted_at", null);
    if ((count ?? 0) >= 1) {
      return fail(`This hostel already has an active ${parsed.data.role}. Deactivate the current ${parsed.data.role} first.`);
    }

    const created = await createStaffAccount({
      role: parsed.data.role,
      fullName: parsed.data.fullName,
      email: parsed.data.email,
      phone: parsed.data.phone || null,
      hostelId: ctx.hostel.id,
      createdBy: user.id,
    });

    await audit("owner.staff.create", { targetType: "user", targetId: created.userId, hostelId: ctx.hostel.id, meta: { role: parsed.data.role } });
    revalidatePath("/owner/staff");
    revalidatePath("/owner");
    return ok(
      {
        userId: created.userId,
        name: parsed.data.fullName,
        role: ROLE_LABEL[parsed.data.role],
        loginId: created.loginId,
        password: created.password,
      },
      `${ROLE_LABEL[parsed.data.role]} account created`,
    );
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Ensure the target user is a manager/warden of the active hostel (RLS-visible). */
async function loadStaffUser(userId: string, hostelId: string) {
  const supabase = await createClient();
  const { data } = await supabase
    .from("users")
    .select("id, role, full_name, email, status")
    .eq("id", userId)
    .eq("hostel_id", hostelId)
    .in("role", ["manager", "warden"])
    .is("deleted_at", null)
    .maybeSingle();
  return (data as { id: string; role: "manager" | "warden"; full_name: string; email: string | null; status: "active" | "inactive" } | null) ?? null;
}

export async function resetStaffPassword(input: { userId: string }): Promise<ActionResult<StaffCredentials>> {
  const parsed = staffIdSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { user, ctx } = await assertWritableContext("owner");
    const rl = await rateLimit(`owner:staff:${user.id}`, LIMITS.accountCreatePerUser.max, LIMITS.accountCreatePerUser.windowSeconds);
    if (!rl.allowed) return fail("Too many account operations in a short time. Please wait a bit and try again.");
    const staff = await loadStaffUser(parsed.data.userId, ctx.hostel.id);
    if (!staff) return fail("Staff member not found in this hostel.");
    const password = await regeneratePassword(staff.id);
    await audit("owner.staff.password_reset", { targetType: "user", targetId: staff.id, hostelId: ctx.hostel.id, meta: { role: staff.role } });
    return ok(
      { userId: staff.id, name: staff.full_name, role: ROLE_LABEL[staff.role], loginId: staff.email ?? "", password },
      "Temporary password generated",
    );
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function setStaffStatus(input: { userId: string; status: "active" | "inactive" }): Promise<ActionResult> {
  const parsed = staffStatusSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { ctx } = await assertWritableContext("owner");
    const staff = await loadStaffUser(parsed.data.userId, ctx.hostel.id);
    if (!staff) return fail("Staff member not found in this hostel.");
    if (staff.status === parsed.data.status) return ok(undefined);
    // Role-limit trigger fires on reactivation and returns a friendly error if the slot is taken.
    await setAccountStatus(staff.id, parsed.data.status);
    await audit("owner.staff.status", { targetType: "user", targetId: staff.id, hostelId: ctx.hostel.id, meta: { role: staff.role, status: parsed.data.status } });
    revalidatePath("/owner/staff");
    revalidatePath("/owner");
    return ok(undefined, parsed.data.status === "inactive" ? `${ROLE_LABEL[staff.role]} deactivated` : `${ROLE_LABEL[staff.role]} reactivated`);
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── Tasks for manager (OW-4) ───────────────────────── */

export async function createTask(input: { title: string; description?: string; dueDate?: string }): Promise<ActionResult<{ id: string }>> {
  const parsed = createTaskSchema.safeParse(input);
  if (!parsed.success) {
    const fe = parsed.error.flatten().fieldErrors;
    return fail(firstIssue(fe, "Check the task and try again."), fe as Record<string, string[]>);
  }
  try {
    const { user, ctx } = await assertWritableContext("owner");
    const supabase = await createClient();
    const manager = await getActiveManager(supabase, ctx.hostel.id);
    if (!manager) return fail("Add a manager first — tasks are assigned to the active manager.");

    const { data, error } = await supabase
      .from("tasks")
      .insert({
        hostel_id: ctx.hostel.id,
        assigned_to: manager.id,
        title: parsed.data.title,
        description: parsed.data.description || null,
        due_date: parsed.data.dueDate || null,
        created_by: user.id,
      })
      .select("id")
      .single();
    if (error) return fail(errorMessage(error));
    revalidatePath("/owner/staff");
    revalidatePath("/manager/tasks");
    revalidatePath("/manager");
    await audit("owner.task.create", { targetType: "task", targetId: String((data as { id: string }).id), hostelId: ctx.hostel.id });
    return ok({ id: String((data as { id: string }).id) }, "Task added");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function updateTask(input: { taskId: string; title?: string; description?: string | null; dueDate?: string | null; status?: "pending" | "in_progress" | "done" }): Promise<ActionResult> {
  const parsed = updateTaskSchema.safeParse(input);
  if (!parsed.success) {
    const fe = parsed.error.flatten().fieldErrors;
    return fail(firstIssue(fe, "Check the task and try again."), fe as Record<string, string[]>);
  }
  try {
    const { ctx } = await assertWritableContext("owner");
    const supabase = await createClient();
    const patch: Record<string, unknown> = {};
    if (parsed.data.title !== undefined) patch.title = parsed.data.title;
    if (parsed.data.description !== undefined) patch.description = parsed.data.description || null;
    if (parsed.data.dueDate !== undefined) patch.due_date = parsed.data.dueDate || null;
    if (parsed.data.status !== undefined) patch.status = parsed.data.status;
    if (Object.keys(patch).length === 0) return ok(undefined);

    const { error } = await supabase.from("tasks").update(patch).eq("id", parsed.data.taskId).eq("hostel_id", ctx.hostel.id).is("deleted_at", null);
    if (error) return fail(errorMessage(error));
    revalidatePath("/owner/staff");
    revalidatePath("/manager/tasks");
    revalidatePath("/manager");
    await audit("owner.task.update", { targetType: "task", targetId: parsed.data.taskId, hostelId: ctx.hostel.id, meta: { fields: Object.keys(patch) } });
    return ok(undefined, "Task updated");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function deleteTask(input: { taskId: string }): Promise<ActionResult> {
  const parsed = taskIdSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { ctx } = await assertWritableContext("owner");
    const supabase = await createClient();
    const { error } = await supabase
      .from("tasks")
      .update({ deleted_at: new Date().toISOString() })
      .eq("id", parsed.data.taskId)
      .eq("hostel_id", ctx.hostel.id);
    if (error) return fail(errorMessage(error));
    revalidatePath("/owner/staff");
    revalidatePath("/manager/tasks");
    revalidatePath("/manager");
    await audit("owner.task.delete", { targetType: "task", targetId: parsed.data.taskId, hostelId: ctx.hostel.id });
    return ok(undefined, "Task removed");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── Hostel rules ───────────────────────── */

export async function updateHostelRules(input: { rules: string }): Promise<ActionResult> {
  const parsed = hostelRulesSchema.safeParse(input);
  if (!parsed.success) {
    const fe = parsed.error.flatten().fieldErrors;
    return fail(firstIssue(fe, "Check the rules text."), fe as Record<string, string[]>);
  }
  try {
    const { ctx } = await assertWritableContext("owner");
    const supabase = await createClient();
    const { error } = await supabase.rpc("ow_update_hostel_rules", { p_hostel_id: ctx.hostel.id, p_rules: parsed.data.rules || null });
    if (error) return fail(errorMessage(error));
    revalidatePath("/owner/staff");
    revalidatePath("/owner");
    revalidatePath("/student");
    await audit("owner.hostel.rules", { targetType: "hostel", targetId: ctx.hostel.id, hostelId: ctx.hostel.id });
    return ok(undefined, "Hostel rules saved");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── Students (OW-5) — read helpers ───────────────────────── */

export interface StudentProfilePayload {
  student: StudentProfileRow;
  /** signed URLs (private bucket, 1 h) */
  photoUrl: string | null;
  idProofUrl: string | null;
}

/**
 * Full profile for the slide-over — loaded on row select so the directory list never ships
 * guardian / address / ID-proof PII in bulk. Read-only; scoped to the active hostel via RLS + hostel_id.
 */
export async function getStudentProfile(input: { studentId: string }): Promise<ActionResult<StudentProfilePayload>> {
  const parsed = studentIdSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { ctx } = await assertHostelContext("owner");
    const supabase = await createClient();
    const student = await getStudentById(supabase, ctx.hostel.id, parsed.data.studentId);
    if (!student) return fail("Student not found.");
    const [photoUrl, idProofUrl] = await Promise.all([
      signedUrl("student-docs", student.photo_url, ctx.hostel.id),
      signedUrl("student-docs", student.id_proof_url, ctx.hostel.id),
    ]);
    return ok({ student, photoUrl, idProofUrl });
  } catch (e) {
    return fail(errorMessage(e));
  }
}
