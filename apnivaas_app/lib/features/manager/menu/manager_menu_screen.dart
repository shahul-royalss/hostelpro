library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../data/providers.dart';
import '../../../shared/clay/clay.dart';
import '../../common/refresh.dart';
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
///
/// ══ WHAT A MEAL PLANNER USUALLY HAS THAT public.menus CANNOT STORE ═══════════════════════
///
/// The table is a WEEK-OF-WEEKDAYS, not a week of dates. That single difference rules out
/// five things a planner screen would normally draw, and every one of them would have to be
/// fabricated to draw:
///
///  1. **A date range and arrows to the next week.** `menus` is keyed on `day_of_week`, an
///     enum of mon..sun. There is no date column, so there is no such thing as last week's menu
///     or next week's — Monday has exactly one row, forever, and paging the week would page over
///     the same twenty-eight rows. The day strip therefore names the weekday and not a date.
///  2. **A serving time beside each meal.** There is no service-time column anywhere in
///     db/schema.sql. The meal name is the whole of what the row knows.
///  3. **Dish chips with ×, and "Add item".** `items` is ONE `text` column, `not null default
///     ''`. A chip editor would have to serialise its chips into that string, and the web app —
///     which reads the same rows for residents — would then show a line of delimiters. The sheet
///     writes the column the database actually has.
///  4. **A "Draft" label.** There is no draft column and no publish step: the upsert IS the
///     publication, and every resident of the hostel can read the row the moment it lands
///     (menus_select is `can_read_hostel`). A "Draft" label over a row that is already live is
///     the most dangerous kind of wrong.
///  5. **"Save & broadcast".** Nothing broadcasts. The write is an upsert on one meal; there is
///     no notification trigger on public.menus in schema.sql, so a button promising a broadcast
///     would promise something that does not happen. Saving is per meal, in the sheet, and the
///     sheet says who can read it.
class ManagerMenuScreen extends ConsumerWidget {
  const ManagerMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    final day = ref.watch(menuDayProvider);

    if (hostelId == null) {
      return const ManagerScreen(
        title: 'Menu',
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.md),
          child: EmptyState(
            icon: ClayIcons.navProperty,
            title: 'No hostel on this account',
            body: 'A manager runs exactly one hostel. Ask the owner to check the assignment.',
          ),
        ),
      );
    }

    final menu = ref.watch(weeklyMenuProvider(hostelId));
    final today = MenuDay.of(DateTime.now());

    return ManagerScreen(
      title: 'Meal menu',
      subtitle: day == today ? 'Today · ${day.label}' : day.label,
      child: RefreshIndicator(
        // See features/common/refresh.dart. The week stays on screen through a failed
        // reload, so a pull that did not land has to say so itself.
        onRefresh: () {
          ref.invalidate(weeklyMenuProvider(hostelId));
          return settleRefresh(context, () => ref.read(weeklyMenuProvider(hostelId).future));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            AsyncSection(
              value: menu,
              // The week IS this page, so a failure stands on the ground at full size.
              carded: false,
              loading: const _MenuSkeleton(),
              onRetry: () => ref.invalidate(weeklyMenuProvider(hostelId)),
              builder: (week) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DayStrip(week: week, selected: day, today: today),
                  const SizedBox(height: Space.md),
                  _DayMenu(hostelId: hostelId, day: day, week: week),
                  if (week.lastUpdated != null) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      'Menu last changed ${shortDate(week.lastUpdated!)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

/// The day strip, carrying the one fact this table has instead of a date.
///
/// Each day is a small calendar tile: the weekday over how much of it is written — `2/4` — in
/// the date-numeral type. That second line is what turns the strip from navigation into
/// information: a manager can see that Saturday has nothing on it without opening Saturday.
///
/// A SingleChildScrollView, not a ListView: the page's own ListView is the one pull-to-refresh
/// is found on, and a second, sideways one nested inside it would be the last ListView in the
/// tree.
class _DayStrip extends ConsumerWidget {
  const _DayStrip({required this.week, required this.selected, required this.today});

  final WeeklyMenu week;
  final MenuDay selected;
  final MenuDay today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final day in MenuDay.values) ...[
            if (day != MenuDay.values.first) const SizedBox(width: Space.tight),
            _DayChip(
              day: day,
              planned: week.plannedOn(day),
              isSelected: day == selected,
              isToday: day == today,
              onTap: () => ref.read(menuDayProvider.notifier).set(day),
            ),
          ],
        ],
      ),
    );
  }
}

/// One day of the strip. Selected is forest with white on it — the one way this design says
/// "this is the one you are looking at". Unselected is the card on a hairline; TODAY, when it
/// is not the selected day, keeps a forest edge, so the strip still says where "now" is after
/// the manager has looked at Thursday.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.planned,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final MenuDay day;
  final int planned;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: Radii.rControl,
      side: isSelected
          ? BorderSide.none
          : BorderSide(
              color: isToday ? scheme.primary : scheme.outlineVariant,
              width: isToday ? Strokes.control : Strokes.hairline,
            ),
    );
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${day.label}, $planned of ${Meal.values.length} meals planned'
          '${isToday ? ', today' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: isSelected ? scheme.primary : scheme.surface,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            // 52 x 56: past the 48dp tap floor both ways, with room for the numeral.
            constraints: const BoxConstraints(
              minWidth: Space.huge + Space.xxs,
              minHeight: Space.huge + Space.xs,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.tight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day.short,
                    style: t.textTheme.labelMedium?.copyWith(
                      color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Space.hair),
                  Text(
                    '$planned/${Meal.values.length}',
                    style: context.textRoles.dateNumeral.copyWith(
                      color: isSelected ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The day being planned: the thali, the day's name and how much of it is written, then the
/// four meals in one card.
///
/// One card, divided, rather than four: the meals are one day's food and read as one list, and
/// the divider between them is the only structure four rows need.
class _DayMenu extends StatelessWidget {
  const _DayMenu({required this.hostelId, required this.day, required this.week});

  final String hostelId;
  final MenuDay day;
  final WeeklyMenu week;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final planned = week.plannedOn(day);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ClayIcon(ClayIcons.food, size: ClaySize.list),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(day.label, style: context.textRoles.tileTitle.copyWith(
                        color: t.colorScheme.onSurface,
                      )),
                    ),
                    Text(
                      planned == Meal.values.length
                          ? 'Every meal is planned'
                          : '$planned of ${Meal.values.length} meals planned',
                      style: t.textTheme.bodySmall
                          ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          for (final meal in Meal.values) ...[
            Divider(height: Strokes.hairline, color: t.dividerTheme.color),
            _MealRow(
              hostelId: hostelId,
              day: day,
              meal: meal,
              items: week.itemsFor(day, meal),
            ),
          ],
        ],
      ),
    );
  }
}

/// One meal: its glyph, its name, and what is being served — or that nothing is written yet.
///
/// A PLANNED MEAL'S NAME IS FOREST and its glyph sits on a Mist disc; an unplanned one is in the
/// secondary ink on an empty ring, with a + where the pencil would be. So the four rows say at a
/// glance how much of the day is written, which is the question a manager standing in the
/// kitchen is actually asking.
class _MealRow extends StatelessWidget {
  const _MealRow({
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

  static IconData _glyphFor(Meal meal) => switch (meal) {
        Meal.breakfast => Icons.free_breakfast_rounded,
        Meal.lunch => Icons.lunch_dining_rounded,
        Meal.snacks => Icons.cookie_rounded,
        Meal.dinner => Icons.dinner_dining_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    final planned = items != null;

    void edit() => showEditMealSheet(
          context,
          hostelId: hostelId,
          day: day,
          meal: meal,
          current: items,
        );

    return Semantics(
      container: true,
      button: true,
      label: '${meal.label}: ${items ?? 'not planned yet'}. Tap to change.',
      excludeSemantics: true,
      onTap: edit,
      child: InkWell(
        onTap: edit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ListRow.minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: Space.xxxl,
                  height: Space.xxxl,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: planned
                        ? (dark ? ApnivaasColors.darkMist : ApnivaasColors.mist)
                        : Colors.transparent,
                    border: planned
                        ? null
                        : Border.all(color: scheme.outlineVariant, width: Strokes.control),
                  ),
                  child: Icon(
                    _glyphFor(meal),
                    size: IconSize.lg,
                    color: planned ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal.label,
                        style: t.textTheme.titleMedium?.copyWith(
                          color: planned ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Space.hair),
                      Text(
                        items ?? 'Not planned yet',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: planned ? scheme.onSurface : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.xs),
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Icon(
                    planned ? Icons.edit_outlined : Icons.add_rounded,
                    size: IconSize.lg,
                    color: scheme.primary,
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

/// The week's outline while it loads: the strip's seven tiles, then the day card.
class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final card = BoxDecoration(
      color: t.colorScheme.surface,
      borderRadius: Radii.rSurface,
      border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
    );
    return SkeletonPulse(
      semanticLabel: 'Loading the menu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: Space.tight),
                const Skeleton(
                  width: Space.huge + Space.xxs,
                  height: Space.huge + Space.xs,
                  radius: Radii.rControl,
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.md),
          DecoratedBox(
            decoration: card,
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Skeleton(widthFactor: 0.4, height: Space.md),
                  for (var i = 0; i < 4; i++) ...[
                    const SizedBox(height: Space.lg),
                    const Row(
                      children: [
                        Skeleton(width: Space.xxxl, height: Space.xxxl, circle: true),
                        SizedBox(width: Space.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Skeleton(widthFactor: 0.35),
                              SizedBox(height: Space.xs),
                              Skeleton(widthFactor: 0.7),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
