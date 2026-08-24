/**
 * Join class names. No merging, no conflict resolution — deliberately.
 *
 * ## Why this exists
 *
 * `cn()` in `lib/utils.ts` is `twMerge(clsx(...))`, and `tailwind-merge` ships
 * with Tailwind's *default* scales baked in. It has never been told about this
 * project's type ramp, so when it meets `text-stat` it cannot match it against
 * any known font-size and falls through to its text-**colour** group. The colour
 * that follows then "wins" the conflict and the size is dropped on the floor:
 *
 * ```
 * twMerge("tabular text-stat text-ink-navy")        -> "tabular text-ink-navy"
 * twMerge("text-title-sm md:text-title text-navy")  -> "md:text-title text-navy"
 * twMerge("text-card-title font-semibold text-navy") -> "font-semibold text-navy"
 * ```
 *
 * Every one of those is a real string this app builds at runtime, so on a phone
 * the 36px stat, the 22px page title and the 16px card title have all been
 * rendering at the inherited 14px. The whole ramp is invisible below `md:`
 * wherever a colour shares the same `cn()` call — which is nearly everywhere.
 *
 * ## The right fix, and where it belongs
 *
 * One `extendTailwindMerge` call in `lib/utils.ts` declaring the ramp as font
 * sizes fixes it for the entire app at once. That file is outside this change's
 * scope, so until it lands, anything in `components/dashboard/**` that puts a
 * ramp class and a colour class in the same string uses `cx` instead of `cn`.
 *
 * `cn` is still correct — and still used here — for merging a caller-supplied
 * `className` onto a base that carries no type-ramp class, which is what the
 * conflict resolution is genuinely for.
 */
export function cx(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(" ");
}
