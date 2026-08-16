"use client";

import * as React from "react";
import { addYears, parseISO, isValid } from "date-fns";
import { CalendarPlus, RefreshCw } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Field, FormGrid } from "@/components/shared/field";
import { useAction } from "@/hooks/use-action";
import { renewSubscription } from "@/lib/actions/super-admin";
import { formatDate, toISODate } from "@/lib/utils";

export interface RenewTarget {
  hostelId: string;
  hostelName: string;
  currentEnd: string | null;
  defaultAmount?: number | null;
}

function defaultNewEnd(currentEnd: string | null): string {
  const base = currentEnd ? parseISO(currentEnd) : new Date();
  const from = isValid(base) && base > new Date() ? base : new Date();
  return toISODate(addYears(from, 1));
}

/**
 * Renew subscription dialog (SA-1 / SA-3 / SA-4). Inserts a new subscription
 * period through sa_renew_subscription — the DB rejects end dates that don't extend the current one.
 */
export function RenewDialog({
  target,
  open,
  onOpenChange,
  onDone,
}: {
  target: RenewTarget | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onDone?: () => void;
}) {
  const [endDate, setEndDate] = React.useState("");
  const [amount, setAmount] = React.useState("");
  const [notes, setNotes] = React.useState("");
  const [errors, setErrors] = React.useState<{ endDate?: string; amount?: string }>({});

  React.useEffect(() => {
    if (open && target) {
      setEndDate(defaultNewEnd(target.currentEnd));
      setAmount(target.defaultAmount != null ? String(target.defaultAmount) : "");
      setNotes("");
      setErrors({});
    }
  }, [open, target]);

  const { run, pending } = useAction(renewSubscription, {
    onSuccess: () => {
      onOpenChange(false);
      onDone?.();
    },
  });

  if (!target) return null;
  const minDate = target.currentEnd && target.currentEnd > toISODate() ? target.currentEnd : toISODate();

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const next: typeof errors = {};
    if (!endDate) next.endDate = "Pick the new end date";
    else if (endDate <= minDate) next.endDate = `Must be after ${formatDate(minDate)}`;
    const amt = Number(amount);
    if (amount === "" || !Number.isFinite(amt) || amt < 0) next.amount = "Enter the renewal amount";
    setErrors(next);
    if (Object.keys(next).length) return;
    void run({ hostelId: target.hostelId, newEndDate: endDate, amount: amt, notes });
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <form onSubmit={submit} className="contents">
          <DialogHeader>
            <div className="mb-1 flex h-11 w-11 items-center justify-center rounded-full bg-navy/5 text-navy">
              <CalendarPlus className="h-5 w-5" />
            </div>
            <DialogTitle>Renew subscription</DialogTitle>
            <DialogDescription>
              <span className="font-medium text-charcoal">{target.hostelName}</span>
              {target.currentEnd ? (
                target.currentEnd < toISODate() ? (
                  <>
                    {" "}
                    — previous period ended {formatDate(target.currentEnd)}. The new period starts today.
                  </>
                ) : (
                  <>
                    {" "}
                    — current period ends {formatDate(target.currentEnd)}. The new period starts from that date.
                  </>
                )
              ) : (
                " — no subscription on record yet."
              )}
            </DialogDescription>
          </DialogHeader>

          <FormGrid>
            <Field label="New end date" htmlFor="renew-end" required error={errors.endDate}>
              <Input
                id="renew-end"
                type="date"
                min={minDate}
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                aria-invalid={!!errors.endDate}
              />
            </Field>
            <Field label="Amount (₹)" htmlFor="renew-amount" required error={errors.amount}>
              <Input
                id="renew-amount"
                type="number"
                inputMode="decimal"
                min={0}
                step="1"
                placeholder="e.g. 24000"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                aria-invalid={!!errors.amount}
              />
            </Field>
          </FormGrid>
          <Field label="Notes" htmlFor="renew-notes" hint="Optional — payment reference, plan, etc.">
            <Textarea id="renew-notes" rows={2} className="min-h-[64px]" value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={500} />
          </Field>

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
              Cancel
            </Button>
            <Button type="submit" loading={pending}>
              <RefreshCw />
              Renew
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Self-contained "Renew" button that owns its dialog — drop into any table row / header. */
export function RenewButton({
  target,
  children = "Renew",
  ...btn
}: { target: RenewTarget } & Omit<ButtonProps, "onClick">) {
  const [open, setOpen] = React.useState(false);
  return (
    <>
      <Button
        {...btn}
        onClick={(e) => {
          e.stopPropagation();
          setOpen(true);
        }}
      >
        {children}
      </Button>
      <RenewDialog target={target} open={open} onOpenChange={setOpen} />
    </>
  );
}
