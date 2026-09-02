"use client";

import * as React from "react";
import { useActionState } from "react";
import { Eye, EyeOff, Lock } from "lucide-react";
import { changePassword } from "@/lib/actions/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { ActionResult } from "@/lib/types";
import { passwordStrength } from "@/lib/auth/password";
import { cn } from "@/lib/utils";

const barTone = ["bg-stone", "bg-red", "bg-sand", "bg-teal", "bg-teal"];

export function ChangePasswordForm({ forced }: { forced: boolean }) {
  const [state, action, pending] = useActionState<ActionResult | null, FormData>(changePassword, null);
  const [pw, setPw] = React.useState("");
  const [show, setShow] = React.useState(false);
  const strength = passwordStrength(pw);
  const fieldErrors = state && !state.ok ? state.fieldErrors ?? {} : {};
  const error = state && !state.ok ? state.error : null;

  return (
    <form action={action} className="flex flex-col gap-5" noValidate>
      {/* ASKED ON BOTH PATHS SINCE 2026-09-01. This field used to be hidden for a forced
          change, on the reasoning that the temporary password had just been used to sign in.
          Supabase Auth disagrees: this project has
          GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD on, and
          PUT /auth/v1/user {password} answers 400 current_password_required without it —
          measured against the live project. Every account here is routed to this page before it
          can reach anything else, so a hidden field meant nobody could finish a first login.

          The LABEL is what keeps it from reading as a bug: on a forced change the reader is
          holding a temporary password somebody handed them, and "Current password" sends them
          hunting for one they never chose. What `forced` still decides is reauthentication,
          in changePassword() — and that decision is made from the profile row, not from here. */}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="currentPassword">{forced ? "Temporary password" : "Current password"}</Label>
        <div className="relative">
          <Lock className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            id="currentPassword"
            name="currentPassword"
            type="password"
            autoComplete="current-password"
            className="pl-10"
            aria-invalid={!!fieldErrors.currentPassword}
            required
            autoFocus
          />
        </div>
        {forced ? (
          <p className="text-xs text-muted">The one you were given, to confirm it is you.</p>
        ) : null}
        {fieldErrors.currentPassword?.[0] ? <p className="text-xs text-red">{fieldErrors.currentPassword[0]}</p> : null}
      </div>

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
            value={pw}
            onChange={(e) => setPw(e.target.value)}
            aria-invalid={!!fieldErrors.password}
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
        {/* strength hint */}
        <div className="mt-1 flex items-center gap-2">
          <div className="flex flex-1 gap-1">
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className={cn("h-1 flex-1 rounded-full transition-colors", i <= strength.score ? barTone[strength.score] : "bg-stone")} />
            ))}
          </div>
          <span className="w-16 text-right text-[11px] text-muted">{pw ? strength.label : "8+ chars"}</span>
        </div>
        {fieldErrors.password?.[0] ? <p className="text-xs text-red">{fieldErrors.password[0]}</p> : null}
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
            aria-invalid={!!fieldErrors.confirm}
            required
          />
        </div>
        {fieldErrors.confirm?.[0] ? <p className="text-xs text-red">{fieldErrors.confirm[0]}</p> : null}
      </div>

      <div aria-live="polite" className={cn("min-h-[20px] text-sm text-red", !error && "hidden")}>
        {error}
      </div>

      <Button type="submit" size="xl" loading={pending}>
        {forced ? "Save & continue" : "Update password"}
      </Button>
    </form>
  );
}
