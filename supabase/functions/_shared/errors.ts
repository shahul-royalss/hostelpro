/**
 * Turn a PostgREST / Postgres error into a message a person can act on, without leaking
 * internals. Port of lib/permissions.ts errorMessage() — the friendly text our triggers and
 * RPCs already raise (SQLSTATE P0001) is shown verbatim, everything else is mapped.
 */
import { HttpError } from "./http.ts";

export interface PostgrestLikeError {
  message?: string;
  code?: string;
  details?: string;
  hint?: string;
}

/** HTTP status that matches the class of failure, so the app can branch without string-matching. */
function statusFor(code: string): number {
  if (code === "42501") return 403;
  if (code === "23505") return 409;
  if (code === "PGRST116") return 404;
  return 400;
}

export function dbError(err: PostgrestLikeError | null | undefined, fallback = "Something went wrong. Please try again."): HttpError {
  const msg = err?.message ?? "";
  const code = err?.code ?? "";

  if (code === "42501" || /row-level security/i.test(msg)) {
    if (/expired|read-only|Only the Super Admin|Only the warden|Not allowed/i.test(msg)) return new HttpError(403, msg);
    return new HttpError(403, "You don't have permission to do that (or the subscription has expired).");
  }
  if (code === "23505") {
    if (/students_phone_active_key/.test(msg)) return new HttpError(409, "A student with this phone number is already registered.");
    if (/users_email_key/.test(msg)) return new HttpError(409, "An account with this email already exists.");
    if (/users_one_active_staff_per_hostel/.test(msg)) return new HttpError(409, "This hostel already has an active manager or warden in that role. Deactivate the current one first.");
    if (/students_one_active_per_bed|beds_student_key/.test(msg)) return new HttpError(409, "That bed is already occupied. Choose a free bed.");
    return new HttpError(409, "This record already exists.");
  }
  if (code === "23503") return new HttpError(400, "That record is linked to something that no longer exists.");
  if (code === "23514" || code === "22003") return new HttpError(400, "One of the values is out of the allowed range.");
  if (code === "22P02" || code === "22007" || code === "22008") return new HttpError(400, "One of the values has an invalid format.");
  if (code === "P0001" && msg) return new HttpError(400, msg); // our own friendly raises
  if (code === "PGRST116") return new HttpError(404, "Not found.");

  // Anything else: log the raw error where only we can see it, tell the caller nothing.
  console.error("[nivora] db error:", JSON.stringify({ code, message: msg }).slice(0, 500));
  return new HttpError(statusFor(code), fallback);
}
