import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getLeaves, getVisitors, hostelDayStart } from "@/lib/queries/warden";
import { LeavesVisitorsTabs } from "@/components/warden/lv-tabs";
import { LeavesView } from "@/components/warden/leaves-view";

export const dynamic = "force-dynamic";

/** WD-6 · Leaves tab — pending requests with approve/reject + history. */
export default async function WardenLeavesPage() {
  const { ctx } = await requireHostelContext("warden");
  const supabase = await createClient();
  // "Today" is the hostel's civil day (Asia/Kolkata), not the server's local midnight.
  const startOfToday = hostelDayStart();
  // Pending is fetched without a cap so an old request can never be pushed out by newer decided ones.
  const [pendingLeaves, history, todaysVisitors] = await Promise.all([
    getLeaves(supabase, ctx.hostel.id, { status: "pending" }),
    getLeaves(supabase, ctx.hostel.id, { status: "decided", limit: 80 }),
    getVisitors(supabase, ctx.hostel.id, startOfToday.toISOString(), 50),
  ]);
  const leaves = [...pendingLeaves, ...history];
  const pendingCount = pendingLeaves.length;

  return (
    <MobilePage role="warden" title="Leaves & visitors" subtitle={ctx.hostel.name} backHref="/warden">
      <div className="flex flex-col gap-4">
        <LeavesVisitorsTabs active="leaves" counts={{ leaves: pendingCount, visitors: todaysVisitors.filter((v) => !v.check_out_at).length }} />
        <LeavesView leaves={leaves} writable={ctx.writable} />
      </div>
    </MobilePage>
  );
}
