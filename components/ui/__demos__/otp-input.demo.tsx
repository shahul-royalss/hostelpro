"use client";

/**
 * Usage examples for <OtpInput />. Not routed and not imported by the app.
 *
 * WHERE THIS BELONGS IN THIS CODEBASE
 * -----------------------------------
 * `components/auth/mfa-challenge-form.tsx` (rendered by `app/mfa/page.tsx`) currently uses
 * a plain <Input> with a KeyRound icon and `tracking-[0.3em]` to fake the code look. That
 * file is outside this task's paths, so it has been left alone. The swap is the block
 * marked "MFA DROP-IN" below: same `name="code"`, same server action, same `ActionResult`
 * error, and it gains a real invalid state and auto-submit on the sixth digit.
 */

import * as React from "react";
import { OtpInput } from "@/components/ui/otp-input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";

/** Uncontrolled, inside a form — the value posts as `code`. */
export function OtpInputBasicDemo() {
  return (
    <form className="flex max-w-sm flex-col gap-5 p-8">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="code">Authentication code</Label>
        <OtpInput id="code" name="code" autoFocus required />
      </div>
      <Button type="submit" size="xl">
        Verify &amp; continue
      </Button>
    </form>
  );
}

/** Controlled, with an error state and auto-submit. */
export function OtpInputControlledDemo() {
  const [code, setCode] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);
  const [attempt, setAttempt] = React.useState(0);

  const verify = React.useCallback((value: string) => {
    setAttempt((n) => n + 1);
    setError(value === "123456" ? null : "That code is not right. Try the current one.");
  }, []);

  return (
    <div className="flex max-w-sm flex-col gap-3 p-8">
      <OtpInput
        name="code"
        value={code}
        onChange={(next) => {
          setCode(next);
          if (error) setError(null);
        }}
        onComplete={verify}
        invalid={error !== null}
        // Same error twice in a row still replays the shake.
        shakeKey={attempt}
        aria-describedby="otp-error"
      />
      <p id="otp-error" aria-live="polite" className="min-h-[20px] text-sm text-red">
        {error}
      </p>
    </div>
  );
}

/** Four slots, e.g. a shorter SMS code. */
export function OtpInputShortDemo() {
  return <OtpInput length={4} name="pin" className="max-w-[14rem]" />;
}

/*
 * MFA DROP-IN — components/auth/mfa-challenge-form.tsx, replacing the <Input> block:
 *
 *   <div className="flex flex-col gap-1.5">
 *     <Label htmlFor="code">Authentication code</Label>
 *     <OtpInput
 *       id="code"
 *       name="code"
 *       required
 *       autoFocus
 *       invalid={error !== null}
 *       aria-describedby="mfa-error"
 *     />
 *   </div>
 *
 * The existing `aria-live` error <div> gets `id="mfa-error"`; nothing else in that file,
 * in `lib/actions/mfa.ts`, or in `app/mfa/page.tsx` has to change — the field still posts
 * one `code` value and still validates `\d{6}` natively.
 */
