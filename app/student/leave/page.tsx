import { UserX } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { GlassCard } from "@/components/shared/glass-card";
import { EmptyState } from "@/components/shared/empty-state";
import { LeaveView } from "@/components/student/leave-view";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getMyLeaves, getMyStudent } from "@/lib/queries/student";

export default async function StudentLeavePage({ searchParams }: { searchParams: Promise<{ new?: string }> }) {
  const { user, ctx } = await requireHostelContext("student");
  const { new: openNew } = await searchParams;
  const supabase = await createClient();
  const student = await getMyStudent(supabase, user.id);
  const leaves = student ? await getMyLeaves(supabase, student.id) : [];
  const pending = leaves.filter((l) => l.status === "pending").length;

  return (
    <MobilePage
      role="student"
      title="Leave"
      subtitle={pending ? `${pending} pending request${pending === 1 ? "" : "s"}` : "Apply and track your leave requests"}
      backHref="/student"
    >
      {!student ? (
        <GlassCard>
          <EmptyState icon={UserX} title="No student record linked" description="Ask your warden to check your registration." />
        </GlassCard>
      ) : (
        <LeaveView leaves={leaves} writable={ctx.writable} openNew={openNew === "1"} />
      )}
    </MobilePage>
  );
}
