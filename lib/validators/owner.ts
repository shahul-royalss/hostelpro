import { z } from "zod";
import { AUDIENCES } from "@/lib/types";

const uuid = z.string().uuid("Invalid id.");
const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Use a valid date.");

/* ───────────────────────── Announcements (OW-3) ───────────────────────── */

export const createAnnouncementSchema = z.object({
  title: z.string().trim().min(3, "Title needs at least 3 characters.").max(120, "Keep the title under 120 characters."),
  body: z.string().trim().min(3, "Message needs at least 3 characters.").max(4000, "Message is too long."),
  audience: z.enum(AUDIENCES as [string, ...string[]]),
});
export type CreateAnnouncementInput = z.infer<typeof createAnnouncementSchema>;

export const announcementIdSchema = z.object({ announcementId: uuid });

/* ───────────────────────── Staff (OW-4) ───────────────────────── */

export const createStaffSchema = z.object({
  role: z.enum(["manager", "warden"]),
  fullName: z.string().trim().min(2, "Enter the full name.").max(80),
  email: z.string().trim().email("Enter a valid email address."),
  phone: z
    .string()
    .trim()
    .regex(/^[\d\s+\-()]{8,16}$/, "Enter a valid phone number.")
    .optional()
    .or(z.literal("")),
});
export type CreateStaffInput = z.infer<typeof createStaffSchema>;

export const staffIdSchema = z.object({ userId: uuid });
export const staffStatusSchema = z.object({ userId: uuid, status: z.enum(["active", "inactive"]) });

/* ───────────────────────── Tasks (OW-4) ───────────────────────── */

export const createTaskSchema = z.object({
  title: z.string().trim().min(2, "Give the task a title.").max(160),
  description: z.string().trim().max(2000).optional().or(z.literal("")),
  dueDate: isoDate.optional().or(z.literal("")),
});
export type CreateTaskInput = z.infer<typeof createTaskSchema>;

export const updateTaskSchema = z.object({
  taskId: uuid,
  title: z.string().trim().min(2, "Give the task a title.").max(160).optional(),
  description: z.string().trim().max(2000).nullable().optional(),
  dueDate: isoDate.nullable().optional(),
  status: z.enum(["pending", "in_progress", "done"]).optional(),
});
export type UpdateTaskInput = z.infer<typeof updateTaskSchema>;

export const taskIdSchema = z.object({ taskId: uuid });

/* ───────────────────────── Hostel rules ───────────────────────── */

export const hostelRulesSchema = z.object({
  rules: z.string().trim().max(6000, "Rules text is too long."),
});

/* ───────────────────────── Students (OW-5) ───────────────────────── */

export const studentIdSchema = z.object({ studentId: uuid });
