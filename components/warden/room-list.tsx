"use client";

import * as React from "react";
import Link from "next/link";
import { BedDouble, ChevronRight, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Field } from "@/components/shared/field";
import { SegmentedPills } from "@/components/shared/segmented";
import { StatusPill } from "@/components/shared/status-pill";
import { BedDots } from "@/components/shared/bed-dots";
import { EmptyState } from "@/components/shared/empty-state";
import { useAction } from "@/hooks/use-action";
import { updateRoom } from "@/lib/actions/warden";
import type { FloorRow, RoomOccupancyRow } from "@/lib/types";
import { cn } from "@/lib/utils";

export function RoomList({ floors, rooms, writable }: { floors: FloorRow[]; rooms: RoomOccupancyRow[]; writable: boolean }) {
  const [floor, setFloor] = React.useState<string>("all");
  const [editing, setEditing] = React.useState<RoomOccupancyRow | null>(null);

  const visible = floor === "all" ? rooms : rooms.filter((r) => String(r.floor_number) === floor);
  const options = [
    { value: "all", label: "All", count: rooms.length },
    ...floors.map((f) => ({ value: String(f.floor_number), label: `Floor ${f.floor_number}` })),
  ];

  return (
    <div className="flex flex-col gap-4">
      <SegmentedPills ariaLabel="Filter by floor" options={options} value={floor} onChange={setFloor} size="sm" className="-mx-4 px-4" />

      {visible.length === 0 ? (
        <div className="glass-card">
          <EmptyState icon={BedDouble} title="No rooms on this floor" />
        </div>
      ) : (
        <ul className="flex flex-col gap-3">
          {visible.map((r) => {
            const full = r.occupied >= r.capacity;
            const empty = r.occupied === 0;
            return (
              <li key={r.room_id} className="glass-card relative flex items-center gap-3 p-4 transition-colors hover:bg-white/80">
                <Link href={`/warden/rooms/${r.room_id}`} className="absolute inset-0 rounded-card" aria-label={`Open room ${r.room_number}`} />
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-navy/5 text-navy">
                  <BedDouble className="h-5 w-5" strokeWidth={1.75} />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-[17px] font-bold text-navy">Room {r.room_number}</span>
                    {full ? <StatusPill tone="navy" size="sm" label="Full" /> : empty ? <StatusPill tone="sage" size="sm" label="All free" /> : null}
                  </div>
                  <div className="mt-0.5 text-[12px] text-muted">Floor {r.floor_number}</div>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1.5">
                  <BedDots capacity={r.capacity} occupied={r.occupied} size="sm" />
                  <span className={cn("text-[12px] font-medium tabular", full ? "text-navy" : empty ? "text-sage" : "text-muted")}>
                    {r.occupied}/{r.capacity} occupied
                  </span>
                </div>
                {writable ? (
                  <button
                    type="button"
                    aria-label={`Edit room ${r.room_number}`}
                    onClick={() => setEditing(r)}
                    className="relative z-10 -mr-2 flex h-11 w-11 items-center justify-center rounded-full text-muted hover:bg-navy/5 hover:text-navy"
                  >
                    <Pencil className="h-4 w-4" />
                  </button>
                ) : (
                  <ChevronRight className="h-4 w-4 shrink-0 text-muted/70" />
                )}
              </li>
            );
          })}
        </ul>
      )}

      <EditRoomSheet room={editing} onOpenChange={(o) => !o && setEditing(null)} />
    </div>
  );
}

export function EditRoomSheet({ room, onOpenChange }: { room: RoomOccupancyRow | null; onOpenChange: (open: boolean) => void }) {
  const [roomNumber, setRoomNumber] = React.useState("");
  const [capacity, setCapacity] = React.useState(3);
  const { run, pending } = useAction(updateRoom, { onSuccess: () => onOpenChange(false) });

  React.useEffect(() => {
    if (room) {
      setRoomNumber(room.room_number);
      setCapacity(room.capacity);
    }
  }, [room]);

  return (
    <Sheet open={!!room} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        <SheetHeader>
          <SheetTitle>Edit room</SheetTitle>
          <SheetDescription>Change the room number or how many beds it has. Capacity can&apos;t go below the occupied beds.</SheetDescription>
        </SheetHeader>
        <form
          className="mt-4 flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            if (!room) return;
            run({ roomId: room.room_id, roomNumber, capacity });
          }}
        >
          <Field label="Room number" htmlFor="roomNumber" required>
            <Input id="roomNumber" value={roomNumber} onChange={(e) => setRoomNumber(e.target.value)} maxLength={12} required />
          </Field>
          <Field label="Capacity (beds)" htmlFor="capacity" required hint={room ? `${room.occupied} currently occupied` : undefined}>
            <div className="flex items-center gap-2">
              <Button type="button" variant="secondary" size="icon" aria-label="Fewer beds" onClick={() => setCapacity((c) => Math.max(1, c - 1))} disabled={capacity <= 1}>
                −
              </Button>
              <Input
                id="capacity"
                type="number"
                inputMode="numeric"
                min={1}
                max={12}
                value={capacity}
                onChange={(e) => setCapacity(Math.max(1, Math.min(12, Number(e.target.value) || 1)))}
                className="text-center tabular"
              />
              <Button type="button" variant="secondary" size="icon" aria-label="More beds" onClick={() => setCapacity((c) => Math.min(12, c + 1))} disabled={capacity >= 12}>
                +
              </Button>
            </div>
          </Field>
          <Button type="submit" size="xl" loading={pending}>
            Save changes
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
