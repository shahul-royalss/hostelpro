"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { ACTIVE_HOSTEL_COOKIE, assertRole, errorMessage, getSessionUser } from "@/lib/permissions";
import { fail, ok, type ActionResult, type NotificationRow } from "@/lib/types";
import { ROLE_HOME } from "@/lib/roles";
import { audit } from "@/lib/audit";

export async function signOut() {
  const supabase = await createClient();
  const user = await getSessionUser();
  if (user) await audit("auth.logout", { targetType: "user", targetId: user.id });
  // scope 'global' revokes every refresh token for this user (all devices), not just this cookie
  await supabase.auth.signOut({ scope: "global" });
  const cookieStore = await cookies();
  cookieStore.delete(ACTIVE_HOSTEL_COOKIE);
  redirect("/login");
}

/**
 * Owner: switch the active hostel (multi-subscription owners). Owner-only by assertRole: staff
 * switch through switchStaffHostel() below, and the shell never offers them this one.
 */
export async function switchHostel(hostelId: string): Promise<ActionResult> {
  try {
    const user = await assertRole("owner");
    const supabase = await createClient();
    const { data } = await supabase.from("hostels").select("id").eq("id", hostelId).eq("owner_user_id", user.id).maybeSingle();
    if (!data) return fail("That hostel isn't linked to your account.");
    const cookieStore = await cookies();
    cookieStore.set(ACTIVE_HOSTEL_COOKIE, hostelId, {
      path: "/",
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      maxAge: 60 * 60 * 24 * 365,
    });
    revalidatePath("/owner", "layout");
    return ok(undefined);
  } catch (e) {
    return fail(errorMessage(e));
  }
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Manager / warden: switch the PG they are working in, then go to their home screen.
 *
 * NOT the owner mechanism above. An owner's active hostel is a cookie on this browser; a staff
 * member's is users.hostel_id, because every RLS policy scopes staff through
 * app.user_hostel_id(). staff_switch_hostel moves it, and only to a PG in the caller's own
 * staff_hostel_access rows, so the access decision is made in Postgres, not here. The
 * consequence users must understand: the column is shared, so switching here switches every
 * device the account is signed in on. Forms still open on those devices are caught by the stale
 * form guard (assertWritableContextFor).
 *
 * Redirects on success (home, because the page the user was on belongs to the PG they just
 * left); returns an error result otherwise.
 */
export async function switchStaffHostel(hostelId: string): Promise<ActionResult> {
  let home: string;
  try {
    const user = await assertRole("manager", "warden");
    if (typeof hostelId !== "string" || !UUID_RE.test(hostelId)) return fail("Choose a PG to switch to.");
    home = ROLE_HOME[user.role];
    if (hostelId !== user.hostel_id) {
      const supabase = await createClient();
      // The RPC writes the staff.hostel.switch audit row itself (and rate-limits switching), so
      // nothing is audited here: a second row for the same switch would only be noise in the trail.
      const { error } = await supabase.rpc("staff_switch_hostel", { p_hostel_id: hostelId });
      if (error) return fail(errorMessage(error));
    }
  } catch (e) {
    return fail(errorMessage(e));
  }
  // Outside the try: redirect() throws to unwind and must not be caught as a failure. The layout
  // is revalidated too, because the shell (PG name, switcher) is rendered by it and an App Router
  // layout is otherwise kept across the navigation.
  revalidatePath(home, "layout");
  redirect(home);
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
