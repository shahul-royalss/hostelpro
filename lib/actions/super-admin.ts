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
  updateHostelStructureSchema,
  type CreateOwnerHostelInput,
  type RegenerateOwnerPasswordInput,
  type RenewSubscriptionInput,
  type SetHostelStatusInput,
  type UpdateHostelStructureInput,
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
 *  • owner.mode = "new"      → 1. create the owner auth user + users row (service role, via lib/auth/accounts)
 *                              2. sa_create_hostel_with_subscription → hostel + subscription + scaffold, atomically
 *                              3. on RPC failure roll the auth user back (users row cascade-deletes)
 *  • owner.mode = "existing" → a second hostel + subscription under an owner account that already exists
 *                              (§4.1) — no new login, so no credentials are issued.
 */
export async function createOwnerAndHostel(
  input: CreateOwnerHostelInput,
): Promise<ActionResult<{ hostelId: string; credentials: IssuedCredentials | null }>> {
  const parsed = createOwnerHostelSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the highlighted fields.", parsed.error.flatten().fieldErrors);
  const { owner, hostel, subscription } = parsed.data;

  try {
    const user = await assertRole("super_admin");
    const supabase = await createClient();

    const rpcArgs = {
      p_hostel_name: hostel.name,
      p_floors: hostel.floors,
      p_rooms: hostel.rooms,
      p_address: hostel.address?.trim() || null,
      p_start_date: subscription.startDate,
      p_end_date: subscription.endDate,
      p_amount: subscription.amount,
      p_notes: subscription.notes?.trim() || null,
      p_beds_per_room: hostel.bedsPerRoom,
    };

    /* ── Existing owner: just the hostel + subscription ── */
    if (owner.mode === "existing") {
      const { data: existing, error: ownerErr } = await supabase
        .from("users")
        .select("id, full_name, status")
        .eq("id", owner.ownerUserId)
        .eq("role", "owner")
        .is("deleted_at", null)
        .maybeSingle();
      if (ownerErr) return fail(errorMessage(ownerErr));
      if (!existing) return fail("Owner account not found.");
      if ((existing as { status: string }).status !== "active") return fail("This owner account is inactive — reactivate it before adding a hostel.");

      const { data, error } = await supabase.rpc("sa_create_hostel_with_subscription", { p_owner_user_id: owner.ownerUserId, ...rpcArgs });
      const hostelId = typeof data === "string" ? data : null;
      if (error || !hostelId) return fail(errorMessage(error ?? new Error("Could not create the hostel.")));

      revalidateSuperAdmin(hostelId);
      return ok({ hostelId, credentials: null }, `${hostel.name} created`);
    }

    /* ── New owner: auth user first, then hostel + subscription ── */
    if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return fail(SERVICE_KEY_MISSING);

    const account = await createStaffAccount({
      role: "owner",
      fullName: owner.name,
      email: owner.email,
      phone: owner.phone,
      hostelId: null,
      createdBy: user.id,
    });

    const { data, error } = await supabase.rpc("sa_create_hostel_with_subscription", { p_owner_user_id: account.userId, ...rpcArgs });
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

/**
 * Hard rule §4.2 — only the Super Admin can change floor / room counts after creation.
 * Grow-only: floors and rooms may only increase (shrinking would orphan occupied rooms/beds).
 * Updates hostels.total_floors / total_rooms, then re-runs scaffold_hostel, which is idempotent
 * (ON CONFLICT DO NOTHING) — existing floors/rooms/beds are untouched, only the new ones are added.
 */
export async function updateHostelStructure(input: UpdateHostelStructureInput): Promise<ActionResult<{ floors: number; rooms: number }>> {
  const parsed = updateHostelStructureSchema.safeParse(input);
  if (!parsed.success) return fail("Please check the highlighted fields.", parsed.error.flatten().fieldErrors);
  const { hostelId, floors, rooms } = parsed.data;
  try {
    await assertRole("super_admin");
    const supabase = await createClient();
    const { data: row, error: readErr } = await supabase
      .from("hostels")
      .select("id, total_floors, total_rooms, beds_per_room_default")
      .eq("id", hostelId)
      .maybeSingle();
    if (readErr) return fail(errorMessage(readErr));
    if (!row) return fail("Hostel not found.");
    const current = row as { total_floors: number; total_rooms: number; beds_per_room_default: number };

    if (floors < current.total_floors) return fail(`Floors can only be increased (currently ${current.total_floors}).`);
    if (rooms < current.total_rooms) return fail(`Rooms can only be increased (currently ${current.total_rooms}).`);
    if (floors === current.total_floors && rooms === current.total_rooms) return fail("Nothing to change — the structure is already set to these values.");

    const { error: updErr } = await supabase.from("hostels").update({ total_floors: floors, total_rooms: rooms }).eq("id", hostelId);
    if (updErr) return fail(errorMessage(updErr));

    const { error: scaffoldErr } = await supabase.rpc("scaffold_hostel", {
      p_hostel_id: hostelId,
      p_floors: floors,
      p_rooms: rooms,
      p_beds_per_room: current.beds_per_room_default,
    });
    if (scaffoldErr) return fail(errorMessage(scaffoldErr));

    revalidateSuperAdmin(hostelId);
    return ok({ floors, rooms }, "Hostel structure updated");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
