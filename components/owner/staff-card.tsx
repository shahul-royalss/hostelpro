"use client";

import * as React from "react";
import { Building2, KeyRound, Mail, Phone, Plus, UserCheck, UserPlus, UserX } from "lucide-react";
import type { StaffUser } from "@/lib/queries/owner";
import { createStaff, resetStaffPassword, setStaffHostels, setStaffStatus, type StaffCredentials } from "@/lib/actions/owner";
import { useAction } from "@/hooks/use-action";
import { ROLE_LABEL, ROLE_LIMITS } from "@/lib/roles";
import { cn, formatDate } from "@/lib/utils";
import { GlassCard } from "@/components/shared/glass-card";
import { Chip, StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { CredentialsDialog, type Credentials } from "@/components/shared/credentials-dialog";
import { Field } from "@/components/shared/field";
import { UserAvatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/misc";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type StaffRole = "manager" | "warden";

/** One of the owner's PGs, for the PG pickers and the "also in" line. */
export interface OwnerPg {
  id: string;
  name: string;
}

const ROLE_BLURB: Record<StaffRole, string> = {
  manager: "Runs finance and operations — daily expenses, revenue, mess menu, and your tasks.",
  warden: "Runs students and rooms — registrations, beds, fees, leaves, visitors, complaints.",
};

function toCredentials(c: StaffCredentials, title: string): Credentials {
  return { title, name: c.name, role: c.role, loginId: c.loginId, loginLabel: "Email", password: c.password };
}

/**
 * OW-4 staff card for one role: every manager (or warden) with access to the current PG, each
 * with Reset password, Deactivate / Reactivate and, for an owner with 2+ PGs, PG access.
 *
 * Hard rule §4.3: up to ROLE_LIMITS (5) ACTIVE members per role per PG, counted by access, so a
 * warden who works here some days and elsewhere on others takes one place in each PG they are
 * allowed into. "Add" and "Reactivate" are disabled once the PG is full; the database is the
 * real guard and its message is shown if the two ever disagree.
 */
export function StaffCard({
  role,
  members,
  writable,
  hostelId,
  pgs,
}: {
  role: StaffRole;
  members: StaffUser[];
  writable: boolean;
  /** the owner's current PG, the one this page lists */
  hostelId: string;
  /** every PG the owner has; PG access controls only appear with two or more */
  pgs: OwnerPg[];
}) {
  const label = ROLE_LABEL[role];
  const limit = ROLE_LIMITS[role];
  const activeCount = members.filter((m) => m.status === "active").length;
  const slotFree = activeCount < limit;
  const multiPg = pgs.length > 1;

  const [addOpen, setAddOpen] = React.useState(false);
  const [confirm, setConfirm] = React.useState<{ member: StaffUser; to: "deactivate" | "reactivate" } | null>(null);
  const [accessFor, setAccessFor] = React.useState<StaffUser | null>(null);
  const [creds, setCreds] = React.useState<Credentials | null>(null);
  /** whose Reset password is spinning: one hook serves every row */
  const [resettingId, setResettingId] = React.useState<string | null>(null);

  const reset = useAction(resetStaffPassword, { onSuccess: (d) => setCreds(toCredentials(d, "Temporary password")) });
  const status = useAction(setStaffStatus, { onSuccess: () => setConfirm(null) });
  const busy = reset.pending || status.pending;

  return (
    <GlassCard as="section" className="flex h-full flex-col">
      <div className="mb-4 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="label-caps">{label}s</div>
          <p className="mt-0.5 text-[13px] text-muted">{ROLE_BLURB[role]}</p>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-2">
          <Chip tone={slotFree ? "muted" : "sand"}>
            {activeCount} of {limit} active
          </Chip>
          {/* A full CURRENT PG only closes the door for a single-PG owner. With several PGs the
              owner can still add someone to another PG from here: the dialog then starts with
              nothing ticked, and createStaff's per-PG check (and the database) refuse a full PG. */}
          {members.length > 0 ? (
            <Button size="sm" disabled={!writable || (!slotFree && !multiPg)} onClick={() => setAddOpen(true)}>
              <Plus /> Add {role}
            </Button>
          ) : null}
        </div>
      </div>

      {members.length > 0 ? (
        <ul className="divide-y divide-line/70">
          {members.map((m) => (
            <StaffMemberRow
              key={m.id}
              member={m}
              hostelId={hostelId}
              pgs={pgs}
              actions={
                <>
                  {m.status === "active" ? (
                    <>
                      <Button
                        variant="secondary"
                        size="sm"
                        disabled={!writable || busy}
                        loading={reset.pending && resettingId === m.id}
                        onClick={() => {
                          setResettingId(m.id);
                          void reset.run({ userId: m.id });
                        }}
                      >
                        {!(reset.pending && resettingId === m.id) ? <KeyRound /> : null}
                        Reset password
                      </Button>
                      <Button variant="outline-red" size="sm" disabled={!writable || busy} onClick={() => setConfirm({ member: m, to: "deactivate" })}>
                        <UserX /> Deactivate
                      </Button>
                    </>
                  ) : (
                    <Button variant="outline-sage" size="sm" disabled={!writable || busy || !slotFree} onClick={() => setConfirm({ member: m, to: "reactivate" })}>
                      <UserCheck /> Reactivate
                    </Button>
                  )}
                  {multiPg ? (
                    <Button variant="ghost" size="sm" disabled={!writable || busy} onClick={() => setAccessFor(m)}>
                      <Building2 /> PG access
                    </Button>
                  ) : null}
                </>
              }
            />
          ))}
        </ul>
      ) : (
        <EmptyState
          compact
          icon={UserPlus}
          title={`No ${role} yet`}
          description={`Create the ${role}'s login. The temporary password is shown once.`}
          action={
            <Button disabled={!writable} onClick={() => setAddOpen(true)}>
              <Plus /> Add {role}
            </Button>
          }
        />
      )}

      {!writable ? <p className="mt-4 text-xs text-muted">Read-only</p> : null}

      {/* Add dialog */}
      <AddStaffDialog
        role={role}
        open={addOpen}
        onOpenChange={setAddOpen}
        hostelId={hostelId}
        pgs={pgs}
        currentFull={!slotFree}
        onCreated={(c) => setCreds(toCredentials(c, `${label} account created`))}
      />

      {/* PG access */}
      <PgAccessDialog member={accessFor} hostelId={hostelId} pgs={pgs} onOpenChange={(v) => (!v ? setAccessFor(null) : null)} />

      {/* Deactivate / reactivate confirm */}
      <Dialog open={!!confirm} onOpenChange={(v) => (!v ? setConfirm(null) : null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>{confirm?.to === "deactivate" ? `Deactivate ${label.toLowerCase()}?` : `Reactivate ${label.toLowerCase()}?`}</DialogTitle>
            <DialogDescription>
              {confirm?.to === "deactivate" ? (
                <>
                  <span className="font-medium text-charcoal">{confirm.member.full_name}</span> will be signed out and can no longer log in
                  {multiPg ? " to any of your PGs" : ""}. This frees their place so you can add someone else.
                  {multiPg ? " To take away just one PG, use PG access instead." : ""}
                </>
              ) : (
                <>
                  <span className="font-medium text-charcoal">{confirm?.member.full_name}</span> will be able to sign in again with their existing password.
                </>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setConfirm(null)} disabled={status.pending}>
              Cancel
            </Button>
            <Button
              variant={confirm?.to === "deactivate" ? "destructive" : "teal"}
              loading={status.pending}
              onClick={() => confirm && status.run({ userId: confirm.member.id, status: confirm.to === "deactivate" ? "inactive" : "active" })}
            >
              {confirm?.to === "deactivate" ? "Deactivate" : "Reactivate"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <CredentialsDialog open={!!creds} onOpenChange={(v) => (!v ? setCreds(null) : null)} credentials={creds} />
    </GlassCard>
  );
}

function StaffMemberRow({ member, hostelId, pgs, actions }: { member: StaffUser; hostelId: string; pgs: OwnerPg[]; actions: React.ReactNode }) {
  const multiPg = pgs.length > 1;
  const workingHere = member.active_hostel_id === hostelId;
  const pgName = (id: string) => pgs.find((p) => p.id === id)?.name;
  // "Also in": their other PGs, in the owner's own order. The current PG is this page, and where
  // they are working now has its own line.
  const others = member.hostel_ids.filter((id) => id !== hostelId && id !== member.active_hostel_id).map(pgName).filter(Boolean) as string[];

  return (
    <li className="py-4 first:pt-0 last:pb-0">
      <div className="flex items-start gap-3">
        <UserAvatar name={member.full_name} size="md" />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="truncate text-[15px] font-semibold text-navy">{member.full_name}</h3>
            <StatusPill status={member.status} size="sm" dot />
          </div>
          <ul className="mt-1 space-y-0.5 text-sm text-charcoal">
            {member.phone ? (
              <li className="flex items-center gap-2">
                <Phone className="h-3.5 w-3.5 text-muted" />
                <a href={`tel:${member.phone}`} className="hover:underline">{member.phone}</a>
              </li>
            ) : null}
            {member.email ? (
              <li className="flex min-w-0 items-center gap-2">
                <Mail className="h-3.5 w-3.5 shrink-0 text-muted" />
                <a href={`mailto:${member.email}`} className="truncate hover:underline">{member.email}</a>
              </li>
            ) : null}
          </ul>
          {multiPg ? (
            <div className="mt-2 flex flex-wrap items-center gap-1.5 text-[12px]">
              <Building2 className="h-3.5 w-3.5 text-muted" />
              {workingHere ? (
                <Chip tone="teal">Working here now</Chip>
              ) : (
                <Chip tone="sand">Working in {member.active_hostel_name ?? "another PG"} now</Chip>
              )}
              {others.length ? <span className="text-muted">Also in {others.join(", ")}</span> : null}
            </div>
          ) : null}
          <p className="mt-2 text-[11px] text-muted">Added {formatDate(member.created_at)}</p>
        </div>
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2 pl-[52px]">{actions}</div>
    </li>
  );
}

/**
 * The owner's PGs as tickable rows. Which PG a NEW account starts in is decided by
 * orderedSelection() below, not by this list: the current PG when it is ticked, otherwise the
 * first ticked one.
 */
function PgChecklist({
  idPrefix,
  pgs,
  hostelId,
  selected,
  onToggle,
  activeId,
  disabled,
}: {
  idPrefix: string;
  pgs: OwnerPg[];
  hostelId: string;
  selected: Set<string>;
  onToggle: (id: string, on: boolean) => void;
  /** where the member is working now, labelled so removing it is a conscious choice */
  activeId?: string | null;
  disabled?: boolean;
}) {
  return (
    <ul className="space-y-1.5">
      {pgs.map((pg) => {
        const id = `${idPrefix}-${pg.id}`;
        return (
          <li key={pg.id}>
            <label
              htmlFor={id}
              className={cn(
                "flex min-h-11 cursor-pointer items-center gap-3 rounded-control border border-line/70 bg-white/50 px-3 py-2 text-sm",
                selected.has(pg.id) && "border-navy/30 bg-navy/[0.04]",
              )}
            >
              <Checkbox id={id} checked={selected.has(pg.id)} disabled={disabled} onCheckedChange={(v) => onToggle(pg.id, v === true)} />
              <span className="min-w-0 flex-1 truncate font-medium text-charcoal">{pg.name}</span>
              {pg.id === activeId ? <Chip tone="teal">Working here now</Chip> : pg.id === hostelId ? <Chip>This PG</Chip> : null}
            </label>
          </li>
        );
      })}
    </ul>
  );
}

/** Ticked PGs in the order the server wants them: the current PG first, then the owner's order. */
function orderedSelection(pgs: OwnerPg[], hostelId: string, selected: Set<string>): string[] {
  const ids = pgs.map((p) => p.id).filter((id) => selected.has(id));
  return ids.includes(hostelId) ? [hostelId, ...ids.filter((id) => id !== hostelId)] : ids;
}

function AddStaffDialog({
  role,
  open,
  onOpenChange,
  hostelId,
  pgs,
  currentFull,
  onCreated,
}: {
  role: StaffRole;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  hostelId: string;
  pgs: OwnerPg[];
  /** the current PG already has its 5 active of this role, so it must not start ticked */
  currentFull: boolean;
  onCreated: (c: StaffCredentials) => void;
}) {
  const multiPg = pgs.length > 1;
  const initial = React.useCallback(() => new Set(currentFull ? [] : [hostelId]), [currentFull, hostelId]);
  const [fullName, setFullName] = React.useState("");
  const [email, setEmail] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [selected, setSelected] = React.useState<Set<string>>(initial);
  const [errors, setErrors] = React.useState<Record<string, string[]>>({});

  // The current PG is pre-ticked each time the dialog opens (and after switching hostel), unless
  // it is full: then nothing is ticked, so the owner picks the PG with room instead of meeting a
  // refusal they could not have avoided. "Choose at least one PG" still guards an empty choice.
  React.useEffect(() => {
    if (open) setSelected(initial());
  }, [open, initial]);

  const { run, pending } = useAction(createStaff, {
    onSuccess: (c) => {
      onOpenChange(false);
      setFullName("");
      setEmail("");
      setPhone("");
      setErrors({});
      onCreated(c);
    },
  });

  const hostelIds = orderedSelection(pgs, hostelId, selected);
  const startsIn = pgs.find((p) => p.id === hostelIds[0])?.name;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (multiPg && hostelIds.length === 0) {
      setErrors({ hostelIds: ["Choose at least one PG."] });
      return;
    }
    const res = await run({
      role,
      fullName: fullName.trim(),
      email: email.trim(),
      phone: phone.trim(),
      // One PG = today's request shape, so the server treats it exactly as before.
      ...(multiPg ? { hostelIds } : {}),
    });
    if (!res.ok && res.fieldErrors) setErrors(res.fieldErrors);
  }

  return (
    <Dialog open={open} onOpenChange={(v) => (!pending ? onOpenChange(v) : null)}>
      <DialogContent className="max-w-md">
        <form onSubmit={submit} className="space-y-5">
          <DialogHeader>
            <DialogTitle>Add {role}</DialogTitle>
            <DialogDescription>They&apos;ll sign in with this email and a temporary password shown to you once.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <Field label="Full name" htmlFor={`${role}-name`} required error={errors.fullName?.[0]}>
              <Input id={`${role}-name`} value={fullName} onChange={(e) => setFullName(e.target.value)} placeholder="e.g., Priya Sharma" autoFocus required maxLength={80} />
            </Field>
            <Field label="Email" htmlFor={`${role}-email`} required error={errors.email?.[0]} hint="This is their login ID.">
              <Input id={`${role}-email`} type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@example.com" required />
            </Field>
            <Field label="Phone" htmlFor={`${role}-phone`} error={errors.phone?.[0]}>
              <Input id={`${role}-phone`} type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="10-digit mobile number" />
            </Field>
            {multiPg ? (
              <Field
                label="PGs they can work in"
                required
                error={errors.hostelIds?.[0]}
                hint={startsIn ? `They start in ${startsIn} and can switch between the PGs you tick.` : "Tick at least one PG."}
              >
                <PgChecklist
                  idPrefix={`${role}-new-pg`}
                  pgs={pgs}
                  hostelId={hostelId}
                  selected={selected}
                  disabled={pending}
                  onToggle={(id, on) => {
                    setErrors((e) => ({ ...e, hostelIds: [] }));
                    setSelected((s) => {
                      const next = new Set(s);
                      if (on) next.add(id);
                      else next.delete(id);
                      return next;
                    });
                  }}
                />
              </Field>
            ) : null}
          </div>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
              Cancel
            </Button>
            <Button type="submit" loading={pending} disabled={multiPg && hostelIds.length === 0}>
              Create {role} login
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Edit which of the owner's PGs one member may work in (owner_set_staff_hostels). */
function PgAccessDialog({
  member,
  hostelId,
  pgs,
  onOpenChange,
}: {
  member: StaffUser | null;
  hostelId: string;
  pgs: OwnerPg[];
  onOpenChange: (open: boolean) => void;
}) {
  const [selected, setSelected] = React.useState<Set<string>>(new Set());
  React.useEffect(() => {
    if (member) setSelected(new Set(member.hostel_ids));
  }, [member]);

  const { run, pending } = useAction(setStaffHostels, { onSuccess: () => onOpenChange(false) });
  const hostelIds = orderedSelection(pgs, hostelId, selected);
  const removesActive = !!member?.active_hostel_id && !selected.has(member.active_hostel_id);
  const removesThis = !selected.has(hostelId);
  const unchanged = !!member && hostelIds.length === member.hostel_ids.length && hostelIds.every((id) => member.hostel_ids.includes(id));

  return (
    <Dialog open={!!member} onOpenChange={(v) => (!pending ? onOpenChange(v) : null)}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>PG access</DialogTitle>
          <DialogDescription>
            Choose the PGs <span className="font-medium text-charcoal">{member?.full_name}</span> can work in. They switch between them from their app.
          </DialogDescription>
        </DialogHeader>
        <PgChecklist
          idPrefix={`access-${member?.id ?? "none"}`}
          pgs={pgs}
          hostelId={hostelId}
          selected={selected}
          activeId={member?.active_hostel_id}
          disabled={pending}
          onToggle={(id, on) =>
            setSelected((s) => {
              const next = new Set(s);
              if (on) next.add(id);
              else next.delete(id);
              return next;
            })
          }
        />
        <div className="space-y-1 text-[12px] text-muted">
          {hostelIds.length === 0 ? <p className="text-red">Choose at least one PG.</p> : null}
          {hostelIds.length > 0 && removesActive ? <p>They are working in a PG you unticked, so they will move to the first remaining PG by name.</p> : null}
          {hostelIds.length > 0 && removesThis ? <p>They will no longer appear on this page.</p> : null}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button loading={pending} disabled={hostelIds.length === 0 || unchanged} onClick={() => member && run({ userId: member.id, hostelIds })}>
            Save access
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
