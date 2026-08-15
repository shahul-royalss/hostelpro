import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getFloors, getRoomOccupancy } from "@/lib/queries/warden";
import { RoomList } from "@/components/warden/room-list";
import { formatNumber } from "@/lib/utils";

export const dynamic = "force-dynamic";

/** WD-3 · Rooms & beds — floor-wise room cards with bed dots. */
export default async function WardenRoomsPage() {
  const { ctx } = await requireHostelContext("warden");
  const supabase = await createClient();
  const [floors, rooms] = await Promise.all([getFloors(supabase, ctx.hostel.id), getRoomOccupancy(supabase, ctx.hostel.id)]);

  const totalBeds = rooms.reduce((s, r) => s + r.capacity, 0);
  const occupied = rooms.reduce((s, r) => s + r.occupied, 0);

  return (
    <MobilePage
      role="warden"
      title="Rooms"
      subtitle={`${formatNumber(rooms.length)} rooms · ${formatNumber(occupied)}/${formatNumber(totalBeds)} beds occupied`}
      backHref="/warden"
    >
      <RoomList floors={floors} rooms={rooms} writable={ctx.writable} />
    </MobilePage>
  );
}
