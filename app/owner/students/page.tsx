import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getStudentsDirectory } from "@/lib/queries/owner";
import { formatNumber, formatPeriodMonth, toPeriodMonth } from "@/lib/utils";
import { PageHeader } from "@/components/shared/page-header";
import { StudentsTable } from "@/components/owner/students-table";

export const dynamic = "force-dynamic";

/** OW-5 — Students directory (read-only) with slide-over profile. */
export default async function OwnerStudentsPage() {
  const { ctx } = await requireHostelContext("owner");
  const supabase = await createClient();
  const { students, floors } = await getStudentsDirectory(supabase, ctx.hostel.id);
  const unpaid = students.filter((s) => s.fee_status !== "paid").length;

  return (
    <>
      <PageHeader
        title="Students"
        description={`${formatNumber(students.length)} resident${students.length === 1 ? "" : "s"} at ${ctx.hostel.name} · ${unpaid} with fees due for ${formatPeriodMonth(toPeriodMonth())}. Registration and edits happen in the warden app.`}
      />
      <StudentsTable students={students} floors={floors} />
    </>
  );
}
