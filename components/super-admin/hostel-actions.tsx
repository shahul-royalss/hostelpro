"use client";

import * as React from "react";
import { Ban, KeyRound, MoreHorizontal, ShieldCheck } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { CredentialsDialog, type Credentials } from "@/components/shared/credentials-dialog";
import { useAction } from "@/hooks/use-action";
import { regenerateOwnerPassword, setHostelStatus } from "@/lib/actions/super-admin";
import type { HostelStatus } from "@/lib/types";

/** Suspend / Unsuspend confirmation (controlled) — shared by the button and the header menu. */
export function HostelStatusDialog({
  hostelId,
  hostelName,
  status,
  open,
  onOpenChange,
}: {
  hostelId: string;
  hostelName: string;
  status: HostelStatus;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const suspended = status === "suspended";
  const { run, pending } = useAction(setHostelStatus, { onSuccess: () => onOpenChange(false) });
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <div className={suspended ? "mb-1 flex h-11 w-11 items-center justify-center rounded-full bg-sage-soft text-sage" : "mb-1 flex h-11 w-11 items-center justify-center rounded-full bg-red-soft text-red"}>
            {suspended ? <ShieldCheck className="h-5 w-5" /> : <Ban className="h-5 w-5" />}
          </div>
          <DialogTitle>{suspended ? "Reactivate hostel?" : "Suspend hostel?"}</DialogTitle>
          <DialogDescription>
            {suspended ? (
              <>
                <span className="font-medium text-charcoal">{hostelName}</span> will become writable again for its owner, staff and students
                (as long as the subscription is not expired).
              </>
            ) : (
              <>
                <span className="font-medium text-charcoal">{hostelName}</span> becomes read-only for its owner, staff and students until you
                unsuspend it. Data is kept.
              </>
            )}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button type="button" variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button
            type="button"
            variant={suspended ? "teal" : "destructive"}
            loading={pending}
            onClick={() => void run({ hostelId, status: suspended ? "active" : "suspended" })}
          >
            {suspended ? "Unsuspend" : "Suspend"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Suspend / Unsuspend a hostel with a confirmation step. */
export function HostelStatusButton({
  hostelId,
  hostelName,
  status,
  size = "sm",
  className,
}: {
  hostelId: string;
  hostelName: string;
  status: HostelStatus;
  size?: ButtonProps["size"];
  className?: string;
}) {
  const [open, setOpen] = React.useState(false);
  const suspended = status === "suspended";

  return (
    <>
      <Button
        type="button"
        size={size}
        variant={suspended ? "outline-sage" : "outline-red"}
        className={className}
        onClick={(e) => {
          e.stopPropagation();
          setOpen(true);
        }}
      >
        {suspended ? <ShieldCheck /> : <Ban />}
        {suspended ? "Unsuspend" : "Suspend"}
      </Button>
      <HostelStatusDialog hostelId={hostelId} hostelName={hostelName} status={status} open={open} onOpenChange={setOpen} />
    </>
  );
}

/**
 * Regenerate an owner's password — controlled variant so it can be triggered from a
 * dropdown menu item; shows the credentials exactly once.
 */
export function useRegenerateOwnerPassword() {
  const [creds, setCreds] = React.useState<Credentials | null>(null);
  const [open, setOpen] = React.useState(false);
  const { run, pending } = useAction(regenerateOwnerPassword, {
    refresh: false,
    onSuccess: (data) => {
      setCreds({ title: "New password issued", name: data.name, loginId: data.loginId, password: data.password, role: "Owner" });
      setOpen(true);
    },
  });
  const dialog = <CredentialsDialog open={open} onOpenChange={setOpen} credentials={creds} />;
  return { regenerate: (ownerUserId: string) => void run({ ownerUserId }), pending, dialog };
}

/** Standalone button version. */
export function RegeneratePasswordButton({ ownerUserId, size = "sm" }: { ownerUserId: string; size?: ButtonProps["size"] }) {
  const { regenerate, pending, dialog } = useRegenerateOwnerPassword();
  return (
    <>
      <Button type="button" variant="secondary" size={size} loading={pending} onClick={() => regenerate(ownerUserId)}>
        <KeyRound />
        Regenerate owner password
      </Button>
      {dialog}
    </>
  );
}

/**
 * SA-4 header "⋯" menu — keeps the detail page read-only-looking (DESIGN.md SA-4: the only
 * prominent edit control is "Renew subscription"); §6.1 row actions live behind this menu.
 */
export function HostelHeaderMenu({
  hostelId,
  hostelName,
  status,
  ownerUserId,
}: {
  hostelId: string;
  hostelName: string;
  status: HostelStatus;
  ownerUserId: string;
}) {
  const [statusOpen, setStatusOpen] = React.useState(false);
  const { regenerate, pending, dialog } = useRegenerateOwnerPassword();
  const suspended = status === "suspended";
  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon" aria-label="More actions" loading={pending}>
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onSelect={() => regenerate(ownerUserId)}>
            <KeyRound />
            Regenerate owner password
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem onSelect={() => setStatusOpen(true)} className={suspended ? "text-sage focus:text-sage" : "text-red focus:text-red"}>
            {suspended ? <ShieldCheck /> : <Ban />}
            {suspended ? "Unsuspend hostel" : "Suspend hostel"}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <HostelStatusDialog hostelId={hostelId} hostelName={hostelName} status={status} open={statusOpen} onOpenChange={setStatusOpen} />
      {dialog}
    </>
  );
}
