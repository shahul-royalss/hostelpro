/**
 * POST /functions/v1/complaint-photo
 *
 * The photo a resident attaches to a complaint: putting it in, and getting it back out.
 * Port of the two halves lib/actions/student.ts and app/*\/complaints/page.tsx already do in
 * the browser — `uploadToBucket("complaint-photos", ctx.hostel.id, "complaints", photo)` and
 * `signedUrl("complaint-photos", row.photo_url, ctx.hostel.id)`.
 *
 * ═══ WHY THIS IS A SERVER AND NOT A CLIENT UPLOAD ═══
 * `complaint-photos` is a PRIVATE bucket and storage.objects is default-deny for anon and
 * authenticated — db/rls-policies.sql has no storage policies at all, on purpose. The phone
 * holds the anon key and an ordinary user session, neither of which storage will accept for a
 * read or a write. So the bytes come here, and the URL that renders them is minted here.
 * `complaints.photo_url` is a storage KEY, never a URL: handing one to Image.network renders
 * nothing, which is why this endpoint exists rather than a column the client could just read.
 *
 * ═══ THE THREE ACTIONS ═══
 *
 *   upload   A resident sends one compressed image; it lands at
 *            `<hostelId>/complaints/<uuid>.<ext>` and the KEY comes back. The caller then
 *            inserts the complaint with that key through PostgREST, where complaints_insert
 *            re-checks student_id, hostel_id and app.hostel_writable(). This endpoint does not
 *            write the row: the insert has a policy of its own and moving it here would mean
 *            re-deciding, with the service role, something the database already decides.
 *
 *   sign     Anyone who may READ the complaint may see its photo. That is not a separate rule
 *            invented here — it is `complaints_select`, asked directly: the row is fetched with
 *            the CALLER'S OWN JWT (callerClient), so RLS answers, and a row coming back IS the
 *            authorisation. A student of another hostel, or a student who did not raise it,
 *            gets no row and therefore no URL. The hostel prefix the object must sit under
 *            comes from that row, never from the request body.
 *
 *   discard  The rollback for an upload whose complaint insert then failed, so a private bucket
 *            does not fill with photos of taps nobody ever reported. Refused for any object a
 *            complaint row still points at — otherwise a resident could delete the evidence out
 *            from under a warden who is looking at it.
 *
 * ═══ WHAT THIS ENDPOINT IS NOT ═══
 * Not an oracle. "No such complaint", "not yours" and "no photo attached" are three different
 * 404s in the code and one sentence on the wire wherever telling them apart would say whether
 * a complaint id exists.
 *
 * ═══ DEPLOY ═══
 *   supabase functions deploy complaint-photo        (see docs/edge-functions.md)
 */
import { requireCaller } from "../_shared/caller.ts";
import { fail, HttpError, ok, preflight, readJsonBody, toResponse } from "../_shared/http.ts";
import { consumeRateLimit, throttled } from "../_shared/ratelimit.ts";
import {
  BUCKET_COMPLAINT_PHOTOS,
  IMAGE_TYPES,
  isPathInHostel,
  removeObjects,
  signedObjectUrl,
  SIGNED_URL_TTL,
  uploadPrivateFile,
} from "../_shared/storage.ts";
import { callerClient, serviceClient } from "../_shared/supabase.ts";
import { assertWritable, requireOwnHostel } from "../_shared/tenant.ts";
import { Validator } from "../_shared/validate.ts";

/**
 * 3 MB of image is ~4 MB of base64; the rest is envelope. readJsonBody refuses anything larger
 * before the body is materialised, and storage.ts enforces the real per-file ceiling after
 * decoding — this only keeps a hostile body from being read into memory at all.
 */
const MAX_BODY_BYTES = 6 * 1024 * 1024;

/** The folder half of the path. Must match lib/actions/student.ts, or the web app's PATH_RE
 * would refuse to sign a photo this endpoint stored. */
const FOLDER = "complaints";

/** Mirrors LIMITS.uploadPerUser in lib/rate-limit.ts. Same policy, same numbers. */
const UPLOAD_LIMIT = { max: 40, windowSeconds: 3600 } as const;

type Action = "upload" | "sign" | "discard";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return preflight();
  if (req.method !== "POST") return fail("Method not allowed.", 405);

  try {
    const body = await readJsonBody(req, MAX_BODY_BYTES);
    const v = new Validator(body);
    const action = v.oneOf<Action>("action", ["upload", "sign", "discard"], "Unknown action.");
    v.done();

    if (action === "upload") return await handleUpload(req, body);
    if (action === "sign") return await handleSign(req, body);
    return await handleDiscard(req, body);
  } catch (e) {
    return toResponse(e);
  }
});

/**
 * A resident attaches a photo.
 *
 * The tenant is `users.hostel_id` and is never accepted from the body — a resident belongs to
 * exactly one hostel, so there is nothing here to get wrong or to abuse. [assertWritable]
 * mirrors app.hostel_writable(), which complaints_insert is about to apply anyway: refusing
 * here means a lapsed subscription does not cost the resident an upload before the insert
 * turns them away.
 */
async function handleUpload(req: Request, body: Record<string, unknown>): Promise<Response> {
  const caller = await requireCaller(req, "student");
  const hostel = await requireOwnHostel(caller);
  assertWritable(hostel);

  // Read by hand rather than through the Validator: its length caps are written for text
  // columns and would report a 4 MB image as "keep this under N characters". The real ceiling
  // is bytes after decoding, and storage.ts is where that is enforced.
  const base64 = body.photoBase64;
  if (typeof base64 !== "string" || !base64.trim()) {
    throw new HttpError(400, "Attach a photo.", { fieldErrors: { photo: ["Attach a photo"] } });
  }

  const wait = await consumeRateLimit("complaint:photo:" + caller.id, UPLOAD_LIMIT, {
    unavailableMessage: "Photo uploads are temporarily unavailable. Send the complaint without one, or try again in a minute.",
  });
  if (wait > 0) throw throttled(`Too many photo uploads in a short time. Try again in ${wait}s.`, wait);

  const path = await uploadPrivateFile({
    base64,
    bucket: BUCKET_COMPLAINT_PHOTOS,
    hostelId: hostel.id,
    folder: FOLDER,
    field: "photo",
    allowed: IMAGE_TYPES,
  });
  if (!path) throw new HttpError(400, "That photo was empty. Try picking it again.", { fieldErrors: { photo: ["Could not read this photo"] } });

  return ok({ path });
}

/**
 * A short-lived URL for the photo on one complaint.
 *
 * THE AUTHORISATION IS THE SELECT. Reading the row through [callerClient] runs
 * complaints_select against this caller's real token — owner and warden of the hostel, or the
 * resident who raised it, and nobody else. The service role is used for exactly one thing after
 * that: minting the URL, which no user session can do because storage.objects admits none of
 * them. Doing the read with the service client instead would skip the only check there is.
 *
 * Any role may call this; there is no `roles` argument to requireCaller on purpose. A manager
 * cannot read complaints at all (rls-policies.sql), so a manager gets no row and no URL from
 * the same code path — the policy says who, and it says so once.
 */
async function handleSign(req: Request, body: Record<string, unknown>): Promise<Response> {
  const caller = await requireCaller(req);

  const v = new Validator(body);
  const complaintId = v.uuid("complaintId", "Unknown complaint.");
  v.done();

  const { data, error } = await callerClient(caller.jwt)
    .from("complaints")
    .select("id, hostel_id, photo_url")
    .eq("id", complaintId)
    .maybeSingle();
  if (error) {
    console.error("[nivora] complaint lookup failed:", error.message);
    throw new HttpError(500, "Could not load that complaint. Please try again.");
  }
  const row = data as { id: string; hostel_id: string; photo_url: string | null } | null;

  // One sentence for "no such complaint" and for "not visible to you": distinguishing them
  // would answer, to any signed-in account, whether a given complaint id is real.
  if (!row) throw new HttpError(404, "That complaint is not visible to your account.");
  if (!row.photo_url) throw new HttpError(404, "No photo is attached to this complaint.");

  const url = await signedObjectUrl(BUCKET_COMPLAINT_PHOTOS, row.photo_url, row.hostel_id);
  if (!url) {
    // Either the stored value is not an object under this hostel's prefix — which is what
    // isPathInHostel refuses, and is the shape a staff-written absolute URL would have — or
    // storage could not sign it. Neither is something the reader can act on.
    throw new HttpError(404, "That photo could not be opened. Ask your warden to check it.");
  }

  return ok({ url, expiresInSeconds: SIGNED_URL_TTL[BUCKET_COMPLAINT_PHOTOS] });
}

/**
 * Delete an uploaded photo that never became a complaint.
 *
 * TWO GUARDS, AND THE SECOND IS THE IMPORTANT ONE. The path must sit under the caller's own
 * hostel prefix (so this is not a delete-anything endpoint), AND no complaint row may still
 * reference it. Without the second, a resident could raise a complaint with a photo of a
 * flooded bathroom and then remove the photo the moment the warden opened it.
 *
 * The reference check uses the SERVICE client deliberately: the question is "does any row
 * anywhere point at this object", and a check narrowed by the caller's own RLS would answer
 * "no" for a row the caller cannot see and then delete the file underneath it.
 */
async function handleDiscard(req: Request, body: Record<string, unknown>): Promise<Response> {
  const caller = await requireCaller(req, "student");
  if (!caller.hostelId) throw new HttpError(403, "No hostel is linked to your account.");

  const v = new Validator(body);
  const path = v.string("path", { min: 1, max: 200, message: "Unknown photo." });
  v.done();

  if (!isPathInHostel(path, caller.hostelId) || !path.startsWith(caller.hostelId + "/" + FOLDER + "/")) {
    throw new HttpError(403, "That photo is not yours to remove.");
  }

  const { count, error } = await serviceClient()
    .from("complaints")
    .select("id", { count: "exact", head: true })
    .eq("photo_url", path);
  if (error) {
    console.error("[nivora] orphan check failed:", error.message);
    throw new HttpError(500, "Could not check that photo. Please try again.");
  }
  if ((count ?? 0) > 0) throw new HttpError(409, "That photo belongs to a complaint and cannot be removed.");

  await removeObjects(BUCKET_COMPLAINT_PHOTOS, [path]);
  return ok({ removed: true });
}
