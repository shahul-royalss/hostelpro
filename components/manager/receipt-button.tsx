"use client";

import * as React from "react";
import { ExternalLink, FileText, Loader2, Paperclip } from "lucide-react";
import { toast } from "sonner";
import { getReceiptUrl } from "@/lib/actions/manager";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

/**
 * Receipt icon in the expenses table. Resolves a signed URL on demand
 * (via the server, through RLS) and previews it in a dialog.
 */
export function ReceiptButton({ expenseId, hasReceipt, label }: { expenseId: string; hasReceipt: boolean; label?: string }) {
  const [open, setOpen] = React.useState(false);
  const [loading, setLoading] = React.useState(false);
  const [receipt, setReceipt] = React.useState<{ url: string; isPdf: boolean } | null>(null);

  if (!hasReceipt) {
    return (
      <span className="inline-flex h-8 w-8 items-center justify-center text-muted/40" aria-label="No receipt">
        <Paperclip className="h-4 w-4" />
      </span>
    );
  }

  const openReceipt = async () => {
    setOpen(true);
    if (receipt) return;
    setLoading(true);
    const res = await getReceiptUrl({ id: expenseId });
    setLoading(false);
    if (res.ok) setReceipt(res.data);
    else {
      toast.error(res.error);
      setOpen(false);
    }
  };

  return (
    <>
      <Button type="button" variant="ghost" size="icon-sm" onClick={openReceipt} aria-label="View receipt" className="text-teal hover:text-teal">
        <FileText className="h-4 w-4" />
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-xl">
          <DialogHeader>
            <DialogTitle>Receipt</DialogTitle>
            {label ? <DialogDescription>{label}</DialogDescription> : null}
          </DialogHeader>
          <div className={cn("flex min-h-[200px] items-center justify-center overflow-hidden rounded-control bg-stone/60")}>
            {loading || !receipt ? (
              <Loader2 className="h-6 w-6 animate-spin text-navy/50" />
            ) : receipt.isPdf ? (
              <div className="flex flex-col items-center gap-3 py-10 text-center">
                <FileText className="h-8 w-8 text-navy/60" strokeWidth={1.5} />
                <p className="text-sm text-muted">This receipt is a PDF.</p>
                <Button asChild>
                  <a href={receipt.url} target="_blank" rel="noopener noreferrer">
                    <ExternalLink /> Open PDF
                  </a>
                </Button>
              </div>
            ) : (
              // eslint-disable-next-line @next/next/no-img-element -- signed storage URL, not a static asset
              <img src={receipt.url} alt="Expense receipt" className="max-h-[70vh] w-full object-contain" />
            )}
          </div>
          {receipt && !receipt.isPdf ? (
            <a href={receipt.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 self-end text-sm font-medium text-navy hover:underline">
              <ExternalLink className="h-4 w-4" /> Open full size
            </a>
          ) : null}
        </DialogContent>
      </Dialog>
    </>
  );
}
