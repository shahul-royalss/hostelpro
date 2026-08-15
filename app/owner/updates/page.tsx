import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getAnnouncements, getAudienceCounts, reachFor } from "@/lib/queries/owner";
import { PageHeader } from "@/components/shared/page-header";
import { UpdateComposer } from "@/components/owner/update-composer";
import { UpdatesHistory, type SentUpdate } from "@/components/owner/updates-history";

export const dynamic = "force-dynamic";

/** OW-3 — Broadcast update composer + sent history. */
export default async function OwnerUpdatesPage() {
  const { ctx } = await requireHostelContext("owner");
  const supabase = await createClient();

  const [announcements, counts] = await Promise.all([getAnnouncements(supabase, ctx.hostel.id), getAudienceCounts(supabase, ctx.hostel.id)]);

  const updates: SentUpdate[] = announcements.map((a) => ({ ...a, reach: reachFor(a.audience, counts) }));
  const reach = {
    all: reachFor("all", counts),
    manager: reachFor("manager", counts),
    warden: reachFor("warden", counts),
    students: reachFor("students", counts),
  };

  return (
    <>
      <PageHeader title="Updates" description={`Broadcast announcements to the people at ${ctx.hostel.name}.`} />
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-5 lg:items-start">
        <div className="lg:col-span-3">
          <UpdateComposer writable={ctx.writable} reach={reach} />
        </div>
        <div className="lg:col-span-2">
          <UpdatesHistory updates={updates} writable={ctx.writable} />
        </div>
      </div>
    </>
  );
}
