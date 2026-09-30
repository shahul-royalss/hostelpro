import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { ROLE_LIMITS } from "@/lib/roles";
import { getStaff, getTasks, taskManagerFor } from "@/lib/queries/owner";
import { PageHeader } from "@/components/shared/page-header";
import { StaffCard } from "@/components/owner/staff-card";
import { TasksCard } from "@/components/owner/tasks-card";
import { HostelRulesCard } from "@/components/owner/hostel-rules-card";

export const dynamic = "force-dynamic";

/**
 * OW-4: managers and wardens of the current PG, tasks for managers, hostel rules editor.
 *
 * "Of the current PG" means staff WITH ACCESS to it (owner_hostel_staff), so a warden the owner
 * shares between two PGs is listed on both, with a note saying where they are working now.
 */
export default async function OwnerStaffPage() {
  const { ctx } = await requireHostelContext("owner");
  const supabase = await createClient();

  const [staff, tasks] = await Promise.all([getStaff(supabase, ctx.hostel.id), getTasks(supabase, ctx.hostel.id)]);
  const managers = staff.filter((s) => s.role === "manager");
  const wardens = staff.filter((s) => s.role === "warden");
  const taskManager = taskManagerFor(staff, ctx.hostel.id);
  const openTasks = tasks.filter((t) => t.status !== "done").length;
  const pgs = ctx.hostels.map((h) => ({ id: h.id, name: h.name }));
  // Names for the task lines. Tasks can be assigned to any of up to five managers, so "assigned
  // to X" at the top of the card is not enough on its own.
  const staffNames = Object.fromEntries(staff.map((s) => [s.id, s.full_name]));

  return (
    <>
      <PageHeader
        title="Staff & tasks"
        description={`Up to ${ROLE_LIMITS.manager} managers and ${ROLE_LIMITS.warden} wardens can work in ${ctx.hostel.name}. ${openTasks} open task${openTasks === 1 ? "" : "s"} for managers.`}
      />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <StaffCard role="manager" members={managers} writable={ctx.writable} hostelId={ctx.hostel.id} pgs={pgs} />
        <StaffCard role="warden" members={wardens} writable={ctx.writable} hostelId={ctx.hostel.id} pgs={pgs} />
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3 lg:items-start">
        <div className="lg:col-span-2">
          <TasksCard tasks={tasks} manager={taskManager} staffNames={staffNames} writable={ctx.writable} />
        </div>
        <HostelRulesCard rules={ctx.hostel.rules} writable={ctx.writable} />
      </div>
    </>
  );
}
