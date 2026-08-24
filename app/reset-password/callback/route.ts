import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { issueResetTicket } from "../ticket";

/**
 * Where the link in the reset email lands.
 *
 * It exists as a Route Handler rather than as part of the page because exchanging the link
 * WRITES the session cookies, and a Server Component cannot write cookies - lib/supabase/server
 * silently swallows the attempt there (see its setAll comment). Doing the exchange in the page
 * would appear to work and then drop the session on the floor.
 *
 * It also means the one-time code never survives into the address bar: this route consumes it
 * and redirects to a clean /reset-password, so the code cannot leak through a Referer header,
 * a screenshot, or the browser history of a shared phone.
 */
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams;

  // The destination is a hardcoded relative path. Nothing from the query string is ever used to
  // build it - a reset callback that honoured a `next=` parameter would be an open redirect
  // reachable from an email, which is the single most useful kind for a phisher.
  const done = (query = "") => {
    const res = NextResponse.redirect(new URL(`/reset-password${query}`, request.url));
    res.headers.set("Cache-Control", "private, no-store, max-age=0, must-revalidate");
    return res;
  };

  // GoTrue reports a dead link (`otp_expired`, `access_denied`) on the query string rather than
  // by failing the exchange, so this has to be checked before anything else.
  if (params.get("error") || params.get("error_code")) return done("?error=link");

  const supabase = await createClient();
  const code = params.get("code");
  const tokenHash = params.get("token_hash");
  const type = params.get("type");

  let userId: string | null = null;
  let isRecovery = false;

  if (code) {
    /**
     * The PKCE path - what Supabase's DEFAULT email template produces, because
     * `createServerClient` runs with `flowType: "pkce"` (@supabase/ssr).
     *
     * `sb_flow_id` names the verifier slot this particular request stored. Passing it through
     * makes the lookup exact: two reset requests from the same browser (a mistyped address,
     * then the right one) each get their own verifier instead of racing over one, and a wrong
     * id fails fast rather than borrowing another flow's verifier.
     */
    const flowId = params.get("sb_flow_id");
    const { data, error } = await supabase.auth.exchangeCodeForSession(code, flowId ? { flowId } : undefined);
    if (error || !data.user) return done("?error=link");
    userId = data.user.id;
    /**
     * GoTrue itself says what kind of link this was, and trusting its answer - rather than
     * assuming any successfully exchanged code is a recovery - is what stops a confirmation or
     * magic link from granting the no-reauthentication password change /reset-password offers.
     *
     * The cast is a typing gap, not a guess: `_exchangeCodeForSession` returns `redirectType`
     * at runtime (its own JSDoc example shows `redirectType: null`) but `AuthTokenResponse`
     * does not declare it. So the key is probed rather than read - PRESENT AND NOT "recovery"
     * is a refusal, and only a library version that omits it entirely falls back to trusting
     * the callback path, which is used by nothing but resetPasswordForEmail. Fail-closed on the
     * case that matters, without a library upgrade silently killing every reset.
     */
    const probe = data as unknown as { redirectType?: string | null };
    const declaredType = "redirectType" in probe ? (probe.redirectType ?? null) : undefined;
    isRecovery = declaredType === undefined || declaredType === "recovery";
  } else if (tokenHash && type === "recovery") {
    /**
     * The token-hash path - what you get after switching the email template to
     * `{{ .TokenHash }}` (docs/password-reset.md §5). Worth supporting because it is the only
     * variant that survives opening the mail on a DIFFERENT device from the one that asked:
     * PKCE keeps the verifier in a cookie on the requesting browser, so a link opened on a
     * laptop after asking on a phone cannot be exchanged.
     */
    const { data, error } = await supabase.auth.verifyOtp({ type: "recovery", token_hash: tokenHash });
    if (error || !data.user) return done("?error=link");
    userId = data.user.id;
    isRecovery = true;
  } else {
    return done("?error=link");
  }

  if (!isRecovery) return done("?error=link");

  try {
    await issueResetTicket(userId);
  } catch {
    // No signing secret - the ticket cannot be issued, so the reset page will refuse. Failing
    // closed here is the point: the alternative is a page that changes passwords on the
    // strength of a session alone.
    return done("?error=config");
  }

  return done();
}
