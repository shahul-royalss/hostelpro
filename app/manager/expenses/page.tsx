import { Lock } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getExpenses, resolvePeriod } from "@/lib/queries/manager";
import { PageHeader } from "@/components/shared/page-header";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { ExpenseForm } from "@/components/manager/expense-form";
import { ExpenseTable } from "@/components/manager/expense-table";

export const dynamic = "force-dynamic";

export default async function ManagerExpensesPage({ searchParams }: { searchParams: Promise<{ month?: string | string[] }> }) {
  const { ctx } = await requireHostelContext("manager");
  const { month } = await searchParams;
  const period = resolvePeriod(month);
  const supabase = await createClient();
  const rows = await getExpenses(supabase, ctx.hostel.id, period);

  return (
    <>
      <PageHeader title="Daily expenses" description={`Record and track outflow for ${ctx.hostel.name}.`} />

      <GlassCard>
        <GlassCardHeader
          title="Add expense"
          description="Date defaults to today. Attach the receipt photo or PDF if you have one."
          action={
            !ctx.writable ? (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-sand-soft px-2.5 py-1 text-xs font-semibold text-sand-deep">
                <Lock className="h-3.5 w-3.5" /> Read-only
              </span>
            ) : undefined
          }
        />
        <ExpenseForm mode="create" disabled={!ctx.writable} />
      </GlassCard>

      <div className="mt-6">
        <ExpenseTable rows={rows} month={period} writable={ctx.writable} />
      </div>
    </>
  );
}
