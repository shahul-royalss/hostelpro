import Link from "next/link";
import { BedDouble, CalendarOff, ChevronRight, Megaphone, MessageSquareWarning, UserPlus, Users, Wallet, type LucideIcon } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getAnnouncements, getHostelStats } from "@/lib/queries/warden";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { Progress } from "@/components/ui/misc";
import { EmptyState } from "@/components/shared/empty-state";
import { Chip } from "@/components/shared/status-pill";
import { cn, formatDate, formatNumber, percent } from "@/lib/utils";

export const dynamic = "force-dynamic";

const TILES: { href: string; label: string; icon: LucideIcon }[] = [
  { href: "/warden/register", label: "Register student", icon: UserPlus },
  { href: "/warden/rooms", label: "Rooms & beds", icon: BedDouble },
  { href: "/warden/fees", label: "Fees", icon: Wallet },
  { href: "/warden/visitors", label: "Visitors", icon: Users },
];

export default async function WardenHomePage() {
  const { ctx } = await requireHostelContext("warden");
  const supabase = await createClient();
  const [stats, announcements] = await Promise.all([getHostelStats(supabase, ctx.hostel.id), getAnnouncements(supabase, ctx.hostel.id, 4)]);

  const totalBeds = stats?.total_beds ?? 0;
  const occupied = stats?.occupied_beds ?? 0;
  const free = Math.max(0, totalBeds - occupied);
  const pct = percent(occupied, totalBeds);
  const unpaid = stats?.students_unpaid ?? 0;

  const chips = [
    { href: "/warden/leaves", label: "Pending leaves", count: stats?.pending_leaves ?? 0, icon: CalendarOff, tone: "sand" as const },
    { href: "/warden/visitors", label: "Visitors today", count: stats?.visitors_today ?? 0, icon: Users, tone: "navy" as const },
    { href: "/warden/complaints", label: "Open complaints", count: stats?.open_complaints ?? 0, icon: MessageSquareWarning, tone: "red" as const },
  ];

  return (
    <MobilePage role="warden" title="greeting">
      <p className="mb-4 text-[13px] text-muted">Here is the status of {ctx.hostel.name} today.</p>

      <div className="flex flex-col gap-4">
        {/* Occupancy hero */}
        <GlassCard as="section" aria-labelledby="occupancy-title">
          <div className="mb-3 flex items-center justify-between">
            <h2 id="occupancy-title" className="text-card-title font-semibold text-navy">Occupancy</h2>
            <BedDouble className="h-5 w-5 text-navy/40" strokeWidth={1.75} />
          </div>
          <div className="flex items-baseline gap-2">
            <span className="text-stat text-navy tabular">{formatNumber(occupied)}</span>
            <span className="text-sm text-muted">/ {formatNumber(totalBeds)} beds filled</span>
          </div>
          <Progress value={pct} aria-label={`${pct}% occupied`} className="mt-3 h-1.5" />
          <div className="mt-4 grid grid-cols-2 gap-3">
            <div>
              <div className="label-caps">Free beds</div>
              <div className="mt-1 text-stat-sm text-sage tabular">{formatNumber(free)}</div>
            </div>
            <div>
              <div className="label-caps">Fees pending</div>
              <div className="mt-1 text-stat-sm text-red tabular">
                {formatNumber(unpaid)} <span className="text-sm font-medium">{unpaid === 1 ? "student" : "students"}</span>
              </div>
            </div>
          </div>
        </GlassCard>

        {/* Quick actions */}
        <div className="grid grid-cols-2 gap-4">
          {TILES.map(({ href, label, icon: Icon }) => (
            <Link
              key={href}
              href={href}
              className="glass-card flex min-h-[112px] flex-col items-center justify-center gap-3 p-4 text-center transition-all hover:bg-white/80 active:scale-[0.98]"
            >
              <span className="flex h-11 w-11 items-center justify-center rounded-full bg-navy/5 text-navy">
                <Icon className="h-5 w-5" strokeWidth={1.75} />
              </span>
              <span className="text-sm font-semibold text-navy">{label}</span>
            </Link>
          ))}
        </div>

        {/* Status chips */}
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4">
          {chips.map(({ href, label, count, icon: Icon, tone }) => (
            <Link
              key={href}
              href={href}
              className={cn(
                "inline-flex h-10 shrink-0 items-center gap-2 rounded-full border border-white/70 bg-white/60 px-3.5 text-[13px] font-medium text-charcoal backdrop-blur-md transition-colors hover:bg-white/80",
              )}
            >
              <Icon className="h-4 w-4 text-muted" strokeWidth={1.75} />
              {label}
              <Chip tone={count > 0 ? tone : "muted"} className="tabular">{count}</Chip>
            </Link>
          ))}
        </div>

        {/* Announcements */}
        <GlassCard as="section" aria-labelledby="ann-title">
          <GlassCardHeader
            title={<span id="ann-title">Announcements</span>}
            action={
              <Link href="/warden/announcements" className="inline-flex items-center gap-0.5 text-[13px] font-medium text-navy hover:underline">
                See all <ChevronRight className="h-3.5 w-3.5" />
              </Link>
            }
          />
          {announcements.length === 0 ? (
            <EmptyState icon={Megaphone} title="No announcements yet" description="Updates from the owner will show up here." compact />
          ) : (
            <ul className="flex flex-col divide-y divide-line">
              {announcements.map((a) => (
                <li key={a.id} className="flex gap-3 py-3 first:pt-0 last:pb-0">
                  <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-teal" aria-hidden />
                  <div className="min-w-0">
                    <p className="text-sm font-semibold text-navy">{a.title}</p>
                    <p className="mt-0.5 line-clamp-2 text-[13px] text-muted">{a.body}</p>
                    <p className="mt-1 text-[11px] text-muted/80">{formatDate(a.created_at)}</p>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>
      </div>
    </MobilePage>
  );
}
