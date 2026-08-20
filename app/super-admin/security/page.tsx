import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { fetchAuditLog, fetchSecurityAlerts } from "@/lib/queries/super-admin";
import { PageHeader } from "@/components/shared/page-header";
import { SecurityConsole } from "@/components/super-admin/security-console";

export const dynamic = "force-dynamic";

/** SA-5 — security console: alerts raised from the audit trail, and the trail itself. */
export default async function SecurityPage() {
  await requireRole("super_admin");
  const supabase = await createClient();
  const [alerts, audit] = await Promise.all([
    fetchSecurityAlerts(supabase, { limit: 200 }),
    fetchAuditLog(supabase, { limit: 300 }),
  ]);
  const open = alerts.filter((a) => !a.acknowledged_at).length;

  return (
    <>
      <PageHeader
        title="Security"
        description={
          open === 0
            ? "No open alerts. Detection runs on every audit event."
            : `${open} alert${open === 1 ? "" : "s"} need${open === 1 ? "s" : ""} attention`
        }
      />
      <SecurityConsole alerts={alerts} audit={audit} />
    </>
  );
}
