/**
 * Private-bucket uploads and signed reads for the mobile paths. Port of lib/storage.ts.
 *
 * storage.objects is default-deny for anon and authenticated (db/rls-policies.sql) — there are
 * no storage policies at all, by design: every object goes in and comes out through the service
 * role after the caller has been authorised. That is why the phone sends the bytes here rather
 * than uploading them itself: it has no key that storage would accept. It is also why a photo
 * cannot be rendered from its stored value — that value is a KEY, and the URL that shows it has
 * to be minted here, after the caller has been shown to be allowed to see the thing it belongs
 * to.
 *
 * Three things are decided server-side and cannot be influenced by the client:
 *   - the content type, sniffed from the file's leading bytes. A declared MIME type or a
 *     filename extension is a claim, not evidence; a .jpg that is really an HTML document
 *     would otherwise be served back from a signed URL and render in the viewer's origin.
 *   - the path, always <hostelId>/<folder>/<uuid>.<ext>. That prefix is what later scopes
 *     signed-URL access to one tenant, so the caller never gets to choose it.
 *   - whether a stored value may be signed at all. [isPathInHostel] refuses anything that is
 *     not a real object under the tenant's own prefix — including an absolute https:// value,
 *     because `*_url` columns are writable by staff through PostgREST and echoing one back
 *     would let a warden point an owner's phone at any host they liked.
 */
import { HttpError } from "./http.ts";
import { serviceClient } from "./supabase.ts";

export const BUCKET_STUDENT_DOCS = "student-docs";
export const BUCKET_COMPLAINT_PHOTOS = "complaint-photos";

/**
 * Per-file cap. Lower than the web's 8 MB because these bytes travel as base64 inside a JSON
 * body (about +33%) through the Edge Function request limit, not as multipart form data.
 * The app should compress a camera photo before sending; a scan of an ID comfortably fits.
 */
export const MAX_UPLOAD_BYTES = 3 * 1024 * 1024;

/**
 * How long a minted URL lives. Same windows as SIGNED_URL_TTL in lib/storage.ts, so a photo
 * does not outlive its browser copy on one client and not the other. Short on purpose: a
 * signed URL is a bearer capability, and anything long enough to be worth pasting into a chat
 * is long enough to be a leak.
 */
export const SIGNED_URL_TTL: Record<string, number> = {
  [BUCKET_STUDENT_DOCS]: 15 * 60,
  [BUCKET_COMPLAINT_PHOTOS]: 30 * 60,
};

/** What each bucket will actually hold, after sniffing. Mirrors ALLOWED in lib/storage.ts. */
export const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
export const DOCUMENT_TYPES = [...IMAGE_TYPES, "application/pdf"] as const;

const EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "application/pdf": "pdf",
};

/** Detect the real content type from magic numbers. Never trust the client's declared type. */
export function sniffContentType(bytes: Uint8Array): string | null {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) return "image/png";
  if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) return "image/webp";
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) return "application/pdf";
  return null;
}

function decodeBase64(value: string, field: string): Uint8Array {
  // Tolerate a data: URL prefix, which is what an image picker often hands a Flutter app.
  const payload = value.includes(",") && value.slice(0, 64).includes("base64") ? value.slice(value.indexOf(",") + 1) : value;
  try {
    const binary = atob(payload.replace(/\s/g, ""));
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out;
  } catch {
    throw new HttpError(400, "That file could not be read. Try picking it again.", { fieldErrors: { [field]: ["Could not read this file"] } });
  }
}

/**
 * The one upload. Every bucket goes through it, so the ceiling, the sniff, the extension and
 * the tenant prefix are decided in exactly one place — a second upload path is a second set of
 * those decisions, and the second set is the one that ends up missing the sniff.
 *
 * Returns the storage path to persist, or null when nothing was sent.
 */
export async function uploadPrivateFile(opts: {
  base64: string | null | undefined;
  bucket: string;
  hostelId: string;
  folder: string;
  /** The form field the refusal belongs under, so the phone can pin it to the right control. */
  field: string;
  allowed: readonly string[];
}): Promise<string | null> {
  const { base64, bucket, hostelId, folder, field, allowed } = opts;
  if (!base64) return null;
  if (!/^[a-z-]{1,32}$/.test(folder)) throw new HttpError(500, "Invalid upload folder.");

  // A base64 string is ~4/3 the size of its bytes; check before decoding so an oversized
  // payload is refused without materialising it.
  if (base64.length > Math.ceil(MAX_UPLOAD_BYTES * 1.4)) {
    throw new HttpError(413, "That file is larger than 3 MB.", { fieldErrors: { [field]: ["File is larger than 3 MB"] } });
  }
  const bytes = decodeBase64(base64, field);
  if (bytes.byteLength === 0) return null;
  if (bytes.byteLength > MAX_UPLOAD_BYTES) {
    throw new HttpError(413, "That file is larger than 3 MB.", { fieldErrors: { [field]: ["File is larger than 3 MB"] } });
  }

  const type = sniffContentType(bytes);
  if (!type || !allowed.includes(type)) {
    const list = allowed.includes("application/pdf") ? "a JPG, PNG, WEBP or PDF" : "a JPG, PNG or WEBP";
    throw new HttpError(400, "Unsupported or corrupted file. Use " + list + ".", {
      fieldErrors: { [field]: ["Use " + list] },
    });
  }

  const path = hostelId + "/" + folder + "/" + crypto.randomUUID() + "." + EXT[type];
  const { error } = await serviceClient().storage.from(bucket).upload(path, bytes, {
    contentType: type,
    upsert: false,
    cacheControl: "0",
  });
  if (error) {
    console.error("[nivora] storage upload failed:", error.message);
    throw new HttpError(500, "Upload failed. Please try again.");
  }
  return path;
}

/** Upload one base64 file into the student-docs bucket. The registration path's shape. */
export function uploadStudentDoc(
  base64: string | null,
  hostelId: string,
  folder: "photos" | "id-proofs",
  field: string,
): Promise<string | null> {
  return uploadPrivateFile({
    base64,
    bucket: BUCKET_STUDENT_DOCS,
    hostelId,
    folder,
    field,
    allowed: DOCUMENT_TYPES,
  });
}

/**
 * Only allow storage paths of the shape `<uuid>/<folder>/<uuid>.<ext>` and scoped to the
 * caller's hostel. Byte-for-byte the same rule as isPathInHostel() in lib/storage.ts — a value
 * the web app will sign and this one will not (or the reverse) is a photo that renders in a
 * browser and not on the phone, for no reason anybody could explain.
 */
const PATH_RE = /^[0-9a-f-]{36}\/[a-z-]{1,32}\/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$/i;

export function isPathInHostel(path: string | null | undefined, hostelId: string): path is string {
  return !!path && PATH_RE.test(path) && path.startsWith(hostelId + "/");
}

/**
 * A short-lived URL for one private object, or null when the stored value is empty, malformed,
 * or NOT under the given hostel prefix.
 *
 * AUTHORISE BEFORE SIGNING. This function checks the TENANT and nothing else — it cannot know
 * whether the caller may see the row the path came off. Callers must have established that
 * first (checklist §10); [hostelId] is the hostel of the ROW, read back from the database under
 * the caller's own RLS, never a value the client sent.
 */
export async function signedObjectUrl(
  bucket: string,
  path: string | null | undefined,
  hostelId: string,
  expiresIn = SIGNED_URL_TTL[bucket] ?? 15 * 60,
): Promise<string | null> {
  if (!isPathInHostel(path, hostelId)) return null;
  try {
    // Images are rendered inline; a PDF is forced to download so an uploaded file can never
    // render as a document in the viewer's origin.
    const isDocument = path.toLowerCase().endsWith(".pdf");
    const { data, error } = await serviceClient().storage
      .from(bucket)
      .createSignedUrl(path, expiresIn, isDocument ? { download: true } : {});
    if (error) {
      console.error("[nivora] signing failed:", error.message);
      return null;
    }
    return data?.signedUrl ?? null;
  } catch (e) {
    console.error("[nivora] signing threw:", e instanceof Error ? e.message : String(e));
    return null;
  }
}

/** Best-effort removal, so a half-finished flow leaves no orphans in a private bucket. */
export async function removeObjects(bucket: string, paths: (string | null | undefined)[]): Promise<void> {
  const keep = paths.filter((p): p is string => !!p && !/^https?:\/\//.test(p));
  if (keep.length === 0) return;
  try {
    await serviceClient().storage.from(bucket).remove(keep);
  } catch (e) {
    // Never mask the original failure with a cleanup failure.
    console.error("[nivora] storage cleanup failed:", e instanceof Error ? e.message : String(e));
  }
}

/** Cleanup for the registration path. */
export function removeStudentDocs(paths: (string | null)[]): Promise<void> {
  return removeObjects(BUCKET_STUDENT_DOCS, paths);
}
