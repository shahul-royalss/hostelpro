import type { Metadata } from "next";
import Link from "next/link";
import { KeyRound, LinkIcon } from "lucide-react";
import { AuthCard } from "@/components/auth/auth-card";
import { ResetPasswordForm } from "@/components/auth/reset-password-form";
import { Button } from "@/components/ui/button";
import { getSessionUser } from "@/lib/permissions";
import { PASSWORD_MIN_LENGTH } from "@/lib/auth/password";
import { resetTicketHolder } from "./ticket";

export const metadata: Metadata = {
  title: "Choose a new password",
  robots: { index: false, follow: false },
};

/**
 * Reached only from /reset-password/callback, which consumes the one-time code and hands over a
 * recovery session plus a signed ticket.
 *
 * MIDDLEWARE: "/reset-password" must be added to PUBLIC_PATHS in lib/supabase/middleware.ts. It
 * covers this page AND /reset-password/callback (PUBLIC_PATHS is prefix-matched), and the
 * callback is the one that has to be reachable signed out - it is the request that creates the
 * session in the first place. Without it, every reset link redirects to /login and the flow is
 * dead on arrival.
 */
export default async function ResetPasswordPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const sp = await searchParams;

  /**
   * TWO independent checks, and both are load-bearing.
   *
   * The ticket says this session was created by opening a recovery link; the session says whose
   * it is. Requiring both is what stops /reset-password becoming a way around the
   * reauthentication that changePassword() demands for a voluntary change - see
   * app/reset-password/ticket.ts. The ticket is read first because it is a local HMAC check,
   * so an invalid one costs no Auth round trip.
   */
  const holder = await resetTicketHolder();
  const user = holder ? await getSessionUser() : null;
  const authorised = !!user && user.id === holder;

  if (!authorised) {
    return (
      <AuthCard
        title="This link has expired"
        subtitle={
          sp.error === "config"
            ? "Password resets are not configured on this deployment yet."
            : "Reset links are single-use and last 60 minutes."
        }
      >
        <div className="flex flex-col gap-5">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-control bg-sand-soft text-ink-sand">
            <LinkIcon className="h-6 w-6" strokeWidth={1.75} />
          </div>
          <p className="text-center text-subhead text-label-secondary">
            {sp.error === "config"
              ? "Ask your administrator to finish the email setup, then try again."
              : "Ask for a new one, and open it on this device - a link opened in a different browser cannot be used."}
          </p>
          <Button asChild size="xl">
            <Link href="/forgot-password">Request a new link</Link>
          </Button>
          <Link
            href="/login"
            className="rounded-control py-1 text-center text-footnote font-medium text-ink-navy underline-offset-4 hover:underline"
          >
            Back to sign in
          </Link>
        </div>
      </AuthCard>
    );
  }

  return (
    <AuthCard title="Choose a new password" subtitle={`Signing in as ${user.email ?? user.full_name}`}>
      <div className="flex flex-col gap-5">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-control bg-teal-soft text-ink-teal">
          <KeyRound className="h-6 w-6" strokeWidth={1.75} />
        </div>
        {/* PASSWORD_MIN_LENGTH is imported HERE, on the server, and passed down as a number -
            see the note in reset-password-form.tsx for what importing it in the client costs. */}
        <ResetPasswordForm minLength={PASSWORD_MIN_LENGTH} />
      </div>
    </AuthCard>
  );
}
