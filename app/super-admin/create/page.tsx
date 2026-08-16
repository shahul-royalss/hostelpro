import { requireRole } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { fetchOwners } from "@/lib/queries/super-admin";
import { PageHeader } from "@/components/shared/page-header";
import { CreateWizard } from "@/components/super-admin/create-wizard";

export const dynamic = "force-dynamic";

/** SA-2 — Create Owner & Hostel wizard (new owner, or a second hostel for an existing owner — §4.1) */
export default async function CreateOwnerHostelPage() {
  await requireRole("super_admin");
  const supabase = await createClient();
  const owners = await fetchOwners(supabase);
  return (
    <>
      <PageHeader
        title="Create owner & hostel"
        description="Set up a new customer in four steps — owner login (new or existing), hostel layout, subscription, then review."
      />
      <CreateWizard owners={owners} />
    </>
  );
}
