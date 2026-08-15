"use client";

import * as React from "react";
import { KeyRound, Mail, Phone, Plus, UserCheck, UserPlus, UserX } from "lucide-react";
import type { StaffUser } from "@/lib/queries/owner";
import { createStaff, resetStaffPassword, setStaffStatus, type StaffCredentials } from "@/lib/actions/owner";
import { useAction } from "@/hooks/use-action";
import { ROLE_LABEL, ROLE_LIMITS } from "@/lib/roles";
import { formatDate } from "@/lib/utils";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { CredentialsDialog, type Credentials } from "@/components/shared/credentials-dialog";
import { Field } from "@/components/shared/field";
import { UserAvatar } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type StaffRole = "manager" | "warden";

const ROLE_BLURB: Record<StaffRole, string> = {
  manager: "Runs finance and operations — daily expenses, revenue, mess menu, and your tasks.",
  warden: "Runs students and rooms — registrations, beds, fees, leaves, visitors, complaints.",
};

function toCredentials(c: StaffCredentials, title: string): Credentials {
  return { title, name: c.name, role: c.role, loginId: c.loginId, loginLabel: "Email", password: c.password };
}

/**
 * OW-4 staff card for one role. Shows the active member (or the most recent inactive one),
 * with Reset password / Deactivate / Reactivate, or an empty state with "Add <role>".
 * Hard rule §4.3: "Add" is disabled while an active member exists (ROLE_LIMITS); the DB trigger is the real guard.
 */
export function StaffCard({ role, members, writable }: { role: StaffRole; members: StaffUser[]; writable: boolean }) {
  const active = members.find((m) => m.status === "active") ?? null;
  const primary = active ?? members[0] ?? null;
  const activeCount = members.filter((m) => m.status === "active").length;
  const slotFree = activeCount < ROLE_LIMITS[role];
  const label = ROLE_LABEL[role];

  const [addOpen, setAddOpen] = React.useState(false);
  const [confirm, setConfirm] = React.useState<"deactivate" | "reactivate" | null>(null);
  const [creds, setCreds] = React.useState<Credentials | null>(null);

  const reset = useAction(resetStaffPassword, { onSuccess: (d) => setCreds(toCredentials(d, "Temporary password")) });
  const status = useAction(setStaffStatus, { onSuccess: () => setConfirm(null) });

  const busy = reset.pending || status.pending;

  return (
    <GlassCard as="section" className="flex h-full flex-col">
      <div className="mb-4 flex items-start justify-between gap-3">
        <div>
          <div className="label-caps">{label}</div>
          <p className="mt-0.5 text-[13px] text-muted">{ROLE_BLURB[role]}</p>
        </div>
        {primary ? <StatusPill status={primary.status} dot /> : null}
      </div>

      {primary ? (
        <>
          <div className="flex items-start gap-4">
            <UserAvatar name={primary.full_name} size="xl" />
            <div className="min-w-0 flex-1">
              <h3 className="truncate text-lg font-semibold text-navy">{primary.full_name}</h3>
              <ul className="mt-1.5 space-y-1 text-sm text-charcoal">
                {primary.phone ? (
                  <li className="flex items-center gap-2">
                    <Phone className="h-3.5 w-3.5 text-muted" />
                    <a href={`tel:${primary.phone}`} className="hover:underline">{primary.phone}</a>
                  </li>
                ) : null}
                {primary.email ? (
                  <li className="flex min-w-0 items-center gap-2">
                    <Mail className="h-3.5 w-3.5 shrink-0 text-muted" />
                    <a href={`mailto:${primary.email}`} className="truncate hover:underline">{primary.email}</a>
                  </li>
                ) : null}
              </ul>
              <p className="mt-2 text-[11px] text-muted">Added {formatDate(primary.created_at)}</p>
            </div>
          </div>

          <div className="mt-5 flex flex-wrap items-center gap-2 border-t border-line/70 pt-4">
            {primary.status === "active" ? (
              <>
                <Button variant="secondary" size="sm" disabled={!writable || busy} loading={reset.pending} onClick={() => reset.run({ userId: primary.id })}>
                  {!reset.pending ? <KeyRound /> : null}
                  Reset password
                </Button>
                <Button variant="outline-red" size="sm" disabled={!writable || busy} onClick={() => setConfirm("deactivate")}>
                  <UserX /> Deactivate
                </Button>
              </>
            ) : (
              <>
                <Button variant="outline-sage" size="sm" disabled={!writable || busy || !slotFree} onClick={() => setConfirm("reactivate")}>
                  <UserCheck /> Reactivate
                </Button>
                <Button size="sm" disabled={!writable || busy || !slotFree} onClick={() => setAddOpen(true)}>
                  <Plus /> Add new {role}
                </Button>
              </>
            )}
            {!writable ? <span className="ml-auto text-xs text-muted">Read-only</span> : null}
          </div>
        </>
      ) : (
        <EmptyState
          compact
          icon={UserPlus}
          title={`No ${role} yet`}
          description={`Create the ${role}'s login — the temporary password is shown once.`}
          action={
            <Button disabled={!writable} onClick={() => setAddOpen(true)}>
              <Plus /> Add {role}
            </Button>
          }
        />
      )}

      {/* Add dialog */}
      <AddStaffDialog role={role} open={addOpen} onOpenChange={setAddOpen} onCreated={(c) => setCreds(toCredentials(c, `${label} account created`))} />

      {/* Deactivate / reactivate confirm */}
      <Dialog open={!!confirm} onOpenChange={(v) => (!v ? setConfirm(null) : null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>{confirm === "deactivate" ? `Deactivate ${label.toLowerCase()}?` : `Reactivate ${label.toLowerCase()}?`}</DialogTitle>
            <DialogDescription>
              {confirm === "deactivate" ? (
                <>
                  <span className="font-medium text-charcoal">{primary?.full_name}</span> will be signed out and can no longer log in. This frees the {role} slot so you can add someone else.
                </>
              ) : (
                <>
                  <span className="font-medium text-charcoal">{primary?.full_name}</span> will be able to sign in again with their existing password.
                </>
              )}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setConfirm(null)} disabled={status.pending}>
              Cancel
            </Button>
            <Button
              variant={confirm === "deactivate" ? "destructive" : "teal"}
              loading={status.pending}
              onClick={() => primary && status.run({ userId: primary.id, status: confirm === "deactivate" ? "inactive" : "active" })}
            >
              {confirm === "deactivate" ? "Deactivate" : "Reactivate"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <CredentialsDialog open={!!creds} onOpenChange={(v) => (!v ? setCreds(null) : null)} credentials={creds} />
    </GlassCard>
  );
}

function AddStaffDialog({
  role,
  open,
  onOpenChange,
  onCreated,
}: {
  role: StaffRole;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated: (c: StaffCredentials) => void;
}) {
  const [fullName, setFullName] = React.useState("");
  const [email, setEmail] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [errors, setErrors] = React.useState<Record<string, string[]>>({});
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

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const res = await run({ role, fullName: fullName.trim(), email: email.trim(), phone: phone.trim() });
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
          </div>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
              Cancel
            </Button>
            <Button type="submit" loading={pending}>
              Create {role} login
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
