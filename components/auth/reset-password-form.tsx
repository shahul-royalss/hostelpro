"use client";

import * as React from "react";
import { useActionState } from "react";
import { Check, Eye, EyeOff, Lock } from "lucide-react";
import { completePasswordReset } from "@/lib/actions/password-reset";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { ActionResult } from "@/lib/types";
import { cn } from "@/lib/utils";

/**
 * `minLength` arrives as a prop instead of being imported, and that is deliberate twice over.
 *
 * 1. ACCURACY. The number is PASSWORD_MIN_LENGTH from lib/auth/password, read by the server
 *    component that renders this. One source of truth, no constant restated in two files that
 *    can drift apart.
 * 2. WEIGHT. Importing that module from a CLIENT component drags `randomInt` from node:crypto
 *    with it, and webpack answers by shipping crypto-browserify to the browser - a 325 kB
 *    chunk. That is measurable today: /change-password imports it and weighs 131 kB against
 *    /login's 1.94 kB, for one strength label. This page keeps the number and leaves the
 *    polyfill behind.
 *
 * The two character rules below mirror changePasswordSchema (lib/validators/auth.ts), which is
 * what the server actually enforces. They are hints; that schema is the policy.
 */
export function ResetPasswordForm({ minLength }: { minLength: number }) {
  const [state, action, pending] = useActionState<ActionResult | null, FormData>(completePasswordReset, null);
  const [password, setPassword] = React.useState("");
  const [confirm, setConfirm] = React.useState("");
  const [show, setShow] = React.useState(false);

  const fieldErrors = state && !state.ok ? (state.fieldErrors ?? {}) : {};
  const error = state && !state.ok ? state.error : null;

  const rules = [
    { label: `At least ${minLength} characters`, met: password.length >= minLength },
    { label: "One letter", met: /[A-Za-z]/.test(password) },
    { label: "One number", met: /\d/.test(password) },
  ];

  return (
    <form action={action} className="flex flex-col gap-5" noValidate>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="password">New password</Label>
        <div className="relative">
          <Lock className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            id="password"
            name="password"
            type={show ? "text" : "password"}
            autoComplete="new-password"
            className="pl-10 pr-10"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            aria-invalid={!!fieldErrors.password}
            aria-describedby="password-rules"
            required
            autoFocus
          />
          <button
            type="button"
            aria-label={show ? "Hide password" : "Show password"}
            onClick={() => setShow((s) => !s)}
            // 44px hit target: this sits inside a 40px field on a 360px-wide phone, where an
            // icon-sized tap area is a coin toss.
            className="absolute right-1.5 top-1/2 flex h-11 w-11 -translate-y-1/2 items-center justify-center rounded-full text-muted hover:text-navy"
          >
            {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        </div>

        {/* The requirements, ticked live. Stated up front rather than revealed by a rejection. */}
        <ul id="password-rules" className="mt-1 flex flex-wrap gap-x-3 gap-y-1">
          {rules.map((rule) => (
            <li
              key={rule.label}
              className={cn(
                "inline-flex items-center gap-1 text-caption-1 transition-colors",
                rule.met ? "text-ink-teal" : "text-label-tertiary",
              )}
            >
              <Check className={cn("h-3 w-3 shrink-0", !rule.met && "opacity-30")} strokeWidth={3} />
              {rule.label}
            </li>
          ))}
        </ul>
        {fieldErrors.password?.[0] ? <p className="text-caption-1 text-ink-red">{fieldErrors.password[0]}</p> : null}
      </div>

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="confirm">Confirm password</Label>
        <div className="relative">
          <Lock className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            id="confirm"
            name="confirm"
            type={show ? "text" : "password"}
            autoComplete="new-password"
            className="pl-10"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            aria-invalid={!!fieldErrors.confirm}
            required
          />
        </div>
        {fieldErrors.confirm?.[0] ? <p className="text-caption-1 text-ink-red">{fieldErrors.confirm[0]}</p> : null}
      </div>

      <div aria-live="polite" className={cn("min-h-[20px] text-sm text-ink-red", !error && "hidden")}>
        {error}
      </div>

      <Button type="submit" size="xl" loading={pending}>
        Set password &amp; sign in
      </Button>

      <p className="text-center text-caption-1 text-label-tertiary">
        Signing in anywhere else will be ended.
      </p>
    </form>
  );
}
