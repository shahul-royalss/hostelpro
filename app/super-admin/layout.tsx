import { DesktopRoleShell } from "@/components/shell/role-shells";

export default function Layout({ children }: { children: React.ReactNode }) {
  return <DesktopRoleShell role="super_admin">{children}</DesktopRoleShell>;
}
