import { BedDouble, Layers, Phone, Users } from "lucide-react";
import { MobilePage } from "@/components/shell/role-shells";
import { GlassCard } from "@/components/shared/glass-card";
import { BedDots } from "@/components/shared/bed-dots";
import { EmptyState } from "@/components/shared/empty-state";
import { UserAvatar } from "@/components/ui/avatar";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getMyRoommates, getMyStudent } from "@/lib/queries/student";

export default async function StudentRoomPage() {
  const { user } = await requireHostelContext("student");
  const supabase = await createClient();
  const [student, roommates] = await Promise.all([getMyStudent(supabase, user.id), getMyRoommates(supabase)]);

  const room = student?.room ?? null;
  const myBed = student?.bed?.bed_number ?? null;
  const occupied = roommates.length + (student?.bed_id ? 1 : 0);

  return (
    <MobilePage role="student" title="My room">
      <div className="flex flex-col gap-4">
        {!room ? (
          <GlassCard>
            <EmptyState icon={BedDouble} title="No room assigned yet" description="Your warden will assign a room and bed to you." />
          </GlassCard>
        ) : (
          <GlassCard strong>
            <div className="flex items-start justify-between gap-3">
              <div>
                <div className="label-caps">My room</div>
                <div className="mt-0.5 text-stat-sm text-navy">Room {room.room_number}</div>
              </div>
              {myBed ? (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-navy px-3 py-1.5 text-[12px] font-semibold text-white">
                  <BedDouble className="h-3.5 w-3.5" /> My bed: {myBed}
                </span>
              ) : null}
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-[13px] text-muted">
              {room.floor ? (
                <span className="inline-flex items-center gap-1.5">
                  <Layers className="h-3.5 w-3.5" /> Floor {room.floor.floor_number}
                </span>
              ) : null}
              <span className="inline-flex items-center gap-1.5">
                <Users className="h-3.5 w-3.5" /> Capacity: {room.capacity}
              </span>
            </div>
            <div className="mt-4 flex items-center justify-between gap-3 rounded-control bg-white/60 px-3.5 py-3">
              <BedDots capacity={room.capacity} occupied={Math.min(occupied, room.capacity)} />
              <span className="text-[12px] text-muted">
                {occupied}/{room.capacity} occupied{myBed ? ` · You're on bed ${myBed}` : ""}
              </span>
            </div>
          </GlassCard>
        )}

        <section>
          <h2 className="mb-3 text-card-title font-semibold text-navy">Roommates</h2>
          {roommates.length === 0 ? (
            <GlassCard>
              <EmptyState compact icon={Users} title="No roommates yet" description="You have the room to yourself for now." />
            </GlassCard>
          ) : (
            <ul className="flex flex-col gap-3">
              {roommates.map((r) => (
                <li key={r.student_id} className="glass-card flex items-center gap-3 p-4">
                  <UserAvatar name={r.full_name} size="md" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-semibold text-navy">{r.full_name}</div>
                    <div className="mt-0.5 text-[12px] text-muted">
                      {r.bed_number ? `Bed ${r.bed_number} · ` : ""}
                      {r.phone}
                    </div>
                  </div>
                  <a
                    href={`tel:${r.phone}`}
                    aria-label={`Call ${r.full_name}`}
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-navy/5 text-navy transition-colors hover:bg-navy hover:text-white active:scale-95"
                  >
                    <Phone className="h-4 w-4" />
                  </a>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </MobilePage>
  );
}
