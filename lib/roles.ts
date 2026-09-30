/** Shared role constants — safe to import from client, server and middleware. */

export const ROLES = ["super_admin", "owner", "manager", "warden", "student"] as const;
export type UserRole = (typeof ROLES)[number];

export const ROLE_HOME: Record<UserRole, string> = {
  super_admin: "/super-admin",
  owner: "/owner",
  manager: "/manager",
  warden: "/warden",
  student: "/student",
};

export const ROLE_LABEL: Record<UserRole, string> = {
  super_admin: "Super Admin",
  owner: "Owner",
  manager: "Manager",
  warden: "Warden",
  student: "Student",
};

/** Roles that get the desktop (sidebar) shell vs the mobile (bottom-nav) shell */
export const DESKTOP_ROLES: UserRole[] = ["super_admin", "owner", "manager"];
export const MOBILE_ROLES: UserRole[] = ["warden", "student"];

/** Which role owns a route prefix. Returns null for shared/public paths. */
export function roleForPath(pathname: string): UserRole | null {
  for (const role of ROLES) {
    const home = ROLE_HOME[role];
    if (pathname === home || pathname.startsWith(home + "/")) return role;
  }
  return null;
}

/**
 * Hard limits per hostel (Hard rule §4.3). Five managers and five wardens since 2026-09-12
 * (db/migrations/2026-09-12-five-staff-per-role.sql), counted as ACTIVE staff WITH ACCESS to the
 * PG (staff_hostel_access), not only the ones working in it right now. The database is the rule;
 * these numbers only drive the web's early messages and disabled buttons.
 */
export const ROLE_LIMITS = {
  manager: 5,
  warden: 5,
  student: 10_000,
} as const;

/** How many PGs one staff account may be given at creation (owner-create-staff accepts 1..20). */
export const MAX_STAFF_HOSTELS = 20;
