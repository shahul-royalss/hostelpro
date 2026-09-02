/**
 * POST /functions/v1/owner-create-staff
 *
 * An OWNER creates the Manager or Warden login for one of their hostels, from the phone.
 * Port of lib/actions/owner.ts → createStaff().
 *
 * ═══ TWO GATES, BECAUSE THE SERVICE ROLE SKIPS THE USUAL ONE ═══
 * Almost every write in this product is authorised by RLS: the policy on public.users already
 * says an owner may insert a manager/warden row only for a hostel they own and only while that
 * hostel is writable (db/rls-policies.sql, users_insert).
 *
 * This path cannot lean on that. Creating a login means auth.admin.createUser, which means the
 * service-role key, and the service role bypasses RLS — so the policy that would have answered
 * "is this hostel yours?" never runs. The web app has exactly the same gap and closes it the
 * same way, in assertWritableContext() before it reaches for the admin client. So:
 *
 *   1. requireCaller(req, "owner")  — the bearer token is verified with GoTrue and the ROLE is
 *      then read from public.users. Not from the request body, not from JWT app_metadata.
 *   2. requireOwnedHostel(caller, hostelId) — hostels.owner_user_id must be this caller. The
 *      hostel id is accepted from the client because an owner may hold several, and it is
 *      therefore verified rather than trusted. "Not yours" and "does not exist" return the
 *      same message, so this endpoint is not an oracle for which hostel ids are real.
 *   3. assertWritable(hostel) — suspended hostel, or lapsed subscription, means no writes.
 *      This mirrors app.hostel_writable(), which RLS would otherwise have enforced.
 *
 * ═══ WHAT THE DATABASE STILL DECIDES ═══
 * The service role bypasses RLS but NOT triggers. app.enforce_role_limits fires on the
 * public.users insert and refuses a second active manager or warden for the same hostel
 * (Hard rule §4.3), and the users_one_active_staff_per_hostel unique index settles the race
 * that the trigger's count(*) cannot. The count below is only a friendlier early message; the
 * trigger and the index are the actual rule.
 *
 * ═══ ROLLBACK ═══
 * If the public.users insert loses to that trigger or index, createStaffAccount deletes the
 * auth user again and — unlike the web version, which swallows a failed rollback — reports it
 * when that deletion itself fails, naming the orphaned auth user id so it can be cleaned up.
 * An auth user with no profile row cannot sign in usefully and permanently holds its email
 * address, so it must never be left behind silently.
 *
 * ═══ THE TEMPORARY PASSWORD ═══
 * Returned ONCE, in this response, with Cache-Control: no-store. Never stored, never logged,
 * never in the audit row.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy owner-create-staff        (see docs/edge-functions.md)
 */
import { createStaffAccount } from "../_shared/accounts.ts";
import { audit } from "../_shared/audit.ts";
import { requireCaller } from "../_shared/caller.ts";
import { dbError } from "../_shared/errors.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { enforceRateLimit } from "../_shared/ratelimit.ts";
import { callerClient } from "../_shared/supabase.ts";
import { requireVerifiedEmail } from "../_shared/verification.ts";
import { assertWritable, requireOwnedHostel } from "../_shared/tenant.ts";
import { normalizePhone, Validator } from "../_shared/validate.ts";

const MAX_BODY_BYTES = 32 * 1024;

/** Mirrors ROLE_LABEL in lib/roles.ts, so the app shows the same words the browser does. */
const ROLE_LABEL: Record<"manager" | "warden", string> = { manager: "Manager", warden: "Warden" };

/** Mirrors createStaffSchema in lib/validators/owner.ts. */
function parseBody(body: Record<string, unknown>) {
  const v = new Validator(body);
  const role = v.oneOf("role", ["manager", "warden"] as const, "Choose Manager or Warden.");
  const fullName = v.string("fullName", { min: 2, max: 80, message: "Enter the full name." });
  const email = v.email("email");
  const phone = v.optionalPhone("phone");
  // Optional: an owner with a single hostel does not have to send it — users.hostel_id is used.
  // An owner with several must, and whichever id arrives is verified against ownership.
  const hostelId = v.optionalUuid("hostelId", "Pick a hostel.");
  v.done();
  return { role, fullName, email, phone, hostelId };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const caller = await requireCaller(req, "owner");
    // See sa-create-owner: an account that has not proved its own address does not get to
    // create others. _shared/verification.ts holds the reasoning and the exemption.
    requireVerifiedEmail(caller);
    const input = parseBody(await readJsonBody(req, MAX_BODY_BYTES));

    // Tenant resolution: the body may name the hostel, but ownership is what decides.
    const hostelId = input.hostelId ?? caller.hostelId;
    if (!hostelId) throw new HttpError(403, "No hostel is linked to your account.");
    const hostel = await requireOwnedHostel(caller, hostelId);
    assertWritable(hostel);

    await enforceRateLimit("owner:staff:" + caller.id);

    // Friendly pre-check under the caller's own RLS. The trigger + unique index are the real
    // guard; this exists so the common case reads as a form error instead of a 409 after a
    // login has already been created and rolled back.
    const asCaller = callerClient(caller.jwt);
    const { count, error: countError } = await asCaller
      .from("users")
      .select("id", { count: "exact", head: true })
      .eq("hostel_id", hostel.id)
      .eq("role", input.role)
      .eq("status", "active")
      .is("deleted_at", null);
    if (countError) throw dbError(countError);
    if ((count ?? 0) >= 1) {
      throw new HttpError(
        409,
        "This hostel already has an active " + input.role + ". Deactivate the current " + input.role + " first.",
      );
    }

    const created = await createStaffAccount({
      role: input.role,
      fullName: input.fullName,
      email: input.email,
      phone: input.phone ? normalizePhone(input.phone) : null,
      hostelId: hostel.id,
      createdBy: caller.id,
    });

    await audit("owner.staff.create", caller, {
      targetType: "user",
      targetId: created.userId,
      hostelId: hostel.id,
      meta: { role: input.role, surface: "edge_function" },
    });

    return ok(
      {
        userId: created.userId,
        name: input.fullName,
        role: ROLE_LABEL[input.role],
        loginId: created.loginId,
        password: created.password,
      },
      ROLE_LABEL[input.role] + " account created",
    );
  } catch (e) {
    return toResponse(e);
  }
});
