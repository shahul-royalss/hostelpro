"use client";

import * as React from "react";
import Link from "next/link";
import { ArrowRight, ListChecks } from "lucide-react";
import { updateTaskStatus } from "@/lib/actions/manager";
import { useAction } from "@/hooks/use-action";
import type { TaskRow } from "@/lib/types";
import { cn } from "@/lib/utils";
import { Checkbox } from "@/components/ui/misc";
import { GlassCard, GlassCardHeader } from "@/components/shared/glass-card";
import { StatusPill } from "@/components/shared/status-pill";
import { EmptyState } from "@/components/shared/empty-state";
import { DueDate } from "./task-list";

function TaskRowItem({ task, writable }: { task: TaskRow; writable: boolean }) {
  const { run, pending } = useAction(updateTaskStatus);
  const id = `task-${task.id}`;
  return (
    <li className={cn("flex items-start gap-3 py-3 transition-opacity", pending && "opacity-60")}>
      <Checkbox
        id={id}
        className="mt-0.5"
        checked={false}
        disabled={!writable || pending}
        onCheckedChange={(v) => v === true && run({ taskId: task.id, status: "done" })}
        aria-label={`Mark "${task.title}" done`}
      />
      <label htmlFor={id} className="min-w-0 flex-1 cursor-pointer">
        <div className="text-sm font-medium text-navy">{task.title}</div>
        <div className="mt-1 flex flex-wrap items-center gap-2">
          <DueDate date={task.due_date} status={task.status} />
          <StatusPill status={task.status} size="sm" />
        </div>
      </label>
    </li>
  );
}

/** MG-1 "My tasks from owner" — open tasks with a checkbox to mark done. */
export function DashboardTasks({ tasks, writable, total }: { tasks: TaskRow[]; writable: boolean; total: number }) {
  return (
    <GlassCard className="flex h-full flex-col">
      <GlassCardHeader
        title="My tasks from owner"
        description={total > 0 ? `${total} open ${total === 1 ? "task" : "tasks"}` : undefined}
        action={
          <Link href="/manager/tasks" className="inline-flex items-center gap-1 text-sm font-medium text-navy hover:underline">
            View all <ArrowRight className="h-4 w-4" />
          </Link>
        }
      />
      {tasks.length === 0 ? (
        <EmptyState compact icon={ListChecks} title="All caught up" description="No open tasks from your owner right now." />
      ) : (
        <ul className="-my-1 divide-y divide-line/70">
          {tasks.map((t) => (
            <TaskRowItem key={t.id} task={t} writable={writable} />
          ))}
        </ul>
      )}
    </GlassCard>
  );
}
