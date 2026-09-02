/**
 * Input validation, mirroring the zod schemas in lib/validators/* field for field and message
 * for message, so the phone and the browser reject the same input for the same reason.
 *
 * Errors accumulate: the whole payload is checked and every field that failed comes back in
 * `fieldErrors`, the same shape zod's flatten() produces, so a form can highlight all of them
 * in one pass instead of one per round trip.
 *
 * This is not decoration. The length caps here are what keep a 10 MB "full name" out of a text
 * column, and the date/number parsers are what stop a NaN reaching a numeric column.
 */
import { HttpError, type FieldErrors } from "./http.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const PHONE_LOOSE_RE = /^[\d\s+\-()]{8,16}$/;

export class Validator {
  private readonly errors: FieldErrors = {};
  constructor(private readonly body: Record<string, unknown>) {}

  private raw(field: string): unknown {
    return field.split(".").reduce<unknown>((acc, part) => {
      if (acc && typeof acc === "object" && !Array.isArray(acc)) return (acc as Record<string, unknown>)[part];
      return undefined;
    }, this.body);
  }

  private add(field: string, message: string): void {
    (this.errors[field] ??= []).push(message);
  }

  /** Is a nested object present at all? Used to pick a branch before validating its fields. */
  has(field: string): boolean {
    return this.raw(field) !== undefined;
  }

  string(field: string, opts: { min?: number; max: number; message?: string }): string {
    const v = this.raw(field);
    if (typeof v !== "string") {
      this.add(field, opts.message ?? "This field is required.");
      return "";
    }
    const trimmed = v.trim();
    if (opts.min !== undefined && trimmed.length < opts.min) {
      this.add(field, opts.message ?? "Enter at least " + opts.min + " characters.");
      return trimmed;
    }
    if (trimmed.length > opts.max) {
      this.add(field, "Keep this under " + opts.max + " characters.");
      return trimmed.slice(0, opts.max);
    }
    return trimmed;
  }

  optionalString(field: string, max: number): string | null {
    const v = this.raw(field);
    if (v === undefined || v === null || v === "") return null;
    if (typeof v !== "string") {
      this.add(field, "This value is not valid.");
      return null;
    }
    const trimmed = v.trim();
    if (!trimmed) return null;
    if (trimmed.length > max) {
      this.add(field, "Keep this under " + max + " characters.");
      return null;
    }
    return trimmed;
  }

  email(field: string, opts: { max?: number } = {}): string {
    const v = this.string(field, { min: 3, max: opts.max ?? 200, message: "Enter a valid email address" });
    if (v && !EMAIL_RE.test(v)) {
      this.add(field, "Enter a valid email address");
      return "";
    }
    return v.toLowerCase();
  }

  optionalEmail(field: string, max = 160): string | null {
    const v = this.optionalString(field, max);
    if (v === null) return null;
    if (!EMAIL_RE.test(v)) {
      this.add(field, "Enter a valid email");
      return null;
    }
    return v.toLowerCase();
  }

  /** Loose form, exactly what the web's createStaffSchema accepts: digits, spaces, + - ( ). */
  optionalPhone(field: string): string | null {
    const v = this.optionalString(field, 16);
    if (v === null) return null;
    if (!PHONE_LOOSE_RE.test(v)) {
      this.add(field, "Enter a valid phone number.");
      return null;
    }
    return v;
  }

  /** Strict 10-digit Indian mobile after normalisation — this one becomes a login id. */
  phone10(field: string): string {
    const v = this.raw(field);
    if (typeof v !== "string" || !v.trim()) {
      this.add(field, "Enter a valid 10-digit phone number");
      return "";
    }
    const normalised = normalizePhone(v);
    if (!/^[6-9]\d{9}$/.test(normalised)) {
      this.add(field, "Enter a valid 10-digit phone number");
      return "";
    }
    return normalised;
  }

  uuid(field: string, message = "Invalid id."): string {
    const v = this.raw(field);
    if (typeof v !== "string" || !UUID_RE.test(v)) {
      this.add(field, message);
      return "";
    }
    return v;
  }

  optionalUuid(field: string, message = "Invalid id."): string | null {
    const v = this.raw(field);
    if (v === undefined || v === null || v === "") return null;
    if (typeof v !== "string" || !UUID_RE.test(v)) {
      this.add(field, message);
      return null;
    }
    return v;
  }

  /** YYYY-MM-DD, and a real day: "2026-02-31" is rejected, not silently rolled forward. */
  isoDate(field: string, message = "Pick a valid date"): string {
    const v = this.raw(field);
    if (typeof v !== "string" || !ISO_DATE_RE.test(v) || !isRealDate(v)) {
      this.add(field, message);
      return "";
    }
    return v;
  }

  optionalIsoDate(field: string, message = "Pick a valid date"): string | null {
    const v = this.raw(field);
    if (v === undefined || v === null || v === "") return null;
    if (typeof v !== "string" || !ISO_DATE_RE.test(v) || !isRealDate(v)) {
      this.add(field, message);
      return null;
    }
    return v;
  }

  int(field: string, opts: { min: number; max: number; message?: string }): number {
    const n = this.number(field, opts);
    if (!Number.isInteger(n)) {
      this.add(field, "Enter a whole number.");
      return opts.min;
    }
    return n;
  }

  number(field: string, opts: { min: number; max: number; message?: string }): number {
    const v = this.raw(field);
    const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : Number.NaN;
    if (!Number.isFinite(n)) {
      this.add(field, opts.message ?? "Enter a number.");
      return opts.min;
    }
    if (n < opts.min || n > opts.max) {
      this.add(field, "Enter a value between " + opts.min + " and " + opts.max + ".");
      return Math.min(Math.max(n, opts.min), opts.max);
    }
    return n;
  }

  oneOf<T extends string>(field: string, allowed: readonly T[], message: string): T {
    const v = this.raw(field);
    if (typeof v !== "string" || !(allowed as readonly string[]).includes(v)) {
      this.add(field, message);
      return allowed[0];
    }
    return v as T;
  }

  optionalOneOf<T extends string>(field: string, allowed: readonly T[], message: string): T | null {
    const v = this.raw(field);
    if (v === undefined || v === null || v === "") return null;
    if (typeof v !== "string" || !(allowed as readonly string[]).includes(v)) {
      this.add(field, message);
      return null;
    }
    return v as T;
  }

  /** Record a cross-field rule failure — the equivalent of zod's .refine(). */
  reject(field: string, message: string): void {
    this.add(field, message);
  }

  get failed(): boolean {
    return Object.keys(this.errors).length > 0;
  }

  /** Throw with everything that failed, or return control if the payload is clean. */
  done(summary = "Please check the highlighted fields."): void {
    if (!this.failed) return;
    const first = Object.values(this.errors)[0]?.[0];
    throw new HttpError(400, first ?? summary, { fieldErrors: this.errors });
  }
}

/** Same normalisation as lib/utils.ts: +91 / leading 0 stripped, digits only. */
export function normalizePhone(input: string): string {
  const digits = input.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("91")) return digits.slice(2);
  if (digits.length === 11 && digits.startsWith("0")) return digits.slice(1);
  return digits;
}

/**
 * Students sign in with their phone number; Supabase Auth needs an email, so the phone maps to
 * a deterministic synthetic address. This MUST stay byte-identical to lib/utils.ts
 * studentLoginEmail() — the web app resolves the same address at login, and a mismatch here
 * would create accounts nobody can sign in to.
 */
export const STUDENT_LOGIN_DOMAIN = "student.hostelpro.local";
export function studentLoginEmail(phone: string): string {
  return normalizePhone(phone) + "@" + STUDENT_LOGIN_DOMAIN;
}

/**
 * Is this address inside the reserved phone-mapping namespace?
 *
 * It matters because a REAL email is now allowed to become a student's login (see
 * warden-register-student). Without this check a warden could type
 * "9812345678@student.hostelpro.local" into the email box and mint the login id that belongs
 * to a phone number they do not control — and, worse, permanently block the resident who
 * actually holds that number from ever being registered, because GoTrue would report the
 * address as taken and nothing in the UI would explain why.
 *
 * The domain is not a real mail domain, so nobody can legitimately own an address in it.
 * Only studentLoginEmail() may write here.
 */
export function isStudentLoginEmail(email: string): boolean {
  return email.trim().toLowerCase().endsWith("@" + STUDENT_LOGIN_DOMAIN);
}

function isRealDate(iso: string): boolean {
  const [y, m, d] = iso.split("-").map(Number);
  if (m < 1 || m > 12 || d < 1 || d > 31) return false;
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

/** Today in UTC as YYYY-MM-DD — the same calendar day Postgres current_date reports. */
export function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}
