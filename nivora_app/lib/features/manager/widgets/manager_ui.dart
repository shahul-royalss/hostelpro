library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import '../../shell/staff_profile_sheet.dart';
import '../../../shared/wordmark.dart';
import '../../../shared/sign_in_again.dart';

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
/// ── THE SHAPES COME FROM FIGMA `4:1159`, `screen-manager-dashboard` ───────────────────────
///
/// That frame is the whole vocabulary of this role, and it is NOT the vocabulary the previous
/// Stitch mockup used. The two disagree on the single most structural thing on the screen:
///
///   * Stitch grouped the dashboard into titled CARDS — a violet glyph, a 20/600 heading, and
///     the rows inside a raised block. [SectionCard] existed for that.
///   * Figma groups it into an 11px uppercase EYEBROW over content standing on the ground.
///     `TODAY'S TASKS` (4:1196) and `CATEGORIZED EXPENSES` (4:1214) are `text-[#6f747a]
///     text-[11px] uppercase` with no box, no glyph and no fill under them.
///
/// So the card is gone and [SectionLabel] is what a group is announced with. Everything else
/// in this file is that frame's own anatomy: the 2x2 KPI grid (4:1177), the boxed task row with
/// its 16dp state square (4:1197), the legend dot (4:1221).
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

/// The frame's 6dp gap — inside a KPI tile (4:1178) and between the day tabs (4:1261).
///
/// Six is NOT a step on [Space], and tokens.dart is explicit that it should not become one:
/// the design's 10s, 6s, 3s and 2s are strays rather than a second vocabulary, and adding a
/// rung for each would turn a scale into a lookup table. It is written as half of [Space.sm]
/// so it still moves if the rhythm ever does, and it is named once here rather than typed as a
/// bare `6` at five paint sites.
const double _gap6 = Space.sm / 2;

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

/// A manager screen: the page header, then content.
///
/// THE HEADER IS THE DESIGN'S OWN, 4:1170. `h-[56px] px-[16px] py-[12px]`, a bottom hairline
/// and nothing else — a 16/700 name over an 11/400 line in the quietest ink. That is a much
/// QUIETER header than the 24/700 display title it replaces, and the difference is the whole
/// point: on `screen-manager-dashboard` the loudest thing is the KPI grid, not the greeting
/// above it. A 24px title competes with the figures the screen exists to show.
///
/// It is still a bar content scrolls beneath, not an AppBar — see GlassHeader, which also owns
/// the status-bar inset so no screen re-derives it. It is also the ONLY pane on the screen:
/// GlassSurface asserts when panes nest, and everything below is FlatSurface.
///
/// THE MOCKUP'S SECOND LINE IS THE ROLE — "NIVORA HQ MANAGER". Ours is the hostel's real name,
/// which is the fact a manager standing in one of two buildings actually needs; the role is
/// already spelled out by the navigation bar underneath.
class ManagerScreen extends StatelessWidget {
  const ManagerScreen({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.masthead = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  /// The dashboard treatment: signature centred, account avatar leading, nothing trailing. Set
  /// only by the manager's home — the other tabs keep their titles, because a masthead over
  /// "Expenses" removes the one word saying which tab you are in.
  final bool masthead;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        GlassHeader(
          child: masthead
              ? _masthead(context)
              : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // title 16/700 — the design's own `text-[16px] Bold` (4:1173).
                    Text(title,
                        style: t.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null) ...[
                      const SizedBox(height: Space.xxs / 2),
                      // meta 11/400 (4:1174). The design sets it in #6F747A, which measures
                      // 3.92:1 and is not AA as text; `tones.muted` is that hue lifted until it
                      // passes. See NivoraColors.darkMuted.
                      Text(subtitle!,
                          style: t.textTheme.bodySmall?.copyWith(color: context.tones.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
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

  /// Avatar, signature, and an empty box the same width as the avatar so the mark is centred on
  /// the SCREEN rather than on the space beside it.
  Widget _masthead(BuildContext context) {
    final t = Theme.of(context);
    final name = title.replaceFirst('Hello, ', '').trim();
    return Row(
      children: [
        Tooltip(
          message: 'Your account',
          child: InkWell(
            onTap: () => showStaffProfile(context),
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(Space.xxs),
              child: AccountAvatar(name: name.isEmpty ? 'Nivora' : name, size: IconSize.xl),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 116,
              height: 116 / 3.4,
              child: NivoraWordmark(progress: 1, color: t.colorScheme.onSurface),
            ),
          ),
        ),
        const SizedBox(width: IconSize.xl + Space.xxs * 2),
      ],
    );
  }
}

/// The design's section eyebrow — `TODAY'S TASKS` (4:1196), `CATEGORIZED EXPENSES` (4:1214).
///
/// An uppercase label in the quietest ink, with nothing under it. This is what replaced the
/// titled card: the Figma dashboard has no card around a group, no glyph in front of a heading
/// and no fill behind either. The rows below simply stand on the ground.
///
/// The string is uppercased HERE rather than at every call site — a TextStyle cannot do it, and
/// leaving it to callers is how one section ends up in sentence case.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});

  final String label;

  /// The design's quiet action on the right of a heading, where a screen has one.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            // label-caps 12/600 at +0.05em, in the muted ink. DESIGN-SYSTEM.md's own
            // "12/600 CAPS · section labels"; the frame draws it at 11, which is the same step.
            style: t.textTheme.labelMedium?.copyWith(color: context.tones.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A titled group: the design's eyebrow, then the content, with the frame's own 10dp gap.
///
/// NOT A CARD. `screen-manager-dashboard` puts every group directly on `#0b0d0f` — see the
/// header of this file for why the previous [SectionCard] had to go.
class Section extends StatelessWidget {
  const Section({super.key, required this.label, required this.child, this.trailing});

  final String label;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(label: label, trailing: trailing),
          const SizedBox(height: Space.sm),
          child,
        ],
      );
}

/// The full-width control at the foot of a list — "View all tasks".
///
/// The design's secondary button (4:1587, "Learn More") is a HAIRLINE OUTLINED BOX with cream
/// text, not a filled block: the outline is what says "button", so the label stays ordinary.
/// It is deliberately not a [FilledButton] — the cream fill is reserved for the one action a
/// screen exists for, and a footer that only navigates is a quieter thing than that.
class CapsButton extends StatelessWidget {
  const CapsButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: onTap,
          child: Container(
            height: Space.xxxl, // 40 — the design's own button height (4:1313)
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: Radii.rControl,
              border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
            ),
            child: Text(
              label.toUpperCase(),
              style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small tinted glyph badge, squared at [Radii.tiny].
///
/// A null [tone] gets the neutral chip surface, which is what the design's own untoned badge
/// uses.
class ToneBadge extends StatelessWidget {
  const ToneBadge({super.key, required this.icon, this.tone, this.size = IconSize.md});

  final IconData icon;

  /// Canonical, resolved here. See NivoraSemantics.resolve.
  final Color? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final ink = tone == null ? t.colorScheme.onSurfaceVariant : tones.resolve(tone!);
    return Container(
      padding: const EdgeInsets.all(Space.xs),
      decoration: BoxDecoration(
        color: tone == null ? t.colorScheme.surfaceContainerHighest : tones.chipFill(tone!),
        borderRadius: Radii.rTiny,
      ),
      child: Icon(icon, size: size, color: ink),
    );
  }
}

/// One filter chip, in the design's day-tab dress (4:1262 / 4:1265).
///
/// Unselected is the raised fill under a hairline; SELECTED IS THE GOLD, with near-black on it
/// — the one place in this design a chip is filled with the accent rather than tinted with it.
/// Built as a real [ChoiceChip] rather than a hand-rolled box so it keeps Material's selection
/// semantics for a screen reader.
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
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primary,
      labelStyle: t.textTheme.titleSmall?.copyWith(
        color: selected ? scheme.onPrimary : scheme.onSurface,
      ),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: Strokes.hairline,
      ),
      shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
    );
  }
}

/// Nothing to show — said in words that tell the manager whether that is good news.
///
/// The shape is the design's empty card (4:1575/4:1578): the RAISED surface under a hairline,
/// a 56dp outlined square holding the glyph, a 14/600 title and an 11/400 support line. Those
/// primitives live in shared/glass — this is where they meet a manager's sentences.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.tone,
    this.illustration,
  });

  final IconData icon;
  final String title;
  final String? detail;

  /// An [EmptyArt] path drawn at 160dp INSTEAD of the outlined glyph square.
  ///
  /// Only the states a brand-new account lands on get one — see the note on
  /// [StateBody.illustration]. A list emptied by a SEARCH or a FILTER keeps its glyph: the
  /// artwork means "nothing here yet", which is not what "no match for that" means. [icon]
  /// stays required either way, because it is what the artwork falls back to.
  final String? illustration;

  /// A STATUS tone only where empty is genuinely GOOD news — the cleared task list's green
  /// tick — or a DOMAIN tone where the empty list belongs to one area and the glyph is that
  /// area's: the noticeboard's blue megaphone, the ledger's green receipt. See NivoraDomain
  /// for the line between the two. Null keeps the design's neutral outline, which is right
  /// for a filter that matched nothing and for every "no hostel on this account": a
  /// reassuring tick over "no data yet" is the interface congratulating itself.
  final Color? tone;

  @override
  Widget build(BuildContext context) => StateCard(
        tone: tone,
        child: StateBody(
          icon: icon,
          illustration: illustration,
          title: title,
          message: detail,
          tone: tone,
        ),
      );
}

/// A failed load, told in the database's own words where it had any.
///
/// [AppFailure] already distinguishes "no signal" from "you are not allowed" from "the
/// subscription lapsed"; the retry button appears only where retrying could actually work,
/// because a button that cannot help is worse than no button.
///
/// The design's error card (4:1588) is the same raised box as the empty one with a red caps
/// badge and NO glyph — the sentence is the message — and its retry is the cream filled button
/// (4:1596). A whole red panel would read as "the app is broken" on a screen where one section
/// failed and three did not.
class FailureNote extends StatelessWidget {
  const FailureNote({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.from(error);
    final canRetry = onRetry != null && failure.isRetryable;
    return StateCard(
      badge: 'Error',
      tone: NivoraColors.error,
      child: StateBody(
        // "Could not load this" is wrong for a dead credential: it did not fail to load, it was
        // never asked on this person's behalf. The heading says which, and the sentence under
        // it is the failure's own.
        title: failure.needsSignIn ? 'Your sign-in has ended' : 'Could not load this',
        message: failure.message,
        action: failure.needsSignIn
            ? const SignInAgainButton()
            : canRetry
                ? FilledButton(
                    onPressed: onRetry,
                    // Width 0 so it hugs its label rather than inheriting the theme's full-bleed
                    // Size.fromHeight; the height stays at the 48dp tap target.
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('Try again'),
                  )
                : null,
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
/// The recipe is the design's subscription banner (4:1531): a 10% fill of the tone under a
/// full-strength hairline, the glyph and the heading in the tone, and THE SENTENCE ITSELF IN
/// CREAM — the tone has already said how serious this is, and a full paragraph in amber is
/// harder to read than one in the body colour.
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
      padding: const EdgeInsets.all(Space.sm),
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
          const SizedBox(width: Space.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The design's eyebrow is set in caps; this one is not uppercased, because it
                // carries a real sentence read off the database rather than a two-word state
                // label. The style is the design's; the case is the sentence's.
                Text(title, style: t.textTheme.labelMedium?.copyWith(color: ink)),
                if (detail != null) ...[
                  const SizedBox(height: Space.xxs / 2),
                  Text(detail!,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface)),
                ],
                if (action != null) ...[
                  const SizedBox(height: Space.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: action,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
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

// ─────────────────────────────────────────────────────────────────────────────
// THE KPI GRID — 4:1177
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

  /// Canonical, resolved by [StatCard]. Null leaves the tile in plain cream, which is the
  /// honest choice when the data does not imply a state.
  final Color? tone;
}

/// The design's KPI tile — 4:1178, and the same box three more times across 4:1177.
///
/// `bg-[#171a1e] border border-[#292e33] rounded-[10px] p-[12px] gap-[6px]`, holding exactly
/// three lines: a 10px uppercase eyebrow in the quietest ink, the figure at 16/700, and one
/// 10px support line. Four of them in a 2x2 grid, which is the first thing on the frame.
///
/// ── WHAT CHANGED FROM THE PREVIOUS TILE, AND WHY ─────────────────────────────────────────
///
/// * **No glyph badge.** The old tile squared a tinted icon into its top-right corner. Not one
///   of the four tiles on 4:1177 has one — the label is the label.
/// * **No 48px hero.** The Stitch mockup had one giant figure per screen on a shadowed pane.
///   Figma's four tiles are all the same size and all 16/700, and the emphasis comes from the
///   one tile that is allowed a colour. So [StatCard] has no `hero` and there is no pane.
/// * **Colour is spent once.** The design tints exactly one of its four tiles (4:1193, the
///   overdue count, red in both the figure and its caption) and leaves the other three cream.
///   [tone] is a MEANING (see [toneFor]), so it colours the figure AND the line under it, and
///   a screen that tones every tile has no emphasis left to spend.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tone,
    this.onTap,
  });

  final String label;

  /// Already formatted. A dash here means the DATA said nothing.
  final String value;
  final String? caption;

  /// Canonical, resolved here. See NivoraSemantics.resolve.
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    final semantics = '$label: $value${caption == null ? '' : '. $caption'}';

    return FlatSurface(
      // The raised fill, not the card one: on 4:1178 the KPI tiles are #171A1E on the #0B0D0F
      // ground, which is a full rung brighter than the rows further down the frame.
      weight: GlassWeight.regular,
      borderRadius: Radii.rControl,
      padding: const EdgeInsets.all(Space.sm),
      onTap: onTap,
      semanticLabel: semantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // labelSmall is the design's chip step: 10/600 at +0.05em. A TextStyle cannot
          // uppercase, so the string does it here.
          Text(label.toUpperCase(),
              style: t.textTheme.labelSmall?.copyWith(color: context.tones.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: _gap6),
          // headlineSmall is 16/700 tabular — the design's own figure size, and tabular so a
          // refreshing row of rupee amounts does not shuffle sideways.
          Text(
            value,
            style: t.textTheme.headlineSmall?.copyWith(color: accent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (caption != null) ...[
            const SizedBox(height: _gap6),
            Text(caption!,
                style: t.textTheme.bodySmall?.copyWith(color: accent ?? context.tones.muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
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
    this.loadingCaption,
    this.onTap,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final String label;

  /// NO GLYPH PARAMETER. The design's KPI tile (4:1178) carries none, and the failed face picks
  /// its own from the failure's TYPE — a padlock for a refusal, a struck-through cloud for no
  /// signal. A glyph chosen at the call site could not know which of those happened.
  final StatFigure Function(T data) figure;
  final String? loadingCaption;
  final VoidCallback? onTap;

  /// Wired to whatever re-reads the provider behind [value]. Omit it where nothing on this
  /// screen can retry — [FailedStat] then draws no button rather than a dead one.
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
        onTap: onTap,
      );
    }
    if (value.hasError) {
      return FailedStat(label: label, error: value.error!, onRetry: onRetry);
    }
    return StatCard(label: label, value: '—', caption: loadingCaption, onTap: onTap);
  }
}

/// The face a stat tile wears when its read failed.
///
/// Deliberately NOT a number-shaped tile: no figure line, no dash in the figure slot. A reader
/// glancing at the grid has to be able to tell at that glance that this one is not a
/// measurement.
///
/// Public because a screen may cover SEVERAL tiles with one failure. Three tiles fed by one
/// provider must not print the same sentence three times when that provider fails — see the
/// KPI grid on the home screen, where a failed finance read collapses to a single card.
class FailedStat extends StatelessWidget {
  const FailedStat({super.key, required this.label, required this.error, this.onRetry});

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
      weight: GlassWeight.regular,
      borderRadius: Radii.rControl,
      padding: const EdgeInsets.all(Space.sm),
      semanticLabel: '$label: not available. ${failure.message}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // THE PADLOCK IS RESERVED FOR AN ACTUAL REFUSAL. A tile whose read died with the
            // access token used to wear it too — a lock glyph over a number the manager is
            // entitled to, on a screen glanced at between two other jobs, is the whole
            // misattribution in one 16dp icon. A dead sign-in gets the clock instead.
            Icon(
              switch (failure) {
                OfflineFailure() => Icons.wifi_off_rounded,
                AccessDeniedFailure() || ReadOnlyFailure() => Icons.lock_outline_rounded,
                SessionExpiredFailure() || SignedOutFailure() => Icons.schedule_rounded,
                _ => Icons.error_outline_rounded,
              },
              size: IconSize.sm,
              color: ink,
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(label.toUpperCase(),
                  style: t.textTheme.labelSmall?.copyWith(color: context.tones.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: _gap6),
          Text('Not available', style: t.textTheme.titleSmall?.copyWith(color: ink)),
          const SizedBox(height: _gap6),
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

/// A list row in the design's own dress — 4:1197.
///
/// `bg-[#111417] border border-[#292e33] rounded-[8px] p-[8px] gap-[10px]`: the CARD fill on
/// the ground under a hairline, at the small radius rather than a card's. Every ordinary row in
/// this role is that box, on the dashboard and in a list alike.
///
///   · default    — the design's row.
///   · [plain]    — no fill, no edge, for a row that already sits on another surface.
///   · [tone]     — the alert row: `chipFill` over `chipBorder`, both from the one place those
///                  alphas are measured (NivoraSemantics). Wins over [plain].
///
/// The minimum height is 48 — Material's tap floor, and above Apple's 44pt, so one number
/// satisfies both. The design's own row is shorter than that and would not be reliably
/// tappable by somebody holding a phone one-handed in a kitchen doorway.
class TapRow extends StatelessWidget {
  const TapRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.xs),
    this.semanticLabel,
    this.tone,
    this.plain = false,
    this.borderRadius = Radii.rControl,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  /// Canonical, resolved here. See NivoraSemantics.resolve.
  final Color? tone;

  /// Drops the fill and the edge, for a row that is already on a card.
  final bool plain;

  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final accent = tone;

    final fill = accent != null
        ? tones.chipFill(accent)
        : plain
            ? Colors.transparent
            : t.colorScheme.surface;
    final edge = accent != null
        ? Border.all(color: tones.chipBorder(accent), width: Strokes.hairline)
        : plain
            ? null
            : Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline);

    final row = Material(
      color: fill,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Space.huge),
          padding: padding,
          decoration: BoxDecoration(borderRadius: borderRadius, border: edge),
          child: child,
        ),
      ),
    );
    return semanticLabel == null
        ? row
        : Semantics(label: semanticLabel, button: onTap != null, container: true, child: row);
  }
}

/// The design's 16dp state square — 4:1198 empty, 4:1208 filled.
///
/// `border border-[#292e33] rounded-[4px] size-[16px]`, and when the job is finished
/// `bg-[#5fae82]` with a 10dp tick inside it.
///
/// IT IS A MARKER, NOT A CHECKBOX, and the semantics say so. A manager may only move a task
/// along through the sheet (app.tasks_before_update refuses everything else), and a tick box
/// that writes on tap would be a second, quieter path to the same status change — one with no
/// confirmation and no way back. The whole row opens the sheet; this square reports where the
/// job has got to.
class _TaskMark extends StatelessWidget {
  const _TaskMark({required this.status, required this.late});

  final TaskStatus status;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final done = status == TaskStatus.done;
    final edge = late ? tones.error : t.colorScheme.outlineVariant;

    return Container(
      width: Space.md,
      height: Space.md,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? tones.success : Colors.transparent,
        borderRadius: Radii.rTiny,
        border: done ? null : Border.all(color: edge, width: Strokes.hairline),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: IconSize.xs, color: t.colorScheme.surface)
          : null,
    );
  }
}

/// One job, in the design's task-row anatomy (4:1197) — and the same widget on the Tasks tab.
///
/// The frame's row is a 16dp state square, the title in plain 13/400 cream, and one 10px meta
/// line beneath it in the colour of the job's state. The finished row goes quiet: its text
/// drops to the muted ink and its square fills green.
///
/// ── WHAT IS THE DESIGN'S AND WHAT IS THE DATABASE'S ──────────────────────────────────────
///
/// The mockup's meta line reads `Purchase • Due 11:00 AM` and `Maintenance • Due 03:00 PM`.
/// public.tasks has NO category column and `due_date` is a DATE, not a timestamp — there is no
/// 11:00 AM anywhere in the schema. So the shape is kept and filled with the two facts the row
/// genuinely has: the status, and the due date said the way somebody plans their day. They are
/// two separate Text spans either side of the design's own bullet, so a screen reader and a
/// test can both address them.
///
/// A LATE ROW IS STILL BOXED IN RED, which the mockup does not draw. Its three rows are all
/// on time, so it had nothing to say about the case; "overdue" is the one fact this role's
/// dashboard exists to surface and it keeps the tinted box it already had.
class TaskLine extends StatelessWidget {
  const TaskLine({super.key, required this.task, this.onTap});

  final Task task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final due = task.dueDate;
    // isOverdue comes from the Task model — due date past AND still open — so the row and the
    // server's own overdue count agree on what "late" means.
    final late = task.isOverdue;
    final done = task.status == TaskStatus.done;
    final meta = late ? tones.error : tones.resolve(toneFor(context, task.status));

    return TapRow(
      onTap: onTap,
      tone: late ? NivoraColors.error : null,
      padding: const EdgeInsets.all(Space.xs),
      semanticLabel: '${task.title}. ${task.status.label}'
          '${due == null ? '' : '. ${dueLabel(due)}'}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Keeps the square on the title's optical centre line rather than the row's.
            padding: const EdgeInsets.only(top: 2),
            child: _TaskMark(status: task.status, late: late),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  // body 13/400 — the design's own row title weight (4:1200). The finished row
                  // drops to the muted ink, which is how 4:1211 says "this one is behind you".
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: late
                        ? tones.error
                        : done
                            ? tones.muted
                            : t.colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xxs / 2),
                // BOTH halves are Flexible. "In progress • 12 days late" at 1.6x text scale
                // is wider than a 320dp row, and a bare Text in a Row has no give at all.
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.status.label,
                        style: t.textTheme.labelSmall
                            ?.copyWith(color: done ? tones.muted : meta, letterSpacing: 0.2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (due != null) ...[
                      Text(' • ',
                          style: t.textTheme.labelSmall?.copyWith(color: tones.muted)),
                      Flexible(
                        child: Text(
                          dueLabel(due),
                          style: t.textTheme.labelSmall?.copyWith(
                            color: done ? tones.muted : meta,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Icon(Icons.chevron_right_rounded, size: IconSize.sm, color: t.colorScheme.outline),
        ],
      ),
    );
  }
}

/// One of the things a manager does most, as a target you can hit without looking.
///
/// The design has no quick-action grid — `screen-manager-dashboard` is a reading screen and its
/// only controls are the rows themselves. This is the frame's own KPI-tile box pressed into
/// service as a shortcut: the raised fill under a hairline at [Radii.control], a 16dp glyph
/// in the tone, and the label in body semibold. Nothing here is circular — there is not one
/// circle in the nineteen Figma frames.
///
/// THE DASHBOARD NO LONGER DRAWS THESE. Its "Do it now" row is four [DomainButton]s, each in
/// the colour of the destination it opens — the tonal weight this design left undrawn, and the
/// one that lets four shortcuts say four different places. This tile survives as the neutral
/// shortcut for a screen that has no domain to point at.
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

  /// Canonical, resolved here. Null leaves the glyph in the gold, which is what the design's
  /// own untoned accents use.
  final Color? tone;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final accent = enabled
        ? tones.resolve(tone ?? t.colorScheme.primary)
        : t.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: FlatSurface(
        weight: GlassWeight.regular,
        borderRadius: Radii.rControl,
        padding: const EdgeInsets.all(Space.sm),
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            Icon(icon, size: IconSize.md, color: accent),
            const SizedBox(width: Space.xs),
            Expanded(
              child: Text(
                label,
                style: t.textTheme.titleSmall?.copyWith(
                  color: enabled ? t.colorScheme.onSurface : t.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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

/// The title bar of a bottom sheet: a name, and whatever state it carries.
///
/// NO DRAG HANDLE. `showGlassSheet` already draws one (`_SheetGrip`) on the pane itself, and
/// this header used to draw a second one 16dp below it — two grey pills stacked on every sheet
/// in this role. The one that survives is the one that belongs to the sheet's geometry.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: t.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (subtitle != null) ...[
                const SizedBox(height: Space.xxs / 2),
                Text(subtitle!,
                    style: t.textTheme.bodySmall?.copyWith(color: context.tones.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        ?trailing,
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
