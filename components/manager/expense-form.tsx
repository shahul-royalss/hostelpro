"use client";

import * as React from "react";
import { FileText, ImageIcon, Save, UploadCloud, X } from "lucide-react";
import { createExpense, updateExpense } from "@/lib/actions/manager";
import { useAction } from "@/hooks/use-action";
import { EXPENSE_CATEGORIES, type ExpenseRow } from "@/lib/types";
import { cn, titleCase, toISODate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Field } from "@/components/shared/field";

const ACCEPT = "image/jpeg,image/png,image/webp,application/pdf";
const MAX_MB = 8;

type FieldErrors = Record<string, string[] | undefined>;

/**
 * Add / edit expense form (MG-2). Uses FormData because of the receipt file.
 * `mode="create"` renders the top "Add expense" card body; `mode="edit"` is used inside the edit dialog.
 */
export function ExpenseForm({
  mode,
  initial,
  disabled,
  onDone,
}: {
  mode: "create" | "edit";
  initial?: ExpenseRow;
  disabled?: boolean;
  onDone?: () => void;
}) {
  const formRef = React.useRef<HTMLFormElement>(null);
  const fileRef = React.useRef<HTMLInputElement>(null);
  const [category, setCategory] = React.useState<string>(initial?.category ?? "groceries");
  const [file, setFile] = React.useState<File | null>(null);
  const [fileError, setFileError] = React.useState<string | null>(null);
  const [removeReceipt, setRemoveReceipt] = React.useState(false);
  const [dragging, setDragging] = React.useState(false);
  const [errors, setErrors] = React.useState<FieldErrors>({});
  // Default date is computed on the client so "today" follows the manager's timezone.
  const [defaultDate] = React.useState(() => initial?.date ?? toISODate());

  const action = mode === "create" ? createExpense : updateExpense;
  const { run, pending } = useAction(action, {
    onSuccess: () => {
      setErrors({});
      if (mode === "create") {
        formRef.current?.reset();
        setCategory("groceries");
        clearFile();
      }
      onDone?.();
    },
    onError: () => undefined,
  });

  const clearFile = () => {
    setFile(null);
    setFileError(null);
    if (fileRef.current) fileRef.current.value = "";
  };

  const pickFile = (f: File | null | undefined) => {
    if (!f) return clearFile();
    if (!ACCEPT.split(",").includes(f.type)) {
      setFileError("Use a JPG, PNG, WEBP or PDF file.");
      return;
    }
    if (f.size > MAX_MB * 1024 * 1024) {
      setFileError(`File is larger than ${MAX_MB} MB.`);
      return;
    }
    setFileError(null);
    setFile(f);
    setRemoveReceipt(false);
  };

  const onSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (fileError) return;
    const fd = new FormData(e.currentTarget);
    fd.set("category", category);
    if (file) fd.set("receipt", file);
    else fd.delete("receipt");
    if (mode === "edit") {
      fd.set("id", initial?.id ?? "");
      fd.set("removeReceipt", removeReceipt ? "1" : "0");
    }
    const res = await run(fd);
    if (!res.ok && res.fieldErrors) setErrors(res.fieldErrors);
  };

  const hasExistingReceipt = mode === "edit" && !!initial?.receipt_url && !removeReceipt && !file;
  const busy = pending || disabled;

  return (
    <form ref={formRef} onSubmit={onSubmit} className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_1fr_1fr_minmax(220px,0.9fr)]" noValidate>
      <div className="grid gap-4 lg:col-span-3 lg:grid-cols-3">
        <Field label="Date" htmlFor={`${mode}-date`} error={errors.date?.[0]} required>
          <Input id={`${mode}-date`} name="date" type="date" defaultValue={defaultDate} max={toISODate()} required disabled={busy} />
        </Field>
        <Field label="Category" htmlFor={`${mode}-category`} error={errors.category?.[0]} required>
          <Select value={category} onValueChange={setCategory} disabled={busy}>
            <SelectTrigger id={`${mode}-category`} aria-label="Category">
              <SelectValue placeholder="Select category" />
            </SelectTrigger>
            <SelectContent>
              {EXPENSE_CATEGORIES.map((c) => (
                <SelectItem key={c} value={c}>
                  {titleCase(c)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field label="Amount (₹)" htmlFor={`${mode}-amount`} error={errors.amount?.[0]} required>
          <div className="relative">
            <span className="pointer-events-none absolute inset-y-0 left-3.5 flex items-center text-sm text-muted">₹</span>
            <Input
              id={`${mode}-amount`}
              name="amount"
              type="number"
              inputMode="decimal"
              min={0}
              step="0.01"
              placeholder="0.00"
              defaultValue={initial ? Number(initial.amount) : undefined}
              className="pl-7 tabular"
              required
              disabled={busy}
            />
          </div>
        </Field>
        <Field label="Note" htmlFor={`${mode}-note`} error={errors.note?.[0]} className="lg:col-span-3">
          <Textarea
            id={`${mode}-note`}
            name="note"
            placeholder="What was this for? e.g. Weekly vegetables and dairy"
            defaultValue={initial?.note ?? ""}
            className="min-h-[72px]"
            maxLength={500}
            disabled={busy}
          />
        </Field>
      </div>

      <div className="flex flex-col gap-3">
        <Field label="Receipt" hint={fileError ? undefined : "JPG, PNG, WEBP or PDF · max 8 MB"} error={fileError}>
          <label
            onDragOver={(e) => {
              e.preventDefault();
              if (!busy) setDragging(true);
            }}
            onDragLeave={() => setDragging(false)}
            onDrop={(e) => {
              e.preventDefault();
              setDragging(false);
              if (!busy) pickFile(e.dataTransfer.files?.[0]);
            }}
            className={cn(
              "flex min-h-[132px] cursor-pointer flex-col items-center justify-center gap-2 rounded-control border-2 border-dashed px-4 py-5 text-center transition-colors",
              dragging ? "border-navy bg-navy/5" : "border-input bg-white/40 hover:border-navy/50 hover:bg-white/60",
              busy && "pointer-events-none opacity-60",
            )}
          >
            <input ref={fileRef} type="file" name="receipt" accept={ACCEPT} className="sr-only" onChange={(e) => pickFile(e.target.files?.[0])} disabled={busy} />
            {file ? (
              <>
                {file.type === "application/pdf" ? <FileText className="h-6 w-6 text-teal" strokeWidth={1.5} /> : <ImageIcon className="h-6 w-6 text-teal" strokeWidth={1.5} />}
                <span className="line-clamp-1 max-w-full break-all text-sm font-medium text-navy">{file.name}</span>
                <span className="text-xs text-muted">{(file.size / 1024).toFixed(0)} KB · click to replace</span>
              </>
            ) : hasExistingReceipt ? (
              <>
                <FileText className="h-6 w-6 text-teal" strokeWidth={1.5} />
                <span className="text-sm font-medium text-navy">Receipt attached</span>
                <span className="text-xs text-muted">Click to replace</span>
              </>
            ) : (
              <>
                <span className="flex h-10 w-10 items-center justify-center rounded-full bg-navy/5 text-navy/70">
                  <UploadCloud className="h-5 w-5" strokeWidth={1.75} />
                </span>
                <span className="text-sm font-medium text-navy">Click to upload</span>
                <span className="text-xs text-muted">or drag and drop the receipt here</span>
              </>
            )}
          </label>
        </Field>
        {file || hasExistingReceipt ? (
          <button
            type="button"
            onClick={() => {
              if (file) clearFile();
              else setRemoveReceipt(true);
            }}
            className="inline-flex items-center gap-1 self-start text-xs font-medium text-red hover:underline"
            disabled={busy}
          >
            <X className="h-3.5 w-3.5" /> {file ? "Remove file" : "Remove receipt"}
          </button>
        ) : null}
        <Button type="submit" loading={pending} disabled={disabled} className={cn(mode === "create" ? "mt-auto w-full" : "w-full")}>
          <Save /> {mode === "create" ? "Save expense" : "Save changes"}
        </Button>
      </div>
    </form>
  );
}
