import Link from "next/link";
import { format, isSameMonth, parse } from "date-fns";
import { ArrowUpRight, IndianRupee, PieChart, Receipt, TrendingUp, Wallet } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getMonthFinance } from "@/lib/queries/owner";
import { EXPENSE_CATEGORIES, REVENUE_SOURCES } from "@/lib/types";
import { formatINR, formatINRCompact, formatPeriodMonth, percent, titleCase, toPeriodMonth } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatCard } from "@/components/shared/stat-card";
import { EmptyState } from "@/components/shared/empty-state";
import { Chip } from "@/components/shared/status-pill";
import { CATEGORY_COLORS, CHART, Donut, DonutLegend, LineTrend } from "@/components/shared/charts";
import { Button } from "@/components/ui/button";
import { FinanceMonthNav } from "@/components/owner/finance-month-nav";
import { FinanceEntriesTable } from "@/components/owner/finance-entries-table";

export const dynamic = "force-dynamic";

const PERIOD_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

/** OW-6 — Finance overview for a month: totals, expenses by category, daily profit trend, latest entries. */
export default async function OwnerFinancePage({ searchParams }: { searchParams: Promise<{ month?: string }> }) {
  const { ctx } = await requireHostelContext("owner");
  const { month } = await searchParams;
  const period = month && PERIOD_RE.test(month) ? month : toPeriodMonth();
  const supabase = await createClient();

  const fin = await getMonthFinance(supabase, ctx.hostel.id, period);
  const profit = fin.totalRevenue - fin.totalExpense;
  const margin = fin.totalRevenue > 0 ? Math.round((profit / fin.totalRevenue) * 100) : 0;

  // Expenses by category (fixed order, hide zeros)
  const byCategory = EXPENSE_CATEGORIES.map((c, i) => ({
    name: titleCase(c),
    value: fin.expenses.filter((e) => e.category === c).reduce((s, e) => s + e.amount, 0),
    color: CATEGORY_COLORS[i % CATEGORY_COLORS.length],
  })).filter((d) => d.value > 0);

  // Revenue by source (small breakdown chips)
  const bySource = REVENUE_SOURCES.map((s) => ({
    name: titleCase(s),
    value: fin.revenues.filter((r) => r.source === s).reduce((sum, r) => sum + r.amount, 0),
  })).filter((d) => d.value > 0);

  // Daily profit — for the current month stop at today so the line doesn't flatline into the future
  const monthDate = parse(`${period}-01`, "yyyy-MM-dd", new Date());
  const today = new Date();
  const todayIso = format(today, "yyyy-MM-dd");
  const dailyRows = isSameMonth(monthDate, today) ? fin.daily.filter((d) => d.day <= todayIso) : fin.daily;
  let running = 0;
  const trend = dailyRows.map((d) => {
    const p = d.revenue - d.expense;
    running += p;
    return { day: format(new Date(`${d.day}T00:00:00`), "d MMM"), profit: p, cumulative: running };
  });
  const hasActivity = fin.expenses.length > 0 || fin.revenues.length > 0;
  const activeDays = dailyRows.filter((d) => d.revenue > 0 || d.expense > 0).length;

  return (
    <>
      <PageHeader
        title="Finance overview"
        description={`Revenue, expenses and profit for ${formatPeriodMonth(period)} — fed by your manager's entries.`}
        actions={<FinanceMonthNav value={period} />}
      />

      {/* Stat row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3 lg:gap-6">
        <StatCard label="Total revenue" value={formatINRCompact(fin.totalRevenue)} tone="teal" icon={IndianRupee} caption={`${fin.revenues.length} entr${fin.revenues.length === 1 ? "y" : "ies"} · ${formatINR(fin.totalRevenue)}`} />
        <StatCard label="Total expenses" value={formatINRCompact(fin.totalExpense)} tone="red" icon={Receipt} caption={`${fin.expenses.length} entr${fin.expenses.length === 1 ? "y" : "ies"} · ${formatINR(fin.totalExpense)}`} />
        <StatCard
          label="Profit"
          value={`${profit < 0 ? "−" : ""}${formatINRCompact(Math.abs(profit))}`}
          tone={profit < 0 ? "red" : "navy"}
          icon={TrendingUp}
          caption={fin.totalRevenue > 0 ? `${margin}% margin · ${formatINR(profit)}` : hasActivity ? formatINR(profit) : "No entries yet"}
        />
      </div>

      {/* Charts */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-5">
        <GlassCard className="lg:col-span-2">
          <GlassCardHeader title="Expenses by category" description={formatPeriodMonth(period)} action={<Chip>{percent(fin.totalExpense, fin.totalRevenue || fin.totalExpense || 1)}% of revenue</Chip>} />
          {byCategory.length === 0 ? (
            <EmptyState compact icon={PieChart} title="No expenses recorded" description="Expense entries from your manager will break down here by category." />
          ) : (
            <>
              <Donut data={byCategory} currency centerLabel="Total" centerValue={formatINRCompact(fin.totalExpense)} height={220} />
              <div className="mt-4">
                <DonutLegend data={byCategory} currency />
              </div>
            </>
          )}
          {bySource.length > 0 ? (
            <div className="mt-5 border-t border-line/70 pt-4">
              <div className="label-caps mb-2">Revenue by source</div>
              <div className="flex flex-wrap gap-2">
                {bySource.map((s) => (
                  <Chip key={s.name} tone="teal">
                    {s.name} · {formatINRCompact(s.value)}
                  </Chip>
                ))}
              </div>
            </div>
          ) : null}
        </GlassCard>

        <GlassCard className="lg:col-span-3">
          <GlassCardHeader title="Daily profit trend" description={`Revenue − expenses per day · ${activeDays} active day${activeDays === 1 ? "" : "s"}`} action={<Chip>{formatPeriodMonth(period)}</Chip>} />
          {!hasActivity ? (
            <EmptyState icon={Wallet} title="Nothing to chart yet" description="Daily profit appears once revenue or expenses are recorded this month." />
          ) : (
            <LineTrend
              data={trend}
              xKey="day"
              height={300}
              currency
              series={[
                { key: "profit", label: "Daily profit", color: CHART.navy },
                { key: "cumulative", label: "Month to date", color: CHART.teal },
              ]}
            />
          )}
        </GlassCard>
      </div>

      {/* Latest entries */}
      <GlassCard className="mt-6" padded={false}>
        <div className="p-5 pb-3 md:p-6 md:pb-3">
          <GlassCardHeader
            className="mb-0"
            title="Latest entries"
            description={`Newest ${Math.min(10, fin.entries.length)} of ${fin.entries.length} in ${formatPeriodMonth(period)} · who recorded each one`}
            action={
              <Button asChild variant="link" size="sm" className="h-auto px-0">
                <Link href="/owner/students">
                  Fee status by student <ArrowUpRight />
                </Link>
              </Button>
            }
          />
        </div>
        <FinanceEntriesTable entries={fin.entries.slice(0, 10)} />
      </GlassCard>
    </>
  );
}
