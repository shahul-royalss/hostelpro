"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { assertRole, errorMessage } from "@/lib/permissions";
import { fail, ok, type ActionResult } from "@/lib/types";

const ackSchema = z.object({ alertId: z.number().int().positive() });

/**
 * Mark a security alert as seen.
 *
 * Goes through the ack_security_alert() RPC rather than a table UPDATE: security_alerts has
 * no INSERT/UPDATE/DELETE policy at all, because anyone able to edit or delete an alert could
 * erase the evidence of their own activity. The RPC re-checks super-admin / owner itself, so
 * this is enforced in the database, not just here.
 */
export async function acknowledgeAlert(input: { alertId: number }): Promise<ActionResult> {
  const parsed = ackSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    await assertRole("super_admin", "owner");
    const supabase = await createClient();
    const { error } = await supabase.rpc("ack_security_alert", { p_alert_id: parsed.data.alertId });
    if (error) return fail(errorMessage(error));
    revalidatePath("/super-admin/security");
    revalidatePath("/owner");
    return ok(undefined, "Alert acknowledged");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
