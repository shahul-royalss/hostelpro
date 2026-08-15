"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { ACTIVE_HOSTEL_COOKIE, assertRole, errorMessage, getSessionUser } from "@/lib/permissions";
import { fail, ok, type ActionResult, type NotificationRow } from "@/lib/types";

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  const cookieStore = await cookies();
  cookieStore.delete(ACTIVE_HOSTEL_COOKIE);
  redirect("/login");
}

/** Owner: switch the active hostel (multi-subscription owners). */
export async function switchHostel(hostelId: string): Promise<ActionResult> {
  try {
    const user = await assertRole("owner");
    const supabase = await createClient();
    const { data } = await supabase.from("hostels").select("id").eq("id", hostelId).eq("owner_user_id", user.id).maybeSingle();
    if (!data) return fail("That hostel isn't linked to your account.");
    const cookieStore = await cookies();
    cookieStore.set(ACTIVE_HOSTEL_COOKIE, hostelId, { path: "/", httpOnly: true, sameSite: "lax", maxAge: 60 * 60 * 24 * 365 });
    revalidatePath("/owner", "layout");
    return ok(undefined);
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Latest notifications for the bell */
export async function fetchNotifications(limit = 20): Promise<ActionResult<{ items: NotificationRow[]; unread: number }>> {
  try {
    const user = await getSessionUser();
    if (!user) return fail("Signed out");
    const supabase = await createClient();
    const [{ data: items }, { data: unread }] = await Promise.all([
      supabase.from("notifications").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(limit),
      supabase.rpc("rpc_unread_count"),
    ]);
    return ok({ items: (items ?? []) as NotificationRow[], unread: Number(unread ?? 0) });
  } catch (e) {
    return fail(errorMessage(e));
  }
}

export async function markNotificationsRead(ids?: string[]): Promise<ActionResult> {
  try {
    const user = await getSessionUser();
    if (!user) return fail("Signed out");
    const supabase = await createClient();
    let q = supabase.from("notifications").update({ read_at: new Date().toISOString() }).eq("user_id", user.id).is("read_at", null);
    if (ids && ids.length) q = q.in("id", ids);
    const { error } = await q;
    if (error) return fail(errorMessage(error));
    return ok(undefined);
  } catch (e) {
    return fail(errorMessage(e));
  }
}
