import Link from "next/link";
import { Building2 } from "lucide-react";
import { GlassCard } from "@/components/shared/glass-card";
import { EmptyState } from "@/components/shared/empty-state";
import { Button } from "@/components/ui/button";

/** Branded 404 for the Super Admin segment (unknown hostel id, bad UUID, …). */
export default function SuperAdminNotFound() {
  return (
    <GlassCard>
      <EmptyState
        icon={Building2}
        title="We couldn't find that hostel"
        description="It may have been removed, or the link is incomplete. Check the hostels list to find what you're looking for."
        action={
          <Button asChild>
            <Link href="/super-admin/hostels">Back to hostels</Link>
          </Button>
        }
      />
    </GlassCard>
  );
}
