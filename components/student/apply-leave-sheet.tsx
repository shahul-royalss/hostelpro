"use client";

import * as React from "react";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/shared/field";
import { useAction } from "@/hooks/use-action";
import { applyLeave } from "@/lib/actions/student";
import { toISODate } from "@/lib/utils";

/** Leave request bottom sheet: From, To, Reason → "Send request". */
export function ApplyLeaveSheet({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const today = React.useMemo(() => toISODate(), []);
  const [fromDate, setFromDate] = React.useState(today);
  const [toDate, setToDate] = React.useState(today);
  const [reason, setReason] = React.useState("");
  const [errors, setErrors] = React.useState<Record<string, string[]>>({});

  const { run, pending } = useAction(applyLeave, {
    onSuccess: () => {
      setFromDate(today);
      setToDate(today);
      setReason("");
      setErrors({});
      onOpenChange(false);
    },
  });

  const nights = React.useMemo(() => {
    const a = new Date(fromDate);
    const b = new Date(toDate);
    if (Number.isNaN(a.getTime()) || Number.isNaN(b.getTime())) return null;
    const d = Math.round((b.getTime() - a.getTime()) / 86_400_000) + 1;
    return d > 0 ? d : null;
  }, [fromDate, toDate]);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setErrors({});
    const res = await run({ fromDate, toDate, reason });
    if (!res.ok && res.fieldErrors) setErrors(res.fieldErrors);
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        <SheetHeader>
          <SheetTitle>Apply for leave</SheetTitle>
          <SheetDescription>Your warden will approve or reject the request.</SheetDescription>
        </SheetHeader>

        <form onSubmit={onSubmit} className="mt-4 flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3">
            <Field label="From" htmlFor="leave-from" required error={errors.fromDate?.[0]}>
              <Input
                id="leave-from"
                type="date"
                value={fromDate}
                min={today}
                onChange={(e) => {
                  setFromDate(e.target.value);
                  if (toDate < e.target.value) setToDate(e.target.value);
                }}
                required
                aria-invalid={!!errors.fromDate}
              />
            </Field>
            <Field label="To" htmlFor="leave-to" required error={errors.toDate?.[0]}>
              <Input
                id="leave-to"
                type="date"
                value={toDate}
                min={fromDate || today}
                onChange={(e) => setToDate(e.target.value)}
                required
                aria-invalid={!!errors.toDate}
              />
            </Field>
          </div>
          {nights ? (
            <p className="-mt-2 text-[12px] text-muted">
              {nights} {nights === 1 ? "day" : "days"} away from the hostel
            </p>
          ) : null}

          <Field label="Reason" htmlFor="leave-reason" required error={errors.reason?.[0]} hint="Where you're going and why — keep it short.">
            <Textarea
              id="leave-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. Going home for a family function"
              maxLength={500}
              rows={3}
              required
              aria-invalid={!!errors.reason}
            />
          </Field>

          <Button type="submit" size="xl" loading={pending} className="mt-1">
            Send request
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
