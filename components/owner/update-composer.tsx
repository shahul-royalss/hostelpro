"use client";

import * as React from "react";
import { Send } from "lucide-react";
import type { AnnouncementAudience } from "@/lib/types";
import { createAnnouncement } from "@/lib/actions/owner";
import { useAction } from "@/hooks/use-action";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { Field } from "@/components/shared/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";

const AUDIENCE_OPTIONS: { value: AnnouncementAudience; label: string; hint: string }[] = [
  { value: "all", label: "Everyone", hint: "Manager, warden and every student" },
  { value: "manager", label: "Manager", hint: "Only the manager" },
  { value: "warden", label: "Warden", hint: "Only the warden" },
  { value: "students", label: "Students", hint: "Every active student" },
];

/** OW-3 left card — "Send an update" composer. */
export function UpdateComposer({ writable, reach }: { writable: boolean; reach: Record<AnnouncementAudience, number> }) {
  const [title, setTitle] = React.useState("");
  const [body, setBody] = React.useState("");
  const [audience, setAudience] = React.useState<AnnouncementAudience>("all");
  const [errors, setErrors] = React.useState<Record<string, string[]>>({});

  const { run, pending } = useAction(createAnnouncement, {
    onSuccess: () => {
      setTitle("");
      setBody("");
      setAudience("all");
      setErrors({});
    },
  });

  const canSend = writable && title.trim().length >= 3 && body.trim().length >= 3;
  const hint = AUDIENCE_OPTIONS.find((o) => o.value === audience)?.hint ?? "";
  const recipients = reach[audience];

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSend) return;
    const res = await run({ title: title.trim(), body: body.trim(), audience });
    if (!res.ok && res.fieldErrors) setErrors(res.fieldErrors);
  }

  return (
    <GlassCard as="section">
      <GlassCardHeader title="Send an update" description="Broadcast an announcement to your hostel. It appears in every recipient's app and notification bell." />
      <form onSubmit={submit} className="space-y-5">
        <Field label="Title" htmlFor="update-title" required error={errors.title?.[0]}>
          <Input
            id="update-title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g., Water supply maintenance on Sunday"
            maxLength={120}
            disabled={!writable || pending}
          />
        </Field>

        <Field label="Audience" hint={`${hint} · ${recipients} recipient${recipients === 1 ? "" : "s"}`}>
          <SegmentedPills<AnnouncementAudience>
            ariaLabel="Audience"
            value={audience}
            onChange={setAudience}
            options={AUDIENCE_OPTIONS.map((o) => ({ value: o.value, label: o.label }))}
          />
        </Field>

        <Field label="Message" htmlFor="update-body" required error={errors.body?.[0]} hint={`${body.length}/4000`}>
          <Textarea
            id="update-body"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Type your message here…"
            rows={9}
            maxLength={4000}
            disabled={!writable || pending}
            className="min-h-[200px]"
          />
        </Field>

        <div className="flex flex-col-reverse items-stretch gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-xs text-muted">{writable ? "Sent updates cannot be edited — remove and resend if needed." : "Read-only — renew the subscription to send updates."}</p>
          <Button type="submit" size="lg" disabled={!canSend} loading={pending} className="sm:min-w-[160px]">
            {!pending ? <Send /> : null}
            Send update
          </Button>
        </div>
      </form>
    </GlassCard>
  );
}
