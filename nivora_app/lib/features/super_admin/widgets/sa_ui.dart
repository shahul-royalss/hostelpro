library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/sign_in_again.dart';
import '../data/sa_models.dart';

/// The Super Admin console's own small kit: formatters, the three not-showing-data states, and
/// the handful of shapes that repeat across five screens.
///
/// WHY THIS IS NOT AN IMPORT FROM features/owner OR features/warden. Each role in this app owns
/// its vocabulary, and the three kits have genuinely diverged: a warden's `StatusPill` speaks
/// bed and fee states, an owner's `StatusChip` is built for one hostel's dashboard, and nothing
/// in either knows what an expired subscription does to a hostel — which is the single most
/// important sentence on these screens. Copying a widget across features would be the wrong
/// trade; what is shared lives in shared/glass and core/theme, and both are used here.
///
/// Nothing below hardcodes a colour, a radius, a duration or a spacing value. They all come
/// from core/theme/tokens.dart — including the tint behind the not-showing-data panels, which
/// goes through NivoraSemantics.chipFill/chipBorder rather than an alpha typed in by eye. A
/// literal alpha is a light-theme alpha painted twice: the dark theme needs a different one to
/// land on the same contrast ratio, and only the token knows that.
///
/// The claim is about tokens, not about every number in the file. An intrinsic dimension that
/// belongs to one widget and to nothing else — the 116dp label column in [SaDetailRow], the 8dp
/// track in [SaMeter] — is stated where it is used, because a token nobody else can spend is
/// not a token.

// ─────────────────────────────────────────────────────────────────────────────
// FORMATTERS
// ─────────────────────────────────────────────────────────────────────────────

final NumberFormat _rupees =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _plain = NumberFormat.decimalPattern('en_IN');
final DateFormat _day = DateFormat('d MMM yyyy');
final DateFormat _dayShort = DateFormat('d MMM');
final DateFormat _stamp = DateFormat('d MMM, HH:mm');

/// Money, to the rupee, in Indian grouping.
///
/// `#,##,##0`, not `#,###`. Twelve lakh rendered as `1,200,000` is read by an Indian owner as
/// `12,00,000` — out by a factor of ten on their own platform revenue.
String money(num amount) => _rupees.format(amount);

/// Money at badge size — k, L (lakh), Cr (crore). Used only where the exact figure is available
/// somewhere else on the same screen.
String moneyShort(num amount) {
  final v = amount.abs();
  final sign = amount < 0 ? '-' : '';
  if (v >= 10000000) {
    return '$sign₹${(v / 10000000).toStringAsFixed(v >= 100000000 ? 0 : 1)}Cr';
  }
  if (v >= 100000) {
    return '$sign₹${(v / 100000).toStringAsFixed(v >= 1000000 ? 0 : 1)}L';
  }
  if (v >= 1000) return '$sign₹${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
  return '$sign₹${v.round()}';
}

/// A count, grouped the Indian way. 12,00,000 hostels is not a realistic number; 1,20,000
/// residents is, eventually.
String count(num n) => _plain.format(n);

/// '24 Aug 2026'.
String dateLabel(DateTime d) => _day.format(d);

/// '24 Aug' — for a range where the year is already established.
String dayLabel(DateTime d) => _dayShort.format(d);

/// '24 Aug, 14:05' in the reader's own zone. Timestamps arrive from Postgres in UTC.
String stampLabel(DateTime d) => _stamp.format(d.toLocal());

/// 'YYYY-MM' → 'Aug'. The chart axis; the full month is in the tooltip line beneath it.
String monthShort(String periodMonth) {
  final parts = periodMonth.split('-');
  if (parts.length != 2) return periodMonth;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return periodMonth;
  return DateFormat('MMM').format(DateTime(year, month));
}

/// 'YYYY-MM' → 'August 2026'.
String monthLabel(String periodMonth) {
  final parts = periodMonth.split('-');
  if (parts.length != 2) return periodMonth;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return periodMonth;
  return DateFormat('MMMM yyyy').format(DateTime(year, month));
}

/// How long ago, in the shortest exact form. [now] is injectable so this is testable.
String relativeTime(DateTime when, {DateTime? now}) {
  final at = when.toLocal();
  final gap = (now ?? DateTime.now()).difference(at);
  // A negative gap means the device clock is behind the server's. "in 3 minutes" would look
  // like a bug in the app rather than in the clock.
  if (gap.isNegative || gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes}m ago';
  if (gap.inHours < 24) return '${gap.inHours}h ago';
  if (gap.inDays < 7) return '${gap.inDays}d ago';
  return dayLabel(at);
}

/// '1 hostel' / '9 hostels'. Kept here so no screen invents its own pluralisation.
String plural(int n, String singular, {String? many}) =>
    '${count(n)} ${n == 1 ? singular : (many ?? '${singular}s')}';

/// A subscription's remaining days as a sentence, from the server's own `days_left`.
///
/// Null means there has never been a subscription for that hostel — the LEFT JOIN LATERAL in
/// rpc_sa_hostels found nothing — which is a different thing from "expired" and says so.
String daysLeftLabel(int? daysLeft) {
  if (daysLeft == null) return 'No subscription on record';
  if (daysLeft < 0) return 'Expired ${plural(-daysLeft, 'day')} ago';
  if (daysLeft == 0) return 'Ends today';
  if (daysLeft == 1) return 'Ends tomorrow';
  return '${plural(daysLeft, 'day')} left';
}

// ─────────────────────────────────────────────────────────────────────────────
// WRITABILITY — the rule the whole console exists to surface
// ─────────────────────────────────────────────────────────────────────────────

/// Whether a hostel can still be written to, and why not when it cannot.
///
/// THIS MIRRORS lib/permissions.ts:301 IN THE WEB APP, deliberately and exactly:
///
///     writable = hostel.status === "active" && subscriptionState !== "expired"
///
/// A read-only hostel is not a cosmetic state. Its warden cannot register a resident, its
/// cashier cannot record a payment, and every write RPC in db/schema.sql refuses with SQLSTATE
/// 42501 through `app.hostel_writable()`. That is the single fact a platform admin most needs
/// to see, so it is computed once here and rendered the same way on the list, the detail screen
/// and the subscriptions tab.
///
/// AND IT IS NOT A CONTROL. Nothing in this app decides whether a write is allowed; the
/// database does, from the same two columns. This extension only decides what to draw.
extension SaHostelWritability on SaHostelRow {
  bool get isWritable =>
      hostelStatus == HostelStatus.active && subState != SubscriptionState.expired;

  /// The reason, in the words a Super Admin would use to explain it to the owner on the phone.
  /// Null when the hostel is writable.
  String? get readOnlyReason {
    if (hostelStatus == HostelStatus.suspended) {
      return 'Suspended by Nivora. Staff can read but cannot record anything.';
    }
    if (hostelStatus == HostelStatus.readonly) {
      return 'Marked read-only. Staff can read but cannot record anything.';
    }
    if (subState == SubscriptionState.expired) {
      return subEnd == null
          ? 'No subscription has ever been recorded, so every write is refused.'
          : 'The subscription ended on ${dateLabel(subEnd!)}. Staff can read but cannot '
              'register residents, record payments or resolve complaints until it is renewed.';
    }
    return null;
  }

  /// Occupied beds as a 0–1 rate. Zero beds is 0, never a divide-by-zero — a hostel scaffolded
  /// with no rooms yet is a real state on the day it is created.
  double get occupancyRate => totalBeds == 0 ? 0 : occupiedBeds / totalBeds;
}

// ─────────────────────────────────────────────────────────────────────────────
// TONES
// ─────────────────────────────────────────────────────────────────────────────

/// The colour a subscription state is drawn in — resolved for THIS theme, so it is legible as
/// text on a light surface and on a dark one. See NivoraSemantics.
Color subscriptionTone(BuildContext context, SubscriptionState state) => switch (state) {
      SubscriptionState.active => context.tones.success,
      SubscriptionState.expiring => context.tones.warning,
      SubscriptionState.expired => context.tones.error,
    };

Color hostelTone(BuildContext context, HostelStatus status) => switch (status) {
      HostelStatus.active => context.tones.success,
      HostelStatus.readonly => context.tones.warning,
      HostelStatus.suspended => context.tones.error,
    };

Color severityTone(BuildContext context, AlertSeverity severity) => switch (severity) {
      AlertSeverity.low => context.tones.muted,
      AlertSeverity.medium => context.tones.info,
      AlertSeverity.high => context.tones.warning,
      AlertSeverity.critical => context.tones.error,
    };

// ─────────────────────────────────────────────────────────────────────────────
// STRUCTURE
// ─────────────────────────────────────────────────────────────────────────────

/// A console tab: glass header, scrollable body, pull to refresh.
///
/// Every tab is built from this so the header geometry, the safe-area inset and the refresh
/// gesture are decided once. [actions] sit to the right of the title.
class SaScreen extends StatelessWidget {
  const SaScreen({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow = 'SUPER ADMIN',
    this.subtitle,
    this.actions = const [],
    this.onRefresh,
    this.scrollable = true,
  });

  final String title;
  final String eyebrow;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final Future<void> Function()? onRefresh;

  /// False when the child manages its own scrolling — a paginated list must own its viewport
  /// or it cannot know when it has been scrolled to the end.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    Widget body = child;
    if (scrollable) {
      body = SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Space.md,
          Space.md,
          Space.md,
          Space.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        child: child,
      );
    }
    if (onRefresh != null) {
      body = RefreshIndicator(onRefresh: onRefresh!, child: body);
    }

    return Column(
      children: [
        GlassHeader(
          child: Row(
            children: [
              const SaBrandDot(),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow, style: t.textTheme.labelSmall),
                    // 4:135 sets the header's own title at 16/700, not at 20. The design has
                    // no 20pt type on any screen; letting the bar outweigh the KPI figures
                    // under it is what made this console read as a different app.
                    Text(title,
                        style: t.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: t.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// The 8dp gold disc the design puts before the wordmark in every header — 4:134.
///
/// It is the only piece of brand furniture on these screens, and it costs eight pixels. Without
/// it the header is a line of text with an icon at the far end and nothing marks the bar as
/// belonging to a product.
class SaBrandDot extends StatelessWidget {
  const SaBrandDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: Space.xs,
        height: Space.xs,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      );
}

/// A pushed page inside the console — the hostel detail and the create wizard.
///
/// Uses the same glass header as a tab, with a back affordance, rather than a Material AppBar:
/// two different bars in one role's navigation is the fastest way to make an app feel assembled
/// rather than designed.
class SaPage extends StatelessWidget {
  const SaPage({
    super.key,
    required this.title,
    required this.child,
    this.eyebrow,
    this.actions = const [],
    this.onRefresh,
    this.bottomBar,
    this.scrollable = true,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final Widget child;
  final Future<void> Function()? onRefresh;
  final Widget? bottomBar;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    Widget body = child;
    if (scrollable) {
      body = SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Space.md,
          Space.md,
          Space.md,
          Space.xxl + (bottomBar == null ? MediaQuery.paddingOf(context).bottom : 0),
        ),
        child: child,
      );
    }
    if (onRefresh != null) {
      body = RefreshIndicator(onRefresh: onRefresh!, child: body);
    }

    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: Space.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) Text(eyebrow!, style: t.textTheme.labelSmall),
                      // Same 16/700 as [SaScreen]'s header, and for the same reason.
                      Text(title,
                          style: t.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

/// A section label — the design's 12px uppercase rule (4:161 "SUBSCRIPTION HEALTH", 4:179
/// "PG GROWTH (6 MONTHS)", 4:202 "RECENT SECURITY ALERTS").
///
/// IT USED TO BE A 20/700 TITLE, and that was the single biggest thing making this console look
/// like a different app from its own mockup. `screen-dashboard` has no 20pt type anywhere: the
/// heaviest thing on the page is a KPI figure at 16/700, and sections are separated by a hairline
/// rule plus a small caps label in the tertiary ink. A 20pt heading over a 16pt number inverts
/// that — the furniture outranks the data.
///
/// [accent] is the design's right-hand figure, set in the gold (4:180). It is the one place on
/// a section header where a number may appear, so it is typed as a String the caller has already
/// computed from real rows rather than as free-form widgets.
class SaHeading extends StatelessWidget {
  const SaHeading({
    super.key,
    required this.title,
    this.caption,
    this.trailing,
    this.accent,
  });

  final String title;
  final String? caption;
  final Widget? trailing;

  /// A short figure in the accent, right-aligned. Ignored when [trailing] is given.
  final String? accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // labelMedium IS `label-caps` — Inter 12/16/600. A TextStyle cannot uppercase,
                // so the string does it here.
                Text(title.toUpperCase(), style: t.textTheme.labelMedium),
                if (caption != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(caption!, style: t.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (accent != null)
            Padding(
              padding: const EdgeInsets.only(left: Space.xs),
              child: Text(
                accent!,
                style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// The hairline between two sections of a page — 4:159, 4:176, 4:200, which are the same rule.
///
/// The design does not box its dashboard sections into cards; it lays them on the ground and
/// separates them with a 1px `#292E33` line and a 20dp gap either side. That is why the screen
/// reads as one document rather than as a stack of tiles.
class SaSectionRule extends StatelessWidget {
  const SaSectionRule({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: Divider(
        height: Strokes.hairline,
        thickness: Strokes.hairline,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// The design's 32dp square icon button (4:136, the bell) — a raised tile at [Radii.control]
/// rather than Material's bare circular ripple, with the design's own 8dp dot for "there is
/// something in here".
///
/// The dot is a BOOLEAN, not a count. 4:138 is an 8dp square of solid tone with no numeral in
/// it: at this size a number is unreadable, and the tab bar below already carries the exact
/// count on the Security destination.
class SaIconButton extends StatelessWidget {
  const SaIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.dot,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// The tone of the corner dot. Null draws none.
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: Radii.rControl,
          child: Container(
            // The design's 32dp square. The 48dp tap minimum is met by the InkWell's parent
            // padding in the header, which is where the rest of the target lives.
            width: Space.xxl,
            height: Space.xxl,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainer,
              borderRadius: Radii.rControl,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(icon, size: IconSize.md, color: t.colorScheme.onSurface),
                if (dot != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: Space.xs,
                      height: Space.xs,
                      decoration: BoxDecoration(
                        color: context.tones.resolve(dot!),
                        borderRadius: Radii.rTiny,
                      ),
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

/// A tinted state pill. Never filled: a row of saturated chips turns a list into a bag of
/// sweets and stops any one of them meaning anything. The alphas come from NivoraSemantics,
/// which measured them against the 11px text that sits on top.
class SaPill extends StatelessWidget {
  const SaPill({super.key, required this.label, required this.tone, this.icon});

  final String label;
  final Color tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs),
      decoration: BoxDecoration(
        color: tones.chipFill(tone),
        borderRadius: Radii.rControl,
        border: Border.all(color: tones.chipBorder(tone)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: IconSize.xs, color: tones.resolve(tone)),
            const SizedBox(width: Space.xxs),
          ],
          Text(label, style: t.textTheme.labelSmall?.copyWith(color: tones.resolve(tone))),
        ],
      ),
    );
  }
}

/// The pill for a hostel's subscription. One widget so the list, the detail page and the
/// subscriptions tab cannot describe the same hostel differently.
class SaSubscriptionPill extends StatelessWidget {
  const SaSubscriptionPill({super.key, required this.state, this.daysLeft});

  final SubscriptionState state;
  final int? daysLeft;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      SubscriptionState.active => 'Active',
      SubscriptionState.expiring =>
        daysLeft == null ? 'Expiring' : '${daysLeft}d left',
      SubscriptionState.expired => 'Expired',
    };
    return SaPill(
      label: label,
      tone: subscriptionTone(context, state),
      icon: switch (state) {
        SubscriptionState.active => Icons.verified_rounded,
        SubscriptionState.expiring => Icons.schedule_rounded,
        SubscriptionState.expired => Icons.lock_rounded,
      },
    );
  }
}

/// The band that says a hostel is read-only, and why.
///
/// THE MOST IMPORTANT WIDGET ON THESE SCREENS. Everything else on a hostel row is reporting;
/// this one is the thing the platform admin is expected to act on. Given a writable hostel it
/// draws nothing at all — a reassuring green "writable" band on every row would drown the three
/// that are not.
class SaReadOnlyBand extends StatelessWidget {
  const SaReadOnlyBand({super.key, required this.hostel, this.compact = false});

  final SaHostelRow hostel;

  /// Kept for the call sites that pass it. The band is now the design's fixed strip (Figma
  /// 4:1531), which has one size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reason = hostel.readOnlyReason;
    if (reason == null) return const SizedBox.shrink();

    final tone = hostel.hostelStatus == HostelStatus.active
        ? NivoraColors.error
        : hostelTone(context, hostel.hostelStatus);

    return NoticeBanner(
      icon: Icons.lock_rounded,
      tone: tone,
      eyebrow: 'Read-only',
      message: reason,
    );
  }
}

/// A labelled value on a detail sheet. Wraps rather than truncating: an address and an owner's
/// email are the two things somebody copies off this screen by hand.
class SaDetailRow extends StatelessWidget {
  const SaDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.tone,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label.toUpperCase(), style: t.textTheme.labelSmall),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              value,
              style: tone == null
                  ? t.textTheme.bodyMedium
                  : t.textTheme.titleSmall?.copyWith(color: context.tones.resolve(tone!)),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A horizontal fill bar with its own label. Used for occupancy, which is the one ratio on
/// these screens that is genuinely a ratio rather than a count.
class SaMeter extends StatelessWidget {
  const SaMeter({
    super.key,
    required this.rate,
    required this.label,
    this.caption,
    this.tone,
  });

  /// 0.0–1.0. Clamped, because a bar that overflows its track reads as a rendering bug rather
  /// than as a number over 100%.
  final double rate;
  final String label;
  final String? caption;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final value = rate.clamp(0.0, 1.0);
    final accent = tone == null ? t.colorScheme.primary : context.tones.resolve(tone!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label.toUpperCase(), style: t.textTheme.labelSmall)),
            Text('${(value * 100).round()}%', style: t.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: Space.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.control / 2),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: t.colorScheme.outlineVariant,
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: Space.xxs),
          Text(caption!, style: t.textTheme.bodySmall),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE NOT-SHOWING-DATA STATES — loading, empty, failed, unverified, refused
//
// FIVE, AND EACH ONE LOOKS DIFFERENT, because they lead to opposite actions. "No overdue
// tasks" and "we could not reach the server" are not the same sentence; a dash where a number
// should be is read as a zero; and a panel that quietly fails to draw tells the reader nothing
// is wrong when something is. A skeleton pulses, an empty state is plain, a failure is drawn in
// error tone with a retry, an unverified answer is drawn in info tone with a way to resolve it,
// and a refusal is drawn in warning tone with no retry at all — because retrying a refusal
// cannot work, and an affordance that cannot work is a lie with a button on it.
// ─────────────────────────────────────────────────────────────────────────────

/// Draws one async section: skeleton, error, or content.
///
/// GO THROUGH THIS RATHER THAN CALLING `.when` DIRECTLY. Riverpod 3 retries a failed provider
/// on its own, and while a retry is pending the state is `AsyncLoading` that still carries the
/// previous error — `hasError` true AND `isLoading` true. `.when()` with its default flags takes
/// the loading branch, so a query that fails shows a skeleton that pulses forever and the error
/// state written for it is never once rendered. `skipLoadingOnReload` is what fixes it; a first
/// load, which has no previous state, still shows the skeleton, which is the one time a skeleton
/// is the right answer.
Widget saAsync<T>(
  AsyncValue<T> value, {
  required Widget Function(T value) data,
  required Widget Function(Object error) error,
  required Widget Function() loading,
}) {
  return value.when(
    skipLoadingOnRefresh: true,
    skipLoadingOnReload: true,
    data: data,
    error: (e, _) => error(e),
    loading: loading,
  );
}

/// A placeholder block, sized like the thing it stands in for.
class SaSkeleton extends StatefulWidget {
  const SaSkeleton({super.key, this.width, this.height = 14, this.radius = Radii.control});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SaSkeleton> createState() => _SaSkeletonState();
}

class _SaSkeletonState extends State<SaSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: Motion.slow);

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    // Someone who asked the OS to reduce motion usually had a reason. The placeholder still
    // appears; it just stops breathing.
    if (MediaQuery.disableAnimationsOf(context)) return box;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1)
          .animate(CurvedAnimation(parent: _pulse, curve: Motion.move)),
      child: box,
    );
  }
}

/// A skeleton in the shape of a card.
class SaSkeletonCard extends StatelessWidget {
  const SaSkeletonCard({super.key, this.lines = 2, this.height});

  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SaSkeleton(width: 96, height: 10),
          const SizedBox(height: Space.sm),
          for (var i = 0; i < lines; i++) ...[
            SaSkeleton(width: i.isEven ? double.infinity : 180, height: 14),
            if (i != lines - 1) const SizedBox(height: Space.xs),
          ],
        ],
      ),
    );
  }
}

/// Nothing to show, and that is fine — said out loud, because an empty list and a failed one
/// look identical when neither says anything.
class SaEmpty extends StatelessWidget {
  const SaEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? Space.sm : Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: IconSize.md, color: t.colorScheme.outline),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(title, style: t.textTheme.titleMedium)),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: Space.xxs),
            Text(message!, style: t.textTheme.bodySmall),
          ],
          if (action != null) ...[
            const SizedBox(height: Space.sm),
            Align(alignment: Alignment.centerLeft, child: action!),
          ],
        ],
      ),
    );
  }
}

/// A failure, with the next step spelled out and a retry only where retrying could work.
class SaError extends StatelessWidget {
  const SaError({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final tone = tones.error;
    final guidance = saErrorGuidance(error);
    // A dead credential is the one terminal state with a recovery that is neither a retry nor
    // an errand: it is one tap, and the console owes the reader that tap rather than a sentence
    // ending in "sign in again" and no way to.
    final needsSignIn = AppFailure.from(error).needsSignIn;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: tones.chipBorder(tone)),
        color: tones.chipFill(tone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: IconSize.md, color: tone),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(guidance.title, style: t.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(guidance.next, style: t.textTheme.bodySmall),
          if (!compact && needsSignIn) ...[
            const SizedBox(height: Space.sm),
            const Align(
              alignment: Alignment.centerLeft,
              child: SignInAgainButton(outlined: true),
            ),
          ] else if (guidance.canRetry && onRetry != null && !compact) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: IconSize.sm),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What went wrong, said in the Super Admin's terms, and whether a retry is honest.
///
/// EXHAUSTIVE OVER A SEALED TYPE on purpose: a tenth failure kind added to the data layer
/// becomes a compile error here rather than a silently generic message. The wording differs from
/// the owner's and the warden's versions because the reader differs — a platform admin is the
/// person who FIXES an expired subscription rather than the person blocked by one.
({String title, String next, bool canRetry}) saErrorGuidance(Object error) {
  final failure = AppFailure.from(error);
  return switch (failure) {
    OfflineFailure() => (
        title: 'No connection',
        next: 'This phone cannot reach Nivora. Reconnect, then pull down to refresh.',
        canRetry: true,
      ),
    // ═══ READ THE NOTE BEFORE REWORDING THIS ═══
    // This sentence is the one that cost a live debugging session. It was shown to the platform
    // owner — signed in as the super admin, on an aal2 session the server was perfectly willing
    // to serve — because his access token had expired an hour earlier and the client had
    // quietly fallen back to the anon key, which `rpc_sa_dashboard()` refuses with zero rows in
    // exactly the same shape as a real impostor. He spent the session auditing an account that
    // was never broken.
    //
    // The wording is unchanged and still correct, because the DATA LAYER no longer produces
    // this failure for a dead session: rpcRowOrRefusal only names a refusal when the token that
    // asked was alive (data/repositories/repository.dart), and a dead one becomes
    // SessionExpiredFailure below. This branch now means what it says.
    AccessDeniedFailure() => (
        title: 'Not permitted',
        next: 'This console is for the Super Admin account. Sign in with that account to '
            'see platform data.',
        canRetry: false,
      ),
    SessionExpiredFailure() => (
        title: 'Sign-in expired',
        next: 'Your sign-in ran out and could not be renewed, so the server answered nobody. '
            'This is not about your account or your role — sign in again.',
        canRetry: false,
      ),
    ReadOnlyFailure() => (
        title: 'Hostel is read-only',
        next: 'That hostel refuses writes until its subscription is renewed.',
        canRetry: false,
      ),
    NotFoundFailure() => (
        title: 'No longer there',
        next: 'That record has been removed. Go back and pick it again from the list.',
        canRetry: false,
      ),
    SignedOutFailure() => (
        title: 'Session ended',
        next: 'Sign out and sign in again to continue.',
        canRetry: false,
      ),
    ServerFailure() => (
        title: 'Nivora is struggling',
        next: 'The server did not answer in time. Try again in a moment.',
        canRetry: true,
      ),
    ConflictFailure() => (title: 'Already recorded', next: failure.message, canRetry: false),
    InvalidInputFailure() => (title: 'Not accepted', next: failure.message, canRetry: false),
    UnexpectedFailure() => (
        title: 'That did not load',
        next: 'Something unexpected happened on the way. Try again.',
        canRetry: true,
      ),
  };
}

/// What an empty answer from a Super Admin read actually means.
///
/// WHY THIS IS A FOUR-VALUED TYPE AND NOT A BOOLEAN. rpc_sa_dashboard and rpc_sa_hostels both
/// end in `where app.is_super_admin()`, so a refusal arrives as ZERO ROWS rather than as a 403.
/// A single empty result therefore cannot tell "not permitted" from "nothing on the platform" —
/// the console decides by corroborating with a second read, the dashboard, and that second read
/// is itself a read: it can be in flight, and it can fail.
///
/// THE BUG THIS TYPE EXISTS TO MAKE UNWRITEABLE was
///
///     emptyIsRefusal: stats.value == null && !stats.isLoading
///
/// which is equally true of a dashboard that FAILED and one that was refused. A platform admin
/// whose connection dropped for one request was told they are not allowed to see their own
/// platform — wrong, and alarming in a way "we could not reach the server" is not.
enum SaEmptyVerdict {
  /// The corroborating read has not answered yet, so nothing can be concluded and nothing is
  /// claimed. Drawn as the loading state it is.
  pending,

  /// The corroborating read failed for a reason that says nothing either way — no signal, a
  /// timeout, a 5xx. Refused and genuinely-empty cannot be told apart from here, and picking
  /// either would be a claim about the platform, or about this account, that nothing on the
  /// device supports. Drawn as [SaUnverified], which offers the only thing that can settle it.
  unverified,

  /// The corroborating read came back with nothing, or refused outright: this account is not
  /// the Super Admin. Drawn as [SaNotPermitted].
  refused,

  /// THE CORROBORATING READ DIED WITH THE TOKEN. Added 2026-09-01, and it is the fifth value
  /// because the four above have no honest home for it:
  ///
  ///   · [refused] would repeat the original bug one layer up — the account is not the problem;
  ///   · [unverified] says "we could not check, check again", and Check again cannot work,
  ///     which makes it a dead end wearing a recovery — precisely what SaUnverified's own
  ///     documentation forbids;
  ///   · [confirmed] would draw an empty platform for the person paid to notice one.
  ///
  /// Drawn as [SaSessionEnded], which carries the one control that does work.
  credentialDead,

  /// The corroborating read returned real figures, so this account can see platform data and
  /// the emptiness in front of it is the truth. Only here may an empty state be drawn.
  confirmed,
}

/// Reads the verdict off the corroborating provider — `saStatsProvider` at every call site.
///
/// A VALUE BEATS A FAILED REFRESH. If the dashboard answered once, that answer is still the best
/// evidence about who this account is; a refresh that timed out afterwards has not changed it,
/// and demoting a known answer to "we cannot tell" on every dropped packet would make the
/// console flicker between two explanations of the same screen.
///
/// ═══ A FAILED CORROBORATION IS NOT ONE THING ═══
/// It used to be: every error became [SaEmptyVerdict.unverified], "we could not check — check
/// again". Two of the errors that reach here cannot be answered by checking again.
///
/// A read that came back 42501 HAS told us who this account is; the console can say so, and
/// saying "we cannot tell" instead is a different lie from the one this file was written to
/// kill but a lie all the same. And a read that failed because the sign-in expired has told us
/// about the TOKEN and nothing about the account — Check again will fail identically for as
/// long as the token stays dead, so offering it is the unreachable button the empty-state rules
/// exist to forbid.
SaEmptyVerdict saEmptyVerdict(AsyncValue<Object?> corroborating) {
  if (corroborating.hasValue) {
    return corroborating.value == null ? SaEmptyVerdict.refused : SaEmptyVerdict.confirmed;
  }
  if (corroborating.hasError) {
    final failure = AppFailure.from(corroborating.error!);
    if (failure.needsSignIn) return SaEmptyVerdict.credentialDead;
    // Deliberately AccessDeniedFailure and not `isRefusal`: a ReadOnlyFailure is about a
    // hostel's subscription, which says nothing about whether this account may read the
    // platform, and rounding it up to "not permitted" would invent a verdict again.
    if (failure is AccessDeniedFailure) return SaEmptyVerdict.refused;
    return SaEmptyVerdict.unverified;
  }
  return SaEmptyVerdict.pending;
}

/// Nothing came back, and the read that would have said why did not come back either.
///
/// Says only what is known. The two explanations it is caught between — an empty platform and a
/// refused account — lead to opposite actions, so naming one of them at random is worse than
/// naming neither, and drawing this as an empty list is naming one of them at random.
///
/// The retry is not decoration: [onRetry] re-runs the corroborating read together with the list,
/// which is the only thing that can turn this state into an answer.
class SaUnverified extends StatelessWidget {
  const SaUnverified({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
    this.action,
  });

  final String title;
  final String message;

  /// Required, deliberately. This state exists because a read can be repeated; a panel that says
  /// "we could not check" and offers no way to check is a dead end wearing an explanation.
  final VoidCallback onRetry;

  /// A second way out where one exists — clearing the filters, when filters are on.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final tone = tones.info;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: tones.chipBorder(tone)),
        color: tones.chipFill(tone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded, size: IconSize.md, color: tone),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(title, style: t.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(message, style: t.textTheme.bodySmall),
          const SizedBox(height: Space.sm),
          // Wrap rather than Row: two buttons and a 360dp phone is the case where a Row overflows
          // and the recovery the panel is built around goes off the edge of the screen.
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: IconSize.sm),
                label: const Text('Check again'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              ),
              ?action,
            ],
          ),
        ],
      ),
    );
  }
}

/// The one state that is neither loading, empty nor broken: the RPC answered, with nothing,
/// because the caller is not the Super Admin.
///
/// rpc_sa_dashboard and rpc_sa_hostels both end in `where app.is_super_admin()`, so they return
/// ZERO ROWS rather than a 403. Drawing that as "no hostels on the platform" would be a lie to
/// the one person who could tell it was one.
class SaNotPermitted extends StatelessWidget {
  const SaNotPermitted({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: context.tones.chipBorder(context.tones.warning)),
        color: context.tones.chipFill(context.tones.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: IconSize.md, color: context.tones.warning),
              const SizedBox(width: Space.xs),
              Expanded(child: Text('Platform data withheld', style: t.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            'The server returned no platform figures for this account. That is what it does '
            'for anyone who is not the Super Admin — it is not a sign that the platform is '
            'empty. Sign in with the Super Admin account.',
            style: t.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// THE PANEL [SaNotPermitted] WAS BEING SHOWN INSTEAD OF.
///
/// Same shape, opposite subject. [SaNotPermitted] is about the reader: the server looked at who
/// you are and declined. This one is about the credential: the server was never asked on your
/// behalf at all, because the token this app was holding had run out and could not be renewed.
/// The platform is fine, the account is fine, and one tap fixes it.
///
/// Drawn in the INFO tone, not the warning tone [SaNotPermitted] wears. A dead sign-in is
/// ordinary — this instance produces one most days — and painting it as a security event is how
/// a routine expiry gets escalated into an account audit, which is exactly what happened.
class SaSessionEnded extends StatelessWidget {
  const SaSessionEnded({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final tone = tones.info;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: tones.chipBorder(tone)),
        color: tones.chipFill(tone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: IconSize.md, color: tone),
              const SizedBox(width: Space.xs),
              Expanded(child: Text('Your sign-in expired', style: t.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xxs),
          Text(
            'This console could not ask the server on your behalf, so nothing here is a '
            'statement about the platform or about your account. Sign in again to carry on.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          const Align(
            alignment: Alignment.centerLeft,
            child: SignInAgainButton(outlined: true),
          ),
        ],
      ),
    );
  }
}

/// A row that opens something. The whole row is the target, at the 48dp minimum.
class SaTapCard extends StatelessWidget {
  const SaTapCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      FlatSurface(onTap: onTap, padding: padding, child: child);
}

/// Copies one value and says so. Used for the owner's email and phone here, and for the
/// temporary password in the credentials dialog.
///
/// SAYS "COPIED" RATHER THAN ANIMATING SILENTLY. On the password dialog this is the difference
/// between an admin who knows the value is on their clipboard and one who taps Done on a
/// credential that is gone forever.
class SaCopyButton extends StatefulWidget {
  const SaCopyButton({super.key, required this.text, required this.label, this.expanded = false});

  final String text;

  /// What was copied, for the confirmation and for screen readers: "phone number", "password".
  final String label;

  /// A full-width labelled button rather than a bare icon.
  final bool expanded;

  @override
  State<SaCopyButton> createState() => _SaCopyButtonState();
}

class _SaCopyButtonState extends State<SaCopyButton> {
  bool _copied = false;

  /// THE FAILURE IS SAID OUT LOUD. `Clipboard.setData` goes over a MethodChannel and can
  /// throw — a platform that refuses the clipboard, a channel that is not up yet. Unhandled,
  /// the tick never appeared and nothing else did either: the one-time password this button
  /// exists for was "copied" as far as the person could tell, and was gone by the time they
  /// found out otherwise.
  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('This device would not take the ${widget.label} — it is still on '
              'screen above, so it can be written down.'),
          behavior: SnackBarBehavior.floating,
          duration: Motion.readMessage,
        ));
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    // Long enough to be read, short enough that a second copy is obviously a second copy.
    await Future<void>.delayed(Motion.confirmed);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final icon = _copied ? Icons.check_rounded : Icons.copy_rounded;
    if (widget.expanded) {
      return OutlinedButton.icon(
        onPressed: _copy,
        icon: Icon(icon, size: IconSize.sm),
        label: Text(_copied ? 'Copied' : 'Copy ${widget.label}'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      );
    }
    return IconButton(
      onPressed: _copy,
      tooltip: _copied ? 'Copied' : 'Copy ${widget.label}',
      icon: Icon(icon, size: IconSize.md),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE DASHBOARD'S OWN SHAPES — screen-dashboard, node 4:125
// ─────────────────────────────────────────────────────────────────────────────

/// One KPI tile — 4:142, and the three beside it.
///
/// `bg-[#111417] border border-[#292e33] rounded-[10px] p-[12px] gap-[4px]`, a 10px uppercase
/// label in the tertiary ink, then the figure at 16/700 in cream. Two of these to a row, 8dp
/// apart; two rows.
///
/// ── WHAT IS NOT COPIED, AND WHY ──────────────────────────────────────────────────────────
///
/// Every tile in the mockup carries a THIRD line — `↑ 12%`, `↑ 8%`, `— 0%`, `↑ 4%`. There is no
/// such number anywhere in this system. `rpc_sa_dashboard` returns seven scalars for RIGHT NOW
/// and keeps no history of itself, so a month-over-month delta on revenue, owners or residents
/// could only be invented. Drawing a green `↑ 12%` under a real figure would make the one part
/// of the tile that is fiction look exactly as authoritative as the part that is not. The line
/// is therefore omitted from all four tiles rather than from some of them, and the tiles are
/// two lines tall.
///
/// The corner radius is [Radii.card] rather than the mockup's literal 10px: 10 is not a step on
/// this project's scale (4 · 8 · 12 · 14), and inventing a fifth step for one widget is what
/// tokens exist to prevent. 12 is the neighbouring step and the one every other card already
/// uses, so the tiles line up with the panels beneath them.
class SaKpiTile extends StatelessWidget {
  const SaKpiTile({
    super.key,
    required this.label,
    required this.value,
    this.semantics,
    this.tone,
    this.onTap,
  });

  final String label;

  /// Already formatted for display by one of the formatters at the top of this file.
  final String value;

  /// What a screen reader should hear instead of `label: value` — used where the tile shows a
  /// rounded figure and the exact one is worth speaking.
  final String? semantics;

  /// Canonical or resolved. Null leaves the figure in the cream, which is the mockup's default
  /// and the right answer for a count that is neither good nor bad news.
  final Color? tone;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);

    return Semantics(
      label: semantics ?? '$label: $value',
      excludeSemantics: true,
      button: onTap != null,
      child: FlatSurface(
        onTap: onTap,
        padding: const EdgeInsets.all(Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: t.textTheme.labelSmall,
              // Two lines, because the honest label for the money tile is "SUBSCRIPTION
              // REVENUE" and the mockup's one-word "REVENUE" would be read on a platform
              // console as rent collected across every hostel — a number ten times larger
              // that this screen does not show. The row equalises its two tiles' heights, so
              // a second line here costs nothing but height.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Space.xxs),
            Text(
              value,
              // headlineSmall is 16/24/700 with tabular figures — the mockup's KPI size, and
              // the tabular variant so four tiles' digits sit on the same rhythm.
              style: t.textTheme.headlineSmall?.copyWith(color: accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// One band of [SaSegmentBar], and one line of its legend.
@immutable
class SaSegment {
  const SaSegment({
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
  });

  final String label;

  /// The count. Zero draws no band at all — a hairline sliver of colour standing for nothing
  /// is a rendering artefact that reads as "a few".
  final int value;

  /// Canonical, resolved at the paint site.
  final Color tone;

  final VoidCallback? onTap;
}

/// The design's subscription-health bar — 4:162, with the legend at 4:166.
///
/// `h-[8px] rounded-[4px] overflow-clip` with one flush band per state, then a row of 6dp dots
/// and `Active (380)`-style labels at 11/400. It replaces three stacked progress meters: the
/// mockup's point is that the three states are PARTS OF ONE WHOLE, and three separate tracks
/// say the opposite — each one looks like its own ratio out of everything.
///
/// THE DENOMINATOR IS THE SUM OF THE BANDS, which the bar gets for free by laying them out with
/// flex factors. It is never `totalHostels`: `app.subscription_state()` classifies exactly one
/// state per hostel that has a subscription, so a hostel that was never sold one is outside all
/// three counts, and dividing by the platform total would draw three bands that mysteriously
/// fail to fill the track.
class SaSegmentBar extends StatelessWidget {
  const SaSegmentBar({super.key, required this.segments});

  final List<SaSegment> segments;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final total = segments.fold<int>(0, (sum, s) => sum + s.value);
    final drawn = segments.where((s) => s.value > 0).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: Radii.rTiny,
          child: SizedBox(
            height: Space.xs,
            child: drawn.isEmpty
                ? ColoredBox(color: t.colorScheme.outlineVariant)
                : Row(
                    children: [
                      for (final segment in drawn)
                        Expanded(
                          flex: segment.value,
                          child: ColoredBox(color: context.tones.resolve(segment.tone)),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            for (final segment in segments)
              Flexible(child: _SaLegendItem(segment: segment, of: total)),
          ],
        ),
      ],
    );
  }
}

class _SaLegendItem extends StatelessWidget {
  const _SaLegendItem({required this.segment, required this.of});

  final SaSegment segment;
  final int of;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = context.tones.resolve(segment.tone);

    return Semantics(
      button: segment.onTap != null,
      label: '${segment.label}: ${plural(segment.value, 'hostel')} of ${count(of)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: segment.onTap,
        borderRadius: Radii.rTiny,
        // The mockup's legend is a bare 11px line. A line is not a tap target, and each of
        // these opens the list its number was counting, so the row is padded out to something
        // a thumb can hit.
        child: Container(
          constraints: const BoxConstraints(minHeight: Space.huge),
          padding: const EdgeInsets.symmetric(vertical: Space.xs, horizontal: Space.xxs),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: Space.xxs + 2,
                height: Space.xxs + 2,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              const SizedBox(width: Space.xxs),
              Flexible(
                child: Text(
                  '${segment.label} (${count(segment.value)})',
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One bar of [SaBarChart].
@immutable
class SaBar {
  const SaBar({required this.label, required this.value, required this.caption});

  /// The short axis label — 'Aug'.
  final String label;
  final int value;

  /// The long form, spoken rather than drawn: 'August 2026: 3 hostels'.
  final String caption;
}

/// The design's growth chart — 4:181.
///
/// Bars are `rounded-[4px]`; every one except the newest is `bg-[#171a1e]` with a `#292e33`
/// hairline, and the newest is the gold at 80%. The month under the newest bar is cream while
/// the rest are the tertiary ink. That is the whole chart: the outline gives a quiet month a
/// visible extent, so twelve months read as twelve months rather than as a gap something
/// failed to draw, and exactly one bar is allowed to be the answer.
///
/// TWELVE BARS, NOT THE MOCKUP'S SIX. `rpc_sa_onboarding_series` generates twelve months and
/// zero-fills them server-side; showing six would throw away half of what the server counted,
/// and a chart that quietly drops the first half of its own series is worse than a slightly
/// narrower bar.
class SaBarChart extends StatelessWidget {
  const SaBarChart({super.key, required this.bars, this.plotHeight = 56});

  final List<SaBar> bars;
  final double plotHeight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final peak = bars.fold<int>(0, (m, b) => b.value > m ? b.value : m);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, bar) in bars.indexed)
          Expanded(
            child: _SaBarColumn(
              bar: bar,
              fraction: peak == 0 ? 0 : bar.value / peak,
              newest: i == bars.length - 1,
              plotHeight: plotHeight,
              labelStyle: t.textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}

class _SaBarColumn extends StatelessWidget {
  const _SaBarColumn({
    required this.bar,
    required this.fraction,
    required this.newest,
    required this.plotHeight,
    required this.labelStyle,
  });

  final SaBar bar;
  final double fraction;
  final bool newest;
  final double plotHeight;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Semantics(
      label: bar.caption,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bar.value == 0 ? '' : count(bar.value), style: labelStyle, maxLines: 1),
            const SizedBox(height: Space.xxs),
            // Flexible, because the column's height budget also has to fit two labels whose
            // heights are the font's business, not ours. At full plotHeight the peak month's
            // bar could exceed what is left and paint an overflow stripe across the chart; a
            // loose fit lets that one bar give up the couple of pixels instead.
            Flexible(
              child: Container(
                height: (plotHeight * fraction).clamp(Space.xxs, plotHeight),
                decoration: BoxDecoration(
                  // The mockup softens the gold to `opacity-80` here. Full strength is used
                  // instead: 0.8 is not a step in this project's opacity scale, and adding one
                  // for a single bar buys nothing the hairline-outlined neighbours do not
                  // already do — the difference between "the newest month" and "every other
                  // month" is fill versus outline, not eight percent of alpha.
                  color: newest
                      ? t.colorScheme.primary
                      : t.colorScheme.surfaceContainer,
                  borderRadius: Radii.rTiny,
                  border: newest
                      ? null
                      : Border.all(
                          color: t.colorScheme.outlineVariant,
                          width: Strokes.hairline,
                        ),
                ),
              ),
            ),
            const SizedBox(height: Space.xxs),
            Text(
              bar.label,
              style: newest ? labelStyle?.copyWith(color: t.colorScheme.onSurface) : labelStyle,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ],
        ),
      ),
    );
  }
}

/// The last row of a paginated console list: still loading, failed, or the honest total.
///
/// IT EXISTS BECAUSE THE SPINNER USED TO BE UNCONDITIONAL. Both paginated tabs asked for the
/// next page from a scroll listener with `unawaited(...loadMore())` and drew a turning circle
/// whenever `hasMore` was true. `PagedNotifier.loadMore` RETURNS its failure rather than
/// throwing — that is its whole contract — so a page that did not load threw the reason away
/// and left a spinner turning under the rows for ever. A platform admin on a hotel Wi-Fi saw a
/// list that was still loading and never would be, with nothing to tap and nothing to read.
///
/// The count is a claim about the LIST, never about the platform: "20 hostels shown" is true
/// whether or not page three exists, where "20 hostels" would not be.
class SaLoadMoreFooter extends StatelessWidget {
  const SaLoadMoreFooter({
    super.key,
    required this.hasMore,
    required this.shown,
    required this.noun,
    this.error,
    this.onRetry,
  });

  final bool hasMore;
  final int shown;
  final String noun;

  /// Non-null when the last attempt at the next page failed.
  final AppFailure? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final failure = error;

    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: Column(
          children: [
            Text(
              failure.message,
              style: t.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xs),
            TextButton(onPressed: onRetry, child: const Text('Load more')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: Center(
        child: hasMore
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text('${plural(shown, noun)} shown', style: t.textTheme.bodySmall),
      ),
    );
  }
}
