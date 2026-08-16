"use client";

import * as React from "react";
import Link from "next/link";
import { ArrowRightLeft, BedDouble, CalendarDays, LogOut, MoreVertical, Pencil, Phone, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { UserAvatar } from "@/components/ui/avatar";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { useAction } from "@/hooks/use-action";
import { fetchFreeBeds, reassignBed, vacateStudent } from "@/lib/actions/warden";
import type { FreeBed, RoomDetail } from "@/lib/queries/warden";
import type { RoomOccupancyRow } from "@/lib/types";
import { cn, formatDate, formatINR } from "@/lib/utils";
import { EditRoomSheet } from "./room-list";

type BedCard = RoomDetail["beds"][number] & { photoUrl: string | null };
type Occupant = NonNullable<BedCard["student"]>;

export function RoomDetailView({
  room,
  beds,
  writable,
}: {
  room: RoomDetail["room"];
  beds: BedCard[];
  writable: boolean;
}) {
  const occupants = beds.filter((b): b is BedCard & { student: Occupant } => !!b.student);
  const occupied = occupants.length;
  const fees = occupants.map((b) => b.student.monthly_fee).filter((n) => Number.isFinite(n) && n > 0);
  const feeRange = fees.length === 0 ? "—" : Math.min(...fees) === Math.max(...fees) ? formatINR(fees[0]) : `${formatINR(Math.min(...fees))} – ${formatINR(Math.max(...fees))}`;

  const [reassign, setReassign] = React.useState<{ bedNumber: number; student: Occupant } | null>(null);
  const [vacate, setVacate] = React.useState<{ bedNumber: number; student: Occupant } | null>(null);
  const [editing, setEditing] = React.useState(false);

  const editRow: RoomOccupancyRow = {
    room_id: room.id,
    floor_id: room.floor_id,
    floor_number: room.floor_number,
    room_number: room.room_number,
    capacity: room.capacity,
    occupied,
  };
  return (
    <div className="flex flex-col gap-4">
      {/* Summary card */}
      <GlassCard as="section" aria-label="Room details">
        <div className="mb-3 flex items-start justify-between gap-3">
          <div>
            <h2 className="text-card-title font-semibold text-navy">Room details</h2>
            <p className="mt-0.5 text-[13px] text-muted">
              {room.capacity === 1 ? "Single" : room.capacity === 2 ? "Double" : room.capacity === 3 ? "Triple" : `${room.capacity}-bed`} sharing · Floor {room.floor_number}
            </p>
          </div>
          <div className="flex items-center gap-1">
            <StatusPill tone={occupied >= room.capacity ? "navy" : occupied === 0 ? "sage" : "teal"} size="sm" label={occupied >= room.capacity ? "Full" : occupied === 0 ? "All free" : `${room.capacity - occupied} free`} />
            {writable ? (
              <button
                type="button"
                aria-label="Edit room"
                onClick={() => setEditing(true)}
                className="-mr-2 flex h-9 w-9 items-center justify-center rounded-full text-muted hover:bg-navy/5 hover:text-navy"
              >
                <Pencil className="h-4 w-4" />
              </button>
            ) : null}
          </div>
        </div>
        <dl className="grid grid-cols-3 gap-3">
          <div>
            <dt className="label-caps">Capacity</dt>
            <dd className="mt-1 text-stat-sm text-navy tabular">{room.capacity}</dd>
          </div>
          <div>
            <dt className="label-caps">Occupied</dt>
            <dd className={cn("mt-1 text-stat-sm tabular", occupied > 0 ? "text-teal" : "text-muted")}>{occupied}</dd>
          </div>
          <div className="min-w-0">
            <dt className="label-caps">Monthly fee</dt>
            <dd className="mt-1 truncate text-[17px] font-bold leading-8 text-navy tabular">{feeRange}</dd>
          </div>
        </dl>
      </GlassCard>

      <h2 className="px-1 text-title-sm text-navy">Beds &amp; assignments</h2>

      {beds.length === 0 ? (
        <GlassCard>
          <EmptyState icon={BedDouble} title="No beds in this room" description="Increase the room capacity to add beds." />
        </GlassCard>
      ) : (
        <ul className="flex flex-col gap-3">
          {beds.map((b) => {
            const s = b.student;
            return (
              <li key={b.id}>
                {s ? (
                  <OccupiedBedCard
                    bed={b}
                    student={s}
                    photoUrl={b.photoUrl}
                    writable={writable}
                    onReassign={() => setReassign({ bedNumber: b.bed_number, student: s })}
                    onVacate={() => setVacate({ bedNumber: b.bed_number, student: s })}
                  />
                ) : (
                  <FreeBedCard bedId={b.id} bedNumber={b.bed_number} writable={writable} />
                )}
              </li>
            );
          })}
        </ul>
      )}

      <ReassignSheet target={reassign} currentRoomId={room.id} onOpenChange={(o) => !o && setReassign(null)} />
      <VacateDialog target={vacate} roomNumber={room.room_number} onOpenChange={(o) => !o && setVacate(null)} />
      <EditRoomSheet room={editing ? editRow : null} onOpenChange={(o) => !o && setEditing(false)} />
    </div>
  );
}

/* ───────────────────────── bed cards ───────────────────────── */

function OccupiedBedCard({
  bed,
  student,
  photoUrl,
  writable,
  onReassign,
  onVacate,
}: {
  bed: BedCard;
  student: Occupant;
  photoUrl: string | null;
  writable: boolean;
  onReassign: () => void;
  onVacate: () => void;
}) {
  const remaining = Math.max(0, student.amount_due - student.amount_paid);
  return (
    <GlassCard as="article" className="p-4" aria-label={`Bed ${bed.bed_number} — ${student.full_name}`}>
      <div className="mb-3 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-semibold text-navy">
          <BedDouble className="h-4 w-4 text-navy/50" strokeWidth={1.75} />
          Bed {bed.bed_number}
          {student.status === "on_leave" ? <StatusPill status="on_leave" size="sm" /> : null}
        </div>
        <StatusPill status={student.fee_status} size="sm" label={student.fee_status === "partial" ? `Partial · ${formatINR(remaining)} due` : undefined} />
      </div>
      <div className="flex items-center gap-3">
        <UserAvatar name={student.full_name} src={photoUrl} size="lg" />
        <div className="min-w-0 flex-1">
          <p className="truncate text-[15px] font-semibold text-navy">{student.full_name}</p>
          <a href={`tel:${student.phone}`} className="mt-0.5 inline-flex items-center gap-1.5 text-[13px] text-muted hover:text-navy">
            <Phone className="h-3.5 w-3.5" /> {student.phone}
          </a>
          <p className="mt-0.5 flex items-center gap-1.5 text-[12px] text-muted">
            <CalendarDays className="h-3.5 w-3.5" /> Joined {formatDate(student.date_of_joining)} · {formatINR(student.monthly_fee)}/mo
          </p>
        </div>
        {writable ? (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button
                type="button"
                aria-label={`Actions for ${student.full_name}`}
                className="-mr-2 flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-muted hover:bg-navy/5 hover:text-navy"
              >
                <MoreVertical className="h-5 w-5" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-48">
              <DropdownMenuItem onSelect={onReassign}>
                <ArrowRightLeft className="h-4 w-4" /> Reassign bed
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={onVacate} className="text-red focus:text-red">
                <LogOut className="h-4 w-4" /> Vacate (checkout)
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        ) : null}
      </div>
    </GlassCard>
  );
}

function FreeBedCard({ bedId, bedNumber, writable }: { bedId: string; bedNumber: number; writable: boolean }) {
  return (
    <article
      aria-label={`Bed ${bedNumber} — free`}
      className="flex flex-col gap-3 rounded-card border border-dashed border-sage/70 bg-white/40 p-4"
    >
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-sm font-semibold text-navy">
          <BedDouble className="h-4 w-4 text-sage" strokeWidth={1.75} />
          Bed {bedNumber} — Free
        </div>
        <StatusPill status="free" size="sm" label="Available" />
      </div>
      {writable ? (
        <Button asChild variant="ghost" className="w-full border border-line bg-white/50">
          <Link href={`/warden/register?bed=${bedId}`}>
            <UserPlus className="h-4 w-4" /> Assign student
          </Link>
        </Button>
      ) : (
        <p className="text-[12px] text-muted">Registration is disabled while the hostel is read-only.</p>
      )}
    </article>
  );
}

/* ───────────────────────── reassign sheet ───────────────────────── */

function ReassignSheet({
  target,
  currentRoomId,
  onOpenChange,
}: {
  target: { bedNumber: number; student: Occupant } | null;
  currentRoomId: string;
  onOpenChange: (open: boolean) => void;
}) {
  const [bedId, setBedId] = React.useState<string | null>(null);
  // Free beds are fetched when the sheet opens (fresh, paged past the 1000-row cap) — not shipped with the page.
  const [freeBeds, setFreeBeds] = React.useState<FreeBed[] | null>(null);
  const [loadError, setLoadError] = React.useState<string | null>(null);
  const [reloadKey, setReloadKey] = React.useState(0);
  const { run, pending } = useAction(reassignBed, { onSuccess: () => onOpenChange(false) });

  React.useEffect(() => {
    if (!target) return;
    let cancelled = false;
    setBedId(null);
    setFreeBeds(null);
    setLoadError(null);
    fetchFreeBeds().then((res) => {
      if (cancelled) return;
      if (res.ok) setFreeBeds(res.data);
      else setLoadError(res.error);
    });
    return () => {
      cancelled = true;
    };
  }, [target, reloadKey]);

  const groups = React.useMemo(() => {
    const m = new Map<string, { room_number: string; floor_number: number; beds: FreeBed[] }>();
    for (const b of freeBeds ?? []) {
      const g = m.get(b.room_id) ?? { room_number: b.room_number, floor_number: b.floor_number, beds: [] };
      g.beds.push(b);
      m.set(b.room_id, g);
    }
    return [...m.entries()].map(([room_id, g]) => ({ room_id, ...g }));
  }, [freeBeds]);

  return (
    <Sheet open={!!target} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        <SheetHeader>
          <SheetTitle>Reassign bed</SheetTitle>
          <SheetDescription>
            Move <span className="font-medium text-charcoal">{target?.student.full_name}</span> from Bed {target?.bedNumber} to a free bed. The current bed is freed automatically.
          </SheetDescription>
        </SheetHeader>

        <div className="mt-4 max-h-[48dvh] overflow-y-auto pr-1">
          {loadError ? (
            <EmptyState
              icon={BedDouble}
              title="Couldn't load free beds"
              description={loadError}
              compact
              action={
                <Button variant="ghost" size="sm" onClick={() => setReloadKey((k) => k + 1)}>
                  Try again
                </Button>
              }
            />
          ) : freeBeds === null ? (
            <p className="py-6 text-center text-sm text-muted" role="status">
              Loading free beds…
            </p>
          ) : groups.length === 0 ? (
            <EmptyState icon={BedDouble} title="No free beds available" description="Every bed in the hostel is occupied." compact />
          ) : (
            <div className="flex flex-col gap-4">
              {groups.map((g) => (
                <div key={g.room_id}>
                  <div className="mb-2 flex items-center justify-between">
                    <span className="text-sm font-semibold text-navy">
                      Room {g.room_number}
                      {g.room_id === currentRoomId ? <span className="ml-1.5 text-[11px] font-medium text-muted">(this room)</span> : null}
                    </span>
                    <span className="text-[11px] text-muted">Floor {g.floor_number}</span>
                  </div>
                  <div className="grid grid-cols-4 gap-2">
                    {g.beds.map((b) => {
                      const active = b.bed_id === bedId;
                      return (
                        <button
                          key={b.bed_id}
                          type="button"
                          aria-pressed={active}
                          onClick={() => setBedId(b.bed_id)}
                          className={cn(
                            "flex h-12 items-center justify-center gap-1.5 rounded-control border text-sm font-semibold transition-all active:scale-[0.97]",
                            active ? "border-navy bg-navy text-white" : "border-sage bg-sage-soft/60 text-navy hover:bg-sage-soft",
                          )}
                        >
                          <BedDouble className="h-4 w-4" strokeWidth={1.75} /> {b.bed_number}
                        </button>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <Button
          size="xl"
          className="mt-5"
          disabled={!bedId || !target}
          loading={pending}
          onClick={() => target && bedId && run({ studentId: target.student.id, bedId })}
        >
          Move to selected bed
        </Button>
      </SheetContent>
    </Sheet>
  );
}

/* ───────────────────────── vacate confirm ───────────────────────── */

function VacateDialog({
  target,
  roomNumber,
  onOpenChange,
}: {
  target: { bedNumber: number; student: Occupant } | null;
  roomNumber: string;
  onOpenChange: (open: boolean) => void;
}) {
  const { run, pending } = useAction(vacateStudent, { onSuccess: () => onOpenChange(false) });
  return (
    <Dialog open={!!target} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <div className="mb-1 flex h-11 w-11 items-center justify-center rounded-full bg-red-soft text-red">
            <LogOut className="h-5 w-5" />
          </div>
          <DialogTitle>Vacate {target?.student.full_name}?</DialogTitle>
          <DialogDescription>
            This checks the student out of Room {roomNumber} · Bed {target?.bedNumber}. The bed becomes free and their login is deactivated. Fee history is kept.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="mt-2 gap-2">
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button variant="destructive" loading={pending} onClick={() => target && run({ studentId: target.student.id })}>
            Vacate student
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
