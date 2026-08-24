/**
 * POST /functions/v1/warden-register-student
 *
 * A WARDEN registers a resident: the student's login, their photo and ID proof in the private
 * bucket, and the users + students rows with a bed assigned. Port of lib/actions/warden.ts →
 * registerStudent(), which takes multipart FormData; here the two files arrive as base64
 * strings inside the JSON body, because supabase.functions.invoke() sends JSON.
 *
 * ═══ WHO IS ALLOWED, AND FOR WHICH HOSTEL ═══
 * requireCaller(req, "warden") verifies the bearer token with GoTrue and then reads the role
 * from public.users — never from the request body or from JWT app_metadata.
 *
 * The hostel is NOT accepted from the client on this path at all. A warden belongs to exactly
 * one hostel, so requireOwnHostel() takes users.hostel_id and that is the tenant for the
 * login, the uploads and the rows. There is no hostelId parameter to get wrong or to abuse.
 * assertWritable() then applies the same subscription/suspension gate app.hostel_writable()
 * would have applied, because the account-creation step runs with the service role and so
 * escapes RLS.
 *
 * ═══ AND THE DATABASE CHECKS IT AGAIN ═══
 * wd_register_student is invoked through the CALLER's client, so inside the RPC auth.uid() is
 * the real warden and its own guards run: app.has_role_in(hostel, 'warden') and
 * app.hostel_writable(hostel). created_by on both rows is therefore the actual person. Calling
 * that RPC with the service key would satisfy nothing useful and skip both guards.
 *
 * ═══ THE FILES ═══
 * storage.objects is default-deny for anon and authenticated — there are no storage policies,
 * by design. The phone holds no key storage would accept, so it sends the bytes here and this
 * function writes them with the service role, under a <hostelId>/… prefix it chooses itself.
 * The content type is sniffed from the leading bytes, never taken from what the client claims.
 *
 * ═══ ROLLBACK — THREE THINGS, TWO OF THEM UNDOABLE ═══
 * The auth user (GoTrue), the objects (Storage) and the rows (Postgres) cannot share a
 * transaction. If the RPC fails, the uploaded objects are removed and the auth user is deleted
 * again. Unlike the web version, a rollback that ITSELF fails is reported rather than
 * swallowed: HTTP 500 naming the orphaned auth user id, because a student login with no
 * students row is invisible, unusable, and permanently holds its phone number — the phone
 * number IS the login id, so that resident can never be registered again until someone deletes
 * the stray account by hand.
 *
 * ═══ THE TEMPORARY PASSWORD ═══
 * Returned ONCE, with Cache-Control: no-store. Never stored, never logged, never audited.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy warden-register-student        (see docs/edge-functions.md)
 */
import { createStudentAuthUser, deleteAuthUser, rollbackAwareError } from "../_shared/accounts.ts";
import { audit } from "../_shared/audit.ts";
import { requireCaller } from "../_shared/caller.ts";
import { dbError } from "../_shared/errors.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { enforceRateLimit } from "../_shared/ratelimit.ts";
import { removeStudentDocs, uploadStudentDoc } from "../_shared/storage.ts";
import { callerClient } from "../_shared/supabase.ts";
import { assertWritable, requireOwnHostel } from "../_shared/tenant.ts";
import { studentLoginEmail, Validator } from "../_shared/validate.ts";

/**
 * Two base64 files at 3 MB each are ~8.4 MB of text, plus the fields. 12 MB is the ceiling
 * readJsonBody enforces before the body is materialised; storage.ts enforces the real per-file
 * limit after decoding.
 */
const MAX_BODY_BYTES = 12 * 1024 * 1024;

/** Mirrors ID_PROOF_TYPES in lib/validators/warden.ts — the students.id_proof_type values. */
const ID_PROOF_TYPES = ["Aadhaar", "PAN", "Passport", "Driving licence", "Voter ID", "Other"] as const;

/** Mirrors registerStudentSchema in lib/validators/warden.ts. */
function parseBody(body: Record<string, unknown>) {
  const v = new Validator(body);

  const fullName = v.string("fullName", { min: 2, max: 120, message: "Enter the student's full name" });
  const phone = v.phone10("phone");
  const email = v.optionalEmail("email", 160);
  const dateOfJoining = v.isoDate("dateOfJoining", "Pick a valid date");

  const guardianName = v.string("guardianName", { min: 2, max: 120, message: "Enter the guardian's name" });
  const guardianPhone = v.phone10("guardianPhone");
  const permanentAddress = v.string("permanentAddress", { min: 6, max: 600, message: "Enter the permanent address" });

  const idProofType = v.oneOf("idProofType", ID_PROOF_TYPES, "Choose an ID proof type");
  const bedId = v.uuid("bedId", "Pick a free bed");
  const monthlyFee = v.number("monthlyFee", { min: 1, max: 1_000_000, message: "Enter the monthly fee" });

  // Spec §6.4 step 3: the ID proof is mandatory. The photo is not.
  const photoBase64 = v.optionalString("photoBase64", MAX_BODY_BYTES);
  const idProofBase64 = v.optionalString("idProofBase64", MAX_BODY_BYTES);
  if (!idProofBase64) v.reject("idProofType", "ID proof file is required");

  v.done();
  return {
    fullName,
    phone,
    email,
    dateOfJoining,
    guardianName,
    guardianPhone,
    permanentAddress,
    idProofType,
    bedId,
    monthlyFee,
    photoBase64,
    idProofBase64,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const caller = await requireCaller(req, "warden");
    const input = parseBody(await readJsonBody(req, MAX_BODY_BYTES));

    // The tenant comes from the caller's own profile row, never from the body.
    const hostel = await requireOwnHostel(caller);
    assertWritable(hostel);

    await enforceRateLimit("warden:register:" + caller.id);

    // The login id is the phone number, mapped to the same synthetic address the web app
    // resolves at sign-in. If that address is taken, createStudentAuthUser fails here with
    // "already has an account" — before anything else has been created.
    const account = await createStudentAuthUser({
      fullName: input.fullName,
      phone: input.phone,
      hostelId: hostel.id,
      loginEmail: studentLoginEmail(input.phone),
    });

    const asCaller = callerClient(caller.jwt);
    let photoPath: string | null = null;
    let idProofPath: string | null = null;
    let studentId: string;

    /*
     * Everything that must be undone if it fails lives in THIS block, and nothing else does.
     * The moment the RPC returns a student id the registration has happened, so the block
     * ends there — a failure afterwards must never trigger a rollback that deletes a real
     * resident's login and documents.
     */
    try {
      // Sequential, not Promise.all: if the first upload is rejected (too large, or not
      // actually a JPG/PNG/WEBP/PDF), the second is never written and never needs cleaning up.
      photoPath = await uploadStudentDoc(input.photoBase64, hostel.id, "photos", "photo");
      idProofPath = await uploadStudentDoc(input.idProofBase64, hostel.id, "id-proofs", "idProof");

      const { data, error } = await asCaller.rpc("wd_register_student", {
        p_user_id: account.userId,
        p_hostel_id: hostel.id,
        p_full_name: input.fullName,
        p_phone: input.phone,
        p_email: input.email,
        p_photo_url: photoPath,
        p_guardian_name: input.guardianName,
        p_guardian_phone: input.guardianPhone,
        p_permanent_address: input.permanentAddress,
        p_id_proof_type: input.idProofType,
        p_id_proof_url: idProofPath,
        p_date_of_joining: input.dateOfJoining,
        p_bed_id: input.bedId,
        p_monthly_fee: input.monthlyFee,
      });
      if (error) throw dbError(error, "Could not register the student.");
      const id = typeof data === "string" ? data : null;
      if (!id) throw new HttpError(400, "Could not register the student.");
      studentId = id;
    } catch (e) {
      // Undo, innermost first: objects, then the login. Object cleanup is best-effort and
      // never masks the original failure; the login rollback's outcome is reported.
      await removeStudentDocs([photoPath, idProofPath]);
      const original = e instanceof HttpError ? e.message : "Could not register the student.";
      const rolled = await deleteAuthUser(account.userId);
      if (!rolled.deleted) throw rollbackAwareError(original, account.userId, rolled);
      throw e;
    }

    // ── The student exists. Nothing from here on may fail the request. ──

    // The room id is a convenience for the app's next screen. Failing to read it is not a
    // failure to register, so it cannot be allowed to throw.
    let roomId: string | null = null;
    try {
      const { data: bed } = await asCaller.from("beds").select("room_id").eq("id", input.bedId).maybeSingle();
      roomId = (bed as { room_id: string } | null)?.room_id ?? null;
    } catch (e) {
      console.error("[nivora] room lookup after registration failed (non-fatal):", e instanceof Error ? e.message : String(e));
    }

    // audit() swallows its own failures by design — the trail must never break the operation.
    await audit("warden.student.register", caller, {
      targetType: "student",
      targetId: studentId,
      hostelId: hostel.id,
      meta: { bedId: input.bedId, surface: "edge_function" },
    });

    return ok(
      {
        studentId,
        roomId,
        // Shown once, on the warden's screen, to hand to the resident.
        credentials: { name: input.fullName, loginId: account.loginId, password: account.password },
      },
      input.fullName + " registered",
    );
  } catch (e) {
    return toResponse(e);
  }
});
