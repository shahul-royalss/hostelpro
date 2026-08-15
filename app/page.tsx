import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/permissions";
import { ROLE_HOME } from "@/lib/roles";

/** "/" → role home when signed in, otherwise /login (middleware also handles this). */
export default async function RootPage() {
  const user = await getSessionUser();
  if (user) redirect(ROLE_HOME[user.role]);
  redirect("/login");
}
