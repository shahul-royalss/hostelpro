"use client";

import * as React from "react";
import { Building2, Check } from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import type { UserRole } from "@/lib/roles";
import { switchHostel, switchStaffHostel } from "@/lib/actions/session";
import { DropdownMenuItem, DropdownMenuLabel } from "@/components/ui/dropdown-menu";

export interface SwitchableHostel {
  id: string;
  name: string;
}

/**
 * Who gets a hostel switcher, and through which action.
 *
 * Two different mechanisms, deliberately never mixed:
 *  • owner   → switchHostel(): an owner-only action that sets the active-hostel cookie for this
 *              browser, then a full reload of /owner.
 *  • manager / warden → switchStaffHostel(): staff_switch_hostel moves users.hostel_id, and the
 *              action redirects to the role's home itself.
 * A staff member is never shown the owner switcher and never calls the owner action; any other
 * role gets no switcher at all. The server enforces the same split (assertRole in each action),
 * so this is the convenience half.
 */
export function canSwitchHostel(role: UserRole): role is "owner" | "manager" | "warden" {
  return role === "owner" || role === "manager" || role === "warden";
}

/**
 * The switch function for a role. Call it in a component that STAYS MOUNTED (the menu's owner,
 * not an item inside the menu): the dropdown unmounts its content on select, and the pending
 * state and error toast belong to what is still on screen.
 */
export function useHostelSwitch(role: UserRole, currentId?: string | null) {
  const [pending, start] = React.useTransition();

  const switchTo = React.useCallback(
    (hostelId: string) => {
      if (hostelId === currentId || !canSwitchHostel(role)) return;
      start(async () => {
        if (role === "owner") {
          const res = await switchHostel(hostelId);
          if (!res.ok) toast.error(res.error);
          else window.location.assign("/owner");
          return;
        }
        // On success this does not return: the action redirects to the role's home.
        const res = await switchStaffHostel(hostelId);
        if (res && !res.ok) toast.error(res.error);
      });
    },
    [role, currentId],
  );

  return { switchTo, pending };
}

/** The list inside a dropdown: a label, one row per hostel, the current one ticked. */
export function HostelSwitchItems({
  role,
  label,
  hostels,
  currentId,
  pending,
  onSwitch,
}: {
  role: UserRole;
  label: string;
  hostels: SwitchableHostel[];
  currentId?: string | null;
  pending: boolean;
  onSwitch: (hostelId: string) => void;
}) {
  return (
    <>
      <DropdownMenuLabel>{label}</DropdownMenuLabel>
      {hostels.map((h) => {
        const current = h.id === currentId;
        return (
          <DropdownMenuItem
            key={h.id}
            disabled={pending}
            onSelect={() => onSwitch(h.id)}
            aria-current={current ? "true" : undefined}
            className={cn(current && "font-semibold text-navy")}
          >
            <Building2 />
            <span className="min-w-0 flex-1 truncate">{h.name}</span>
            {current ? <Check className="text-teal" /> : null}
          </DropdownMenuItem>
        );
      })}
      {/* users.hostel_id is one value for the whole account, so this is not a per-device choice. */}
      {role !== "owner" ? <p className="px-2 pb-1.5 pt-1 text-[11px] leading-snug text-muted">This also switches the PG on your other devices.</p> : null}
    </>
  );
}
