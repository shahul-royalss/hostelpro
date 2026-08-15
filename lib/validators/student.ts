import { z } from "zod";
import { COMPLAINT_CATEGORIES } from "@/lib/types";

export const createComplaintSchema = z.object({
  category: z.enum(COMPLAINT_CATEGORIES as [string, ...string[]], { message: "Pick a category" }),
  title: z.string().trim().min(3, "Give your complaint a short title").max(120, "Keep the title under 120 characters"),
  description: z.string().trim().max(2000, "Keep the description under 2000 characters").optional().or(z.literal("")),
});
export type CreateComplaintInput = z.infer<typeof createComplaintSchema>;

const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Pick a date");

export const applyLeaveSchema = z
  .object({
    fromDate: isoDate,
    toDate: isoDate,
    reason: z.string().trim().min(3, "Tell your warden why you need leave").max(500, "Keep the reason under 500 characters"),
  })
  .refine((v) => v.toDate >= v.fromDate, { path: ["toDate"], message: "End date can't be before the start date" });
export type ApplyLeaveInput = z.infer<typeof applyLeaveSchema>;
