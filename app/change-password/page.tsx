import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { AuthCard } from "@/components/auth/auth-card";
import { ChangePasswordForm } from "@/components/auth/change-password-form";
import { getSessionUser } from "@/lib/permissions";
import { ROLE_HOME } from "@/lib/roles";

export const metadata: Metadata = { title: "Set a new password" };

export default async function ChangePasswordPage() {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  const forced = user.must_change_password;

  return (
    <AuthCard
      title={forced ? "Set a new password" : "Change password"}
      subtitle={
        forced
          ? "You signed in with a temporary password. Choose a new one to continue."
          : "Choose a strong password you don't use elsewhere."
      }
      footer={
        forced ? undefined : (
          <Link href={ROLE_HOME[user.role]} className="text-sm font-medium text-navy hover:underline">
            ← Back
          </Link>
        )
      }
    >
      <ChangePasswordForm forced={forced} />
    </AuthCard>
  );
}
