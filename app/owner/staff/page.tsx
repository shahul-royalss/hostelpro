import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getStaff, getTasks } from "@/lib/queries/owner";
import { PageHeader } from "@/components/shared/page-header";
import { StaffCard } from "@/components/owner/staff-card";
import { TasksCard } from "@/components/owner/tasks-card";
import { HostelRulesCard } from "@/components/owner/hostel-rules-card";

export const dynamic = "force-dynamic";

/** OW-4 — Manager & Warden cards, tasks for the manager, hostel rules editor. */
export default async function OwnerStaffPage() {
  const { ctx } = await requireHostelContext("owner");
  const supabase = await createClient();

  const [staff, tasks] = await Promise.all([getStaff(supabase, ctx.hostel.id), getTasks(supabase, ctx.hostel.id)]);
  const managers = staff.filter((s) => s.role === "manager");
  const wardens = staff.filter((s) => s.role === "warden");
  const activeManager = managers.find((m) => m.status === "active") ?? null;
  const openTasks = tasks.filter((t) => t.status !== "done").length;

  return (
    <>
      <PageHeader title="Staff & tasks" description={`One manager and one warden run ${ctx.hostel.name}. ${openTasks} open task${openTasks === 1 ? "" : "s"} for the manager.`} />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <StaffCard role="manager" members={managers} writable={ctx.writable} />
        <StaffCard role="warden" members={wardens} writable={ctx.writable} />
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3 lg:items-start">
        <div className="lg:col-span-2">
          <TasksCard tasks={tasks} manager={activeManager} writable={ctx.writable} />
        </div>
        <HostelRulesCard rules={ctx.hostel.rules} writable={ctx.writable} />
      </div>
    </>
  );
}
