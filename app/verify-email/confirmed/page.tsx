import type { Metadata } from "next";
import { MailCheck, TriangleAlert } from "lucide-react";
import { AuthCard } from "@/components/auth/auth-card";

export const metadata: Metadata = {
  title: "Email confirmed",
  robots: { index: false, follow: false },
};

/**
 * Where the confirmation link in a NIVORA verification email lands.
 *
 * ═══ THIS PAGE DECIDES NOTHING ═══
 *
 * By the time a browser reaches this URL, GoTrue has already done the only thing that matters:
 * the link points at /auth/v1/verify, which matches the single-use token, records the login in
 * auth.mfa_amr_claims and auth.audit_log_entries, and only THEN issues the 302 that lands here.
 * The address is proved before this component renders.
 *
 * So there is deliberately no session exchange, no cookie write, and no database read. The
 * `?code=` GoTrue appends is ignored on purpose: it is a PKCE grant whose verifier lives in the
 * mobile app that asked for the link, so this browser could not redeem it even if there were a
 * reason to - and there is not. Redeeming it would sign this browser into the web app as a side
 * effect of confirming an address, which is a surprise nobody asked for and a real one on a
 * shared computer.
 *
 * What the mobile app does instead is ask its own server on the next resume, and that server
 * reads GoTrue's record of the click (public.email_link_proof). See
 * db/migrations/2026-09-01-email-link-verification.sql.
 *
 * ═══ WHICH MAKES THE FAILURE CASE THE ONLY INTERESTING ONE ═══
 *
 * GoTrue reports a dead link on the QUERY STRING rather than by refusing to redirect -
 * `?error=access_denied&error_code=otp_expired` - exactly as the reset-password callback
 * documents. That is the one thing worth branching on here: a person who clicked an hour-old
 * link and is told "confirmed" would go back to the app, find the banner still there, and have
 * no way to tell which of the two screens was lying.
 *
 * ═══ MIDDLEWARE ═══
 *
 * "/verify-email" is in PUBLIC_PATHS in lib/supabase/middleware.ts. The browser that opens a
 * link from an inbox is usually not signed into the web app, and behind the session gate every
 * confirmation would land on /login looking like a failure.
 */
export default async function EmailConfirmedPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; error_code?: string; error_description?: string }>;
}) {
  const sp = await searchParams;
  const failed = Boolean(sp.error || sp.error_code);
  // `otp_expired` covers both halves of what GoTrue means by it: a link past its TTL, and a link
  // that was already used. Neither is worth distinguishing to the person holding the phone,
  // because the remedy is identical.
  const expired = (sp.error_code ?? "").includes("expired");

  if (failed) {
    return (
      <AuthCard
        title="That link did not work"
        subtitle={
          expired
            ? "Confirmation links expire, and each one can only be opened once."
            : "This confirmation link is no longer valid."
        }
      >
        <div className="flex flex-col items-center gap-4 text-center">
          <div className="flex h-12 w-12 items-center justify-center rounded-control bg-amber-100 text-amber-700">
            <TriangleAlert className="h-6 w-6" strokeWidth={1.75} aria-hidden />
          </div>
          <p className="text-sm text-muted">
            Open NIVORA on your phone, tap <strong>Verify now</strong> on the banner at the top of
            your home screen, and use the newest email it sends you. Only the most recent link
            works.
          </p>
          <p className="text-caption text-muted/80">
            Nothing has changed on your account, and you can keep using NIVORA in the meantime.
          </p>
        </div>
      </AuthCard>
    );
  }

  return (
    <AuthCard
      title="Email confirmed"
      subtitle="Thanks — that address belongs to you."
    >
      <div className="flex flex-col items-center gap-4 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-control bg-emerald-100 text-emerald-700">
          <MailCheck className="h-6 w-6" strokeWidth={1.75} aria-hidden />
        </div>
        <p className="text-sm text-muted">
          You can close this page and go back to NIVORA. It checks again every time you return to
          the app, so the reminder will be gone.
        </p>
        <p className="text-caption text-muted/80">
          You do not need to sign in here. This page only confirms the address.
        </p>
      </div>
    </AuthCard>
  );
}
