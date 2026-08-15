import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getFloors, getFreeBeds, getRoomOccupancy } from "@/lib/queries/warden";
import { RegisterStudentForm } from "@/components/warden/register-form";

export const dynamic = "force-dynamic";

export default async function RegisterStudentPage({ searchParams }: { searchParams: Promise<{ bed?: string }> }) {
  const { ctx } = await requireHostelContext("warden");
  const { bed } = await searchParams;
  const supabase = await createClient();
  const [floors, rooms, freeBeds, { data: feeRow }] = await Promise.all([
    getFloors(supabase, ctx.hostel.id),
    getRoomOccupancy(supabase, ctx.hostel.id),
    getFreeBeds(supabase, ctx.hostel.id),
    // most recent student's fee as a sensible default
    supabase.from("students").select("monthly_fee").eq("hostel_id", ctx.hostel.id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
  ]);
  const defaultFee = feeRow ? Number((feeRow as { monthly_fee: number }).monthly_fee) || undefined : undefined;

  return (
    <MobilePage role="warden" title="New student" backHref="/warden" hideNav>
      <RegisterStudentForm
        floors={floors}
        rooms={rooms}
        freeBeds={freeBeds}
        initialBedId={typeof bed === "string" ? bed : undefined}
        defaultFee={defaultFee}
        writable={ctx.writable}
      />
    </MobilePage>
  );
}
