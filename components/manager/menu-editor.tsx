"use client";

import * as React from "react";
import { Coffee, Cookie, Moon, RotateCcw, Save, Sun, type LucideIcon } from "lucide-react";
import { saveMenu } from "@/lib/actions/manager";
import { useAction } from "@/hooks/use-action";
import { DAYS_OF_WEEK, DAY_LABEL, MEALS, MEAL_LABEL, MEAL_TIMING, type DayOfWeek, type MealType, type MenuRow } from "@/lib/types";
import { cn, formatDateTime } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { GlassCard } from "@/components/shared/glass-card";

const MEAL_ICON: Record<MealType, LucideIcon> = { breakfast: Coffee, lunch: Sun, snacks: Cookie, dinner: Moon };
const MAX_LEN = 400;

type Grid = Record<DayOfWeek, Record<MealType, string>>;

function cellKey(day: DayOfWeek, meal: MealType) {
  return `${day}-${meal}`;
}

function buildGrid(rows: MenuRow[]): Grid {
  const grid = {} as Grid;
  for (const day of DAYS_OF_WEEK) {
    grid[day] = {} as Record<MealType, string>;
    for (const meal of MEALS) grid[day][meal] = "";
  }
  for (const r of rows) {
    if (grid[r.day_of_week] && MEALS.includes(r.meal)) grid[r.day_of_week][r.meal] = r.items ?? "";
  }
  return grid;
}

function sameGrid(a: Grid, b: Grid) {
  return DAYS_OF_WEEK.every((d) => MEALS.every((m) => a[d][m] === b[d][m]));
}

/** Textarea that grows with its content (no scrollbars in the grid). */
function GrowingTextarea({
  value,
  onChange,
  disabled,
  ariaLabel,
}: {
  value: string;
  onChange: (v: string) => void;
  disabled?: boolean;
  ariaLabel: string;
}) {
  const ref = React.useRef<HTMLTextAreaElement>(null);
  React.useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.style.height = "0px";
    el.style.height = `${Math.max(el.scrollHeight, 64)}px`;
  }, [value]);
  const overLimit = value.length > MAX_LEN;
  return (
    <textarea
      ref={ref}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      disabled={disabled}
      rows={2}
      aria-label={ariaLabel}
      aria-invalid={overLimit || undefined}
      placeholder="e.g., Idli, sambar, chutney"
      className={cn(
        "block w-full resize-none overflow-hidden rounded-control border border-input bg-white/70 px-3 py-2 text-sm leading-relaxed text-charcoal transition-colors",
        "placeholder:text-muted/60 focus-visible:outline-none focus-visible:border-navy focus-visible:ring-1 focus-visible:ring-navy",
        "disabled:cursor-not-allowed disabled:opacity-60",
        overLimit && "border-red",
      )}
    />
  );
}

/** MG-4 weekly mess menu editor: day × meal grid with sticky Save/Reset footer. */
export function MenuEditor({ rows, writable }: { rows: MenuRow[]; writable: boolean }) {
  const initial = React.useMemo(() => buildGrid(rows), [rows]);
  const [grid, setGrid] = React.useState<Grid>(initial);
  const [saved, setSaved] = React.useState<Grid>(initial);

  // When the server sends fresh rows (after a save/refresh) re-baseline the editor.
  React.useEffect(() => {
    setGrid(initial);
    setSaved(initial);
  }, [initial]);

  const dirty = !sameGrid(grid, saved);
  const tooLong = DAYS_OF_WEEK.some((d) => MEALS.some((m) => grid[d][m].length > MAX_LEN));
  const filled = DAYS_OF_WEEK.reduce((n, d) => n + MEALS.filter((m) => grid[d][m].trim().length > 0).length, 0);
  const lastUpdated = rows.reduce<string | null>((latest, r) => (!latest || r.updated_at > latest ? r.updated_at : latest), null);

  const { run, pending } = useAction(saveMenu, {
    onSuccess: () => setSaved(grid),
  });

  const setCell = (day: DayOfWeek, meal: MealType, value: string) =>
    setGrid((g) => ({ ...g, [day]: { ...g[day], [meal]: value } }));

  const onSave = () => {
    if (!dirty || tooLong) return;
    const cells = DAYS_OF_WEEK.flatMap((day) => MEALS.map((meal) => ({ day, meal, items: grid[day][meal] })));
    void run(cells);
  };

  const onReset = () => setGrid(saved);
  const locked = !writable || pending;

  return (
    <div>
      <GlassCard padded={false} className="overflow-hidden">
        {/* Desktop / tablet grid */}
        <div className="hidden md:block">
          <div className="grid grid-cols-[120px_repeat(4,minmax(0,1fr))] border-b border-line/70 bg-white/40">
            <div className="label-caps px-5 py-3">Day</div>
            {MEALS.map((meal) => {
              const Icon = MEAL_ICON[meal];
              return (
                <div key={meal} className="px-3 py-3">
                  <div className="flex items-center gap-1.5 text-sm font-semibold text-navy">
                    <Icon className="h-4 w-4 text-navy/60" strokeWidth={1.75} /> {MEAL_LABEL[meal]}
                  </div>
                  <div className="mt-0.5 text-[11px] text-muted">{MEAL_TIMING[meal]}</div>
                </div>
              );
            })}
          </div>
          <div className="divide-y divide-line/60">
            {DAYS_OF_WEEK.map((day) => (
              <div key={day} className="grid grid-cols-[120px_repeat(4,minmax(0,1fr))] items-start gap-x-3 px-2 py-3">
                <div className="px-3 pt-2 text-sm font-semibold text-navy">{DAY_LABEL[day]}</div>
                {MEALS.map((meal) => (
                  <div key={cellKey(day, meal)} className="px-1">
                    <GrowingTextarea
                      value={grid[day][meal]}
                      onChange={(v) => setCell(day, meal, v)}
                      disabled={locked}
                      ariaLabel={`${DAY_LABEL[day]} ${MEAL_LABEL[meal]}`}
                    />
                  </div>
                ))}
              </div>
            ))}
          </div>
        </div>

        {/* Mobile: one stacked card per day */}
        <div className="divide-y divide-line/60 md:hidden">
          {DAYS_OF_WEEK.map((day) => (
            <section key={day} className="p-4">
              <h3 className="mb-3 text-[15px] font-semibold text-navy">{DAY_LABEL[day]}</h3>
              <div className="space-y-3">
                {MEALS.map((meal) => {
                  const Icon = MEAL_ICON[meal];
                  return (
                    <div key={cellKey(day, meal)}>
                      <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-charcoal">
                        <Icon className="h-3.5 w-3.5 text-navy/60" strokeWidth={1.75} /> {MEAL_LABEL[meal]}
                        <span className="text-muted">· {MEAL_TIMING[meal]}</span>
                      </div>
                      <GrowingTextarea
                        value={grid[day][meal]}
                        onChange={(v) => setCell(day, meal, v)}
                        disabled={locked}
                        ariaLabel={`${DAY_LABEL[day]} ${MEAL_LABEL[meal]}`}
                      />
                    </div>
                  );
                })}
              </div>
            </section>
          ))}
        </div>
      </GlassCard>

      {/* Sticky footer */}
      <div className="sticky bottom-0 z-20 mt-4 pb-4">
        <div>
          <div className="glass-card-strong flex flex-col gap-3 rounded-card px-4 py-3 sm:flex-row sm:items-center sm:justify-between md:px-5">
            <div className="min-w-0 text-[13px] text-muted">
              <span className="font-medium text-navy">{filled}/{DAYS_OF_WEEK.length * MEALS.length}</span> meals filled
              {dirty ? <span className="ml-2 text-sand-deep">· Unsaved changes</span> : lastUpdated ? <span className="ml-2">· Last saved {formatDateTime(lastUpdated)}</span> : null}
              {tooLong ? <span className="ml-2 text-red">· A cell is over {MAX_LEN} characters</span> : null}
              {!writable ? <span className="ml-2 text-red">· Read-only — subscription expired</span> : null}
            </div>
            <div className="flex shrink-0 items-center gap-2">
              <Button type="button" variant="ghost" onClick={onReset} disabled={!dirty || locked}>
                <RotateCcw /> Reset
              </Button>
              <Button type="button" onClick={onSave} loading={pending} disabled={!writable || !dirty || tooLong}>
                <Save /> Save menu
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
