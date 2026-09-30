/**
 * Tenant checks — "is this hostel yours, and may anyone write to it right now?"
 *
 * WHY THESE ARE HERE AND NOT LEFT TO THE DATABASE. Creating a staff account is one of the few
 * writes that genuinely needs the service role (auth.admin.createUser, then the public.users
 * insert), and the service role bypasses RLS. So for that path the policy that would normally
 * answer "which hostel may this owner touch" never runs. The web app has the same gap and
 * closes it the same way, in assertWritableContext() before it reaches for the admin client.
 *
 * The hostel id therefore comes from the client on the owner path (an owner may hold several)
 * and is verified here against hostels.owner_user_id; it is never taken on trust. On the warden
 * path it is not accepted from the client at all — users.hostel_id is used.
 */
import { HttpError } from "./http.ts";
import { serviceClient } from "./supabase.ts";
import { todayIso } from "./validate.ts";
import type { Caller } from "./caller.ts";

export interface HostelContext {
  id: string;
  name: string;
  status: "active" | "suspended" | "readonly";
  /**
   * false when the hostel is suspended, read-only, or its plan has lapsed or been cancelled →
   * all writes blocked.
   */
  writable: boolean;
  latestSubscriptionEnd: string | null;
}

/**
 * Load a hostel and compute its writability the same way app.hostel_writable() does:
 * hostels.status = 'active' AND the newest UNCANCELLED subscription's end_date has not passed.
 * Dates are compared as YYYY-MM-DD strings in UTC, which is the calendar day Postgres
 * current_date reports on a Supabase instance.
 *
 * THE cancelled_at FILTER IS LOAD-BEARING, and it was missing until 2026-09-19. A plan the Super
 * Admin cancels usually still has months to run, so without it the newest row's end_date is a
 * future date and this reads a cancelled hostel as writable — while app.subscription_state(),
 * which every RLS policy consults, already calls it expired. The service role bypasses RLS on
 * exactly the paths that import this file (creating staff, registering a resident, re-issuing a
 * resident's login, uploading a complaint photo), so this function is the only thing standing
 * between them and a hostel the database has already closed. See
 * db/migrations/2026-09-16-sa-hostel-controls.sql, which added the column and the table guard
 * that keeps hostels.status honest for the same reason.
 */
async function loadHostel(hostelId: string): Promise<HostelContext | null> {
  const admin = serviceClient();
  const { data: hostel, error } = await admin
    .from("hostels")
    .select("id, name, status, owner_user_id")
    .eq("id", hostelId)
    .maybeSingle();
  if (error) {
    console.error("[nivora] hostel lookup failed:", error.message);
    throw new HttpError(500, "Could not load the hostel. Please try again.");
  }
  if (!hostel) return null;

  const { data: sub } = await admin
    .from("subscriptions")
    .select("end_date")
    .eq("hostel_id", hostelId)
    .is("cancelled_at", null)
    .order("end_date", { ascending: false })
    .limit(1)
    .maybeSingle();

  const row = hostel as { id: string; name: string; status: "active" | "suspended" | "readonly" };
  const end = (sub as { end_date: string } | null)?.end_date ?? null;
  return {
    id: row.id,
    name: row.name,
    status: row.status,
    latestSubscriptionEnd: end,
    writable: row.status === "active" && end !== null && end >= todayIso(),
  };
}

/** Throws the same two messages the web app's assertWritable() throws. */
export function assertWritable(hostel: HostelContext): void {
  if (hostel.writable) return;
  if (hostel.status === "suspended") throw new HttpError(403, "This hostel is suspended. Contact NIVORA support.");
  throw new HttpError(403, "Subscription expired — the hostel is read-only until it is renewed.");
}

/**
 * Every EXTRA PG in a multi-PG request must be open for writes too, checked BEFORE any account is
 * created. The database refuses access to a read-only or suspended PG as well (the guard on
 * staff_hostel_access), but only after the auth user exists and has to be rolled back, and its
 * sentence cannot name the PG. Here the owner gets a form error that says which PG is the problem.
 * The first PG is not checked here: it is the loaded [HostelContext] and goes through
 * assertWritable, whose two sentences the apps already know.
 */
export async function assertExtraHostelsWritable(all: readonly OwnedHostel[]): Promise<void> {
  for (const h of all.slice(1)) {
    const ctx = await loadHostel(h.id);
    if (!ctx) throw new HttpError(403, "Hostel not found.");
    if (!ctx.writable) {
      const why = ctx.status === "suspended" ? "suspended" : "read-only";
      throw new HttpError(403, `${h.name} is ${why}, so no one can be given access to it.`);
    }
  }
}

/** A PG the caller has been proved to own. Enough to name it in a message; not a write gate. */
export interface OwnedHostel {
  id: string;
  name: string;
}

/**
 * The owner-path gate: the caller must be the registered owner of THIS hostel.
 *
 * One message for "no such hostel" and for "not yours", deliberately: a distinguishable
 * response would turn this endpoint into an oracle for which hostel ids exist.
 */
export async function requireOwnedHostel(caller: Caller, hostelId: string): Promise<HostelContext> {
  return (await requireOwnedHostels(caller, [hostelId])).first;
}

/**
 * [requireOwnedHostel] for several PGs at once. Every id must be one of the caller's, or the
 * whole request is refused with the same "Hostel not found." It never says WHICH id failed:
 * naming the bad one would be the same oracle the single-id gate refuses to be, one id at a time.
 *
 * ONE ownership query for the whole list, not one per id. owner-create-staff accepts up to 20
 * PGs, and three round trips each would be sixty before any work is done.
 *
 * Only the FIRST id is loaded as a full [HostelContext], because only the first is written to:
 * owner-create-staff makes it the new account's users.hostel_id, which is the row the
 * users_insert policy checks with app.hostel_writable(). The others get access rows only, and
 * an access row grants no write by itself: every write policy still checks
 * app.hostel_writable() on the PG the staff member is working in at the time.
 *
 * Ids are compared lowercased because Postgres returns uuids lowercased and accepts them in
 * any case. Without that, a client sending an uppercase id that today's single-id path accepts
 * would be told "Hostel not found." here.
 */
export async function requireOwnedHostels(
  caller: Caller,
  hostelIds: readonly string[],
): Promise<{ first: HostelContext; all: OwnedHostel[] }> {
  const wanted = hostelIds.map((id) => id.toLowerCase());
  if (!wanted.length) throw new HttpError(403, "Hostel not found.");

  const { data, error } = await serviceClient()
    .from("hostels")
    .select("id, name")
    .in("id", wanted)
    .eq("owner_user_id", caller.id);
  if (error) {
    console.error("[nivora] ownership check failed:", error.message);
    throw new HttpError(500, "Could not verify the hostel. Please try again.");
  }
  const owned = new Map(((data ?? []) as OwnedHostel[]).map((h) => [h.id.toLowerCase(), h]));
  const all: OwnedHostel[] = [];
  for (const id of wanted) {
    const hostel = owned.get(id);
    if (!hostel) throw new HttpError(403, "Hostel not found.");
    all.push(hostel);
  }

  const first = await loadHostel(all[0].id);
  if (!first) throw new HttpError(403, "Hostel not found.");
  return { first, all };
}

/**
 * The warden/manager-path gate: the tenant is whatever users.hostel_id says, never the body.
 *
 * ── STAFF WITH SEVERAL PGs ───────────────────────────────────────────────────────────────
 * Since public.staff_hostel_access, users.hostel_id is the PG a warden or manager is working
 * in NOW, one of possibly several they are allowed into. It still comes from the profile row,
 * never from the request, and apart from the Super Admin and the service role it only moves
 * under app.users_update_guard's rule: onto a PG the person holds an access row for (what
 * staff_switch_hostel does), or off a PG the owner takes away (owner_set_staff_hostels). So
 * following users.hostel_id here is still the right tenant.
 *
 * The access row is re-checked anyway, for managers and wardens, because of what the callers of
 * this function do next. They act with the SERVICE ROLE, which skips every RLS policy:
 * warden-student-credentials resets a resident's password with nothing in front of it but this
 * gate and a hostel_id predicate. The guard keeps users.hostel_id on a PG the person holds an
 * access row for only while the row is there; deleting an access row does not move
 * users.hostel_id. If one were ever deleted some other way (by hand, by the service role, by a
 * future bug), this function would otherwise let the warden act in a PG the owner has taken away
 * from them. app.user_hostel_id() makes the same test, but only inside RLS, and the service role
 * never evaluates it, so it protects none of these paths. The check costs one indexed lookup.
 *
 * Students and owners have no access rows and are not checked: a resident's hostel is fixed at
 * registration, and owners come through [requireOwnedHostel] instead.
 *
 * DEPLOY ORDER: the staff_hostel_access migration must be applied before any function that
 * imports this file is deployed. Without the table this lookup fails, and every warden call
 * answers "Could not verify the hostel."
 */
export async function requireOwnHostel(caller: Caller): Promise<HostelContext> {
  if (!caller.hostelId) throw new HttpError(403, "No hostel is linked to your account.");
  if (caller.role === "manager" || caller.role === "warden") {
    await requireStaffAccess(caller.id, caller.hostelId);
  }
  const hostel = await loadHostel(caller.hostelId);
  if (!hostel) throw new HttpError(403, "No hostel is linked to your account.");
  return hostel;
}

/** Mirrors the access-row test in app.user_hostel_id(). See [requireOwnHostel] for why. */
async function requireStaffAccess(userId: string, hostelId: string): Promise<void> {
  const { data, error } = await serviceClient()
    .from("staff_hostel_access")
    .select("hostel_id")
    .eq("user_id", userId)
    .eq("hostel_id", hostelId)
    .maybeSingle();
  if (error) {
    console.error("[nivora] staff access check failed:", error.message);
    throw new HttpError(500, "Could not verify the hostel. Please try again.");
  }
  if (!data) throw new HttpError(403, "You no longer have access to this PG.");
}
