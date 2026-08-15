import { notFound } from "next/navigation";
import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getFreeBeds, getRoomDetail } from "@/lib/queries/warden";
import { RoomDetailView } from "@/components/warden/room-detail";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** WD-4 · Room detail — one card per bed with occupant, fee status and actions. */
export default async function WardenRoomDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { ctx } = await requireHostelContext("warden");
  const { id } = await params;
  if (!UUID.test(id)) notFound();

  const supabase = await createClient();
  const [detail, freeBeds] = await Promise.all([getRoomDetail(supabase, ctx.hostel.id, id), getFreeBeds(supabase, ctx.hostel.id)]);
  if (!detail) notFound();

  // Signed photo URLs (null when the storage key is not configured → initials avatar)
  const photoUrls = await Promise.all(detail.beds.map((b) => (b.student?.photo_url ? signedUrl("student-docs", b.student.photo_url) : Promise.resolve(null))));
  const beds = detail.beds.map((b, i) => ({ ...b, photoUrl: photoUrls[i] }));

  return (
    <MobilePage role="warden" title={`Room ${detail.room.room_number} · Floor ${detail.room.floor_number}`} backHref="/warden/rooms">
      <RoomDetailView room={detail.room} beds={beds} freeBeds={freeBeds} writable={ctx.writable} />
    </MobilePage>
  );
}
