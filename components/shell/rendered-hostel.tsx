"use client";

import * as React from "react";
import { useRouter } from "next/navigation";

/**
 * STALE FORM GUARD, client half. The server half is assertWritableContextFor() in
 * lib/permissions.ts, which explains the failure this prevents.
 *
 * Holds the id of the PG the current page was RENDERED for, so every warden and manager write
 * can hand it to the server, which refuses the write when the account has since moved to a
 * different PG (on this device or another one).
 *
 * WHERE IT IS PROVIDED.
 *  • Warden (and student) pages: MobileShell, which MobilePage renders per page with that
 *    request's own context, so the value is always the page's.
 *  • Manager pages: each page wraps its own content. NOT the manager layout: an App Router layout
 *    is kept across client-side navigation, so a layout-level id would go stale exactly when it
 *    matters, and a correct submit would be refused.
 *  • Owner complaints page: updateComplaintStatus is shared with the warden and takes the id too.
 *
 * `undefined` means no provider at all, which is a programming error and throws on render so it
 * is found in development. `null` means the page has no PG; the id is then empty and the server
 * refuses the write, which is the safe direction.
 *
 * THE TOP BAR, TOO. The guard above protects a page rendered for the wrong PG. It cannot protect
 * a page rendered for the RIGHT PG under a top bar naming the wrong one, and that is what a
 * layout produces: DesktopShell is drawn by app/manager/layout.tsx, which the App Router keeps
 * across client-side navigation. After a switch on the phone, the manager's next click on the web
 * renders PG B's page beneath a bar that still says PG A, and a write from that page is correctly
 * NOT refused (it really was rendered for B), while the manager believes they are working in A.
 * So RenderedHostel also compares the page's PG with the layout's (LayoutHostel, provided by
 * DesktopShell) and refreshes when they differ, which redraws the layout from the session. It
 * cannot loop: the layout and the page read the same per-request getHostelContext(), so after one
 * refresh they agree.
 */
const RenderedHostelContext = React.createContext<string | null | undefined>(undefined);

/** The PG the persistent layout shell was drawn for. `undefined` outside DesktopShell. */
const LayoutHostelContext = React.createContext<string | null | undefined>(undefined);

export function LayoutHostel({ hostelId, children }: { hostelId: string | null; children: React.ReactNode }) {
  return <LayoutHostelContext.Provider value={hostelId}>{children}</LayoutHostelContext.Provider>;
}

export function RenderedHostel({ hostelId, children }: { hostelId: string | null; children: React.ReactNode }) {
  const layoutHostelId = React.useContext(LayoutHostelContext);
  const router = useRouter();
  React.useEffect(() => {
    // Only when both sides name a PG: MobileShell has no layout above it (undefined), and a
    // Super Admin layout has no PG (null).
    if (layoutHostelId && hostelId && layoutHostelId !== hostelId) router.refresh();
  }, [layoutHostelId, hostelId, router]);
  return <RenderedHostelContext.Provider value={hostelId}>{children}</RenderedHostelContext.Provider>;
}

export function useRenderedHostelId(): string {
  const hostelId = React.useContext(RenderedHostelContext);
  if (hostelId === undefined) {
    throw new Error("useRenderedHostelId() needs a <RenderedHostel> above it. Wrap the page that renders this form.");
  }
  return hostelId ?? "";
}

/**
 * A staff write action with the rendered PG bound as its first argument.
 *
 *   const save = useHostelBound(saveMenu);   // saveMenu(renderedHostelId, cells)
 *   const { run } = useAction(save);          // run(cells)
 *
 * Server Action references support .bind() on the client (Next.js "passing additional
 * arguments"): the bound value travels with every call exactly as a normal argument would.
 */
export function useHostelBound<A extends unknown[], R>(action: (renderedHostelId: string, ...args: A) => R): (...args: A) => R {
  const hostelId = useRenderedHostelId();
  return React.useMemo(() => action.bind(null, hostelId), [action, hostelId]);
}
