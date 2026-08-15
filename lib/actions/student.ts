"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { assertWritableContext, errorMessage, PermissionError } from "@/lib/permissions";
import { uploadToBucket } from "@/lib/storage";
import { fail, ok, type ActionResult } from "@/lib/types";
import { applyLeaveSchema, createComplaintSchema } from "@/lib/validators/student";

async function myStudentId(supabase: Awaited<ReturnType<typeof createClient>>, userId: string): Promise<string> {
  const { data } = await supabase
    .from("students")
    .select("id")
    .eq("user_id", userId)
    .neq("status", "vacated")
    .maybeSingle();
  const id = (data as { id: string } | null)?.id;
  if (!id) throw new PermissionError("Your student record could not be found. Contact your warden.");
  return id;
}

/**
 * ST-4 — raise a complaint (FormData: category, title, description, photo?).
 * RLS: complaints_insert (student_id = own, hostel_id = own hostel, writable).
 * Trigger writes the first complaint_event + notifies owner/warden.
 */
export async function createComplaint(formData: FormData): Promise<ActionResult<{ photoSkipped: boolean }>> {
  const parsed = createComplaintSchema.safeParse({
    category: formData.get("category"),
    title: formData.get("title"),
    description: formData.get("description") ?? "",
  });
  if (!parsed.success) return fail("Please check the form.", parsed.error.flatten().fieldErrors);

  try {
    const { user, ctx } = await assertWritableContext("student");
    const supabase = await createClient();
    const studentId = await myStudentId(supabase, user.id);

    const photo = formData.get("photo");
    let photoUrl: string | null = null;
    let photoSkipped = false;
    if (photo instanceof File && photo.size > 0) {
      try {
        photoUrl = await uploadToBucket("complaint-photos", ctx.hostel.id, "complaints", photo);
      } catch (e) {
        // Missing service key / storage error: still file the complaint, just without the photo.
        const msg = errorMessage(e);
        if (/SERVICE_ROLE_KEY|not set/i.test(msg)) photoSkipped = true;
        else return fail(msg);
      }
    }

    const { error } = await supabase.from("complaints").insert({
      hostel_id: ctx.hostel.id,
      student_id: studentId,
      category: parsed.data.category,
      title: parsed.data.title,
      description: parsed.data.description || null,
      photo_url: photoUrl,
      updated_by: user.id,
    });
    if (error) return fail(errorMessage(error));

    revalidatePath("/student/complaints");
    revalidatePath("/student");
    revalidatePath("/warden/complaints");
    revalidatePath("/owner/complaints");
    return ok(
      { photoSkipped },
      photoSkipped ? "Complaint submitted (photo could not be attached right now)" : "Complaint submitted",
    );
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Student leave request → pending; warden decides (§6.5). RLS: leaves_insert. */
export async function applyLeave(input: { fromDate: string; toDate: string; reason: string }): Promise<ActionResult> {
  const parsed = applyLeaveSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the dates and reason.", parsed.error.flatten().fieldErrors);

  try {
    const { user, ctx } = await assertWritableContext("student");
    const supabase = await createClient();
    const studentId = await myStudentId(supabase, user.id);

    const { error } = await supabase.from("leaves").insert({
      hostel_id: ctx.hostel.id,
      student_id: studentId,
      from_date: parsed.data.fromDate,
      to_date: parsed.data.toDate,
      reason: parsed.data.reason,
    });
    if (error) return fail(errorMessage(error));

    revalidatePath("/student/leave");
    revalidatePath("/warden/leaves");
    revalidatePath("/warden");
    return ok(undefined, "Leave request sent to your warden");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
