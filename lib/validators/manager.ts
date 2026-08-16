import { z } from "zod";
import { DAYS_OF_WEEK, EXPENSE_CATEGORIES, MEALS, REVENUE_SOURCES } from "@/lib/types";

const isoDate = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "Enter a valid date.")
  .refine((s) => !Number.isNaN(Date.parse(s)), "Enter a valid date.");

/**
 * Required, positive amount. Both forms are `noValidate`, so an empty field arrives as "" —
 * preprocess maps that to `undefined` so it fails as "required" instead of coercing to 0.
 */
const amount = z.preprocess(
  (v) => (v === "" || v === null ? undefined : v),
  z.coerce
    .number({ required_error: "Enter an amount.", invalid_type_error: "Enter an amount." })
    .positive("Amount must be greater than 0.")
    .max(99_999_999, "Amount is too large."),
);

const note = z
  .string()
  .trim()
  .max(500, "Note is too long (max 500 characters).")
  .transform((s) => (s.length ? s : null))
  .nullable()
  .optional();

export const expenseSchema = z.object({
  date: isoDate,
  category: z.enum(EXPENSE_CATEGORIES as [string, ...string[]]),
  amount,
  note,
});
export type ExpenseInput = z.infer<typeof expenseSchema>;

export const expenseUpdateSchema = expenseSchema.extend({
  id: z.string().uuid(),
  /** "1" when the user removed the existing receipt in the edit dialog */
  removeReceipt: z.enum(["0", "1"]).optional(),
});

export const revenueSchema = z.object({
  date: isoDate,
  source: z.enum(REVENUE_SOURCES as [string, ...string[]]),
  amount,
  note,
});
/** Raw (pre-validation) shape the client form sends — `amount` is the untrimmed field string. */
export type RevenueInput = z.input<typeof revenueSchema>;

export const revenueUpdateSchema = revenueSchema.extend({ id: z.string().uuid() });

export const idSchema = z.object({ id: z.string().uuid() });

export const taskStatusSchema = z.object({
  taskId: z.string().uuid(),
  status: z.enum(["pending", "in_progress", "done"]),
});
export type TaskStatusInput = z.infer<typeof taskStatusSchema>;

export const menuCellSchema = z.object({
  day: z.enum(DAYS_OF_WEEK as [string, ...string[]]),
  meal: z.enum(MEALS as [string, ...string[]]),
  items: z.string().max(400, "Keep each cell under 400 characters."),
});
export const menuSchema = z.array(menuCellSchema).min(1).max(DAYS_OF_WEEK.length * MEALS.length);
export type MenuCellInput = z.infer<typeof menuCellSchema>;

export const exportSchema = z.object({
  type: z.enum(["expenses", "revenue"]),
  month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/),
});
