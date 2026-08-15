import Link from "next/link";
import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { fetchSaHostels } from "@/lib/queries/super-admin";
import { formatNumber } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { Button } from "@/components/ui/button";
import { HostelsTable } from "@/components/super-admin/hostels-table";

export const dynamic = "force-dynamic";

/** /super-admin/hostels — all hostels on the platform (monitoring list) */
export default async function HostelsPage() {
  await requireRole("super_admin");
  const supabase = await createClient();
  const rows = await fetchSaHostels(supabase);
  const beds = rows.reduce((s, r) => s + r.total_beds, 0);
  const occupied = rows.reduce((s, r) => s + r.occupied_beds, 0);

  return (
    <>
      <PageHeader
        title="Hostels"
        description={`${formatNumber(rows.length)} hostel${rows.length === 1 ? "" : "s"} · ${formatNumber(occupied)} of ${formatNumber(beds)} beds occupied platform-wide`}
        actions={
          <Button asChild>
            <Link href="/super-admin/create">Create owner &amp; hostel</Link>
          </Button>
        }
      />
      <HostelsTable rows={rows} />
    </>
  );
}
