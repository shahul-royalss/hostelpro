import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getActiveStudents, getVisitors } from "@/lib/queries/warden";
import { LeavesVisitorsTabs } from "@/components/warden/lv-tabs";
import { VisitorsView } from "@/components/warden/visitors-view";

export const dynamic = "force-dynamic";

/** WD-6 · Visitors tab — log a visitor, today's list with check-out, 30-day history. */
export default async function WardenVisitorsPage() {
  const { ctx } = await requireHostelContext("warden");
  const supabase = await createClient();
  const since = new Date();
  since.setDate(since.getDate() - 30);
  since.setHours(0, 0, 0, 0);

  const [visitors, students, { count: pendingLeaves }] = await Promise.all([
    getVisitors(supabase, ctx.hostel.id, since.toISOString(), 300),
    getActiveStudents(supabase, ctx.hostel.id),
    supabase.from("leaves").select("id", { count: "exact", head: true }).eq("hostel_id", ctx.hostel.id).eq("status", "pending"),
  ]);

  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const todayMs = startOfToday.getTime();
  // Today's card list = checked in today, plus anyone still inside from earlier
  const today = visitors.filter((v) => new Date(v.check_in_at).getTime() >= todayMs || !v.check_out_at);
  const history = visitors.filter((v) => !today.includes(v));

  return (
    <MobilePage role="warden" title="Leaves & visitors" subtitle={ctx.hostel.name} backHref="/warden">
      <div className="flex flex-col gap-4">
        <LeavesVisitorsTabs active="visitors" counts={{ leaves: pendingLeaves ?? 0, visitors: today.filter((v) => !v.check_out_at).length }} />
        <VisitorsView today={today} history={history} students={students} writable={ctx.writable} />
      </div>
    </MobilePage>
  );
}
