library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/glass/glass.dart';
import '../data/manager_models.dart';
import '../data/manager_providers.dart';
import '../widgets/manager_ui.dart';
import 'edit_meal_sheet.dart';

/// The week's food. Figma `4:1236`, `screen-meal-editor`.
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
/// ══ WHAT 4:1236 ASKS FOR THAT public.menus CANNOT STORE ═══════════════════════════════════
///
/// The frame is a WEEK-OF-DATES editor. This table is a WEEK-OF-WEEKDAYS. That single
/// difference makes five of its elements unbuildable, and every one of them would have to be
/// fabricated to draw:
///
///  1. **`01 Sep - 07 Sep 2026` and the two week arrows (4:1254–4:1259).** `menus` is keyed on
///     `day_of_week`, an enum of mon..sun. There is no date column, so there is no such thing
///     as last week's menu or next week's — Monday has exactly one row, forever, and paging
///     the week would page over the same twenty-eight rows. The day strip therefore names the
///     weekday and not a date; drawing `31 / 01 / 02` under it would attach this week's
///     calendar to rows that do not belong to a week.
///  2. **`BREAKFAST • 08:00 AM` (4:1283).** There is no service-time column anywhere in
///     db/schema.sql. The meal name is the whole of what the row knows.
///  3. **The dish chips with `×`, and `+ Add Item` (4:1291–4:1306).** `items` is ONE `text`
///     column, `not null default ''`. A chip editor would have to serialise its chips into
///     that string, and the web app — which reads the same rows for residents — would then
///     show a line of delimiters. The sheet writes the column the database actually has.
///  4. **`Draft` and the gold "currently editing" card (4:1286–4:1289).** There is no draft
///     column and no publish step: the upsert IS the publication, and every resident of the
///     hostel can read the row the moment it lands (menus_select is `can_read_hostel`). A
///     "Draft" label over a row that is already live is the most dangerous kind of wrong.
///  5. **`Save & Broadcast Menu` (4:1313).** Nothing broadcasts. The write is an upsert on one
///     meal; there is no notification trigger on public.menus in schema.sql, so a button
///     promising a broadcast would promise something that does not happen. Saving is per-meal,
///     in the sheet, and the sheet says who can read it.
///
/// WHAT IS TAKEN: the day strip's chip (4:1262 unselected, 4:1265 gold-selected), the meal card
/// (4:1281 — raised fill, hairline, a gold caps meal name with the edit glyph opposite, the
/// dishes under it in body semibold), and the frame's 16dp body rhythm.
/// The frame's 6dp gap between day tabs (4:1261). See the note beside manager_ui's own copy on
/// why six is written as half of [Space.sm] rather than added to the scale.
const double _gap6 = Space.sm / 2;

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
          child: EmptyNote(
            icon: Icons.restaurant_rounded,
            title: 'No hostel on this account',
            detail: 'A manager runs exactly one hostel. Ask the owner to check the assignment.',
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

/// The frame's day tabs (4:1261), carrying the one fact this table has instead of a date.
///
/// The chip's anatomy is the design's: `rounded-[8px] px-[10px] py-[8px] gap-[4px]`, a 10px
/// caps line over a 12/700 one, unselected on the raised fill under a hairline and SELECTED IN
/// THE GOLD with near-black on it.
///
/// The design puts the day of the MONTH on the second line — `MON / 31`. This table has no
/// dates (see the class note on [ManagerMenuScreen]), so that line carries how much of the day
/// is written instead: `2/4`. It is the better number anyway. It is what turns the strip from
/// navigation into information — a manager can see that Saturday has nothing on it without
/// opening Saturday.
class _DayStrip extends ConsumerWidget {
  const _DayStrip({required this.week, required this.selected, required this.today});

  final WeeklyMenu week;
  final MenuDay selected;
  final MenuDay today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final day in MenuDay.values) ...[
            if (day != MenuDay.values.first) const SizedBox(width: _gap6),
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
    final onChip = isSelected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${day.label}, $planned of ${Meal.values.length} meals planned'
          '${isToday ? ', today' : ''}',
      child: Material(
        // The gold fill is the design's own selected tab. Unselected is the raised surface,
        // which is what every other chip and icon button in the file sits on.
        color: isSelected ? scheme.primary : scheme.surfaceContainer,
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: onTap,
          child: Container(
            // 48dp square keeps the target on Material's tap floor; the design's own chip is
            // shorter, and a day nobody can hit is a day nobody plans.
            constraints: const BoxConstraints(minWidth: Space.huge, minHeight: Space.huge),
            padding:
                const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
            decoration: BoxDecoration(
              borderRadius: Radii.rControl,
              border: Border.all(
                // Today is marked with the gold edge when it is not the selected day, so the
                // strip still says where "now" is after the manager has looked at Thursday.
                color: isSelected
                    ? scheme.primary
                    : isToday
                        ? scheme.primary
                        : scheme.outlineVariant,
                width: Strokes.hairline,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  day.short.toUpperCase(),
                  // chip 10/600 — the design's `text-[10px]` day label.
                  style: t.textTheme.labelSmall?.copyWith(
                    color: isSelected ? scheme.onPrimary : context.tones.muted,
                  ),
                ),
                const SizedBox(height: Space.xxs),
                Text(
                  '$planned/${Meal.values.length}',
                  // 12/600 caps is the closest step to the design's 12/700 date line.
                  style: t.textTheme.labelMedium?.copyWith(color: onChip, letterSpacing: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The day being edited — the ONE domain-tinted surface this screen gets.
///
/// A saffron [DomainCard] around the four meals, opened by the food glyph: the manager's side
/// of the resident's "Today's food" card, so the menu is recognisably the menu on both ends of
/// the app. It is the card that IS the screen's subject and it carries no status — an unplanned
/// meal is said in muted ink inside it, never as a tint of the whole — which is exactly the
/// case [NivoraDomain] allows a domain onto a surface. Nothing else here is tinted: the day
/// strip keeps the design's gold-selected chip, because that is selection, not identity.
///
/// The meal blocks inside drop their hairline. The design's own inner blocks (4:1603, 4:1606)
/// are bare fills — a hairline inside a hairlined card reads as a table — and the card's
/// tone-coloured edge is the only outline this group needs.
class _DayMenu extends StatelessWidget {
  const _DayMenu({required this.hostelId, required this.day, required this.week});

  final String hostelId;
  final MenuDay day;
  final WeeklyMenu week;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return DomainCard(
      domain: NivoraDomain.food,
      padding: const EdgeInsets.all(Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // A BARE GLYPH, NOT A PLATE. This card is a DomainCard(food), so its ground is
              // already a 10% saffron tint — and a DomainIcon's fill is a 10% tint of the same
              // tone, which lands twice as far toward its own glyph and all but disappears. It
              // is the tint-on-tint stack NivoraSemantics.surfaceTintAlpha describes for chips,
              // one layer up. One domain object per card: the ground says food, so the mark in
              // the corner only has to be legible, and the ink at full strength is.
              Icon(
                Icons.restaurant_rounded,
                size: IconSize.md,
                color: context.tones.resolve(NivoraDomain.food.tone),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  day.label,
                  style: t.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final meal in Meal.values) ...[
            if (meal != Meal.values.first) const SizedBox(height: Space.xs),
            _MealCard(
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

/// One meal, in the frame's meal-card anatomy (4:1281).
///
/// `bg-[#171a1e] border border-[#292e33] rounded-[10px] p-[12px] gap-[8px]`: the meal's name
/// along the top in GOLD CAPS with the edit glyph opposite it, and the dishes underneath in
/// body semibold cream. The border is the one part not drawn any more — see [_DayMenu] for
/// why an inner block of a tinted card goes edgeless.
///
/// THE GOLD IS THE DESIGN'S, AND IT STILL MEANS SOMETHING HERE. 4:1283 and 4:1310 set every
/// meal heading in `#c9a96e` regardless of state, because every meal on that frame is planned.
/// An unplanned meal is the case the frame does not draw, and it takes the muted ink and a `+`
/// instead of a pencil — so the four rows still say at a glance how much of the day is
/// written, which is the question a manager standing in the kitchen is actually asking.
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
    final accent = planned ? t.colorScheme.primary : context.tones.muted;

    // The raised fill at a card's radius — the frame's meal block, not a list row on the
    // ground. FlatSurface rather than GlassSurface: nothing here is elevated above the page,
    // and GlassSurface asserts the moment two panes stack. No hairline: this block sits inside
    // the day's tinted card, whose own edge already outlines the group.
    return FlatSurface(
      weight: GlassWeight.regular,
      borderRadius: Radii.rCard,
      border: false,
      padding: const EdgeInsets.all(Space.sm),
      semanticLabel: '${meal.label}: ${items ?? 'not planned yet'}. Tap to change.',
      onTap: () => showEditMealSheet(
        context,
        hostelId: hostelId,
        day: day,
        meal: meal,
        current: items,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal.label.toUpperCase(),
                  // label-caps 12/600 — the design's own `text-[12px] Bold uppercase`.
                  style: t.textTheme.labelMedium?.copyWith(color: accent),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.xs),
              Icon(
                planned ? Icons.edit_outlined : Icons.add_rounded,
                // The frame's edit glyph is 14 (4:1358).
                size: IconSize.sm,
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          planned
              ? Text(items!, style: t.textTheme.titleSmall)
              : Text(
                  'Not planned yet',
                  style: t.textTheme.titleSmall?.copyWith(color: context.tones.muted),
                ),
        ],
      ),
    );
  }
}
