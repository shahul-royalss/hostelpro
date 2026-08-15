import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getComplaintEvents, getComplaints } from "@/lib/queries/owner";
import { PageHeader } from "@/components/shared/page-header";
import { ComplaintsInbox, type SelectedComplaint } from "@/components/owner/complaints-inbox";

export const dynamic = "force-dynamic";

export default async function OwnerComplaintsPage({ searchParams }: { searchParams: Promise<{ id?: string }> }) {
  const { ctx } = await requireHostelContext("owner");
  const { id } = await searchParams;
  const supabase = await createClient();

  const complaints = await getComplaints(supabase, ctx.hostel.id);
  const open = complaints.filter((c) => c.status !== "resolved").length;

  // Selected: explicit ?id= if it belongs to this hostel, else the newest one (desktop default).
  const target = (id && complaints.find((c) => c.id === id)) || complaints[0] || null;
  let selected: SelectedComplaint | null = null;
  if (target) {
    const [events, photoUrl] = await Promise.all([getComplaintEvents(supabase, target.id), signedUrl("complaint-photos", target.photo_url)]);
    selected = { complaint: target, events, photoUrl };
  }

  return (
    <>
      <PageHeader title="Complaints inbox" description={`${open} open · ${complaints.length} total`} />
      <ComplaintsInbox complaints={complaints} selected={selected} writable={ctx.writable} />
    </>
  );
}
