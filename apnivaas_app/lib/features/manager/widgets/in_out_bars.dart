library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
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
/// in either bar. The caption says so, every time, so nobody reads a quiet month here as a
/// hostel that took no money.
///
/// AND IT IS NOT THE FRAME'S OWN CHART. `screen-manager-dashboard` (4:1215) draws a stacked
/// band of expense CATEGORIES with a percentage legend under it. Nothing in db/schema.sql
/// aggregates expenses by category — see the note on ManagerHomeScreen — so that chart cannot
/// be drawn from data. What is taken from it is the legend: the design's 6dp dot beside a 10px
/// label (4:1221), which is what the row along the top of this chart now is.
class InOutBars extends StatelessWidget {
  const InOutBars({super.key, required this.window});

  final FinanceWindow window;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final days = window.trendDays;
    final peak = window.trendPeak;

    if (days.isEmpty) {
      return const EmptyNote(
        icon: Icons.bar_chart_rounded,
        title: 'No days to chart yet',
        detail: 'The daily figures start the day this hostel books its first entry.',
      );
    }

    if (peak <= 0) {
      return EmptyNote(
        icon: Icons.bar_chart_rounded,
        title: 'Nothing booked in ${days.length} days',
        detail: 'Expenses and revenue you record show up here the same day.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: tones.success, label: 'In'),
            const SizedBox(width: Space.sm),
            _LegendDot(color: tones.warning, label: 'Out'),
            const SizedBox(width: Space.xs),
            // Expanded rather than a Spacer: at 1.6x text scale on a 320dp phone the two
            // legend dots and this sentence are wider than the row, and a Spacer has no give.
            Expanded(
              child: Text(
                'Busiest day ${moneyShort(peak)}',
                style: t.textTheme.labelSmall?.copyWith(color: context.tones.muted),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: 96,
          child: Semantics(
            label: 'Money in and out, one bar per day for the last ${days.length} days. '
                'The busiest single day is ${moneyShort(peak)}.',
            container: true,
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: _Bar(
                                  fraction: day.revenue / peak,
                                  colour: tones.success,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: _Bar(
                                  fraction: day.expense / peak,
                                  colour: tones.warning,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Text(shortDate(days.first.day),
                style: t.textTheme.labelSmall?.copyWith(color: context.tones.muted)),
            const Spacer(),
            Text(shortDate(days.last.day),
                style: t.textTheme.labelSmall?.copyWith(color: context.tones.muted)),
          ],
        ),
      ],
    );
  }
}

/// One bar. A day with nothing booked still gets a 2dp stub, so the reader can see the day
/// exists and was zero — an absent bar reads as missing data.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.colour});

  final double fraction;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    // 72dp is the tallest a bar goes, leaving headroom under the 96dp box.
    final height = fraction <= 0 ? 2.0 : (fraction.clamp(0.0, 1.0) * 72).clamp(3.0, 72.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: fraction <= 0 ? Theme.of(context).colorScheme.outlineVariant : colour,
        // The frame's own bar band is `rounded-[4px]` (4:1215) — the badge step, which is what
        // tokens.dart reserves for something too small to have a corner in the usual sense.
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.tiny)),
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
        // The design's legend dot is `size-[6px]` (4:1222). 6 is not on the spacing scale and
        // does not need to be: it is half of Space.sm, which is how the frame's own 6dp gaps
        // are expressed everywhere else in this role.
        Container(
          width: Space.sm / 2,
          height: Space.sm / 2,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.xxs),
        Text(label,
            style: t.textTheme.labelSmall
                ?.copyWith(color: t.colorScheme.onSurfaceVariant, letterSpacing: 0.2)),
      ],
    );
  }
}
