import Link from "next/link";
import { IndianRupee, ListChecks, Megaphone, PieChart, Plus, Receipt, TrendingUp } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { firstName, formatDateTime, formatINR, formatINRCompact, formatNumber, formatPeriodMonth, greeting, sumBy, toISODate, toPeriodMonth } from "@/lib/utils";
import { getAnnouncementsForManager, getExpenses, getExpensesByCategory, getManagerStats, getMyTasks, getRevenues } from "@/lib/queries/manager";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatCard } from "@/components/shared/stat-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { Donut, DonutLegend } from "@/components/shared/charts";
import { Button } from "@/components/ui/button";
import { DashboardTasks } from "@/components/manager/dashboard-tasks";

export const dynamic = "force-dynamic";

export default async function ManagerDashboardPage() {
  const { user, ctx } = await requireHostelContext("manager");
  const supabase = await createClient();
  const hostelId = ctx.hostel.id;
  const period = toPeriodMonth();
  const today = toISODate();

  const [stats, categories, monthExpenses, monthRevenues, openTasks, announcements] = await Promise.all([
    getManagerStats(supabase, hostelId, period),
    getExpensesByCategory(supabase, hostelId, period),
    getExpenses(supabase, hostelId, period),
    getRevenues(supabase, hostelId, period),
    getMyTasks(supabase, hostelId, user.id, { openOnly: true }),
    getAnnouncementsForManager(supabase, hostelId, 5),
  ]);

  // "Today" is computed here against the app's date (same `toISODate()` the entry forms default to),
  // not the RPC's Postgres `current_date` (UTC), so an entry saved after midnight IST shows up immediately.
  const expensesToday = sumBy(monthExpenses.filter((r) => r.date === today), (r) => r.amount);
  const revenueToday = sumBy(monthRevenues.filter((r) => r.date === today), (r) => r.amount);
  const revenueMonth = Number(stats?.revenue_month ?? sumBy(monthRevenues, (r) => r.amount));
  const expensesMonth = Number(stats?.expenses_month ?? sumBy(monthExpenses, (r) => r.amount));
  const profit = revenueMonth - expensesMonth;
  // Per-manager count (the RPC's pending_tasks is hostel-wide and can include a previous manager's tasks).
  const pendingTasks = openTasks.length;
  const monthLabel = formatPeriodMonth(period);

  return (
    <>
      <div className="mb-6 flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-title-sm md:text-title text-navy">
            {greeting()}, {firstName(user.full_name)}
          </h1>
          <p className="mt-1 text-sm text-muted">Finance and operations at {ctx.hostel.name} — {monthLabel}.</p>
        </div>
      </div>

      {/* Stat row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 lg:gap-6">
        <StatCard label="Today's expenses" value={formatINRCompact(expensesToday)} caption={formatINR(expensesToday)} tone="red" icon={Receipt} />
        <StatCard label="Today's revenue" value={formatINRCompact(revenueToday)} caption={formatINR(revenueToday)} tone="teal" icon={IndianRupee} />
        <StatCard
          label="This-month profit"
          value={formatINRCompact(profit)}
          caption={`${formatINRCompact(revenueMonth)} in · ${formatINRCompact(expensesMonth)} out`}
          tone={profit < 0 ? "red" : "navy"}
          icon={TrendingUp}
        />
        <StatCard label="Pending tasks" value={formatNumber(pendingTasks)} caption="From your owner" tone="sand" icon={ListChecks} />
      </div>

      {/* Donut + tasks */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-5">
        <GlassCard className="lg:col-span-3">
          <GlassCardHeader title="This month — expenses by category" description={`Where the money went in ${monthLabel}`} />
          {categories.length === 0 ? (
            <EmptyState
              icon={PieChart}
              title="No expenses this month"
              description="Log today's spend and the breakdown will appear here."
              action={
                ctx.writable ? (
                  <Button asChild size="sm">
                    <Link href="/manager/expenses">
                      <Plus /> Add expense
                    </Link>
                  </Button>
                ) : undefined
              }
            />
          ) : (
            <div className="grid grid-cols-1 items-center gap-6 md:grid-cols-2">
              <Donut data={categories} currency centerLabel="Total" height={250} />
              <DonutLegend data={categories} currency />
            </div>
          )}
        </GlassCard>

        <div className="lg:col-span-2">
          <DashboardTasks tasks={openTasks.slice(0, 6)} writable={ctx.writable} total={openTasks.length} />
        </div>
      </div>

      {/* Quick-add strip */}
      <GlassCard className="mt-6 flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between md:py-4">
        <div>
          <div className="text-sm font-semibold text-navy">Quick add</div>
          <p className="text-[13px] text-muted">{ctx.writable ? "Log today's cash flow in a couple of clicks." : "Subscription expired — entries are read-only until it is renewed."}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button asChild className={!ctx.writable ? "pointer-events-none opacity-50" : undefined}>
            <Link href="/manager/expenses" aria-disabled={!ctx.writable}>
              <Plus /> Add expense
            </Link>
          </Button>
          <Button asChild className={!ctx.writable ? "pointer-events-none opacity-50" : undefined}>
            <Link href="/manager/revenue" aria-disabled={!ctx.writable}>
              <Plus /> Add revenue
            </Link>
          </Button>
        </div>
      </GlassCard>

      {/* Announcements */}
      <GlassCard className="mt-6">
        <GlassCardHeader title="Announcements" description="Updates from your owner" />
        {announcements.length === 0 ? (
          <EmptyState compact icon={Megaphone} title="No announcements yet" description="Updates your owner sends to managers or everyone will show up here." />
        ) : (
          <ul className="divide-y divide-line/70">
            {announcements.map((a) => (
              <li key={a.id} className="flex gap-3 py-3 first:pt-0 last:pb-0">
                <span className="mt-2 h-2 w-2 shrink-0 rounded-full bg-teal" aria-hidden />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                    <p className="text-sm font-semibold text-navy">{a.title}</p>
                    <StatusPill status={a.audience} size="sm" />
                  </div>
                  <p className="mt-0.5 line-clamp-2 whitespace-pre-line text-sm text-charcoal/80">{a.body}</p>
                  <p className="mt-1 text-[11px] text-muted tabular">{formatDateTime(a.created_at)}</p>
                </div>
              </li>
            ))}
          </ul>
        )}
      </GlassCard>
    </>
  );
}
