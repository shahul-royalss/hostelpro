"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { getSessionUser, errorMessage } from "@/lib/permissions";
import { fail, ok, type ActionResult } from "@/lib/types";
import { LIMITS, rateLimit } from "@/lib/rate-limit";
import { audit } from "@/lib/audit";
import { ROLE_HOME } from "@/lib/roles";

/**
 * Two-factor authentication (TOTP) via Supabase Auth MFA (checklist §3, §30).
 *  • any user may enrol an authenticator app; roles in MFA_REQUIRED_ROLES must
 *  • after enrolment every sign-in requires a 6-digit code (middleware enforces aal2)
 *  • disabling requires an aal2 session (i.e. the code was entered this session)
 */

const codeSchema = z.object({
  factorId: z.string().uuid(),
  code: z.string().trim().regex(/^\d{6}$/, "Enter the 6-digit code from your authenticator app"),
});

export interface MfaStatus {
  enrolled: boolean; // a verified TOTP factor exists
  factorId: string | null;
  currentLevel: "aal1" | "aal2" | null;
  required: boolean; // role listed in MFA_REQUIRED_ROLES
}

export async function getMfaStatus(): Promise<MfaStatus | null> {
  const user = await getSessionUser();
  if (!user) return null;
  const supabase = await createClient();
  const [{ data: factors }, { data: aal }] = await Promise.all([
    supabase.auth.mfa.listFactors(),
    supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
  ]);
  const verified = factors?.totp?.find((f) => f.status === "verified") ?? null;
  const required = (process.env.MFA_REQUIRED_ROLES ?? "")
    .split(",")
    .map((s) => s.trim())
    .includes(user.role);
  return {
    enrolled: !!verified,
    factorId: verified?.id ?? null,
    currentLevel: (aal?.currentLevel as "aal1" | "aal2" | null) ?? null,
    required,
  };
}

/** Start enrolment: returns the QR code (SVG data URI) + secret for manual entry. */
export async function startTotpEnrollment(): Promise<ActionResult<{ factorId: string; qrCode: string; secret: string; uri: string }>> {
  try {
    const user = await getSessionUser();
    if (!user) return fail("Signed out.");
    const supabase = await createClient();
    // Remove any stale unverified factors so re-tries don't pile up
    const { data: factors } = await supabase.auth.mfa.listFactors();
    for (const f of factors?.totp ?? []) {
      if (f.status !== "verified") await supabase.auth.mfa.unenroll({ factorId: f.id });
    }
    const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: `NIVORA (${user.role})` });
    if (error || !data) return fail(errorMessage(error ?? new Error("Could not start enrolment.")));
    return ok({ factorId: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret, uri: data.totp.uri });
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Confirm enrolment with the first code → factor becomes verified, session becomes aal2. */
export async function confirmTotpEnrollment(input: { factorId: string; code: string }): Promise<ActionResult> {
  const parsed = codeSchema.safeParse(input);
  if (!parsed.success) return fail("Enter the 6-digit code from your authenticator app.");
  try {
    const user = await getSessionUser();
    if (!user) return fail("Signed out.");
    const rl = await rateLimit(`mfa:${user.id}`, LIMITS.mfaVerifyPerUser.max, LIMITS.mfaVerifyPerUser.windowSeconds, true);
    if (!rl.allowed) return fail("Too many attempts. Please wait a few minutes and try again.");

    const supabase = await createClient();
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: parsed.data.factorId, code: parsed.data.code });
    if (error) {
      await audit("auth.mfa.failed", { targetType: "user", targetId: user.id, meta: { phase: "enroll" } });
      return fail("That code didn't work. Check the time on your phone and try again.");
    }
    await audit("auth.mfa.enrolled", { targetType: "user", targetId: user.id });
    return ok(undefined, "Two-factor authentication is on");
  } catch (e) {
    return fail(errorMessage(e));
  }
}

/** Login step-up: verify a code against the user's verified factor. */
export async function verifyTotpChallenge(_prev: ActionResult | null, formData: FormData): Promise<ActionResult> {
  const code = String(formData.get("code") ?? "").trim();
  const next = String(formData.get("next") ?? "");
  if (!/^\d{6}$/.test(code)) return fail("Enter the 6-digit code from your authenticator app.");
  const user = await getSessionUser();
  if (!user) redirect("/login");

  const rl = await rateLimit(`mfa:${user.id}`, LIMITS.mfaVerifyPerUser.max, LIMITS.mfaVerifyPerUser.windowSeconds, true);
  if (!rl.allowed) return fail("Too many attempts. Please wait a few minutes and try again.");

  const supabase = await createClient();
  const { data: factors } = await supabase.auth.mfa.listFactors();
  const factor = factors?.totp?.find((f) => f.status === "verified");
  if (!factor) redirect(ROLE_HOME[user.role]);

  const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code });
  if (error) {
    await audit("auth.mfa.failed", { targetType: "user", targetId: user.id, meta: { phase: "login" } });
    return fail("That code didn't work. Try again.");
  }
  await audit("auth.mfa.verified", { targetType: "user", targetId: user.id });

  const home = ROLE_HOME[user.role];
  const target = next.startsWith("/") && !next.startsWith("//") && (next === home || next.startsWith(home + "/") || next.startsWith("/security") || next === "/change-password") ? next : home;
  redirect(user.must_change_password ? "/change-password" : target);
}

/** Turn 2FA off (requires the code to have been entered this session — aal2). */
export async function disableTotp(input: { factorId: string; code: string }): Promise<ActionResult> {
  const parsed = codeSchema.safeParse(input);
  if (!parsed.success) return fail("Enter the 6-digit code from your authenticator app.");
  try {
    const user = await getSessionUser();
    if (!user) return fail("Signed out.");
    const required = (process.env.MFA_REQUIRED_ROLES ?? "").split(",").map((s) => s.trim()).includes(user.role);
    if (required) return fail("Two-factor authentication is mandatory for your role and can't be turned off.");

    const rl = await rateLimit(`mfa:${user.id}`, LIMITS.mfaVerifyPerUser.max, LIMITS.mfaVerifyPerUser.windowSeconds, true);
    if (!rl.allowed) return fail("Too many attempts. Please wait a few minutes and try again.");

    const supabase = await createClient();
    // Re-verify the code right now (reauthentication for a sensitive action)
    const { error: verifyErr } = await supabase.auth.mfa.challengeAndVerify({ factorId: parsed.data.factorId, code: parsed.data.code });
    if (verifyErr) return fail("That code didn't work. Try again.");
    const { error } = await supabase.auth.mfa.unenroll({ factorId: parsed.data.factorId });
    if (error) return fail(errorMessage(error));
    await audit("auth.mfa.unenrolled", { targetType: "user", targetId: user.id });
    return ok(undefined, "Two-factor authentication turned off");
  } catch (e) {
    return fail(errorMessage(e));
  }
}
