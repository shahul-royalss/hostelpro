library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/providers.dart';
import '../data/manager_models.dart';
import '../data/manager_providers.dart';
import '../widgets/manager_ui.dart';
import 'edit_meal_sheet.dart';

/// The week's food.
///
/// TABLE: public.menus. Seven days times four meals, unique on (hostel_id, day_of_week, meal),
/// so the whole week is at most 28 rows and is fetched in one request — see
/// ManagerRepository.weeklyMenu for why this is the one list in the app that is not paginated.
///
/// A DAY AT A TIME, NOT A 7x4 GRID. A grid of twenty-eight cells on a phone gives each meal
/// about forty points of width, which fits neither a dish list nor a thumb. The day strip
/// keeps every day one tap away and gives the four meals the full width of the screen — and it
/// opens on TODAY, because the question a manager has in the kitchen is what is being served
/// now, not what happens on Thursday.
///
/// AN ABSENT ROW IS SAID AS "NOT PLANNED YET", NEVER AS AN EMPTY MEAL. There is no row for a
/// meal nobody has written, and inventing a blank one would let this screen tell a hostel there
/// is no dinner on Sunday — a claim the database never made. See WeeklyMenu.
class ManagerMenuScreen extends ConsumerWidget {
  const ManagerMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    final day = ref.watch(menuDayProvider);

    if (hostelId == null) {
      return const ManagerScreen(
        title: 'Menu',
        child: EmptyNote(
          icon: Icons.restaurant_rounded,
          title: 'No hostel on this account',
          detail: 'A manager runs exactly one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final menu = ref.watch(weeklyMenuProvider(hostelId));
    final today = MenuDay.of(DateTime.now());

    return ManagerScreen(
      title: 'Menu',
      subtitle: day == today ? 'Today · ${day.label}' : day.label,
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(weeklyMenuProvider(hostelId)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            AsyncSection(
              value: menu,
              onRetry: () => ref.invalidate(weeklyMenuProvider(hostelId)),
              builder: (week) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DayStrip(week: week, selected: day, today: today),
                  const SizedBox(height: Space.md),
                  for (final meal in Meal.values) ...[
                    _MealCard(
                      hostelId: hostelId,
                      day: day,
                      meal: meal,
                      items: week.itemsFor(day, meal),
                    ),
                    const SizedBox(height: Space.xs),
                  ],
                  if (week.lastUpdated != null) ...[
                    const SizedBox(height: Space.sm),
                    Text(
                      'Menu last changed ${shortDate(week.lastUpdated!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seven days across the top, each showing how much of that day is planned.
///
/// The count under each letter is what turns this from navigation into information: a manager
/// can see at a glance that Saturday has nothing on it without opening Saturday.
class _DayStrip extends ConsumerWidget {
  const _DayStrip({required this.week, required this.selected, required this.today});

  final WeeklyMenu week;
  final MenuDay selected;
  final MenuDay today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final day in MenuDay.values) ...[
            if (day != MenuDay.values.first) const SizedBox(width: Space.xs),
            _DayChip(
              day: day,
              planned: week.plannedOn(day),
              isSelected: day == selected,
              isToday: day == today,
              onTap: () => ref.read(menuDayProvider.notifier).set(day),
              textTheme: t,
            ),
          ],
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.planned,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
    required this.textTheme,
  });

  final MenuDay day;
  final int planned;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;
  final ThemeData textTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = textTheme.colorScheme;
    final onChip = isSelected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${day.label}, $planned of ${Meal.values.length} meals planned'
          '${isToday ? ', today' : ''}',
      child: Material(
        color: isSelected ? scheme.primary : scheme.surface,
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: onTap,
          child: Container(
            width: 52,
            // 64dp keeps the target past the 48dp minimum with the count underneath.
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            decoration: BoxDecoration(
              borderRadius: Radii.rControl,
              border: Border.all(
                color: isToday && !isSelected ? scheme.primary : scheme.outlineVariant,
                width: Strokes.hairline,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day.short,
                  style: textTheme.textTheme.titleSmall?.copyWith(color: onChip),
                ),
                const SizedBox(height: 2),
                Text(
                  '$planned/${Meal.values.length}',
                  style: textTheme.textTheme.labelSmall?.copyWith(
                    color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.hostelId,
    required this.day,
    required this.meal,
    required this.items,
  });

  final String hostelId;
  final MenuDay day;
  final Meal meal;

  /// Null when there is no row, and null when the row is blank. Both mean "not planned".
  final String? items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final planned = items != null;

    return TapRow(
      onTap: () => showEditMealSheet(
        context,
        hostelId: hostelId,
        day: day,
        meal: meal,
        current: items,
      ),
      semanticLabel: '${meal.label}: ${items ?? 'not planned yet'}. Tap to change.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.label.toUpperCase(), style: t.textTheme.labelSmall),
                const SizedBox(height: Space.xxs),
                planned
                    ? Text(items!, style: t.textTheme.bodyMedium)
                    : Text(
                        'Not planned yet',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: t.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Icon(
            planned ? Icons.edit_outlined : Icons.add_rounded,
            size: IconSize.md,
            color: t.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
