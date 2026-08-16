import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getComplaintById, getComplaintEvents, getComplaintsInbox, type ComplaintFilter } from "@/lib/queries/owner";
import { formatNumber } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { ComplaintsInbox, type SelectedComplaint } from "@/components/owner/complaints-inbox";

export const dynamic = "force-dynamic";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FILTERS: ComplaintFilter[] = ["all", "open", "in_progress", "resolved"];

/** OW-2 — status filter, search and paging are URL params applied server-side; ?id= selects a complaint. */
export default async function OwnerComplaintsPage({ searchParams }: { searchParams: Promise<{ id?: string; status?: string; q?: string; page?: string }> }) {
  const { ctx } = await requireHostelContext("owner");
  const sp = await searchParams;
  const status: ComplaintFilter = FILTERS.includes(sp.status as ComplaintFilter) ? (sp.status as ComplaintFilter) : "all";
  const q = typeof sp.q === "string" ? sp.q.slice(0, 80) : "";
  const page = sp.page && /^\d{1,6}$/.test(sp.page) ? Math.max(1, Number(sp.page)) : 1;
  const id = sp.id && UUID_RE.test(sp.id) ? sp.id : null;
  const supabase = await createClient();

  const inbox = await getComplaintsInbox(supabase, ctx.hostel.id, { status, q, page });
  const { counts } = inbox;
  const open = counts.open + counts.in_progress;

  // Selected: explicit ?id= (fetched directly if it falls outside the current page/filter), else the first listed (desktop default).
  let target = (id && inbox.complaints.find((c) => c.id === id)) || null;
  if (!target && id) target = await getComplaintById(supabase, ctx.hostel.id, id);
  if (!target) target = inbox.complaints[0] ?? null;

  let selected: SelectedComplaint | null = null;
  if (target) {
    const [events, photoUrl] = await Promise.all([getComplaintEvents(supabase, target.id), signedUrl("complaint-photos", target.photo_url)]);
    selected = { complaint: target, events, photoUrl };
  }

  return (
    <>
      <PageHeader title="Complaints inbox" description={`${formatNumber(open)} open · ${formatNumber(counts.all)} total`} />
      <ComplaintsInbox inbox={inbox} params={{ status, q }} selected={selected} writable={ctx.writable} />
    </>
  );
}
