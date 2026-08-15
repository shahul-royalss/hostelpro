"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { resolveLoginEmail } from "@/lib/utils";
import { ROLE_HOME, type UserRole } from "@/lib/roles";
import { changePasswordSchema, loginSchema } from "@/lib/validators/auth";
import { fail, type ActionResult } from "@/lib/types";
import { getSessionUser, errorMessage } from "@/lib/permissions";
import { clearMustChangePassword } from "@/lib/auth/accounts";

/**
 * Single login for all roles (§3). Accepts email OR phone (students).
 * On success redirects to the role home (or /change-password on first login).
 */
export async function signIn(_prev: ActionResult | null, formData: FormData): Promise<ActionResult> {
  const parsed = loginSchema.safeParse({
    identifier: formData.get("identifier"),
    password: formData.get("password"),
    next: formData.get("next") ?? undefined,
  });
  if (!parsed.success) {
    return fail("Check your details and try again.", parsed.error.flatten().fieldErrors);
  }
  const { identifier, password, next } = parsed.data;
  const email = resolveLoginEmail(identifier);

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error || !data.user) {
    if (error?.message?.toLowerCase().includes("banned")) {
      return fail("This account has been deactivated. Contact your hostel owner.");
    }
    return fail("Incorrect email/phone or password.");
  }

  // Profile row → role, status, must_change_password
  const { data: profile } = await supabase
    .from("users")
    .select("role, status, must_change_password, deleted_at")
    .eq("id", data.user.id)
    .maybeSingle();

  if (!profile || profile.deleted_at) {
    await supabase.auth.signOut();
    return fail("Your account isn't set up yet. Contact your administrator.");
  }
  if (profile.status !== "active") {
    await supabase.auth.signOut();
    return fail("This account has been deactivated. Contact your hostel owner.");
  }

  const role = profile.role as UserRole;
  const meta = data.user.app_metadata as { must_change_password?: boolean } | undefined;
  const mustChange = profile.must_change_password || meta?.must_change_password === true;

  if (mustChange) redirect("/change-password");
  const target = next && next.startsWith(ROLE_HOME[role]) ? next : ROLE_HOME[role];
  redirect(target);
}

/** First-login forced change + regular self-service change (§4.9). */
export async function changePassword(_prev: ActionResult | null, formData: FormData): Promise<ActionResult> {
  const parsed = changePasswordSchema.safeParse({
    password: formData.get("password"),
    confirm: formData.get("confirm"),
  });
  if (!parsed.success) {
    return fail("Please fix the errors below.", parsed.error.flatten().fieldErrors);
  }
  const user = await getSessionUser();
  if (!user) redirect("/login");

  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) {
    return fail(
      /same password|different from the old/i.test(error.message)
        ? "Choose a password different from your temporary one."
        : errorMessage(error),
    );
  }

  // Clear the flag in DB (RLS allows self-update) and in app_metadata (admin API, if configured)
  await supabase.from("users").update({ must_change_password: false }).eq("id", user.id);
  try {
    await clearMustChangePassword(user.id);
  } catch {
    // Service role key not configured — DB flag is cleared; middleware falls back to it.
  }

  redirect(ROLE_HOME[user.role]);
}

/** Used by the change-password page to know whether this is a forced first-login change. */
export async function getPasswordChangeContext(): Promise<{ forced: boolean; role: UserRole } | null> {
  const user = await getSessionUser();
  if (!user) return null;
  return { forced: user.must_change_password, role: user.role };
}
