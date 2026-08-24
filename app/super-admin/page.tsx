import Link from "next/link";
import { AlertTriangle, Building2, CreditCard, GraduationCap, IndianRupee, PlusCircle, Users } from "lucide-react";
import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { fetchOnboardingSeries, fetchSaDashboard, fetchSaHostels } from "@/lib/queries/super-admin";
import { formatDate, formatINR, formatNumber, percent, toPeriodMonth } from "@/lib/utils";
import { HeroStat, heroAmount } from "@/components/dashboard/hero-stat";
import { Verdict } from "@/components/dashboard/delta";
import { Meter } from "@/components/dashboard/meter";
import { TrendBars } from "@/components/dashboard/trend-bars";
import { InsetEmpty, InsetList, InsetRow, ListSectionHeader, SeeAll } from "@/components/dashboard/inset-list";
import { Metric, MetricGrid } from "@/components/dashboard/metric-grid";
import { PrimaryAction } from "@/components/dashboard/primary-action";
import { longMonth, previousPeriod, shortMonth, plural } from "@/components/dashboard/period";
import { ExpiringSoonTable } from "@/components/super-admin/expiring-soon-table";

export const dynamic = "force-dynamic";

/**
 * SA-1 · Platform dashboard.
 *
 * Six equal stat cards, each captioned with a phrase that judged nothing ("on
 * the platform", "active residents"), plus a line chart and a donut that cost
 * the Recharts bundle to say "three numbers add up to a total".
 *
 * The lead is now subscription health, because that is the number that decides
 * whether the platform has a business next month, and it carries its own target
 * (every hostel active) rather than floating free.
 */
export default async function SuperAdminDashboardPage() {
  await requireRole("super_admin");
  const supabase = await createClient();

  // Sync stored subscription statuses / read-only flags + expiring notifications (DECISIONS #14). Best-effort.
  await supabase.rpc("refresh_subscription_statuses").then(() => undefined, () => undefined);

  const [stats, series, hostels] = await Promise.all([
    fetchSaDashboard(supabase),
    fetchOnboardingSeries(supabase),
    fetchSaHostels(supabase),
  ]);

  const period = toPeriodMonth();
  const prev = previousPeriod(period);
  const monthName = longMonth(period);

  const totalSubs = stats.active_subs + stats.expiring_subs + stats.expired_subs;
  const healthy = percent(stats.active_subs, totalSubs);
  const atRisk = stats.expiring_subs + stats.expired_subs;

  // §4.4 — flag hostels expiring in 7 / 15 / 30 days (+ already expired); bucketed client-side in ExpiringSoonTable
  const expiringSoon = hostels.filter((h) => h.days_left !== null && h.days_left <= 30);
  const soonest = [...expiringSoon].sort((a, b) => (a.days_left ?? 0) - (b.days_left ?? 0)).slice(0, 4);

  const onboardedThisMonth = series.find((p) => p.month === period)?.hostels ?? 0;
  const onboardedLastMonth = series.find((p) => p.month === prev)?.hostels ?? null;
  const revenue = heroAmount(stats.monthly_subscription_revenue);

  const trend = series.map((p) => ({ label: formatDate(`${p.month}-01`, "MMM"), a: p.hostels }));
  const trendHasData = trend.some((p) => p.a > 0);

  return (
    <>
      <header className="mb-6 flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div className="min-w-0">
          <h1 className="text-title-sm md:text-title text-navy">Platform</h1>
          <p className="mt-1 text-subhead text-label-secondary">
            {formatNumber(stats.total_hostels)} {plural(stats.total_hostels, "hostel")} · {formatNumber(stats.total_students)} residents · {monthName}
          </p>
        </div>
        <PrimaryAction
          href="/super-admin/create"
          label="Create owner & hostel"
          icon={PlusCircle}
          hint="Sets up the owner login, the hostel and its first subscription"
          className="md:w-auto md:max-w-sm"
        />
      </header>

      <div className="flex flex-col gap-6">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <HeroStat
            eyebrow="Subscriptions in good standing"
            value={formatNumber(stats.active_subs)}
            unit={totalSubs > 0 ? `of ${formatNumber(totalSubs)}` : undefined}
            icon={CreditCard}
            tone={atRisk === 0 ? "teal" : stats.expired_subs > 0 ? "red" : "sand"}
            verdict={
              atRisk === 0 ? (
                <Verdict verdict="good">Every hostel is paid up</Verdict>
              ) : (
                <Verdict verdict={stats.expired_subs > 0 ? "bad" : "flat"}>
                  {stats.expiring_subs > 0 ? `${formatNumber(stats.expiring_subs)} expiring soon` : ""}
                  {stats.expiring_subs > 0 && stats.expired_subs > 0 ? " · " : ""}
                  {stats.expired_subs > 0 ? `${formatNumber(stats.expired_subs)} already expired` : ""}
                </Verdict>
              )
            }
            meter={<Meter percent={healthy} tone={atRisk === 0 ? "teal" : stats.expired_subs > 0 ? "red" : "sand"} label={`${healthy}% of hostels have an active subscription`} />}
            caption={totalSubs > 0 ? `${healthy}% of hostels · target is every one of them` : "No subscriptions on the platform yet"}
            footer={
              atRisk > 0 ? (
                <InsetRow
                  href="/super-admin/subscriptions"
                  title={`${formatNumber(atRisk)} ${plural(atRisk, "hostel")} need renewing`}
                  subtitle="An expired subscription puts that hostel into read-only"
                  tone={stats.expired_subs > 0 ? "red" : "sand"}
                />
              ) : undefined
            }
          />

          <HeroStat
            size="md"
            eyebrow={`Subscription revenue · ${monthName}`}
            value={revenue.display}
            icon={IndianRupee}
            tone="navy"
            /* A percentage delta here would sit next to a rupee figure and read as
               "revenue up 50%", which is not what the platform can measure — the
               RPC exposes this month's booked total and nothing before it. So the
               verdict is a rate the reader can judge, and the onboarding
               comparison is stated as what it actually is. */
            verdict={
              <Verdict verdict="unknown">
                {stats.active_subs > 0
                  ? `${formatINR(Math.round(stats.monthly_subscription_revenue / stats.active_subs))} per active hostel`
                  : "No active hostels to average across"}
              </Verdict>
            }
            caption={
              `${revenue.compacted ? `${revenue.exact} · ` : ""}${formatNumber(onboardedThisMonth)} new ${plural(onboardedThisMonth, "hostel")} onboarded in ${monthName}` +
              (onboardedLastMonth === null ? "" : ` · ${formatNumber(onboardedLastMonth)} in ${shortMonth(prev)}`)
            }
          />
        </div>

        <MetricGrid className="lg:grid-cols-4">
          <Metric
            label="Hostels"
            value={formatNumber(stats.total_hostels)}
            caption={onboardedThisMonth > 0 ? `${formatNumber(onboardedThisMonth)} added in ${shortMonth(period)}` : `none added in ${shortMonth(period)}`}
            icon={Building2}
            href="/super-admin/hostels"
          />
          <Metric
            label="Owners"
            value={formatNumber(stats.total_owners)}
            caption={
              stats.total_owners > 0
                ? `${(stats.total_hostels / stats.total_owners).toFixed(1)} hostels each`
                : "no owner accounts yet"
            }
            icon={Users}
            href="/super-admin/hostels"
          />
          <Metric
            label="Residents"
            value={formatNumber(stats.total_students)}
            caption={
              stats.total_hostels > 0
                ? `${Math.round(stats.total_students / stats.total_hostels)} per hostel on average`
                : "no hostels yet"
            }
            icon={GraduationCap}
          />
          <Metric
            label="Expiring soon"
            value={formatNumber(stats.expiring_subs)}
            caption={stats.expired_subs > 0 ? `${formatNumber(stats.expired_subs)} already expired` : "none lapsed yet"}
            icon={AlertTriangle}
            tone={stats.expired_subs > 0 ? "red" : stats.expiring_subs > 0 ? "sand" : "sage"}
            href="/super-admin/subscriptions"
          />
        </MetricGrid>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          <section className="material-regular rounded-card squircle p-5 md:p-6">
            <div className="mb-4 min-w-0">
              <h2 className="text-card-title font-semibold text-navy">Hostels onboarded</h2>
              <p className="mt-0.5 text-footnote text-label-secondary">One bar per month, last 12 months</p>
            </div>
            {trendHasData ? (
              <TrendBars
                points={trend}
                aLabel="New hostels"
                aTone="navy"
                summary={`New hostels per month for the last 12 months, ${formatNumber(trend.reduce((s, p) => s + p.a, 0))} in total.`}
              />
            ) : (
              <InsetEmpty icon={Building2} title="No hostels onboarded yet" hint="Create the first owner and hostel; this chart fills in one bar per month." />
            )}
          </section>

          <section>
            <ListSectionHeader title="Renew these first" action={<SeeAll href="/super-admin/subscriptions" />} />
            <InsetList aria-label="Subscriptions closest to expiry">
              {soonest.length === 0 ? (
                <InsetEmpty icon={CreditCard} title="Nothing expiring in the next 30 days" hint="Hostels move here automatically as their renewal date approaches, soonest first." />
              ) : (
                soonest.map((h) => (
                  <InsetRow
                    key={h.hostel_id}
                    href={`/super-admin/hostels/${h.hostel_id}`}
                    icon={Building2}
                    tone={(h.days_left ?? 0) < 0 ? "red" : (h.days_left ?? 0) <= 7 ? "sand" : "default"}
                    title={h.hostel_name}
                    subtitle={`${h.owner_name}${h.sub_end ? ` · ends ${formatDate(h.sub_end, "d MMM")}` : ""}`}
                    value={(h.days_left ?? 0) < 0 ? "Expired" : `${formatNumber(h.days_left ?? 0)}d`}
                    valueCaption={(h.days_left ?? 0) < 0 ? `${formatNumber(Math.abs(h.days_left ?? 0))} days ago` : "left"}
                  />
                ))
              )}
            </InsetList>
          </section>
        </div>

        {/* Expiring soon table — 7 / 15 / 30-day windows (§4.4) */}
        <section className="material-regular overflow-hidden rounded-card squircle">
          <div className="flex flex-wrap items-end justify-between gap-3 p-5 pb-4 md:p-6 md:pb-4">
            <div className="min-w-0">
              <h2 className="text-card-title font-semibold text-navy">Renewal windows</h2>
              <p className="mt-0.5 text-footnote text-label-secondary">
                {formatNumber(expiringSoon.length)} {plural(expiringSoon.length, "subscription")} ending within 30 days, plus anything already lapsed
              </p>
            </div>
            <Link href="/super-admin/subscriptions" className="text-footnote font-medium text-ink-navy hover:underline">
              View all subscriptions
            </Link>
          </div>
          <ExpiringSoonTable rows={expiringSoon} />
        </section>
      </div>
    </>
  );
}
