import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getMyTasks } from "@/lib/queries/manager";
import { PageHeader } from "@/components/shared/page-header";
import { TaskList } from "@/components/manager/task-list";

export const dynamic = "force-dynamic";

export default async function ManagerTasksPage() {
  const { user, ctx } = await requireHostelContext("manager");
  const supabase = await createClient();
  const tasks = await getMyTasks(supabase, ctx.hostel.id, user.id);
  const open = tasks.filter((t) => t.status !== "done").length;

  return (
    <>
      <PageHeader
        title="My tasks"
        description={open > 0 ? `${open} open ${open === 1 ? "task" : "tasks"} assigned by your owner. Move them from pending to in progress to done.` : "Tasks assigned by your owner. Move them from pending to in progress to done."}
      />
      <TaskList tasks={tasks} writable={ctx.writable} />
    </>
  );
}
