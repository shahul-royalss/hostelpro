import { Lock } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getRevenues, resolvePeriod } from "@/lib/queries/manager";
import { PageHeader } from "@/components/shared/page-header";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { RevenueForm } from "@/components/manager/revenue-form";
import { RevenueTable } from "@/components/manager/revenue-table";

export const dynamic = "force-dynamic";

export default async function ManagerRevenuePage({ searchParams }: { searchParams: Promise<{ month?: string | string[] }> }) {
  const { ctx } = await requireHostelContext("manager");
  const { month } = await searchParams;
  const period = resolvePeriod(month);
  const supabase = await createClient();
  const rows = await getRevenues(supabase, ctx.hostel.id, period);

  return (
    <>
      <PageHeader title="Daily revenue" description={`Record fees, mess and other collections for ${ctx.hostel.name}.`} />

      <GlassCard>
        <GlassCardHeader
          title="Add revenue"
          description="Date defaults to today. Pick the source and enter the amount collected."
          action={
            !ctx.writable ? (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-sand-soft px-2.5 py-1 text-xs font-semibold text-sand-deep">
                <Lock className="h-3.5 w-3.5" /> Read-only
              </span>
            ) : undefined
          }
        />
        <RevenueForm mode="create" disabled={!ctx.writable} />
      </GlassCard>

      <div className="mt-6">
        <RevenueTable rows={rows} month={period} writable={ctx.writable} />
      </div>
    </>
  );
}
