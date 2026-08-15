import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, BedDouble, Building2, CalendarRange, GraduationCap, IndianRupee, Mail, MapPin, MessageSquareWarning, Phone, UserRound } from "lucide-react";
import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import {
  fetchComplaintsPerWeek,
  fetchHostelRow,
  fetchHostelStaff,
  fetchHostelStats,
  fetchMonthlyFinance,
  fetchSaHostel,
  fetchSubscriptionHistory,
} from "@/lib/queries/super-admin";
import { formatDate, formatINR, formatINRCompact, formatNumber, percent } from "@/lib/utils";
import { ROLE_LABEL } from "@/lib/roles";
import { PageHeader } from "@/components/shared/page-header";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatCard } from "@/components/shared/stat-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { GroupedBars, LineTrend } from "@/components/shared/charts";
import { Button } from "@/components/ui/button";
import { UserAvatar } from "@/components/ui/avatar";
import { Progress } from "@/components/ui/misc";
import { RenewButton } from "@/components/super-admin/renew-dialog";
import { HostelStatusButton, RegeneratePasswordButton } from "@/components/super-admin/hostel-actions";
import { DaysLeftPill } from "@/components/super-admin/days-left-pill";
import { SubscriptionTimeline } from "@/components/super-admin/subscription-timeline";

export const dynamic = "force-dynamic";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** SA-4 — Hostel detail (monitoring, read-only except Renew / Suspend) */
export default async function HostelDetailPage({ params }: { params: Promise<{ id: string }> }) {
  await requireRole("super_admin");
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();

  const supabase = await createClient();
  const hostel = await fetchSaHostel(supabase, id);
  if (!hostel) notFound();

  const [row, stats, finance, complaintsWeekly, staff, history] = await Promise.all([
    fetchHostelRow(supabase, id),
    fetchHostelStats(supabase, id),
    fetchMonthlyFinance(supabase, id, 6),
    fetchComplaintsPerWeek(supabase, id, 8),
    fetchHostelStaff(supabase, id),
    fetchSubscriptionHistory(supabase, id),
  ]);

  const totalBeds = stats?.total_beds ?? hostel.total_beds;
  const occupiedBeds = stats?.occupied_beds ?? hostel.occupied_beds;
  const occupancy = percent(occupiedBeds, totalBeds);
  const students = stats?.active_students ?? hostel.active_students;
  const openComplaints = stats?.open_complaints ?? hostel.open_complaints;
  const revenueMonth = stats?.revenue_month ?? 0;
  const expensesMonth = stats?.expenses_month ?? 0;

  const financeData = finance.map((p) => ({ month: p.month, revenue: p.revenue, expenses: p.expenses }));
  const hasFinance = finance.some((p) => p.revenue > 0 || p.expenses > 0);
  const complaintsData = complaintsWeekly.map((w) => ({ week: formatDate(w.week_start, "d MMM"), complaints: w.complaints }));
  const hasComplaints = complaintsWeekly.some((w) => w.complaints > 0);

  const manager = staff.find((u) => u.role === "manager" && u.status === "active") ?? staff.find((u) => u.role === "manager") ?? null;
  const warden = staff.find((u) => u.role === "warden" && u.status === "active") ?? staff.find((u) => u.role === "warden") ?? null;
  const renewTarget = { hostelId: hostel.hostel_id, hostelName: hostel.hostel_name, currentEnd: hostel.sub_end, defaultAmount: hostel.sub_amount };
  const effectiveStatus = hostel.hostel_status === "suspended" ? "suspended" : hostel.sub_state;

  return (
    <>
      <PageHeader
        eyebrow={
          <Link href="/super-admin/hostels" className="inline-flex items-center gap-1 text-muted hover:text-navy">
            <ArrowLeft className="h-3 w-3" />
            Hostels
          </Link>
        }
        title="Hostel detail"
        description="Monitoring view — tenant data is read-only for the Super Admin."
        actions={
          <>
            <RegeneratePasswordButton ownerUserId={hostel.owner_id} />
            <HostelStatusButton hostelId={hostel.hostel_id} hostelName={hostel.hostel_name} status={hostel.hostel_status} size="default" />
          </>
        }
      />

      {/* Header card */}
      <GlassCard>
        <div className="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
          <div className="flex min-w-0 items-start gap-4">
            <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-card bg-navy/5 text-navy">
              <Building2 className="h-6 w-6" strokeWidth={1.75} />
            </span>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2.5">
                <h2 className="text-title-sm text-navy">{hostel.hostel_name}</h2>
                <StatusPill status={effectiveStatus} />
                {hostel.hostel_status === "readonly" ? <StatusPill status="readonly" /> : null}
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-x-5 gap-y-1.5 text-sm text-charcoal">
                <span className="inline-flex items-center gap-1.5">
                  <UserRound className="h-4 w-4 text-muted" />
                  {hostel.owner_name}
                </span>
                {hostel.owner_phone ? (
                  <span className="inline-flex items-center gap-1.5">
                    <Phone className="h-4 w-4 text-muted" />
                    {hostel.owner_phone}
                  </span>
                ) : null}
                {hostel.owner_email ? (
                  <span className="inline-flex items-center gap-1.5">
                    <Mail className="h-4 w-4 text-muted" />
                    {hostel.owner_email}
                  </span>
                ) : null}
              </div>
              <div className="mt-1.5 flex flex-wrap items-center gap-x-5 gap-y-1.5 text-sm text-muted">
                {hostel.address ? (
                  <span className="inline-flex items-center gap-1.5">
                    <MapPin className="h-4 w-4" />
                    {hostel.address}
                  </span>
                ) : null}
                <span className="inline-flex items-center gap-1.5">
                  <BedDouble className="h-4 w-4" />
                  {formatNumber(totalBeds)} beds · onboarded {formatDate(hostel.created_at)}
                </span>
              </div>
            </div>
          </div>

          <div className="flex shrink-0 flex-col items-start gap-3 lg:items-end">
            <div className="flex items-center gap-3">
              <div className="text-left lg:text-right">
                <div className="label-caps">Subscription ends</div>
                <div className="text-[17px] font-semibold text-navy tabular">{formatDate(hostel.sub_end)}</div>
              </div>
              <DaysLeftPill daysLeft={hostel.days_left} />
            </div>
            <RenewButton target={renewTarget}>
              <CalendarRange />
              Renew subscription
            </RenewButton>
          </div>
        </div>
      </GlassCard>

      {/* Stat cards */}
      <div className="mt-6 grid grid-cols-2 gap-4 md:gap-6 xl:grid-cols-4">
        <StatCard label="Occupancy" value={`${occupancy}%`} icon={BedDouble} caption={`${formatNumber(occupiedBeds)} / ${formatNumber(totalBeds)} beds`}>
          <Progress value={occupancy} className="mt-3 h-1.5" indicatorClassName={occupancy >= 90 ? "bg-teal" : "bg-navy"} aria-label={`${occupancy}% occupied`} />
        </StatCard>
        <StatCard label="Active students" value={formatNumber(students)} icon={GraduationCap} caption={`${formatNumber(stats?.students_paid ?? 0)} paid this month`} />
        <StatCard
          label="Open complaints"
          value={formatNumber(openComplaints)}
          icon={MessageSquareWarning}
          tone={openComplaints > 0 ? "red" : "teal"}
          caption={openComplaints > 0 ? "Action needed" : "All resolved"}
        />
        <StatCard
          label="This-month revenue"
          value={formatINRCompact(revenueMonth)}
          icon={IndianRupee}
          tone="teal"
          caption={`vs ${formatINRCompact(expensesMonth)} expenses`}
        />
      </div>

      {/* Charts */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
        <GlassCard>
          <GlassCardHeader title="Revenue vs Expenses" description="Monthly totals, last 6 months" />
          {hasFinance ? (
            <GroupedBars
              data={financeData}
              xKey="month"
              series={[
                { key: "revenue", label: "Revenue" },
                { key: "expenses", label: "Expenses" },
              ]}
              height={260}
            />
          ) : (
            <EmptyState compact title="No finance entries yet" description="The manager's revenue and expense entries will appear here." />
          )}
        </GlassCard>
        <GlassCard>
          <GlassCardHeader title="Complaints per week" description="New complaints raised, last 8 weeks" />
          {hasComplaints ? (
            <LineTrend data={complaintsData} xKey="week" series={[{ key: "complaints", label: "Complaints" }]} height={260} />
          ) : (
            <EmptyState compact title="No complaints in the last 8 weeks" description="Nice and quiet." />
          )}
        </GlassCard>
      </div>

      {/* Staff + subscription history */}
      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div className="space-y-6">
          <GlassCard>
            <GlassCardHeader title="Staff" description="One manager and one warden per hostel" />
            <div className="space-y-3">
              <StaffCard role="manager" user={manager} />
              <StaffCard role="warden" user={warden} />
            </div>
          </GlassCard>
          <GlassCard>
            <GlassCardHeader title="Structure" />
            <dl className="grid grid-cols-2 gap-3 text-sm">
              <StructRow label="Floors" value={formatNumber(row?.total_floors ?? 0)} />
              <StructRow label="Rooms" value={formatNumber(row?.total_rooms ?? 0)} />
              <StructRow label="Beds" value={formatNumber(totalBeds)} />
              <StructRow label="Occupied" value={formatNumber(occupiedBeds)} />
              <StructRow label="Free" value={formatNumber(Math.max(0, totalBeds - occupiedBeds))} />
              <StructRow label="Fees collected" value={formatINR(stats?.fees_collected ?? 0)} />
              <StructRow label="Fees pending" value={formatINR(stats?.fees_pending ?? 0)} />
              <StructRow label="Pending leaves" value={formatNumber(stats?.pending_leaves ?? 0)} />
            </dl>
          </GlassCard>
        </div>
        <GlassCard className="lg:col-span-2">
          <GlassCardHeader
            title="Subscription history"
            description={`${history.length} period${history.length === 1 ? "" : "s"} · lifetime value ${formatINR(history.reduce((s, h) => s + h.amount, 0))}`}
            action={
              <Button asChild variant="ghost" size="sm">
                <Link href="/super-admin/subscriptions">All subscriptions</Link>
              </Button>
            }
          />
          <SubscriptionTimeline subscriptions={history} />
        </GlassCard>
      </div>
    </>
  );
}

function StaffCard({ role, user }: { role: "manager" | "warden"; user: { full_name: string; phone: string | null; email: string | null; status: string } | null }) {
  const label = ROLE_LABEL[role];
  if (!user) {
    return (
      <div className="flex items-center gap-3 rounded-card border border-dashed border-line bg-white/40 p-3.5">
        <span className="flex h-10 w-10 items-center justify-center rounded-full bg-stone text-muted">
          <UserRound className="h-4 w-4" />
        </span>
        <div className="min-w-0">
          <div className="text-sm font-medium text-navy">No {label.toLowerCase()} yet</div>
          <div className="text-xs text-muted">The owner adds staff from their dashboard.</div>
        </div>
      </div>
    );
  }
  return (
    <div className="flex items-center gap-3 rounded-card border border-line/70 bg-white/50 p-3.5">
      <UserAvatar name={user.full_name} />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-semibold text-navy">{user.full_name}</span>
          <StatusPill status={user.status} size="sm" />
        </div>
        <div className="truncate text-xs text-muted">
          {label}
          {user.phone ? ` · ${user.phone}` : ""}
          {user.email ? ` · ${user.email}` : ""}
        </div>
      </div>
    </div>
  );
}

function StructRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-control bg-white/50 px-3 py-2">
      <dt className="label-caps">{label}</dt>
      <dd className="mt-0.5 font-semibold text-navy tabular">{value}</dd>
    </div>
  );
}
