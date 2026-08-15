"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { assertRole, errorMessage } from "@/lib/permissions";
import { createStaffAccount, deleteAuthUser, regeneratePassword, syncHostelMetadata } from "@/lib/auth/accounts";
import { fail, ok, type ActionResult } from "@/lib/types";
import {
  createOwnerHostelSchema,
  regenerateOwnerPasswordSchema,
  renewSubscriptionSchema,
  setHostelStatusSchema,
  type CreateOwnerHostelInput,
  type RegenerateOwnerPasswordInput,
  type RenewSubscriptionInput,
  type SetHostelStatusInput,
} from "@/lib/validators/super-admin";

const SERVICE_KEY_MISSING = "Service role key not configured — add SUPABASE_SERVICE_ROLE_KEY to .env.local";

export interface IssuedCredentials {
  name: string;
  loginId: string;
  password: string;
}

function revalidateSuperAdmin(hostelId?: string) {
  revalidatePath("/super-admin");
  revalidatePath("/super-admin/hostels");
  revalidatePath("/super-admin/subscriptions");
  if (hostelId) revalidatePath(`/super-admin/hostels/${hostelId}`);
}

/**
 * SA-2 wizard submit (Hard rules §4.1, §4.2, §4.9):
 *  1. create the owner auth user + users row (service role, via lib/auth/accounts)
 *  2. sa_create_hostel_with_subscription → hostel + subscription + scaffold, atomically
 *  3. on RPC failure roll the auth user back (users row cascade-deletes)
 */
export async function createOwnerAndHostel(
  input: CreateOwnerHostelInput,
): Promise<ActionResult<{ hostelId: string; credentials: IssuedCredentials }>> {
  const parsed = createOwnerHostelSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the highlighted fields.", parsed.error.flatten().fieldErrors);
  const { owner, hostel, subscription } = parsed.data;

  try {
    const user = await assertRole("super_admin");
    if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return fail(SERVICE_KEY_MISSING);

    const account = await createStaffAccount({
      role: "owner",
      fullName: owner.name,
      email: owner.email,
      phone: owner.phone,
      hostelId: null,
      createdBy: user.id,
    });

    const supabase = await createClient();
    const { data, error } = await supabase.rpc("sa_create_hostel_with_subscription", {
      p_owner_user_id: account.userId,
      p_hostel_name: hostel.name,
      p_floors: hostel.floors,
      p_rooms: hostel.rooms,
      p_address: hostel.address?.trim() || null,
      p_start_date: subscription.startDate,
      p_end_date: subscription.endDate,
      p_amount: subscription.amount,
      p_notes: subscription.notes?.trim() || null,
      p_beds_per_room: hostel.bedsPerRoom,
    });
    const hostelId = typeof data === "string" ? data : null;
    if (error || !hostelId) {
      await deleteAuthUser(account.userId);
      return fail(errorMessage(error ?? new Error("Could not create the hostel.")));
    }

    try {
      await syncHostelMetadata(account.userId, hostelId);
    } catch {
      // metadata is a convenience mirror; users.hostel_id (set by the RPC) is the source of truth
    }

    revalidateSuperAdmin(hostelId);
    return ok(
      { hostelId, credentials: { name: owner.name, loginId: account.loginId, password: account.password } },
      `${hostel.name} created`,
    );
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Extend a hostel's subscription — inserts a new period row (history) via sa_renew_subscription. */
export async function renewSubscription(input: RenewSubscriptionInput): Promise<ActionResult<{ subscriptionId: string }>> {
  const parsed = renewSubscriptionSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the renewal details.", parsed.error.flatten().fieldErrors);
  try {
    await assertRole("super_admin");
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("sa_renew_subscription", {
      p_hostel_id: parsed.data.hostelId,
      p_new_end_date: parsed.data.newEndDate,
      p_amount: parsed.data.amount,
      p_notes: parsed.data.notes?.trim() || null,
    });
    if (error) return fail(errorMessage(error));
    revalidateSuperAdmin(parsed.data.hostelId);
    return ok({ subscriptionId: String(data ?? "") }, "Subscription renewed");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Suspend / unsuspend a hostel. Suspended ⇒ all tenant writes blocked (app.hostel_writable). */
export async function setHostelStatus(input: SetHostelStatusInput): Promise<ActionResult> {
  const parsed = setHostelStatusSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    await assertRole("super_admin");
    const supabase = await createClient();
    const { error } = await supabase.from("hostels").update({ status: parsed.data.status }).eq("id", parsed.data.hostelId);
    if (error) return fail(errorMessage(error));
    if (parsed.data.status === "active") {
      // if the subscription is still expired this flips it straight back to read-only
      await supabase.rpc("refresh_subscription_statuses");
    }
    revalidateSuperAdmin(parsed.data.hostelId);
    return ok(undefined, parsed.data.status === "suspended" ? "Hostel suspended" : "Hostel reactivated");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Issue a new temporary password for an owner (shown once). */
export async function regenerateOwnerPassword(input: RegenerateOwnerPasswordInput): Promise<ActionResult<IssuedCredentials>> {
  const parsed = regenerateOwnerPasswordSchema.safeParse(input);
  if (!parsed.success) return fail("Invalid request.");
  try {
    await assertRole("super_admin");
    if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return fail(SERVICE_KEY_MISSING);
    const supabase = await createClient();
    const { data: owner, error } = await supabase
      .from("users")
      .select("id, full_name, email, role")
      .eq("id", parsed.data.ownerUserId)
      .eq("role", "owner")
      .maybeSingle();
    if (error) return fail(errorMessage(error));
    if (!owner) return fail("Owner account not found.");
    const o = owner as { id: string; full_name: string; email: string | null };
    if (!o.email) return fail("This owner has no email on file.");

    const password = await regeneratePassword(o.id);
    return ok({ name: o.full_name, loginId: o.email, password }, "New password issued");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
