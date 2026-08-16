import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getComplaints } from "@/lib/queries/warden";
import { ComplaintsView } from "@/components/warden/complaints-view";

export const dynamic = "force-dynamic";

/** Warden complaints — same data the owner sees; update status / add note via the shared action. */
export default async function WardenComplaintsPage() {
  const { ctx } = await requireHostelContext("warden");
  const supabase = await createClient();
  const complaints = await getComplaints(supabase, ctx.hostel.id, 100);
  const photoUrls = await Promise.all(complaints.map((c) => (c.photo_url ? signedUrl("complaint-photos", c.photo_url, ctx.hostel.id) : Promise.resolve(null))));
  const rows = complaints.map((c, i) => ({ ...c, photoUrl: photoUrls[i] }));
  const open = rows.filter((c) => c.status !== "resolved").length;

  return (
    <MobilePage role="warden" title="Complaints" subtitle={`${open} open · ${ctx.hostel.name}`} backHref="/warden">
      <ComplaintsView complaints={rows} writable={ctx.writable} />
    </MobilePage>
  );
}
