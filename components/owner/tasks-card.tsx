"use client";

import * as React from "react";
import { differenceInCalendarDays, parseISO } from "date-fns";
import { CalendarDays, ListChecks, Pencil, Plus, Trash2 } from "lucide-react";
import type { TaskRow, TaskStatus } from "@/lib/types";
import type { StaffUser } from "@/lib/queries/owner";
import { createTask, deleteTask, updateTask } from "@/lib/actions/owner";
import { useAction } from "@/hooks/use-action";
import { cn, formatDate, toISODate } from "@/lib/utils";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { SegmentedPills } from "@/components/shared/segmented";
import { Field } from "@/components/shared/field";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";

type Filter = "all" | TaskStatus;

const STATUS_OPTIONS: { value: TaskStatus; label: string }[] = [
  { value: "pending", label: "Pending" },
  { value: "in_progress", label: "In progress" },
  { value: "done", label: "Done" },
];

function dueInfo(task: TaskRow): { text: string; tone: "red" | "sand" | "muted" | "teal" } {
  if (!task.due_date) return { text: "No due date", tone: "muted" };
  const diff = differenceInCalendarDays(parseISO(task.due_date), new Date());
  if (task.status === "done") return { text: `Due ${formatDate(task.due_date)}`, tone: "teal" };
  if (diff < 0) return { text: `Overdue · ${formatDate(task.due_date)}`, tone: "red" };
  if (diff === 0) return { text: "Due today", tone: "sand" };
  if (diff === 1) return { text: "Due tomorrow", tone: "sand" };
  return { text: `Due ${formatDate(task.due_date)}`, tone: "muted" };
}

const dueTone = { red: "text-red", sand: "text-sand-deep", muted: "text-muted", teal: "text-teal" } as const;

/** OW-4 "Tasks for manager": add row, filterable list with status pills, edit + soft delete. */
export function TasksCard({ tasks, manager, writable }: { tasks: TaskRow[]; manager: StaffUser | null; writable: boolean }) {
  const [filter, setFilter] = React.useState<Filter>("all");
  const [editing, setEditing] = React.useState<TaskRow | null>(null);
  const [deleting, setDeleting] = React.useState<TaskRow | null>(null);

  const counts = React.useMemo(() => {
    const c: Record<TaskStatus, number> = { pending: 0, in_progress: 0, done: 0 };
    for (const t of tasks) c[t.status] += 1;
    return c;
  }, [tasks]);

  const visible = React.useMemo(() => {
    const list = filter === "all" ? tasks : tasks.filter((t) => t.status === filter);
    // open tasks first (earliest due first), done last
    return [...list].sort((a, b) => {
      const ad = a.status === "done" ? 1 : 0;
      const bd = b.status === "done" ? 1 : 0;
      if (ad !== bd) return ad - bd;
      const aDue = a.due_date ?? "9999-12-31";
      const bDue = b.due_date ?? "9999-12-31";
      if (aDue !== bDue) return aDue.localeCompare(bDue);
      return b.created_at.localeCompare(a.created_at);
    });
  }, [tasks, filter]);

  const del = useAction(deleteTask, { onSuccess: () => setDeleting(null) });
  const canWrite = writable && !!manager;

  return (
    <GlassCard as="section">
      <GlassCardHeader
        title={
          <span className="inline-flex items-center gap-2">
            <ListChecks className="h-4 w-4 text-teal" /> Tasks for manager
          </span>
        }
        description={manager ? `Assigned to ${manager.full_name}. The manager updates status from their app.` : "Add a manager first — tasks are assigned to the active manager."}
      />

      <AddTaskRow disabled={!canWrite} />

      <div className="mt-5 flex flex-wrap items-center justify-between gap-3">
        <SegmentedPills<Filter>
          size="sm"
          ariaLabel="Filter tasks"
          value={filter}
          onChange={setFilter}
          options={[
            { value: "all", label: "All", count: tasks.length },
            { value: "pending", label: "Pending", count: counts.pending, tone: "sand" },
            { value: "in_progress", label: "In progress", count: counts.in_progress },
            { value: "done", label: "Done", count: counts.done, tone: "teal" },
          ]}
        />
      </div>

      {visible.length === 0 ? (
        <EmptyState compact icon={ListChecks} title={tasks.length ? "No tasks in this view" : "No tasks yet"} description={tasks.length ? "Try another filter." : "Send your manager their first task using the row above."} />
      ) : (
        <ul className="mt-3 divide-y divide-line/70">
          {visible.map((t) => {
            const due = dueInfo(t);
            return (
              <li key={t.id} className="flex items-start gap-3 py-3">
                <StatusPill status={t.status} size="sm" className="mt-0.5 w-[92px] justify-center" />
                <div className="min-w-0 flex-1">
                  <p className={cn("text-sm font-medium text-charcoal", t.status === "done" && "text-muted line-through decoration-line")}>{t.title}</p>
                  {t.description ? <p className="mt-0.5 line-clamp-2 text-[12px] text-muted">{t.description}</p> : null}
                </div>
                <div className={cn("hidden shrink-0 items-center gap-1.5 text-[12px] font-medium tabular sm:flex", dueTone[due.tone])}>
                  <CalendarDays className="h-3.5 w-3.5" />
                  {due.text}
                </div>
                {writable ? (
                  <div className="flex shrink-0 items-center gap-0.5">
                    <Button variant="ghost" size="icon-sm" aria-label="Edit task" onClick={() => setEditing(t)}>
                      <Pencil />
                    </Button>
                    <Button variant="ghost" size="icon-sm" aria-label="Delete task" className="text-muted hover:text-red" onClick={() => setDeleting(t)}>
                      <Trash2 />
                    </Button>
                  </div>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}

      {editing ? <EditTaskDialog key={editing.id} task={editing} onClose={() => setEditing(null)} /> : null}

      <Dialog open={!!deleting} onOpenChange={(v) => (!v ? setDeleting(null) : null)}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Delete this task?</DialogTitle>
            <DialogDescription>
              <span className="font-medium text-charcoal">{deleting?.title}</span> will be removed from your manager&apos;s list.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setDeleting(null)} disabled={del.pending}>
              Cancel
            </Button>
            <Button variant="destructive" loading={del.pending} onClick={() => deleting && del.run({ taskId: deleting.id })}>
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </GlassCard>
  );
}

function AddTaskRow({ disabled }: { disabled: boolean }) {
  const [title, setTitle] = React.useState("");
  const [dueDate, setDueDate] = React.useState("");
  const [description, setDescription] = React.useState("");
  const [showDesc, setShowDesc] = React.useState(false);
  const { run, pending } = useAction(createTask, {
    onSuccess: () => {
      setTitle("");
      setDueDate("");
      setDescription("");
      setShowDesc(false);
    },
  });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (title.trim().length < 2) return;
    void run({ title: title.trim(), description: description.trim(), dueDate });
  }

  return (
    <form onSubmit={submit} className="rounded-card border border-line/70 bg-white/50 p-3">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative flex-1">
          <Plus className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Add a new task…" className="pl-9" maxLength={160} disabled={disabled || pending} aria-label="Task title" />
        </div>
        <Input type="date" value={dueDate} min={toISODate()} onChange={(e) => setDueDate(e.target.value)} className="sm:w-[170px]" disabled={disabled || pending} aria-label="Due date" />
        <Button type="submit" disabled={disabled || title.trim().length < 2} loading={pending} className="sm:min-w-[96px]">
          Add
        </Button>
      </div>
      {showDesc ? (
        <Textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Optional details for the manager…" rows={2} maxLength={2000} className="mt-2" disabled={disabled || pending} />
      ) : (
        <button type="button" onClick={() => setShowDesc(true)} disabled={disabled} className="mt-2 text-xs font-medium text-navy/70 hover:text-navy disabled:opacity-50">
          + Add description
        </button>
      )}
    </form>
  );
}

function EditTaskDialog({ task, onClose }: { task: TaskRow; onClose: () => void }) {
  const [title, setTitle] = React.useState(task.title);
  const [description, setDescription] = React.useState(task.description ?? "");
  const [dueDate, setDueDate] = React.useState(task.due_date ?? "");
  const [status, setStatus] = React.useState<TaskStatus>(task.status);
  const { run, pending } = useAction(updateTask, { onSuccess: onClose });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    void run({ taskId: task.id, title: title.trim(), description: description.trim() || null, dueDate: dueDate || null, status });
  }

  return (
    <Dialog open onOpenChange={(v) => (!v && !pending ? onClose() : null)}>
      <DialogContent className="max-w-md">
        <form onSubmit={submit} className="space-y-5">
          <DialogHeader>
            <DialogTitle>Edit task</DialogTitle>
            <DialogDescription>Changes are reflected in the manager&apos;s task list immediately.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <Field label="Title" htmlFor="task-title" required>
              <Input id="task-title" value={title} onChange={(e) => setTitle(e.target.value)} required minLength={2} maxLength={160} />
            </Field>
            <Field label="Description" htmlFor="task-desc">
              <Textarea id="task-desc" value={description} onChange={(e) => setDescription(e.target.value)} rows={3} maxLength={2000} />
            </Field>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <Field label="Due date" htmlFor="task-due">
                <Input id="task-due" type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
              </Field>
              <Field label="Status">
                <Select value={status} onValueChange={(v) => setStatus(v as TaskStatus)}>
                  <SelectTrigger aria-label="Status">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {STATUS_OPTIONS.map((o) => (
                      <SelectItem key={o.value} value={o.value}>
                        {o.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose} disabled={pending}>
              Cancel
            </Button>
            <Button type="submit" loading={pending} disabled={title.trim().length < 2}>
              Save changes
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
