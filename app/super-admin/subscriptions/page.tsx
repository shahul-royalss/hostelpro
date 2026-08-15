import Link from "next/link";
import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { fetchAllSubscriptionsByHostel, fetchSaHostels } from "@/lib/queries/super-admin";
import { formatINR } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { Button } from "@/components/ui/button";
import { SubscriptionsTable } from "@/components/super-admin/subscriptions-table";

export const dynamic = "force-dynamic";

const FILTERS = ["all", "active", "expiring", "expired"] as const;
type Filter = (typeof FILTERS)[number];

/** SA-3 — Subscriptions table + slide-over history */
export default async function SubscriptionsPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  await requireRole("super_admin");
  const supabase = await createClient();
  const { status } = await searchParams;
  const initialFilter: Filter = FILTERS.includes(status as Filter) ? (status as Filter) : "all";

  const [rows, history] = await Promise.all([fetchSaHostels(supabase), fetchAllSubscriptionsByHostel(supabase)]);
  const revenue = rows.reduce((s, r) => s + (r.sub_state !== "expired" ? Number(r.sub_amount ?? 0) : 0), 0);

  return (
    <>
      <PageHeader
        title="Subscriptions"
        description={`${rows.length} hostel subscription${rows.length === 1 ? "" : "s"} · ${formatINR(revenue)} across active periods`}
        actions={
          <Button asChild>
            <Link href="/super-admin/create">Create owner &amp; hostel</Link>
          </Button>
        }
      />
      <SubscriptionsTable rows={rows} history={history} initialFilter={initialFilter} />
    </>
  );
}
