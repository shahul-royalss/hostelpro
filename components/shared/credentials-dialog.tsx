"use client";

import * as React from "react";
import { Check, Copy, KeyRound, ShieldAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

export interface Credentials {
  title?: string;
  name: string;
  loginId: string;
  loginLabel?: string; // "Email" | "Phone"
  password: string;
  role?: string;
}

/**
 * Shows generated credentials exactly once (Hard rule §4.9) with copy buttons.
 * Closing is deliberate — the user must confirm they've saved them.
 */
export function CredentialsDialog({
  open,
  onOpenChange,
  credentials,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  credentials: Credentials | null;
}) {
  const [confirmed, setConfirmed] = React.useState(false);
  React.useEffect(() => {
    if (open) setConfirmed(false);
  }, [open]);

  if (!credentials) return null;
  const c = credentials;
  const loginLabel = c.loginLabel ?? (c.loginId.includes("@") ? "Email" : "Phone");
  const all = `${c.name}\n${loginLabel}: ${c.loginId}\nTemporary password: ${c.password}`;

  return (
    <Dialog open={open} onOpenChange={(v) => (v || confirmed ? onOpenChange(v) : null)}>
      <DialogContent hideClose className="max-w-md">
        <DialogHeader>
          <div className="mb-1 flex h-11 w-11 items-center justify-center rounded-full bg-teal-soft text-teal">
            <KeyRound className="h-5 w-5" />
          </div>
          <DialogTitle>{c.title ?? "Account created"}</DialogTitle>
          <DialogDescription>
            Share these credentials with <span className="font-medium text-charcoal">{c.name}</span>
            {c.role ? ` (${c.role})` : ""}. They&apos;ll be asked to set a new password on first sign-in.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          <CredRow label={loginLabel} value={c.loginId} />
          <CredRow label="Temporary password" value={c.password} mono />
        </div>

        <div className="flex items-start gap-2 rounded-control bg-sand-soft px-3 py-2.5 text-[13px] text-sand-deep">
          <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0" />
          <p>This password is shown only once. Copy it now — it cannot be viewed again (you can regenerate a new one later).</p>
        </div>

        <DialogFooter className="items-center gap-3 sm:justify-between">
          <label className="flex cursor-pointer items-center gap-2 text-sm text-charcoal">
            <input type="checkbox" className="h-4 w-4 rounded border-input accent-navy" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            I&apos;ve saved these credentials
          </label>
          <div className="flex gap-2">
            <CopyButton text={all} label="Copy all" />
            <Button disabled={!confirmed} onClick={() => onOpenChange(false)}>
              Done
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function CredRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex items-center justify-between gap-3 rounded-control border border-line bg-white/70 px-3.5 py-2.5">
      <div className="min-w-0">
        <div className="label-caps">{label}</div>
        <div className={cn("mt-0.5 truncate text-sm font-semibold text-navy", mono && "font-mono tracking-wide")}>{value}</div>
      </div>
      <CopyButton text={value} />
    </div>
  );
}

export function CopyButton({ text, label, className }: { text: string; label?: string; className?: string }) {
  const [copied, setCopied] = React.useState(false);
  return (
    <Button
      type="button"
      variant="secondary"
      size={label ? "sm" : "icon-sm"}
      className={className}
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(text);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        } catch {
          /* clipboard unavailable */
        }
      }}
      aria-label={label ?? "Copy"}
    >
      {copied ? <Check className="text-teal" /> : <Copy />}
      {label ? (copied ? "Copied" : label) : null}
    </Button>
  );
}
