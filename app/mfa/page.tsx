import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { AuthCard } from "@/components/auth/auth-card";
import { MfaChallengeForm } from "@/components/auth/mfa-challenge-form";
import { getSessionUser } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { ROLE_HOME } from "@/lib/roles";
import { signOut } from "@/lib/actions/session";

export const metadata: Metadata = { title: "Two-factor authentication" };

/** Step-up page: shown after password sign-in when the account has a verified TOTP factor. */
export default async function MfaPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  const supabase = await createClient();
  const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (aal?.nextLevel !== "aal2" || aal.currentLevel === "aal2") redirect(ROLE_HOME[user.role]);
  const { next } = await searchParams;

  return (
    <AuthCard
      title="Two-factor authentication"
      subtitle="Enter the 6-digit code from your authenticator app to finish signing in."
      footer={
        <form action={signOut}>
          <button type="submit" className="text-sm font-medium text-muted hover:text-navy">
            Use a different account
          </button>
        </form>
      }
    >
      <MfaChallengeForm next={next} />
    </AuthCard>
  );
}
