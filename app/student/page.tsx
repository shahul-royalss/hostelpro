import Link from "next/link";
import { PayRentButton } from "@/components/payments/pay-rent-button";
import { Bed, Building2, CalendarOff, ChevronRight, MessageSquareWarning, Phone, UtensilsCrossed, Megaphone, ShieldQuestion } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { QuickGrid } from "@/components/student/quick-grid";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getAnnouncements, getHostelContacts, getMyFeeForPeriod, getMyStudent, summariseFee } from "@/lib/queries/student";
import { firstName, formatDate, formatINR, formatPeriodMonth, toPeriodMonth } from "@/lib/utils";

export default async function StudentHomePage() {
  const { user, ctx } = await requireHostelContext("student");
  const supabase = await createClient();
  const period = toPeriodMonth();

  const [student, announcements, contacts] = await Promise.all([
    getMyStudent(supabase, user.id),
    getAnnouncements(supabase, ctx.hostel.id, 5),
    getHostelContacts(supabase),
  ]);
  const fee = student ? summariseFee(await getMyFeeForPeriod(supabase, student.id, period), Number(student.monthly_fee)) : null;

  const room = student?.room;
  const roomLine = room
    ? [`Room ${room.room_number}`, student?.bed ? `Bed ${student.bed.bed_number}` : null, room.floor ? `Floor ${room.floor.floor_number}` : null]
        .filter(Boolean)
        .join(" · ")
    : null;

  return (
    <MobilePage role="student" title={`Hi, ${firstName(user.full_name)}`} subtitle={ctx.hostel.name}>
      <div className="flex flex-col gap-4">
        {/* Hero — room + fee status */}
        <GlassCard strong className="p-5">
          <div className="flex items-start gap-3">
            <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-control bg-navy/10 text-navy">
              <Building2 className="h-5 w-5" strokeWidth={1.75} />
            </span>
            <div className="min-w-0 flex-1">
              <div className="label-caps">My stay</div>
              {roomLine ? (
                <div className="mt-0.5 text-[20px] font-bold leading-tight text-navy">{roomLine}</div>
              ) : (
                <div className="mt-0.5 text-[17px] font-semibold text-navy">No room assigned yet</div>
              )}
              <div className="mt-0.5 text-[12px] text-muted">{ctx.hostel.name}</div>
            </div>
          </div>

          <div className="mt-4 flex items-center justify-between gap-3 rounded-control bg-white/60 px-3.5 py-3">
            <div className="min-w-0">
              <div className="label-caps">{formatPeriodMonth(period)} fee</div>
              <div className="mt-0.5 text-[12px] text-muted">
                {!fee
                  ? "Not linked to a student record"
                  : fee.status === "paid"
                    ? `${formatINR(fee.paid)} received — thank you`
                    : "Pay at warden desk"}
              </div>
            </div>
            {fee ? (
              fee.status === "paid" ? (
                <StatusPill status="paid" label="Paid" />
              ) : fee.status === "partial" ? (
                <StatusPill status="partial" label={`Partial · ${formatINR(fee.remaining)} remaining`} />
              ) : (
                <StatusPill status="unpaid" label={`Due ${formatINR(fee.remaining)}`} />
              )
            ) : null}
          </div>

          {/* Pay online. Renders nothing when nothing is outstanding; the sheet asks the
              server for the real figure when it opens an order, so these props are labels. */}
          {fee && fee.remaining > 0 ? (
            <div className="mt-4">
              <PayRentButton amountDue={fee.remaining} period={period} />
            </div>
          ) : null}
        </GlassCard>

        {/* Updates */}
        <GlassCard>
          <GlassCardHeader title="Updates from hostel" />
          {announcements.length === 0 ? (
            <EmptyState compact icon={Megaphone} title="No updates yet" description="Announcements from the hostel will show up here." />
          ) : (
            <ul className="divide-y divide-line">
              {announcements.map((a) => (
                <li key={a.id} className="flex gap-3 py-3 first:pt-0 last:pb-0">
                  <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-navy/5 text-navy">
                    <Megaphone className="h-3.5 w-3.5" strokeWidth={1.75} />
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="text-sm font-semibold text-navy">{a.title}</div>
                    <p className="mt-0.5 line-clamp-2 text-[13px] text-charcoal/80">{a.body}</p>
                    <div className="mt-1 text-[11px] uppercase tracking-wide text-muted">{formatDate(a.created_at)}</div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </GlassCard>

        {/* Quick actions */}
        <section>
          <h2 className="mb-3 text-card-title font-semibold text-navy">Quick actions</h2>
          <QuickGrid
            tiles={[
              { href: "/student/menu", label: "Mess menu", icon: UtensilsCrossed, tone: "navy" },
              { href: "/student/complaints?new=1", label: "Raise complaint", icon: MessageSquareWarning, tone: "red" },
              { href: "/student/leave?new=1", label: "Apply leave", icon: CalendarOff, tone: "sand" },
              { href: "/student/room", label: "My room", icon: Bed, tone: "teal" },
            ]}
          />
        </section>

        {/* Hostel info row */}
        <div className="glass-card flex items-center gap-3 p-4">
          <Link href="/student/info" className="flex min-w-0 flex-1 items-center gap-3 active:opacity-70">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-teal-soft text-teal">
              <ShieldQuestion className="h-5 w-5" strokeWidth={1.75} />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-sm font-semibold text-navy">Hostel info</span>
              <span className="block truncate text-[12px] text-muted">
                {contacts?.warden_name ? `Warden · ${contacts.warden_name}` : "Warden contact & hostel rules"}
              </span>
            </span>
            {!contacts?.warden_phone ? <ChevronRight className="h-5 w-5 shrink-0 text-muted" /> : null}
          </Link>
          {contacts?.warden_phone ? (
            <a
              href={`tel:${contacts.warden_phone}`}
              aria-label={`Call warden ${contacts.warden_name ?? ""}`}
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-navy text-white active:scale-95"
            >
              <Phone className="h-4 w-4" />
            </a>
          ) : null}
        </div>
      </div>
    </MobilePage>
  );
}
