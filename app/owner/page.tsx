import Link from "next/link";
import { format } from "date-fns";
import { ArrowUpRight, IndianRupee, Megaphone, MessageSquareWarning, Users, Wallet } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { firstName, formatINRCompact, formatDateTime, formatNumber, greeting, percent } from "@/lib/utils";
import { getHostelStats, getLast30DaysFinance, getLatestAnnouncements, getRecentComplaints } from "@/lib/queries/owner";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatCard, ProgressRing } from "@/components/shared/stat-card";
import { StatusPill, Chip } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { AreaTrend } from "@/components/shared/charts";
import { SubscriptionCard } from "@/components/owner/subscription-card";
import { ComplaintCategoryIcon } from "@/components/owner/complaint-icon";
import { Button } from "@/components/ui/button";

export const dynamic = "force-dynamic";

export default async function OwnerDashboardPage() {
  const { user, ctx } = await requireHostelContext("owner");
  const supabase = await createClient();
  const hostelId = ctx.hostel.id;

  // Stored subscription statuses / hostel read-only flags are refreshed alongside the reads (DECISIONS #14) —
  // it never blocks the page (read-only enforcement is computed live via app.subscription_state) and errors are non-fatal.
  const [stats, finance, announcements, complaints] = await Promise.all([
    getHostelStats(supabase, hostelId),
    getLast30DaysFinance(supabase, hostelId),
    getLatestAnnouncements(supabase, hostelId, 4),
    getRecentComplaints(supabase, hostelId, 4),
    supabase.rpc("refresh_subscription_statuses").then(() => undefined, () => undefined),
  ]);

  const totalBeds = stats?.total_beds ?? 0;
  const occupied = stats?.occupied_beds ?? 0;
  const occupancy = percent(occupied, totalBeds);
  const chartData = finance.map((d) => ({
    day: format(new Date(`${d.day}T00:00:00`), "d MMM"),
    revenue: d.revenue,
    expenses: d.expense,
  }));

  return (
    <>
      {/* Header */}
      <div className="mb-6 flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
        <div>
          <h1 className="text-title-sm md:text-title text-navy">
            {greeting()}, {firstName(user.full_name)}
          </h1>
          <p className="mt-1 text-sm text-muted">Here&apos;s what&apos;s happening at {ctx.hostel.name} today.</p>
        </div>
        <SubscriptionCard ctx={ctx} />
      </div>

      {/* Stat row */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5 lg:gap-6">
        <StatCard label="Occupancy" value={formatNumber(occupied)} caption={`${formatNumber(occupied)} / ${formatNumber(totalBeds)} beds`} className="relative">
          <div className="absolute right-5 top-5 md:right-6 md:top-6">
            <ProgressRing percent={occupancy} size={52} />
          </div>
        </StatCard>
        <StatCard label="Active students" value={formatNumber(stats?.active_students ?? 0)} caption="Currently registered" icon={Users} />
        <StatCard label="Fees collected" value={formatINRCompact(stats?.fees_collected ?? 0)} caption="This month" tone="teal" icon={IndianRupee} />
        <StatCard label="Fees pending" value={formatINRCompact(stats?.fees_pending ?? 0)} caption={`${formatNumber(stats?.students_unpaid ?? 0)} students due`} tone="red" icon={Wallet} />
        <StatCard label="Open complaints" value={formatNumber(stats?.open_complaints ?? 0)} caption="Awaiting resolution" icon={MessageSquareWarning} />
      </div>

      {/* Middle + right column */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <GlassCard className="lg:col-span-2">
          <GlassCardHeader
            title="Revenue vs Expenses"
            description="Daily totals for the last 30 days"
            action={<Chip>Last 30 days</Chip>}
          />
          {finance.some((d) => d.revenue > 0 || d.expense > 0) ? (
            <AreaTrend
              data={chartData}
              xKey="day"
              height={300}
              series={[
                { key: "revenue", label: "Revenue" },
                { key: "expenses", label: "Expenses" },
              ]}
            />
          ) : (
            <EmptyState icon={Wallet} title="No finance entries yet" description="Revenue and expenses recorded by your manager will chart here." />
          )}
        </GlassCard>

        <div className="flex flex-col gap-6">
          <GlassCard>
            <GlassCardHeader
              title="Latest updates"
              action={
                <Button asChild variant="link" size="sm" className="h-auto px-0">
                  <Link href="/owner/updates">
                    View all <ArrowUpRight />
                  </Link>
                </Button>
              }
            />
            {announcements.length === 0 ? (
              <EmptyState
                compact
                icon={Megaphone}
                title="No updates sent yet"
                action={
                  <Button asChild size="sm">
                    <Link href="/owner/updates">Send an update</Link>
                  </Button>
                }
              />
            ) : (
              <ul className="space-y-3">
                {announcements.map((a) => (
                  <li key={a.id} className="flex gap-3">
                    <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-teal" aria-hidden />
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-muted">
                        <span className="tabular">{formatDateTime(a.created_at)}</span>
                        <StatusPill status={a.audience} size="sm" />
                      </div>
                      <p className="mt-0.5 line-clamp-2 text-sm font-medium text-charcoal">{a.title}</p>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </GlassCard>

          <GlassCard>
            <GlassCardHeader
              title="Recent complaints"
              action={
                <Button asChild variant="link" size="sm" className="h-auto px-0">
                  <Link href="/owner/complaints">
                    View all <ArrowUpRight />
                  </Link>
                </Button>
              }
            />
            {complaints.length === 0 ? (
              <EmptyState compact icon={MessageSquareWarning} title="No complaints yet" description="Students haven't raised anything." />
            ) : (
              <ul className="divide-y divide-line/70">
                {complaints.map((c) => (
                  <li key={c.id}>
                    <Link href={`/owner/complaints?id=${c.id}`} className="-mx-2 flex items-center gap-3 rounded-control px-2 py-2.5 transition-colors hover:bg-white/60">
                      <ComplaintCategoryIcon category={c.category} size="sm" />
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-charcoal">{c.title}</p>
                        <p className="truncate text-[12px] text-muted">
                          {c.student?.room?.room_number ? `Room ${c.student.room.room_number} · ` : ""}
                          {c.student?.full_name ?? "Student"}
                        </p>
                      </div>
                      <StatusPill status={c.status} size="sm" />
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </GlassCard>
        </div>
      </div>
    </>
  );
}
