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

  /// Whether these days will actually draw a plot rather than one of the two empty notes below.
  ///
  /// Exported so the section heading above the well can decide whether to show [CashflowLegend]
  /// beside it: a legend over an "nothing booked in the last 30 days" card names two lines that
  /// are not on the screen. The two callers agreeing on one predicate is the point — this used
  /// to be knowable only by getting as far as [build].
  static bool hasPlot(List<FinanceDay> days) {
    for (final d in days) {
      if (d.revenue > 0 || d.expense > 0) return true;
    }
    return false;
  }

  final List<FinanceDay> days;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final inTone = _incomeTone(t.colorScheme);
    final outTone = _expenseTone(t.colorScheme);

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
        // The two legend dots have moved OUT of the plot and up beside the section label, which
        // is where 4:437 puts them. What stays is the scale — the peak is the only number on
        // this chart, and a plot whose tallest point is unlabelled cannot be read at all.
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
                _series(days.map((d) => d.expense).toList(growable: false), outTone,
                    dash: _expenseDash),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        // The design's axis row — `W1 … W4` along the foot of the plot. Real dates rather than
        // week ordinals: the series is 30 calendar days from `rpc_daily_finance`, and "W3" is a
        // bucket nothing in this app actually computes.
        Row(
          children: [
            Text(dayLabel(days.first.day), style: t.textTheme.bodySmall),
            Expanded(
              child: Text(
                'Busiest day ${moneyShort(peak)}',
                style: t.textTheme.bodySmall,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(dayLabel(days.last.day), style: t.textTheme.bodySmall),
          ],
        ),
      ],
    );
  }

  LineChartBarData _series(List<double> values, Color color, {Color? fill, List<int>? dash}) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
      ],
      color: color,
      barWidth: _lineWidth,
      isCurved: false,
      isStrokeCapRound: dash == null,
      isStrokeJoinRound: true,
      dashArray: dash,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: fill != null, color: fill),
    );
  }
}

/// Money in — the design's own gold line (4:437). The brand accent carries the series an owner
/// came to look at; expenses are the counterweight, not a second headline.
Color _incomeTone(ColorScheme scheme) => scheme.primary;

/// Money out. `#6F747A` on the frame, which is [ColorScheme.outline] — 3.70:1 on the chart
/// well, past the 3:1 a graphical object owes its background. It is NOT the amber this app
/// uses for warnings: an expense is not a problem, and spending the warning colour on every
/// ledger entry would leave nothing to say with it on the card two sections up.
Color _expenseTone(ColorScheme scheme) => scheme.outline;

/// THE DASH IS THE POINT, not a texture. The two series are told apart by pattern first and
/// hue second, so the chart still reads for the ~8% of men who cannot separate these two by
/// colour — and on the greyscale a cheap panel effectively renders in.
const _expenseDash = <int>[4, 4];

/// The chart's key, drawn beside the section label rather than inside the plot — 4:437 puts
/// `● Income  ● Expenses` on the heading row.
///
/// THE LABELS ARE NOT PAINTED IN THEIR SERIES COLOUR, which is the one thing here the mockup
/// does and this does not. Gold text would be fine (8.70:1 on the ground); the expense grey is
/// 4.13:1, a fail at 10px. Colouring one and not the other would be worse than colouring
/// neither, so the DOT carries the hue — and the expense dot carries the dash as well, so the
/// key shows the mark it is naming — and both labels stay in the legible secondary ink.
class CashflowLegend extends StatelessWidget {
  const CashflowLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LegendMark(color: _incomeTone(scheme), label: 'Money in'),
        _LegendMark(color: _expenseTone(scheme), label: 'Money out', dashed: true),
      ],
    );
  }
}

class _LegendMark extends StatelessWidget {
  const _LegendMark({required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A solid rule for the solid series, two ticks for the dashed one: the key draws the
        // mark, not a dot that stands in for it.
        SizedBox(
          width: IconSize.xs,
          height: Strokes.glyph,
          child: dashed
              ? Row(
                  children: [
                    Expanded(child: ColoredBox(color: color)),
                    const SizedBox(width: Strokes.glyph),
                    Expanded(child: ColoredBox(color: color)),
                  ],
                )
              : ColoredBox(color: color),
        ),
        const SizedBox(width: Space.xxs),
        Text(label, style: t.textTheme.labelSmall),
      ],
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
