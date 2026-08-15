"use client";

import * as React from "react";
import { useActionState } from "react";
import { ArrowRight, Eye, EyeOff, Lock, Mail } from "lucide-react";
import { signIn } from "@/lib/actions/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { ActionResult } from "@/lib/types";
import { cn } from "@/lib/utils";

export function LoginForm({ next, initialError }: { next?: string; initialError?: string | null }) {
  const [state, action, pending] = useActionState<ActionResult | null, FormData>(signIn, null);
  const [show, setShow] = React.useState(false);
  const error = state && !state.ok ? state.error : initialError;

  return (
    <form action={action} className="flex flex-col gap-5" noValidate>
      {next ? <input type="hidden" name="next" value={next} /> : null}

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
            required
            autoFocus
          />
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <div className="flex items-center justify-between">
          <Label htmlFor="password">Password</Label>
          <span className="text-caption normal-case tracking-normal text-teal" title="Ask your administrator to regenerate your password">
            Forgot password?
          </span>
        </div>
        <div className="relative">
          <Lock className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            id="password"
            name="password"
            type={show ? "text" : "password"}
            autoComplete="current-password"
            placeholder="••••••••"
            className="pl-10 pr-10"
            required
          />
          <button
            type="button"
            aria-label={show ? "Hide password" : "Show password"}
            onClick={() => setShow((s) => !s)}
            className="absolute right-3 top-1/2 -translate-y-1/2 rounded-full p-1 text-muted hover:text-navy"
          >
            {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        </div>
      </div>

      <div aria-live="polite" className={cn("min-h-[20px] text-sm text-red", !error && "hidden")}>
        {error}
      </div>

      <Button type="submit" size="xl" loading={pending} className="mt-1">
        Sign in {!pending && <ArrowRight />}
      </Button>
    </form>
  );
}
