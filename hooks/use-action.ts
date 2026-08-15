"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import type { ActionResult } from "@/lib/types";

/**
 * Run a server action returning ActionResult with pending state + toasts.
 *
 *   const { run, pending } = useAction(createTask, { success: "Task added", refresh: true });
 *   <Button loading={pending} onClick={() => run({ title })}>Add</Button>
 */
export function useAction<Args extends unknown[], T>(
  action: (...args: Args) => Promise<ActionResult<T>>,
  opts: {
    success?: string | ((data: T) => string | undefined);
    error?: string;
    /** router.refresh() after success (default true) */
    refresh?: boolean;
    onSuccess?: (data: T) => void;
    onError?: (error: string) => void;
  } = {},
) {
  const [pending, start] = React.useTransition();
  const router = useRouter();
  const { refresh = true } = opts;

  const run = React.useCallback(
    (...args: Args) =>
      new Promise<ActionResult<T>>((resolve) => {
        start(async () => {
          try {
            const res = await action(...args);
            if (res.ok) {
              const msg = typeof opts.success === "function" ? opts.success(res.data) : opts.success ?? res.message;
              if (msg) toast.success(msg);
              opts.onSuccess?.(res.data);
              if (refresh) router.refresh();
            } else {
              toast.error(opts.error ?? res.error);
              opts.onError?.(res.error);
            }
            resolve(res);
          } catch (e) {
            const msg = e instanceof Error ? e.message : "Something went wrong";
            toast.error(msg);
            opts.onError?.(msg);
            resolve({ ok: false, error: msg });
          }
        });
      }),
    [action, opts, refresh, router],
  );

  return { run, pending };
}
