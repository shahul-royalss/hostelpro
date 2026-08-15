import { z } from "zod";

/* ───────────────────────── Create Owner + Hostel wizard (SA-2) ───────────────────────── */

const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Pick a valid date");

export const ownerStepSchema = z.object({
  name: z.string().trim().min(2, "Enter the owner's full name").max(120),
  email: z.string().trim().email("Enter a valid email address").max(200),
  phone: z
    .string()
    .trim()
    .min(10, "Enter a valid 10-digit phone number")
    .max(16)
    .regex(/^[\d\s+\-()]+$/, "Enter a valid phone number"),
});

export const hostelStepSchema = z
  .object({
    name: z.string().trim().min(2, "Enter the hostel name").max(120),
    floors: z.coerce.number({ invalid_type_error: "Enter the number of floors" }).int("Floors must be a whole number").min(1, "At least 1 floor").max(50, "Maximum 50 floors"),
    rooms: z.coerce.number({ invalid_type_error: "Enter the number of rooms" }).int("Rooms must be a whole number").min(1, "At least 1 room").max(5000, "Maximum 5,000 rooms"),
    bedsPerRoom: z.coerce.number({ invalid_type_error: "Enter beds per room" }).int().min(1, "At least 1 bed per room").max(12, "Maximum 12 beds per room"),
    address: z.string().trim().max(500).optional().or(z.literal("")),
  })
  .refine((v) => v.rooms >= v.floors, { path: ["rooms"], message: "Add at least one room per floor" });

export const subscriptionStepSchema = z
  .object({
    startDate: isoDate,
    endDate: isoDate,
    amount: z.coerce.number({ invalid_type_error: "Enter the amount" }).min(0, "Amount cannot be negative").max(99_999_999, "Amount is too large"),
    notes: z.string().trim().max(500).optional().or(z.literal("")),
  })
  .refine((v) => v.endDate > v.startDate, { path: ["endDate"], message: "End date must be after the start date" });

export const createOwnerHostelSchema = z.object({
  owner: ownerStepSchema,
  hostel: hostelStepSchema,
  subscription: subscriptionStepSchema,
});
export type CreateOwnerHostelInput = z.infer<typeof createOwnerHostelSchema>;

/* ───────────────────────── Subscription / hostel actions (SA-1, SA-3, SA-4) ───────────────────────── */

export const renewSubscriptionSchema = z.object({
  hostelId: z.string().uuid(),
  newEndDate: isoDate,
  amount: z.coerce.number({ invalid_type_error: "Enter the amount" }).min(0, "Amount cannot be negative").max(99_999_999, "Amount is too large"),
  notes: z.string().trim().max(500).optional().or(z.literal("")),
});
export type RenewSubscriptionInput = z.infer<typeof renewSubscriptionSchema>;

export const setHostelStatusSchema = z.object({
  hostelId: z.string().uuid(),
  status: z.enum(["active", "suspended"]),
});
export type SetHostelStatusInput = z.infer<typeof setHostelStatusSchema>;

export const regenerateOwnerPasswordSchema = z.object({
  ownerUserId: z.string().uuid(),
});
export type RegenerateOwnerPasswordInput = z.infer<typeof regenerateOwnerPasswordSchema>;
