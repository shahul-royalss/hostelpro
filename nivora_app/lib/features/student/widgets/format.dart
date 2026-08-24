library;

import 'package:intl/intl.dart';

/// Money, months and time, as a RESIDENT reads them.
///
/// WHY THIS IS NOT THE SAME FUNCTION THE OWNER DASHBOARD USES. An owner glances at a month's
/// collections; a resident reconciles a number against their own bank app. So the owner's
/// formatter drops paise on purpose and this one does not: rounding ₹3,000.50 to ₹3,001 on the
/// screen where someone checks what they still owe is a small lie about their money, and the
/// person who notices it is the person it is about. Whole rupees still render as whole rupees,
/// because that is what every amount in this database actually is — the decimals appear only
/// when there is something there to show.
///
/// INDIAN GROUPING IS NOT COSMETIC. The default `#,###` pattern renders one lakh twenty
/// thousand as `120,000`; an Indian reader parses that shape as `12,00,000` and is out by a
/// factor of ten. Every rupee figure in the student app goes through [rupees] so no two
/// screens can disagree about where the commas go.

final NumberFormat _whole =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _exact =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Money, exactly. Paise are shown when the amount has them and hidden when it does not.
///
/// Takes a `num` and never does arithmetic on it. Every figure this receives was computed by
/// Postgres (`numeric`) or by a model getter over those values — nothing in the UI adds two
/// amounts together, which is the only way a rendered total can disagree with the ledger.
String rupees(num amount) {
  // `% 1` on a double from a numeric(10,2) is exact: the values are two-decimal quantities
  // parsed once, never accumulated, so there is no drift to guard against here.
  final hasPaise = amount % 1 != 0;
  return (hasPaise ? _exact : _whole).format(amount);
}

/// 'YYYY-MM' → 'August 2026'.
///
/// Returns the input unchanged when it is not that shape, so a surprise from the server shows
/// up as itself rather than being silently rendered as some other month.
String monthLabel(String periodMonth) {
  final parts = periodMonth.split('-');
  if (parts.length != 2) return periodMonth;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return periodMonth;
  return DateFormat('MMMM yyyy').format(DateTime(year, month));
}

/// 'YYYY-MM' → 'AUGUST'. For the eyebrow above a figure whose year is already established.
String monthEyebrow(String periodMonth) {
  final full = monthLabel(periodMonth);
  if (full == periodMonth) return periodMonth.toUpperCase();
  return full.split(' ').first.toUpperCase();
}

/// A calendar day: '19 Aug 2026'.
///
/// `date` columns are parsed to LOCAL midnight by the data layer (see parse.dart), so there is
/// nothing to convert here — calling `.toLocal()` on one would be a no-op at best.
String dayLabel(DateTime day) => DateFormat('d MMM yyyy').format(day);

/// A day without its year: '19 Aug'. For a row whose year is obvious from context.
String shortDayLabel(DateTime day) => DateFormat('d MMM').format(day);

/// How long ago something happened, in the shortest form that is still exact enough.
///
/// [now] is injectable so this is testable without waiting for the clock. Timestamps arrive
/// from Postgres in UTC and are converted here, at the point of display — the only place that
/// knows the reader's timezone.
String relativeTime(DateTime when, {DateTime? now}) {
  final at = when.toLocal();
  final gap = (now ?? DateTime.now()).difference(at);
  // A negative gap means the device clock is behind the server's. "just now" is a better
  // answer than "in 3 minutes", which reads as a bug in the app rather than in the clock.
  if (gap.isNegative || gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  if (gap.inDays < 7) return '${gap.inDays}d ago';
  return dayLabel(at);
}

/// '1 complaint' / '3 complaints'. Kept here so no screen invents its own pluralisation.
String countLabel(int n, String singular, {String? plural}) =>
    '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

/// The first word of a full name, for a greeting. Falls back to a neutral address rather than
/// greeting an empty string.
String firstName(String? fullName) {
  final trimmed = (fullName ?? '').trim();
  if (trimmed.isEmpty) return 'there';
  return trimmed.split(RegExp(r'\s+')).first;
}

/// The greeting at the top of the home screen, from the local clock.
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}
