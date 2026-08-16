"use client";

import * as React from "react";
import { useActionState } from "react";
import { KeyRound } from "lucide-react";
import { verifyTotpChallenge } from "@/lib/actions/mfa";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { ActionResult } from "@/lib/types";
import { cn } from "@/lib/utils";

/** Login step-up: 6-digit TOTP code (A-2 style card). */
export function MfaChallengeForm({ next }: { next?: string }) {
  const [state, action, pending] = useActionState<ActionResult | null, FormData>(verifyTotpChallenge, null);
  const error = state && !state.ok ? state.error : null;
  return (
    <form action={action} className="flex flex-col gap-5" noValidate>
      {next ? <input type="hidden" name="next" value={next} /> : null}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="code">Authentication code</Label>
        <div className="relative">
          <KeyRound className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            id="code"
            name="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            maxLength={6}
            placeholder="123456"
            className="pl-10 tracking-[0.3em] text-lg font-semibold tabular"
            required
            autoFocus
          />
        </div>
      </div>
      <div aria-live="polite" className={cn("min-h-[20px] text-sm text-red", !error && "hidden")}>
        {error}
      </div>
      <Button type="submit" size="xl" loading={pending}>
        Verify &amp; continue
      </Button>
    </form>
  );
}
