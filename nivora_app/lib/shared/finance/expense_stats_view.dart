library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../glass/glass.dart';

/// EXPENSES, MONTH AGAINST MONTH.
///
/// The product owner: "introduce graphs, stats dashboard that owner and manager can view
/// expenses in that model it compares other months (statistics)."
///
/// ── ONE WIDGET, TWO ROLES ────────────────────────────────────────────────────────────────
///
/// The owner and the manager see the SAME figures for the same PG — `expenses_select` admits
/// both and nobody else — so they get the same widget rather than two that drift.
///
/// THAT IS WHY IT USES NONE OF THE ROLE UI KITS. `AsyncSection`, `EmptyState`, `StatusChip` and
/// `SectionLabel` each exist FOUR TIMES in this app, once per role, tuned to that role's
/// surfaces. A shared widget reaching into one of them would drag a feature folder into
/// lib/shared and make this screen look like the warden's inside the owner's app. Everything
/// below is built from lib/shared/glass — StateCard, StateBadge, FlatSurface — or from Material.
///
/// ── EVERY NUMBER IS SUMMED BY POSTGRES ───────────────────────────────────────────────────
///
/// public.rpc_expense_months groups by month, kind and category; nothing here re-adds rows that
/// arrived pre-added, and nothing is estimated from a loaded page. That matters because the
/// manager's expense LIST is paginated at twenty: a category share computed from twenty rows of
/// a hostel with four hundred looks like a measurement and is not one.
///
/// ── THE BARS ARE DRAWN BY HAND ───────────────────────────────────────────────────────────
///
/// Containers, not a charting library — the same choice InOutBars made, for the same reason: a
/// stacked bar of two known quantities is a Column with two boxes in it, and a library would
/// bring its own type scale, its own tooltips and its own idea of a colour.
class ExpenseStatsView extends ConsumerStatefulWidget {
  const ExpenseStatsView({super.key, required this.hostelId, this.months = 6});

  final String hostelId;

  /// How many months to chart, including this one. The RPC clamps to 1..24.
  final int months;

  @override
  ConsumerState<ExpenseStatsView> createState() => _ExpenseStatsViewState();
}

class _ExpenseStatsViewState extends ConsumerState<ExpenseStatsView> {
  /// Which month the breakdown below the chart is about. Null means "the latest one", resolved
  /// per build rather than stored, so the panel follows the chart across a month boundary
  /// instead of pinning itself to a month that has scrolled off the axis.
  String? _selected;

  /// `YYYY-MM` for today.
  ///
  /// The DEVICE clock, where the RPC uses app.today() (Asia/Kolkata). They agree on any phone
  /// set to Indian time, which is every phone this ships to; a device deliberately set to
  /// Honolulu would draw one extra empty month at the right-hand end and nothing worse — the
  /// figures themselves are the server's either way.
  static String _thisMonth() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  static final NumberFormat _rupees =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  /// "Sep", or "Sep 25" when the year is not this one.
  static String _shortMonth(String key) {
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(5, 7));
    final label = DateFormat('MMM').format(DateTime(year, month));
    return year == DateTime.now().year ? label : '$label ${key.substring(2, 4)}';
  }

  static String _longMonth(String key) => DateFormat('MMMM yyyy')
      .format(DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(5, 7))));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final query = (hostelId: widget.hostelId, months: widget.months);
    final slices = ref.watch(expenseMonthsProvider(query));

    return slices.when(
      // A refresh keeps the previous chart on screen — `.when` skips the loading state for one
      // by default — so this is only ever the genuinely cold first paint.
      loading: () => const StateCard(
        badge: 'ADDING UP',
        child: Text('Reading the last months of the expense book.'),
      ),
      error: (error, _) => StateCard(
        badge: 'COULD NOT LOAD',
        tone: NivoraColors.error,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppFailure.from(error).message, style: t.textTheme.bodyMedium),
            const SizedBox(height: Space.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => ref.invalidate(expenseMonthsProvider(query)),
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
      data: (rows) {
        final stats = ExpenseStats.from(
          rows,
          latest: _thisMonth(),
          monthsWanted: widget.months,
        );
        if (stats.peak <= 0) {
          return const StateCard(
            badge: 'NOTHING YET',
            child: Text(
              'The chart fills in as expenses are recorded. Monthly bills and day-to-day '
              'spending are drawn separately.',
            ),
          );
        }

        final selected = stats.months.contains(_selected) ? _selected! : stats.months.last;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Legend(),
            const SizedBox(height: Space.sm),
            _MonthBars(
              stats: stats,
              selected: selected,
              onSelect: (month) => setState(() => _selected = month),
              label: _shortMonth,
              money: _rupees.format,
            ),
            const SizedBox(height: Space.md),
            _MonthPanel(
              stats: stats,
              month: selected,
              title: _longMonth(selected),
              previousTitle: stats.previousOf(selected) == null
                  ? null
                  : _longMonth(stats.previousOf(selected)!),
              money: _rupees.format,
            ),
          ],
        );
      },
    );
  }
}

/// Which colour means which kind — the design's dot-and-word legend (4:1221).
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    return Row(
      children: [
        _Dot(color: tones.resolve(NivoraDomain.rooms.tone)),
        const SizedBox(width: Space.xxs),
        Text('Monthly', style: t.textTheme.labelSmall),
        const SizedBox(width: Space.sm),
        _Dot(color: tones.resolve(NivoraDomain.money.tone)),
        const SizedBox(width: Space.xxs),
        Text('Day-to-day', style: t.textTheme.labelSmall),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: Space.xs,
        height: Space.xs,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// One stacked bar per month, tappable.
///
/// SCALED TO THE TALLEST MONTH IN THE WINDOW, not to a round number above it: the question this
/// chart answers is "which months were heavy", which is a comparison between bars rather than a
/// reading off an axis. There is deliberately no y-axis — the figures are printed in full under
/// the chart for whichever month is selected.
class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.stats,
    required this.selected,
    required this.onSelect,
    required this.label,
    required this.money,
  });

  final ExpenseStats stats;
  final String selected;
  final ValueChanged<String> onSelect;
  final String Function(String) label;
  final String Function(num) money;

  /// Tall enough to tell a heavy month from a light one, short enough that the chart and the
  /// breakdown under it are both on screen on a five-inch phone.
  static const double _height = 96;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final peak = stats.peak;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final month in stats.months)
          Expanded(
            child: Semantics(
              button: true,
              selected: month == selected,
              label: '${label(month)}, ${money(stats.totalIn(month))}',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: Radii.rControl,
                onTap: () => onSelect(month),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xxs / 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: _height,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // A month with nothing in it is a bar of zero height, which is a
                            // real answer. ExpenseStats.from fills the gaps precisely so an
                            // empty month keeps its place on the axis, instead of letting March
                            // sit next to June and read as consecutive.
                            _Segment(
                              height: _height *
                                  (stats.totalOfKind(month, ExpenseKind.monthly) / peak),
                              color: tones.resolve(NivoraDomain.rooms.tone),
                              top: true,
                            ),
                            _Segment(
                              height: _height *
                                  (stats.totalOfKind(month, ExpenseKind.daily) / peak),
                              color: tones.resolve(NivoraDomain.money.tone),
                              top: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.xxs),
                      Text(
                        label(month),
                        style: t.textTheme.labelSmall?.copyWith(
                          color: month == selected ? t.colorScheme.primary : tones.muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.height, required this.color, required this.top});

  final double height;
  final Color color;

  /// Only the top of the whole bar is rounded, so the two kinds read as one column rather than
  /// as two bricks with a seam between them.
  final bool top;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();
    return Container(
      // A month with a tiny amount in it must still be visible; 2dp is the thinnest line that
      // is not mistaken for the axis.
      height: height < 2 ? 2 : height,
      decoration: BoxDecoration(
        color: color,
        borderRadius:
            top ? const BorderRadius.vertical(top: Radius.circular(3)) : BorderRadius.zero,
      ),
    );
  }
}

/// One month in figures: the total, how it compares with the month before, and where it went.
class _MonthPanel extends StatelessWidget {
  const _MonthPanel({
    required this.stats,
    required this.month,
    required this.title,
    required this.previousTitle,
    required this.money,
  });

  final ExpenseStats stats;
  final String month;
  final String title;
  final String? previousTitle;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final total = stats.totalIn(month);
    final change = stats.changeVsPrevious(month);
    final categories = stats.byCategory(month);
    final entries = stats.entriesIn(month);

    return FlatSurface(
      weight: GlassWeight.regular,
      borderRadius: Radii.rCard,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: t.textTheme.labelSmall),
                    Text(money(total), style: t.textTheme.headlineSmall),
                  ],
                ),
              ),
              // MORE SPENT IS NOT AUTOMATICALLY BAD, so this is not painted as an alarm: a PG
              // that filled up spends more on food. Red for up and green for down would be a
              // verdict the data cannot support. The arrow states the direction; the colour
              // stays the quiet grey.
              if (change != null)
                StateBadge(
                  label: '${change >= 0 ? '▲' : '▼'} '
                      '${(change.abs() * 100).toStringAsFixed(0)}%',
                ),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            change == null
                ? previousTitle == null
                    // The oldest month on the axis has nothing before it IN THIS WINDOW. Saying
                    // "no change" would be a claim about a month that was never fetched.
                    ? 'No earlier month in this range to compare with.'
                    : 'Nothing was booked in $previousTitle, so there is no percentage to show.'
                : '${change >= 0 ? 'More' : 'Less'} than $previousTitle '
                    '(${money(stats.totalIn(stats.previousOf(month)!))}).',
            style: t.textTheme.bodySmall,
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text('WHERE IT WENT', style: t.textTheme.labelSmall),
            for (final row in categories) ...[
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      row.category.label,
                      style: t.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: Radii.rTiny,
                      child: Container(
                        height: Space.xs,
                        color: tones.chipFill(NivoraColors.textMuted),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          // Against the MONTH'S own total, so a bar reads as a share of this
                          // month rather than against the tallest month on the chart above.
                          widthFactor: total <= 0 ? 0 : (row.total / total).clamp(0, 1),
                          child: ColoredBox(color: tones.resolve(NivoraDomain.money.tone)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(money(row.total), style: t.textTheme.labelSmall),
                ],
              ),
            ],
          ],
          const SizedBox(height: Space.sm),
          Text(
            '$entries ${entries == 1 ? 'entry' : 'entries'} · '
            'monthly ${money(stats.totalOfKind(month, ExpenseKind.monthly))} · '
            'day-to-day ${money(stats.totalOfKind(month, ExpenseKind.daily))}',
            style: t.textTheme.labelSmall?.copyWith(color: tones.muted),
          ),
        ],
      ),
    );
  }
}
