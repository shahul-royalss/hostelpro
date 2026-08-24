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
  status: "active" | "suspended";
  /** false when the hostel is suspended or the subscription has lapsed → all writes blocked. */
  writable: boolean;
  latestSubscriptionEnd: string | null;
}

/**
 * Load a hostel and compute its writability the same way app.hostel_writable() does:
 * hostels.status = 'active' AND the newest subscription's end_date has not passed.
 * Dates are compared as YYYY-MM-DD strings in UTC, which is the calendar day Postgres
 * current_date reports on a Supabase instance.
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
    .order("end_date", { ascending: false })
    .limit(1)
    .maybeSingle();

  const row = hostel as { id: string; name: string; status: "active" | "suspended" };
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
 * The owner-path gate: the caller must be the registered owner of THIS hostel.
 *
 * One message for "no such hostel" and for "not yours", deliberately: a distinguishable
 * response would turn this endpoint into an oracle for which hostel ids exist.
 */
export async function requireOwnedHostel(caller: Caller, hostelId: string): Promise<HostelContext> {
  const { data, error } = await serviceClient()
    .from("hostels")
    .select("id")
    .eq("id", hostelId)
    .eq("owner_user_id", caller.id)
    .maybeSingle();
  if (error) {
    console.error("[nivora] ownership check failed:", error.message);
    throw new HttpError(500, "Could not verify the hostel. Please try again.");
  }
  if (!data) throw new HttpError(403, "Hostel not found.");

  const hostel = await loadHostel(hostelId);
  if (!hostel) throw new HttpError(403, "Hostel not found.");
  return hostel;
}

/** The warden/manager-path gate: the tenant is whatever users.hostel_id says, never the body. */
export async function requireOwnHostel(caller: Caller): Promise<HostelContext> {
  if (!caller.hostelId) throw new HttpError(403, "No hostel is linked to your account.");
  const hostel = await loadHostel(caller.hostelId);
  if (!hostel) throw new HttpError(403, "No hostel is linked to your account.");
  return hostel;
}
