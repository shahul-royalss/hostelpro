import { BedDouble, CalendarOff, IndianRupee, Megaphone, MessageSquareWarning, Users, Wallet } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getAnnouncements, getFeeLedger, getHostelStats } from "@/lib/queries/warden";
import { HeroStat, heroAmount } from "@/components/dashboard/hero-stat";
import { Delta } from "@/components/dashboard/delta";
import { Meter } from "@/components/dashboard/meter";
import { InsetEmpty, InsetList, InsetRow, ListSectionHeader, SeeAll } from "@/components/dashboard/inset-list";
import { Metric, MetricGrid } from "@/components/dashboard/metric-grid";
import { PrimaryAction } from "@/components/dashboard/primary-action";
import { monthDeadline, monthProgress, previousPeriod, shortMonth, plural } from "@/components/dashboard/period";
import { formatDate, formatINR, formatINRCompact, formatNumber, percent, toPeriodMonth } from "@/lib/utils";

export const dynamic = "force-dynamic";

/**
 * WD-1 · Warden home.
 *
 * The warden's job is money in and who has not paid, so that is the hero and the
 * list directly under it. Everything that used to compete with it — four
 * equal-weight quick tiles that repeated the bottom nav (Register, Rooms, Fees
 * are all nav items) and a horizontally scrolling chip row whose last chip sat
 * off-screen at 360px — is gone.
 */
export default async function WardenHomePage() {
  const { ctx } = await requireHostelContext("warden");
  const supabase = await createClient();
  const period = toPeriodMonth();
  const prev = previousPeriod(period);

  const [stats, lastMonth, ledger, announcements] = await Promise.all([
    getHostelStats(supabase, ctx.hostel.id, period),
    // Same RPC, previous period — this is what turns every figure below from a
    // bare number into a comparison.
    getHostelStats(supabase, ctx.hostel.id, prev),
    getFeeLedger(supabase, ctx.hostel.id, period),
    getAnnouncements(supabase, ctx.hostel.id, 3),
  ]);

  const totalBeds = stats?.total_beds ?? 0;
  const occupied = stats?.occupied_beds ?? 0;
  const free = Math.max(0, totalBeds - occupied);
  const occupancy = percent(occupied, totalBeds);

  const collected = Number(stats?.fees_collected ?? 0);
  const pending = Number(stats?.fees_pending ?? 0);
  const billed = collected + pending;
  const collectionRate = percent(collected, billed);
  const unpaidCount = stats?.students_unpaid ?? 0;
  const openComplaints = stats?.open_complaints ?? 0;
  const pendingLeaves = stats?.pending_leaves ?? 0;
  const visitorsToday = stats?.visitors_today ?? 0;

  const progress = monthProgress(period);
  const money = heroAmount(collected);

  // Who has not paid, biggest gap first — the four the warden should chase today.
  const owing = ledger
    .map((r) => ({ ...r, outstanding: Math.max(0, r.amount_due - r.amount_paid) }))
    .filter((r) => r.outstanding > 0)
    .sort((a, b) => b.outstanding - a.outstanding);

  return (
    <MobilePage role="warden" title="greeting">
      {/* The shell's app bar carries the greeting and the hostel name; repeating
          either here is the duplication the owner flagged. */}
      <h1 className="sr-only">Warden dashboard</h1>

      <div className="flex flex-col gap-6">
        <HeroStat
          eyebrow={`Collected in ${progress.name}`}
          value={money.display}
          icon={IndianRupee}
          tone="navy"
          verdict={<Delta current={collected} previous={lastMonth?.fees_collected} baselineLabel={shortMonth(prev)} format={formatINRCompact} emptyLabel={`Nothing was collected in ${shortMonth(prev)}`} />}
          meter={<Meter percent={collectionRate} tone={collectionRate >= 90 ? "teal" : collectionRate >= 60 ? "navy" : "sand"} label={`${collectionRate}% of this month's fees collected`} />}
          caption={
            billed > 0
              ? // `heroAmount` compacts anything from ₹10L up so 36px digits cannot
                // overflow a 320px phone; the exact figure is restored here.
                `${money.compacted ? `${money.exact} · ` : ""}${collectionRate}% of ${formatINR(billed)} billed · ${monthDeadline(progress)}`
              : `No fees billed for ${progress.name} yet`
          }
          footer={
            unpaidCount > 0 ? (
              <InsetRow
                href="/warden/fees"
                title={`${formatNumber(unpaidCount)} ${plural(unpaidCount, "student")} still to pay`}
                subtitle={monthDeadline(progress)}
                value={formatINR(pending)}
                tone="red"
              />
            ) : billed > 0 ? (
              <InsetRow href="/warden/fees" title={`Everyone has paid for ${progress.name}`} subtitle="Open the ledger to see receipts" tone="teal" />
            ) : undefined
          }
        />

        <PrimaryAction
          href="/warden/fees"
          label="Record a payment"
          icon={Wallet}
          hint={unpaidCount > 0 ? `${formatNumber(unpaidCount)} ${plural(unpaidCount, "student")} owe ${formatINR(pending)}` : `Nothing outstanding for ${progress.name}`}
        />

        {/* Four numbers that each carry a target or a next step, in one surface.
            Every tile goes somewhere different, and two of the four (visitors,
            complaints) are not in the bottom nav — so this replaces the old tile
            grid without repeating it. */}
        <MetricGrid>
          <Metric
            label="Occupancy"
            value={`${occupancy}%`}
            caption={`${formatNumber(occupied)} of ${formatNumber(totalBeds)} beds · ${formatNumber(free)} free`}
            icon={BedDouble}
            href="/warden/rooms"
          />
          <Metric
            label="Visitors today"
            value={formatNumber(visitorsToday)}
            caption={visitorsToday === 0 ? "none signed in yet" : "signed in today"}
            icon={Users}
            tone={visitorsToday > 0 ? "navy" : "muted"}
            href="/warden/visitors"
          />
          <Metric
            label="Complaints"
            value={formatNumber(openComplaints)}
            caption={openComplaints === 0 ? "nothing open — good" : "goal: none open"}
            icon={MessageSquareWarning}
            tone={openComplaints > 0 ? "red" : "sage"}
            href="/warden/complaints"
          />
          <Metric
            label="Leave requests"
            value={formatNumber(pendingLeaves)}
            caption={pendingLeaves === 0 ? "all decided" : "waiting on you"}
            icon={CalendarOff}
            tone={pendingLeaves > 0 ? "sand" : "sage"}
            href="/warden/leaves"
          />
        </MetricGrid>

        <section>
          <ListSectionHeader title="Who hasn't paid" action={owing.length > 4 ? <SeeAll href="/warden/fees">All {formatNumber(owing.length)}</SeeAll> : undefined} />
          <InsetList aria-label={`Students with fees outstanding for ${progress.name}`}>
            {owing.length === 0 ? (
              <InsetEmpty
                icon={Wallet}
                title={billed > 0 ? `All paid up for ${progress.name}` : "No fees billed yet"}
                hint={
                  billed > 0
                    ? "Nothing to chase today. New dues appear here as soon as the month rolls over."
                    : "Register a student, or open the fee ledger to raise this month's dues."
                }
              />
            ) : (
              owing.slice(0, 4).map((r) => (
                <InsetRow
                  key={r.student_id}
                  href="/warden/fees"
                  title={r.full_name}
                  subtitle={[r.room_number ? `Room ${r.room_number}` : null, r.bed_number ? `Bed ${r.bed_number}` : null].filter(Boolean).join(" · ") || "No bed allotted"}
                  value={formatINR(r.outstanding)}
                  valueCaption={r.amount_paid > 0 ? `${formatINR(r.amount_paid)} paid` : undefined}
                  tone={r.amount_paid > 0 ? "sand" : "red"}
                />
              ))
            )}
          </InsetList>
        </section>

        <section>
          <ListSectionHeader title="From the owner" action={<SeeAll href="/warden/announcements" />} />
          <InsetList aria-label="Recent announcements">
            {announcements.length === 0 ? (
              <InsetEmpty icon={Megaphone} title="No announcements yet" hint="Notices your owner sends to the hostel will appear here, newest first." />
            ) : (
              announcements.map((a) => (
                <InsetRow key={a.id} href="/warden/announcements" title={a.title} subtitle={a.body} valueCaption={formatDate(a.created_at, "d MMM")} icon={Megaphone} />
              ))
            )}
          </InsetList>
        </section>
      </div>
    </MobilePage>
  );
}
