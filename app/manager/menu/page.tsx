import { Info } from "lucide-react";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getMenu } from "@/lib/queries/manager";
import { PageHeader } from "@/components/shared/page-header";
import { MenuEditor } from "@/components/manager/menu-editor";

export const dynamic = "force-dynamic";

export default async function ManagerMenuPage() {
  const { ctx } = await requireHostelContext("manager");
  const supabase = await createClient();
  const rows = await getMenu(supabase, ctx.hostel.id);

  return (
    <>
      <PageHeader
        title="Weekly mess menu"
        description={
          <span className="inline-flex items-center gap-1.5">
            <Info className="h-3.5 w-3.5 text-teal" /> Students see this menu in their app.
          </span>
        }
      />
      <MenuEditor rows={rows} writable={ctx.writable} />
    </>
  );
}
