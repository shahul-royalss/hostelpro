"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { assertWritableContext, errorMessage } from "@/lib/permissions";
import { fail, ok, type ActionResult, type ComplaintStatus } from "@/lib/types";

const updateSchema = z.object({
  complaintId: z.string().uuid(),
  status: z.enum(["open", "in_progress", "resolved"]),
  resolutionNote: z.string().trim().max(2000).optional().nullable(),
});

/**
 * Shared by Owner (/owner/complaints) and Warden (/warden/complaints):
 * move a complaint through open → in_progress → resolved and/or add a note.
 * RLS: complaints_update (owner | warden of the hostel, writable subscription).
 * Trigger: writes complaint_events + notifies the student.
 */
export async function updateComplaintStatus(input: {
  complaintId: string;
  status: ComplaintStatus;
  resolutionNote?: string | null;
}): Promise<ActionResult> {
  const parsed = updateSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.", parsed.error.flatten().fieldErrors);
  try {
    const { user, ctx } = await assertWritableContext("owner", "warden");
    const supabase = await createClient();
    const patch: Record<string, unknown> = { status: parsed.data.status, updated_by: user.id };
    if (parsed.data.resolutionNote !== undefined) patch.resolution_note = parsed.data.resolutionNote || null;
    if (parsed.data.status === "resolved") patch.resolved_at = new Date().toISOString();

    const { error } = await supabase
      .from("complaints")
      .update(patch)
      .eq("id", parsed.data.complaintId)
      .eq("hostel_id", ctx.hostel.id);
    if (error) return fail(errorMessage(error));

    revalidatePath("/owner/complaints");
    revalidatePath("/owner");
    revalidatePath("/warden/complaints");
    revalidatePath("/warden");
    revalidatePath("/student/complaints");
    return ok(undefined, parsed.data.status === "resolved" ? "Complaint marked resolved" : "Complaint updated");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
