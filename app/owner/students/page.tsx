import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getStudentsDirectory, type StudentFeeFilter } from "@/lib/queries/owner";
import { formatNumber, formatPeriodMonth } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { StudentsTable } from "@/components/owner/students-table";

export const dynamic = "force-dynamic";

const FEE_FILTERS: StudentFeeFilter[] = ["all", "paid", "partial", "unpaid"];

/** OW-5 — Students directory (read-only). Search / filters / paging live in the URL and run server-side. */
export default async function OwnerStudentsPage({ searchParams }: { searchParams: Promise<{ q?: string; floor?: string; fee?: string; page?: string }> }) {
  const { ctx } = await requireHostelContext("owner");
  const sp = await searchParams;
  const q = typeof sp.q === "string" ? sp.q.slice(0, 80) : "";
  const floor = sp.floor && /^\d{1,3}$/.test(sp.floor) ? Number(sp.floor) : null;
  const fee: StudentFeeFilter = FEE_FILTERS.includes(sp.fee as StudentFeeFilter) ? (sp.fee as StudentFeeFilter) : "all";
  const page = sp.page && /^\d{1,6}$/.test(sp.page) ? Math.max(1, Number(sp.page)) : 1;

  const supabase = await createClient();
  const result = await getStudentsDirectory(supabase, ctx.hostel.id, { q, floor, fee, page });
  const due = result.counts.partial + result.counts.unpaid;

  return (
    <>
      <PageHeader
        title="Students"
        description={`${formatNumber(result.counts.all)} resident${result.counts.all === 1 ? "" : "s"} at ${ctx.hostel.name} · ${formatNumber(due)} with fees due for ${formatPeriodMonth(result.period)}. Registration and edits happen in the warden app.`}
      />
      <StudentsTable result={result} params={{ q, floor, fee }} />
    </>
  );
}
