"use client";

import * as React from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Controller, useForm, type FieldPath } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { addYears } from "date-fns";
import { toast } from "sonner";
import { ArrowLeft, ArrowRight, BedDouble, Building2, Check, CreditCard, Info, Lightbulb, Pencil, Search, Sparkles, UserRound, UserRoundPlus, Users, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { UserAvatar } from "@/components/ui/avatar";
import { Field, FormGrid } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { Chip, StatusPill } from "@/components/shared/status-pill";
import { CredentialsDialog } from "@/components/shared/credentials-dialog";
import { useAction } from "@/hooks/use-action";
import { createOwnerAndHostel, type IssuedCredentials } from "@/lib/actions/super-admin";
import type { SaOwnerOption } from "@/lib/queries/super-admin";
import { createOwnerHostelSchema, type CreateOwnerHostelInput } from "@/lib/validators/super-admin";
import { cn, formatDate, formatINR, formatNumber, toISODate } from "@/lib/utils";
import { NumberStepper } from "./number-stepper";

const STEPS = [
  { key: "owner", label: "Owner", icon: UserRound },
  { key: "hostel", label: "Hostel", icon: Building2 },
  { key: "subscription", label: "Subscription", icon: CreditCard },
  { key: "review", label: "Review", icon: Check },
] as const;

type OwnerMode = "new" | "existing";

/** Flat view of the owner step (the zod schema is a discriminated union on `mode`). */
type OwnerFields = { mode: OwnerMode; name?: string; email?: string; phone?: string; ownerUserId?: string };
type OwnerErrors = Partial<Record<keyof OwnerFields, { message?: string }>>;

const OWNER_FIELDS: Record<OwnerMode, FieldPath<CreateOwnerHostelInput>[]> = {
  new: ["owner.name", "owner.email", "owner.phone"],
  existing: ["owner.ownerUserId"],
};

const STEP_FIELDS: FieldPath<CreateOwnerHostelInput>[][] = [
  [], // owner — depends on mode, see stepFields()
  ["hostel.name", "hostel.floors", "hostel.rooms", "hostel.bedsPerRoom", "hostel.address"],
  ["subscription.startDate", "subscription.endDate", "subscription.amount", "subscription.notes"],
  [],
];

function defaults(): CreateOwnerHostelInput {
  const today = new Date();
  return {
    // all owner fields are kept in the form so switching modes doesn't lose typed values; zod strips the unused ones
    owner: { mode: "new", name: "", email: "", phone: "", ownerUserId: "" } as unknown as CreateOwnerHostelInput["owner"],
    hostel: { name: "", floors: 1, rooms: 10, bedsPerRoom: 3, address: "" },
    subscription: { startDate: toISODate(today), endDate: toISODate(addYears(today, 1)), amount: Number.NaN, notes: "" },
  };
}

type WizardResult = { hostelId: string; credentials: IssuedCredentials | null };

/** SA-2 — 4-step "Create Owner & Hostel" wizard (new owner, or a second hostel for an existing owner — §4.1). */
export function CreateWizard({ owners }: { owners: SaOwnerOption[] }) {
  const router = useRouter();
  const [step, setStep] = React.useState(0);
  const [visited, setVisited] = React.useState(0); // furthest step reached
  const [result, setResult] = React.useState<WizardResult | null>(null);
  const [credsOpen, setCredsOpen] = React.useState(false);

  const form = useForm<CreateOwnerHostelInput>({
    resolver: zodResolver(createOwnerHostelSchema),
    defaultValues: defaults(),
    mode: "onTouched",
  });
  const { register, control, trigger, handleSubmit, watch, formState, reset, setValue, clearErrors } = form;
  const values = watch();
  const owner = values.owner as OwnerFields;
  const ownerMode: OwnerMode = owner.mode ?? "new";
  const ownerErrors = (formState.errors.owner ?? undefined) as unknown as OwnerErrors | undefined;
  const selectedOwner = ownerMode === "existing" ? owners.find((o) => o.id === owner.ownerUserId) ?? null : null;
  const ownerDisplayName = ownerMode === "existing" ? selectedOwner?.full_name ?? "" : owner.name ?? "";

  const stepFields = React.useCallback((i: number) => (i === 0 ? OWNER_FIELDS[ownerMode] : STEP_FIELDS[i]), [ownerMode]);

  const { run, pending } = useAction(createOwnerAndHostel, {
    refresh: false,
    onSuccess: (data) => {
      setResult(data);
      if (data.credentials) setCredsOpen(true);
    },
  });

  const goNext = async () => {
    const valid = await trigger(stepFields(step), { shouldFocus: true });
    if (!valid) return;
    const next = Math.min(step + 1, STEPS.length - 1);
    setStep(next);
    setVisited((v) => Math.max(v, next));
  };
  const goBack = () => setStep((s) => Math.max(0, s - 1));
  /** Stepper / summary jumps: backwards is free; forwards re-validates every step in between. */
  const jumpTo = async (i: number) => {
    if (i > visited) return;
    if (i <= step) {
      setStep(i);
      return;
    }
    for (let k = step; k < i; k++) {
      const valid = await trigger(stepFields(k), { shouldFocus: true });
      if (!valid) {
        setStep(k);
        return;
      }
    }
    setStep(i);
  };

  const onSubmit = handleSubmit(
    (data) => void run(data),
    (errors) => {
      const firstBad = (["owner", "hostel", "subscription"] as const).findIndex((k) => errors[k]);
      if (firstBad >= 0) setStep(firstBad);
      toast.error("Please fix the highlighted fields");
    },
  );

  const switchOwnerMode = (mode: OwnerMode) => {
    setValue("owner.mode" as FieldPath<CreateOwnerHostelInput>, mode, { shouldDirty: true });
    clearErrors("owner");
  };

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
            <Stepper current={step} visited={visited} onJump={(i) => void jumpTo(i)} done={!!result} />
          </div>

          {result ? (
            <SuccessPanel
              hostelId={result.hostelId}
              hostelName={values.hostel.name}
              ownerName={ownerDisplayName}
              existingOwner={!result.credentials}
              onAnother={startOver}
              onShowCreds={result.credentials ? () => setCredsOpen(true) : undefined}
            />
          ) : (
            <form onSubmit={onSubmit} noValidate className="flex flex-1 flex-col">
              <div className="flex-1 px-6 py-6 md:px-8">
                {step === 0 && (
                  <StepShell
                    title="Owner details"
                    description={
                      ownerMode === "new"
                        ? "The person who owns this hostel. They'll receive a login and set their own password on first sign-in."
                        : "Add a second hostel (with its own subscription) under an owner account that already exists. No new login is created — the owner switches hostels from their dashboard."
                    }
                  >
                    <div className="mb-5">
                      <SegmentedPills<OwnerMode>
                        ariaLabel="Owner account"
                        value={ownerMode}
                        onChange={switchOwnerMode}
                        options={[
                          {
                            value: "new",
                            label: (
                              <span className="inline-flex items-center gap-1.5">
                                <UserRoundPlus className="h-3.5 w-3.5" />
                                New owner
                              </span>
                            ),
                          },
                          {
                            value: "existing",
                            label: (
                              <span className="inline-flex items-center gap-1.5">
                                <Users className="h-3.5 w-3.5" />
                                Existing owner
                              </span>
                            ),
                            count: owners.length,
                          },
                        ]}
                      />
                    </div>

                    {ownerMode === "new" ? (
                      <FormGrid>
                        <Field label="Full name" htmlFor="owner-name" required error={ownerErrors?.name?.message} className="md:col-span-2">
                          <Input id="owner-name" placeholder="e.g. Priya Sharma" autoComplete="off" {...register("owner.name" as FieldPath<CreateOwnerHostelInput>)} aria-invalid={!!ownerErrors?.name} />
                        </Field>
                        <Field label="Email address" htmlFor="owner-email" required error={ownerErrors?.email?.message} hint="Used as the owner's login ID">
                          <Input id="owner-email" type="email" placeholder="owner@example.com" autoComplete="off" {...register("owner.email" as FieldPath<CreateOwnerHostelInput>)} aria-invalid={!!ownerErrors?.email} />
                        </Field>
                        <Field label="Phone number" htmlFor="owner-phone" required error={ownerErrors?.phone?.message}>
                          <Input id="owner-phone" type="tel" inputMode="tel" placeholder="98765 43210" autoComplete="off" {...register("owner.phone" as FieldPath<CreateOwnerHostelInput>)} aria-invalid={!!ownerErrors?.phone} />
                        </Field>
                      </FormGrid>
                    ) : (
                      <Controller
                        control={control}
                        name={"owner.ownerUserId" as FieldPath<CreateOwnerHostelInput>}
                        render={({ field, fieldState }) => (
                          <Field label="Owner account" htmlFor="owner-search" required error={fieldState.error?.message}>
                            <OwnerPicker owners={owners} value={typeof field.value === "string" ? field.value : ""} onChange={field.onChange} onBlur={field.onBlur} />
                          </Field>
                        )}
                      />
                    )}
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
                  <StepShell
                    title="Review & create"
                    description={
                      ownerMode === "new"
                        ? "Double-check everything. On submit we create the owner login, the hostel, its floors, rooms and beds, and the subscription."
                        : "Double-check everything. On submit we create the hostel, its floors, rooms and beds, and the subscription under the selected owner."
                    }
                  >
                    <div className="space-y-4">
                      <ReviewSection title="Owner" onEdit={() => setStep(0)}>
                        {ownerMode === "existing" ? (
                          <>
                            <ReviewRow label="Account" value={selectedOwner ? <span className="inline-flex items-center gap-2">{selectedOwner.full_name}<Chip tone="navy">Existing</Chip></span> : "—"} />
                            <ReviewRow label="Email (login)" value={selectedOwner?.email ?? "—"} />
                            <ReviewRow label="Phone" value={selectedOwner?.phone ?? "—"} />
                            <ReviewRow label="Hostels today" value={selectedOwner ? `${formatNumber(selectedOwner.hostel_count)} → ${formatNumber(selectedOwner.hostel_count + 1)} after this` : "—"} />
                          </>
                        ) : (
                          <>
                            <ReviewRow label="Name" value={owner.name} />
                            <ReviewRow label="Email (login)" value={owner.email} />
                            <ReviewRow label="Phone" value={owner.phone} />
                          </>
                        )}
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
                      {ownerMode === "new" ? (
                        <div className="flex items-start gap-2.5 rounded-control bg-sand-soft px-3.5 py-3 text-[13px] text-sand-deep">
                          <Sparkles className="mt-0.5 h-4 w-4 shrink-0" />
                          <p>A temporary password will be generated and shown <span className="font-semibold">once</span> after creation. Copy it before closing the dialog.</p>
                        </div>
                      ) : (
                        <div className="flex items-start gap-2.5 rounded-control bg-navy/5 px-3.5 py-3 text-[13px] text-charcoal">
                          <Info className="mt-0.5 h-4 w-4 shrink-0 text-navy/70" />
                          <p>No new login is created. The owner keeps their existing password and will see a hostel switcher in their dashboard header.</p>
                        </div>
                      )}
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
                    {ownerMode === "new" ? "Create owner & hostel" : "Create hostel"}
                  </Button>
                )}
              </div>
            </form>
          )}
        </GlassCard>

        {/* ── Summary panel ── */}
        <div className="space-y-4">
          <SummaryCard title="Owner details" icon={UserRound} saved={visited > 0 || !!result} active={step === 0 && !result} onEdit={!result && visited > 0 ? () => void jumpTo(0) : undefined}>
            {ownerMode === "existing" ? (
              <>
                <SummaryRow label="Account" value={selectedOwner ? `${selectedOwner.full_name} (existing)` : ""} />
                <SummaryRow label="Email" value={selectedOwner?.email ?? ""} />
                <SummaryRow label="Phone" value={selectedOwner?.phone ?? ""} />
              </>
            ) : (
              <>
                <SummaryRow label="Full name" value={owner.name ?? ""} />
                <SummaryRow label="Email" value={owner.email ?? ""} />
                <SummaryRow label="Phone" value={owner.phone ?? ""} />
              </>
            )}
          </SummaryCard>
          <SummaryCard title="Hostel details" icon={Building2} saved={visited > 1 || !!result} active={step === 1 && !result} onEdit={!result && visited > 1 ? () => void jumpTo(1) : undefined}>
            <SummaryRow label="Name" value={values.hostel.name} />
            <SummaryRow label="Layout" value={values.hostel.name ? `${values.hostel.floors} fl · ${values.hostel.rooms} rooms · ${values.hostel.bedsPerRoom} beds/room` : ""} />
            <SummaryRow label="Beds" value={values.hostel.name ? formatNumber(totalBeds) : ""} />
          </SummaryCard>
          <SummaryCard title="Subscription" icon={CreditCard} saved={visited > 2 || !!result} active={step === 2 && !result} onEdit={!result && visited > 2 ? () => void jumpTo(2) : undefined}>
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
          result?.credentials
            ? { title: "Owner account created", name: result.credentials.name, loginId: result.credentials.loginId, password: result.credentials.password, role: "Owner" }
            : null
        }
      />
    </>
  );
}

/* ───────────────────────── pieces ───────────────────────── */

/** Searchable owner list (existing-owner mode) — filter box + radio-style rows. */
function OwnerPicker({
  owners,
  value,
  onChange,
  onBlur,
}: {
  owners: SaOwnerOption[];
  value: string;
  onChange: (id: string) => void;
  onBlur?: () => void;
}) {
  const [query, setQuery] = React.useState("");
  const q = query.trim().toLowerCase();
  const filtered = React.useMemo(
    () => (q ? owners.filter((o) => [o.full_name, o.email ?? "", o.phone ?? ""].some((v) => v.toLowerCase().includes(q))) : owners),
    [owners, q],
  );
  const selected = owners.find((o) => o.id === value) ?? null;

  if (owners.length === 0) {
    return (
      <div className="rounded-control border border-dashed border-line bg-white/40 px-4 py-6 text-center text-sm text-muted">
        No owner accounts yet — switch to <span className="font-medium text-navy">New owner</span> to create the first one.
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
        <Input
          id="owner-search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onBlur={onBlur}
          placeholder="Search owners by name, email or phone…"
          className="pl-9 pr-9"
          autoComplete="off"
        />
        {query ? (
          <button type="button" aria-label="Clear search" onClick={() => setQuery("")} className="absolute right-2.5 top-1/2 -translate-y-1/2 rounded-full p-1 text-muted hover:bg-navy/5 hover:text-navy">
            <X className="h-3.5 w-3.5" />
          </button>
        ) : null}
      </div>
      <div role="radiogroup" aria-label="Owner accounts" className="max-h-72 overflow-y-auto rounded-control border border-line/80 bg-white/50">
        {filtered.length === 0 ? (
          <div className="px-4 py-6 text-center text-sm text-muted">No owners match “{query}”.</div>
        ) : (
          filtered.map((o) => {
            const active = o.id === value;
            const inactive = o.status !== "active";
            return (
              <button
                key={o.id}
                type="button"
                role="radio"
                aria-checked={active}
                disabled={inactive}
                onClick={() => onChange(o.id)}
                className={cn(
                  "flex w-full items-center gap-3 border-b border-line/60 px-3.5 py-2.5 text-left transition-colors last:border-b-0",
                  active ? "bg-navy/5" : "hover:bg-white/80",
                  inactive && "cursor-not-allowed opacity-50",
                )}
              >
                <UserAvatar name={o.full_name} size="sm" />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="truncate text-sm font-medium text-navy">{o.full_name}</span>
                    {inactive ? <StatusPill status={o.status} size="sm" /> : null}
                  </div>
                  <div className="truncate text-xs text-muted">{[o.email, o.phone].filter(Boolean).join(" · ") || "—"}</div>
                </div>
                <Chip tone={o.hostel_count > 0 ? "teal" : "muted"}>
                  {formatNumber(o.hostel_count)} hostel{o.hostel_count === 1 ? "" : "s"}
                </Chip>
                <span className={cn("flex h-5 w-5 shrink-0 items-center justify-center rounded-full border", active ? "border-navy bg-navy text-white" : "border-line bg-white")}>
                  {active ? <Check className="h-3 w-3" /> : null}
                </span>
              </button>
            );
          })
        )}
      </div>
      {selected ? (
        <p className="text-xs text-muted">
          Selected <span className="font-medium text-charcoal">{selected.full_name}</span>
          {selected.email ? ` (${selected.email})` : ""} — currently {formatNumber(selected.hostel_count)} hostel{selected.hostel_count === 1 ? "" : "s"}.
        </p>
      ) : null}
    </div>
  );
}

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
  existingOwner,
  onAnother,
  onShowCreds,
}: {
  hostelId: string;
  hostelName: string;
  ownerName: string;
  existingOwner: boolean;
  onAnother: () => void;
  onShowCreds?: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 py-14 text-center md:px-8">
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-teal-soft text-teal">
        <BedDouble className="h-6 w-6" />
      </div>
      <h2 className="text-[20px] font-semibold text-navy">{hostelName} is ready</h2>
      <p className="mt-1 max-w-md text-sm text-muted">
        {existingOwner ? (
          <>
            The hostel, its floors, rooms, beds and the first subscription period were created under{" "}
            <span className="font-medium text-charcoal">{ownerName}</span>&apos;s existing account. They can switch to it from their dashboard header.
          </>
        ) : (
          <>
            The owner account for <span className="font-medium text-charcoal">{ownerName}</span> was created along with the hostel, its floors, rooms, beds and the first
            subscription period.
          </>
        )}
      </p>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-2">
        <Button asChild>
          <Link href={`/super-admin/hostels/${hostelId}`}>View hostel</Link>
        </Button>
        {onShowCreds ? (
          <Button variant="secondary" onClick={onShowCreds}>
            Show credentials again
          </Button>
        ) : null}
        <Button variant="ghost" onClick={onAnother}>
          Create another
        </Button>
      </div>
      {onShowCreds ? <p className="mt-4 text-xs text-muted">Credentials are only available in this session — once you leave this page they cannot be viewed again.</p> : null}
    </div>
  );
}
