library;

import 'package:intl/intl.dart';

/// Money, counts and time, formatted once for every owner screen.
///
/// WHY INDIAN GROUPING IS NOT COSMETIC. The default `#,###` pattern renders twelve lakh as
/// `1,200,000`; an Indian owner reads that shape as `12,00,000` and is out by a factor of ten
/// on their own month. The `en_IN` pattern (`#,##,##0`) is used everywhere money appears, so
/// the hero figure and a list row can never disagree about where the commas go.
///
/// Nothing here rounds anything into existence. [moneyShort] is only ever used on a chart axis,
/// where the exact figure is printed in full underneath it.

final NumberFormat _rupees =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Money, to the rupee. Paise are never shown: fees in this database are whole rupees in
/// practice, and a dashboard is read at a glance rather than reconciled against a bank.
String money(num amount) => _rupees.format(amount);

/// Money at chart-axis size. Indian units — k, L (lakh), Cr (crore) — because "₹1.2L" is a
/// number an owner reads instantly and "₹120.0K" is one they have to convert.
String moneyShort(num amount) {
  final v = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (v >= 10000000) {
    return '$sign₹${(v / 10000000).toStringAsFixed(v >= 100000000 ? 0 : 1)}Cr';
  }
  if (v >= 100000) {
    return '$sign₹${(v / 100000).toStringAsFixed(v >= 1000000 ? 0 : 1)}L';
  }
  if (v >= 1000) {
    return '$sign₹${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
  }
  return '$sign₹${v.round()}';
}

/// A 0.0–1.0 rate as a whole percentage. Rounded, never truncated: 0.669 is 67%, not 66%.
String percentLabel(double rate) => '${(rate * 100).round()}%';

/// 'YYYY-MM' → 'August 2026'. Returns the input unchanged if it is not that shape, so a
/// surprise from the server shows up as itself rather than as a wrong month.
String monthLabel(String periodMonth) {
  final parts = periodMonth.split('-');
  if (parts.length != 2) return periodMonth;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return periodMonth;
  return DateFormat('MMMM yyyy').format(DateTime(year, month));
}

/// 'YYYY-MM' → 'August'. For captions where the year is already established above.
String monthNameOnly(String periodMonth) {
  final full = monthLabel(periodMonth);
  return full == periodMonth ? periodMonth : full.split(' ').first;
}

/// A day on a chart axis or a list row: '24 Aug'.
String dayLabel(DateTime day) => DateFormat('d MMM').format(day);

/// How long ago something happened, in the shortest form that is still exact enough.
///
/// [now] is injectable so this is testable without waiting for the clock. Timestamps arrive
/// from Postgres in UTC (see parse.dart) and are converted here, at the point of display,
/// which is the only place that knows the reader's zone.
String relativeTime(DateTime when, {DateTime? now}) {
  final at = when.toLocal();
  final from = now ?? DateTime.now();
  final gap = from.difference(at);
  // A negative gap means the device clock is behind the server's. Say "just now" rather than
  // "in 3 minutes", which would look like a bug in the app rather than in the clock.
  if (gap.isNegative || gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  if (gap.inDays < 7) return '${gap.inDays}d ago';
  return dayLabel(at);
}

/// '1 resident' / '12 residents'. Kept here so no screen invents its own pluralisation.
String countLabel(int n, String singular, {String? plural}) =>
    '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

/// The greeting at the top of the dashboard, from the local clock.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// The first word of a full name, for a greeting. Falls back to the whole string, and to a
/// neutral address when the profile has no name at all.
String firstName(String? fullName) {
  final trimmed = (fullName ?? '').trim();
  if (trimmed.isEmpty) return 'there';
  return trimmed.split(RegExp(r'\s+')).first;
}
