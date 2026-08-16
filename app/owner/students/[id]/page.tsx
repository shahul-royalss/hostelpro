import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getStudentById } from "@/lib/queries/owner";
import { formatDate, formatPeriodMonth, toPeriodMonth } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { GlassCard } from "@/components/shared/glass-card";
import { Button } from "@/components/ui/button";
import { StudentProfile } from "@/components/owner/student-profile";

export const dynamic = "force-dynamic";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** OW-5 fallback — full-page read-only student profile. */
export default async function OwnerStudentDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { ctx } = await requireHostelContext("owner");
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();

  const supabase = await createClient();
  const student = await getStudentById(supabase, ctx.hostel.id, id);
  if (!student) notFound();

  const [photoUrl, idProofUrl] = await Promise.all([signedUrl("student-docs", student.photo_url), signedUrl("student-docs", student.id_proof_url)]);

  return (
    <>
      <PageHeader
        eyebrow="Student profile"
        title={student.full_name}
        description={
          student.status === "vacated"
            ? `Read-only · this student has vacated${student.vacated_at ? ` (${formatDate(student.vacated_at)})` : ""}. Historical record only.`
            : `Read-only · fee status for ${formatPeriodMonth(toPeriodMonth())}. Contact your warden to correct details.`
        }
        actions={
          <Button asChild variant="secondary" size="sm">
            <Link href="/owner/students">
              <ArrowLeft /> All students
            </Link>
          </Button>
        }
      />
      <div className="mx-auto max-w-2xl">
        <GlassCard>
          <StudentProfile student={student} photoUrl={photoUrl} idProofUrl={idProofUrl} />
        </GlassCard>
      </div>
    </>
  );
}
