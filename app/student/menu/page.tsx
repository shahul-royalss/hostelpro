import { MobilePage } from "@/components/shell/role-shells";
import { MenuView } from "@/components/student/menu-view";
import { requireHostelContext } from "@/lib/permissions";
import { createClient } from "@/lib/supabase/server";
import { getMenus } from "@/lib/queries/student";
import { MEALS, type DayOfWeek, type MealType } from "@/lib/types";

const DAY_KEYS: DayOfWeek[] = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
const MEAL_END: Record<MealType, number> = { breakfast: 9 * 60 + 30, lunch: 14 * 60 + 30, snacks: 18 * 60, dinner: 22 * 60 };

export default async function StudentMenuPage() {
  const { ctx } = await requireHostelContext("student");
  const supabase = await createClient();
  const menus = await getMenus(supabase, ctx.hostel.id);

  // Initial values from the server clock; the client re-syncs to the device clock on mount.
  const now = new Date();
  const minutes = now.getHours() * 60 + now.getMinutes();
  const initialNext = MEALS.find((m) => minutes < MEAL_END[m]) ?? null;

  return (
    <MobilePage role="student" title="Mess menu" subtitle="Plan your meals for the week">
      <MenuView menus={menus} initialDay={DAY_KEYS[now.getDay()]} initialNext={initialNext} />
    </MobilePage>
  );
}
