/**
 * Private-bucket uploads for the student-registration path. Port of lib/storage.ts.
 *
 * storage.objects is default-deny for anon and authenticated (db/rls-policies.sql) — there are
 * no storage policies at all, by design: every object goes in and comes out through the service
 * role after the caller has been authorised. That is why the phone sends the bytes here rather
 * than uploading them itself: it has no key that storage would accept.
 *
 * Two things are decided server-side and cannot be influenced by the client:
 *   - the content type, sniffed from the file's leading bytes. A declared MIME type or a
 *     filename extension is a claim, not evidence; a .jpg that is really an HTML document
 *     would otherwise be served back from a signed URL and render in the viewer's origin.
 *   - the path, always <hostelId>/<folder>/<uuid>.<ext>. That prefix is what later scopes
 *     signed-URL access to one tenant, so the caller never gets to choose it.
 */
import { HttpError } from "./http.ts";
import { serviceClient } from "./supabase.ts";

export const BUCKET_STUDENT_DOCS = "student-docs";

/**
 * Per-file cap. Lower than the web's 8 MB because these bytes travel as base64 inside a JSON
 * body (about +33%) through the Edge Function request limit, not as multipart form data.
 * The app should compress a camera photo before sending; a scan of an ID comfortably fits.
 */
export const MAX_UPLOAD_BYTES = 3 * 1024 * 1024;

const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp", "application/pdf"] as const;
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
 * Upload one base64 file into the private bucket under the hostel's prefix.
 * Returns the storage path to persist, or null when nothing was sent.
 */
export async function uploadStudentDoc(
  base64: string | null,
  hostelId: string,
  folder: "photos" | "id-proofs",
  field: string,
): Promise<string | null> {
  if (!base64) return null;
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
  if (!type || !(ALLOWED_TYPES as readonly string[]).includes(type)) {
    throw new HttpError(400, "Unsupported or corrupted file. Use a JPG, PNG, WEBP or PDF.", {
      fieldErrors: { [field]: ["Use a JPG, PNG, WEBP or PDF"] },
    });
  }

  const path = hostelId + "/" + folder + "/" + crypto.randomUUID() + "." + EXT[type];
  const { error } = await serviceClient().storage.from(BUCKET_STUDENT_DOCS).upload(path, bytes, {
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

/** Best-effort cleanup so a failed registration leaves no orphans in the private bucket. */
export async function removeStudentDocs(paths: (string | null)[]): Promise<void> {
  const keep = paths.filter((p): p is string => !!p);
  if (keep.length === 0) return;
  try {
    await serviceClient().storage.from(BUCKET_STUDENT_DOCS).remove(keep);
  } catch (e) {
    // Never mask the original failure with a cleanup failure.
    console.error("[nivora] storage cleanup failed:", e instanceof Error ? e.message : String(e));
  }
}
