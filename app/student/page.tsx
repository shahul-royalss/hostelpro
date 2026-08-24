import Link from "next/link";
import { PayRentButton } from "@/components/payments/pay-rent-button";
import { BadgeCheck, Bed, CalendarOff, Megaphone, MessageSquareWarning, Phone, ShieldQuestion, Wallet } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { HeroStat, heroAmount } from "@/components/dashboard/hero-stat";
import { Verdict } from "@/components/dashboard/delta";
import { Meter } from "@/components/dashboard/meter";
import { InsetEmpty, InsetList, InsetRow, ListSectionHeader } from "@/components/dashboard/inset-list";
import { monthDeadline, monthProgress } from "@/components/dashboard/period";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getAnnouncements, getHostelContacts, getMyFeeForPeriod, getMyStudent, summariseFee } from "@/lib/queries/student";
import { firstName, formatDate, formatINR, percent, toPeriodMonth } from "@/lib/utils";

/**
 * ST-1 · Student home.
 *
 * A student opens this to answer one question: what do I owe, and by when. That
 * answer is now the largest thing on the screen instead of a 12px pill inside a
 * white box inside a card — which was also a material nested in a material
 * (docs/design-system.md §3 forbids it).
 *
 * The old 2×2 quick grid is gone: three of its four tiles (Mess menu, Raise
 * complaint, My room) were already in the bottom nav.
 */
export default async function StudentHomePage() {
  const { user, ctx } = await requireHostelContext("student");
  const supabase = await createClient();
  const period = toPeriodMonth();

  const [student, announcements, contacts] = await Promise.all([
    getMyStudent(supabase, user.id),
    getAnnouncements(supabase, ctx.hostel.id, 3),
    getHostelContacts(supabase),
  ]);
  const feeRow = student ? await getMyFeeForPeriod(supabase, student.id, period) : null;
  const fee = student ? summariseFee(feeRow, Number(student.monthly_fee)) : null;

  const room = student?.room;
  const roomLine = room
    ? [`Room ${room.room_number}`, student?.bed ? `Bed ${student.bed.bed_number}` : null, room.floor ? `Floor ${room.floor.floor_number}` : null]
        .filter(Boolean)
        .join(" · ")
    : null;

  const progress = monthProgress(period);
  const deadline = monthDeadline(progress);
  const paidShare = fee && fee.due > 0 ? percent(fee.paid, fee.due) : 100;
  const owed = fee ? heroAmount(fee.remaining) : null;

  return (
    <MobilePage role="student" title={`Hi, ${firstName(user.full_name)}`} subtitle={ctx.hostel.name}>
      {/* The app bar already carries the name and the hostel — the hero starts
          with the number, not a repeat of the header. */}
      <h1 className="sr-only">Student home</h1>

      <div className="flex flex-col gap-6">
        {!fee ? (
          <HeroStat
            eyebrow="Your account"
            value="Not linked"
            icon={ShieldQuestion}
            tone="sand"
            verdict={<Verdict verdict="unknown">No student record is attached to this login</Verdict>}
            caption="Ask your warden to link your registration, and your room and fees will show up here."
          />
        ) : fee.remaining > 0 ? (
          <>
            <HeroStat
              eyebrow={`Due for ${progress.name}`}
              value={owed?.display}
              icon={Wallet}
              tone={progress.past ? "red" : "sand"}
              verdict={
                <Verdict verdict={progress.past ? "bad" : "unknown"}>
                  {progress.past ? `Overdue — ${deadline.toLowerCase()}` : deadline}
                </Verdict>
              }
              meter={fee.paid > 0 ? <Meter percent={paidShare} tone="sand" label={`${paidShare}% of this month's fee paid`} /> : undefined}
              caption={
                fee.paid > 0
                  ? `${formatINR(fee.paid)} of ${formatINR(fee.due)} already paid — ${formatINR(fee.remaining)} to go`
                  : `Monthly fee ${formatINR(fee.due)} · pay online below or at the warden's desk`
              }
            />
            {/* The one primary action on this screen. Renders nothing when there
                is nothing outstanding, and asks the server for the real figure. */}
            <PayRentButton amountDue={fee.remaining} period={period} />
          </>
        ) : (
          <HeroStat
            eyebrow={`${progress.name} fee`}
            value="Paid"
            icon={BadgeCheck}
            tone="teal"
            verdict={<Verdict verdict="good">Nothing outstanding</Verdict>}
            caption={
              fee.paid > 0
                ? `${formatINR(fee.paid)} received${feeRow?.paid_on ? ` on ${formatDate(feeRow.paid_on, "d MMM")}` : ""} — thank you.`
                : "No fee is due from you this month."
            }
          />
        )}

        <section>
          <ListSectionHeader title="My stay" />
          <InsetList aria-label="My stay">
            <InsetRow
              href="/student/room"
              icon={Bed}
              tone="navy"
              title={roomLine ?? "No room allotted yet"}
              subtitle={roomLine ? "Roommates and room details" : "Your warden will allot a bed shortly"}
            />
            <InsetRow
              href="/student/info"
              icon={ShieldQuestion}
              tone="teal"
              title="Hostel info & rules"
              subtitle={contacts?.warden_name ? `Warden · ${contacts.warden_name}` : "Warden contact and house rules"}
            />
          </InsetList>
          {contacts?.warden_phone ? (
            <a
              href={`tel:${contacts.warden_phone}`}
              className="mt-3 flex min-h-[44px] items-center justify-center gap-2 rounded-control-lg squircle border border-separator bg-fill-quaternary px-4 text-subhead font-medium text-label transition-colors duration-quick ease-sys hover:bg-fill-tertiary active:bg-fill-secondary"
            >
              <Phone className="h-4 w-4 text-label-secondary" strokeWidth={1.9} aria-hidden />
              Call the warden{contacts.warden_name ? `, ${firstName(contacts.warden_name)}` : ""}
            </a>
          ) : null}
        </section>

        <section>
          <ListSectionHeader title="Raise a request" />
          {/* Only destinations the bottom nav does not already offer, or that open
              a form the nav cannot (?new=1). Mess menu and My room were dropped —
              both are one tap away in the nav bar. */}
          <InsetList aria-label="Raise a request">
            <InsetRow href="/student/leave?new=1" icon={CalendarOff} tone="sand" title="Apply for leave" subtitle="Tell the warden when you are away" />
            <InsetRow href="/student/complaints?new=1" icon={MessageSquareWarning} tone="red" title="Raise a complaint" subtitle="Food, cleaning, wifi, maintenance" />
          </InsetList>
        </section>

        <section>
          <ListSectionHeader title="Updates from the hostel" />
          <InsetList aria-label="Updates from the hostel">
            {announcements.length === 0 ? (
              <InsetEmpty
                icon={Megaphone}
                title="No updates yet"
                hint="Notices about the mess, water, maintenance and fees will appear here."
              />
            ) : (
              announcements.map((a) => (
                <InsetRow key={a.id} icon={Megaphone} title={a.title} subtitle={a.body} valueCaption={formatDate(a.created_at, "d MMM")} />
              ))
            )}
          </InsetList>
        </section>

        <p className="px-1 pb-2 text-caption-1 text-label-secondary">
          Something else?{" "}
          <Link href="/student/profile" className="font-medium text-ink-navy underline underline-offset-2">
            Your profile
          </Link>{" "}
          has your documents, password and login details.
        </p>
      </div>
    </MobilePage>
  );
}
