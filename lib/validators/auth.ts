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
     * The password the account currently has: the one the holder chose, or the temporary one
     * they were handed.
     *
     * STILL `optional()` HERE, AND REQUIRED BY THE ACTION. Supabase Auth refuses a password
     * change without it on both paths (this project runs
     * GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD), so changePassword() rejects an
     * absent value with a sentence written for whichever path the DB says applies — "enter the
     * temporary password you were given" reads very differently from "enter your current
     * password", and this schema cannot tell which reader it has. Making it `.min(1)` here
     * would spend that distinction on a generic message.
     */
    currentPassword: z.string().optional(),
    /**
     * ═══ 2026-09-01: THE RULE GREW, BECAUSE SUPABASE'S WAS ALWAYS LONGER ═══
     * This held length + a letter + a digit. The project runs GoTrue's character-class policy,
     * which wants one of each of lower case, upper case, digits and symbols. Walked through a
     * real account on the live project with PUT /auth/v1/user:
     *
     *     "correct1horse"  -> 422 weak_password (characters)
     *     "Correct1horse"  -> 422 weak_password (characters)
     *     "correct1horse!" -> 422 weak_password (characters)
     *     "CORRECT1HORSE!" -> 422 weak_password (characters)
     *     "Correct1horse!" -> 200
     *
     * So this schema passed a password the server then refused, the strength meter above it
     * read "Good" at the same moment, and the sentence that came back said "at least 6
     * characters" while the form had just demanded eight. Three statements of the rule, none of
     * them the real one.
     *
     * PASSWORD_MIN_LENGTH stays at 8 although GoTrue would take 6: being STRICTER than the
     * server tells nobody a lie, and 8 is the number every screen in this product already says.
     * Mirrored rule-for-rule by _Rule in
     * nivora_app/lib/features/auth/change_password_screen.dart.
     */
    password: z
      .string()
      .min(PASSWORD_MIN_LENGTH, `Use at least ${PASSWORD_MIN_LENGTH} characters`)
      .max(200, "That password is too long")
      // The lower-case rule keeps the old "letter" wording: it is already on people's screens,
      // and a password with a capital and no small letter is the rarer mistake to explain.
      .regex(/[a-z]/, "Include at least one letter")
      .regex(/\d/, "Include at least one number")
      .regex(/[A-Z]/, "Include at least one capital letter")
      // Wider than the symbol set GoTrue names in its error text — that set is its own default,
      // and a password built from a character just outside it should be refused here, where the
      // message is written for a person.
      .regex(/[^A-Za-z0-9\s]/, "Include at least one symbol, like ! or @"),
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, { path: ["confirm"], message: "Passwords don't match" })
  .refine((v) => v.currentPassword !== v.password, {
    path: ["password"],
    message: "Choose a password different from your current one",
  });
export type ChangePasswordInput = z.infer<typeof changePasswordSchema>;
