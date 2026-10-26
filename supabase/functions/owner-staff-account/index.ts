/**
 * POST /functions/v1/owner-staff-account
 *
 * What an OWNER can do to a manager's or warden's login once it exists
 * (docs/self-signup-onboarding-spec.md, Flow 5). One action:
 *
 *   { "action": "delete", "userId": "<uuid of the manager or warden>" }
 *
 * Permanent. public.svc_delete_staff_account (service role only, 2026-10-25 migration) does it in
 * ONE transaction and re-checks everything this function checks:
 *   - the caller is an active owner who owns a PG the target works in (users.hostel_id or any
 *     staff_hostel_access row); "not yours" and "does not exist" read the same;
 *   - the target is a manager or warden, never an owner, tenant or Super Admin;
 *   - their documents, external links, push devices, notifications and PG access go (files are
 *     queued for the storage-erasure drain by the triggers, the existing erasure path);
 *   - the profile becomes a tombstone ("Deleted staff member"), so every history row keeps its
 *     foreign key;
 *   - the GoTrue user is soft-deleted the way GoTrue does it: address and phone released,
 *     identities, factors, one-time tokens and sessions gone, banned. Signing in with the old
 *     login then answers "No account found", and the person can sign up later like anyone new.
 * It writes its own audit row (owner.staff.deleted).
 *
 * Deploy: npx supabase functions deploy owner-staff-account
 * Contract: docs/self-signup-api.md.
 */
import { requireCaller } from "../_shared/caller.ts";
import { dbError } from "../_shared/errors.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { enforceRateLimit } from "../_shared/ratelimit.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { requireVerifiedEmail } from "../_shared/verification.ts";

const MAX_BODY_BYTES = 2 * 1024;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const caller = await requireCaller(req, "owner");
    // Same gate as owner-create-staff: an owner who has not proved their address does not
    // change anyone else's login. Exempt for addresses that cannot receive mail.
    requireVerifiedEmail(caller);

    const body = await readJsonBody(req, MAX_BODY_BYTES);
    if (body["action"] !== "delete") throw new HttpError(400, "Unknown action.");
    const userId = typeof body["userId"] === "string" ? body["userId"].trim() : "";
    if (!UUID_RE.test(userId)) throw new HttpError(404, "Staff member not found.");
    if (userId === caller.id) throw new HttpError(400, "You cannot delete your own account here.");

    // Durable and fail-closed, per owner, shared with no other action.
    await enforceRateLimit("owner:staff-delete:" + caller.id);

    const { data, error } = await serviceClient().rpc("svc_delete_staff_account", {
      p_actor: caller.id,
      p_user: userId,
    });
    if (error) {
      const http = dbError(error, "Could not delete that account. Please try again.");
      // "Staff member not found." is a verdict, not a bad request.
      if (/Staff member not found/.test(error.message ?? "")) throw new HttpError(404, "Staff member not found.");
      throw http;
    }
    const result = (data ?? {}) as Record<string, unknown>;
    return ok({
      user_id: result["user_id"] ?? userId,
      role: result["role"] ?? null,
      already_deleted: result["already_deleted"] === true,
    }, "Account deleted.");
  } catch (err) {
    return toResponse(err);
  }
});
