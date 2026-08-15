import { requireRole } from "@/lib/permissions";

/** Mobile roles render <MobilePage> per page (per-page titles); the layout only guards. */
export default async function Layout({ children }: { children: React.ReactNode }) {
  await requireRole("warden");
  return <>{children}</>;
}
