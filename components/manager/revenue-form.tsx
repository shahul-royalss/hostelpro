"use client";

import * as React from "react";
import { Save } from "lucide-react";
import { createRevenue, updateRevenue } from "@/lib/actions/manager";
import { useAction } from "@/hooks/use-action";
import { REVENUE_SOURCES, type RevenueRow, type RevenueSource } from "@/lib/types";
import { cn, titleCase, toISODate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Field } from "@/components/shared/field";

type FieldErrors = Record<string, string[] | undefined>;

/** Add / edit revenue form (MG-3) — same pattern as expenses, no receipt. */
export function RevenueForm({
  mode,
  initial,
  disabled,
  onDone,
}: {
  mode: "create" | "edit";
  initial?: RevenueRow;
  disabled?: boolean;
  onDone?: () => void;
}) {
  const formRef = React.useRef<HTMLFormElement>(null);
  const [source, setSource] = React.useState<RevenueSource>(initial?.source ?? "fees");
  const [errors, setErrors] = React.useState<FieldErrors>({});
  const [defaultDate] = React.useState(() => initial?.date ?? toISODate());

  const create = useAction(createRevenue, {
    onSuccess: () => {
      setErrors({});
      formRef.current?.reset();
      setSource("fees");
      onDone?.();
    },
  });
  const update = useAction(updateRevenue, {
    onSuccess: () => {
      setErrors({});
      onDone?.();
    },
  });
  const pending = create.pending || update.pending;
  const busy = pending || disabled;

  const onSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const payload = {
      date: String(fd.get("date") ?? ""),
      source,
      amount: Number(fd.get("amount") ?? NaN),
      note: String(fd.get("note") ?? ""),
    };
    const res = mode === "create" ? await create.run(payload) : await update.run({ ...payload, id: initial?.id ?? "" });
    if (!res.ok && res.fieldErrors) setErrors(res.fieldErrors);
  };

  return (
    <form
      ref={formRef}
      onSubmit={onSubmit}
      className={cn("grid grid-cols-1 gap-4 md:grid-cols-2", mode === "create" && "lg:grid-cols-[1fr_1fr_1fr_1.6fr_auto]")}
      noValidate
    >
      <Field label="Date" htmlFor={`${mode}-rev-date`} error={errors.date?.[0]} required>
        <Input id={`${mode}-rev-date`} name="date" type="date" defaultValue={defaultDate} max={toISODate()} required disabled={busy} />
      </Field>
      <Field label="Source" htmlFor={`${mode}-rev-source`} error={errors.source?.[0]} required>
        <Select value={source} onValueChange={(v) => setSource(v as RevenueSource)} disabled={busy}>
          <SelectTrigger id={`${mode}-rev-source`} aria-label="Source">
            <SelectValue placeholder="Select source" />
          </SelectTrigger>
          <SelectContent>
            {REVENUE_SOURCES.map((s) => (
              <SelectItem key={s} value={s}>
                {titleCase(s)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
      <Field label="Amount (₹)" htmlFor={`${mode}-rev-amount`} error={errors.amount?.[0]} required>
        <div className="relative">
          <span className="pointer-events-none absolute inset-y-0 left-3.5 flex items-center text-sm text-muted">₹</span>
          <Input
            id={`${mode}-rev-amount`}
            name="amount"
            type="number"
            inputMode="decimal"
            min={0}
            step="0.01"
            placeholder="0.00"
            defaultValue={initial ? Number(initial.amount) : undefined}
            className="pl-7 tabular"
            required
            disabled={busy}
          />
        </div>
      </Field>
      <Field label="Note" htmlFor={`${mode}-rev-note`} error={errors.note?.[0]} className={cn("md:col-span-2", mode === "create" && "lg:col-span-1")}>
        <Textarea
          id={`${mode}-rev-note`}
          name="note"
          placeholder="e.g. Fees from 12 students, mess coupons"
          defaultValue={initial?.note ?? ""}
          className={cn("min-h-[40px]", mode === "create" ? "lg:h-10 lg:min-h-0 lg:resize-none lg:py-2.5" : "min-h-[72px]")}
          rows={1}
          maxLength={500}
          disabled={busy}
        />
      </Field>
      <div className={cn("flex items-end md:col-span-2", mode === "create" && "lg:col-span-1")}>
        <Button type="submit" loading={pending} disabled={disabled} className={cn("w-full", mode === "create" && "lg:w-auto")}>
          <Save /> {mode === "create" ? "Save revenue" : "Save changes"}
        </Button>
      </div>
    </form>
  );
}
