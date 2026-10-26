library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/brow_header.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/sign_in_again.dart';
import '../../../shared/motion/settle.dart';

/// The pieces every manager screen is built from.
///
/// WHY THIS FILE EXISTS. Four screens that each invent their own row height, their own "nothing
/// here yet" sentence and their own idea of what amber means do not read as one product, and
/// none of those differences are visible to the analyzer. Putting them here means a manager
/// learns the interface once: a tone always means the same thing, a red row always means
/// somebody has to do something, and every list fails and empties the same way.
///
/// It holds no state and talks to no repository — presentation and formatting only. Each role
/// in this app keeps its own copy of this layer (owner_format.dart, warden_ui.dart,
/// student/widgets) so one role's screens can be restyled without touching another's.
///
/// ── THE SHAPES ARE THE CLAY KIT'S ───────────────────────────────────────────────────────
///
/// Forest header, cream ground, flat cards on a hairline, Outfit headings in sentence case and
/// clay art where a picture helps somebody find their place (shared/clay/). Most of what is here
/// is that kit meeting a manager's sentences and a manager's four states: [StatCard] is a clay
/// [StatTile] fed from a [StatFigure], [FailureNote] is an [EmptyState] that knows what an
/// [AppFailure] can and cannot promise, [TaskLine] is a list row with the job's state square
/// in front of it. What this file adds on top is the rule each of them encodes — which is
/// why most of the comments below are about honesty rather than paint.
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
/// Returns a CANONICAL token ([ApnivaasColors.success] and friends). The paint site resolves it
/// to this theme's legible value through `context.tones` — see ApnivaasSemantics.resolve.
Color toneFor(BuildContext context, WireValue status) {
  final t = Theme.of(context);
  return switch (status) {
    TaskStatus.pending => ApnivaasColors.warning,
    TaskStatus.inProgress => ApnivaasColors.info,
    TaskStatus.done => ApnivaasColors.success,
    _ => t.colorScheme.primary,
  };
}

/// A state, said once, the same way everywhere — as the clay [StatusChip].
///
/// Takes the enum rather than a string so the wording comes from [WireValue.label] — the same
/// text the web app shows for the same row. The `.text` variant is for the few states that are
/// not a database enum ("2 days late", "Not planned").
///
/// The chip measures its own fill and ink (ApnivaasSemantics.chipFill and resolve): 12px type on
/// a tint of its own ink is the tightest contrast case in this app, and a chip drawn at a
/// plausible-looking alpha fails it. That is also why a chip never sits on Mist or on the
/// neutral fill — see tokens.dart.
class Pill extends StatelessWidget {
  const Pill({super.key, required WireValue status})
      : _status = status, // ignore: prefer_initializing_formals
        label = null,
        tone = null;

  const Pill.text({super.key, required this.label, required this.tone}) : _status = null;

  final WireValue? _status;
  final String? label;

  /// Canonical, not resolved.
  final Color? tone;

  @override
  Widget build(BuildContext context) => StatusChip(
        label: label ?? _status!.label,
        tone: StatusTone.fromCanonical(tone ?? toneFor(context, _status!)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

/// A manager tab: the forest header, then content.
///
/// The header is the brow every role's screens open with — the forest gradient with its few soft
/// stars and the rounded bottom edge — drawn by [GlassHeader.onBrow], which also owns the
/// status-bar inset so no screen re-derives it. It is a bar the content scrolls beneath, not an
/// AppBar. On it: the page name, an optional second line, and the screen's own controls at the
/// trailing edge. Strings go into [BrowTitleBlock], never Text in the theme's styles: those carry
/// the theme's ink and would beat the brow's white.
///
/// THE HOME TAB DOES NOT USE THIS. It opens with the clay [AppHeader] — the date over the
/// greeting, the account at the leading edge — which is the shape every role's home shares. A
/// tab keeps its title here, because a greeting over "Expenses" would take away the one word
/// saying which of four tabs you are standing in.
class ManagerScreen extends StatelessWidget {
  const ManagerScreen({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
  });

  final String title;

  /// For a real second fact — which ledger is showing, which day is open — because the
  /// alternative is a header that cannot say what you are looking at.
  final String? subtitle;

  /// The clay [HeaderIconButton] is the control that belongs here. A plain IconButton still
  /// takes the brow's ink from [BrowTitleBlock].
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GlassHeader(
          onBrow: true,
          child: BrowTitleBlock(title: title, subtitle: subtitle, actions: actions),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The heading over a group INSIDE a sheet or a form — "Move it along", "Category".
///
/// The clay [SectionHeader] at the form step: Outfit, sentence case, the theme's ink, and a
/// semantics header so a screen reader can jump to it. It was an 11px upper-cased eyebrow,
/// which on a cream sheet read as a caption that had lost its picture.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});

  final String label;

  /// A quiet fact or control on the right of the heading, where a form has one.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) =>
      SectionHeader(title: label, size: SectionHeaderSize.form, trailing: trailing);
}

/// A titled group on a page: the clay heading at the card step, then the content under it.
///
/// [actionLabel] is the heading's own link — "View all" — with its 48dp target. A heading that
/// carries one is taller than a bare one by the button's padding, so the gap under it is taken
/// back by the same amount and the content starts on the same rhythm either way.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final linked = trailing == null && actionLabel != null && onAction != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: label,
          size: SectionHeaderSize.card,
          trailing: trailing,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
        SizedBox(height: linked ? Space.xxs : Space.sm),
        child,
      ],
    );
  }
}

/// A card on the page: the card fill at the surface radius, on the design's hairline, flat.
///
/// Every resting card in the clay system is flat — elevation is for things that float, and
/// nothing on a manager's page does. This is [FlatSurface] at the radius the kit gives a group
/// of rows, a banner and a stat tile, so a section built here lines up with the tiles above it.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      FlatSurface(borderRadius: Radii.rSurface, padding: padding, child: child);
}

/// One filter chip — the clay filter pill, built on a real [ChoiceChip].
///
/// Unselected is the card fill on a hairline with the label in the secondary ink; SELECTED IS
/// FOREST with white on it, which is the one way this design says "this is the one of these
/// you are looking at". A capsule, because a chip label is one line and can never take a
/// second. The visual pill is short; the tap target is padded out to 48dp.
///
/// A ChoiceChip rather than a hand-rolled box so it keeps Material's selection semantics for a
/// screen reader.
class ToggleChip extends StatelessWidget {
  const ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;

  /// Null disables the chip, which is what a sheet does while a write is in flight.
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return ChoiceChip(
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary,
      // The row-title step, without the tabular figures it carries for numbers: a word has no
      // use for them.
      labelStyle: t.textTheme.titleSmall?.copyWith(
        fontFeatures: const [],
        color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: Strokes.hairline,
      ),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.tight),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATES
// ─────────────────────────────────────────────────────────────────────────────

/// A failed load, told in the database's own words where it had any.
///
/// [AppFailure] already distinguishes "no signal" from "you are not allowed" from "the
/// subscription lapsed"; the retry button appears only where retrying could actually work,
/// because a button that cannot help is worse than no button.
///
/// It is the clay [EmptyState] in its failure dress — the art on a Mist disc, a heading, the
/// failure's own sentence under it — rather than a red panel: a whole red block reads as "the
/// app is broken" on a screen where one section failed and three did not. [compact] is the
/// in-card size, for a section of a page; the full size is for a page that is nothing else.
class FailureNote extends StatelessWidget {
  const FailureNote({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.from(error);
    final canRetry = onRetry != null && failure.isRetryable;
    return EmptyState(
      compact: compact,
      icon: failure.needsSignIn ? ClayIcons.security : ClayIcons.complaint,
      // "Could not load this" is wrong for a dead credential: it did not fail to load, it was
      // never asked on this person's behalf. The heading says which, and the sentence under
      // it is the failure's own.
      title: failure.needsSignIn ? 'Your sign-in has ended' : 'Could not load this',
      body: failure.message,
      action: failure.needsSignIn ? const SignInAgainButton() : null,
      actionLabel: canRetry ? 'Try again' : null,
      onAction: canRetry ? onRetry : null,
    );
  }
}

/// An [AsyncValue] rendered with one loading, one failure and one data treatment.
///
/// While a refresh is in flight the PREVIOUS data stays on screen: `hasValue` is checked before
/// `isLoading`. This also sidesteps a Riverpod 3 behaviour that would otherwise delete every
/// error state in the app — a failed provider is retried with backoff, and while that retry is
/// pending the state is AsyncLoading carrying the previous error, so `.when()` with its default
/// flags takes the loading branch and the error is never drawn.
///
/// LOADING IS A SKELETON, never a spinner: the rows' own outline, pulsing, so the arrival of the
/// data changes what is in the shapes rather than the shapes themselves. [loading] is the
/// section's own skeleton; the default is three list rows.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
    this.carded = true,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  /// True for a SECTION of a page: a failure is drawn in a card at the compact size, so it
  /// keeps the section's shape among the cards around it. False for a page that is this one
  /// read and nothing else, where the failure stands on the ground at full size.
  final bool carded;

  @override
  Widget build(BuildContext context) {
    // ── THE ONE PLACE THE WHOLE APP GAINS AN ARRIVAL ────────────────────────────────────
    // This used to return the three branches directly, so a skeleton was present on one frame
    // and the rows were present on the next. See shared/motion/settle.dart for why that single
    // instant substitution is most of what the owner noticed against the competitor, and why
    // the fix belongs here rather than at the call sites.
    if (value.hasValue) {
      return Settle(state: 'data', child: builder(value.requireValue));
    }
    if (value.hasError) {
      final note = FailureNote(error: value.error!, onRetry: onRetry, compact: carded);
      return Settle(
        state: 'error',
        child: carded ? SectionCard(padding: EdgeInsets.zero, child: note) : note,
      );
    }
    return Settle(state: 'loading', child: loading ?? const ListSkeleton());
  }
}

/// A banner at the top of a screen. One geometry for every kind of notice, so "we are
/// checking", "here is a warning" and "we could not check" occupy the same space and differ
/// only in the two things that carry the meaning: the colour and the words.
///
/// The clay banner's shape — a rounded fill with no edge, the glyph on a disc of the card fill —
/// in the tone it was given. AN INFO NOTICE TAKES MIST, the kit's own information fill, with the
/// heading in forest; a warning or a failure takes a 10% tint of its tone with the heading in
/// that tone's text ink. The sentence under the heading is in the body ink either way: the tone
/// has already said how serious this is, and a paragraph in amber is harder to read than one in
/// the body colour.
///
/// [tone] is a CANONICAL token ([ApnivaasColors.warning] and friends); it is resolved here.
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

  /// Canonical, not resolved. See ApnivaasSemantics.resolve.
  final Color tone;

  /// Drawn only when there is something a retry could actually change.
  final VoidCallback? action;
  final String? actionLabel;

  /// Replaces the icon with a spinner, for the "we do not know yet" face.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final info = tone == ApnivaasColors.info;
    final fill = info
        ? (dark ? ApnivaasColors.darkMist : ApnivaasColors.mist)
        : context.tones.chipFill(tone);
    final ink = info
        ? (dark ? t.colorScheme.onSurface : ApnivaasColors.forest)
        : context.tones.resolve(tone);

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: fill, borderRadius: Radii.rWell),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.md, Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: Space.xxxl,
                  height: Space.xxxl,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: t.colorScheme.surface, shape: BoxShape.circle),
                  child: busy
                      ? SizedBox.square(
                          dimension: IconSize.md,
                          child: CircularProgressIndicator(strokeWidth: Strokes.focus, color: ink),
                        )
                      : Icon(icon, size: IconSize.lg, color: ink),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Padding(
                  // Sets the heading's first line against the disc's centre rather than its top.
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.textTheme.titleMedium?.copyWith(color: ink)),
                      if (detail != null) ...[
                        const SizedBox(height: Space.hair),
                        Text(
                          detail!,
                          style: t.textTheme.bodyMedium
                              ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                        ),
                      ],
                      if (action != null) ...[
                        const SizedBox(height: Space.xs),
                        PillButton(label: actionLabel ?? 'Try again', onPressed: action),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE OVERVIEW TILES
// ─────────────────────────────────────────────────────────────────────────────

/// The figure a stat tile draws once a read has actually produced one.
///
/// Returned by [AsyncStat.figure] rather than assembled at the call site, so a screen cannot
/// accidentally compute a caption or a tone from data it does not have yet.
class StatFigure {
  const StatFigure({required this.value, this.caption, this.tone});

  /// Already formatted. A dash here means the DATA said nothing, not that it is still coming.
  final String value;
  final String? caption;

  /// Canonical. When set, [caption] is drawn as a [StatusChip] in this tone — the one part of
  /// a tile that is allowed to carry a state. Null leaves the caption a plain line, which is
  /// the honest choice when the data does not imply a state.
  final Color? tone;
}

/// A manager's overview tile: the clay [StatTile] fed the way this role's figures need.
///
/// One clay icon, the figure in tabular Outfit, the label under it and one caption. [hero] is
/// the forest tile, at most one per screen. [tone] is a MEANING (see [toneFor]): it turns the
/// caption into a chip of that tone rather than colouring the figure — "2 past their date" in
/// red under a job count is the state; the count itself is just a count. A screen that tones
/// every tile has no emphasis left to spend.
///
/// The whole tile is one node to a screen reader, "Jobs open: 4. 2 past their date", and a
/// button when [onTap] opens what it counts.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tone,
    this.icon,
    this.hero = false,
    this.onTap,
  });

  final String label;

  /// Already formatted. A dash here means the DATA said nothing.
  final String value;
  final String? caption;

  /// Canonical, resolved by the chip. See ApnivaasSemantics.resolve. Ignored on the hero, whose
  /// forest has no room for a second colour.
  final Color? tone;

  /// A [ClayIcons] path.
  final String? icon;
  final bool hero;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = tone != null && caption != null && !hero;
    return StatTile(
      style: hero ? StatTileStyle.hero : StatTileStyle.plain,
      icon: icon,
      label: label,
      value: value,
      caption: chip ? null : caption,
      delta: chip ? caption : null,
      deltaTone: chip ? StatusTone.fromCanonical(tone) : StatusTone.neutral,
      onTap: onTap,
      semanticLabel: '$label: $value${caption == null ? '' : '. $caption'}',
    );
  }
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
///   · failed  — [FailedStat]: the failure's own sentence, and a retry only where one can work.
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
    required this.figure,
    this.icon,
    this.loadingCaption,
    this.onTap,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final String label;
  final StatFigure Function(T data) figure;

  /// The tile's clay art, the same in every face so the tile keeps its identity when it fails.
  /// The failed face adds its own glyph for WHAT failed — a padlock for a refusal, a struck-
  /// through cloud for no signal — which a call site could not know in advance.
  final String? icon;
  final String? loadingCaption;
  final VoidCallback? onTap;

  /// Wired to whatever re-reads the provider behind [value]. Omit it where nothing on this
  /// screen can retry — [FailedStat] then offers no retry rather than a dead one.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final f = figure(value.requireValue);
      return StatCard(
        label: label,
        value: f.value,
        caption: f.caption,
        tone: f.tone,
        icon: icon,
        onTap: onTap,
      );
    }
    if (value.hasError) {
      return FailedStat(label: label, error: value.error!, onRetry: onRetry, icon: icon);
    }
    return StatCard(label: label, value: '—', caption: loadingCaption, icon: icon, onTap: onTap);
  }
}

/// The face a stat tile wears when its read failed.
///
/// "Not available" stands where the figure would, in the error ink — WORDS, so the tile cannot
/// be read as a measurement at a glance — with the failure's own sentence under it. The clay art
/// stays, so a manager still knows which tile this is; the glyph beside it says why.
///
/// THE WHOLE TILE IS THE RETRY, where a retry can work, and the chip under the sentence says so:
/// a tile is one node to a screen reader, so a second button inside it would be a control that
/// only sighted people could reach. Where retrying cannot help — AccessDeniedFailure will refuse
/// again — the tile is inert and offers nothing, because a control that does nothing teaches
/// people the controls do nothing.
///
/// Public because a screen may cover SEVERAL tiles with one failure. Three tiles fed by one
/// provider must not print the same sentence three times when that provider fails — see the
/// overview on the home screen, where a failed finance read collapses to a single tile.
class FailedStat extends StatelessWidget {
  const FailedStat({
    super.key,
    required this.label,
    required this.error,
    this.onRetry,
    this.icon,
  });

  final String label;
  final Object error;
  final VoidCallback? onRetry;

  /// A [ClayIcons] path — the art the tile wears when it has a figure.
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.from(error);
    final canRetry = onRetry != null && failure.isRetryable;

    return StatTile(
      icon: icon,
      label: label,
      value: 'Not available',
      valueTone: ApnivaasColors.error,
      caption: failure.message,
      // THE PADLOCK IS RESERVED FOR AN ACTUAL REFUSAL. A tile whose read died with the access
      // token used to wear it too — a lock glyph over a number the manager is entitled to, on
      // a screen glanced at between two other jobs, is the whole misattribution in one icon. A
      // dead sign-in gets the clock instead.
      badge: Icon(
        switch (failure) {
          OfflineFailure() => Icons.wifi_off_rounded,
          AccessDeniedFailure() || ReadOnlyFailure() => Icons.lock_outline_rounded,
          SessionExpiredFailure() || SignedOutFailure() => Icons.schedule_rounded,
          _ => Icons.error_outline_rounded,
        },
        size: IconSize.lg,
        color: context.tones.error,
      ),
      delta: canRetry ? 'Tap to try again' : null,
      deltaTone: StatusTone.brand,
      onTap: canRetry ? onRetry : null,
      semanticLabel: '$label: not available. ${failure.message}'
          '${canRetry ? ' Double tap to try again.' : ''}',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ROWS
// ─────────────────────────────────────────────────────────────────────────────

/// The job's state square — empty, under way, finished, or late.
///
/// IT IS A MARKER, NOT A CHECKBOX, and the semantics say so. A manager may only move a task
/// along through the sheet (app.tasks_before_update refuses everything else), and a tick box
/// that writes on tap would be a second, quieter path to the same status change — one with no
/// confirmation and no way back. The whole row opens the sheet; this square reports where the
/// job has got to.
///
/// Four faces, told apart by shape as well as by hue, so the column still reads in greyscale:
/// an empty outline, an outline with a smaller square inside it (under way), a filled square
/// with a tick (finished), and a red outline on a red tint (late).
class _TaskMark extends StatelessWidget {
  const _TaskMark({required this.status, required this.late});

  final TaskStatus status;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final done = status == TaskStatus.done;
    final underway = status == TaskStatus.inProgress;

    final Color edge = late
        ? tones.error
        : underway
            ? tones.info
            : t.colorScheme.outline;

    return Container(
      width: Space.xl,
      height: Space.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done
            ? tones.success
            : late
                ? tones.chipFill(tones.error)
                : Colors.transparent,
        borderRadius: Radii.rCheck,
        border: done ? null : Border.all(color: edge, width: Strokes.control),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: IconSize.md, color: t.colorScheme.surface)
          : underway && !late
              ? Container(
                  width: Space.xs + Space.hair,
                  height: Space.xs + Space.hair,
                  decoration: BoxDecoration(color: edge, borderRadius: Radii.rCheck / 2),
                )
              : null,
    );
  }
}

/// One job — the same widget on the home screen's "Today's tasks" and on the Tasks tab.
///
/// The state square, the title, and one meta line: the status as a [StatusChip] and the due date
/// said the way somebody plans their day, in red when it has passed. The finished row goes
/// quiet — its title drops to the secondary ink and its date becomes the day it closed — which
/// is how a list says "this one is behind you" without hiding it.
///
/// The status and the due date are TWO SEPARATE TEXTS, so a screen reader and a test can both
/// address them. public.tasks has no category column and `due_date` is a DATE, not a timestamp,
/// so those two are the facts a row genuinely has; nothing here invents a third.
///
/// [grouped] is for rows the caller has put in one [ListGroup] (the home's three); otherwise the
/// row is its own card, the way every paged list in the app draws its rows.
class TaskLine extends StatelessWidget {
  const TaskLine({super.key, required this.task, this.onTap, this.grouped = false});

  final Task task;
  final VoidCallback? onTap;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final due = task.dueDate;
    // isOverdue comes from the Task model — due date past AND still open — so the row and the
    // server's own overdue count agree on what "late" means.
    final late = task.isOverdue;
    final done = task.status == TaskStatus.done;
    // A FINISHED JOB IS NOT "4 DAYS LATE". Measuring its due date against today would make a
    // claim about how late it was finished that the row cannot back; it says when it closed
    // (completed_at, stamped by the server) or, failing that, when it was due.
    final completed = task.completedAt;
    final when = done
        ? completed != null
            ? 'Finished ${shortDate(completed)}'
            : due == null
                ? null
                : 'Was due ${shortDate(due)}'
        : due == null
            ? null
            : dueLabel(due);

    final row = Semantics(
      container: true,
      button: onTap != null,
      label: '${task.title}. ${task.status.label}${when == null ? '' : '. $when'}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ListRow.minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                _TaskMark(status: task.status, late: late),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: t.textTheme.titleMedium?.copyWith(
                          color: done ? t.colorScheme.onSurfaceVariant : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Space.xxs),
                      // A WRAP, NOT A ROW: "In progress" and "12 days late" side by side at 1.6x
                      // text are wider than a 320dp row, and a Row has no give at all.
                      Wrap(
                        spacing: Space.xs,
                        runSpacing: Space.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(
                            label: task.status.label,
                            tone: StatusTone.fromCanonical(toneFor(context, task.status)),
                          ),
                          if (when != null)
                            Text(
                              when,
                              style: t.textTheme.bodySmall?.copyWith(
                                color: late ? tones.error : t.colorScheme.onSurfaceVariant,
                                fontWeight: late ? FontWeight.w700 : null,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: IconSize.lg,
                  color: t.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return grouped ? row : ListGroup(children: [row]);
  }
}

/// A label above a value, for the detail sheets, with its glyph on a small Mist disc.
///
/// STACKED, NOT SIDE BY SIDE. The old two-column row gave the label a fixed 112dp, which at
/// large text squeezed "Raised by" onto two lines and left the value the rest; on top of each
/// other, both words get the full width at any size.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(
              child: Container(
                width: Space.xxl,
                height: Space.xxl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark ? ApnivaasColors.darkMist : ApnivaasColors.mist,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: IconSize.sm, color: t.colorScheme.primary),
              ),
            ),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Space.hair),
                  Text(value, style: t.textTheme.titleSmall?.copyWith(fontFeatures: const [])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEETS
// ─────────────────────────────────────────────────────────────────────────────

/// The title of a bottom sheet — the clay [SheetTitle] — and whatever state it carries.
///
/// NO DRAG HANDLE. `showGlassSheet` already draws one on the pane itself, and this header used
/// to draw a second one 16dp below it — two grey pills stacked on every sheet in this role.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;

  /// A status chip, or the clay art for what the sheet records.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = SheetTitle(title: title, subtitle: subtitle);
    final end = trailing;
    if (end == null) return heading;
    // AT LARGE TEXT THE CHIP GOES ON TOP. Beside a 20px title at 1.6x and more, a status chip
    // leaves the heading so little width that "vegetables" breaks in the middle of the word;
    // above it, the chip reads as the heading's label and the title gets the whole line.
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.6) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [end, const SizedBox(height: Space.xs), heading],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heading),
        const SizedBox(width: Space.sm),
        end,
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
          const SizedBox(height: Space.lg),
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

/// The small spinner a button wears while its write is in flight — the one place a spinner is
/// still right in this role, because a write has no shape to sketch a skeleton of.
class BusyMark extends StatelessWidget {
  const BusyMark({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: IconSize.lg,
        child: CircularProgressIndicator(strokeWidth: Strokes.focus, color: color),
      );
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
