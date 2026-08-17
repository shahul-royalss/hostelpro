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
     */
    "/((?!_next/static/|_next/image/|favicon\\.ico$|icons/|manifest\\.webmanifest$|robots\\.txt$).*)",
  ],
};
