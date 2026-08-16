"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, Copy, ShieldCheck, ShieldOff, Smartphone } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { confirmTotpEnrollment, disableTotp, startTotpEnrollment, type MfaStatus } from "@/lib/actions/mfa";

/**
 * Two-factor authentication management (any role).
 * Enrol: show QR + secret → enter first code. Disable: enter current code (reauth).
 */
export function MfaManage({ status, required }: { status: MfaStatus; required: boolean }) {
  const router = useRouter();
  const [pending, start] = React.useTransition();
  const [enroll, setEnroll] = React.useState<{ factorId: string; qrCode: string; secret: string } | null>(null);
  const [code, setCode] = React.useState("");
  const [error, setError] = React.useState<string | null>(null);

  function begin() {
    setError(null);
    start(async () => {
      const res = await startTotpEnrollment();
      if (!res.ok) return setError(res.error);
      setEnroll(res.data);
      setCode("");
    });
  }

  function confirm() {
    if (!enroll) return;
    setError(null);
    start(async () => {
      const res = await confirmTotpEnrollment({ factorId: enroll.factorId, code });
      if (!res.ok) return setError(res.error);
      toast.success(res.message ?? "Two-factor authentication is on");
      setEnroll(null);
      setCode("");
      router.refresh();
    });
  }

  function disable() {
    if (!status.factorId) return;
    setError(null);
    start(async () => {
      const res = await disableTotp({ factorId: status.factorId!, code });
      if (!res.ok) return setError(res.error);
      toast.success(res.message ?? "Two-factor authentication turned off");
      setCode("");
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <GlassCard>
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-start gap-3">
            <div className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-full ${status.enrolled ? "bg-teal-soft text-teal" : "bg-sand-soft text-sand-deep"}`}>
              {status.enrolled ? <ShieldCheck className="h-5 w-5" /> : <ShieldOff className="h-5 w-5" />}
            </div>
            <div>
              <h2 className="text-card-title font-semibold text-navy">Authenticator app (TOTP)</h2>
              <p className="mt-0.5 text-[13px] text-muted">
                {status.enrolled
                  ? "Every sign-in asks for a 6-digit code from your authenticator app."
                  : "Add a second step to sign-in using Google Authenticator, Authy, 1Password or any TOTP app."}
              </p>
            </div>
          </div>
          <StatusPill tone={status.enrolled ? "teal" : "sand"} label={status.enrolled ? "On" : "Off"} />
        </div>

        {required && !status.enrolled ? (
          <p className="mt-4 rounded-control bg-red-soft px-3 py-2 text-[13px] text-red">
            Two-factor authentication is required for your role. Set it up to continue using HostelPro.
          </p>
        ) : null}

        {/* ── Enrol ── */}
        {!status.enrolled && !enroll ? (
          <div className="mt-5">
            <Button onClick={begin} loading={pending}>
              <Smartphone /> Set up two-factor authentication
            </Button>
          </div>
        ) : null}

        {!status.enrolled && enroll ? (
          <div className="mt-5 grid gap-5 md:grid-cols-[200px_1fr]">
            <div className="rounded-control border border-line bg-white p-3">
              {/* SVG data URI from Supabase — safe to render as an <img> */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={enroll.qrCode} alt="Scan this QR code with your authenticator app" className="h-auto w-full" />
            </div>
            <div className="space-y-4">
              <ol className="list-decimal space-y-1 pl-5 text-sm text-charcoal">
                <li>Open your authenticator app and scan the QR code.</li>
                <li>
                  Or enter this key manually:
                  <div className="mt-1 flex items-center gap-2">
                    <code className="rounded-[8px] bg-stone px-2 py-1 font-mono text-xs tracking-wider text-navy">{enroll.secret}</code>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Copy key"
                      onClick={() => navigator.clipboard.writeText(enroll.secret).then(() => toast.success("Key copied")).catch(() => {})}
                    >
                      <Copy />
                    </Button>
                  </div>
                </li>
                <li>Enter the 6-digit code the app shows to confirm.</li>
              </ol>
              <div className="flex flex-col gap-1.5">
                <Label htmlFor="mfa-code">Code</Label>
                <div className="flex gap-2">
                  <Input id="mfa-code" inputMode="numeric" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} placeholder="123456" className="max-w-[160px] tracking-[0.3em] font-semibold tabular" />
                  <Button onClick={confirm} loading={pending} disabled={code.length !== 6}>
                    <CheckCircle2 /> Confirm
                  </Button>
                  <Button variant="ghost" onClick={() => setEnroll(null)} disabled={pending}>
                    Cancel
                  </Button>
                </div>
              </div>
            </div>
          </div>
        ) : null}

        {/* ── Disable ── */}
        {status.enrolled && !required ? (
          <div className="mt-5 flex flex-col gap-1.5">
            <Label htmlFor="mfa-off">Enter your current code to turn 2FA off</Label>
            <div className="flex gap-2">
              <Input id="mfa-off" inputMode="numeric" maxLength={6} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))} placeholder="123456" className="max-w-[160px] tracking-[0.3em] font-semibold tabular" />
              <Button variant="outline-red" onClick={disable} loading={pending} disabled={code.length !== 6}>
                <ShieldOff /> Turn off
              </Button>
            </div>
          </div>
        ) : null}

        {error ? (
          <p role="alert" className="mt-3 text-sm text-red">
            {error}
          </p>
        ) : null}
      </GlassCard>

      <p className="text-[12px] text-muted">
        Lost your device? Ask your administrator to reset your password — that does not remove 2FA; contact HostelPro support to
        remove a lost authenticator.
      </p>
    </div>
  );
}
