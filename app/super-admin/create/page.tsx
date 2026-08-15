import { requireRole } from "@/lib/permissions";
import { PageHeader } from "@/components/shared/page-header";
import { CreateWizard } from "@/components/super-admin/create-wizard";

export const dynamic = "force-dynamic";

/** SA-2 — Create Owner & Hostel wizard */
export default async function CreateOwnerHostelPage() {
  await requireRole("super_admin");
  return (
    <>
      <PageHeader
        title="Create owner & hostel"
        description="Set up a new customer in four steps — owner login, hostel layout, subscription, then review."
      />
      <CreateWizard />
    </>
  );
}
