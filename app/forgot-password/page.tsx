import type { Metadata } from "next";
import { AuthCard } from "@/components/auth/auth-card";
import { ForgotPasswordForm } from "@/components/auth/forgot-password-form";

export const metadata: Metadata = {
  title: "Forgot password",
  // A reset page has no business in an index, and the crawl budget is not the reason.
  robots: { index: false, follow: false },
};

/**
 * Deliberately a plain server component with no session read.
 *
 * Nothing here depends on who is asking - the whole point of the form is that it answers
 * identically for everyone - so it prerenders as static and costs no Auth round trip. Adding a
 * getSessionUser() call to redirect the already-signed-in would buy a nicety and pay ~200ms on
 * the one page a locked-out user reaches on a bad connection.
 *
 * MIDDLEWARE: "/forgot-password" must be added to PUBLIC_PATHS in lib/supabase/middleware.ts or
 * every signed-out visitor is bounced to /login - which is the entire audience for this page.
 */
export default function ForgotPasswordPage() {
  return (
    <AuthCard title="Forgot your password?" subtitle="We'll get you back in - it depends on how you sign in.">
      <ForgotPasswordForm />
    </AuthCard>
  );
}
