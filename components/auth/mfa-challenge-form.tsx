"use client";

import * as React from "react";
import { useActionState } from "react";
import { verifyTotpChallenge } from "@/lib/actions/mfa";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { OtpInput } from "@/components/ui/otp-input";
import type { ActionResult } from "@/lib/types";
import { cn } from "@/lib/utils";

/**
 * Login step-up: 6-digit TOTP code.
 *
 * The code lives in React state and rides to the server action in a hidden field, because the
 * slots are six separate inputs and a Server Action reads FormData, not component state.
 *
 * Submitting on the sixth digit is the point of the component: a TOTP code is fixed-length, so
 * asking someone to type six digits and then reach for a button is a step the machine can take
 * for them. The button stays for keyboard and assistive-technology users, and for the case where
 * auto-submit already fired and failed.
 */
export function MfaChallengeForm({ next }: { next?: string }) {
  const [state, action, pending] = useActionState<ActionResult | null, FormData>(verifyTotpChallenge, null);
  const error = state && !state.ok ? state.error : null;

  const [code, setCode] = React.useState("");
  const formRef = React.useRef<HTMLFormElement>(null);
  // Changing this replays the shake when the SAME error comes back twice — otherwise the second
  // wrong code looks identical to the first and the field appears not to have responded.
  const [attempt, setAttempt] = React.useState(0);

  React.useEffect(() => {
    if (error) setAttempt((n) => n + 1);
  }, [error]);

  const submit = React.useCallback(() => {
    if (pending) return;
    formRef.current?.requestSubmit();
  }, [pending]);

  return (
    <form ref={formRef} action={action} className="flex flex-col gap-5" noValidate>
      {next ? <input type="hidden" name="next" value={next} /> : null}
      <input type="hidden" name="code" value={code} />

      <div className="flex flex-col items-center gap-3">
        <Label htmlFor="otp-0" className="self-start">
          Authentication code
        </Label>
        <OtpInput
          id="otp-0"
          length={6}
          value={code}
          onChange={setCode}
          onComplete={submit}
          invalid={Boolean(error)}
          shakeKey={attempt}
          disabled={pending}
          autoFocus
          aria-label="Six-digit authentication code"
        />
      </div>

      <div aria-live="polite" className={cn("min-h-[20px] text-center text-sm text-red", !error && "hidden")}>
        {error}
      </div>

      <Button type="submit" size="xl" loading={pending} disabled={code.length < 6}>
        Verify &amp; continue
      </Button>
    </form>
  );
}
