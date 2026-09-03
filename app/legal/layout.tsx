import type { Metadata } from "next";
import Link from "next/link";
import { Building2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

/**
 * Public legal shell.
 *
 * Signed-out safe by construction: this file imports nothing that reads a session,
 * a cookie or the database. "/legal" is listed in PUBLIC_PATHS in
 * lib/supabase/middleware.ts, so every page under it renders for an anonymous
 * visitor — which is what the Play Console requires of a privacy policy URL.
 */

const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? "NIVORA";

export const metadata: Metadata = {
  // The rest of the app is deliberately noindex (private workspace). The legal
  // pages are the one part that is meant to be publicly readable.
  robots: { index: true, follow: true },
};

const NAV = [
  { href: "/legal", label: "Overview" },
  { href: "/legal/privacy", label: "Privacy Policy" },
  { href: "/legal/terms", label: "Terms of Use" },
  { href: "/legal/account-deletion", label: "Delete your data" },
] as const;

export default function LegalLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-dvh">
      <header className="glass-bar sticky top-0 z-20 border-b">
        <div className="mx-auto flex w-full max-w-4xl items-center justify-between gap-4 px-page-mobile py-3 md:px-page-desktop">
          <Link
            href="/legal"
            className="flex items-center gap-3 rounded-control focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-navy/30"
          >
            <span className="flex h-9 w-9 items-center justify-center rounded-control bg-navy text-white shadow-sm">
              <Building2 className="h-4 w-4" strokeWidth={1.75} />
            </span>
            <span className="leading-tight">
              <span className="block text-card-title text-navy">{APP_NAME}</span>
              <span className="label-caps block">Legal</span>
            </span>
          </Link>
          <Button asChild variant="secondary" size="sm">
            <Link href="/login">Sign in</Link>
          </Button>
        </div>
        <nav aria-label="Legal documents" className="border-t border-white/50">
          <ul className="no-scrollbar mx-auto flex w-full max-w-4xl gap-1 overflow-x-auto px-page-mobile py-2 md:px-page-desktop">
            {NAV.map((item) => (
              <li key={item.href}>
                <Link
                  href={item.href}
                  className="block whitespace-nowrap rounded-control px-3 py-1.5 text-sm text-muted transition-colors hover:bg-white/70 hover:text-navy focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-navy/30"
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </header>

      <main className="mx-auto w-full max-w-4xl px-page-mobile py-8 md:px-page-desktop md:py-12">
        {children}
      </main>

      <footer className="mx-auto w-full max-w-4xl px-page-mobile pb-12 md:px-page-desktop">
        <div className="border-t border-line pt-6 text-sm text-muted">
          <div className="flex flex-wrap items-center gap-x-5 gap-y-2">
            {NAV.map((item) => (
              <Link key={item.href} href={item.href} className="hover:text-navy">
                {item.label}
              </Link>
            ))}
            <Link href="/login" className="hover:text-navy">
              Sign in
            </Link>
          </div>
          <p className="mt-4 text-caption uppercase tracking-[0.05em] text-muted/80">
            © {new Date().getFullYear()} {APP_NAME}. Accounts are created by your hostel
            administrator — there is no public sign-up.
          </p>
        </div>
      </footer>
    </div>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
 * Shared presentation used by the documents under /legal. Kept here so the
 * pages hold text and nothing else, and so they read as one document set.
 * ──────────────────────────────────────────────────────────────────────────── */

/** ISO date → "21 August 2026". Evaluated at build time; these pages are static. */
function formatDate(iso: string) {
  return new Date(iso + "T00:00:00Z").toLocaleDateString("en-GB", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}

/** Page header for a legal document. */
export function DocHeader({
  title,
  summary,
  updated,
}: {
  title: string;
  summary: string;
  updated: string;
}) {
  return (
    <div className="mb-8">
      <span className="label-caps">{APP_NAME}</span>
      <h1 className="mt-1 text-title text-navy md:text-[32px] md:leading-10">{title}</h1>
      <p className="mt-3 max-w-2xl text-[15px] leading-7 text-charcoal/90">{summary}</p>
      <p className="mt-4 text-sm text-muted">
        Last updated <time dateTime={updated}>{formatDate(updated)}</time>
      </p>
    </div>
  );
}

/** Frosted sheet the document body sits on. */
export function DocBody({ children }: { children: React.ReactNode }) {
  return <div className="glass-card space-y-10 p-6 md:p-10">{children}</div>;
}

/** A linkable section. Prose styling is applied to plain HTML children. */
export function Section({
  id,
  title,
  children,
}: {
  id: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="scroll-mt-32">
      <h2 className="text-title-sm text-navy">{title}</h2>
      <div
        className={cn(
          "mt-3 space-y-4 text-[15px] leading-7 text-charcoal/90",
          "[&_strong]:font-semibold [&_strong]:text-navy",
          "[&_ul]:list-disc [&_ul]:space-y-2 [&_ul]:pl-5",
          "[&_ol]:list-decimal [&_ol]:space-y-2 [&_ol]:pl-5",
          "[&_a]:text-teal [&_a]:underline [&_a]:underline-offset-2 hover:[&_a]:text-navy",
          "[&_h3]:pt-2 [&_h3]:text-card-title [&_h3]:text-navy",
        )}
      >
        {children}
      </div>
    </section>
  );
}

/** Contents list at the top of a long document. */
export function TableOfContents({
  items,
}: {
  items: ReadonlyArray<{ id: string; title: string }>;
}) {
  return (
    <nav aria-label="Contents" className="glass-card-strong mb-6 p-5 md:p-6">
      <p className="label-caps">Contents</p>
      <ol className="mt-3 grid gap-x-8 gap-y-1.5 text-sm md:grid-cols-2">
        {items.map((item, i) => (
          <li key={item.id} className="flex gap-2">
            <span className="tabular text-muted">{i + 1}.</span>
            <a href={"#" + item.id} className="text-navy hover:underline hover:underline-offset-2">
              {item.title}
            </a>
          </li>
        ))}
      </ol>
    </nav>
  );
}

/** Tinted aside. "teal" = plain-English summary, "sand" = something to act on. */
export function Callout({
  tone = "teal",
  title,
  children,
}: {
  tone?: "teal" | "sand";
  title?: string;
  children: React.ReactNode;
}) {
  return (
    <div
      className={cn(
        "rounded-card border p-5",
        tone === "teal" && "border-teal/20 bg-teal-soft/70",
        tone === "sand" && "border-sand/40 bg-sand-soft/80",
      )}
    >
      {title ? (
        <p className={cn("mb-2 text-card-title", tone === "teal" ? "text-teal" : "text-sand-deep")}>
          {title}
        </p>
      ) : null}
      <div className="space-y-3 text-sm leading-6 text-charcoal/90 [&_a]:text-navy [&_a]:underline [&_a]:underline-offset-2 [&_strong]:font-semibold [&_strong]:text-navy [&_ul]:list-disc [&_ul]:space-y-1.5 [&_ul]:pl-5">
        {children}
      </div>
    </div>
  );
}

/** Small data table that scrolls horizontally rather than breaking the layout. */
export function DataTable({
  head,
  rows,
}: {
  head: readonly string[];
  rows: ReadonlyArray<readonly React.ReactNode[]>;
}) {
  return (
    <div className="-mx-1 overflow-x-auto px-1">
      <table className="w-full min-w-[520px] border-collapse text-left text-sm">
        <thead>
          <tr className="border-b border-line">
            {head.map((h) => (
              <th
                key={h}
                scope="col"
                className="py-2 pr-4 align-bottom text-caption uppercase tracking-[0.05em] text-muted"
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className="border-b border-line/70 align-top last:border-0">
              {row.map((cell, j) => (
                <td
                  key={j}
                  className={cn("py-2.5 pr-4 leading-6", j === 0 && "font-medium text-navy")}
                >
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
