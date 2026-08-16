"use client";

import * as React from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useForm, type FieldPath } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { BedDouble, Camera, Check, FileText, ImagePlus, Lock, Phone, User, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Progress } from "@/components/ui/misc";
import { Field } from "@/components/shared/field";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { StatusPill } from "@/components/shared/status-pill";
import { CredentialsDialog, type Credentials } from "@/components/shared/credentials-dialog";
import { fetchFreeBeds, registerStudent } from "@/lib/actions/warden";
import { ID_PROOF_TYPES, registerFormSchema, type RegisterFormValues } from "@/lib/validators/warden";
import type { FreeBed } from "@/lib/queries/warden";
import type { FloorRow, RoomOccupancyRow } from "@/lib/types";
import { cn, formatDate, formatINR, toISODate } from "@/lib/utils";
import { StickyBar } from "./sticky-bar";

const STEPS = ["Personal", "Guardian", "ID proof", "Room & fee", "Review"] as const;
const STEP_FIELDS: FieldPath<RegisterFormValues>[][] = [
  ["fullName", "phone", "email", "dateOfJoining"],
  ["guardianName", "guardianPhone", "permanentAddress"],
  ["idProofType"],
  ["bedId", "monthlyFee"],
  [],
];

const ACCEPT_IMAGE = "image/jpeg,image/png,image/webp";
const ACCEPT_DOC = "image/jpeg,image/png,image/webp,application/pdf";
/**
 * Both files travel in ONE server-action request, and Next's
 * serverActions.bodySizeLimit is 8 MB — so cap each file at 3.5 MB and the pair
 * at 7.5 MB (leaving headroom for the text fields + multipart framing).
 */
const MAX_FILE_BYTES = 3.5 * 1024 * 1024;
const MAX_TOTAL_BYTES = 7.5 * 1024 * 1024;
const MAX_FILE_LABEL = "3.5 MB";

export function RegisterStudentForm({
  floors,
  rooms,
  initialFreeBeds,
  initialBedId,
  defaultFee,
  writable,
}: {
  floors: FloorRow[];
  rooms: RoomOccupancyRow[];
  /** Free beds of the deep-linked (?bed=) room only; every other room loads on tap. */
  initialFreeBeds: FreeBed[];
  initialBedId?: string;
  defaultFee?: number;
  writable: boolean;
}) {
  const router = useRouter();
  const preselected = React.useMemo(() => initialFreeBeds.find((b) => b.bed_id === initialBedId) ?? null, [initialFreeBeds, initialBedId]);
  // room_id → free beds (fetched lazily per room so a 10,000-bed hostel never ships its whole bed list)
  const [freeByRoom, setFreeByRoom] = React.useState<Map<string, FreeBed[]>>(() => {
    const m = new Map<string, FreeBed[]>();
    for (const b of initialFreeBeds) (m.get(b.room_id) ?? m.set(b.room_id, []).get(b.room_id)!).push(b);
    return m;
  });
  const [bedsLoading, setBedsLoading] = React.useState<string | null>(null);

  const [step, setStep] = React.useState(0);
  const [pending, startTransition] = React.useTransition();
  const [photo, setPhoto] = React.useState<File | null>(null);
  const [idProof, setIdProof] = React.useState<File | null>(null);
  const [floor, setFloor] = React.useState<number | null>(preselected?.floor_number ?? floors[0]?.floor_number ?? null);
  const [roomId, setRoomId] = React.useState<string | null>(preselected?.room_id ?? null);
  const [credentials, setCredentials] = React.useState<Credentials | null>(null);
  const [doneRoomId, setDoneRoomId] = React.useState<string | null>(null);

  const form = useForm<RegisterFormValues>({
    resolver: zodResolver(registerFormSchema),
    mode: "onTouched",
    defaultValues: {
      fullName: "",
      phone: "",
      email: "",
      dateOfJoining: toISODate(),
      guardianName: "",
      guardianPhone: "",
      permanentAddress: "",
      idProofType: undefined,
      bedId: preselected?.bed_id ?? "",
      monthlyFee: defaultFee,
    },
  });
  const { register, formState, watch, setValue, trigger, setError, handleSubmit } = form;
  const errors = formState.errors;
  const values = watch();

  const roomsOnFloor = React.useMemo(() => rooms.filter((r) => floor === null || r.floor_number === floor), [rooms, floor]);
  const selectedRoom = rooms.find((r) => r.room_id === roomId) ?? null;
  const roomBeds = roomId ? freeByRoom.get(roomId) : undefined;
  const selectedBed = React.useMemo(() => {
    for (const beds of freeByRoom.values()) {
      const hit = beds.find((b) => b.bed_id === values.bedId);
      if (hit) return hit;
    }
    return null;
  }, [freeByRoom, values.bedId]);

  const loadRoomBeds = React.useCallback(
    async (id: string, force = false) => {
      if (!force && freeByRoom.has(id)) return;
      setBedsLoading(id);
      const res = await fetchFreeBeds({ roomId: id });
      setBedsLoading((cur) => (cur === id ? null : cur));
      if (!res.ok) {
        toast.error(res.error);
        return;
      }
      setFreeByRoom((m) => new Map(m).set(id, res.data));
    },
    [freeByRoom],
  );

  const progress = ((step + 1) / STEPS.length) * 100;

  async function next() {
    const valid = await trigger(STEP_FIELDS[step], { shouldFocus: true });
    if (!valid) return;
    if (step === 2 && !idProof) {
      toast.error("Upload the ID proof to continue.");
      return;
    }
    setStep((s) => Math.min(STEPS.length - 1, s + 1));
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  function back() {
    if (step === 0) router.push("/warden");
    else setStep((s) => s - 1);
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  const submit = handleSubmit((data) => {
    if (!idProof) {
      toast.error("Upload the ID proof to continue.");
      setStep(2);
      return;
    }
    if ((photo?.size ?? 0) + idProof.size > MAX_TOTAL_BYTES) {
      toast.error(`Photo and ID proof together must be under ${Math.floor(MAX_TOTAL_BYTES / (1024 * 1024))} MB. Use smaller files.`);
      setStep(2);
      return;
    }
    const fd = new FormData();
    for (const [k, v] of Object.entries(data)) if (v !== undefined && v !== null) fd.set(k, String(v));
    if (photo) fd.set("photo", photo);
    fd.set("idProof", idProof);
    startTransition(async () => {
      const res = await registerStudent(fd);
      if (!res.ok) {
        toast.error(res.error);
        if (res.fieldErrors) {
          for (const [k, msgs] of Object.entries(res.fieldErrors)) {
            setError(k as FieldPath<RegisterFormValues>, { message: msgs[0] });
          }
          const idx = STEP_FIELDS.findIndex((fields) => fields.some((f) => res.fieldErrors?.[f]));
          if (idx >= 0) setStep(idx);
        }
        return;
      }
      toast.success("Student registered");
      setDoneRoomId(res.data.roomId);
      setCredentials({ ...res.data.credentials, role: "Student", loginLabel: "Phone (login)", title: "Student registered" });
    });
  });

  return (
    <div className="-mt-2">
      {/* Slim progress bar + stepper (sticky under the app bar) */}
      <div className="sticky top-16 z-30 -mx-4 bg-ivory/85 px-4 pb-3 pt-1 backdrop-blur-md">
        <Progress value={progress} className="h-1" aria-label={`Step ${step + 1} of ${STEPS.length}`} />
        <ol className="no-scrollbar mt-2.5 flex gap-4 overflow-x-auto text-[11px] font-semibold uppercase tracking-wider">
          {STEPS.map((label, i) => (
            <li key={label} className={cn("flex shrink-0 items-center gap-1.5", i === step ? "text-navy" : i < step ? "text-teal" : "text-muted/70")}>
              <span
                className={cn(
                  "flex h-4 w-4 items-center justify-center rounded-full text-[9px]",
                  i === step ? "bg-navy text-white" : i < step ? "bg-teal-soft text-teal" : "border border-line",
                )}
              >
                {i < step ? <Check className="h-2.5 w-2.5" /> : i + 1}
              </span>
              {label}
            </li>
          ))}
        </ol>
      </div>

      {!writable && (
        <div className="mb-4 flex items-start gap-2 rounded-control bg-sand-soft px-3 py-2.5 text-[13px] text-sand-deep">
          <Lock className="mt-0.5 h-4 w-4 shrink-0" />
          Registration is disabled while the hostel is read-only.
        </div>
      )}

      <form onSubmit={submit} className="pb-24" noValidate>
        {step === 0 && (
          <StepCard title="Personal details" description="The phone number becomes the student's login.">
            <Field label="Full name" htmlFor="fullName" required error={errors.fullName?.message}>
              <Input id="fullName" autoComplete="name" placeholder="e.g. Aarav Sharma" aria-invalid={!!errors.fullName} {...register("fullName")} />
            </Field>
            <Field label="Phone (login)" htmlFor="phone" required error={errors.phone?.message} hint="10 digits — used to sign in">
              <Input id="phone" type="tel" inputMode="numeric" autoComplete="tel" placeholder="98765 43210" aria-invalid={!!errors.phone} {...register("phone")} />
            </Field>
            <Field label="Email (optional)" htmlFor="email" error={errors.email?.message}>
              <Input id="email" type="email" inputMode="email" autoComplete="email" placeholder="name@example.com" aria-invalid={!!errors.email} {...register("email")} />
            </Field>
            <Field label="Date of joining" htmlFor="dateOfJoining" required error={errors.dateOfJoining?.message}>
              <Input id="dateOfJoining" type="date" aria-invalid={!!errors.dateOfJoining} {...register("dateOfJoining")} />
            </Field>
          </StepCard>
        )}

        {step === 1 && (
          <StepCard title="Guardian details" description="Emergency contact and permanent address.">
            <Field label="Guardian name" htmlFor="guardianName" required error={errors.guardianName?.message}>
              <Input id="guardianName" placeholder="Full name" aria-invalid={!!errors.guardianName} {...register("guardianName")} />
            </Field>
            <Field label="Guardian phone" htmlFor="guardianPhone" required error={errors.guardianPhone?.message}>
              <Input id="guardianPhone" type="tel" inputMode="numeric" placeholder="98765 43210" aria-invalid={!!errors.guardianPhone} {...register("guardianPhone")} />
            </Field>
            <Field label="Permanent address" htmlFor="permanentAddress" required error={errors.permanentAddress?.message}>
              <Textarea id="permanentAddress" rows={4} placeholder="Street, city, state, PIN" aria-invalid={!!errors.permanentAddress} {...register("permanentAddress")} />
            </Field>
          </StepCard>
        )}

        {step === 2 && (
          <StepCard title="ID proof & photo" description={`Upload a clear image or PDF of the ID (max ${MAX_FILE_LABEL} per file).`}>
            <Field label="ID proof type" htmlFor="idProofType" required error={errors.idProofType?.message}>
              <Select value={values.idProofType ?? ""} onValueChange={(v) => setValue("idProofType", v as RegisterFormValues["idProofType"], { shouldValidate: true })}>
                <SelectTrigger id="idProofType" aria-invalid={!!errors.idProofType}>
                  <SelectValue placeholder="Choose ID type" />
                </SelectTrigger>
                <SelectContent>
                  {ID_PROOF_TYPES.map((t) => (
                    <SelectItem key={t} value={t}>
                      {t}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <FilePicker
              id="idProof"
              label="ID proof file"
              required
              accept={ACCEPT_DOC}
              file={idProof}
              onChange={setIdProof}
              icon={FileText}
              hint="JPG, PNG, WEBP or PDF"
            />
            <FilePicker id="photo" label="Student photo (optional)" accept={ACCEPT_IMAGE} capture file={photo} onChange={setPhoto} icon={Camera} hint="JPG, PNG or WEBP" round />
          </StepCard>
        )}

        {step === 3 && (
          <StepCard title="Room & fee" description="Only free beds can be selected.">
            <div className="flex flex-col gap-1.5">
              <span className="label-caps text-charcoal/80">Floor</span>
              <SegmentedPills
                ariaLabel="Floor"
                size="sm"
                options={floors.map((f) => ({ value: String(f.floor_number), label: `Floor ${f.floor_number}` }))}
                value={floor === null ? "" : String(floor)}
                onChange={(v) => {
                  setFloor(Number(v));
                  setRoomId(null);
                  setValue("bedId", "", { shouldValidate: false });
                }}
              />
            </div>

            <div className="flex flex-col gap-1.5">
              <span className="label-caps text-charcoal/80">Room</span>
              {roomsOnFloor.length === 0 ? (
                <p className="text-sm text-muted">No rooms on this floor.</p>
              ) : (
                <div className="grid grid-cols-3 gap-2">
                  {roomsOnFloor.map((r) => {
                    // Occupancy comes from rpc_room_occupancy (whole hostel, paged) — no bed list needed to show "Full".
                    const free = freeByRoom.get(r.room_id)?.length ?? Math.max(0, r.capacity - r.occupied);
                    const active = r.room_id === roomId;
                    return (
                      <button
                        key={r.room_id}
                        type="button"
                        disabled={free === 0}
                        onClick={() => {
                          setRoomId(r.room_id);
                          setValue("bedId", "", { shouldValidate: false });
                          void loadRoomBeds(r.room_id);
                        }}
                        aria-pressed={active}
                        className={cn(
                          "flex min-h-[56px] flex-col items-center justify-center rounded-control border px-2 py-2 text-sm font-semibold transition-all active:scale-[0.97]",
                          active ? "border-navy bg-navy text-white" : "border-white/70 bg-white/60 text-navy hover:bg-white/80",
                          free === 0 && "opacity-45",
                        )}
                      >
                        {r.room_number}
                        <span className={cn("mt-0.5 text-[10px] font-medium", active ? "text-white/80" : free === 0 ? "text-muted" : "text-sage")}>
                          {free === 0 ? "Full" : `${free} free`}
                        </span>
                      </button>
                    );
                  })}
                </div>
              )}
            </div>

            <Field label="Bed" required error={errors.bedId?.message}>
              {!selectedRoom ? (
                <p className="text-sm text-muted">Pick a room to see its free beds.</p>
              ) : bedsLoading === selectedRoom.room_id && !roomBeds ? (
                <p className="text-sm text-muted" role="status">
                  Loading free beds…
                </p>
              ) : !roomBeds ? (
                <button type="button" onClick={() => void loadRoomBeds(selectedRoom.room_id, true)} className="text-sm font-medium text-navy hover:underline">
                  Couldn&apos;t load beds — tap to retry
                </button>
              ) : roomBeds.length === 0 ? (
                <p className="text-sm text-muted">No free beds in this room any more — pick another room.</p>
              ) : (
                <div className="grid grid-cols-4 gap-2">
                  {roomBeds.map((b) => {
                    const active = b.bed_id === values.bedId;
                    return (
                      <button
                        key={b.bed_id}
                        type="button"
                        aria-pressed={active}
                        onClick={() => setValue("bedId", b.bed_id, { shouldValidate: true })}
                        className={cn(
                          "flex h-12 items-center justify-center gap-1.5 rounded-control border text-sm font-semibold transition-all active:scale-[0.97]",
                          active ? "border-navy bg-navy text-white" : "border-sage bg-sage-soft/60 text-navy hover:bg-sage-soft",
                        )}
                      >
                        <BedDouble className="h-4 w-4" strokeWidth={1.75} /> {b.bed_number}
                      </button>
                    );
                  })}
                </div>
              )}
            </Field>

            <Field label="Monthly fee (₹)" htmlFor="monthlyFee" required error={errors.monthlyFee?.message}>
              <Input id="monthlyFee" type="number" inputMode="numeric" min={0} step={100} placeholder="6500" aria-invalid={!!errors.monthlyFee} {...register("monthlyFee", { valueAsNumber: true })} />
            </Field>
          </StepCard>
        )}

        {step === 4 && (
          <div className="flex flex-col gap-4">
            <GlassCard>
              <div className="flex items-center gap-4">
                <PhotoThumb file={photo} name={values.fullName} />
                <div className="min-w-0">
                  <div className="truncate text-card-title font-semibold text-navy">{values.fullName || "—"}</div>
                  <div className="mt-0.5 flex items-center gap-1.5 text-[13px] text-muted">
                    <Phone className="h-3.5 w-3.5" /> {values.phone}
                  </div>
                  <div className="mt-1.5">
                    <StatusPill tone="teal" size="sm" label={selectedBed ? `Room ${selectedBed.room_number} · Bed ${selectedBed.bed_number}` : "No bed"} />
                  </div>
                </div>
              </div>
            </GlassCard>
            <ReviewSection title="Personal" onEdit={() => setStep(0)}>
              <ReviewRow label="Email" value={values.email || "—"} />
              <ReviewRow label="Joining" value={formatDate(values.dateOfJoining)} />
            </ReviewSection>
            <ReviewSection title="Guardian" onEdit={() => setStep(1)}>
              <ReviewRow label="Name" value={values.guardianName} />
              <ReviewRow label="Phone" value={values.guardianPhone} />
              <ReviewRow label="Address" value={values.permanentAddress} />
            </ReviewSection>
            <ReviewSection title="ID proof" onEdit={() => setStep(2)}>
              <ReviewRow label="Type" value={values.idProofType ?? "—"} />
              <ReviewRow label="File" value={idProof?.name ?? "Not uploaded"} />
              <ReviewRow label="Photo" value={photo?.name ?? "Not uploaded"} />
            </ReviewSection>
            <ReviewSection title="Room & fee" onEdit={() => setStep(3)}>
              <ReviewRow label="Floor" value={selectedBed ? `Floor ${selectedBed.floor_number}` : "—"} />
              <ReviewRow label="Room · Bed" value={selectedBed ? `${selectedBed.room_number} · Bed ${selectedBed.bed_number}` : "—"} />
              <ReviewRow label="Monthly fee" value={formatINR(values.monthlyFee)} />
            </ReviewSection>
            <p className="px-1 text-[12px] text-muted">
              Submitting creates the student&apos;s login (phone number + temporary password shown once) and marks the bed occupied.
            </p>
          </div>
        )}

        <StickyBar bottom="nav-hidden">
          <Button type="button" variant="ghost" size="lg" onClick={back} disabled={pending} className="shrink-0 px-5">
            Back
          </Button>
          {step < STEPS.length - 1 ? (
            <Button type="button" size="lg" className="flex-1" onClick={next} disabled={!writable}>
              Continue
            </Button>
          ) : (
            <Button type="submit" size="lg" className="flex-1" loading={pending} disabled={!writable}>
              Submit
            </Button>
          )}
        </StickyBar>
      </form>

      <CredentialsDialog
        open={!!credentials}
        onOpenChange={(o) => {
          if (!o) {
            setCredentials(null);
            router.push(doneRoomId ? `/warden/rooms/${doneRoomId}` : "/warden/rooms");
          }
        }}
        credentials={credentials}
      />
    </div>
  );
}

/* ───────────────────────── pieces ───────────────────────── */

function StepCard({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <div>
      <h2 className="text-title-sm text-navy">{title}</h2>
      {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
      <GlassCard className="mt-4 flex flex-col gap-4">{children}</GlassCard>
    </div>
  );
}

function ReviewSection({ title, onEdit, children }: { title: string; onEdit: () => void; children: React.ReactNode }) {
  return (
    <GlassCard className="p-4">
      <div className="mb-2 flex items-center justify-between">
        <span className="label-caps">{title}</span>
        <button type="button" onClick={onEdit} className="text-[12px] font-medium text-navy hover:underline">
          Edit
        </button>
      </div>
      <dl className="flex flex-col gap-1.5">{children}</dl>
    </GlassCard>
  );
}

function ReviewRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4 text-sm">
      <dt className="shrink-0 text-muted">{label}</dt>
      <dd className="min-w-0 break-words text-right font-medium text-charcoal">{value}</dd>
    </div>
  );
}

function PhotoThumb({ file, name }: { file: File | null; name: string }) {
  const url = useObjectUrl(file);
  return (
    <div className="relative flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full bg-sand-soft text-sand-deep">
      {url ? <Image src={url} alt={name} fill unoptimized className="object-cover" sizes="64px" /> : <User className="h-7 w-7" strokeWidth={1.5} />}
    </div>
  );
}

function useObjectUrl(file: File | null) {
  const [url, setUrl] = React.useState<string | null>(null);
  React.useEffect(() => {
    if (!file || !file.type.startsWith("image/")) {
      setUrl(null);
      return;
    }
    const u = URL.createObjectURL(file);
    setUrl(u);
    return () => URL.revokeObjectURL(u);
  }, [file]);
  return url;
}

function FilePicker({
  id,
  label,
  required,
  accept,
  capture,
  file,
  onChange,
  icon: Icon,
  hint,
  round,
}: {
  id: string;
  label: string;
  required?: boolean;
  accept: string;
  capture?: boolean;
  file: File | null;
  onChange: (f: File | null) => void;
  icon: React.ComponentType<{ className?: string; strokeWidth?: number }>;
  hint?: string;
  round?: boolean;
}) {
  const inputRef = React.useRef<HTMLInputElement>(null);
  const url = useObjectUrl(file);
  const isPdf = file?.type === "application/pdf";

  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={id} className="label-caps text-charcoal/80">
        {label}
        {required ? <span className="ml-0.5 text-red">*</span> : null}
      </label>
      <input
        ref={inputRef}
        id={id}
        type="file"
        accept={accept}
        capture={capture ? "user" : undefined}
        className="sr-only"
        onChange={(e) => {
          const f = e.target.files?.[0] ?? null;
          if (f && f.size > MAX_FILE_BYTES) {
            toast.error(`File is larger than ${MAX_FILE_LABEL}. Please use a smaller file.`);
            e.target.value = "";
            return;
          }
          onChange(f);
        }}
      />
      {file ? (
        <div className="flex items-center gap-3 rounded-control border border-line bg-white/70 p-3">
          <div className={cn("relative h-14 w-14 shrink-0 overflow-hidden bg-stone", round ? "rounded-full" : "rounded-[10px]")}>
            {url ? (
              <Image src={url} alt="" fill unoptimized className="object-cover" sizes="56px" />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-navy/60">
                {isPdf ? <FileText className="h-6 w-6" strokeWidth={1.5} /> : <Icon className="h-6 w-6" strokeWidth={1.5} />}
              </div>
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium text-navy">{file.name}</p>
            <p className="text-[12px] text-muted">{(file.size / 1024).toFixed(0)} KB</p>
            <button type="button" onClick={() => inputRef.current?.click()} className="mt-1 text-[12px] font-medium text-navy hover:underline">
              Replace
            </button>
          </div>
          <button
            type="button"
            aria-label="Remove file"
            onClick={() => {
              onChange(null);
              if (inputRef.current) inputRef.current.value = "";
            }}
            className="flex h-10 w-10 items-center justify-center rounded-full text-muted hover:bg-navy/5 hover:text-navy"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => inputRef.current?.click()}
          className="flex min-h-[88px] w-full flex-col items-center justify-center gap-1.5 rounded-control border border-dashed border-navy/25 bg-white/40 px-4 py-4 text-navy transition-colors hover:bg-white/70"
        >
          <span className="flex h-9 w-9 items-center justify-center rounded-full bg-navy/5">
            {round ? <ImagePlus className="h-4 w-4" strokeWidth={1.75} /> : <Icon className="h-4 w-4" strokeWidth={1.75} />}
          </span>
          <span className="text-sm font-medium">Tap to upload</span>
          {hint ? <span className="text-[11px] text-muted">{hint}</span> : null}
        </button>
      )}
    </div>
  );
}
