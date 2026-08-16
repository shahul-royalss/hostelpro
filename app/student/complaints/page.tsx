import { MobilePage } from "@/components/shell/role-shells";
import { GlassCard } from "@/components/shared/glass-card";
import { EmptyState } from "@/components/shared/empty-state";
import { ComplaintsView, type ComplaintWithEvents } from "@/components/student/complaints-view";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getComplaintEvents, getMyComplaints, getMyStudent } from "@/lib/queries/student";
import { UserX } from "lucide-react";

export default async function StudentComplaintsPage({ searchParams }: { searchParams: Promise<{ new?: string }> }) {
  const { user, ctx } = await requireHostelContext("student");
  const { new: openNew } = await searchParams;
  const supabase = await createClient();
  const student = await getMyStudent(supabase, user.id);

  let complaints: ComplaintWithEvents[] = [];
  if (student) {
    const rows = await getMyComplaints(supabase, student.id);
    const [events, photos] = await Promise.all([
      getComplaintEvents(
        supabase,
        rows.map((r) => r.id),
      ),
      Promise.all(rows.map((r) => signedUrl("complaint-photos", r.photo_url, ctx.hostel.id))),
    ]);
    complaints = rows.map((r, i) => ({
      ...r,
      events: events.filter((e) => e.complaint_id === r.id),
      photoSrc: photos[i],
    }));
  }

  return (
    <MobilePage role="student" title="Complaints" subtitle={`${complaints.filter((c) => c.status !== "resolved").length} open`}>
      {!student ? (
        <GlassCard>
          <EmptyState icon={UserX} title="No student record linked" description="Ask your warden to check your registration." />
        </GlassCard>
      ) : (
        <ComplaintsView complaints={complaints} writable={ctx.writable} openNew={openNew === "1"} />
      )}
    </MobilePage>
  );
}
