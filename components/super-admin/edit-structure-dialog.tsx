"use client";

import * as React from "react";
import { Info, Layers, Pencil } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Field, FormGrid } from "@/components/shared/field";
import { useAction } from "@/hooks/use-action";
import { updateHostelStructure } from "@/lib/actions/super-admin";
import { formatNumber } from "@/lib/utils";
import { NumberStepper } from "./number-stepper";

/**
 * SA-4 "Edit structure" — Hard rule §4.2: only the Super Admin changes floor / room counts.
 * Grow-only: the dialog clamps to the current values as minimums; the server re-checks.
 */
export function EditStructureButton({
  hostelId,
  hostelName,
  floors,
  rooms,
  bedsPerRoom,
  size = "sm",
  variant = "ghost",
}: {
  hostelId: string;
  hostelName: string;
  floors: number;
  rooms: number;
  bedsPerRoom: number;
  size?: ButtonProps["size"];
  variant?: ButtonProps["variant"];
}) {
  const [open, setOpen] = React.useState(false);
  const [nextFloors, setNextFloors] = React.useState(floors);
  const [nextRooms, setNextRooms] = React.useState(rooms);
  const [errors, setErrors] = React.useState<{ floors?: string; rooms?: string }>({});

  React.useEffect(() => {
    if (open) {
      setNextFloors(floors);
      setNextRooms(rooms);
      setErrors({});
    }
  }, [open, floors, rooms]);

  const { run, pending } = useAction(updateHostelStructure, { onSuccess: () => setOpen(false) });

  const f = Number.isFinite(nextFloors) ? nextFloors : floors;
  const r = Number.isFinite(nextRooms) ? nextRooms : rooms;
  const addedRooms = Math.max(0, r - rooms);
  const unchanged = f === floors && r === rooms;

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const next: typeof errors = {};
    if (!Number.isInteger(f) || f < floors) next.floors = `Floors can only be increased (currently ${floors})`;
    if (!Number.isInteger(r) || r < rooms) next.rooms = `Rooms can only be increased (currently ${rooms})`;
    else if (r < f) next.rooms = "Add at least one room per floor";
    setErrors(next);
    if (Object.keys(next).length || unchanged) return;
    void run({ hostelId, floors: f, rooms: r });
  };

  return (
    <>
      <Button type="button" variant={variant} size={size} onClick={() => setOpen(true)}>
        <Pencil />
        Edit structure
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <form onSubmit={submit} className="contents">
            <DialogHeader>
              <div className="mb-1 flex h-11 w-11 items-center justify-center rounded-full bg-navy/5 text-navy">
                <Layers className="h-5 w-5" />
              </div>
              <DialogTitle>Edit structure</DialogTitle>
              <DialogDescription>
                <span className="font-medium text-charcoal">{hostelName}</span> — currently {formatNumber(floors)} floor{floors === 1 ? "" : "s"} and{" "}
                {formatNumber(rooms)} rooms. Only the Super Admin can change these counts.
              </DialogDescription>
            </DialogHeader>

            <FormGrid>
              <Field label="Number of floors" htmlFor="struct-floors" required error={errors.floors} hint={`Minimum ${floors}`}>
                <NumberStepper id="struct-floors" value={nextFloors} onChange={setNextFloors} min={floors} max={50} disabled={pending} />
              </Field>
              <Field label="Number of rooms" htmlFor="struct-rooms" required error={errors.rooms} hint={`Minimum ${rooms}`}>
                <NumberStepper id="struct-rooms" value={nextRooms} onChange={setNextRooms} min={rooms} max={5000} disabled={pending} />
              </Field>
            </FormGrid>

            <div className="flex items-start gap-2.5 rounded-control bg-navy/5 px-3.5 py-3 text-[13px] text-charcoal">
              <Info className="mt-0.5 h-4 w-4 shrink-0 text-navy/70" />
              <p>
                Shrinking is not supported — floors and rooms can only be added. New rooms are numbered automatically and get {bedsPerRoom} bed
                {bedsPerRoom === 1 ? "" : "s"} each
                {addedRooms > 0 ? (
                  <>
                    {" "}
                    (<span className="font-semibold text-navy">+{formatNumber(addedRooms)}</span> room{addedRooms === 1 ? "" : "s"},{" "}
                    <span className="font-semibold text-navy">+{formatNumber(addedRooms * bedsPerRoom)}</span> beds)
                  </>
                ) : null}
                . Existing rooms, beds and students are untouched.
              </p>
            </div>

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={() => setOpen(false)} disabled={pending}>
                Cancel
              </Button>
              <Button type="submit" loading={pending} disabled={unchanged}>
                Save structure
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
