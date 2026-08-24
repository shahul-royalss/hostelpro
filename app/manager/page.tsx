import { IndianRupee, ListChecks, Megaphone, Plus, Receipt, Wallet } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { firstName, formatDate, formatINR, formatINRCompact, formatNumber, greeting, sumBy, toISODate, toPeriodMonth } from "@/lib/utils";
import { getAnnouncementsForManager, getExpenses, getExpensesByCategory, getManagerStats, getMyTasks, getRevenues } from "@/lib/queries/manager";
import { HeroStat, heroAmount } from "@/components/dashboard/hero-stat";
import { Delta } from "@/components/dashboard/delta";
import { SegmentMeter, type MeterTone } from "@/components/dashboard/meter";
import { InsetEmpty, InsetList, InsetRow, ListSectionHeader, SeeAll } from "@/components/dashboard/inset-list";
import { Metric, MetricGrid } from "@/components/dashboard/metric-grid";
import { ActionRow, PrimaryAction, SecondaryAction } from "@/components/dashboard/primary-action";
import { longMonth, monthDeadlineShort, monthProgress, previousPeriod, shortMonth, plural } from "@/components/dashboard/period";
import { DashboardTasks } from "@/components/manager/dashboard-tasks";

export const dynamic = "force-dynamic";

/** Category bars, in the order the list renders them. Graphical marks, so `mark-*` (≥3:1). */
const CATEGORY_TONES: MeterTone[] = ["navy", "teal", "sand", "sage", "red"];
const TONE_BAR: Record<MeterTone, string> = {
  navy: "bg-navy",
  teal: "bg-teal",
  sand: "bg-mark-sand",
  sage: "bg-mark-sage",
  red: "bg-red",
};

/**
 * MG-1 · Manager dashboard.
 *
 * The manager's number is this month's spend, so it is the hero. It used to be
 * third in a row of four identical cards, behind "Today's expenses ₹0" and
 * "Today's revenue ₹0" — the two figures that are zero for most of every day
 * were the biggest things on the page, and each repeated its own value in its
 * caption (`₹0` above `₹0`).
 *
 * The donut is gone. A pie with a six-row legend is unreadable at 360px and cost
 * the whole Recharts bundle in First Load JS; a stacked bar plus a grouped inset
 * list says the same thing, ranks it, and renders on the server.
 */
export default async function ManagerDashboardPage() {
  const { user, ctx } = await requireHostelContext("manager");
  const supabase = await createClient();
  const hostelId = ctx.hostel.id;
  const period = toPeriodMonth();
  const prev = previousPeriod(period);
  const today = toISODate();

  const [stats, lastMonth, categories, lastCategories, monthExpenses, monthRevenues, openTasks, announcements] = await Promise.all([
    getManagerStats(supabase, hostelId, period),
    // rpc_hostel_stats for the previous period — the baseline for every delta below.
    getManagerStats(supabase, hostelId, prev),
    getExpensesByCategory(supabase, hostelId, period),
    getExpensesByCategory(supabase, hostelId, prev),
    getExpenses(supabase, hostelId, period),
    getRevenues(supabase, hostelId, period),
    getMyTasks(supabase, hostelId, user.id, { openOnly: true }),
    getAnnouncementsForManager(supabase, hostelId, 3),
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

  const progress = monthProgress(period);
  const monthName = longMonth(period);

  /**
   * Comparing a part-finished month against a finished one is not a comparison —
   * it always reads as "spending is down" until the last day. So the delta is on
   * the run-rate projection, and the caption states the projection explicitly.
   */
  const perDay = progress.elapsed > 0 ? expensesMonth / progress.elapsed : 0;
  const projected = progress.past ? expensesMonth : Math.round(perDay * progress.total);
  const spend = heroAmount(expensesMonth);

  const categoryTotal = categories.reduce((s, c) => s + c.value, 0);
  const lastByCategory = new Map(lastCategories.map((c) => [c.category, c.value]));
  const ranked = [...categories].sort((a, b) => b.value - a.value);

  return (
    <>
      {/* The hostel name lives in the top bar and nowhere else on this page. */}
      <header className="mb-6">
        <h1 className="text-title-sm md:text-title text-navy">
          {greeting()}, {firstName(user.full_name)}
        </h1>
        <p className="mt-1 text-subhead text-label-secondary">
          {monthName} so far · {monthDeadlineShort(progress)}
        </p>
      </header>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="flex flex-col gap-6 lg:col-span-2">
          <HeroStat
            eyebrow={`Spent in ${monthName}`}
            value={spend.display}
            icon={Receipt}
            tone="navy"
            verdict={
              <Delta
                current={projected}
                previous={lastMonth?.expenses_month}
                baselineLabel={shortMonth(prev)}
                lowerIsBetter
                format={formatINRCompact}
                emptyLabel={`Nothing was recorded in ${shortMonth(prev)} to compare with`}
              />
            }
            caption={
              progress.past
                ? `${spend.compacted ? `${spend.exact} · ` : ""}Final total for ${monthName}`
                : `${spend.compacted ? `${spend.exact} · ` : ""}${formatINR(Math.round(perDay))} a day so far — on track for about ${formatINR(projected)} by month end`
            }
            footer={
              // Reports only the money IN on purpose: expenses are this card's own headline
              // figure, so naming them again here printed the same number twice on one card.
              <InsetRow
                href="/manager/revenue"
                title={profit < 0 ? "Running at a loss this month" : "Net this month"}
                subtitle={`${formatINR(revenueMonth)} came in this month`}
                value={formatINR(profit)}
                tone={profit < 0 ? "red" : "teal"}
              />
            }
          />

          <PrimaryAction
            href="/manager/expenses"
            label="Add an expense"
            icon={Plus}
            hint={expensesToday > 0 ? `${formatINR(expensesToday)} logged so far today` : "Nothing logged today yet"}
            disabled={!ctx.writable}
            disabledHint="Subscription expired — entries are read-only until it is renewed"
          />

          <MetricGrid>
            {/*
              Revenue and Net used to live here as well. The hero's footer row already states
              "<revenue> in · <expenses> out" with net as its value, so those two cards repeated
              three numbers the reader had just been given — the same figure twice on one screen
              is not emphasis, it is noise. These two answer questions the hero does not.
            */}
            <Metric
              label="Biggest cost"
              value={ranked.length ? formatINRCompact(ranked[0].value) : "—"}
              caption={
                ranked.length
                  ? `${ranked[0].name}${categoryTotal > 0 ? ` · ${Math.round((ranked[0].value / categoryTotal) * 100)}% of ${monthName} spend` : ""}`
                  : `Nothing logged in ${monthName} yet`
              }
              icon={IndianRupee}
              tone={ranked.length ? "navy" : "muted"}
              href="/manager/expenses"
            />
            <Metric
              label="Entries"
              value={formatNumber(monthExpenses.length)}
              caption={
                monthExpenses.length
                  ? `${plural(monthExpenses.length, "expense")} recorded in ${monthName}`
                  : "nothing recorded this month"
              }
              icon={Receipt}
              tone={monthExpenses.length ? "sage" : "muted"}
              href="/manager/expenses"
            />
            <Metric
              label="Logged today"
              value={formatINRCompact(expensesToday)}
              caption={expensesToday > 0 ? `plus ${formatINRCompact(revenueToday)} received` : "add today's spend"}
              icon={Wallet}
              tone={expensesToday > 0 ? "navy" : "muted"}
              href="/manager/expenses"
            />
            <Metric
              label="Open tasks"
              value={formatNumber(pendingTasks)}
              caption={pendingTasks === 0 ? "all caught up" : `${plural(pendingTasks, "task")} from your owner`}
              icon={ListChecks}
              tone={pendingTasks > 0 ? "sand" : "sage"}
              href="/manager/tasks"
            />
          </MetricGrid>

          <section>
            <ListSectionHeader title={`Where the money went in ${monthName}`} action={<SeeAll href="/manager/expenses">All entries</SeeAll>} />
            <InsetList aria-label={`Expenses by category for ${monthName}`}>
              {ranked.length === 0 ? (
                <InsetEmpty
                  icon={Receipt}
                  title={`No expenses recorded for ${monthName}`}
                  hint="Log the first one and this breaks down by category, ranked, with last month beside it."
                  action={
                    ctx.writable ? (
                      <SecondaryAction href="/manager/expenses" label="Add the first expense" icon={Plus} />
                    ) : undefined
                  }
                />
              ) : (
                <>
                  <div className="border-b border-separator px-4 py-4">
                    <SegmentMeter
                      segments={ranked.map((c, i) => ({ value: c.value, tone: CATEGORY_TONES[i % CATEGORY_TONES.length], label: c.name }))}
                      label={`${formatINR(categoryTotal)} of spend, split across ${ranked.length} ${plural(ranked.length, "category", "categories")}`}
                    />
                    {/* The total is the hero's headline figure at the top of this page, so this
                        line reports the SHAPE of the spend instead of restating the amount. */}
                    <p className="mt-2.5 text-footnote text-label-secondary">
                      Biggest is{" "}
                      <span className="font-semibold text-ink-navy">{ranked[0].name}</span>
                      {categoryTotal > 0
                        ? ` at ${Math.round((ranked[0].value / categoryTotal) * 100)}% of the month`
                        : ""}
                      {" · "}
                      {ranked.length} {plural(ranked.length, "category", "categories")} in all
                    </p>
                  </div>
                  {ranked.slice(0, 5).map((c, i) => {
                    const before = lastByCategory.get(c.category);
                    const share = categoryTotal > 0 ? Math.round((c.value / categoryTotal) * 100) : 0;
                    const diff = before === undefined ? null : c.value - before;
                    return (
                      <InsetRow
                        key={c.category}
                        href="/manager/expenses"
                        leading={
                          <span className={`h-8 w-1.5 shrink-0 rounded-full ${TONE_BAR[CATEGORY_TONES[i % CATEGORY_TONES.length]]}`} aria-hidden />
                        }
                        title={c.name}
                        subtitle={
                          diff === null
                            ? `${share}% of spend · new this month`
                            : diff === 0
                              ? `${share}% of spend · same as ${shortMonth(prev)}`
                              : `${share}% of spend · ${diff > 0 ? "+" : "−"}${formatINRCompact(Math.abs(diff))} vs ${shortMonth(prev)}`
                        }
                        value={formatINR(c.value)}
                      />
                    );
                  })}
                </>
              )}
            </InsetList>
          </section>
        </div>

        <div className="flex flex-col gap-6">
          <DashboardTasks tasks={openTasks.slice(0, 6)} writable={ctx.writable} total={openTasks.length} />

          <ActionRow className="grid-cols-1">
            <SecondaryAction href="/manager/revenue" label="Add revenue" icon={IndianRupee} disabled={!ctx.writable} />
          </ActionRow>

          <section>
            <ListSectionHeader title="From your owner" />
            <InsetList aria-label="Announcements from the owner">
              {announcements.length === 0 ? (
                <InsetEmpty icon={Megaphone} title="No announcements yet" hint="Updates your owner sends to managers or to everyone land here." />
              ) : (
                announcements.map((a) => (
                  <InsetRow key={a.id} icon={Megaphone} title={a.title} subtitle={a.body} valueCaption={formatDate(a.created_at, "d MMM")} />
                ))
              )}
            </InsetList>
          </section>
        </div>
      </div>
    </>
  );
}
