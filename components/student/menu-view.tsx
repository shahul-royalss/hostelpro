"use client";

import * as React from "react";
import { Coffee, Cookie, Moon, UtensilsCrossed, type LucideIcon } from "lucide-react";
import { GlassCard } from "@/components/shared/glass-card";
import { EmptyState } from "@/components/shared/empty-state";
import { DAYS_OF_WEEK, DAY_LABEL, MEALS, MEAL_LABEL, MEAL_TIMING, type DayOfWeek, type MealType, type MenuRow } from "@/lib/types";
import { cn } from "@/lib/utils";

const MEAL_ICON: Record<MealType, LucideIcon> = {
  breakfast: Coffee,
  lunch: UtensilsCrossed,
  snacks: Cookie,
  dinner: Moon,
};

/** Meal windows in minutes-from-midnight (mirrors MEAL_TIMING labels). */
const MEAL_WINDOW: Record<MealType, [number, number]> = {
  breakfast: [7 * 60 + 30, 9 * 60 + 30],
  lunch: [12 * 60 + 30, 14 * 60 + 30],
  snacks: [17 * 60, 18 * 60],
  dinner: [20 * 60, 22 * 60],
};

const SHORT: Record<DayOfWeek, string> = { mon: "Mon", tue: "Tue", wed: "Wed", thu: "Thu", fri: "Fri", sat: "Sat", sun: "Sun" };

function todayKey(d = new Date()): DayOfWeek {
  // JS: 0 = Sunday
  return (["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as DayOfWeek[])[d.getDay()];
}

/** The first meal whose window hasn't ended yet today (null once dinner is over). */
function nextMeal(d = new Date()): MealType | null {
  const now = d.getHours() * 60 + d.getMinutes();
  return MEALS.find((m) => now < MEAL_WINDOW[m][1]) ?? null;
}

function splitItems(items: string): string[] {
  return items
    .split(/[\n,;•]+/)
    .map((s) => s.trim())
    .filter(Boolean);
}

export function MenuView({ menus, initialDay, initialNext }: { menus: MenuRow[]; initialDay: DayOfWeek; initialNext: MealType | null }) {
  const [day, setDay] = React.useState<DayOfWeek>(initialDay);
  const [today, setToday] = React.useState<DayOfWeek>(initialDay);
  const [next, setNext] = React.useState<MealType | null>(initialNext);

  // Server rendered with the server clock; align to the device clock after mount.
  React.useEffect(() => {
    const sync = () => {
      const t = todayKey();
      setToday(t);
      setNext(nextMeal());
    };
    sync();
    const id = window.setInterval(sync, 60_000);
    return () => window.clearInterval(id);
  }, []);

  React.useEffect(() => {
    // Keep the highlighted day in sync when the page was rendered around midnight.
    setDay((d) => (d === initialDay && initialDay !== today ? today : d));
  }, [today, initialDay]);

  const byMeal = React.useMemo(() => {
    const map = new Map<MealType, string>();
    for (const m of menus) if (m.day_of_week === day) map.set(m.meal, m.items);
    return map;
  }, [menus, day]);

  const hasAny = menus.some((m) => m.items.trim().length > 0);

  return (
    <div className="flex flex-col gap-4">
      <div role="tablist" aria-label="Day of week" className="no-scrollbar -mx-page-mobile flex gap-2 overflow-x-auto px-page-mobile pb-1">
        {DAYS_OF_WEEK.map((d) => {
          const active = d === day;
          const isToday = d === today;
          return (
            <button
              key={d}
              role="tab"
              type="button"
              aria-selected={active}
              onClick={() => setDay(d)}
              className={cn(
                "inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-4 py-2 text-sm font-medium transition-all active:scale-[0.97]",
                active
                  ? "bg-navy text-white shadow-sm"
                  : "border border-white/70 bg-white/60 text-muted backdrop-blur-md hover:text-navy",
              )}
            >
              {SHORT[d]}
              {isToday ? <span className={cn("text-[10px] uppercase tracking-wide", active ? "text-white/70" : "text-teal")}>Today</span> : null}
            </button>
          );
        })}
      </div>

      {!hasAny ? (
        <GlassCard>
          <EmptyState
            icon={UtensilsCrossed}
            title="Menu not set yet"
            description="The mess menu will appear here once the manager publishes it."
          />
        </GlassCard>
      ) : (
        <div className="flex flex-col gap-4">
          <div className="label-caps px-1">{DAY_LABEL[day]}</div>
          {MEALS.map((meal) => {
            const Icon = MEAL_ICON[meal];
            const items = splitItems(byMeal.get(meal) ?? "");
            const isNext = day === today && next === meal;
            return (
              <GlassCard key={meal} className={cn("relative overflow-hidden", isNext && "border-l-4 border-l-teal")}>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <span
                      className={cn(
                        "flex h-10 w-10 shrink-0 items-center justify-center rounded-full",
                        isNext ? "bg-teal-soft text-teal" : "bg-navy/5 text-navy",
                      )}
                    >
                      <Icon className="h-[18px] w-[18px]" strokeWidth={1.75} />
                    </span>
                    <div>
                      <div className="text-card-title font-semibold text-navy">{MEAL_LABEL[meal]}</div>
                      <div className="text-[12px] text-muted">{MEAL_TIMING[meal]}</div>
                    </div>
                  </div>
                  {isNext ? (
                    <span className="rounded-full bg-teal-soft px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wider text-teal">Next meal</span>
                  ) : null}
                </div>
                {items.length ? (
                  <ul className="mt-3 flex flex-wrap gap-x-2 gap-y-1 text-sm text-charcoal">
                    {items.map((it, i) => (
                      <li key={`${it}-${i}`} className="flex items-center gap-2">
                        {i > 0 ? <span className="h-1 w-1 rounded-full bg-line" aria-hidden /> : null}
                        <span>{it}</span>
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p className="mt-3 text-sm text-muted">Not set for this meal.</p>
                )}
              </GlassCard>
            );
          })}
        </div>
      )}
    </div>
  );
}
