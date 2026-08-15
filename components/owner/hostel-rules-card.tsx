"use client";

import * as React from "react";
import { ScrollText } from "lucide-react";
import { updateHostelRules } from "@/lib/actions/owner";
import { useAction } from "@/hooks/use-action";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";

/** Small "Hostel rules" editor — students read this on their Hostel info screen (§6.5). */
export function HostelRulesCard({ rules, writable }: { rules: string | null; writable: boolean }) {
  const [value, setValue] = React.useState(rules ?? "");
  const [saved, setSaved] = React.useState(rules ?? "");
  const { run, pending } = useAction(updateHostelRules, { onSuccess: () => setSaved(value) });
  const dirty = value.trim() !== saved.trim();

  return (
    <GlassCard as="section" className="flex h-full flex-col">
      <GlassCardHeader
        title={
          <span className="inline-flex items-center gap-2">
            <ScrollText className="h-4 w-4 text-teal" /> Hostel rules
          </span>
        }
        description="Shown to every student under Hostel info. One rule per line works best."
      />
      <Textarea
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder={"e.g.\n• Gate closes at 10:30 PM\n• No outside guests after 8 PM\n• Keep common areas clean"}
        rows={8}
        maxLength={6000}
        disabled={!writable || pending}
        className="min-h-[180px] flex-1"
      />
      <div className="mt-3 flex items-center justify-between gap-3">
        <span className="text-xs text-muted tabular">{value.length}/6000</span>
        <div className="flex items-center gap-2">
          {dirty ? (
            <Button variant="ghost" size="sm" disabled={pending} onClick={() => setValue(saved)}>
              Discard
            </Button>
          ) : null}
          <Button size="sm" disabled={!writable || !dirty} loading={pending} onClick={() => run({ rules: value })}>
            Save rules
          </Button>
        </div>
      </div>
    </GlassCard>
  );
}
