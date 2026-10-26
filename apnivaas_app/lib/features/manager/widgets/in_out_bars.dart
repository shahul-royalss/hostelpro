library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/clay/clay.dart';
import '../data/manager_models.dart';
import 'manager_ui.dart';

/// Money in against money out, one pair of bars per day.
///
/// THE SERIES IS NOT INTERPOLATED AND NOTHING HERE INVENTS A POINT. public.rpc_daily_finance
/// emits a row for EVERY day in the range from generate_series, zero-filled — so a flat
/// stretch is a genuinely quiet week rather than a gap a charting library drew a line across.
/// That is the whole reason the RPC exists.
///
/// WHY BARS AND NOT A LINE. A line implies a continuous quantity moving between its points;
/// spending does not move between Tuesday and Wednesday, it happens on a day or it does not.
/// Fourteen discrete pairs also fit a phone without a horizontal scroll, and the two columns
/// for one day sit next to each other where they can be compared at a glance.
///
/// WHAT THIS IS NOT. These are public.revenues and public.expenses — the ledgers the manager
/// keeps by hand. Rent lives in public.fee_payments, which this role cannot read, and is not
/// in either bar. The "Recorded in" tile above it says so, so nobody reads a quiet month here as
/// a hostel that took no money.
///
/// THE TWO SERIES ARE THE OWNER'S CASH-FLOW COLOURS: money in in the brand's forest, money out
/// in the control border's warm grey. Not amber — an expense is not a warning, and spending the
/// warning colour on every day of the month would leave nothing to say with it elsewhere. The
/// two are a full step apart in lightness as well as hue, so they still separate in greyscale.
class InOutBars extends StatelessWidget {
  const InOutBars({super.key, required this.window});

  final FinanceWindow window;

  /// The plot's height, and the tallest a bar goes inside it — headroom for the rounded tops.
  static const _plot = Space.huge * 2;
  static const _tallest = Space.huge + Space.xl;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final days = window.trendDays;
    final peak = window.trendPeak;
    final quiet = t.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    if (days.isEmpty) {
      return const EmptyState(
        compact: true,
        icon: ClayIcons.analytics,
        title: 'No days to chart yet',
        body: 'The daily figures start the day this hostel books its first entry.',
      );
    }

    if (peak <= 0) {
      return EmptyState(
        compact: true,
        icon: ClayIcons.analytics,
        title: 'Nothing booked in ${plural(days.length, 'day', 'days')}',
        body: 'Expenses and money in that you record show up here the same day.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: scheme.primary, label: 'In'),
            const SizedBox(width: Space.sm),
            _LegendDot(color: scheme.outline, label: 'Out'),
            const SizedBox(width: Space.xs),
            // Expanded rather than a Spacer: at 1.6x text scale on a 320dp phone the two
            // legend dots and this sentence are wider than the row, and a Spacer has no give.
            Expanded(
              child: Text(
                'Busiest day ${moneyShort(peak)}',
                style: quiet,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: _plot,
          child: Semantics(
            label: 'Money in and out, one bar per day for the last ${days.length} days. '
                'The busiest single day is ${moneyShort(peak)}.',
            container: true,
            excludeSemantics: true,
            child: DecoratedBox(
              // The baseline the bars stand on, so a run of quiet days reads as zero rather
              // than as a chart that stopped drawing.
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant, width: Strokes.hairline),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.hair / 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _Bar(fraction: day.revenue / peak, colour: scheme.primary),
                            ),
                            const SizedBox(width: Space.hair / 2),
                            Expanded(
                              child: _Bar(fraction: day.expense / peak, colour: scheme.outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Text(shortDate(days.first.day), style: quiet),
            const Spacer(),
            Text(shortDate(days.last.day), style: quiet),
          ],
        ),
      ],
    );
  }
}

/// One bar. A day with nothing booked still gets a hairline stub, so the reader can see the day
/// exists and was zero — an absent bar reads as missing data.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.colour});

  final double fraction;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final height = fraction <= 0
        ? Space.hair
        : (fraction.clamp(0.0, 1.0) * InOutBars._tallest).clamp(Space.xxs, InOutBars._tallest);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: fraction <= 0 ? Theme.of(context).colorScheme.outlineVariant : colour,
        // The check radius — the smallest corner the kit draws — because a bar a few dp wide
        // with a card's corner would be a capsule rather than a bar.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.check)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Space.xs,
          height: Space.xs,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.tight),
        Text(label, style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurface)),
      ],
    );
  }
}
