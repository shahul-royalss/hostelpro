import { MobilePage } from "@/components/shell/role-shells";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { signedUrl } from "@/lib/storage";
import { getFeeLedger } from "@/lib/queries/warden";
import { FeesView } from "@/components/warden/fees-view";
import { formatPeriodMonth, toPeriodMonth } from "@/lib/utils";

export const dynamic = "force-dynamic";

const PERIOD = /^\d{4}-(0[1-9]|1[0-2])$/;

/** WD-5 · Fees tracker — month chips, collected vs pending, filterable ledger, record-payment sheet. */
export default async function WardenFeesPage({ searchParams }: { searchParams: Promise<{ month?: string }> }) {
  const { ctx } = await requireHostelContext("warden");
  const { month } = await searchParams;
  const period = typeof month === "string" && PERIOD.test(month) ? month : toPeriodMonth();

  const supabase = await createClient();
  const ledger = await getFeeLedger(supabase, ctx.hostel.id, period);
  const photoUrls = await Promise.all(ledger.map((r) => (r.photo_url ? signedUrl("student-docs", r.photo_url, ctx.hostel.id) : Promise.resolve(null))));
  const rows = ledger.map((r, i) => ({ ...r, photoUrl: photoUrls[i] }));

  return (
    <MobilePage role="warden" title="Fees" subtitle={`${formatPeriodMonth(period)} · ${ctx.hostel.name}`} backHref="/warden">
      <FeesView period={period} rows={rows} writable={ctx.writable} />
    </MobilePage>
  );
}
