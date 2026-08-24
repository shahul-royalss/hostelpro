library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';

/// The pieces every warden screen is built from.
///
/// WHY THIS FILE EXISTS. Five screens that each invent their own row height, their own "no rows
/// yet" sentence and their own idea of what red means do not read as one product, and the
/// differences are invisible to the analyzer. Putting them here means a warden learns the
/// interface once: a pill is always a status, a red pill always means somebody has to do
/// something, and every list fails and empties the same way.
///
/// It holds no state and talks to no repository — it is presentation and formatting only.

// ─────────────────────────────────────────────────────────────────────────────
// FORMATTING
// ─────────────────────────────────────────────────────────────────────────────

/// Rupees, grouped the Indian way (₹1,50,000 — not ₹150,000).
///
/// No paise. Rent is quoted in whole rupees and a corridor is not the place to read decimals;
/// the exact figure is still in the database and on the receipt.
final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String money(num amount) => _money.format(amount);

final _dayMonth = DateFormat('d MMM');
final _dayMonthYear = DateFormat('d MMM yyyy');
final _clock = DateFormat('h:mm a');

String shortDate(DateTime d) {
  final local = d.toLocal();
  return local.year == DateTime.now().year ? _dayMonth.format(local) : _dayMonthYear.format(local);
}

String timeOfDay(DateTime d) => _clock.format(d.toLocal());

/// "just now" / "3h" / "2d" / "5 Aug". How old a complaint is matters more than when it landed.
String age(DateTime from) {
  final elapsed = DateTime.now().difference(from.toLocal());
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return shortDate(from);
}

/// 'YYYY-MM' as a person reads it. Parsed rather than assumed: an unrecognised string is
/// returned untouched instead of throwing on a screen that only wanted a heading.
String monthLabel(String periodMonth) {
  final parts = periodMonth.split('-');
  if (parts.length != 2) return periodMonth;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null || month < 1 || month > 12) return periodMonth;
  return DateFormat('MMMM yyyy').format(DateTime(year, month));
}

/// One or two letters for an avatar. Never more — three initials in a circle is unreadable at
/// the size a list row allows.
String initials(String fullName) {
  final words = fullName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.characters.first.toUpperCase();
  return (words.first.characters.first + words.last.characters.first).toUpperCase();
}

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC COLOUR
// ─────────────────────────────────────────────────────────────────────────────

/// What a colour MEANS on a warden screen, so no screen has to decide for itself.
///
/// The rule: red is not "bad", it is "you have to do something". An unpaid fee and an open
/// complaint are red because they are work; a checked-out resident is grey because they are
/// simply not here any more.
Color toneFor(BuildContext context, WireValue status) {
  final t = Theme.of(context);
  return switch (status) {
    FeeStatus.paid => NivoraColors.success,
    FeeStatus.partial => NivoraColors.warning,
    FeeStatus.unpaid => NivoraColors.error,
    ComplaintStatus.open => NivoraColors.error,
    ComplaintStatus.inProgress => NivoraColors.warning,
    ComplaintStatus.resolved => NivoraColors.success,
    StudentStatus.active => NivoraColors.success,
    StudentStatus.onLeave => NivoraColors.warning,
    StudentStatus.vacated => t.colorScheme.onSurfaceVariant,
    BedStatus.free => NivoraColors.success,
    BedStatus.occupied => t.colorScheme.primary,
    SubscriptionState.active => NivoraColors.success,
    SubscriptionState.expiring => NivoraColors.warning,
    SubscriptionState.expired => NivoraColors.error,
    _ => t.colorScheme.primary,
  };
}

/// A status, said once, the same way everywhere.
///
/// Takes the enum rather than a string so the wording comes from [WireValue.label] — the same
/// text the web app shows for the same row — and the colour from [toneFor]. The `.text` variant
/// is for the handful of states that are not a database enum ("No bed", "3 free").
class StatusPill extends StatelessWidget {
  // A named parameter cannot be private, so the enum cannot arrive as an initializing formal
  // for `_status`; it has to be copied across in the initialiser list.
  const StatusPill({super.key, required WireValue status, this.dense = false})
      : _status = status, // ignore: prefer_initializing_formals
        label = null,
        tone = null;

  const StatusPill.text({
    super.key,
    required this.label,
    required this.tone,
    this.dense = false,
  }) : _status = null;

  final WireValue? _status;
  final String? label;
  final Color? tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = _status;
    final accent = tone ?? toneFor(context, status!);
    final text = label ?? status!.label;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Space.xs : Space.sm,
        vertical: dense ? 2 : Space.xxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Text(
        text,
        style: t.textTheme.labelSmall?.copyWith(color: accent, letterSpacing: 0.2),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

/// A warden screen: glass header, then content.
///
/// The header is a bar content scrolls beneath, not an AppBar — see GlassHeader, which also
/// owns the status-bar inset so no screen re-derives it.
class WardenScreen extends StatelessWidget {
  const WardenScreen({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        GlassHeader(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.textTheme.titleLarge,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(subtitle!, style: t.textTheme.bodySmall,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// A heading over a group of rows.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xxs, Space.lg, Space.xxs, Space.xs),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: t.textTheme.labelSmall)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Nothing to show — said in words that tell the warden whether that is good news.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.detail});
  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(height: Space.sm),
          Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
          if (detail != null) ...[
            const SizedBox(height: Space.xxs),
            Text(detail!, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// A failed load, told in the database's own words where it had any.
///
/// [AppFailure] already distinguishes "no signal" from "you are not allowed" from "the
/// subscription lapsed"; the retry button appears only where retrying could actually work,
/// because a button that cannot help is worse than no button.
class FailureState extends StatelessWidget {
  const FailureState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final failure = AppFailure.from(error);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            failure is OfflineFailure
                ? Icons.wifi_off_rounded
                : failure is AccessDeniedFailure
                    ? Icons.lock_outline_rounded
                    : Icons.error_outline_rounded,
            size: 32,
            color: NivoraColors.error,
          ),
          const SizedBox(height: Space.sm),
          Text(failure.message, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
          if (onRetry != null && failure.isRetryable) ...[
            const SizedBox(height: Space.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

/// An [AsyncValue] rendered with one loading, one failure and one empty treatment.
///
/// While a refresh is in flight the PREVIOUS data stays on screen. A warden mid-sentence with a
/// resident should not lose the row they are reading because the list refreshed underneath
/// them, so `hasValue` wins over `isLoading`.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) return FailureState(error: value.error!, onRetry: onRetry);
    return loading ?? const _Spinner();
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xxl),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLS
// ─────────────────────────────────────────────────────────────────────────────

/// One of the four things a warden does most, as a target you can hit without looking.
///
/// 88dp tall and a whole card wide at two per row: comfortably past the 48dp minimum, because
/// the person tapping it is standing up, holding a phone in one hand and talking to somebody.
class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tone;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = enabled ? (tone ?? t.colorScheme.primary) : t.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: t.colorScheme.surface,
        borderRadius: Radii.rCard,
        child: InkWell(
          borderRadius: Radii.rCard,
          onTap: enabled ? onTap : null,
          child: Container(
            height: 88,
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              borderRadius: Radii.rCard,
              border: Border.all(color: t.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.xs),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: Radii.rControl,
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                Text(
                  label,
                  style: t.textTheme.titleSmall?.copyWith(
                    color: enabled ? null : t.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A list row sized for a thumb: 64dp minimum, the whole width tappable.
class TapRow extends StatelessWidget {
  const TapRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final row = Material(
      color: t.colorScheme.surface,
      borderRadius: Radii.rCard,
      child: InkWell(
        borderRadius: Radii.rCard,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: Radii.rCard,
            border: Border.all(color: t.colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
    return semanticLabel == null
        ? row
        : Semantics(label: semanticLabel, button: onTap != null, container: true, child: row);
  }
}

/// Initials in a circle. No photo: students.photo_url is a private storage KEY, not a URL, and
/// showing a broken image is worse than showing none.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.tone, this.size = 40});
  final String name;
  final Color? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone ?? t.colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials(name),
        style: t.textTheme.titleSmall?.copyWith(color: accent),
      ),
    );
  }
}

/// A label above a value, for the detail sheets.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.sm),
          ],
          SizedBox(
            width: 108,
            child: Text(label, style: t.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: t.textTheme.bodyMedium?.copyWith(
            color: t.colorScheme.onSurface,
          ))),
        ],
      ),
    );
  }
}

/// The title bar of a bottom sheet: a drag handle, a name, and a way out.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: Space.md),
          decoration: BoxDecoration(
            color: t.colorScheme.outline,
            borderRadius: const BorderRadius.all(Radius.circular(2)),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.textTheme.titleLarge,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(subtitle!, style: t.textTheme.bodySmall,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIONS
// ─────────────────────────────────────────────────────────────────────────────

/// Runs a write and reports the outcome in one place.
///
/// EVERY WRITE ON A WARDEN SCREEN GOES THROUGH HERE, for one reason: the database says useful
/// things when it refuses, and each of those sentences was written for the person at the desk —
/// "Bed 3 is already occupied. Choose a free bed.", "That student has been checked out",
/// "Subscription expired — hostel is read-only." [AppFailure] has already turned the SQLSTATE
/// into the right one; throwing that away for "something went wrong" is how staff learn to stop
/// reading error messages.
///
/// Returns true when the write succeeded.
Future<bool> runAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (!context.mounted) return true;
    messenger.showSnackBar(SnackBar(
      content: Text(success),
      behavior: SnackBarBehavior.floating,
    ));
    return true;
  } catch (error) {
    final failure = AppFailure.from(error);
    if (!context.mounted) return false;
    messenger.showSnackBar(SnackBar(
      content: Text(failure.message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: NivoraColors.error,
      duration: const Duration(seconds: 5),
    ));
    return false;
  }
}
