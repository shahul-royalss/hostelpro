import "server-only";
import { createAdminClient } from "@/lib/supabase/admin";

export type Bucket = "student-docs" | "receipts" | "complaint-photos";

const MAX_BYTES = 8 * 1024 * 1024;
const ALLOWED: Record<Bucket, string[]> = {
  "student-docs": ["image/jpeg", "image/png", "image/webp", "application/pdf"],
  receipts: ["image/jpeg", "image/png", "image/webp", "application/pdf"],
  "complaint-photos": ["image/jpeg", "image/png", "image/webp"],
};

function extFor(type: string) {
  return type === "application/pdf" ? "pdf" : type === "image/png" ? "png" : type === "image/webp" ? "webp" : "jpg";
}

/**
 * Upload a File (from a server-action FormData) into a private bucket under
 * `<hostelId>/<folder>/<random>.<ext>`. Returns the storage path to persist.
 * Caller must have authorised the request first.
 */
export async function uploadToBucket(bucket: Bucket, hostelId: string, folder: string, file: File | null | undefined): Promise<string | null> {
  if (!file || file.size === 0) return null;
  if (file.size > MAX_BYTES) throw new Error("File is larger than 8 MB.");
  if (!ALLOWED[bucket].includes(file.type)) throw new Error("Unsupported file type. Use JPG, PNG, WEBP or PDF.");

  const admin = createAdminClient();
  const path = `${hostelId}/${folder}/${crypto.randomUUID()}.${extFor(file.type)}`;
  const bytes = Buffer.from(await file.arrayBuffer());
  const { error } = await admin.storage.from(bucket).upload(path, bytes, {
    contentType: file.type,
    upsert: false,
  });
  if (error) throw new Error(error.message);
  return path;
}

/** Signed URL (1 hour) for a private object. Returns null when path is empty. */
export async function signedUrl(bucket: Bucket, path: string | null | undefined, expiresIn = 3600): Promise<string | null> {
  if (!path) return null;
  if (/^https?:\/\//.test(path)) return path; // already a URL (seed data)
  try {
    const admin = createAdminClient();
    const { data } = await admin.storage.from(bucket).createSignedUrl(path, expiresIn);
    return data?.signedUrl ?? null;
  } catch {
    return null;
  }
}
