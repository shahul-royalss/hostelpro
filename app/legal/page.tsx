import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, FileText, ShieldCheck, UserMinus } from "lucide-react";
import { Callout, DocHeader } from "./layout";

const UPDATED = "2026-08-21";

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "HostelPro";

export const metadata: Metadata = {
  title: "Legal",
  description:
    "Privacy Policy, Terms of Service and data deletion request for HostelPro — hostel and PG management software.",
};

/** Rendered per-request so middleware's CSP nonce reaches the script tags — see
 *  the note in `app/legal/privacy/page.tsx`. The page itself reads no session,
 *  no cookies and no data, so it remains statically renderable. */
export const dynamic = "force-dynamic";

const DOCUMENTS = [
  {
    href: "/legal/privacy",
    icon: ShieldCheck,
    title: "Privacy Policy",
    blurb:
      "Exactly what personal data is held about residents, guardians, visitors and staff; why; for how long; who else can reach it; and your rights under the DPDP Act 2023 and the GDPR.",
  },
  {
    href: "/legal/terms",
    icon: FileText,
    title: "Terms of Service",
    blurb:
      "The terms the service is provided on: accounts issued by your hostel, acceptable use, what read-only mode means when a subscription lapses, and limitation of liability.",
  },
  {
    href: "/legal/account-deletion",
    icon: UserMinus,
    title: "Delete your account and data",
    blurb:
      "How to ask for your account and personal data to be deleted, what gets removed, what has to be kept for legal reasons, and how long it takes.",
  },
] as const;

export default function LegalIndexPage() {
  return (
    <>
      <DocHeader
        title="Legal"
        summary={
          APP_NAME +
          " is hostel and PG management software used by hostel owners and their staff. These are the documents that govern it. They are public: you do not need an account to read them."
        }
        updated={UPDATED}
      />

      <ul className="grid gap-4">
        {DOCUMENTS.map((doc) => (
          <li key={doc.href}>
            <Link
              href={doc.href}
              className="glass-card group flex items-start gap-4 p-5 transition-all hover:bg-white/80 hover:shadow-glass-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-navy/30 md:p-6"
            >
              <span className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-control bg-navy text-white shadow-sm">
                <doc.icon className="h-5 w-5" strokeWidth={1.75} />
              </span>
              <span className="min-w-0 flex-1">
                <span className="flex items-center gap-2 text-card-title text-navy">
                  {doc.title}
                  <ArrowRight className="h-4 w-4 shrink-0 text-muted transition-transform group-hover:translate-x-0.5 group-hover:text-navy" />
                </span>
                <span className="mt-1 block text-sm leading-6 text-charcoal/90">{doc.blurb}</span>
              </span>
            </Link>
          </li>
        ))}
      </ul>

      <div className="mt-6">
        <Callout title="How accounts work here">
          <p>
            There is no public sign-up. The platform administrator creates hostel Owner accounts,
            Owners create Manager and Warden accounts, and a Warden registers residents. Residents
            sign in with the phone number their hostel registered. If your details are wrong, your
            hostel&rsquo;s Warden or Owner can correct them in the app straight away — that is
            faster than writing to us.
          </p>
          <p>
            Already have an account? <Link href="/login">Sign in</Link>.
          </p>
        </Callout>
      </div>
    </>
  );
}
