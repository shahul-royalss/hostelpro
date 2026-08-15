"use client";

import * as React from "react";
import { format } from "date-fns";
import { ChevronDown, Clock, LogOut, Phone, Plus, Search, UserCheck, Users, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { UserAvatar } from "@/components/ui/avatar";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Field } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { Chip, StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { useAction } from "@/hooks/use-action";
import { checkOutVisitor, logVisitor } from "@/lib/actions/warden";
import type { StudentOption, VisitorWithStudent } from "@/lib/queries/warden";
import { cn, formatDate } from "@/lib/utils";

const RELATIONS = ["Parent", "Sibling", "Relative", "Friend", "Guardian", "Other"] as const;

function timeOf(iso: string) {
  return format(new Date(iso), "h:mm a");
}

export function VisitorsView({
  today,
  history,
  students,
  writable,
}: {
  today: VisitorWithStudent[];
  history: VisitorWithStudent[];
  students: StudentOption[];
  writable: boolean;
}) {
  const [logOpen, setLogOpen] = React.useState(false);
  const [historyOpen, setHistoryOpen] = React.useState(false);
  const inside = today.filter((v) => !v.check_out_at).length;

  return (
    <div className="flex flex-col gap-5">
      {writable ? (
        <Button size="xl" onClick={() => setLogOpen(true)}>
          <Plus className="h-4 w-4" /> Log visitor
        </Button>
      ) : (
        <p className="rounded-control bg-sand-soft px-3 py-2.5 text-[13px] text-sand-deep">Visitor logging is disabled while the hostel is read-only.</p>
      )}

      {/* Today */}
      <section aria-labelledby="today-title">
        <div className="mb-3 flex items-center justify-between px-1">
          <h2 id="today-title" className="text-title-sm text-navy">
            Today
          </h2>
          <span className="text-[12px] text-muted">
            {today.length} {today.length === 1 ? "visitor" : "visitors"}
            {inside > 0 ? ` · ${inside} inside` : ""}
          </span>
        </div>
        {today.length === 0 ? (
          <GlassCard>
            <EmptyState icon={Users} title="No visitors today" description="Logged visitors will show up here with a check-out button." compact />
          </GlassCard>
        ) : (
          <ul className="flex flex-col gap-3">
            {today.map((v) => (
              <VisitorCard key={v.id} visitor={v} writable={writable} />
            ))}
          </ul>
        )}
      </section>

      {/* History (30 days) */}
      <section aria-labelledby="vhistory-title">
        <button
          type="button"
          onClick={() => setHistoryOpen((o) => !o)}
          aria-expanded={historyOpen}
          className="mb-3 flex w-full items-center justify-between px-1"
        >
          <h2 id="vhistory-title" className="text-title-sm text-navy">
            History <span className="text-[13px] font-normal text-muted">· last 30 days</span>
          </h2>
          <span className="inline-flex items-center gap-1 text-[12px] font-medium text-navy">
            {history.length}
            <ChevronDown className={cn("h-4 w-4 transition-transform", historyOpen && "rotate-180")} />
          </span>
        </button>
        {historyOpen ? (
          history.length === 0 ? (
            <GlassCard>
              <EmptyState icon={Users} title="No earlier visitors" compact />
            </GlassCard>
          ) : (
            <GlassCard className="p-0">
              <ul className="divide-y divide-line">
                {history.map((v) => (
                  <li key={v.id} className="flex items-center gap-3 px-4 py-3">
                    <UserAvatar name={v.visitor_name} size="sm" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-semibold text-navy">
                        {v.visitor_name}
                        {v.relation ? <span className="font-normal text-muted"> · {v.relation}</span> : null}
                      </p>
                      <p className="truncate text-[12px] text-muted">
                        Visited {v.student?.full_name ?? "—"}
                        {v.student?.room_number ? ` (Room ${v.student.room_number})` : ""} · {formatDate(v.check_in_at, "d MMM")} {timeOf(v.check_in_at)}
                        {v.check_out_at ? ` → ${timeOf(v.check_out_at)}` : ""}
                      </p>
                    </div>
                    <StatusPill tone={v.check_out_at ? "muted" : "teal"} size="sm" label={v.check_out_at ? "Left" : "Inside"} />
                  </li>
                ))}
              </ul>
            </GlassCard>
          )
        ) : null}
      </section>

      <LogVisitorSheet open={logOpen} onOpenChange={setLogOpen} students={students} />
    </div>
  );
}

function VisitorCard({ visitor: v, writable }: { visitor: VisitorWithStudent; writable: boolean }) {
  const { run, pending } = useAction(checkOutVisitor);
  const inside = !v.check_out_at;
  return (
    <GlassCard as="article" className="p-4" aria-label={`Visitor ${v.visitor_name}`}>
      <div className="flex items-start gap-3">
        <UserAvatar name={v.visitor_name} size="md" />
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-2">
            <p className="truncate text-[15px] font-semibold text-navy">{v.visitor_name}</p>
            <StatusPill tone={inside ? "teal" : "muted"} size="sm" label={inside ? "Inside" : "Checked out"} />
          </div>
          <div className="mt-1 flex flex-wrap items-center gap-1.5 text-[12px] text-muted">
            {v.relation ? <Chip tone="muted">{v.relation}</Chip> : null}
            <span className="inline-flex items-center gap-1">
              <UserCheck className="h-3.5 w-3.5" /> {v.student?.full_name ?? "—"}
              {v.student?.room_number ? ` · Room ${v.student.room_number}` : ""}
            </span>
          </div>
          <div className="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px] text-muted">
            <span className="inline-flex items-center gap-1">
              <Clock className="h-3.5 w-3.5" /> In {timeOf(v.check_in_at)}
              {v.check_out_at ? ` · Out ${timeOf(v.check_out_at)}` : ""}
            </span>
            {v.visitor_phone ? (
              <a href={`tel:${v.visitor_phone}`} className="inline-flex items-center gap-1 hover:text-navy">
                <Phone className="h-3.5 w-3.5" /> {v.visitor_phone}
              </a>
            ) : null}
          </div>
        </div>
      </div>
      {inside && writable ? (
        <Button variant="ghost" className="mt-3 w-full border border-line bg-white/50" loading={pending} onClick={() => run({ visitorId: v.id })}>
          <LogOut className="h-4 w-4" /> Check out
        </Button>
      ) : null}
    </GlassCard>
  );
}

/* ───────────────────────── log visitor sheet ───────────────────────── */

function localNow() {
  return format(new Date(), "yyyy-MM-dd'T'HH:mm");
}

function LogVisitorSheet({ open, onOpenChange, students }: { open: boolean; onOpenChange: (open: boolean) => void; students: StudentOption[] }) {
  const [studentId, setStudentId] = React.useState<string>("");
  const [studentQuery, setStudentQuery] = React.useState("");
  const [name, setName] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [relation, setRelation] = React.useState<string>("");
  const [checkIn, setCheckIn] = React.useState(localNow());
  const [errors, setErrors] = React.useState<Record<string, string>>({});
  const { run, pending } = useAction(logVisitor, { onSuccess: () => onOpenChange(false) });

  React.useEffect(() => {
    if (open) {
      setStudentId("");
      setStudentQuery("");
      setName("");
      setPhone("");
      setRelation("");
      setCheckIn(localNow());
      setErrors({});
    }
  }, [open]);

  const selected = students.find((s) => s.id === studentId) ?? null;
  const q = studentQuery.trim().toLowerCase();
  const matches = q ? students.filter((s) => s.full_name.toLowerCase().includes(q) || s.phone.includes(q) || (s.room_number ?? "").toLowerCase().includes(q)).slice(0, 8) : students.slice(0, 8);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        <SheetHeader>
          <SheetTitle>Log visitor</SheetTitle>
          <SheetDescription>Record who is visiting, and whom. Check-in defaults to now.</SheetDescription>
        </SheetHeader>
        <form
          className="mt-4 flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            const errs: Record<string, string> = {};
            if (!studentId) errs.student = "Select the student being visited";
            if (name.trim().length < 2) errs.name = "Enter the visitor's name";
            const ts = new Date(checkIn);
            if (Number.isNaN(ts.getTime())) errs.checkIn = "Pick a valid check-in time";
            setErrors(errs);
            if (Object.keys(errs).length) return;
            run({ studentId, visitorName: name.trim(), visitorPhone: phone.trim() || undefined, relation: relation || undefined, checkInAt: ts.toISOString() });
          }}
        >
          <Field label="Visiting student" required error={errors.student}>
            {selected ? (
              <div className="flex items-center gap-3 rounded-control border border-navy/20 bg-white/70 p-2.5">
                <UserAvatar name={selected.full_name} size="sm" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-semibold text-navy">{selected.full_name}</p>
                  <p className="text-[12px] text-muted">
                    {selected.room_number ? `Room ${selected.room_number} · ` : ""}
                    {selected.phone}
                  </p>
                </div>
                <button type="button" aria-label="Change student" onClick={() => setStudentId("")} className="flex h-9 w-9 items-center justify-center rounded-full text-muted hover:bg-navy/5 hover:text-navy">
                  <X className="h-4 w-4" />
                </button>
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                <div className="relative">
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
                  <Input type="search" placeholder="Search by name, room or phone" value={studentQuery} onChange={(e) => setStudentQuery(e.target.value)} className="pl-9" aria-label="Search students" />
                </div>
                {students.length === 0 ? (
                  <p className="text-[12px] text-muted">No active students yet.</p>
                ) : matches.length === 0 ? (
                  <p className="text-[12px] text-muted">No students match.</p>
                ) : (
                  <ul className="max-h-44 overflow-y-auto rounded-control border border-line bg-white/60">
                    {matches.map((s) => (
                      <li key={s.id}>
                        <button type="button" onClick={() => setStudentId(s.id)} className="flex w-full items-center gap-2.5 px-3 py-2 text-left hover:bg-white/80">
                          <UserAvatar name={s.full_name} size="xs" />
                          <span className="min-w-0 flex-1 truncate text-sm font-medium text-navy">{s.full_name}</span>
                          <span className="shrink-0 text-[11px] text-muted">{s.room_number ? `Room ${s.room_number}` : "No room"}</span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </Field>

          <Field label="Visitor name" htmlFor="visitor-name" required error={errors.name}>
            <Input id="visitor-name" placeholder="Full name" value={name} onChange={(e) => setName(e.target.value)} autoComplete="off" />
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Phone (optional)" htmlFor="visitor-phone">
              <Input id="visitor-phone" type="tel" inputMode="numeric" placeholder="98765 43210" value={phone} onChange={(e) => setPhone(e.target.value)} />
            </Field>
            <Field label="Check-in" htmlFor="visitor-checkin" required error={errors.checkIn}>
              <Input id="visitor-checkin" type="datetime-local" value={checkIn} max={localNow()} onChange={(e) => setCheckIn(e.target.value)} />
            </Field>
          </div>

          <div className="flex flex-col gap-1.5">
            <span className="label-caps text-charcoal/80">Relation</span>
            <div className="no-scrollbar -mx-1 flex gap-2 overflow-x-auto px-1">
              {RELATIONS.map((r) => {
                const active = relation === r;
                return (
                  <button
                    key={r}
                    type="button"
                    aria-pressed={active}
                    onClick={() => setRelation(active ? "" : r)}
                    className={cn(
                      "shrink-0 rounded-full border px-3 py-1.5 text-xs font-medium transition-all active:scale-[0.97]",
                      active ? "border-navy bg-navy text-white shadow-sm" : "border-white/70 bg-white/60 text-muted hover:text-navy",
                    )}
                  >
                    {r}
                  </button>
                );
              })}
            </div>
          </div>

          <Button type="submit" size="xl" loading={pending}>
            Save visitor
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
