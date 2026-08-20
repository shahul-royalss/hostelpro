import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Run on everything except genuinely static assets served from /public and /_next.
     *
     * SECURITY: do NOT exclude by file extension (e.g. `.*\.(png|jpg|svg)$`). That pattern
     * matches ANY url ending in that extension — including application routes such as
     * `/owner/x.png` — so a request could skip the session refresh, the security headers,
     * the forced-password-change gate, the MFA step-up and the role↔route check while Next
     * still dispatched a Server Action posted to that URL. Only real asset prefixes and the
     * specific files we ship in /public are listed here.
     *
     * `.well-known/` is excluded as a PATH PREFIX, which is safe for the same reason the
     * extension form was not: a prefix cannot match an application route, because no route
     * lives under it. It has to be excluded — Android fetches /.well-known/assetlinks.json
     * unauthenticated to verify the Digital Asset Links association for the TWA, and
     * middleware was answering that request with a 307 to /login. Verification would have
     * failed silently and the installed app would have shown a URL bar. RFC 8615 reserves
     * this prefix for exactly this kind of public, unauthenticated metadata.
     */
    "/((?!_next/static/|_next/image/|favicon\\.ico$|icons/|\\.well-known/|manifest\\.webmanifest$|robots\\.txt$).*)",
  ],
};
