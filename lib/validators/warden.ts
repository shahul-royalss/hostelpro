import { z } from "zod";

/* ───────────────────────── shared pieces ───────────────────────── */

const phone10 = z
  .string()
  .trim()
  .transform((v) => v.replace(/\D/g, "").replace(/^91(?=\d{10}$)/, "").replace(/^0(?=\d{10}$)/, ""))
  .refine((v) => /^\d{10}$/.test(v), "Enter a valid 10-digit phone number");

const optionalPhone = z
  .string()
  .trim()
  .optional()
  .transform((v) => (v ? v.replace(/\D/g, "") : ""))
  .refine((v) => v === "" || /^\d{10}$/.test(v), "Enter a valid 10-digit phone number");

/** Real calendar date (rejects 2026-13-45, which Postgres would otherwise reject with a raw error). */
const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Pick a date")
  .refine((v) => {
    const d = new Date(`${v}T00:00:00Z`);
    return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
  }, "Pick a valid date");

/** Today's date (UTC+5:30 — hostel timezone) as YYYY-MM-DD, for "not in the future" checks. */
function todayISO() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
const isoDateNotFuture = isoDate.refine((v) => v <= todayISO(), "Date cannot be in the future");

const uuid = z.string().uuid("Invalid selection");

export const ID_PROOF_TYPES = ["Aadhaar", "PAN", "Passport", "Driving licence", "Voter ID", "Other"] as const;
export type IdProofType = (typeof ID_PROOF_TYPES)[number];

/* ───────────────────────── register student (WD-2) ───────────────────────── */

export const personalStepSchema = z.object({
  fullName: z.string().trim().min(2, "Enter the student's full name").max(120),
  phone: phone10,
  email: z.string().trim().email("Enter a valid email").max(160).or(z.literal("")).optional(),
  dateOfJoining: isoDate,
});

export const guardianStepSchema = z.object({
  guardianName: z.string().trim().min(2, "Enter the guardian's name").max(120),
  guardianPhone: phone10,
  permanentAddress: z.string().trim().min(6, "Enter the permanent address").max(600),
});

export const idProofStepSchema = z.object({
  idProofType: z.enum(ID_PROOF_TYPES, { errorMap: () => ({ message: "Choose an ID proof type" }) }),
});

export const roomFeeStepSchema = z.object({
  bedId: z.string().min(1, "Pick a free bed").uuid("Pick a free bed"),
  monthlyFee: z.coerce.number({ invalid_type_error: "Enter the monthly fee" }).min(1, "Enter the monthly fee").max(1_000_000),
});

/** Full payload validated server-side (files arrive separately via FormData). */
export const registerStudentSchema = personalStepSchema
  .merge(guardianStepSchema)
  .merge(idProofStepSchema)
  .merge(roomFeeStepSchema);
export type RegisterStudentInput = z.infer<typeof registerStudentSchema>;

/** Client-side form values (before coercion) — used by react-hook-form. */
export const registerFormSchema = z.object({
  fullName: personalStepSchema.shape.fullName,
  phone: personalStepSchema.shape.phone,
  email: personalStepSchema.shape.email,
  dateOfJoining: personalStepSchema.shape.dateOfJoining,
  guardianName: guardianStepSchema.shape.guardianName,
  guardianPhone: guardianStepSchema.shape.guardianPhone,
  permanentAddress: guardianStepSchema.shape.permanentAddress,
  idProofType: idProofStepSchema.shape.idProofType,
  bedId: roomFeeStepSchema.shape.bedId,
  monthlyFee: roomFeeStepSchema.shape.monthlyFee,
});
export type RegisterFormValues = z.input<typeof registerFormSchema>;

/* ───────────────────────── rooms (WD-3 / WD-4) ───────────────────────── */

export const updateRoomSchema = z.object({
  roomId: uuid,
  roomNumber: z.string().trim().min(1, "Enter a room number").max(12),
  capacity: z.coerce.number().int().min(1, "At least 1 bed").max(12, "Max 12 beds"),
});
export type UpdateRoomInput = z.infer<typeof updateRoomSchema>;

export const reassignBedSchema = z.object({
  studentId: uuid,
  bedId: uuid,
});

export const vacateStudentSchema = z.object({
  studentId: uuid,
});

/* ───────────────────────── fees (WD-5) ───────────────────────── */

export const recordPaymentSchema = z.object({
  studentId: uuid,
  periodMonth: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, "Invalid month"),
  amount: z.coerce.number({ invalid_type_error: "Enter an amount" }).positive("Amount must be greater than zero").max(10_000_000),
  mode: z.enum(["cash", "upi", "bank"]),
  paidOn: isoDateNotFuture,
  notes: z.string().trim().max(300).optional(),
});
export type RecordPaymentInput = z.infer<typeof recordPaymentSchema>;

/* ───────────────────────── leaves & visitors (WD-6) ───────────────────────── */

export const decideLeaveSchema = z.object({
  leaveId: uuid,
  status: z.enum(["approved", "rejected"]),
  note: z.string().trim().max(300).optional(),
});
export type DecideLeaveInput = z.infer<typeof decideLeaveSchema>;

export const logVisitorSchema = z.object({
  studentId: z.string().min(1, "Select the student being visited").uuid("Select the student being visited"),
  visitorName: z.string().trim().min(2, "Enter the visitor's name").max(120),
  visitorPhone: optionalPhone,
  relation: z.string().trim().max(60).optional(),
  checkInAt: z
    .string()
    .min(1, "Pick a check-in time")
    .refine((v) => !Number.isNaN(new Date(v).getTime()), "Pick a valid check-in time")
    // small clock-skew allowance; the client caps the picker at "now"
    .refine((v) => new Date(v).getTime() <= Date.now() + 5 * 60_000, "Check-in time cannot be in the future"),
});
export type LogVisitorInput = z.infer<typeof logVisitorSchema>;

export const checkOutVisitorSchema = z.object({
  visitorId: uuid,
});
