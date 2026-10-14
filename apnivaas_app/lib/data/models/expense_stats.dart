library;

import 'enums.dart';
import 'parse.dart';

/// WHAT THE EXPENSE CHARTS ARE DRAWN FROM.
///
/// The product owner asked for "graphs, stats dashboard that owner and manager can view expenses
/// in that model it compares other months". Two RPCs answer it, both SECURITY INVOKER so
/// expenses_select decides who sees what — the hostel's owner, its manager, the Super Admin:
///
///   public.rpc_expense_months(hostel, months)  one row per month × kind × category
///   public.rpc_expense_days(hostel, 'YYYY-MM') one row per day × kind
///
/// AGGREGATED IN POSTGRES, NOT ON THE PHONE. A PG that records forty vegetable purchases a month
/// would ship 480 rows to draw a twelve-month bar chart; grouped, the same chart is a few dozen.
/// It also means the figures cannot disagree with the ledger list, which sums the same column.

/// One month's spending under one kind and one category.
class ExpenseMonthSlice {
  const ExpenseMonthSlice({
    required this.periodMonth,
    required this.kind,
    required this.category,
    required this.total,
    required this.entries,
  });

  /// `YYYY-MM`, in Asia/Kolkata calendar months — see the RPC. Never parsed into a DateTime
  /// here: it is a key, and turning it into a local midnight is how a month drifts by one.
  final String periodMonth;
  final ExpenseKind kind;
  final ExpenseCategory category;
  final double total;
  final int entries;

  factory ExpenseMonthSlice.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_expense_months';
    return ExpenseMonthSlice(
      periodMonth: reqString(row, src, 'period_month'),
      kind: ExpenseKind.tryParse(row['kind'] as String?) ?? ExpenseKind.daily,
      category: wireOrThrow(ExpenseCategory.values, row['category'], src, 'category'),
      total: reqDouble(row, src, 'total'),
      entries: reqInt(row, src, 'entries'),
    );
  }
}

/// One day's spending under one kind.
class ExpenseDaySlice {
  const ExpenseDaySlice({
    required this.day,
    required this.kind,
    required this.total,
    required this.entries,
  });

  final DateTime day;
  final ExpenseKind kind;
  final double total;
  final int entries;

  factory ExpenseDaySlice.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_expense_days';
    return ExpenseDaySlice(
      day: reqDate(row, src, 'day'),
      kind: ExpenseKind.tryParse(row['kind'] as String?) ?? ExpenseKind.daily,
      total: reqDouble(row, src, 'total'),
      entries: reqInt(row, src, 'entries'),
    );
  }
}

/// The folded view a chart actually needs: months in order, and what each one holds.
///
/// PURE ARITHMETIC, NO WIDGETS. Every interesting case here is an edge case — a month with
/// nothing in it, a first month with no month before it to compare against, a category that
/// appears in one month and not the next — and none of them is reachable by tapping around a
/// seeded demo. Keeping the fold out of the widget is what makes them testable.
class ExpenseStats {
  const ExpenseStats._(this.months, this._byMonth);

  /// Every month in the window, oldest first, INCLUDING months with no spending.
  ///
  /// The gaps are filled deliberately. A bar chart drawn from only the months that have rows
  /// puts March next to June and reads as three consecutive months; the eye measures position,
  /// not labels. An empty month is a real answer and is drawn as a zero-height bar.
  final List<String> months;

  final Map<String, List<ExpenseMonthSlice>> _byMonth;

  /// [slices] as the RPC returned them, plus the window it was asked for.
  ///
  /// [monthsWanted] and [latest] come from the caller rather than from the rows, because rows
  /// cannot describe a month in which nothing happened — which is exactly the month the gap
  /// filling exists for.
  factory ExpenseStats.from(
    List<ExpenseMonthSlice> slices, {
    required String latest,
    required int monthsWanted,
  }) {
    final keys = <String>[];
    var year = int.parse(latest.substring(0, 4));
    var month = int.parse(latest.substring(5, 7));
    for (var i = 0; i < monthsWanted; i++) {
      keys.add('${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}');
      month -= 1;
      if (month == 0) {
        month = 12;
        year -= 1;
      }
    }
    final ordered = keys.reversed.toList(growable: false);

    final byMonth = <String, List<ExpenseMonthSlice>>{for (final k in ordered) k: <ExpenseMonthSlice>[]};
    for (final slice in slices) {
      // A row outside the window can only mean the clock moved between the two calls. Adding a
      // month the axis does not have would silently widen the chart, so it is dropped.
      byMonth[slice.periodMonth]?.add(slice);
    }
    return ExpenseStats._(ordered, byMonth);
  }

  List<ExpenseMonthSlice> slicesIn(String month) => _byMonth[month] ?? const [];

  double totalIn(String month) =>
      slicesIn(month).fold(0, (sum, s) => sum + s.total);

  double totalOfKind(String month, ExpenseKind kind) =>
      slicesIn(month).where((s) => s.kind == kind).fold(0, (sum, s) => sum + s.total);

  int entriesIn(String month) => slicesIn(month).fold(0, (sum, s) => sum + s.entries);

  /// Spending per category in one month, largest first. Categories with nothing are absent —
  /// unlike months, a category that was not used is not a gap in a sequence.
  List<({ExpenseCategory category, double total})> byCategory(String month) {
    final totals = <ExpenseCategory, double>{};
    for (final s in slicesIn(month)) {
      totals[s.category] = (totals[s.category] ?? 0) + s.total;
    }
    final out = [for (final e in totals.entries) (category: e.key, total: e.value)];
    out.sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  /// The tallest month in the window — what the bars are scaled against. Zero when nothing was
  /// spent at all, which the chart must treat as "no bars", never as a divisor.
  double get peak => months.fold<double>(0, (m, k) {
        final t = totalIn(k);
        return t > m ? t : m;
      });

  /// The month before [month] in this window, or null when [month] is the oldest one shown.
  String? previousOf(String month) {
    final i = months.indexOf(month);
    return i <= 0 ? null : months[i - 1];
  }

  /// Change against the previous month as a FRACTION (0.12 = 12% more), or null when there is
  /// nothing honest to compare against.
  ///
  /// Null in two cases, and they are different from "no change": no previous month is in the
  /// window at all, and a previous month of zero — where a percentage would be a division by
  /// zero that reads as "infinity% up" if it is computed anyway.
  double? changeVsPrevious(String month) {
    final previous = previousOf(month);
    if (previous == null) return null;
    final before = totalIn(previous);
    if (before <= 0) return null;
    return (totalIn(month) - before) / before;
  }
}
