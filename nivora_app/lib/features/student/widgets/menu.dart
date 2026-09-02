library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import 'common.dart';

/// The mess menu, as a resident reads it.
///
/// READS public.menus, through `weeklyMenuProvider` → [MenuRepository]. The manager writes
/// these rows and nobody else may; a resident's copy of this screen is read-only by RLS, not by
/// a decision made in a widget.
///
/// ── THE ONE RULE THIS FILE EXISTS TO KEEP ────────────────────────────────────────────────
///
/// A MEAL NOBODY WROTE IS SAID AS "NOT PLANNED YET", AND A DAY NOBODY WROTE IS SAID IN ONE
/// SENTENCE. There is no row in `menus` for a meal that has never been planned, and there is no
/// row at all for a day the kitchen has not got to. Neither is an error, and neither is an
/// empty plate: a PG that has not filled in Sunday is a PG that has not filled in Sunday. What
/// this must never do is draw four blank lines under Sunday, because a resident reading that
/// would take it to mean there is no food on Sunday — a claim the database never made, about
/// the one subject on this screen that people plan their evening around.
///
/// So an unwritten day gets a sentence rather than four empty rows, and an unwritten meal
/// inside a written day gets the muted "Not planned yet" — the difference between "nobody has
/// filled this in" and "there is nothing to eat" is the whole of what these two widgets are
/// careful about.

/// One meal on one day: the meal's name, then what is being served under it.
///
/// STACKED, NOT A LABEL-AND-VALUE ROW. `items` is one free-text column that a manager types
/// into — "Idli, sambar, coconut chutney" is a short one — so the food gets the full width of
/// the card. A two-column row would have put a 12dp caps label beside it, and at the 1.6x text
/// Android hands out on a 320dp phone the label alone eats a third of the line.
class MealLine extends StatelessWidget {
  const MealLine({super.key, required this.meal, required this.items});

  final Meal meal;

  /// What is being served, or NULL — which means both "there is no row" and "the row is
  /// blank". Both are the same fact to a resident: nobody has written this meal.
  final String? items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final planned = items != null;

    return Semantics(
      // One utterance per meal. Without this a screen reader reads the caps label as an
      // initialism and then the dishes as a separate node, which is two swipes for one line.
      label: planned
          ? '${meal.label}: ${items!}'
          : '${meal.label}: not planned yet',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The accent on a planned meal is the manager's own screen's (its meal cards head
          // every written meal in the gold), so the two roles are looking at one object. An
          // unplanned meal takes the muted ink in both places.
          CapsLabel(
            meal.label,
            tone: planned ? t.colorScheme.primary : NivoraColors.textMuted,
          ),
          const SizedBox(height: Space.xxs),
          planned
              // Selectable, so a resident can copy a dish they cannot spell into a search.
              ? SelectionArea(child: Text(items!, style: t.textTheme.bodyMedium))
              : Text(
                  'Not planned yet',
                  style: t.textTheme.bodyMedium?.copyWith(color: context.tones.muted),
                ),
        ],
      ),
    );
  }
}

/// One day of the week, with its four meals — or with the sentence that says nobody has written
/// it.
///
/// [today] draws the leading accent rail and the pill. The design gives that rail to the row
/// that matters most on a screen, and on a week of identical cards the only thing that
/// distinguishes one is which one is now.
class DayMenuCard extends StatelessWidget {
  const DayMenuCard({
    super.key,
    required this.day,
    required this.week,
    this.isToday = false,
  });

  final MenuDay day;
  final WeeklyMenu week;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final planned = week.plannedOn(day);

    return OutlineCard(
      accent: isToday ? t.colorScheme.primary : null,
      // The rail eats into the leading edge, so a today card insets past it rather than
      // starting under it. Same arithmetic as NoticeTile.
      padding: isToday
          ? const EdgeInsets.fromLTRB(Space.md + Space.xs, Space.md, Space.md, Space.md)
          : const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A Wrap, not a Row: "Wednesday" and the pill both grow with the text scale, and two
          // of them competing for one line is the layout that breaks at 1.6x on a 320dp phone.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(day.label, style: t.textTheme.titleMedium),
              if (isToday)
                StatusPill(
                  label: 'Today',
                  tone: t.colorScheme.primary,
                  icon: Icons.today_rounded,
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (planned == 0)
            // THE WHOLE POINT OF THIS FILE. One sentence, not four empty rows.
            Text(
              'No menu set for ${day.label} yet.',
              style: t.textTheme.bodyMedium?.copyWith(color: context.tones.muted),
            )
          else
            for (final meal in Meal.values) ...[
              MealLine(meal: meal, items: week.itemsFor(day, meal)),
              if (meal != Meal.values.last) const SizedBox(height: Space.sm),
            ],
        ],
      ),
    );
  }
}

/// The week in the order a resident thinks about it: today, then the days still ahead, then
/// the ones already eaten.
///
/// The table is keyed on a WEEKDAY, not a date (there is no date column in public.menus and
/// there is exactly one Monday row, forever), so this rotates the enum rather than counting
/// days forward from a calendar — and the cards are labelled "Monday", never "8 Sep", because
/// attaching this week's dates to rows that do not belong to a week would be inventing a fact.
List<MenuDay> weekFrom(MenuDay today) {
  final start = MenuDay.values.indexOf(today);
  return [
    for (var i = 0; i < MenuDay.values.length; i++)
      MenuDay.values[(start + i) % MenuDay.values.length],
  ];
}
