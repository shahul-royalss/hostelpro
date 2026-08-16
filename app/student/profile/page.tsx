import Link from "next/link";
import { CalendarDays, ChevronRight, ExternalLink, KeyRound, Phone, UserX } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { UserAvatar } from "@/components/ui/avatar";
import { DetailRow, DetailSection } from "@/components/student/detail-rows";
import { LogoutButton } from "@/components/student/logout-button";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getMyStudent } from "@/lib/queries/student";
import { formatDate, formatINR } from "@/lib/utils";

export default async function StudentProfilePage() {
  const { user } = await requireHostelContext("student");
  const supabase = await createClient();
  const student = await getMyStudent(supabase, user.id);

  const [photoSrc, idProofHref] = student
    ? await Promise.all([signedUrl("student-docs", student.photo_url), signedUrl("student-docs", student.id_proof_url)])
    : [null, null];

  return (
    <MobilePage role="student" title="My details">
      {!student ? (
        <GlassCard>
          <EmptyState icon={UserX} title="No student record linked" description="Ask your warden to check your registration." />
          <div className="mt-2">
            <LogoutButton />
          </div>
        </GlassCard>
      ) : (
        <div className="flex flex-col gap-4">
          {/* Header card */}
          <GlassCard strong className="flex flex-col items-center p-6 text-center">
            <UserAvatar name={student.full_name} src={photoSrc} size="xl" className="ring-4 ring-white/80 shadow-glass" />
            <h2 className="mt-3 text-[18px] font-bold text-navy">{student.full_name}</h2>
            <a href={`tel:${student.phone}`} className="mt-1 inline-flex items-center gap-1.5 text-sm text-charcoal/80">
              <Phone className="h-3.5 w-3.5 text-muted" />
              {student.phone}
            </a>
            <div className="mt-3 flex flex-wrap items-center justify-center gap-2">
              <StatusPill status={student.status} size="sm" dot />
              <span className="inline-flex items-center gap-1 text-[12px] text-muted">
                <CalendarDays className="h-3.5 w-3.5" />
                Joined {formatDate(student.date_of_joining, "MMM yyyy")}
              </span>
            </div>
          </GlassCard>

          <DetailSection title="Personal">
            <DetailRow label="Email" value={student.email} />
            <DetailRow label="Joined" value={formatDate(student.date_of_joining)} />
          </DetailSection>

          <DetailSection title="Guardian">
            <DetailRow label="Name" value={student.guardian_name} />
            <DetailRow
              label="Phone"
              value={student.guardian_phone}
              action={
                student.guardian_phone ? (
                  <a href={`tel:${student.guardian_phone}`} aria-label="Call guardian" className="rounded-full bg-navy/5 p-1.5 text-navy active:scale-95">
                    <Phone className="h-3.5 w-3.5" />
                  </a>
                ) : null
              }
            />
          </DetailSection>

          <DetailSection title="Address">
            <DetailRow label="Permanent address" value={student.permanent_address} stacked />
          </DetailSection>

          <DetailSection title="ID proof">
            <DetailRow
              label="Type"
              value={student.id_proof_type}
              action={
                idProofHref ? (
                  <a
                    href={idProofHref}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 rounded-full bg-navy px-2.5 py-1 text-[11px] font-semibold text-white active:scale-95"
                  >
                    View <ExternalLink className="h-3 w-3" />
                  </a>
                ) : null
              }
            />
          </DetailSection>

          <DetailSection title="Room & fee">
            <DetailRow label="Room" value={student.room ? `Room ${student.room.room_number}` : "Not assigned"} />
            <DetailRow label="Bed" value={student.bed ? `Bed ${student.bed.bed_number}` : "—"} />
            <DetailRow label="Floor" value={student.room?.floor ? `Floor ${student.room.floor.floor_number}` : "—"} />
            <DetailRow label="Monthly fee" value={`${formatINR(student.monthly_fee)}/mo`} />
          </DetailSection>

          <p className="px-1 text-center text-[12px] text-muted">To correct details, contact your warden.</p>

          <Link
            href="/change-password"
            className="glass-card flex items-center gap-3 p-4 transition-all active:scale-[0.98] hover:bg-white/80"
          >
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-navy/10 text-navy">
              <KeyRound className="h-[18px] w-[18px]" strokeWidth={1.75} />
            </span>
            <span className="flex-1 text-sm font-semibold text-navy">Change password</span>
            <ChevronRight className="h-5 w-5 text-muted" />
          </Link>

          <LogoutButton />
        </div>
      )}
    </MobilePage>
  );
}
