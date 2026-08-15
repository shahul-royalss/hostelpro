"use client";

import * as React from "react";
import { Camera, ImageIcon, X } from "lucide-react";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/shared/field";
import { useAction } from "@/hooks/use-action";
import { createComplaint } from "@/lib/actions/student";
import { COMPLAINT_CATEGORIES, type ComplaintCategory } from "@/lib/types";
import { COMPLAINT_CATEGORY_LABEL } from "./complaint-icons";

/** ST-4 bottom sheet: Category, Title, Description, Add photo tile, "Submit complaint". */
export function NewComplaintSheet({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const formRef = React.useRef<HTMLFormElement>(null);
  const fileRef = React.useRef<HTMLInputElement>(null);
  const [category, setCategory] = React.useState<ComplaintCategory | "">("");
  const [photo, setPhoto] = React.useState<File | null>(null);
  const [errors, setErrors] = React.useState<Record<string, string[]>>({});

  const { run, pending } = useAction(createComplaint, {
    onSuccess: () => {
      formRef.current?.reset();
      setCategory("");
      setPhoto(null);
      setErrors({});
      onOpenChange(false);
    },
  });

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    fd.set("category", category);
    if (photo) fd.set("photo", photo);
    else fd.delete("photo");
    const res = await run(fd);
    if (!res.ok && res.fieldErrors) setErrors(res.fieldErrors);
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="mx-auto max-w-[480px]">
        <SheetHeader>
          <SheetTitle>New complaint</SheetTitle>
          <SheetDescription>Your warden and owner will be notified right away.</SheetDescription>
        </SheetHeader>

        <form ref={formRef} onSubmit={onSubmit} className="mt-4 flex flex-col gap-4">
          <Field label="Category" htmlFor="complaint-category" required error={errors.category?.[0]}>
            <Select value={category} onValueChange={(v) => setCategory(v as ComplaintCategory)}>
              <SelectTrigger id="complaint-category" aria-invalid={!!errors.category}>
                <SelectValue placeholder="What is this about?" />
              </SelectTrigger>
              <SelectContent>
                {COMPLAINT_CATEGORIES.map((c) => (
                  <SelectItem key={c} value={c}>
                    {COMPLAINT_CATEGORY_LABEL[c]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>

          <Field label="Title" htmlFor="complaint-title" required error={errors.title?.[0]}>
            <Input id="complaint-title" name="title" placeholder="e.g. Leaking tap in bathroom" maxLength={120} required aria-invalid={!!errors.title} />
          </Field>

          <Field label="Description" htmlFor="complaint-description" error={errors.description?.[0]} hint="Where, since when, how often — anything that helps.">
            <Textarea id="complaint-description" name="description" placeholder="Describe the issue" maxLength={2000} rows={3} />
          </Field>

          <div className="flex flex-col gap-1.5">
            <span className="text-caption uppercase tracking-[0.05em] text-charcoal/80">Photo (optional)</span>
            <input
              ref={fileRef}
              type="file"
              name="photo"
              accept="image/jpeg,image/png,image/webp"
              className="sr-only"
              onChange={(e) => setPhoto(e.target.files?.[0] ?? null)}
              aria-label="Add photo"
            />
            {photo ? (
              <div className="flex items-center gap-3 rounded-control border border-line bg-white/60 px-3.5 py-3">
                <span className="flex h-9 w-9 items-center justify-center rounded-full bg-teal-soft text-teal">
                  <ImageIcon className="h-4 w-4" />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-medium text-navy">{photo.name}</div>
                  <div className="text-[11px] text-muted">{(photo.size / 1024 / 1024).toFixed(2)} MB</div>
                </div>
                <button
                  type="button"
                  aria-label="Remove photo"
                  onClick={() => {
                    setPhoto(null);
                    if (fileRef.current) fileRef.current.value = "";
                  }}
                  className="rounded-full p-1.5 text-muted hover:bg-navy/5 hover:text-navy"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
            ) : (
              <button
                type="button"
                onClick={() => fileRef.current?.click()}
                className="flex h-[76px] w-full items-center justify-center gap-2 rounded-control border border-dashed border-navy/25 bg-white/40 text-sm font-medium text-navy transition-colors hover:bg-white/70 active:scale-[0.99]"
              >
                <Camera className="h-4 w-4" /> Add photo
              </button>
            )}
          </div>

          <Button type="submit" size="xl" loading={pending} className="mt-1">
            Submit complaint
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
