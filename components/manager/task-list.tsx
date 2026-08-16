"use client";

import * as React from "react";
import { CalendarDays, Check, ListChecks, Play, RotateCcw, Undo2 } from "lucide-react";
import { updateTaskStatus } from "@/lib/actions/manager";
import { useAction } from "@/hooks/use-action";
import type { TaskRow, TaskStatus } from "@/lib/types";
import { cn, daysUntil, formatDate, formatDateTime } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { GlassCard } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { SegmentedPills } from "@/components/shared/segmented";
import { EmptyState } from "@/components/shared/empty-state";

type Filter = "all" | TaskStatus;

/** Due-date caption: overdue → red, due today/tomorrow → sand, else muted. */
export function DueDate({ date, status, className }: { date: string | null; status: TaskStatus; className?: string }) {
  if (!date) return <span className={cn("text-xs text-muted", className)}>No due date</span>;
  const days = daysUntil(date);
  const overdue = status !== "done" && days !== null && days < 0;
  const soon = status !== "done" && days !== null && days >= 0 && days <= 1;
  return (
    <span className={cn("inline-flex items-center gap-1 text-xs tabular", overdue ? "font-semibold text-red" : soon ? "font-medium text-sand-deep" : "text-muted", className)}>
      <CalendarDays className="h-3.5 w-3.5" />
      {formatDate(date, "d MMM")}
      {overdue ? " · Overdue" : soon ? (days === 0 ? " · Today" : " · Tomorrow") : ""}
    </span>
  );
}

/** Status transition buttons: pending → in_progress → done (and back). */
export function TaskActions({ task, disabled, size = "sm" }: { task: TaskRow; disabled?: boolean; size?: "sm" | "default" }) {
  const { run, pending } = useAction(updateTaskStatus);
  const go = (status: TaskStatus) => run({ taskId: task.id, status });
  // Read-only (expired subscription): keep the controls visible but disabled (rule §4.4), don't hide them.
  const off = disabled || pending;

  if (task.status === "pending") {
    return (
      <div className="flex flex-wrap items-center gap-1.5">
        <Button type="button" size={size} variant="secondary" loading={pending} disabled={off} onClick={() => go("in_progress")}>
          <Play /> Start
        </Button>
        <Button type="button" size={size} variant="teal" loading={pending} disabled={off} onClick={() => go("done")}>
          <Check /> Done
        </Button>
      </div>
    );
  }
  if (task.status === "in_progress") {
    return (
      <div className="flex flex-wrap items-center gap-1.5">
        <Button type="button" size={size} variant="ghost" loading={pending} disabled={off} onClick={() => go("pending")}>
          <Undo2 /> Pending
        </Button>
        <Button type="button" size={size} variant="teal" loading={pending} disabled={off} onClick={() => go("done")}>
          <Check /> Done
        </Button>
      </div>
    );
  }
  return (
    <Button type="button" size={size} variant="ghost" loading={pending} disabled={off} onClick={() => go("in_progress")}>
      <RotateCcw /> Reopen
    </Button>
  );
}

export function TaskList({ tasks, writable }: { tasks: TaskRow[]; writable: boolean }) {
  const [filter, setFilter] = React.useState<Filter>("all");
  const counts = React.useMemo(
    () => ({
      all: tasks.length,
      pending: tasks.filter((t) => t.status === "pending").length,
      in_progress: tasks.filter((t) => t.status === "in_progress").length,
      done: tasks.filter((t) => t.status === "done").length,
    }),
    [tasks],
  );
  const visible = filter === "all" ? tasks : tasks.filter((t) => t.status === filter);

  return (
    <div className="space-y-4">
      <SegmentedPills<Filter>
        ariaLabel="Filter tasks"
        value={filter}
        onChange={setFilter}
        options={[
          { value: "all", label: "All", count: counts.all },
          { value: "pending", label: "Pending", count: counts.pending, tone: "sand" },
          { value: "in_progress", label: "In progress", count: counts.in_progress },
          { value: "done", label: "Done", count: counts.done, tone: "teal" },
        ]}
      />

      <GlassCard padded={false}>
        {visible.length === 0 ? (
          <EmptyState
            icon={ListChecks}
            title={tasks.length === 0 ? "No tasks yet" : `No ${filter === "in_progress" ? "in-progress" : filter} tasks`}
            description={tasks.length === 0 ? "Tasks your owner assigns to you will show up here." : "Try a different filter."}
          />
        ) : (
          <ul className="divide-y divide-line/70">
            {visible.map((t) => (
              <li key={t.id} className="flex flex-col gap-3 p-5 md:flex-row md:items-start md:justify-between md:px-6">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className={cn("text-[15px] font-semibold text-navy", t.status === "done" && "text-muted line-through decoration-muted/60")}>{t.title}</h3>
                    <StatusPill status={t.status} size="sm" />
                  </div>
                  {t.description ? <p className="mt-1 whitespace-pre-line text-sm text-charcoal/80">{t.description}</p> : null}
                  <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1">
                    <DueDate date={t.due_date} status={t.status} />
                    <span className="text-xs text-muted">Assigned {formatDate(t.created_at)}</span>
                    {t.completed_at ? <span className="text-xs text-teal">Completed {formatDateTime(t.completed_at)}</span> : null}
                  </div>
                </div>
                <div className="shrink-0 md:pl-4">
                  <TaskActions task={t} disabled={!writable} />
                </div>
              </li>
            ))}
          </ul>
        )}
      </GlassCard>
    </div>
  );
}
