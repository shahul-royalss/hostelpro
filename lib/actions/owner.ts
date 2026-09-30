"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { assertHostelContext, assertWritableContext, errorMessage, type HostelContext } from "@/lib/permissions";
import { createStaffAccount, regeneratePassword, setAccountStatus } from "@/lib/auth/accounts";
import { signedUrl } from "@/lib/storage";
import { fail, ok, type ActionResult, type AnnouncementAudience } from "@/lib/types";
import { ROLE_LABEL, ROLE_LIMITS } from "@/lib/roles";
import { audit } from "@/lib/audit";
import { LIMITS, rateLimit } from "@/lib/rate-limit";
import { activeCount, getActiveManager, getStaff, getStudentById, type StudentProfileRow } from "@/lib/queries/owner";
import {
  announcementIdSchema,
  createAnnouncementSchema,
  createStaffSchema,
  createTaskSchema,
  hostelRulesSchema,
  staffHostelsSchema,
  staffIdSchema,
  staffStatusSchema,
  studentIdSchema,
  taskIdSchema,
  updateTaskSchema,
} from "@/lib/validators/owner";

/**
 * Owner server actions. Every write:
 *   validate (zod) → assertWritableContext('owner') → RLS client → revalidate.
 * hostel_id is always ctx.hostel.id (never trusted from the client). The one exception is staff
 * PG access (createStaff / setStaffHostels), where the owner picks PGs: those ids are accepted
 * only when they are in the owner's own hostel list, and the database checks them again.
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
 * The owner's own PGs, as a set, from the hostel context (hostels where owner_user_id is the
 * caller, read under RLS). Every "is this PG yours?" check in this file asks this set, and
 * createStaffAccount / owner_set_staff_hostels ask the database again on their own.
 */
function ownedHostelIds(ctx: HostelContext): Set<string> {
  return new Set(ctx.hostels.map((h) => h.id));
}

/**
 * Create a Manager or Warden, allowed into one or more of the owner's PGs. The DB trigger
 * enforces five active of each per PG (Hard rule §4.3) and returns a friendly message; the auth
 * user is rolled back on failure.
 *
 * `hostelIds` absent means the current PG only, exactly as before multi-PG staff. When present,
 * the first id is where the new account starts working, and every id must be the caller's own.
 */
export async function createStaff(input: {
  role: "manager" | "warden";
  fullName: string;
  email: string;
  phone?: string;
  hostelIds?: string[];
}): Promise<ActionResult<StaffCredentials>> {
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

    const owned = ownedHostelIds(ctx);
    const hostelIds = [...new Set(parsed.data.hostelIds ?? [ctx.hostel.id])];
    if (hostelIds.some((id) => !owned.has(id))) return fail("You can only give access to your own PGs.");

    // A suspended PG is refused here, by name, before any account exists. ctx.hostels carries each
    // PG's status but not its subscription state, so an EXPIRED (read-only) extra PG is left to the
    // database: the staff_hostel_access guard refuses it with a P0001 sentence that createStaffAccount
    // passes through after rolling the half-made account back.
    const suspended = ctx.hostels.find((h) => hostelIds.includes(h.id) && h.status === "suspended");
    if (suspended) return fail(`${suspended.name} is suspended, so no one can be given access to it.`);

    // Friendly pre-check, per chosen PG (the database is the real guard). Five each since
    // 2026-09-12, counted as active staff WITH ACCESS to the PG, matching app.enforce_role_limits
    // and the mobile app's owner-create-staff Edge Function.
    const limit = ROLE_LIMITS[parsed.data.role];
    const perPg = await Promise.all(
      hostelIds.map(async (id) => ({ id, active: activeCount(await getStaff(supabase, id), parsed.data.role) })),
    );
    const full = perPg.find((p) => p.active >= limit);
    if (full) {
      const name = ctx.hostels.find((h) => h.id === full.id)?.name ?? "This PG";
      return fail(`${name} already has ${limit} active ${parsed.data.role}s. Remove one from it first.`);
    }

    const created = await createStaffAccount({
      role: parsed.data.role,
      fullName: parsed.data.fullName,
      email: parsed.data.email,
      phone: parsed.data.phone || null,
      hostelIds,
      createdBy: user.id,
    });

    await audit("owner.staff.create", { targetType: "user", targetId: created.userId, hostelId: ctx.hostel.id, meta: { role: parsed.data.role, hostelIds } });
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

/**
 * Ensure the target user is one of THIS owner's managers/wardens: a live manager/warden account
 * with an access row for at least one of the owner's PGs.
 *
 * It deliberately no longer requires users.hostel_id to be the owner's CURRENT PG. That column
 * is where the staff member is working right now, and they may have switched to another of the
 * owner's PGs; the owner must still be able to reset their password or deactivate them from any
 * PG they share.
 *
 * Both reads run under the owner's RLS session, and each is a check in its own right:
 *  • users_select only shows an owner the staff rows whose active PG is one of theirs;
 *  • staff_hostel_access only shows an owner the rows for their own PGs, and the query is pinned
 *    to those ids as well.
 * The admin-client helpers the callers then use (regeneratePassword, setAccountStatus) act on the
 * id returned here and nothing else.
 */
async function loadStaffUser(userId: string, ownedIds: Set<string>) {
  if (ownedIds.size === 0) return null;
  const supabase = await createClient();
  const [{ data: member }, { data: access }] = await Promise.all([
    supabase
      .from("users")
      .select("id, role, full_name, email, status")
      .eq("id", userId)
      .in("role", ["manager", "warden"])
      .is("deleted_at", null)
      .maybeSingle(),
    supabase.from("staff_hostel_access").select("hostel_id").eq("user_id", userId).in("hostel_id", [...ownedIds]).limit(1),
  ]);
  if (!member || !access?.length) return null;
  return member as { id: string; role: "manager" | "warden"; full_name: string; email: string | null; status: "active" | "inactive" };
}

export async function resetStaffPassword(input: { userId: string }): Promise<ActionResult<StaffCredentials>> {
  const parsed = staffIdSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { user, ctx } = await assertWritableContext("owner");
    const rl = await rateLimit(`owner:staff:${user.id}`, LIMITS.accountCreatePerUser.max, LIMITS.accountCreatePerUser.windowSeconds);
    if (!rl.allowed) return fail("Too many account operations in a short time. Please wait a bit and try again.");
    const staff = await loadStaffUser(parsed.data.userId, ownedHostelIds(ctx));
    if (!staff) return fail("That staff member is not yours.");
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
    const staff = await loadStaffUser(parsed.data.userId, ownedHostelIds(ctx));
    if (!staff) return fail("That staff member is not yours.");
    if (staff.status === parsed.data.status) return ok(undefined);
    // Account-wide on purpose: deactivating takes away EVERY PG (users.status gates them all);
    // taking away one PG is setStaffHostels(). The role-limit trigger fires on reactivation and
    // returns a friendly error if one of their PGs is already full.
    await setAccountStatus(staff.id, parsed.data.status);
    await audit("owner.staff.status", { targetType: "user", targetId: staff.id, hostelId: ctx.hostel.id, meta: { role: staff.role, status: parsed.data.status } });
    revalidatePath("/owner/staff");
    revalidatePath("/owner");
    return ok(undefined, parsed.data.status === "inactive" ? `${ROLE_LABEL[staff.role]} deactivated` : `${ROLE_LABEL[staff.role]} reactivated`);
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/**
 * Replace the PGs a manager/warden may work in (owner_set_staff_hostels).
 *
 * The RPC is the guard, run as the owner's own session: it refuses a PG the caller does not own,
 * a staff member who is not theirs, and a PG already at its five-per-role limit, and when their
 * current PG is removed it moves them to the first remaining one by name. The checks here only
 * turn the common mistakes into a message before the round trip.
 */
export async function setStaffHostels(input: { userId: string; hostelIds: string[] }): Promise<ActionResult<{ hostelIds: string[]; activeHostelId: string | null }>> {
  const parsed = staffHostelsSchema.safeParse(input);
  if (!parsed.success) {
    const fe = parsed.error.flatten().fieldErrors;
    return fail(firstIssue(fe, "Choose at least one PG."), fe as Record<string, string[]>);
  }
  try {
    const { user, ctx } = await assertWritableContext("owner");
    const rl = await rateLimit(`owner:staff:${user.id}`, LIMITS.accountCreatePerUser.max, LIMITS.accountCreatePerUser.windowSeconds);
    if (!rl.allowed) return fail("Too many account operations in a short time. Please wait a bit and try again.");
    const owned = ownedHostelIds(ctx);
    const hostelIds = [...new Set(parsed.data.hostelIds)];
    if (hostelIds.some((id) => !owned.has(id))) return fail("You can only give access to your own PGs.");
    const staff = await loadStaffUser(parsed.data.userId, owned);
    if (!staff) return fail("That staff member is not yours.");

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("owner_set_staff_hostels", { p_user_id: staff.id, p_hostel_ids: hostelIds });
    if (error) return fail(errorMessage(error));
    const rows = (data ?? []) as { hostel_id: string; is_active: boolean }[];
    const activeHostelId = rows.find((r) => r.is_active)?.hostel_id ?? null;
    // No audit() here: the RPC records owner.staff.hostels itself, with the before and after
    // lists, and only when something actually changed.
    revalidatePath("/owner/staff");
    revalidatePath("/owner");
    return ok({ hostelIds: rows.map((r) => r.hostel_id), activeHostelId }, "PG access saved");
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
    if (!manager) return fail("Add a manager first. Tasks go to an active manager of this PG.");

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
