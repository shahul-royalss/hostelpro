import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getMfaStatus } from "@/lib/actions/mfa";
import { getSessionUser } from "@/lib/permissions";
import { ROLE_HOME } from "@/lib/roles";
import { MfaManage } from "@/components/auth/mfa-manage";
import { PageHeader } from "@/components/shared/page-header";

export const metadata: Metadata = { title: "Two-factor authentication" };

/**
 * /security/mfa — available to every role. Rendered as a plain centered page (no role shell)
 * so it works for desktop and mobile roles alike and is reachable even before enrolment is complete.
 */
export default async function MfaSettingsPage({ searchParams }: { searchParams: Promise<{ required?: string }> }) {
  const user = await getSessionUser();
  if (!user) redirect("/login");
  const status = await getMfaStatus();
  if (!status) redirect("/login");
  const { required } = await searchParams;

  return (
    <div className="mx-auto w-full max-w-2xl px-page-mobile py-8 md:px-page-desktop">
      <Link href={ROLE_HOME[user.role]} className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-navy hover:underline">
        <ArrowLeft className="h-4 w-4" /> Back to app
      </Link>
      <PageHeader eyebrow="Security" title="Two-factor authentication" description={`Signed in as ${user.full_name}`} />
      <MfaManage status={status} required={status.required || required === "1"} />
    </div>
  );
}
