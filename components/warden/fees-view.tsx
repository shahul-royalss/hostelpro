"use client";

import * as React from "react";
import { usePathname, useRouter } from "next/navigation";
import { Banknote, CheckCircle2, ChevronRight, Search, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { UserAvatar } from "@/components/ui/avatar";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Field } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { MonthSelector } from "@/components/shared/month-selector";
import { SegmentedPills } from "@/components/shared/segmented";
import { Chip, StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { useAction } from "@/hooks/use-action";
import { recordPayment } from "@/lib/actions/warden";
import { PAYMENT_MODES, type FeeLedgerRow, type FeeStatus, type PaymentMode } from "@/lib/types";
import { cn, formatDate, formatINR, formatINRCompact, formatPeriodMonth, toISODate } from "@/lib/utils";

export type FeeRow = FeeLedgerRow & { photoUrl: string | null };

type Filter = "all" | FeeStatus;

const MODE_LABEL: Record<PaymentMode, string> = { cash: "Cash", upi: "UPI", bank: "Bank" };

export function FeesView({ period, rows, writable }: { period: string; rows: FeeRow[]; writable: boolean }) {
  const router = useRouter();
  const pathname = usePathname();
  const [filter, setFilter] = React.useState<Filter>("all");
  const [query, setQuery] = React.useState("");
  const [selected, setSelected] = React.useState<FeeRow | null>(null);
  const [navPending, startNav] = React.useTransition();

  const collected = rows.reduce((s, r) => s + r.amount_paid, 0);
  const pending = rows.reduce((s, r) => s + Math.max(0, r.amount_due - r.amount_paid), 0);
  const counts = React.useMemo(() => {
    const c: Record<Filter, number> = { all: rows.length, unpaid: 0, partial: 0, paid: 0 };
    for (const r of rows) c[r.status] += 1;
    return c;
  }, [rows]);

  const q = query.trim().toLowerCase();
  const visible = rows.filter((r) => (filter === "all" || r.status === filter) && (!q || r.full_name.toLowerCase().includes(q) || r.phone.includes(q) || (r.room_number ?? "").toLowerCase().includes(q)));

  function changeMonth(next: string) {
    startNav(() => router.push(`${pathname}?month=${next}`));
  }

  return (
    <div className="flex flex-col gap-4">
      <MonthSelector value={period} onChange={changeMonth} variant="chips" monthsBack={5} className={cn("-mx-4 px-4", navPending && "opacity-60")} />

      {/* Summary strip */}
      <div className="grid grid-cols-2 gap-3">
        <GlassCard className="p-4">
          <div className="flex items-start justify-between gap-2">
            <div className="label-caps">Collected</div>
            <CheckCircle2 className="h-4 w-4 text-teal/60" strokeWidth={1.75} />
          </div>
          <div className="mt-1 text-stat-sm text-teal tabular" title={formatINR(collected)}>
            {formatINRCompact(collected)}
          </div>
          <div className="mt-0.5 text-[11px] text-muted">
            {counts.paid} paid · {formatPeriodMonth(period)}
          </div>
        </GlassCard>
        <GlassCard className="p-4">
          <div className="flex items-start justify-between gap-2">
            <div className="label-caps">Pending</div>
            <Wallet className="h-4 w-4 text-red/60" strokeWidth={1.75} />
          </div>
          <div className="mt-1 text-stat-sm text-red tabular" title={formatINR(pending)}>
            {formatINRCompact(pending)}
          </div>
          <div className="mt-0.5 text-[11px] text-muted">
            {counts.unpaid + counts.partial} {counts.unpaid + counts.partial === 1 ? "student" : "students"} due
          </div>
        </GlassCard>
      </div>

      {/* Filters + search */}
      <SegmentedPills<Filter>
        ariaLabel="Filter by fee status"
        size="sm"
        className="-mx-4 px-4"
        options={[
          { value: "all", label: "All", count: counts.all },
          { value: "unpaid", label: "Unpaid", count: counts.unpaid, tone: "red" },
          { value: "partial", label: "Partial", count: counts.partial, tone: "sand" },
          { value: "paid", label: "Paid", count: counts.paid, tone: "teal" },
        ]}
        value={filter}
        onChange={setFilter}
      />
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
        <Input
          type="search"
          inputMode="search"
          placeholder="Search name, phone or room"
          aria-label="Search students"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="pl-9"
        />
      </div>

      {/* Ledger */}
      {visible.length === 0 ? (
        <GlassCard>
          <EmptyState
            icon={Banknote}
            title={rows.length === 0 ? "No active students" : q ? "No students match your search" : `No ${filter === "all" ? "" : filter + " "}students this month`}
            description={rows.length === 0 ? "Register a student to start tracking fees." : undefined}
          />
        </GlassCard>
      ) : (
        <ul className="flex flex-col gap-2.5">
          {visible.map((r) => {
            const remaining = Math.max(0, r.amount_due - r.amount_paid);
            const actionable = writable && r.status !== "paid";
            const inner = (
              <>
                <UserAvatar name={r.full_name} src={r.photoUrl} size="md" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-semibold text-navy">{r.full_name}</p>
                  <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[11px] text-muted">
                    <Chip tone="muted">{r.room_number ? `Room ${r.room_number}` : "No room"}</Chip>
                    <span className="truncate">
                      {r.status === "paid"
                        ? `Paid ${formatDate(r.paid_on, "d MMM")}${r.mode ? ` · ${MODE_LABEL[r.mode]}` : ""}`
                        : r.status === "partial"
                          ? `Bal: ${formatINR(remaining)}`
                          : `Due ${formatINR(r.amount_due)}`}
                    </span>
                  </div>
                </div>
                <div className="flex shrink-0 flex-col items-end gap-1">
                  <span className="text-[15px] font-bold text-navy tabular">{formatINR(r.amount_due)}</span>
                  <StatusPill status={r.status} size="sm" />
                </div>
                {actionable ? <ChevronRight className="h-4 w-4 shrink-0 text-muted/70" /> : null}
              </>
            );
            return (
              <li key={r.student_id}>
                {actionable ? (
                  <button
                    type="button"
                    onClick={() => setSelected(r)}
                    className="glass-card flex w-full items-center gap-3 p-3.5 text-left transition-colors hover:bg-white/80 active:scale-[0.99]"
                    aria-label={`Record payment for ${r.full_name}`}
                  >
                    {inner}
                  </button>
                ) : (
                  <div className="glass-card flex items-center gap-3 p-3.5">{inner}</div>
                )}
              </li>
            );
          })}
        </ul>
      )}

      <RecordPaymentSheet row={selected} period={period} onOpenChange={(o) => !o && setSelected(null)} />
    </div>
  );
}

/* ───────────────────────── record payment sheet ───────────────────────── */

export function RecordPaymentSheet({ row, period, onOpenChange }: { row: FeeRow | null; period: string; onOpenChange: (open: boolean) => void }) {
  const remaining = row ? Math.max(0, row.amount_due - row.amount_paid) : 0;
  const [amount, setAmount] = React.useState<string>("");
  const [mode, setMode] = React.useState<PaymentMode>("cash");
  const [paidOn, setPaidOn] = React.useState(toISODate());
  const [notes, setNotes] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const { run, pending } = useAction(recordPayment, { onSuccess: () => onOpenChange(false) });

  React.useEffect(() => {
    if (row) {
      setAmount(String(Math.max(0, row.amount_due - row.amount_paid) || row.amount_due));
      setMode(row.mode ?? "cash");
      setPaidOn(toISODate());
      setNotes("");
      setError(null);
    }
  }, [row]);

  const amt = Number(amount);
  const willOverpay = row ? amt > remaining && remaining > 0 : false;

  return (
    <Sheet open={!!row} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        <SheetHeader>
          <SheetTitle>Record payment</SheetTitle>
          <SheetDescription>
            {row ? (
              <>
                <span className="font-medium text-charcoal">{row.full_name}</span>
                {row.room_number ? ` · Room ${row.room_number}` : ""} · {formatPeriodMonth(period)}
              </>
            ) : null}
          </SheetDescription>
        </SheetHeader>

        {row ? (
          <form
            className="mt-4 flex flex-col gap-4"
            onSubmit={(e) => {
              e.preventDefault();
              if (!Number.isFinite(amt) || amt <= 0) {
                setError("Enter an amount greater than zero.");
                return;
              }
              setError(null);
              run({ studentId: row.student_id, periodMonth: period, amount: amt, mode, paidOn, notes: notes.trim() || undefined });
            }}
          >
            <div className="grid grid-cols-3 gap-2 rounded-control bg-white/60 p-3 text-center">
              <div>
                <div className="label-caps">Due</div>
                <div className="mt-0.5 text-sm font-semibold text-navy tabular">{formatINR(row.amount_due)}</div>
              </div>
              <div>
                <div className="label-caps">Paid</div>
                <div className="mt-0.5 text-sm font-semibold text-teal tabular">{formatINR(row.amount_paid)}</div>
              </div>
              <div>
                <div className="label-caps">Remaining</div>
                <div className="mt-0.5 text-sm font-semibold text-red tabular">{formatINR(remaining)}</div>
              </div>
            </div>

            <Field label="Amount (₹)" htmlFor="pay-amount" required error={error} hint={willOverpay ? `More than the remaining ${formatINR(remaining)} — will be recorded as an advance.` : undefined}>
              <Input
                id="pay-amount"
                type="number"
                inputMode="numeric"
                min={1}
                step={1}
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                className="text-[17px] font-semibold tabular"
                autoFocus
              />
            </Field>

            <div className="flex flex-col gap-1.5">
              <span className="label-caps text-charcoal/80">Mode</span>
              <SegmentedPills<PaymentMode>
                ariaLabel="Payment mode"
                fullWidth
                options={PAYMENT_MODES.map((m) => ({ value: m, label: MODE_LABEL[m] }))}
                value={mode}
                onChange={setMode}
              />
            </div>

            <Field label="Date" htmlFor="pay-date" required>
              <Input id="pay-date" type="date" value={paidOn} max={toISODate()} onChange={(e) => setPaidOn(e.target.value)} required />
            </Field>

            <Field label="Note (optional)" htmlFor="pay-notes">
              <Textarea id="pay-notes" rows={2} maxLength={300} placeholder="e.g. UPI ref 4821…" value={notes} onChange={(e) => setNotes(e.target.value)} />
            </Field>

            <Button type="submit" size="xl" loading={pending}>
              Save payment
            </Button>
          </form>
        ) : null}
      </SheetContent>
    </Sheet>
  );
}
