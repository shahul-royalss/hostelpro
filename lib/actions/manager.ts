"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { assertHostelContext, assertWritableContext, errorMessage } from "@/lib/permissions";
import { signedUrl, uploadToBucket } from "@/lib/storage";
import { fail, ok, type ActionResult } from "@/lib/types";
import {
  expenseSchema,
  expenseUpdateSchema,
  idSchema,
  menuSchema,
  revenueSchema,
  revenueUpdateSchema,
  taskStatusSchema,
  type MenuCellInput,
  type RevenueInput,
  type TaskStatusInput,
} from "@/lib/validators/manager";

const FINANCE_PATHS = ["/manager", "/manager/expenses", "/manager/revenue", "/owner", "/owner/finance"];
function revalidateFinance() {
  FINANCE_PATHS.forEach((p) => revalidatePath(p));
}

function formValue(fd: FormData, key: string): string | undefined {
  const v = fd.get(key);
  return typeof v === "string" ? v : undefined;
}
function formFile(fd: FormData, key: string): File | null {
  const v = fd.get(key);
  return v instanceof File && v.size > 0 ? v : null;
}

/**
 * Upload a receipt if one was attached. When the storage service-role key is not
 * configured we still save the entry — the caller gets a warning to surface.
 */
async function tryUploadReceipt(hostelId: string, file: File | null): Promise<{ path: string | null; warning?: string }> {
  if (!file) return { path: null };
  try {
    return { path: await uploadToBucket("receipts", hostelId, "expenses", file) };
  } catch (e) {
    const msg = e instanceof Error ? e.message : "";
    if (/SERVICE_ROLE_KEY|not set/i.test(msg)) {
      return { path: null, warning: "Saved without the receipt — file storage isn't configured yet." };
    }
    throw e;
  }
}

/* ───────────────────────── Expenses (MG-2) ───────────────────────── */

export async function createExpense(formData: FormData): Promise<ActionResult<{ id: string }>> {
  const parsed = expenseSchema.safeParse({
    date: formValue(formData, "date"),
    category: formValue(formData, "category"),
    amount: formValue(formData, "amount"),
    note: formValue(formData, "note"),
  });
  if (!parsed.success) return fail("Please check the form.", parsed.error.flatten().fieldErrors);

  try {
    const { user, ctx } = await assertWritableContext("manager");
    const { path, warning } = await tryUploadReceipt(ctx.hostel.id, formFile(formData, "receipt"));

    const supabase = await createClient();
    const { data, error } = await supabase
      .from("expenses")
      .insert({
        hostel_id: ctx.hostel.id,
        date: parsed.data.date,
        category: parsed.data.category,
        amount: parsed.data.amount,
        note: parsed.data.note ?? null,
        receipt_url: path,
        uploaded_by: user.id,
      })
      .select("id")
      .single();
    if (error) return fail(errorMessage(error));

    revalidateFinance();
    return ok({ id: (data as { id: string }).id }, warning ?? "Expense saved");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function updateExpense(formData: FormData): Promise<ActionResult> {
  const parsed = expenseUpdateSchema.safeParse({
    id: formValue(formData, "id"),
    date: formValue(formData, "date"),
    category: formValue(formData, "category"),
    amount: formValue(formData, "amount"),
    note: formValue(formData, "note"),
    removeReceipt: formValue(formData, "removeReceipt") ?? "0",
  });
  if (!parsed.success) return fail("Please check the form.", parsed.error.flatten().fieldErrors);

  try {
    const { ctx } = await assertWritableContext("manager");
    const { path, warning } = await tryUploadReceipt(ctx.hostel.id, formFile(formData, "receipt"));

    const patch: Record<string, unknown> = {
      date: parsed.data.date,
      category: parsed.data.category,
      amount: parsed.data.amount,
      note: parsed.data.note ?? null,
    };
    if (path) patch.receipt_url = path;
    else if (parsed.data.removeReceipt === "1") patch.receipt_url = null;

    const supabase = await createClient();
    const { error, count } = await supabase
      .from("expenses")
      .update(patch, { count: "exact" })
      .eq("id", parsed.data.id)
      .eq("hostel_id", ctx.hostel.id)
      .is("deleted_at", null);
    if (error) return fail(errorMessage(error));
    if (!count) return fail("That expense no longer exists.");

    revalidateFinance();
    return ok(undefined, warning ?? "Expense updated");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Soft delete (Hard rule §4.10) — hard deletes are blocked by RLS. */
export async function deleteExpense(input: { id: string }): Promise<ActionResult> {
  const parsed = idSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { ctx } = await assertWritableContext("manager");
    const supabase = await createClient();
    const { error, count } = await supabase
      .from("expenses")
      .update({ deleted_at: new Date().toISOString() }, { count: "exact" })
      .eq("id", parsed.data.id)
      .eq("hostel_id", ctx.hostel.id)
      .is("deleted_at", null);
    if (error) return fail(errorMessage(error));
    if (!count) return fail("That expense no longer exists.");
    revalidateFinance();
    return ok(undefined, "Expense deleted");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Resolve a 1-hour signed URL for an expense receipt (looked up through RLS, never by raw path). */
export async function getReceiptUrl(input: { id: string }): Promise<ActionResult<{ url: string; isPdf: boolean }>> {
  const parsed = idSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { ctx } = await assertHostelContext("manager", "owner");
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("expenses")
      .select("receipt_url")
      .eq("id", parsed.data.id)
      .eq("hostel_id", ctx.hostel.id)
      .maybeSingle();
    if (error) return fail(errorMessage(error));
    const path = (data as { receipt_url: string | null } | null)?.receipt_url;
    if (!path) return fail("No receipt attached to this expense.");
    const url = await signedUrl("receipts", path);
    if (!url) return fail("Receipt can't be opened right now — file storage isn't configured.");
    return ok({ url, isPdf: /\.pdf(\?|$)/i.test(path) });
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── Revenue (MG-3) ───────────────────────── */

export async function createRevenue(input: RevenueInput): Promise<ActionResult<{ id: string }>> {
  const parsed = revenueSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the form.", parsed.error.flatten().fieldErrors);
  try {
    const { user, ctx } = await assertWritableContext("manager");
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("revenues")
      .insert({
        hostel_id: ctx.hostel.id,
        date: parsed.data.date,
        source: parsed.data.source,
        amount: parsed.data.amount,
        note: parsed.data.note ?? null,
        uploaded_by: user.id,
      })
      .select("id")
      .single();
    if (error) return fail(errorMessage(error));
    revalidateFinance();
    return ok({ id: (data as { id: string }).id }, "Revenue saved");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function updateRevenue(input: RevenueInput & { id: string }): Promise<ActionResult> {
  const parsed = revenueUpdateSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the form.", parsed.error.flatten().fieldErrors);
  try {
    const { ctx } = await assertWritableContext("manager");
    const supabase = await createClient();
    const { error, count } = await supabase
      .from("revenues")
      .update(
        { date: parsed.data.date, source: parsed.data.source, amount: parsed.data.amount, note: parsed.data.note ?? null },
        { count: "exact" },
      )
      .eq("id", parsed.data.id)
      .eq("hostel_id", ctx.hostel.id)
      .is("deleted_at", null);
    if (error) return fail(errorMessage(error));
    if (!count) return fail("That revenue entry no longer exists.");
    revalidateFinance();
    return ok(undefined, "Revenue updated");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function deleteRevenue(input: { id: string }): Promise<ActionResult> {
  const parsed = idSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { ctx } = await assertWritableContext("manager");
    const supabase = await createClient();
    const { error, count } = await supabase
      .from("revenues")
      .update({ deleted_at: new Date().toISOString() }, { count: "exact" })
      .eq("id", parsed.data.id)
      .eq("hostel_id", ctx.hostel.id)
      .is("deleted_at", null);
    if (error) return fail(errorMessage(error));
    if (!count) return fail("That revenue entry no longer exists.");
    revalidateFinance();
    return ok(undefined, "Revenue entry deleted");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── Tasks ───────────────────────── */

/**
 * Manager moves a task pending → in_progress → done (and back).
 * RLS + `tasks_before_update` trigger only allow the status column to change;
 * `tasks_after_change` notifies the owner.
 */
export async function updateTaskStatus(input: TaskStatusInput): Promise<ActionResult> {
  const parsed = taskStatusSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    const { user, ctx } = await assertWritableContext("manager");
    const supabase = await createClient();
    const { error, count } = await supabase
      .from("tasks")
      .update({ status: parsed.data.status }, { count: "exact" })
      .eq("id", parsed.data.taskId)
      .eq("hostel_id", ctx.hostel.id)
      .eq("assigned_to", user.id);
    if (error) return fail(errorMessage(error));
    if (!count) return fail("That task no longer exists.");
    revalidatePath("/manager");
    revalidatePath("/manager/tasks");
    revalidatePath("/owner/staff");
    const label = parsed.data.status === "done" ? "Task marked done" : parsed.data.status === "in_progress" ? "Task started" : "Task moved back to pending";
    return ok(undefined, label);
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/* ───────────────────────── Mess menu (MG-4) ───────────────────────── */

/** Upsert the whole weekly grid on (hostel_id, day_of_week, meal). */
export async function saveMenu(cells: MenuCellInput[]): Promise<ActionResult> {
  const parsed = menuSchema.safeParse(cells);
  if (!parsed.success) return fail("Please check the menu — one of the cells is too long.");
  try {
    const { user, ctx } = await assertWritableContext("manager");
    const supabase = await createClient();
    const rows = parsed.data.map((c) => ({
      hostel_id: ctx.hostel.id,
      day_of_week: c.day,
      meal: c.meal,
      items: c.items.trim(),
      updated_by: user.id,
    }));
    const { error } = await supabase.from("menus").upsert(rows, { onConflict: "hostel_id,day_of_week,meal" });
    if (error) return fail(errorMessage(error));
    revalidatePath("/manager/menu");
    revalidatePath("/student/menu");
    revalidatePath("/student");
    return ok(undefined, "Menu saved — students will see it in their app");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
