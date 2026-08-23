import Link from "next/link";
import { AlertTriangle, Building2, CreditCard, GraduationCap, IndianRupee, Users } from "lucide-react";
import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { fetchOnboardingSeries, fetchSaDashboard, fetchSaHostels } from "@/lib/queries/super-admin";
import { formatDate, formatINRCompact, formatNumber } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { StatCard } from "@/components/shared/stat-card";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { EmptyState } from "@/components/shared/empty-state";
import { CHART, Donut, DonutLegend, LineTrend } from "@/components/shared/charts";
import { Button } from "@/components/ui/button";
import { ExpiringSoonTable } from "@/components/super-admin/expiring-soon-table";

export const dynamic = "force-dynamic";

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

  const onboarding = series.map((p) => ({ month: formatDate(`${p.month}-01`, "MMM"), hostels: p.hostels }));
  const donut = [
    { name: "Active", value: stats.active_subs, color: CHART.teal },
    { name: "Expiring", value: stats.expiring_subs, color: CHART.sand },
    { name: "Expired", value: stats.expired_subs, color: CHART.red },
  ];
  const totalSubs = stats.active_subs + stats.expiring_subs + stats.expired_subs;

  // §4.4 — flag hostels expiring in 7 / 15 / 30 days (+ already expired); bucketed client-side in ExpiringSoonTable
  const expiringSoon = hostels.filter((h) => h.days_left !== null && h.days_left <= 30);

  return (
    <>
      <PageHeader
        title="Dashboard"
        description="Platform overview — hostels, subscriptions and residents across NIVORA."
        actions={
          <Button asChild>
            <Link href="/super-admin/create">Create owner &amp; hostel</Link>
          </Button>
        }
      />

      {/* Stat row */}
      <div className="grid grid-cols-2 gap-4 md:grid-cols-3 md:gap-6 xl:grid-cols-6">
        <StatCard label="Total hostels" value={formatNumber(stats.total_hostels)} icon={Building2} caption="on the platform" />
        <StatCard label="Active subscriptions" value={formatNumber(stats.active_subs)} icon={CreditCard} tone="teal" caption={`of ${formatNumber(totalSubs)} total`} />
        <StatCard
          label="Expiring soon"
          value={formatNumber(stats.expiring_subs)}
          icon={AlertTriangle}
          tone="sand"
          caption={stats.expired_subs > 0 ? `${formatNumber(stats.expired_subs)} already expired` : "within 15 days"}
        />
        <StatCard label="Total students" value={formatNumber(stats.total_students)} icon={GraduationCap} caption="active residents" />
        <StatCard label="Total owners" value={formatNumber(stats.total_owners)} icon={Users} caption="owner accounts" />
        <StatCard label="Subscription revenue" value={formatINRCompact(stats.monthly_subscription_revenue)} icon={IndianRupee} tone="teal" caption="this month" />
      </div>

      {/* Charts */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <GlassCard className="lg:col-span-2">
          <GlassCardHeader title="Hostels onboarded" description="New hostels created per month, last 12 months" />
          {series.length ? (
            <LineTrend data={onboarding} xKey="month" series={[{ key: "hostels", label: "Hostels" }]} height={280} />
          ) : (
            <EmptyState compact title="No onboarding data yet" />
          )}
        </GlassCard>
        <GlassCard>
          <GlassCardHeader title="Subscription status" description="Live state across all hostels" />
          {totalSubs > 0 ? (
            <>
              <Donut data={donut} height={220} centerLabel="Hostels" centerValue={formatNumber(totalSubs)} />
              <div className="mt-2">
                <DonutLegend data={donut} />
              </div>
            </>
          ) : (
            <EmptyState compact title="No subscriptions yet" description="Create the first owner and hostel to get started." />
          )}
        </GlassCard>
      </div>

      {/* Expiring soon table — 7 / 15 / 30-day windows (§4.4) */}
      <GlassCard className="mt-6" padded={false}>
        <div className="p-5 pb-4 md:p-6 md:pb-4">
          <GlassCardHeader
            title="Expiring soon"
            description="Subscriptions ending within 7 / 15 / 30 days (and any already expired)"
            action={
              <Button asChild variant="ghost" size="sm">
                <Link href="/super-admin/subscriptions">View all</Link>
              </Button>
            }
          />
        </div>
        <ExpiringSoonTable rows={expiringSoon} />
      </GlassCard>
    </>
  );
}
