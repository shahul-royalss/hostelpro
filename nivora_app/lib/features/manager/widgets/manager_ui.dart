library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';

/// The pieces every manager screen is built from.
///
/// WHY THIS FILE EXISTS. Four screens that each invent their own row height, their own "nothing
/// here yet" sentence and their own idea of what amber means do not read as one product, and
/// none of those differences are visible to the analyzer. Putting them here means a manager
/// learns the interface once: a pill is always a state, a red pill always means somebody has to
/// do something, and every list fails and empties the same way.
///
/// It holds no state and talks to no repository — presentation and formatting only. Each role
/// in this app keeps its own copy of this layer (owner_format.dart, warden_ui.dart,
/// student/widgets) so one role's screens can be restyled without touching another's.

// ─────────────────────────────────────────────────────────────────────────────
// FORMATTING
// ─────────────────────────────────────────────────────────────────────────────

/// Rupees, grouped the Indian way — 1,50,000 rather than 150,000.
///
/// The default `#,###` pattern renders twelve lakh as `1,200,000`; an Indian manager reads that
/// shape as `12,00,000` and is out by a factor of ten on their own month.
final NumberFormat _rupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final NumberFormat _rupeesPaise =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Money to the rupee. For summaries, where the reader wants a magnitude.
String money(num amount) => _rupees.format(amount);

/// Money exactly as the column holds it. For a LEDGER ROW, where the reader is checking a
/// figure against a receipt.
///
/// public.expenses.amount is numeric(12,2), so paise are real and roundable away. This shows
/// them only when they are not zero: ₹1,250 stays ₹1,250, and ₹1,250.75 does not quietly
/// become ₹1,251 on the one screen where that matters.
String moneyExact(num amount) {
  final rounded = (amount * 100).round();
  return rounded % 100 == 0 ? _rupees.format(amount) : _rupeesPaise.format(amount);
}

/// Money at bar-label size. Indian units — k, L (lakh), Cr (crore) — because a manager reads
/// "₹1.2L" instantly and has to convert "₹120.0K".
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

final DateFormat _dayMonth = DateFormat('d MMM');
final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');
final DateFormat _monthYear = DateFormat('MMMM yyyy');

/// '24 Aug', or '24 Aug 2025' once the year stops being obvious.
String shortDate(DateTime d) {
  final local = d.toLocal();
  return local.year == DateTime.now().year ? _dayMonth.format(local) : _dayMonthYear.format(local);
}

/// The heading over a month's figures: 'August 2026'.
String monthTitle(DateTime d) => _monthYear.format(d);

/// A due date said the way somebody plans their day.
///
/// [now] is injectable so this is testable without waiting for the clock. Everything is
/// compared on the LOCAL CALENDAR DAY, not on elapsed hours: a job due at some point today is
/// "Due today" at 9am and at 9pm, and one due tomorrow never reads as "in 14 hours".
String dueLabel(DateTime due, {DateTime? now}) {
  final today = _startOfDay(now ?? DateTime.now());
  final day = _startOfDay(due);
  final gap = day.difference(today).inDays;
  if (gap == 0) return 'Due today';
  if (gap == 1) return 'Due tomorrow';
  if (gap == -1) return '1 day late';
  if (gap < -1) return '${-gap} days late';
  if (gap <= 6) return 'Due ${DateFormat('EEEE').format(day)}';
  return 'Due ${shortDate(day)}';
}

DateTime _startOfDay(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// '1 job' / '4 jobs'. Kept here so no screen invents its own pluralisation.
String plural(int count, String one, String many) => '$count ${count == 1 ? one : many}';

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC COLOUR
// ─────────────────────────────────────────────────────────────────────────────

/// What a colour MEANS on a manager screen, so no screen has to decide for itself.
///
/// The rule matches the rest of the app: red is not "bad", it is "you have to do something".
/// A late job is red because it is work; a finished one is green because it is not.
///
/// Returns a CANONICAL token ([NivoraColors.success] and friends). The paint site resolves it
/// to this theme's legible value through `context.tones` — see NivoraSemantics.resolve.
Color toneFor(BuildContext context, WireValue status) {
  final t = Theme.of(context);
  return switch (status) {
    TaskStatus.pending => NivoraColors.warning,
    TaskStatus.inProgress => NivoraColors.info,
    TaskStatus.done => NivoraColors.success,
    _ => t.colorScheme.primary,
  };
}

/// A state, said once, the same way everywhere.
///
/// Takes the enum rather than a string so the wording comes from [WireValue.label] — the same
/// text the web app shows for the same row. The `.text` variant is for the few states that are
/// not a database enum ("2 days late", "Not planned").
///
/// The fill and border alphas come from NivoraSemantics, which is where they were measured:
/// 11px type on a tint of its own ink is the tightest contrast case in this app, and a chip
/// drawn at a plausible-looking alpha fails it.
class Pill extends StatelessWidget {
  const Pill({super.key, required WireValue status})
      : _status = status, // ignore: prefer_initializing_formals
        label = null,
        tone = null;

  const Pill.text({super.key, required this.label, required this.tone}) : _status = null;

  final WireValue? _status;
  final String? label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final canonical = tone ?? toneFor(context, _status!);
    final ink = tones.resolve(canonical);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 2),
      decoration: BoxDecoration(
        color: tones.chipFill(canonical),
        border: Border.all(color: tones.chipBorder(canonical), width: Strokes.hairline),
        // rControl, not a hardcoded 999 and not Radii.rPill. tokens.dart reserves the pill
        // radius for things that are genuinely capsule-shaped and can never take a second
        // line; a status pill takes [Radii.control], which is also what warden_ui's twin uses.
        borderRadius: Radii.rControl,
      ),
      child: Text(
        label ?? _status!.label,
        style: t.textTheme.labelSmall?.copyWith(color: ink, letterSpacing: 0.2),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

/// A manager screen: glass header, then content.
///
/// The header is a bar content scrolls beneath, not an AppBar — see GlassHeader, which also
/// owns the status-bar inset so no screen re-derives it. It is also the ONLY glass on the
/// screen: GlassSurface asserts when panes nest, and everything below is FlatSurface.
class ManagerScreen extends StatelessWidget {
  const ManagerScreen({
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
                    Text(title,
                        style: t.textTheme.titleLarge,
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

/// Nothing to show — said in words that tell the manager whether that is good news.
class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.icon, required this.title, this.detail});
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
          Icon(icon, size: IconSize.xl, color: t.colorScheme.onSurfaceVariant),
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
class FailureNote extends StatelessWidget {
  const FailureNote({super.key, required this.error, this.onRetry});
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
            size: IconSize.xl,
            color: context.tones.error,
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
/// While a refresh is in flight the PREVIOUS data stays on screen: `hasValue` is checked before
/// `isLoading`. This also sidesteps a Riverpod 3 behaviour that would otherwise delete every
/// error state in the app — a failed provider is retried with backoff, and while that retry is
/// pending the state is AsyncLoading carrying the previous error, so `.when()` with its default
/// flags takes the loading branch and the error is never drawn.
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
    if (value.hasError) return FailureNote(error: value.error!, onRetry: onRetry);
    return loading ?? const Spinner();
  }
}

/// The one spinner. Never full-screen where a layout could be kept instead.
class Spinner extends StatelessWidget {
  const Spinner({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.xxl),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
}

/// A short, coloured strip at the top of a screen. One geometry for every kind of notice, so
/// "we are checking", "here is a warning" and "we could not check" occupy the same space and
/// differ only in the two things that carry the meaning: the colour and the words.
///
/// [tone] is a CANONICAL token ([NivoraColors.warning] and friends); it is resolved here.
class NoticeStrip extends StatelessWidget {
  const NoticeStrip({
    super.key,
    required this.icon,
    required this.title,
    required this.tone,
    this.detail,
    this.action,
    this.actionLabel,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// Canonical, not resolved. See NivoraSemantics.resolve.
  final Color tone;

  /// Drawn only when there is something a retry could actually change.
  final VoidCallback? action;
  final String? actionLabel;

  /// Replaces the icon with a spinner, for the "we do not know yet" face.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ink = context.tones.resolve(tone);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.tones.chipFill(tone),
        border: Border.all(color: context.tones.chipBorder(tone), width: Strokes.hairline),
        borderRadius: Radii.rCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          busy
              ? SizedBox(
                  width: IconSize.md,
                  height: IconSize.md,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                )
              : Icon(icon, size: IconSize.md, color: ink),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.titleSmall?.copyWith(color: ink)),
                if (detail != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(detail!, style: t.textTheme.bodySmall),
                ],
                if (action != null) ...[
                  const SizedBox(height: Space.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: action,
                      child: Text(actionLabel ?? 'Try again'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The figure a stat tile draws once a read has actually produced one.
///
/// Returned by [AsyncStat.figure] rather than assembled at the call site, so a screen cannot
/// accidentally compute a caption or a tone from data it does not have yet.
class StatFigure {
  const StatFigure({required this.value, this.caption, this.tone});

  /// Already formatted. A dash here means the DATA said nothing, not that it is still coming.
  final String value;
  final String? caption;

  /// Canonical, resolved by GlassStatCard. Null leaves the tile in the neutral accent, which
  /// is the honest choice when the data does not imply a state.
  final Color? tone;
}

/// A stat tile whose figure comes from an [AsyncValue] — with a DIFFERENT FACE PER OUTCOME.
///
/// The bug this class exists to make impossible: `provider.value` is null while a read is in
/// flight AND after it failed, so a tile written as `v == null ? '—' : format(v)` draws the
/// same dash for "still counting" and for "we never got an answer" — and a dash where a number
/// belongs is read as a zero. "No overdue jobs" and "we could not reach the server" lead to
/// opposite actions.
///
/// Four outcomes, four faces:
///   · loading — the tile's own layout with a dash and [loadingCaption], no tone. A tone would
///     claim a state ("None late", in green) that nothing has established yet.
///   · loaded  — whatever [figure] returns, including a dash where the DATA is genuinely absent.
///   · failed  — [_FailedStat]: the failure's own sentence, and a retry only where one can work.
///   · refused — the same, but AppFailure has already classified it, so it says "you do not have
///     access to that" with a padlock and offers no retry.
///
/// `hasValue` is checked before `hasError` for the same reason [AsyncSection] does it: a
/// refresh that fails must not blank a figure that is already on screen.
class AsyncStat<T> extends StatelessWidget {
  const AsyncStat({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.figure,
    this.loadingCaption,
    this.emphasised = false,
    this.onTap,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final String label;
  final IconData icon;
  final StatFigure Function(T data) figure;
  final String? loadingCaption;
  final bool emphasised;
  final VoidCallback? onTap;

  /// Wired to whatever re-reads the provider behind [value]. Omit it where nothing on this
  /// screen can retry — [_FailedStat] then draws no button rather than a dead one.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final f = figure(value.requireValue);
      return GlassStatCard(
        label: label,
        value: f.value,
        caption: f.caption,
        icon: icon,
        tone: f.tone,
        emphasised: emphasised,
        onTap: onTap,
      );
    }
    if (value.hasError) {
      return _FailedStat(label: label, error: value.error!, onRetry: onRetry);
    }
    return GlassStatCard(
      label: label,
      value: '—',
      caption: loadingCaption,
      icon: icon,
      emphasised: emphasised,
      onTap: onTap,
    );
  }
}

/// The face a stat tile wears when its read failed.
///
/// Deliberately NOT a number-shaped tile: no headline figure, no dash in the figure slot. A
/// reader glancing at the row has to be able to tell at that glance that this one is not a
/// measurement. Flat rather than glass even when the tile it replaces was emphasised — the
/// emphasis exists to draw the eye to a figure, and there is no figure.
class _FailedStat extends StatelessWidget {
  const _FailedStat({required this.label, required this.error, this.onRetry});

  final String label;
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final failure = AppFailure.from(error);
    final ink = context.tones.error;
    final canRetry = onRetry != null && failure.isRetryable;

    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      semanticLabel: '$label: not available. ${failure.message}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              failure is OfflineFailure
                  ? Icons.wifi_off_rounded
                  : failure is AccessDeniedFailure
                      ? Icons.lock_outline_rounded
                      : Icons.error_outline_rounded,
              size: IconSize.sm,
              color: ink,
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(label.toUpperCase(),
                  style: t.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: Space.xs),
          Text('Not available', style: t.textTheme.titleSmall?.copyWith(color: ink)),
          const SizedBox(height: Space.xxs),
          Text(failure.message,
              style: t.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          // No button where retrying cannot help: AccessDeniedFailure will refuse again, and a
          // control that does nothing teaches people the controls do nothing.
          if (canRetry) ...[
            const SizedBox(height: Space.xs),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLS
// ─────────────────────────────────────────────────────────────────────────────

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

/// One of the things a manager does most, as a target you can hit without looking.
///
/// 88dp tall and half a card wide: comfortably past the 48dp minimum, because the person
/// tapping it is standing in a kitchen doorway holding a phone in one hand.
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
    final accent = enabled
        ? context.tones.resolve(tone ?? t.colorScheme.primary)
        : t.colorScheme.onSurfaceVariant;
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
                  child: Icon(icon, size: IconSize.md, color: accent),
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
            Icon(icon, size: IconSize.sm, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.sm),
          ],
          SizedBox(width: 112, child: Text(label, style: t.textTheme.bodySmall)),
          Expanded(
            child: Text(
              value,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface),
            ),
          ),
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
                  Text(title,
                      style: t.textTheme.titleLarge,
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
            ?trailing,
          ],
        ),
      ],
    );
  }
}

/// The inside of every manager bottom sheet.
///
/// showGlassSheet already owns the geometry, the barrier and the keyboard inset. This owns the
/// two things it cannot: a HEIGHT CAP, and scrolling. Without the cap a long form grows past
/// the top of the screen and its submit button becomes unreachable — an isScrollControlled
/// sheet is allowed to be taller than the display, and Flutter will let it.
class SheetBody extends StatelessWidget {
  const SheetBody({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.88 - media.padding.top;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: title, subtitle: subtitle, trailing: trailing),
          const SizedBox(height: Space.md),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTIONS
// ─────────────────────────────────────────────────────────────────────────────

/// Runs a write and reports the outcome in one place.
///
/// EVERY WRITE ON A MANAGER SCREEN GOES THROUGH HERE, for one reason: the database says useful
/// things when it refuses, and each of those sentences was written for the person holding the
/// phone — "Managers can only update the task status.", "Subscription expired — hostel is
/// read-only.", "You do not have access to that." [AppFailure] has already turned the SQLSTATE
/// into the right one; replacing it with "something went wrong" is how staff learn to stop
/// reading error messages.
///
/// Returns true when the write succeeded.
Future<bool> runAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColour = context.tones.error;
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
      backgroundColor: errorColour,
      duration: Motion.readMessage,
    ));
    return false;
  }
}
