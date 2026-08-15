import type { LucideIcon } from "lucide-react";
import {
  Bed,
  BedDouble,
  Building2,
  CalendarOff,
  ClipboardList,
  CreditCard,
  Home,
  IndianRupee,
  LayoutDashboard,
  ListChecks,
  Megaphone,
  MessageSquareWarning,
  PlusCircle,
  Receipt,
  UserCircle,
  UserPlus,
  Users,
  UtensilsCrossed,
  Wallet,
  Contact,
} from "lucide-react";
import type { UserRole } from "@/lib/roles";

export interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
  /** exact match only (used for the role home) */
  exact?: boolean;
  /** mobile: render as raised center action */
  center?: boolean;
}

/** Sidebar / bottom-nav items per role — labels match DESIGN.md screen prompts. */
export const NAV: Record<UserRole, NavItem[]> = {
  super_admin: [
    { href: "/super-admin", label: "Dashboard", icon: LayoutDashboard, exact: true },
    { href: "/super-admin/hostels", label: "Hostels", icon: Building2 },
    { href: "/super-admin/subscriptions", label: "Subscriptions", icon: CreditCard },
    { href: "/super-admin/create", label: "Create Owner", icon: PlusCircle },
  ],
  owner: [
    { href: "/owner", label: "Dashboard", icon: LayoutDashboard, exact: true },
    { href: "/owner/complaints", label: "Complaints", icon: MessageSquareWarning },
    { href: "/owner/updates", label: "Updates", icon: Megaphone },
    { href: "/owner/staff", label: "Staff", icon: Contact },
    { href: "/owner/students", label: "Students", icon: Users },
    { href: "/owner/finance", label: "Finance", icon: Wallet },
  ],
  manager: [
    { href: "/manager", label: "Dashboard", icon: LayoutDashboard, exact: true },
    { href: "/manager/expenses", label: "Expenses", icon: Receipt },
    { href: "/manager/revenue", label: "Revenue", icon: IndianRupee },
    { href: "/manager/tasks", label: "Tasks", icon: ListChecks },
    { href: "/manager/menu", label: "Menu", icon: UtensilsCrossed },
  ],
  // Mobile bottom nav (WD-1): Home, Rooms, Register (center), Fees, More(Leaves)
  warden: [
    { href: "/warden", label: "Home", icon: Home, exact: true },
    { href: "/warden/rooms", label: "Rooms", icon: BedDouble },
    { href: "/warden/register", label: "Register", icon: UserPlus, center: true },
    { href: "/warden/fees", label: "Fees", icon: Wallet },
    { href: "/warden/leaves", label: "Leaves", icon: CalendarOff },
  ],
  // ST-1: Home, Menu, Complaints, Room, Profile
  student: [
    { href: "/student", label: "Home", icon: Home, exact: true },
    { href: "/student/menu", label: "Menu", icon: UtensilsCrossed },
    { href: "/student/complaints", label: "Complaints", icon: ClipboardList },
    { href: "/student/room", label: "Room", icon: Bed },
    { href: "/student/profile", label: "Profile", icon: UserCircle },
  ],
};

/** Secondary warden pages reachable from Home tiles / "More" (not in bottom nav) */
export const WARDEN_MORE: NavItem[] = [
  { href: "/warden/visitors", label: "Visitors", icon: Users },
  { href: "/warden/complaints", label: "Complaints", icon: MessageSquareWarning },
];

export function isActive(pathname: string, item: NavItem) {
  if (item.exact) return pathname === item.href;
  return pathname === item.href || pathname.startsWith(item.href + "/");
}
