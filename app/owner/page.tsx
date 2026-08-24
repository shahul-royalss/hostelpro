import { format } from "date-fns";
import { BedDouble, IndianRupee, Megaphone, MessageSquareWarning, Receipt, Users, Wallet } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import type { HostelStats } from "@/lib/types";
import { firstName, formatDate, formatINR, formatINRCompact, formatNumber, greeting, percent, toPeriodMonth } from "@/lib/utils";
import { getHostelStats, getLast30DaysFinance, getLatestAnnouncements, getRecentComplaints } from "@/lib/queries/owner";
import { HeroStat, heroAmount } from "@/components/dashboard/hero-stat";
import { Delta, Verdict } from "@/components/dashboard/delta";
import { Meter } from "@/components/dashboard/meter";
import { TrendBars } from "@/components/dashboard/trend-bars";
import { InsetEmpty, InsetList, InsetRow, ListSectionHeader, SeeAll } from "@/components/dashboard/inset-list";
import { Metric, MetricGrid } from "@/components/dashboard/metric-grid";
import { PrimaryAction } from "@/components/dashboard/primary-action";
import { longMonth, monthDeadline, monthDeadlineShort, monthProgress, previousPeriod, shortMonth, plural } from "@/components/dashboard/period";
import { SubscriptionCard } from "@/components/owner/subscription-card";
import { ComplaintCategoryIcon } from "@/components/owner/complaint-icon";
import { StatusPill } from "@/components/shared/status-pill";

export const dynamic = "force-dynamic";

/** Days of daily finance to chart. 30 bars on a 360px phone are 4px wide; 14 are readable. */
const TREND_DAYS = 14;

/**
 * OW-1 · Owner dashboard.
 *
 * Was five identical stat cards — a wall of same-sized numbers, every caption a
 * static phrase ("Currently registered", "Awaiting resolution") that judged
 * nothing — plus a 30-point Recharts area chart and no primary action at all.
 *
 * Now: occupancy leads, priced in rupees so an empty bed reads as lost income;
 * collection is the runner-up with its own meter and a real month-on-month
 * delta; and there is one obvious thing to do.
 */
export default async function OwnerDashboardPage() {
  const { user, ctx } = await requireHostelContext("owner");
  const supabase = await createClient();
  const hostelId = ctx.hostel.id;
  const period = toPeriodMonth();
  const prev = previousPeriod(period);

  /**
   * `getHostelStats` (owner) always asks for the current period. The same RPC
   * takes a period argument, and last month's row is the baseline that turns
   * every figure on this page from a number into a comparison.
   */
  const lastMonthStats = async (): Promise<HostelStats | null> => {
    const { data } = await supabase.rpc("rpc_hostel_stats", { p_hostel_id: hostelId, p_period_month: prev }).maybeSingle();
    return (data as HostelStats | null) ?? null;
  };

  // Stored subscription statuses / hostel read-only flags are refreshed alongside the reads (DECISIONS #14) —
  // it never blocks the page (read-only enforcement is computed live via app.subscription_state) and errors are non-fatal.
  const [stats, lastMonth, finance, announcements, complaints] = await Promise.all([
    getHostelStats(supabase, hostelId),
    lastMonthStats(),
    getLast30DaysFinance(supabase, hostelId),
    getLatestAnnouncements(supabase, hostelId, 3),
    getRecentComplaints(supabase, hostelId, 3),
    supabase.rpc("refresh_subscription_statuses").then(() => undefined, () => undefined),
  ]);

  const totalBeds = stats?.total_beds ?? 0;
  const occupied = stats?.occupied_beds ?? 0;
  const free = Math.max(0, totalBeds - occupied);
  const occupancy = percent(occupied, totalBeds);

  const collected = Number(stats?.fees_collected ?? 0);
  const pendingFees = Number(stats?.fees_pending ?? 0);
  const billed = collected + pendingFees;
  const collectionRate = percent(collected, billed);
  const unpaidStudents = stats?.students_unpaid ?? 0;
  const billedStudents = (stats?.students_paid ?? 0) + unpaidStudents;

  /**
   * What the empty beds are worth, at the fee this hostel actually charges —
   * the average of what it billed this month, not a guess. This is the line
   * that makes "33%" mean something to an owner.
   */
  const avgFee = billedStudents > 0 ? Math.round(billed / billedStudents) : 0;
  const idleValue = free * avgFee;

  const revenueMonth = Number(stats?.revenue_month ?? 0);
  const expensesMonth = Number(stats?.expenses_month ?? 0);
  const progress = monthProgress(period);
  const monthName = longMonth(period);
  const money = heroAmount(collected);

  const trend = finance.slice(-TREND_DAYS).map((d) => ({
    label: format(new Date(`${d.day}T00:00:00`), "d MMM"),
    a: d.revenue,
    b: d.expense,
  }));
  const trendHasData = trend.some((d) => d.a > 0 || d.b > 0);
  const trendRevenue = trend.reduce((s, d) => s + d.a, 0);
  const trendExpense = trend.reduce((s, d) => s + (d.b ?? 0), 0);

  return (
    <>
      {/* The hostel name is in the top bar. This row is the person, the month and
          the one thing that can stop the account working. */}
      <header className="mb-6 flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div className="min-w-0">
          <h1 className="text-title-sm md:text-title text-navy">
            {greeting()}, {firstName(user.full_name)}
          </h1>
          <p className="mt-1 text-subhead text-label-secondary">
            {monthName} · {monthDeadlineShort(progress)}
          </p>
        </div>
        <SubscriptionCard ctx={ctx} />
      </header>

      <div className="flex flex-col gap-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <HeroStat
            eyebrow="Occupancy"
            value={`${occupancy}%`}
            icon={BedDouble}
            tone={occupancy >= 90 ? "teal" : occupancy >= 65 ? "navy" : "sand"}
            verdict={
              free === 0 ? (
                <Verdict verdict="good">Every bed is filled</Verdict>
              ) : (
                <Verdict verdict={occupancy >= 90 ? "good" : occupancy >= 65 ? "flat" : "bad"}>
                  {formatNumber(free)} empty {plural(free, "bed")}
                  {idleValue > 0 ? ` · about ${formatINRCompact(idleValue)} a month unearned` : ""}
                </Verdict>
              )
            }
            meter={<Meter percent={occupancy} tone={occupancy >= 90 ? "teal" : occupancy >= 65 ? "navy" : "sand"} label={`${occupancy}% of beds occupied`} />}
            caption={
              totalBeds > 0
                ? `${formatNumber(occupied)} of ${formatNumber(totalBeds)} beds filled${avgFee > 0 ? ` · average fee ${formatINR(avgFee)}` : ""}`
                : "No beds have been set up for this hostel yet"
            }
            footer={
              free > 0 ? (
                <InsetRow href="/owner/students" title={`Fill ${formatNumber(free)} more ${plural(free, "bed")}`} subtitle="See who is in, who has left, and where the gaps are" tone="navy" />
              ) : undefined
            }
          />

          <HeroStat
            size="md"
            eyebrow={`Collected in ${monthName}`}
            value={money.display}
            icon={IndianRupee}
            tone="navy"
            verdict={
              <Delta
                current={collected}
                previous={lastMonth?.fees_collected}
                baselineLabel={shortMonth(prev)}
                format={formatINRCompact}
                emptyLabel={`Nothing was collected in ${shortMonth(prev)} to compare with`}
              />
            }
            meter={<Meter percent={collectionRate} tone={collectionRate >= 90 ? "teal" : collectionRate >= 60 ? "navy" : "sand"} label={`${collectionRate}% of billed fees collected`} />}
            caption={
              billed > 0
                ? `${money.compacted ? `${money.exact} · ` : ""}${collectionRate}% of ${formatINR(billed)} billed to ${formatNumber(billedStudents)} ${plural(billedStudents, "student")}`
                : `Nothing billed for ${monthName} yet`
            }
            footer={
              unpaidStudents > 0 ? (
                <InsetRow
                  href="/owner/finance"
                  title={`${formatNumber(unpaidStudents)} ${plural(unpaidStudents, "student")} still to pay`}
                  subtitle={monthDeadline(progress)}
                  value={formatINR(pendingFees)}
                  tone="red"
                />
              ) : billed > 0 ? (
                <InsetRow href="/owner/finance" title={`Everyone has paid for ${monthName}`} subtitle="Open the ledger for the full breakdown" tone="teal" />
              ) : undefined
            }
          />
        </div>

        <PrimaryAction
          href="/owner/updates"
          label="Send an update"
          icon={Megaphone}
          hint="Reaches every student, warden and manager at this hostel"
          className="lg:max-w-md"
        />

        <MetricGrid className="lg:grid-cols-4">
          <Metric
            label="Students"
            value={formatNumber(stats?.active_students ?? 0)}
            caption={totalBeds > 0 ? `in ${formatNumber(totalBeds)} beds` : "no beds set up"}
            icon={Users}
            href="/owner/students"
          />
          <Metric
            label="Owed to you"
            value={formatINRCompact(pendingFees)}
            caption={unpaidStudents > 0 ? `${formatNumber(unpaidStudents)} ${plural(unpaidStudents, "student")} behind` : "nothing outstanding"}
            icon={Wallet}
            tone={pendingFees > 0 ? "red" : "sage"}
            href="/owner/finance"
          />
          <Metric
            label="Complaints"
            value={formatNumber(stats?.open_complaints ?? 0)}
            caption={(stats?.open_complaints ?? 0) === 0 ? "nothing open — good" : "goal: none open"}
            icon={MessageSquareWarning}
            tone={(stats?.open_complaints ?? 0) > 0 ? "red" : "sage"}
            href="/owner/complaints"
          />
          <Metric
            label={`Spent in ${shortMonth(period)}`}
            value={formatINRCompact(expensesMonth)}
            caption={lastMonth ? `vs ${formatINRCompact(lastMonth.expenses_month)} in ${shortMonth(prev)}` : "first month of records"}
            icon={Receipt}
            tone="navy"
            href="/owner/finance"
          />
        </MetricGrid>

        <section className="material-regular rounded-card squircle p-5 md:p-6">
          <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
            <div className="min-w-0">
              <h2 className="text-card-title font-semibold text-navy">Money in and out</h2>
              <p className="mt-0.5 text-footnote text-label-secondary">The last {TREND_DAYS} days, day by day</p>
            </div>
            <SeeAll href="/owner/finance">Full ledger</SeeAll>
          </div>
          {trendHasData ? (
            <>
              <TrendBars
                points={trend}
                aLabel="Money in"
                bLabel="Money out"
                summary={`Revenue and expenses for the last ${TREND_DAYS} days: ${formatINR(trendRevenue)} in, ${formatINR(trendExpense)} out.`}
              />
              <p className="mt-4 border-t border-separator pt-3 text-footnote text-label-secondary">
                <span className="font-semibold tabular text-ink-teal">{formatINR(trendRevenue)}</span> in ·{" "}
                <span className="font-semibold tabular text-ink-red">{formatINR(trendExpense)}</span> out over {TREND_DAYS} days ·{" "}
                <span className={`font-semibold tabular ${trendRevenue - trendExpense < 0 ? "text-ink-red" : "text-ink-teal"}`}>
                  {formatINR(trendRevenue - trendExpense)}
                </span>{" "}
                net. {monthName} to date: {formatINR(revenueMonth)} in, {formatINR(expensesMonth)} out.
              </p>
            </>
          ) : (
            <InsetEmpty
              icon={Wallet}
              title="No entries in the last 30 days"
              hint="Your manager records revenue and expenses; as soon as one is logged this fills in day by day."
            />
          )}
        </section>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <section>
            <ListSectionHeader title="Complaints needing attention" action={<SeeAll href="/owner/complaints" />} />
            <InsetList aria-label="Recent complaints">
              {complaints.length === 0 ? (
                <InsetEmpty icon={MessageSquareWarning} title="Nothing raised yet" hint="When a student reports a problem it lands here with the room number, so you can see it before they call." />
              ) : (
                complaints.map((c) => (
                  <InsetRow
                    key={c.id}
                    href={`/owner/complaints?id=${c.id}`}
                    leading={<ComplaintCategoryIcon category={c.category} size="sm" />}
                    title={c.title}
                    subtitle={`${c.student?.room?.room_number ? `Room ${c.student.room.room_number} · ` : ""}${c.student?.full_name ?? "Student"}`}
                    trailing={<StatusPill status={c.status} size="sm" />}
                  />
                ))
              )}
            </InsetList>
          </section>

          <section>
            <ListSectionHeader title="Your latest updates" action={<SeeAll href="/owner/updates" />} />
            <InsetList aria-label="Latest announcements">
              {announcements.length === 0 ? (
                <InsetEmpty
                  icon={Megaphone}
                  title="You haven't sent an update yet"
                  hint="One message reaches every student, warden and manager — fee reminders, water cuts, mess changes."
                />
              ) : (
                announcements.map((a) => (
                  <InsetRow
                    key={a.id}
                    href="/owner/updates"
                    icon={Megaphone}
                    title={a.title}
                    subtitle={a.body}
                    valueCaption={formatDate(a.created_at, "d MMM")}
                    trailing={<StatusPill status={a.audience} size="sm" />}
                  />
                ))
              )}
            </InsetList>
          </section>
        </div>
      </div>
    </>
  );
}
