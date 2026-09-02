/**
 * POST /functions/v1/sa-create-owner
 *
 * The Super Admin creates an OWNER account and that owner's first hostel — from the phone,
 * without the service-role key ever being on the phone.
 *
 * Port of lib/actions/super-admin.ts → createOwnerAndHostel(). Same two branches, same
 * ordering, same database calls, same friendly messages. One deliberate difference, below.
 *
 * ═══ WHY THIS ENDPOINT EXISTS AT ALL ═══
 * Creating a login requires auth.admin.createUser, which requires the service-role key. That
 * key bypasses RLS for the whole project. An APK is a zip file: anything compiled into it, or
 * passed by --dart-define, or sitting in an env.dart, is a published secret. So the key lives
 * here, in a Deno process on Supabase's infrastructure, set with `supabase secrets set`, and
 * the phone holds only a user session. The phone asks; the server decides and acts.
 *
 * ═══ WHO IS ALLOWED — CHECKED AGAINST THE DATABASE, NOT THE TOKEN ═══
 * requireCaller(req, "super_admin") verifies the bearer token with GoTrue and then reads
 * public.users for the verified id using the service client. The role that authorises this
 * request comes from that ROW. Not from a `role` field in the JSON body, and not from the
 * JWT's app_metadata either — app_metadata is a service-role-writable mirror, and a JWT body
 * is base64, not evidence. Platform `verify_jwt` is left ON as an outer gate, but it is
 * satisfied by the anon key alone, so on its own it authorises nothing.
 *
 * Then the database checks a second time: sa_create_hostel_with_subscription is invoked
 * through the CALLER's client, so auth.uid() is the real Super Admin inside the RPC and its
 * own `if not app.is_super_admin()` guard runs. Calling it with the service key would satisfy
 * app.is_service_role() and skip precisely the guard worth keeping. It also means created_by
 * on the new hostel and subscription is the actual person instead of NULL.
 *
 * ═══ THE ROLLBACK, AND THE ONE DIFFERENCE FROM THE WEB VERSION ═══
 * Two systems are written in sequence and they cannot share a transaction: the auth user lives
 * in GoTrue, the hostel lives in Postgres. If the hostel RPC fails after the auth user exists,
 * the auth user has to be deleted again.
 *
 * The web version calls deleteAuthUser(), which swallows its own error — so a rollback that
 * ITSELF fails is indistinguishable from one that worked. What that leaves behind is an owner
 * login with no public.users row and no hostel: it cannot sign in usefully, nobody is told it
 * is there, and it holds the email address hostage, because GoTrue refuses to register that
 * address again. Retrying the wizard with the same email then fails with "already exists" and
 * the reason is invisible.
 *
 * Here the rollback's outcome is checked and, when it fails, REPORTED: HTTP 500, a message
 * naming the orphaned auth user id, and `rollback: { failed: true, orphanedAuthUserId }` in
 * the body so the app can surface it and somebody can delete that account by hand. A clean
 * failure is worth more than a quiet half-success.
 *
 * ═══ THE TEMPORARY PASSWORD ═══
 * Generated here, returned ONCE in this response, and never written to any table, log or audit
 * row. Every response carries Cache-Control: no-store; audit_event() strips password-ish keys
 * out of meta as a second line of defence. If the Super Admin loses it, the fix is to issue a
 * new one — there is nowhere to look the old one up.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy sa-create-owner
 * The secret it needs, and how to set it: docs/edge-functions.md. No secret value is in the repo.
 */
import { createStaffAccount, deleteAuthUser, rollbackAwareError, syncHostelMetadata } from "../_shared/accounts.ts";
import { audit } from "../_shared/audit.ts";
import { requireCaller } from "../_shared/caller.ts";
import { dbError } from "../_shared/errors.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { enforceRateLimit } from "../_shared/ratelimit.ts";
import { callerClient } from "../_shared/supabase.ts";
import { requireVerifiedEmail } from "../_shared/verification.ts";
import { normalizePhone, Validator } from "../_shared/validate.ts";

/** 64 KB. This payload is a handful of short strings and numbers, never a file. */
const MAX_BODY_BYTES = 64 * 1024;

interface HostelStep {
  name: string;
  floors: number;
  rooms: number;
  bedsPerRoom: number;
  address: string | null;
}

interface SubscriptionStep {
  startDate: string;
  endDate: string;
  amount: number;
  notes: string | null;
}

/**
 * Mirrors createOwnerHostelSchema in lib/validators/super-admin.ts field for field and message
 * for message. The whole payload is checked before anything is created, so a typo in the last
 * step cannot leave an auth user behind from the first.
 */
function parseBody(body: Record<string, unknown>) {
  const v = new Validator(body);

  const mode = v.oneOf("owner.mode", ["new", "existing"] as const, "Choose whether this is a new or existing owner.");

  let ownerUserId: string | null = null;
  let ownerName = "";
  let ownerEmail = "";
  let ownerPhone = "";
  if (mode === "existing") {
    ownerUserId = v.uuid("owner.ownerUserId", "Pick an existing owner");
  } else {
    ownerName = v.string("owner.name", { min: 2, max: 120, message: "Enter the owner's full name" });
    ownerEmail = v.email("owner.email", { max: 200 });
    ownerPhone = v.string("owner.phone", { min: 10, max: 16, message: "Enter a valid 10-digit phone number" });
    // The same shape the web form accepts: digits plus the separators people actually type.
    if (ownerPhone && !/^[\d\s+\-()]+$/.test(ownerPhone)) v.reject("owner.phone", "Enter a valid phone number");
  }

  const hostel: HostelStep = {
    name: v.string("hostel.name", { min: 2, max: 120, message: "Enter the hostel name" }),
    floors: v.int("hostel.floors", { min: 1, max: 50, message: "Enter the number of floors" }),
    rooms: v.int("hostel.rooms", { min: 1, max: 5000, message: "Enter the number of rooms" }),
    bedsPerRoom: v.int("hostel.bedsPerRoom", { min: 1, max: 12, message: "Enter beds per room" }),
    address: v.optionalString("hostel.address", 500),
  };
  // scaffold_hostel divides rooms across floors; fewer rooms than floors would leave floors empty.
  if (hostel.rooms < hostel.floors) v.reject("hostel.rooms", "Add at least one room per floor");

  const subscription: SubscriptionStep = {
    startDate: v.isoDate("subscription.startDate"),
    endDate: v.isoDate("subscription.endDate"),
    amount: v.number("subscription.amount", { min: 0, max: 99_999_999, message: "Enter the amount" }),
    notes: v.optionalString("subscription.notes", 500),
  };
  if (subscription.startDate && subscription.endDate && subscription.endDate <= subscription.startDate) {
    v.reject("subscription.endDate", "End date must be after the start date");
  }

  v.done();
  return { mode, ownerUserId, ownerName, ownerEmail, ownerPhone, hostel, subscription };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    // Identity first: an unauthenticated or under-privileged caller is refused before the
    // request body is read, let alone acted on.
    const caller = await requireCaller(req, "super_admin");
    // An unproved address must not be able to mint another login. This endpoint is the one
    // place where "somebody typed an email" turns into credentials, and until the caller has
    // answered a code sent to their own address there is nothing behind their identity but a
    // password somebody else may have chosen for them. See _shared/verification.ts.
    requireVerifiedEmail(caller);
    const input = parseBody(await readJsonBody(req, MAX_BODY_BYTES));

    // Per-caller, durable (Postgres-backed) and FAIL-CLOSED: this endpoint mints a credential,
    // so if the limiter cannot be consulted the request is refused, not waved through.
    await enforceRateLimit("sa:create:" + caller.id);

    const rest = {
      p_hostel_name: input.hostel.name,
      p_floors: input.hostel.floors,
      p_rooms: input.hostel.rooms,
      p_address: input.hostel.address,
      p_start_date: input.subscription.startDate,
      p_end_date: input.subscription.endDate,
      p_amount: input.subscription.amount,
      p_notes: input.subscription.notes,
      p_beds_per_room: input.hostel.bedsPerRoom,
    };

    // Runs AS the Super Admin, so the RPC's own app.is_super_admin() gate applies and
    // created_by lands on the real actor.
    const asCaller = callerClient(caller.jwt);

    /* ── Branch 1: an owner account that already exists gets a second hostel (Hard rule §4.1).
          No login is created, so no credentials are issued and there is nothing to roll back. ── */
    if (input.mode === "existing") {
      const { data: existing, error: ownerErr } = await asCaller
        .from("users")
        .select("id, full_name, status")
        .eq("id", input.ownerUserId as string)
        .eq("role", "owner")
        .is("deleted_at", null)
        .maybeSingle();
      if (ownerErr) throw dbError(ownerErr);
      if (!existing) throw new HttpError(404, "Owner account not found.");
      if ((existing as { status: string }).status !== "active") {
        throw new HttpError(400, "This owner account is inactive — reactivate it before adding a hostel.");
      }

      const { data, error } = await asCaller.rpc("sa_create_hostel_with_subscription", {
        p_owner_user_id: input.ownerUserId,
        ...rest,
      });
      if (error) throw dbError(error, "Could not create the hostel.");
      const hostelId = typeof data === "string" ? data : null;
      if (!hostelId) throw new HttpError(400, "Could not create the hostel.");

      await audit("sa.owner_hostel.create", caller, {
        targetType: "hostel",
        targetId: hostelId,
        hostelId,
        meta: {
          ownerUserId: input.ownerUserId,
          mode: "existing",
          floors: input.hostel.floors,
          rooms: input.hostel.rooms,
          surface: "edge_function",
        },
      });
      return ok({ hostelId, credentials: null }, input.hostel.name + " created");
    }

    /* ── Branch 2: a brand-new owner. Auth user → public.users row → hostel + subscription +
          room scaffold. The first two are one helper; the third is the RPC. ── */
    const account = await createStaffAccount({
      role: "owner",
      fullName: input.ownerName,
      email: input.ownerEmail,
      phone: normalizePhone(input.ownerPhone),
      // null on purpose: sa_create_hostel_with_subscription sets users.hostel_id to the hostel
      // it creates. An owner row is exempt from the "must belong to a hostel" trigger, which
      // binds only manager / warden / student.
      hostelId: null,
      createdBy: caller.id,
    });

    const { data, error } = await asCaller.rpc("sa_create_hostel_with_subscription", {
      p_owner_user_id: account.userId,
      ...rest,
    });
    const hostelId = typeof data === "string" ? data : null;
    if (error || !hostelId) {
      // The hostel did not happen, so the login must not survive it. Whether the undo worked is
      // reported rather than swallowed — see the header.
      const original = error ? dbError(error, "Could not create the hostel.").message : "Could not create the hostel.";
      throw rollbackAwareError(original, account.userId, await deleteAuthUser(account.userId));
    }

    // Cosmetic mirror only; users.hostel_id (set by the RPC) is the source of truth, so a
    // failure here does not fail the request.
    await syncHostelMetadata(account.userId, hostelId);

    await audit("sa.owner_hostel.create", caller, {
      targetType: "hostel",
      targetId: hostelId,
      hostelId,
      meta: {
        ownerUserId: account.userId,
        mode: "new",
        floors: input.hostel.floors,
        rooms: input.hostel.rooms,
        surface: "edge_function",
      },
    });

    return ok(
      {
        hostelId,
        // Shown once on the Super Admin's screen. Not stored here or anywhere else.
        credentials: { name: input.ownerName, loginId: account.loginId, password: account.password },
      },
      input.hostel.name + " created",
    );
  } catch (e) {
    return toResponse(e);
  }
});
