import { Megaphone } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getAnnouncements } from "@/lib/queries/warden";
import { GlassCard } from "@/components/shared/glass-card";
import { EmptyState } from "@/components/shared/empty-state";
import { StatusPill } from "@/components/shared/status-pill";
import { formatDateTime } from "@/lib/utils";

export const dynamic = "force-dynamic";

export default async function WardenAnnouncementsPage() {
  const { ctx } = await requireHostelContext("warden");
  const supabase = await createClient();
  const announcements = await getAnnouncements(supabase, ctx.hostel.id, 50);

  return (
    <MobilePage role="warden" title="Announcements" subtitle={ctx.hostel.name} backHref="/warden">
      {announcements.length === 0 ? (
        <GlassCard>
          <EmptyState icon={Megaphone} title="No announcements yet" description="Updates from the owner will show up here." />
        </GlassCard>
      ) : (
        <ul className="flex flex-col gap-4">
          {announcements.map((a) => (
            <GlassCard key={a.id} as="article">
              <div className="mb-1 flex items-start justify-between gap-3">
                <h2 className="text-card-title font-semibold text-navy">{a.title}</h2>
                <StatusPill status={a.audience} size="sm" />
              </div>
              <p className="whitespace-pre-line text-sm text-charcoal">{a.body}</p>
              <p className="mt-3 text-[11px] text-muted">{formatDateTime(a.created_at)}</p>
            </GlassCard>
          ))}
        </ul>
      )}
    </MobilePage>
  );
}
