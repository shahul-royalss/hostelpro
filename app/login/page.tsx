import type { Metadata } from "next";
import { AuthCard } from "@/components/auth/auth-card";
import { LoginForm } from "@/components/auth/login-form";

export const metadata: Metadata = { title: "Sign in" };

const ERRORS: Record<string, string> = {
  inactive: "This account has been deactivated. Contact your hostel owner.",
  "no-profile": "Your account isn't set up yet. Contact your administrator.",
  "no-hostel": "No hostel is linked to your account yet.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const sp = await searchParams;
  return (
    <AuthCard title="Welcome back" subtitle="Sign in to your hostel workspace">
      <LoginForm next={sp.next} initialError={sp.error ? ERRORS[sp.error] ?? null : null} />
    </AuthCard>
  );
}
