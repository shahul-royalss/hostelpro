"use client";

import * as React from "react";
import { useActionState } from "react";
import Link from "next/link";
import { ArrowRight, CheckCircle2, Mail, ShieldQuestion } from "lucide-react";
import { requestPasswordReset, type ResetRequestOutcome } from "@/lib/actions/password-reset";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { ActionResult } from "@/lib/types";
import { cn } from "@/lib/utils";

type State = ActionResult<ResetRequestOutcome> | null;

export function ForgotPasswordForm() {
  const [state, action, pending] = useActionState<State, FormData>(requestPasswordReset, null);

  // Success replaces the form rather than sitting under it. On a 360px phone an unchanged form
  // with a green line beneath it reads as "nothing happened, try again" - which is how a reset
  // page turns into a mail bomb aimed at its own user.
  if (state?.ok) return <Outcome outcome={state.data} />;

  const error = state && !state.ok ? state.error : null;

  return (
    <form action={action} className="flex flex-col gap-5" noValidate>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="identifier">Email or phone</Label>
        <div className="relative">
          <Mail className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            id="identifier"
            name="identifier"
            type="text"
            inputMode="email"
            autoComplete="username"
            placeholder="you@hostel.com or 98765 43210"
            className="pl-10"
            aria-describedby="identifier-hint"
            required
            autoFocus
          />
        </div>
        <p id="identifier-hint" className="text-footnote text-label-secondary">
          Use whatever you normally sign in with.
        </p>
      </div>

      <div aria-live="polite" className={cn("min-h-[20px] text-sm text-ink-red", !error && "hidden")}>
        {error}
      </div>

      <Button type="submit" size="xl" loading={pending}>
        Continue {!pending && <ArrowRight />}
      </Button>

      <Link
        href="/login"
        className="rounded-control py-1 text-center text-footnote font-medium text-ink-navy underline-offset-4 hover:underline"
      >
        Back to sign in
      </Link>
    </form>
  );
}

function Outcome({ outcome }: { outcome: ResetRequestOutcome }) {
  const isEmail = outcome.channel === "email";

  return (
    // role="status" so the swap is announced: the visible change is off-screen for anyone
    // using a screen reader, and this is the only feedback the flow gives.
    <div role="status" className="flex flex-col gap-5 text-center">
      <div
        className={cn(
          "mx-auto flex h-12 w-12 items-center justify-center rounded-control",
          isEmail ? "bg-teal-soft text-ink-teal" : "bg-sand-soft text-ink-sand",
        )}
      >
        {isEmail ? (
          <CheckCircle2 className="h-6 w-6" strokeWidth={1.75} />
        ) : (
          <ShieldQuestion className="h-6 w-6" strokeWidth={1.75} />
        )}
      </div>

      {isEmail ? (
        <div className="flex flex-col gap-2">
          <h2 className="text-title-3 text-label">Check your email</h2>
          {/*
            "If an account exists" is load-bearing, not hedging. The same sentence is returned
            for an address the app has never seen, which is what keeps this form from telling a
            stranger who banks here.
          */}
          <p className="text-subhead text-label-secondary">
            If an account exists for <span className="font-medium text-label">{outcome.sentTo}</span>, a reset link is
            on its way. It expires in 60 minutes.
          </p>
          <p className="text-footnote text-label-tertiary">
            Nothing after a few minutes? Look in spam, then ask your hostel owner to reset it for you.
          </p>
          <p className="text-footnote text-label-tertiary">
            Open the link on this device - it will not work in a different browser.
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          <h2 className="text-title-3 text-label">Your warden resets this one</h2>
          {/*
            Students sign in with a phone number, which the app maps to an address at a domain
            that does not exist. There is no inbox to mail. Saying so plainly - and saying whose
            job it is instead - is the whole point of this branch; a fake "check your email"
            would leave them waiting for something that can never arrive.

            The warden is named by ROLE, never by name and number. Looking the phone number up to
            print a specific warden would answer "is this number a resident here, and of which
            hostel" for anyone who typed it, about people whose address is the thing most worth
            protecting.
          */}
          <p className="text-subhead text-label-secondary">
            Student accounts sign in with a phone number, not an email address, so there is no inbox for us to send a
            link to.
          </p>
          <p className="text-subhead text-label-secondary">
            Ask your <span className="font-medium text-label">warden</span> or the hostel office to set a new password
            for you. They can do it from their own account, and it takes a minute.
          </p>
          <p className="text-footnote text-label-tertiary">Bring an ID - they should check who is asking.</p>
        </div>
      )}

      <Button asChild size="xl" variant={isEmail ? "secondary" : "default"}>
        <Link href="/login">Back to sign in</Link>
      </Button>
    </div>
  );
}
