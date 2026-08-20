"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, Check, Shield, ShieldAlert } from "lucide-react";
import type { AuditRow, SecurityAlertRow } from "@/lib/queries/super-admin";
import { acknowledgeAlert } from "@/lib/actions/security";
import { cn, formatDate } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { GlassCard } from "@/components/shared/glass-card";
import { SegmentedPills } from "@/components/shared/segmented";
import { EmptyState } from "@/components/shared/empty-state";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const SEVERITY_STYLE: Record<SecurityAlertRow["severity"], string> = {
  critical: "bg-red/15 text-red border-red/30",
  high: "bg-red/10 text-red border-red/25",
  medium: "bg-sand/25 text-navy border-sand/50",
  low: "bg-sage/20 text-navy border-sage/40",
};

function SeverityPill({ severity }: { severity: SecurityAlertRow["severity"] }) {
  return (
    <span className={cn("inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium capitalize", SEVERITY_STYLE[severity])}>
      {severity}
    </span>
  );
}

function timeAgo(iso: string) {
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.floor(hrs / 24)}d ago`;
}

/**
 * SA-5 — security console.
 *
 * The audit trail and its alerts previously had no reader. "Logged" and "monitored" are not
 * the same thing: a detection that nobody can see is not a control. This is the reader.
 */
export function SecurityConsole({ alerts, audit }: { alerts: SecurityAlertRow[]; audit: AuditRow[] }) {
  const router = useRouter();
  const [showAcked, setShowAcked] = React.useState(false);
  const [pending, setPending] = React.useState<number | null>(null);
  const [query, setQuery] = React.useState("");

  const visible = showAcked ? alerts : alerts.filter((a) => !a.acknowledged_at);
  const openCount = alerts.filter((a) => !a.acknowledged_at).length;

  const ack = async (id: number) => {
    setPending(id);
    await acknowledgeAlert({ alertId: id });
    setPending(null);
    router.refresh();
  };

  const filteredAudit = React.useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return audit;
    return audit.filter(
      (r) =>
        r.action.toLowerCase().includes(q) ||
        (r.actor_role ?? "").toLowerCase().includes(q) ||
        (r.ip ?? "").toLowerCase().includes(q) ||
        (r.target_type ?? "").toLowerCase().includes(q),
    );
  }, [audit, query]);

  return (
    <Tabs defaultValue="alerts" className="space-y-6">
      <TabsList>
        <TabsTrigger value="alerts">
          Alerts
          {openCount > 0 && (
            <span className="ml-2 rounded-full bg-red/15 px-2 py-0.5 text-xs font-semibold text-red">{openCount}</span>
          )}
        </TabsTrigger>
        <TabsTrigger value="audit">Audit trail</TabsTrigger>
      </TabsList>

      <TabsContent value="alerts">
        <GlassCard className="p-0">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-navy/10 p-4">
            <div className="flex items-center gap-2 text-sm text-muted">
              <ShieldAlert className="h-4 w-4" aria-hidden />
              {openCount === 0 ? "No open alerts" : `${openCount} open alert${openCount === 1 ? "" : "s"}`}
            </div>
            <SegmentedPills
              value={showAcked ? "all" : "open"}
              onChange={(v) => setShowAcked(v === "all")}
              ariaLabel="Filter alerts"
              options={[
                { value: "open", label: "Open" },
                { value: "all", label: "All" },
              ]}
            />
          </div>

          {visible.length === 0 ? (
            <EmptyState
              icon={Shield}
              title={showAcked ? "No alerts recorded" : "Nothing needs attention"}
              description="Alerts are raised automatically from the audit trail — repeated failed sign-ins, authorization probing, failed second factors, and admin password resets."
            />
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Severity</TableHead>
                    <TableHead>What happened</TableHead>
                    <TableHead>When</TableHead>
                    <TableHead>IP</TableHead>
                    <TableHead className="text-right">Action</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visible.map((a) => (
                    <TableRow key={a.id} className={cn(a.acknowledged_at && "opacity-55")}>
                      <TableCell>
                        <SeverityPill severity={a.severity} />
                      </TableCell>
                      <TableCell>
                        <div className="font-medium text-navy">{a.summary}</div>
                        <div className="font-mono text-xs text-muted">{a.kind}</div>
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-sm text-muted" title={formatDate(a.at)}>
                        {timeAgo(a.at)}
                      </TableCell>
                      <TableCell className="font-mono text-xs text-muted">{a.ip ?? "—"}</TableCell>
                      <TableCell className="text-right">
                        {a.acknowledged_at ? (
                          <span className="inline-flex items-center gap-1 text-xs text-muted">
                            <Check className="h-3.5 w-3.5" aria-hidden /> Acknowledged
                          </span>
                        ) : (
                          <Button size="sm" variant="outline" disabled={pending === a.id} onClick={() => ack(a.id)}>
                            {pending === a.id ? "Saving…" : "Acknowledge"}
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </GlassCard>
      </TabsContent>

      <TabsContent value="audit">
        <GlassCard className="p-0">
          <div className="border-b border-navy/10 p-4">
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Filter by action, role, IP…"
              aria-label="Filter the audit trail"
              className="max-w-sm"
            />
          </div>
          {filteredAudit.length === 0 ? (
            <EmptyState icon={AlertTriangle} title="Nothing matches" description="Try a different search term." />
          ) : (
            <div className="max-h-[32rem] overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>When</TableHead>
                    <TableHead>Action</TableHead>
                    <TableHead>Actor</TableHead>
                    <TableHead>Target</TableHead>
                    <TableHead>IP</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredAudit.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="whitespace-nowrap text-sm text-muted" title={formatDate(r.at)}>
                        {timeAgo(r.at)}
                      </TableCell>
                      <TableCell className="font-mono text-xs text-navy">{r.action}</TableCell>
                      <TableCell className="text-sm capitalize text-muted">{r.actor_role ?? "—"}</TableCell>
                      <TableCell className="text-sm text-muted">{r.target_type ?? "—"}</TableCell>
                      <TableCell className="font-mono text-xs text-muted">{r.ip ?? "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </GlassCard>
      </TabsContent>
    </Tabs>
  );
}
