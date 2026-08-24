import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../owner_format.dart';
import 'states.dart';

/// Money in against money out, one point per day.
///
/// THE SERIES IS NOT INTERPOLATED. `rpc_daily_finance` emits a row for every day in the range
/// from `generate_series`, zero-filled, so a flat stretch on this chart is a genuinely quiet
/// week rather than a gap a charting library drew a straight line across. That is the whole
/// reason the RPC exists, and it is why nothing in this file invents a point.
///
/// WHAT IT IS NOT. These are the `revenues` and `expenses` ledgers the manager keeps. Fee
/// collections are counted separately by `rpc_fee_ledger` and shown separately on the
/// dashboard: adding the two together would double-count every hostel that also books rent as
/// revenue, which is exactly the mistake the data layer warns about on the Revenue model.
class CashflowChart extends StatelessWidget {
  const CashflowChart({super.key, required this.days});

  /// The plot's height, exported so the loading skeleton can stand in at exactly this size and
  /// the card does not jump when the series arrives.
  static const plotHeight = 148.0;

  /// A chart line has to be visible at arm's length on a cheap panel; a hairline is not.
  static const _lineWidth = 2.0;

  final List<FinanceDay> days;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Resolved: the two series are the only thing carrying meaning on this chart, and the
    // canonical inks were authored against white.
    final inTone = context.tones.success;
    final outTone = context.tones.warning;

    if (days.isEmpty) {
      return const EmptyNote(
        icon: Icons.show_chart_rounded,
        title: 'No days to chart yet',
        message: 'The daily figures start the day this PG books its first entry.',
        compact: true,
      );
    }

    final peak = days.fold<double>(
      0,
      (m, d) => [m, d.revenue, d.expense].reduce((a, b) => a > b ? a : b),
    );

    if (peak <= 0) {
      return const EmptyNote(
        icon: Icons.show_chart_rounded,
        title: 'Nothing booked in the last 30 days',
        message: 'Expenses and revenue your manager records will show up here.',
        compact: true,
      );
    }

    final ceiling = niceCeiling(peak);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wrap, not Row: at 1.4x text scale on a 320dp phone the two legends and the peak
        // figure are wider than the card, and a Row would have clipped the figure.
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LegendDot(color: inTone, label: 'Money in'),
            _LegendDot(color: outTone, label: 'Money out'),
            Text('Busiest day ${moneyShort(peak)}', style: t.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: Space.sm),
        SizedBox(
          height: plotHeight,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (days.length - 1).toDouble(),
              minY: 0,
              maxY: ceiling,
              // Titles are drawn below by hand: fl_chart's axis labels do not read from the
              // app's type scale, and a chart with its own typography is a chart that looks
              // borrowed from another product.
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              // Nothing to touch: this is a shape, not a data table. The exact figures are
              // printed underneath, where they can be read without holding a finger on glass.
              lineTouchData: const LineTouchData(enabled: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: ceiling / 2,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: t.colorScheme.outlineVariant,
                  strokeWidth: Strokes.hairline,
                ),
              ),
              lineBarsData: [
                _series(days.map((d) => d.revenue).toList(growable: false), inTone,
                    fill: context.tones.chipFill(inTone)),
                _series(days.map((d) => d.expense).toList(growable: false), outTone),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(dayLabel(days.first.day), style: t.textTheme.bodySmall),
            Text(dayLabel(days.last.day), style: t.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }

  LineChartBarData _series(List<double> values, Color color, {Color? fill}) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
      ],
      color: color,
      barWidth: _lineWidth,
      isCurved: false,
      isStrokeCapRound: true,
      isStrokeJoinRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: fill != null, color: fill),
    );
  }
}

/// Rounds a peak up to a ceiling a person would have chosen: 1, 2 or 5 times a power of ten.
///
/// Pure, and tested. Left to fl_chart the top gridline lands on 8 137.5, which is a number
/// nobody has ever wanted to read.
double niceCeiling(double peak) {
  if (peak <= 0) return 1;
  var magnitude = 1.0;
  while (magnitude * 10 <= peak) {
    magnitude *= 10;
  }
  for (final step in const [1.0, 2.0, 5.0, 10.0]) {
    final candidate = magnitude * step;
    if (candidate >= peak) return candidate;
  }
  return magnitude * 10;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Space.xs,
          height: Space.xs,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: Space.xxs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
