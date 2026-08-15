"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Controller, useForm, type FieldPath } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { addYears } from "date-fns";
import { ArrowLeft, ArrowRight, BedDouble, Building2, Check, CreditCard, Info, Lightbulb, Minus, Pencil, Plus, Sparkles, UserRound } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Field, FormGrid } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { CredentialsDialog } from "@/components/shared/credentials-dialog";
import { useAction } from "@/hooks/use-action";
import { createOwnerAndHostel } from "@/lib/actions/super-admin";
import { createOwnerHostelSchema, type CreateOwnerHostelInput } from "@/lib/validators/super-admin";
import { cn, formatDate, formatINR, formatNumber, toISODate } from "@/lib/utils";

const STEPS = [
  { key: "owner", label: "Owner", icon: UserRound },
  { key: "hostel", label: "Hostel", icon: Building2 },
  { key: "subscription", label: "Subscription", icon: CreditCard },
  { key: "review", label: "Review", icon: Check },
] as const;

const STEP_FIELDS: FieldPath<CreateOwnerHostelInput>[][] = [
  ["owner.name", "owner.email", "owner.phone"],
  ["hostel.name", "hostel.floors", "hostel.rooms", "hostel.bedsPerRoom", "hostel.address"],
  ["subscription.startDate", "subscription.endDate", "subscription.amount", "subscription.notes"],
  [],
];

function defaults(): CreateOwnerHostelInput {
  const today = new Date();
  return {
    owner: { name: "", email: "", phone: "" },
    hostel: { name: "", floors: 1, rooms: 10, bedsPerRoom: 3, address: "" },
    subscription: { startDate: toISODate(today), endDate: toISODate(addYears(today, 1)), amount: Number.NaN, notes: "" },
  };
}

/** SA-2 — 4-step "Create Owner & Hostel" wizard. */
export function CreateWizard() {
  const router = useRouter();
  const [step, setStep] = React.useState(0);
  const [visited, setVisited] = React.useState(0); // furthest step reached
  const [result, setResult] = React.useState<{ hostelId: string; credentials: { name: string; loginId: string; password: string } } | null>(null);
  const [credsOpen, setCredsOpen] = React.useState(false);

  const form = useForm<CreateOwnerHostelInput>({
    resolver: zodResolver(createOwnerHostelSchema),
    defaultValues: defaults(),
    mode: "onTouched",
  });
  const { register, control, trigger, handleSubmit, watch, formState, reset } = form;
  const values = watch();

  const { run, pending } = useAction(createOwnerAndHostel, {
    refresh: false,
    onSuccess: (data) => {
      setResult(data);
      setCredsOpen(true);
    },
  });

  const goNext = async () => {
    const valid = await trigger(STEP_FIELDS[step], { shouldFocus: true });
    if (!valid) return;
    const next = Math.min(step + 1, STEPS.length - 1);
    setStep(next);
    setVisited((v) => Math.max(v, next));
  };
  const goBack = () => setStep((s) => Math.max(0, s - 1));
  const jumpTo = (i: number) => {
    if (i <= visited) setStep(i);
  };

  const onSubmit = handleSubmit((data) => void run(data));

  const totalBeds = (Number(values.hostel.rooms) || 0) * (Number(values.hostel.bedsPerRoom) || 0);

  const startOver = () => {
    reset(defaults());
    setResult(null);
    setStep(0);
    setVisited(0);
  };

  return (
    <>
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_320px]">
        {/* ── Main wizard card ── */}
        <GlassCard className="flex flex-col p-0" padded={false}>
          <div className="border-b border-line/70 px-6 pt-6 pb-5 md:px-8">
            <Stepper current={step} visited={visited} onJump={jumpTo} done={!!result} />
          </div>

          {result ? (
            <SuccessPanel hostelId={result.hostelId} hostelName={values.hostel.name} ownerName={values.owner.name} onAnother={startOver} onShowCreds={() => setCredsOpen(true)} />
          ) : (
            <form onSubmit={onSubmit} noValidate className="flex flex-1 flex-col">
              <div className="flex-1 px-6 py-6 md:px-8">
                {step === 0 && (
                  <StepShell title="Owner details" description="The person who owns this hostel. They'll receive a login and set their own password on first sign-in.">
                    <FormGrid>
                      <Field label="Full name" htmlFor="owner-name" required error={formState.errors.owner?.name?.message} className="md:col-span-2">
                        <Input id="owner-name" placeholder="e.g. Priya Sharma" autoComplete="off" {...register("owner.name")} aria-invalid={!!formState.errors.owner?.name} />
                      </Field>
                      <Field label="Email address" htmlFor="owner-email" required error={formState.errors.owner?.email?.message} hint="Used as the owner's login ID">
                        <Input id="owner-email" type="email" placeholder="owner@example.com" autoComplete="off" {...register("owner.email")} aria-invalid={!!formState.errors.owner?.email} />
                      </Field>
                      <Field label="Phone number" htmlFor="owner-phone" required error={formState.errors.owner?.phone?.message}>
                        <Input id="owner-phone" type="tel" inputMode="tel" placeholder="98765 43210" autoComplete="off" {...register("owner.phone")} aria-invalid={!!formState.errors.owner?.phone} />
                      </Field>
                    </FormGrid>
                  </StepShell>
                )}

                {step === 1 && (
                  <StepShell title="Hostel details" description="Configure the physical layout of the new property.">
                    <div className="space-y-5">
                      <Field label="Hostel name" htmlFor="hostel-name" required error={formState.errors.hostel?.name?.message}>
                        <Input id="hostel-name" placeholder="e.g. Sunny Days PG, Koramangala" autoComplete="off" {...register("hostel.name")} aria-invalid={!!formState.errors.hostel?.name} />
                      </Field>
                      <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
                        <Controller
                          control={control}
                          name="hostel.floors"
                          render={({ field, fieldState }) => (
                            <Field label="Number of floors" htmlFor="hostel-floors" required error={fieldState.error?.message}>
                              <NumberStepper id="hostel-floors" value={field.value} onChange={field.onChange} onBlur={field.onBlur} min={1} max={50} />
                            </Field>
                          )}
                        />
                        <Controller
                          control={control}
                          name="hostel.rooms"
                          render={({ field, fieldState }) => (
                            <Field label="Number of rooms" htmlFor="hostel-rooms" required error={fieldState.error?.message}>
                              <NumberStepper id="hostel-rooms" value={field.value} onChange={field.onChange} onBlur={field.onBlur} min={1} max={5000} />
                            </Field>
                          )}
                        />
                        <Controller
                          control={control}
                          name="hostel.bedsPerRoom"
                          render={({ field, fieldState }) => (
                            <Field label="Beds per room" htmlFor="hostel-beds" required error={fieldState.error?.message}>
                              <NumberStepper id="hostel-beds" value={field.value} onChange={field.onChange} onBlur={field.onBlur} min={1} max={12} />
                            </Field>
                          )}
                        />
                      </div>
                      <Field label="Address" htmlFor="hostel-address" error={formState.errors.hostel?.address?.message}>
                        <Textarea id="hostel-address" placeholder="Street, area, city, PIN" rows={3} {...register("hostel.address")} />
                      </Field>
                      <div className="flex items-start gap-2.5 rounded-control bg-navy/5 px-3.5 py-3 text-[13px] text-charcoal">
                        <Info className="mt-0.5 h-4 w-4 shrink-0 text-navy/70" />
                        <p>
                          Rooms and beds will be auto-generated ({values.hostel.bedsPerRoom || 3} beds per room). Rooms are spread evenly across floors and numbered
                          101, 102… 201, 202…. That&apos;s <span className="font-semibold text-navy">{formatNumber(totalBeds)}</span> beds in total. The warden can fine-tune
                          room numbers and beds later.
                        </p>
                      </div>
                    </div>
                  </StepShell>
                )}

                {step === 2 && (
                  <StepShell title="Subscription" description="One subscription per hostel. The hostel becomes read-only after the end date until it's renewed.">
                    <FormGrid>
                      <Field label="Start date" htmlFor="sub-start" required error={formState.errors.subscription?.startDate?.message}>
                        <Input id="sub-start" type="date" {...register("subscription.startDate")} aria-invalid={!!formState.errors.subscription?.startDate} />
                      </Field>
                      <Field label="End date" htmlFor="sub-end" required error={formState.errors.subscription?.endDate?.message}>
                        <Input id="sub-end" type="date" min={values.subscription.startDate} {...register("subscription.endDate")} aria-invalid={!!formState.errors.subscription?.endDate} />
                      </Field>
                      <Field label="Amount (₹)" htmlFor="sub-amount" required error={formState.errors.subscription?.amount?.message}>
                        <Input id="sub-amount" type="number" inputMode="decimal" min={0} step="1" placeholder="e.g. 24000" {...register("subscription.amount", { valueAsNumber: true })} aria-invalid={!!formState.errors.subscription?.amount} />
                      </Field>
                      <Field label="Notes" htmlFor="sub-notes" hint="Optional — plan name, payment reference…">
                        <Input id="sub-notes" placeholder="e.g. Annual plan, paid via UPI" {...register("subscription.notes")} />
                      </Field>
                    </FormGrid>
                  </StepShell>
                )}

                {step === 3 && (
                  <StepShell title="Review & create" description="Double-check everything. On submit we create the owner login, the hostel, its floors, rooms and beds, and the subscription.">
                    <div className="space-y-4">
                      <ReviewSection title="Owner" onEdit={() => setStep(0)}>
                        <ReviewRow label="Name" value={values.owner.name} />
                        <ReviewRow label="Email (login)" value={values.owner.email} />
                        <ReviewRow label="Phone" value={values.owner.phone} />
                      </ReviewSection>
                      <ReviewSection title="Hostel" onEdit={() => setStep(1)}>
                        <ReviewRow label="Name" value={values.hostel.name} />
                        <ReviewRow label="Structure" value={`${values.hostel.floors} floor${values.hostel.floors === 1 ? "" : "s"} · ${values.hostel.rooms} rooms · ${values.hostel.bedsPerRoom} beds/room`} />
                        <ReviewRow label="Total beds" value={formatNumber(totalBeds)} />
                        <ReviewRow label="Address" value={values.hostel.address || "—"} />
                      </ReviewSection>
                      <ReviewSection title="Subscription" onEdit={() => setStep(2)}>
                        <ReviewRow label="Period" value={`${formatDate(values.subscription.startDate)} → ${formatDate(values.subscription.endDate)}`} />
                        <ReviewRow label="Amount" value={Number.isFinite(values.subscription.amount) ? formatINR(values.subscription.amount) : "—"} />
                        <ReviewRow label="Notes" value={values.subscription.notes || "—"} />
                      </ReviewSection>
                      <div className="flex items-start gap-2.5 rounded-control bg-sand-soft px-3.5 py-3 text-[13px] text-sand-deep">
                        <Sparkles className="mt-0.5 h-4 w-4 shrink-0" />
                        <p>A temporary password will be generated and shown <span className="font-semibold">once</span> after creation. Copy it before closing the dialog.</p>
                      </div>
                    </div>
                  </StepShell>
                )}
              </div>

              <div className="flex items-center justify-between gap-3 border-t border-line/70 px-6 py-4 md:px-8">
                <Button type="button" variant="ghost" onClick={goBack} disabled={step === 0 || pending}>
                  <ArrowLeft />
                  Back
                </Button>
                {step < STEPS.length - 1 ? (
                  <Button type="button" onClick={goNext}>
                    Continue
                    <ArrowRight />
                  </Button>
                ) : (
                  <Button type="submit" loading={pending}>
                    <Check />
                    Create owner &amp; hostel
                  </Button>
                )}
              </div>
            </form>
          )}
        </GlassCard>

        {/* ── Summary panel ── */}
        <div className="space-y-4">
          <SummaryCard title="Owner details" icon={UserRound} saved={visited > 0 || !!result} active={step === 0 && !result} onEdit={!result && visited > 0 ? () => setStep(0) : undefined}>
            <SummaryRow label="Full name" value={values.owner.name} />
            <SummaryRow label="Email" value={values.owner.email} />
            <SummaryRow label="Phone" value={values.owner.phone} />
          </SummaryCard>
          <SummaryCard title="Hostel details" icon={Building2} saved={visited > 1 || !!result} active={step === 1 && !result} onEdit={!result && visited > 1 ? () => setStep(1) : undefined}>
            <SummaryRow label="Name" value={values.hostel.name} />
            <SummaryRow label="Layout" value={values.hostel.name ? `${values.hostel.floors} fl · ${values.hostel.rooms} rooms · ${values.hostel.bedsPerRoom} beds/room` : ""} />
            <SummaryRow label="Beds" value={values.hostel.name ? formatNumber(totalBeds) : ""} />
          </SummaryCard>
          <SummaryCard title="Subscription" icon={CreditCard} saved={visited > 2 || !!result} active={step === 2 && !result} onEdit={!result && visited > 2 ? () => setStep(2) : undefined}>
            <SummaryRow label="Period" value={visited > 1 || step >= 2 ? `${formatDate(values.subscription.startDate)} → ${formatDate(values.subscription.endDate)}` : ""} />
            <SummaryRow label="Amount" value={Number.isFinite(values.subscription.amount) ? formatINR(values.subscription.amount) : ""} />
          </SummaryCard>
          <GlassCard className="p-5">
            <div className="mb-2 flex items-center gap-2 text-navy">
              <Lightbulb className="h-4 w-4 text-teal" />
              <span className="text-sm font-semibold">Pro tip</span>
            </div>
            <p className="text-[13px] leading-relaxed text-muted">
              Accurate floor and room counts let the auto-generator create realistic room numbering (101, 102, 201…), saving the warden time later. Only a
              Super Admin can change floor and room counts afterwards.
            </p>
          </GlassCard>
        </div>
      </div>

      <CredentialsDialog
        open={credsOpen}
        onOpenChange={(v) => {
          setCredsOpen(v);
          if (!v && result) router.prefetch(`/super-admin/hostels/${result.hostelId}`);
        }}
        credentials={
          result
            ? { title: "Owner account created", name: result.credentials.name, loginId: result.credentials.loginId, password: result.credentials.password, role: "Owner" }
            : null
        }
      />
    </>
  );
}

/* ───────────────────────── pieces ───────────────────────── */

function Stepper({ current, visited, onJump, done }: { current: number; visited: number; onJump: (i: number) => void; done: boolean }) {
  return (
    <ol className="flex items-center" aria-label="Wizard progress">
      {STEPS.map((s, i) => {
        const complete = done || i < current;
        const active = !done && i === current;
        const reachable = i <= visited && !done;
        return (
          <li key={s.key} className={cn("flex items-center", i < STEPS.length - 1 && "flex-1")}>
            <button
              type="button"
              onClick={() => onJump(i)}
              disabled={!reachable}
              aria-current={active ? "step" : undefined}
              className={cn("group flex flex-col items-center gap-1.5 disabled:cursor-default", reachable && "cursor-pointer")}
            >
              <span
                className={cn(
                  "flex h-8 w-8 items-center justify-center rounded-full border text-xs font-semibold transition-colors",
                  complete && "border-navy bg-navy text-white",
                  active && "border-navy bg-white text-navy ring-4 ring-navy/10",
                  !complete && !active && "border-line bg-white/60 text-muted",
                )}
              >
                {complete ? <Check className="h-4 w-4" /> : i + 1}
              </span>
              <span className={cn("text-[11px] font-medium uppercase tracking-[0.05em]", active || complete ? "text-navy" : "text-muted")}>{s.label}</span>
            </button>
            {i < STEPS.length - 1 && <div className={cn("mx-3 mb-5 h-px flex-1 transition-colors", i < current || done ? "bg-navy" : "bg-line")} />}
          </li>
        );
      })}
    </ol>
  );
}

function StepShell({ title, description, children }: { title: string; description: string; children: React.ReactNode }) {
  return (
    <div>
      <h2 className="text-[18px] font-semibold text-navy">{title}</h2>
      <p className="mb-6 mt-1 text-sm text-muted">{description}</p>
      {children}
    </div>
  );
}

/** −/+ stepper input (SA-2 "Number of floors / rooms"). */
function NumberStepper({
  id,
  value,
  onChange,
  onBlur,
  min,
  max,
}: {
  id: string;
  value: number;
  onChange: (v: number) => void;
  onBlur?: () => void;
  min: number;
  max: number;
}) {
  const n = Number.isFinite(value) ? value : min;
  const clamp = (v: number) => Math.min(max, Math.max(min, v));
  return (
    <div className="flex h-10 items-stretch overflow-hidden rounded-control border border-input bg-white/70 focus-within:border-navy focus-within:ring-1 focus-within:ring-navy">
      <button
        type="button"
        aria-label="Decrease"
        className="flex w-10 shrink-0 items-center justify-center text-navy transition-colors hover:bg-navy/5 disabled:opacity-40"
        onClick={() => onChange(clamp(n - 1))}
        disabled={n <= min}
      >
        <Minus className="h-4 w-4" />
      </button>
      <input
        id={id}
        type="number"
        inputMode="numeric"
        min={min}
        max={max}
        value={Number.isFinite(value) ? value : ""}
        onChange={(e) => onChange(e.target.value === "" ? Number.NaN : Number(e.target.value))}
        onBlur={() => {
          if (!Number.isFinite(value)) onChange(min);
          else onChange(clamp(Math.round(value)));
          onBlur?.();
        }}
        className="w-full min-w-0 border-x border-input bg-transparent text-center text-sm font-semibold text-navy tabular outline-none [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
      />
      <button
        type="button"
        aria-label="Increase"
        className="flex w-10 shrink-0 items-center justify-center text-navy transition-colors hover:bg-navy/5 disabled:opacity-40"
        onClick={() => onChange(clamp(n + 1))}
        disabled={n >= max}
      >
        <Plus className="h-4 w-4" />
      </button>
    </div>
  );
}

function ReviewSection({ title, onEdit, children }: { title: string; onEdit: () => void; children: React.ReactNode }) {
  return (
    <section className="rounded-card border border-line/80 bg-white/50 p-4">
      <div className="mb-2 flex items-center justify-between">
        <h3 className="label-caps !text-navy">{title}</h3>
        <Button type="button" variant="ghost" size="sm" onClick={onEdit}>
          <Pencil />
          Edit
        </Button>
      </div>
      <dl className="grid grid-cols-1 gap-x-6 gap-y-1.5 sm:grid-cols-2">{children}</dl>
    </section>
  );
}

function ReviewRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-baseline justify-between gap-3 text-sm sm:block">
      <dt className="text-xs text-muted">{label}</dt>
      <dd className="truncate font-medium text-charcoal">{value || "—"}</dd>
    </div>
  );
}

function SummaryCard({
  title,
  icon: Icon,
  saved,
  active,
  onEdit,
  children,
}: {
  title: string;
  icon: React.ComponentType<{ className?: string }>;
  saved: boolean;
  active: boolean;
  onEdit?: () => void;
  children: React.ReactNode;
}) {
  return (
    <GlassCard className={cn("p-5 transition-shadow", active && "ring-1 ring-navy/20")}>
      <div className="mb-3 flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-navy">
          <Icon className="h-4 w-4 text-navy/70" />
          <span className="text-sm font-semibold">{title}</span>
        </div>
        {saved ? <StatusPill tone="teal" label="Saved" size="sm" /> : active ? <StatusPill tone="navy" label="In progress" size="sm" /> : <StatusPill tone="muted" label="Pending" size="sm" />}
      </div>
      <dl className="space-y-2">{children}</dl>
      {onEdit ? (
        <button type="button" onClick={onEdit} className="mt-3 inline-flex items-center gap-1.5 text-xs font-medium text-navy hover:underline">
          <Pencil className="h-3 w-3" />
          Edit {title.toLowerCase()}
        </button>
      ) : null}
    </GlassCard>
  );
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="label-caps">{label}</dt>
      <dd className={cn("truncate text-sm", value ? "font-medium text-charcoal" : "text-muted/60")}>{value || "—"}</dd>
    </div>
  );
}

function SuccessPanel({
  hostelId,
  hostelName,
  ownerName,
  onAnother,
  onShowCreds,
}: {
  hostelId: string;
  hostelName: string;
  ownerName: string;
  onAnother: () => void;
  onShowCreds: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 py-14 text-center md:px-8">
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-teal-soft text-teal">
        <BedDouble className="h-6 w-6" />
      </div>
      <h2 className="text-[20px] font-semibold text-navy">{hostelName} is ready</h2>
      <p className="mt-1 max-w-md text-sm text-muted">
        The owner account for <span className="font-medium text-charcoal">{ownerName}</span> was created along with the hostel, its floors, rooms, beds and the first
        subscription period.
      </p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-2">
        <Button asChild>
          <Link href={`/super-admin/hostels/${hostelId}`}>View hostel</Link>
        </Button>
        <Button variant="secondary" onClick={onShowCreds}>
          Show credentials again
        </Button>
        <Button variant="ghost" onClick={onAnother}>
          Create another
        </Button>
      </div>
      <p className="mt-4 text-xs text-muted">Credentials are only available in this session — once you leave this page they cannot be viewed again.</p>
    </div>
  );
}
