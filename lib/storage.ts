import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

export type Bucket = "student-docs" | "receipts" | "complaint-photos";

/** Server-side upload cap (Server Action body limit is 8 MB in next.config.ts). */
export const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;
/** Signed URLs are short-lived; ID proofs get the shortest window. */
export const SIGNED_URL_TTL: Record<Bucket, number> = {
  "student-docs": 15 * 60,
  receipts: 30 * 60,
  "complaint-photos": 30 * 60,
};

const ALLOWED: Record<Bucket, string[]> = {
  "student-docs": ["image/jpeg", "image/png", "image/webp", "application/pdf"],
  receipts: ["image/jpeg", "image/png", "image/webp", "application/pdf"],
  "complaint-photos": ["image/jpeg", "image/png", "image/webp"],
};

const EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "application/pdf": "pdf",
};

/**
 * Detect the real content type from the file's leading bytes (magic numbers).
 * We never trust the client-declared `file.type` or the filename extension.
 */
export function sniffContentType(bytes: Uint8Array): string | null {
  if (bytes.length < 12) return null;
  // JPEG: FF D8 FF
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) return "image/png";
  // WEBP: "RIFF" .... "WEBP"
  if (bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return "image/webp";
  // PDF: "%PDF"
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) return "application/pdf";
  return null;
}

/** Only allow storage paths of the shape `<uuid>/<folder>/<uuid>.<ext>` and scoped to the caller's hostel. */
const PATH_RE = /^[0-9a-f-]{36}\/[a-z-]{1,32}\/[0-9a-f-]{36}\.(jpg|png|webp|pdf)$/i;
export function isPathInHostel(path: string | null | undefined, hostelId: string): path is string {
  return !!path && PATH_RE.test(path) && path.startsWith(`${hostelId}/`);
}

/**
 * Upload a File (from a server-action FormData) into a private bucket under
 * `<hostelId>/<folder>/<random>.<ext>`. Returns the storage path to persist.
 *
 * Callers must have authorised the request first (assertWritableContext) and pass
 * ctx.hostel.id — the path prefix is what later scopes signed-URL access.
 * The file's real type is sniffed from its bytes; the declared type is ignored.
 */
export async function uploadToBucket(bucket: Bucket, hostelId: string, folder: string, file: File | null | undefined): Promise<string | null> {
  if (!file || file.size === 0) return null;
  if (file.size > MAX_UPLOAD_BYTES) throw new Error("File is larger than 8 MB.");
  if (!/^[a-z-]{1,32}$/.test(folder)) throw new Error("Invalid upload folder.");

  const bytes = new Uint8Array(await file.arrayBuffer());
  const type = sniffContentType(bytes);
  if (!type || !ALLOWED[bucket].includes(type)) {
    throw new Error("Unsupported or corrupted file. Use a JPG, PNG, WEBP" + (bucket === "complaint-photos" ? "." : " or PDF."));
  }

  const admin = createAdminClient();
  const path = `${hostelId}/${folder}/${crypto.randomUUID()}.${EXT[type]}`;
  const { error } = await admin.storage.from(bucket).upload(path, bytes, {
    contentType: type,
    upsert: false,
    cacheControl: "0",
  });
  if (error) throw new Error("Upload failed. Please try again.");
  return path;
}

/**
 * Signed URL for a private object. Returns null when the path is empty, malformed,
 * or NOT under the given hostel prefix — callers must pass ctx.hostel.id so a user
 * can never mint a URL for another tenant's file (checklist §10: authorise before signing).
 */
export async function signedUrl(bucket: Bucket, path: string | null | undefined, hostelId: string, expiresIn = SIGNED_URL_TTL[bucket]): Promise<string | null> {
  if (!path) return null;
  if (/^https?:\/\//.test(path)) return path; // legacy absolute URL (seed data)
  if (!isPathInHostel(path, hostelId)) return null;
  try {
    const admin = createAdminClient();
    const { data } = await admin.storage.from(bucket).createSignedUrl(path, expiresIn);
    return data?.signedUrl ?? null;
  } catch {
    return null;
  }
}

/** Best-effort removal of uploaded objects (used to roll back when the DB half of a flow fails). */
export async function removeFromBucket(bucket: Bucket, paths: (string | null | undefined)[]): Promise<void> {
  const keep = paths.filter((p): p is string => !!p && !/^https?:\/\//.test(p));
  if (keep.length === 0) return;
  try {
    await createAdminClient().storage.from(bucket).remove(keep);
  } catch {
    // never mask the original error
  }
}
