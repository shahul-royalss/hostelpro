"use client";

import * as React from "react";
import { Ban, KeyRound, ShieldCheck } from "lucide-react";
import { Button, type ButtonProps } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { CredentialsDialog, type Credentials } from "@/components/shared/credentials-dialog";
import { useAction } from "@/hooks/use-action";
import { regenerateOwnerPassword, setHostelStatus } from "@/lib/actions/super-admin";
import type { HostelStatus } from "@/lib/types";

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
  const { run, pending } = useAction(setHostelStatus, { onSuccess: () => setOpen(false) });

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
      <Dialog open={open} onOpenChange={setOpen}>
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
            <Button type="button" variant="ghost" onClick={() => setOpen(false)} disabled={pending}>
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

/** Standalone button version (hostel detail). */
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
