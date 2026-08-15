import Link from "next/link";
import { AlertTriangle, Building2, CreditCard, GraduationCap, IndianRupee, Users } from "lucide-react";
import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { fetchOnboardingSeries, fetchSaDashboard, fetchSaHostels } from "@/lib/queries/super-admin";
import { formatDate, formatINRCompact, formatNumber } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { StatCard } from "@/components/shared/stat-card";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { CHART, Donut, DonutLegend, LineTrend } from "@/components/shared/charts";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { RenewButton } from "@/components/super-admin/renew-dialog";
import { DaysLeftPill } from "@/components/super-admin/days-left-pill";

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

  const expiringSoon = hostels
    .filter((h) => h.days_left !== null && h.days_left <= 30)
    .sort((a, b) => (a.days_left ?? 0) - (b.days_left ?? 0));

  return (
    <>
      <PageHeader
        title="Dashboard"
        description="Platform overview — hostels, subscriptions and residents across HostelPro."
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

      {/* Expiring soon table */}
      <GlassCard className="mt-6" padded={false}>
        <div className="p-5 pb-0 md:p-6 md:pb-0">
          <GlassCardHeader
            title="Expiring soon"
            description="Subscriptions ending within 30 days (and any already expired)"
            action={
              <Button asChild variant="ghost" size="sm">
                <Link href="/super-admin/subscriptions">View all</Link>
              </Button>
            }
          />
        </div>
        {expiringSoon.length === 0 ? (
          <EmptyState compact title="Nothing expiring in the next 30 days" description="All subscriptions are in good standing." />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="pl-6">Hostel</TableHead>
                <TableHead>Owner</TableHead>
                <TableHead>Ends on</TableHead>
                <TableHead>Days left</TableHead>
                <TableHead>Status</TableHead>
                <TableHead className="pr-6 text-right">Action</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {expiringSoon.map((h) => (
                <TableRow key={h.hostel_id}>
                  <TableCell className="pl-6">
                    <Link href={`/super-admin/hostels/${h.hostel_id}`} className="font-medium text-navy hover:underline">
                      {h.hostel_name}
                    </Link>
                  </TableCell>
                  <TableCell>
                    <div className="text-charcoal">{h.owner_name}</div>
                    <div className="text-xs text-muted">{h.owner_email ?? h.owner_phone ?? ""}</div>
                  </TableCell>
                  <TableCell className="tabular">{formatDate(h.sub_end)}</TableCell>
                  <TableCell>
                    <DaysLeftPill daysLeft={h.days_left} />
                  </TableCell>
                  <TableCell>
                    <StatusPill status={h.hostel_status === "suspended" ? "suspended" : h.sub_state} />
                  </TableCell>
                  <TableCell className="pr-6 text-right">
                    <RenewButton
                      size="sm"
                      target={{ hostelId: h.hostel_id, hostelName: h.hostel_name, currentEnd: h.sub_end, defaultAmount: h.sub_amount }}
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </GlassCard>
    </>
  );
}
