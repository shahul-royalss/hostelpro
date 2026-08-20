"use client";

import * as React from "react";
import Link from "next/link";
import { ChevronRight, CircleCheck, ShieldAlert, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Field } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { useAction } from "@/hooks/use-action";
import { requestAccountDeletion } from "@/lib/actions/account";
import { formatDate } from "@/lib/utils";

/**
 * "Delete my account and data" — the in-app entry point Google Play requires.
 *
 * It files a REQUEST rather than deleting anything: nobody in this app holds a delete
 * privilege on their own record, and identity has to be verified in person first. See the
 * long note at the top of lib/actions/account.ts, and /legal/account-deletion for the
 * public-facing version of the same explanation.
 */
export function DeleteAccountCard({ requestedAt }: { requestedAt: string | null }) {
  const [open, setOpen] = React.useState(false);
  const [reason, setReason] = React.useState("");
  const [filedAt, setFiledAt] = React.useState<string | null>(requestedAt);

  // The server component re-reads the request on router.refresh(); keep the props in sync so
  // the card does not flip back to its initial state on an unrelated re-render.
  React.useEffect(() => setFiledAt(requestedAt), [requestedAt]);

  const { run, pending } = useAction(requestAccountDeletion, {
    onSuccess: (data) => {
      setFiledAt(data.requestedAt);
      setReason("");
      setOpen(false);
    },
  });

  return (
    <GlassCard className="border border-red/20">
      <div className="flex items-start gap-3">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-red-soft text-red">
          <Trash2 className="h-[18px] w-[18px]" strokeWidth={1.75} />
        </span>
        <div className="min-w-0 flex-1">
          <h2 className="text-card-title font-semibold text-navy">Delete my account and data</h2>
          <p className="mt-1 text-[13px] leading-relaxed text-muted">
            Your hostel registered this account, so deletion is handled as a verified request. Your warden and hostel
            owner are notified, they confirm it is really you, and your personal details, photo and ID proof are then
            erased.
          </p>
        </div>
      </div>

      {filedAt ? (
        <div className="mt-4 flex items-start gap-2.5 rounded-control border border-teal/25 bg-teal-soft px-3.5 py-3">
          <CircleCheck className="mt-0.5 h-4 w-4 shrink-0 text-teal" strokeWidth={2} />
          <div className="text-[13px] leading-relaxed text-charcoal">
            <span className="font-semibold text-navy">Request sent on {formatDate(filedAt)}.</span> Your warden and
            hostel owner have it. They will speak to you to confirm your identity before anything is erased. If nobody
            has been in touch within 30 days, use the contact details on the deletion page below.
          </div>
        </div>
      ) : (
        <>
          <div className="mt-4 flex items-start gap-2.5 rounded-control border border-sand/40 bg-sand-soft px-3.5 py-3">
            <ShieldAlert className="mt-0.5 h-4 w-4 shrink-0 text-sand-deep" strokeWidth={2} />
            <div className="text-[13px] leading-relaxed text-charcoal">
              Fee and payment records are kept even after your details are erased — the hostel has an accounting duty it
              cannot waive. Your name is removed from them instead.
            </div>
          </div>

          <Button
            type="button"
            variant="outline-red"
            size="xl"
            className="mt-4"
            onClick={() => setOpen(true)}
          >
            <Trash2 />
            Delete my account and data
          </Button>
        </>
      )}

      <Link
        href="/legal/account-deletion"
        className="mt-3 flex items-center gap-1.5 px-1 text-[12px] font-medium text-navy underline-offset-4 hover:underline"
      >
        What gets deleted, what is kept and why
        <ChevronRight className="h-3.5 w-3.5" />
      </Link>

      <Dialog open={open} onOpenChange={(v) => (pending ? null : setOpen(v))}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Request account deletion?</DialogTitle>
            <DialogDescription>
              This sends a request to your warden and hostel owner. It does not sign you out, and nothing is erased
              until they have confirmed who you are.
            </DialogDescription>
          </DialogHeader>

          <ul className="-mt-1 flex flex-col gap-1.5 text-[13px] leading-relaxed text-charcoal">
            <li className="flex gap-2">
              <span aria-hidden className="text-red">
                &bull;
              </span>
              <span>
                <strong className="font-semibold text-navy">Erased:</strong> your name, phone, email, address, photo, ID
                proof, guardian contact, complaints, leave requests and visitor entries.
              </span>
            </li>
            <li className="flex gap-2">
              <span aria-hidden className="text-red">
                &bull;
              </span>
              <span>
                <strong className="font-semibold text-navy">Kept:</strong> fee and payment records, with your name
                removed, for as long as the hostel is legally required to keep its accounts.
              </span>
            </li>
            <li className="flex gap-2">
              <span aria-hidden className="text-red">
                &bull;
              </span>
              <span>
                <strong className="font-semibold text-navy">Afterwards:</strong> you will not be able to sign in, and
                you must settle any dues with the hostel separately.
              </span>
            </li>
          </ul>

          <Field
            label="Reason (optional)"
            htmlFor="deletion-reason"
            hint="Only your warden and hostel owner see this."
          >
            <Textarea
              id="deletion-reason"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              maxLength={500}
              rows={2}
              placeholder="e.g. I have moved out"
            />
          </Field>

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => setOpen(false)} disabled={pending}>
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              loading={pending}
              onClick={() => void run({ confirm: true, reason })}
            >
              Send request
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </GlassCard>
  );
}
