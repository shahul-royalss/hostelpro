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
 *   1. requireCaller(req, "owner"): the bearer token is verified with GoTrue and the ROLE is
 *      then read from public.users. Not from the request body, not from JWT app_metadata.
 *   2. requireOwnedHostels(caller, hostelIds): hostels.owner_user_id must be this caller, for
 *      EVERY PG named. The ids are accepted from the client because an owner may hold several,
 *      and they are therefore verified rather than trusted. "Not yours" and "does not exist"
 *      return the same message, and one bad id refuses the whole request without saying which,
 *      so this endpoint is not an oracle for which hostel ids are real.
 *   3. assertWritable(first PG): suspended hostel, or lapsed subscription, means no writes.
 *      This mirrors app.hostel_writable(), which the users_insert policy would otherwise have
 *      applied to the row's hostel_id. Only the first PG becomes that hostel_id; see below.
 *
 * ═══ ONE PG OR SEVERAL ═══
 * An owner with two or more PGs may give a warden or manager access to several of them by
 * sending "hostelIds". The FIRST is where the account starts: it becomes users.hostel_id, the
 * active PG that every RLS policy scopes to through app.user_hostel_id(). The database's AFTER
 * INSERT trigger on public.users writes the access row for it, and createStaffAccount writes
 * the rest into public.staff_hostel_access. The warden then moves between them with
 * staff_switch_hostel, which only accepts a PG they hold an access row for.
 *
 * Without "hostelIds" nothing changed: one PG, taken from "hostelId" or else the owner's own
 * users.hostel_id. The live Android app sends exactly that shape and must keep working.
 *
 * ═══ WHAT THE DATABASE STILL DECIDES ═══
 * The service role bypasses RLS but NOT triggers. The database refuses the SIXTH active manager
 * or warden for a PG (Hard rule §4.3, five each since 2026-09-12), taking an advisory lock on
 * (hostel, role) before it counts so two simultaneous creates cannot both squeeze past four.
 * Since staff_hostel_access the count is staff WITH ACCESS to that PG, not staff currently
 * working in it, and it fires on the profile row and on every access row alike. The count below
 * is a friendlier early message; the database is the actual rule.
 *
 * ═══ ROLLBACK ═══
 * If the public.users insert or the access-row insert loses to that rule, createStaffAccount
 * deletes the auth user again (which cascades to the profile row and every access row) and,
 * unlike the web version, which swallows a failed rollback, reports it when that deletion
 * itself fails, naming the orphaned auth user id so it can be cleaned up. An auth user with no
 * profile row cannot sign in usefully and permanently holds its email address, so it must never
 * be left behind silently.
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
import { assertExtraHostelsWritable, assertWritable, requireOwnedHostels } from "../_shared/tenant.ts";
import { normalizePhone, Validator } from "../_shared/validate.ts";

const MAX_BODY_BYTES = 32 * 1024;

/**
 * The most PGs one request may grant. Far above any real owner today; it exists so a single
 * body cannot ask for hundreds of ownership checks and access rows.
 */
const MAX_HOSTELS = 20;

/**
 * How many active managers, and how many active wardens, one PG may have.
 *
 * MIRRORS THE DATABASE'S PER-PG STAFF LIMIT, WHICH IS THE ACTUAL RULE. The count below is a
 * friendlier early message so the common case reads as a form error instead of a refusal
 * arriving after a login has been created and rolled back. It was 1 until 2026-09-12; the owner
 * needed staff for a second PG and shift cover for the first. Since staff_hostel_access it counts
 * staff with access to the PG, as the database does. If these two numbers ever disagree, the
 * database wins and this one is a bug.
 */
const MAX_PER_ROLE = 5;

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
  // Optional, and newer: every PG this person may work in, the first being where they start.
  // When present it decides and hostelId is ignored. Deduplicated and lowercased by the
  // validator, so the same PG sent twice is one PG, not two access rows or two limit checks.
  const hostelIds = v.optionalUuidList("hostelIds", {
    max: MAX_HOSTELS,
    message: "Pick a hostel.",
    empty: "Choose at least one PG.",
    tooMany: "Choose " + MAX_HOSTELS + " PGs or fewer.",
  });
  v.done();
  return { role, fullName, email, phone, hostelId, hostelIds };
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

    // Tenant resolution: the body may name the PGs, but ownership is what decides. Without
    // hostelIds this is the old single-PG path, unchanged.
    const single = input.hostelId ?? caller.hostelId;
    const requested = input.hostelIds ?? (single ? [single] : []);
    if (!requested.length) throw new HttpError(403, "No hostel is linked to your account.");
    const { first: hostel, all: hostels } = await requireOwnedHostels(caller, requested);
    assertWritable(hostel);
    await assertExtraHostelsWritable(hostels);
    const grantedIds = hostels.map((h) => h.id);

    await enforceRateLimit("owner:staff:" + caller.id);

    // Friendly pre-check under the caller's own RLS. The database is the real guard; this
    // exists so the common case reads as a form error instead of a refusal after a login has
    // already been created and rolled back.
    //
    // It counts what the database counts: active, undeleted staff of this role WITH ACCESS to
    // each requested PG, wherever they happen to be working right now. `users!user_id` names
    // the foreign key, because staff_hostel_access has two to public.users (user_id and
    // granted_by) and an unhinted embed is refused as ambiguous. `!inner` makes the filters on
    // users drop the access row rather than merely empty the embed.
    //
    // Under the caller's RLS an owner sees the access rows of their own PGs and the users working
    // in their own PGs. Access is only ever granted within one owner's PGs, so nobody counted
    // here is hidden; and if someone ever were, the cost is an under-count, which only means the
    // database gives the refusal instead of this check.
    const asCaller = callerClient(caller.jwt);
    const { data: holders, error: countError } = await asCaller
      .from("staff_hostel_access")
      .select("hostel_id, users!user_id!inner(id)")
      .in("hostel_id", grantedIds)
      .eq("users.role", input.role)
      .eq("users.status", "active")
      .is("users.deleted_at", null);
    if (countError) throw dbError(countError);
    const held = new Map<string, number>();
    for (const row of (holders ?? []) as { hostel_id: string }[]) {
      held.set(row.hostel_id, (held.get(row.hostel_id) ?? 0) + 1);
    }
    const full = hostels.find((h) => (held.get(h.id) ?? 0) >= MAX_PER_ROLE);
    if (full) {
      // "This PG" when one was asked for, its name when several were, so the owner knows which
      // one to fix. Both keep the shape the apps recognise ("already has 5 active"), and the
      // wording matches the database's own refusal now that removing someone's access to the
      // PG frees a place as well as deactivating them.
      throw new HttpError(
        409,
        (hostels.length > 1 ? full.name : "This PG") +
          " already has " + MAX_PER_ROLE + " active " + input.role + "s. Remove one from it first.",
      );
    }

    const created = await createStaffAccount({
      role: input.role,
      fullName: input.fullName,
      email: input.email,
      phone: input.phone ? normalizePhone(input.phone) : null,
      hostelId: hostel.id,
      extraHostelIds: grantedIds.slice(1),
      createdBy: caller.id,
    });

    await audit("owner.staff.create", caller, {
      targetType: "user",
      targetId: created.userId,
      hostelId: hostel.id,
      meta: { role: input.role, hostelIds: grantedIds, surface: "edge_function" },
    });

    return ok(
      {
        userId: created.userId,
        name: input.fullName,
        role: ROLE_LABEL[input.role],
        loginId: created.loginId,
        password: created.password,
        // Every PG the account may work in, the first being the one it starts in. Always
        // present, one entry on the single-PG path, so a client never has to guess.
        hostelIds: grantedIds,
      },
      ROLE_LABEL[input.role] + " account created",
    );
  } catch (e) {
    return toResponse(e);
  }
});
