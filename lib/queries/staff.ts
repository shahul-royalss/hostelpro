import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { HostelStatus } from "@/lib/types";

/**
 * Multi-PG staff helpers. A warden or manager can be allowed into several of their owner's PGs
 * (public.staff_hostel_access) and works in one at a time: users.hostel_id is the ACTIVE PG, and
 * every RLS policy keeps scoping to it through app.user_hostel_id().
 */

export interface StaffHostel {
  id: string;
  name: string;
  status: HostelStatus;
  /** the PG the account is working in right now (users.hostel_id) */
  isActive: boolean;
}

/**
 * Every PG the signed-in warden/manager is allowed into, ordered by name (my_staff_hostels).
 * Empty for any other role, which is what the RPC itself returns for them.
 *
 * Failure returns [] rather than throwing: this list only decides whether the Switch PG control
 * is drawn, and a staff member who cannot see it still works in their active PG exactly as
 * before. It must never take the whole page down with it.
 */
export async function getMyStaffHostels(supabase: SupabaseClient): Promise<StaffHostel[]> {
  const { data, error } = await supabase.rpc("my_staff_hostels");
  if (error || !Array.isArray(data)) return [];
  return (data as { hostel_id: string; name: string; status: HostelStatus; is_active: boolean }[]).map((h) => ({
    id: h.hostel_id,
    name: h.name,
    status: h.status,
    isActive: h.is_active,
  }));
}
