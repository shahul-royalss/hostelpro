import { z } from "zod";
import { PASSWORD_MIN_LENGTH } from "@/lib/auth/password";

export const loginSchema = z.object({
  identifier: z.string().trim().min(3, "Enter your email or phone number"),
  password: z.string().min(1, "Enter your password"),
  next: z.string().optional(),
});
export type LoginInput = z.infer<typeof loginSchema>;

export const changePasswordSchema = z
  .object({
    /**
     * Required for a voluntary change (checklist §8: sensitive actions need reauthentication),
     * omitted for the forced first-login change where the user has just proven the temporary
     * password. The server decides which rule applies — never the client.
     */
    currentPassword: z.string().optional(),
    password: z
      .string()
      .min(PASSWORD_MIN_LENGTH, `Use at least ${PASSWORD_MIN_LENGTH} characters`)
      .max(200, "That password is too long")
      .regex(/[A-Za-z]/, "Include at least one letter")
      .regex(/\d/, "Include at least one number"),
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, { path: ["confirm"], message: "Passwords don't match" })
  .refine((v) => v.currentPassword !== v.password, {
    path: ["password"],
    message: "Choose a password different from your current one",
  });
export type ChangePasswordInput = z.infer<typeof changePasswordSchema>;
