"use client";

import * as React from "react";
import Link from "next/link";
import { Bell, CheckCheck } from "lucide-react";
import { formatDistanceToNowStrict } from "date-fns";
import { fetchNotifications, markNotificationsRead } from "@/lib/actions/session";
import type { NotificationRow } from "@/lib/types";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/misc";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { EmptyState } from "./empty-state";

const typeDot: Record<string, string> = {
  announcement: "bg-teal",
  task: "bg-navy",
  complaint: "bg-red",
  leave: "bg-sand",
  subscription: "bg-sand",
  fee: "bg-teal",
  system: "bg-muted",
};

/** Bell icon with unread badge + popover list. Polls every 60s. */
export function NotificationBell({ initialUnread = 0, className }: { initialUnread?: number; className?: string }) {
  const [open, setOpen] = React.useState(false);
  const [unread, setUnread] = React.useState(initialUnread);
  const [items, setItems] = React.useState<NotificationRow[]>([]);
  const [loading, setLoading] = React.useState(false);

  const load = React.useCallback(async () => {
    const res = await fetchNotifications(20);
    if (res.ok) {
      setItems(res.data.items);
      setUnread(res.data.unread);
    }
  }, []);

  React.useEffect(() => {
    const t = setInterval(load, 60_000);
    return () => clearInterval(t);
  }, [load]);

  React.useEffect(() => {
    if (open) {
      setLoading(true);
      load().finally(() => setLoading(false));
    }
  }, [open, load]);

  async function markAll() {
    await markNotificationsRead();
    setItems((prev) => prev.map((n) => ({ ...n, read_at: n.read_at ?? new Date().toISOString() })));
    setUnread(0);
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          aria-label={`Notifications${unread ? `, ${unread} unread` : ""}`}
          className={cn(
            "relative flex h-10 w-10 items-center justify-center rounded-full text-navy transition-colors hover:bg-navy/5 active:scale-95",
            className,
          )}
        >
          <Bell className="h-5 w-5" strokeWidth={1.75} />
          {unread > 0 && (
            <span className="absolute right-1.5 top-1.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-red px-1 text-[10px] font-bold text-white ring-2 ring-ivory">
              {unread > 99 ? "99+" : unread}
            </span>
          )}
        </button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-[min(92vw,380px)] p-0">
        <div className="flex items-center justify-between border-b border-line px-4 py-3">
          <div className="text-sm font-semibold text-navy">Notifications</div>
          <Button variant="ghost" size="sm" onClick={markAll} disabled={unread === 0}>
            <CheckCheck /> Mark all read
          </Button>
        </div>
        <div className="max-h-[60vh] overflow-y-auto">
          {loading && items.length === 0 ? (
            <div className="p-4 text-sm text-muted">Loading…</div>
          ) : items.length === 0 ? (
            <EmptyState compact icon={Bell} title="You're all caught up" description="New updates will appear here." />
          ) : (
            <ul className="divide-y divide-line/70">
              {items.map((n) => {
                const inner = (
                  <div className={cn("flex gap-3 px-4 py-3 transition-colors hover:bg-navy/[0.03]", !n.read_at && "bg-navy/[0.02]")}>
                    <span className={cn("mt-1.5 h-2 w-2 shrink-0 rounded-full", typeDot[n.type] ?? "bg-muted", n.read_at && "opacity-40")} />
                    <div className="min-w-0 flex-1">
                      <div className={cn("text-sm text-charcoal", !n.read_at && "font-semibold text-navy")}>{n.title}</div>
                      {n.body ? <div className="mt-0.5 line-clamp-2 text-[13px] text-muted">{n.body}</div> : null}
                      <div className="mt-1 text-[11px] text-muted/80">
                        {formatDistanceToNowStrict(new Date(n.created_at), { addSuffix: true })}
                      </div>
                    </div>
                  </div>
                );
                return (
                  <li key={n.id}>
                    {n.link ? (
                      <Link
                        href={n.link}
                        onClick={() => {
                          if (!n.read_at) {
                            markNotificationsRead([n.id]);
                            setUnread((u) => Math.max(0, u - 1));
                          }
                          setOpen(false);
                        }}
                      >
                        {inner}
                      </Link>
                    ) : (
                      inner
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}
