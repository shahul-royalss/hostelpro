import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getFloors, getFreeBeds, getRoomOccupancy } from "@/lib/queries/warden";
import { RegisterStudentForm } from "@/components/warden/register-form";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function RegisterStudentPage({ searchParams }: { searchParams: Promise<{ bed?: string }> }) {
  const { ctx } = await requireHostelContext("warden");
  const { bed } = await searchParams;
  const supabase = await createClient();
  const bedId = typeof bed === "string" && UUID.test(bed) ? bed : undefined;
  const [floors, rooms, { data: feeRow }, { data: bedRow }] = await Promise.all([
    getFloors(supabase, ctx.hostel.id),
    getRoomOccupancy(supabase, ctx.hostel.id),
    // most recent student's fee as a sensible default
    supabase.from("students").select("monthly_fee").eq("hostel_id", ctx.hostel.id).order("created_at", { ascending: false }).limit(1).maybeSingle(),
    // ?bed=<id> deep link (from a free-bed card): resolve its room so step 4 can preselect it
    bedId ? supabase.from("beds").select("room_id").eq("id", bedId).eq("hostel_id", ctx.hostel.id).is("student_id", null).maybeSingle() : Promise.resolve({ data: null }),
  ]);
  const defaultFee = feeRow ? Number((feeRow as { monthly_fee: number }).monthly_fee) || undefined : undefined;
  const preRoomId = (bedRow as { room_id: string } | null)?.room_id ?? null;
  // Free beds are loaded per room (fetchFreeBeds action) when the warden taps a room —
  // never the whole hostel — so only the deep-linked room is preloaded here.
  const initialFreeBeds = preRoomId ? await getFreeBeds(supabase, ctx.hostel.id, preRoomId) : [];

  return (
    <MobilePage role="warden" title="New student" backHref="/warden" hideNav>
      <RegisterStudentForm
        floors={floors}
        rooms={rooms}
        initialFreeBeds={initialFreeBeds}
        initialBedId={bedId}
        defaultFee={defaultFee}
        writable={ctx.writable}
      />
    </MobilePage>
  );
}
