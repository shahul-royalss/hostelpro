library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/brow.dart';
import '../../../shared/brow_header.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/illustrations.dart';
import '../../../shared/sign_in_again.dart';
import '../../../shared/motion/settle.dart';

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

/// The month of a 'YYYY-MM' alone — "October" — for a figure that already sits under the
/// year's heading. An unrecognised string comes back untouched, like [monthLabel].
String monthName(String periodMonth) {
  final parts = periodMonth.split('-');
  final month = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (month == null || month < 1 || month > 12) return periodMonth;
  return DateFormat('MMMM').format(DateTime(2000, month));
}

/// A count with its noun agreeing — "1 resident", "6 residents". [plural] for the nouns that
/// do not take an s.
String countOf(int n, String singular, {String? plural}) =>
    '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

/// One or two letters for an avatar — the clay [InitialsDisc]'s own rule, so the initials a
/// sheet prints and the ones every disc in the app draws cannot disagree. Never more than two:
/// three initials in a circle is unreadable at the size a list row allows.
String initials(String fullName) => InitialsDisc.initialsFor(fullName);

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC COLOUR
// ─────────────────────────────────────────────────────────────────────────────

/// What a colour MEANS on a warden screen, so no screen has to decide for itself.
///
/// The rule: red is not "bad", it is "you have to do something". An unpaid fee and an open
/// complaint are red because they are work; a checked-out resident is grey because they are
/// simply not here any more.
///
/// THE RETURN IS RESOLVED FOR THE CURRENT THEME, not canonical. The switch names the meaning
/// with [ApnivaasColors.success] and friends, which is what makes it readable; `context.tones`
/// then swaps in the value that is legible on THIS theme's surfaces. Skipping that step is
/// what every status pill in the app was doing, and canonical `success` #188D43 measures
/// 3.87:1 as text on the dark elevated surface — a fail, in the one place the app uses colour
/// to carry a state.
Color toneFor(BuildContext context, WireValue status) {
  final t = Theme.of(context);
  return context.tones.resolve(switch (status) {
    FeeStatus.paid => ApnivaasColors.success,
    FeeStatus.partial => ApnivaasColors.warning,
    FeeStatus.unpaid => ApnivaasColors.error,
    ComplaintStatus.open => ApnivaasColors.error,
    ComplaintStatus.inProgress => ApnivaasColors.warning,
    ComplaintStatus.resolved => ApnivaasColors.success,
    StudentStatus.active => ApnivaasColors.success,
    StudentStatus.onLeave => ApnivaasColors.warning,
    StudentStatus.vacated => t.colorScheme.onSurfaceVariant,
    BedStatus.free => ApnivaasColors.success,
    BedStatus.occupied => t.colorScheme.primary,
    SubscriptionState.active => ApnivaasColors.success,
    SubscriptionState.expiring => ApnivaasColors.warning,
    SubscriptionState.expired => ApnivaasColors.error,
    _ => t.colorScheme.primary,
  });
}

/// The same meanings as [toneFor], named the way the clay [StatusChip] takes them.
///
/// Two functions rather than one because they answer for two different objects: [toneFor] gives
/// a colour to paint a glyph or a figure in, this gives the chip its tone and lets the chip
/// resolve its own ink and tint. They must never disagree, which is why they sit side by side.
StatusTone statusToneOf(WireValue status) => switch (status) {
      FeeStatus.paid ||
      ComplaintStatus.resolved ||
      StudentStatus.active ||
      BedStatus.free ||
      SubscriptionState.active =>
        StatusTone.success,
      FeeStatus.partial ||
      ComplaintStatus.inProgress ||
      StudentStatus.onLeave ||
      SubscriptionState.expiring =>
        StatusTone.warning,
      FeeStatus.unpaid || ComplaintStatus.open || SubscriptionState.expired => StatusTone.error,
      StudentStatus.vacated => StatusTone.neutral,
      _ => StatusTone.brand,
    };

/// A small round dot in a semantic tone.
///
/// The design's own status marker — `flex h-2 w-2 rounded-full bg-error` in the Stitch HTML,
/// which is [Space.xs] across. It appears wherever the mockups label a state: `● OCCUPIED` on
/// the rooms summary, `● IN PROGRESS` in the ticket header, `● Available Now` on a free bed.
/// Shape as well as colour, so the state survives a reader who cannot separate the hues.
class ToneDot extends StatelessWidget {
  const ToneDot({super.key, required this.tone, this.size = Space.xs});

  final Color tone;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          // Gold on the brow, for the same reason SaBrandDot is: the header's indicator dot
          // is the brand, and the brow is the brand. Gold is the brow's ribbon, 3.32:1 on its
          // lightest stop. Only this one call site is ever on a brow; every other ToneDot marks
          // a domain on a card and keeps its tone.
          color: BrowScope.of(context) ? BrowInk.gold : tone,
          shape: BoxShape.circle,
        ),
      );
}

/// A status, said once, the same way everywhere.
///
/// Takes the enum rather than a string so the wording comes from [WireValue.label] — the same
/// text the web app shows for the same row — and the tone from [statusToneOf]. The `.text`
/// variant is for the handful of states that are not a database enum ("No bed", "3 free").
///
/// IT IS THE CLAY [StatusChip] NOW: a pill with a 10% tint of its tone and the word in that
/// tone's text ink, Manrope 12/16 bold, in sentence case. The old shape — a 4px-cornered box
/// with a full-strength border and the word in capitals — shouted on a list where every row
/// carries one; a chip says the same thing at a speaking volume, and the word is still the cue
/// a colour-blind reader needs ("Overdue" says overdue without the red).
class StatusPill extends StatelessWidget {
  // A named parameter cannot be private, so the enum cannot arrive as an initializing formal
  // for `_status`; it has to be copied across in the initialiser list.
  const StatusPill({super.key, required WireValue status, this.dot = false})
      : _status = status, // ignore: prefer_initializing_formals
        label = null,
        tone = null;

  const StatusPill.text({
    super.key,
    required this.label,
    required this.tone,
    this.dot = false,
  }) : _status = null;

  final WireValue? _status;
  final String? label;

  /// Canonical or theme-resolved — either is matched back to its [StatusTone] here, so a caller
  /// keeps naming the meaning. The scheme's primary reads as the brand; anything else unknown is
  /// drawn neutral rather than guessed at.
  final Color? tone;

  /// Opt back into the leading dot for the one case that still earns it: a chip whose label is
  /// a COUNT rather than a state name ("3 free"), where the words carry no colour meaning of
  /// their own.
  final bool dot;

  static StatusTone _toneOfColor(BuildContext context, Color? colour) {
    if (colour == null) return StatusTone.neutral;
    if (colour == Theme.of(context).colorScheme.primary) return StatusTone.brand;
    final tones = context.tones;
    for (final tone in StatusTone.values) {
      if (colour == tone.canonical || colour == tones.resolve(tone.canonical)) return tone;
    }
    return StatusTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return StatusChip(
      label: label ?? status!.label,
      tone: status != null ? statusToneOf(status) : _toneOfColor(context, tone),
      dot: dot,
    );
  }
}

/// A row of filter chips: one is on, the rest are a tap away.
///
/// The SELECTED chip is filled forest with its label in white — the one solid fill on a list
/// screen, which is what tells you which list you are looking at from across a corridor. The
/// rest sit on the card fill behind the card hairline with a quiet label, so they read as
/// choices rather than as a second row of buttons.
///
/// It replaces Material's [ChoiceChip]: the stock chip is a 32dp capsule with a check mark that
/// slides in, in the scheme's `secondaryContainer`, which is nobody's idea of this app.
class FilterBar<T> extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> options;
  final T selected;
  final String Function(T option) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: FilterPill(
                label: labelOf(option),
                selected: option == selected,
                onTap: () => onSelected(option),
              ),
            ),
        ],
      ),
    );
  }
}

/// One chip of a [FilterBar]. Public because two screens filter on something that is not a
/// single enum (a nullable status, a month) and build their own row.
///
/// 36dp to the eye and 48 to the finger: the button pads its own hit area out to the floor
/// ([MaterialTapTargetSize.padded]) without drawing a fat capsule to get there.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// The chip's painted height. The target around it is the 48dp floor.
  static const height = 36.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected ? scheme.primary : scheme.surface,
          foregroundColor: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          minimumSize: const Size(0, height),
          padding: const EdgeInsets.symmetric(horizontal: Space.md - Space.xxs),
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: Strokes.hairline,
            ),
          ),
          // The row-title step in sentence case, the same type the clay PillButton sets; the
          // tabular figures it carries for numbers have no business in a word.
          textStyle: t.textTheme.titleSmall?.copyWith(fontFeatures: const []),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

/// A warden screen: the forest header, then content.
///
/// The header is the brow every role's screens open with — the forest gradient with its few
/// soft stars and the rounded bottom edge — drawn by [GlassHeader.onBrow], which also owns the
/// status-bar inset so no screen re-derives it. It is a bar the content scrolls beneath, not an
/// AppBar. On it: the small gold brand dot, the page name, an optional second line, and the
/// screen's own controls at the trailing edge.
///
/// [subtitle] is for real second facts — the month a ledger is showing, the term a list is
/// filtered by — because the alternative is a header that cannot say which month you are
/// looking at.
///
/// The home tab does not use this: it opens with the clay [AppHeader] (greeting, avatar and the
/// search pill), the shape every role's home shares. A tab keeps its title here, because a
/// masthead on "Rooms" or "Complaints" would take away the one thing telling you which of five
/// tabs you are standing in.
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
    return Column(
      children: [
        GlassHeader(
          onBrow: true,
          // Strings into BrowTitleBlock, never Text with the theme's titleMedium/bodySmall:
          // those carry the theme's ink and beat the brow's white. See BrowText.
          child: BrowTitleBlock(
            // The brand disc in front of the page name. Gold on the brow; see ToneDot.
            leading: const ToneDot(tone: ApnivaasColors.primary),
            title: title,
            subtitle: subtitle,
            actions: actions,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The heading over a section of a page or a sheet: Outfit at the form step, in the theme's
/// ink, sentence case, with an optional trailing fact ("2 free", "8 residents").
///
/// It is the clay [SectionHeader] — a semantics header, so a screen reader can jump between
/// sections — at the size a heading INSIDE a screen takes. The page's own title is the header
/// above it and the home's section titles are a step larger; three sizes, each saying how much
/// of the page it governs. It used to be an 11px caps whisper, which on a cream page read as a
/// caption that had lost its picture.
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Space.lg, 0, Space.sm),
      child: SectionHeader(title: label, size: SectionHeaderSize.form, trailing: trailing),
    );
  }
}

/// The small heading the design puts INSIDE a card, over the thing it names — "Paid by", "This
/// month", "Current assignment", or the word over a figure.
///
/// SENTENCE CASE, as it is everywhere in the clay system. This was `label-caps` — an 11px
/// upper-cased eyebrow — which the canvas retired: capitals at that size read as a caption that
/// has lost its picture, and they are slower to read than the words they shout. It is
/// [TextTheme.labelMedium] (Manrope 12/16 bold) in the theme's secondary ink, so it ranks under
/// the row title it sits above without disappearing into the body text beside it.
class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(this.label, {super.key, this.tone, this.dot = false});

  final String label;

  /// Canonical or resolved. Null takes the theme's secondary text colour, which is what the
  /// design's own muted labels use.
  final Color? tone;

  /// Marks a summary figure's label with its state's dot — "● Occupied", "● Free" — so the
  /// label is also the legend for whatever is painted in that colour nearby.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot && accent != null) ...[
          ToneDot(tone: accent, size: Space.tight),
          const SizedBox(width: Space.tight),
        ],
        Flexible(
          child: Text(
            label,
            style: t.textTheme.labelMedium?.copyWith(
              color: accent ?? t.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A round icon control: 44 to the eye, 48 to the finger, with its name as a tooltip and as
/// what a screen reader says.
///
/// ON THE FOREST HEADER it is the clay [HeaderIconButton] — white glyph on white at 8% inside a
/// faint ring — so a warden tab's controls are the same object as the home header's. ON THE
/// PAGE (the month stepper over the ledger) the same circle is drawn on the card fill behind the
/// card hairline with the glyph in the theme's ink. [badge] is the gold unread dot, shown only
/// when there is something to alert about, because a dot that is always on is decoration.
class HeaderAction extends StatelessWidget {
  const HeaderAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    if (BrowScope.of(context)) {
      return HeaderIconButton(
        icon: icon,
        label: tooltip,
        onPressed: onPressed,
        hasUnread: badge,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: onPressed,
          radius: Space.huge / 2,
          child: SizedBox.square(
            dimension: Space.huge,
            child: Center(
              child: Container(
                width: HeaderIconButton.size,
                height: HeaderIconButton.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surface,
                  border: Border.all(color: scheme.outlineVariant, width: Strokes.hairline),
                ),
                child: Icon(
                  icon,
                  size: IconSize.lg,
                  color: enabled
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant.withValues(alpha: Dim.readOnly),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An aside: a glyph and a sentence on a quiet fill.
///
/// NEUTRAL BY DEFAULT — the clay [InfoNote]'s fill and radius, the glyph and the words in the
/// strong secondary ink — for the notes that explain rather than warn ("No app login is linked
/// to this resident"). [tone] tints the whole aside for one that carries a WARNING instead — a
/// refusal the server explained, a write that cannot be undone — at the measured chip tint, with
/// the glyph and the [title] in that tone's text ink.
class InfoCallout extends StatelessWidget {
  const InfoCallout({
    super.key,
    required this.icon,
    required this.child,
    this.tone,
    this.title,
  });

  final IconData icon;
  final Widget child;
  final String? title;

  /// Null draws the neutral note.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final accent = tone == null ? t.colorScheme.onSurfaceVariant : tones.resolve(tone!);
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tone == null ? t.colorScheme.surfaceContainerHighest : tones.chipFill(accent),
        borderRadius: Radii.rButton,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.hair),
            child: Icon(icon, size: IconSize.md, color: accent),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: title == null
                ? child
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: t.textTheme.titleSmall?.copyWith(color: accent)),
                      const SizedBox(height: Space.hair),
                      child,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The glyph at the head of a confirmation: a tinted disc with the glyph in its tone.
///
/// The check-out and assign confirmations open with it. It is the one ornament a question
/// sheet allows itself, drawn at the size a compact empty state's art takes so that "are you
/// sure", "nothing here" and "that worked" are one size of event.
class StateHalo extends StatelessWidget {
  const StateHalo({super.key, required this.icon, this.tone});

  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final accent = context.tones.resolve(tone ?? Theme.of(context).colorScheme.primary);
    return Container(
      width: ClaySize.banner,
      height: ClaySize.banner,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.tones.chipFill(accent), shape: BoxShape.circle),
      child: Icon(icon, size: IconSize.xl, color: accent),
    );
  }
}

/// Nothing to show — said in words that tell the warden whether that is good news.
///
/// The kit's [EmptyState] with a choice made for it: given a picture it IS that widget, and
/// without one it draws the same anatomy around a glyph. Its own name, so a warden screen can
/// import the whole clay kit without hiding anything.
///
/// THE CLAY EMPTY STATE'S ANATOMY: a Mist disc with the picture on it, a title, one helpful
/// sentence. What goes on the disc says which KIND of empty this is:
///
///  * a first-run state draws clay art — its [illustration]'s ([EmptyArt.clayFor]), or an
///    [art] path for the states that have no EmptyArt name — "nothing here YET";
///  * an empty that is GOOD news ([tone] success — every complaint resolved, every leave
///    decided) draws the clay success art;
///  * anything else — a search or a filter that matched nothing — keeps its Material [icon]
///    in forest on the disc, because artwork means "nothing here yet", which is not what "no
///    match for that" means.
///
/// The words are real Text either way, so they stay translatable and selectable.
class WardenEmptyState extends StatelessWidget {
  const WardenEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.tone,
    this.illustration,
    this.art,
    this.compact = false,
  });
  final IconData icon;
  final String title;
  final String? detail;

  /// A clay path drawn instead of the glyph, for a first-run state with no [EmptyArt] name of
  /// its own (a building with no rooms set up yet).
  final String? art;

  /// An [EmptyArt] state whose clay art is drawn INSTEAD of the glyph.
  ///
  /// Only the states a brand-new account lands on get one. [icon] stays required either way,
  /// because it is what every other kind of empty draws.
  final String? illustration;

  /// Null is the neutral "nothing here". Pass [ApnivaasColors.success] where an empty list is the
  /// good outcome — every complaint resolved, every leave decided.
  final Color? tone;

  /// The in-card size — for a sheet, or a section of a page that has other things in it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final goodNews = tone != null && context.tones.resolve(tone!) == context.tones.success;
    final picture = art ??
        (illustration != null
            ? EmptyArt.clayFor(illustration!)
            : goodNews
                ? ClayIcons.success
                : null);
    if (picture != null) {
      return EmptyState(icon: picture, title: title, body: detail, compact: compact);
    }

    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final disc = compact ? ClaySize.promo : ArtSize.emptyDisc;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: EmptyState.maxWidth),
        child: Padding(
          padding: EdgeInsets.all(compact ? Space.md : Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: disc,
                  height: disc,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark ? ApnivaasColors.darkMist : ApnivaasColors.mist,
                    shape: BoxShape.circle,
                  ),
                  child: ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: compact ? IconSize.xl : Space.huge,
                      color: t.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? Space.sm : Space.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: compact
                    ? t.textTheme.titleMedium
                    : t.textTheme.headlineSmall?.copyWith(fontFeatures: const []),
              ),
              if (detail != null) ...[
                const SizedBox(height: Space.tight),
                Text(detail!, textAlign: TextAlign.center, style: t.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// WHICH KIND OF FAILURE, IN TWO WORDS — the job the design gives the caps badge on its error
/// card. The sentence underneath is the repository's own and is never paraphrased.
///
/// A free function rather than a local inside [FailureState.build] because it is a claim about
/// the reader's situation and claims want tests. "Not allowed" is the accusing one, and it was
/// worth being able to assert in `flutter test` that a warden whose token expired at the desk
/// mid-shift is never shown it: nothing has been refused, the sign-in simply ran out, and the
/// badge is the first thing on the card anybody reads.
String failureBadge(AppFailure failure) => switch (failure) {
      OfflineFailure() => 'Offline',
      AccessDeniedFailure() => 'Not allowed',
      ReadOnlyFailure() => 'Read only',
      NotFoundFailure() => 'Not found',
      SessionExpiredFailure() || SignedOutFailure() => 'Signed out',
      _ => 'Failed',
    };

/// A failed load, told in the database's own words where it had any.
///
/// [AppFailure] already distinguishes "no signal" from "you are not allowed" from "the
/// subscription lapsed"; the retry button appears only where retrying could actually work,
/// because a button that cannot help is worse than no button.
///
/// It stays a card with a caps badge on it, unlike [WardenEmptyState]: the badge names the KIND of
/// failure in two words before anyone reads the sentence (see [failureBadge]), and a failure is
/// an event on the page rather than the page having nothing to say. No glyph — the sentence is
/// the message.
class FailureState extends StatelessWidget {
  const FailureState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failure = AppFailure.from(error);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: StateCard(
        badge: failureBadge(failure),
        tone: ApnivaasColors.error,
        child: StateBody(
          title: failure.message,
          // A dead sign-in is neither retryable nor a refusal — it is the one failure with a
          // one-tap fix, and a warden at the desk must not have to hunt a menu for it.
          action: failure.needsSignIn
              ? const SignInAgainButton()
              : onRetry != null && failure.isRetryable
                  ? FilledButton(onPressed: onRetry, child: const Text('Try again'))
                  : null,
        ),
      ),
    );
  }
}

/// A confirmation: a picture on a Mist disc, a headline, a sentence, a summary of what was
/// written, and the ways on from here.
///
/// The summary is label/value rows under a small caps heading, and every value passed to it
/// comes from what the SERVER returned, never from what a form was holding.
class SuccessPanel extends StatelessWidget {
  const SuccessPanel({
    super.key,
    required this.title,
    required this.message,
    this.summaryTitle,
    this.summary = const <(String, String)>[],
    this.tone,
    this.art,
    this.actions = const <Widget>[],
  });

  final String title;
  final String message;
  final String? summaryTitle;

  /// Label / value pairs, drawn the quiet label left, the emphasised value right.
  final List<(String, String)> summary;

  /// The tone of the tick drawn when there is no [art].
  final Color? tone;

  /// A clay path for the disc — the receipt for a payment, say. Null draws a tick in [tone].
  final String? art;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final picture = art;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: picture == null
              ? StateHalo(
                  icon: Icons.check_circle_outline_rounded,
                  tone: tone ?? ApnivaasColors.success,
                )
              : Container(
                  width: ClaySize.promo,
                  height: ClaySize.promo,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dark ? ApnivaasColors.darkMist : ApnivaasColors.mist,
                    shape: BoxShape.circle,
                  ),
                  child: ClayIcon(picture, size: ClaySize.banner),
                ),
        ),
        const SizedBox(height: Space.md),
        Text(title, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: Space.xxs),
        Text(message, style: t.textTheme.bodyMedium, textAlign: TextAlign.center),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          FlatSurface(
            weight: GlassWeight.regular,
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summaryTitle != null) ...[
                  EyebrowLabel(summaryTitle!),
                  const SizedBox(height: Space.xs),
                  Divider(color: t.colorScheme.outlineVariant, height: Strokes.hairline),
                  const SizedBox(height: Space.xs),
                ],
                for (final (label, value) in summary)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: Text(label, style: t.textTheme.bodySmall)),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          flex: 6,
                          child: Text(
                            value,
                            textAlign: TextAlign.right,
                            style: t.textTheme.titleSmall?.copyWith(
                              color: t.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        for (final action in actions) ...[
          const SizedBox(height: Space.xs),
          action,
        ],
      ],
    );
  }
}

/// A card-shaped placeholder for a section that has not arrived.
///
/// It keeps the card's shape on screen so the page does not jump when the figures land, and —
/// unlike a spinner — it says WHERE the missing thing will be. The bars are the clay
/// [Skeleton]'s, under one [SkeletonPulse] for the card: one live region saying "Loading", one
/// slow breath, still for anyone who asked the system for less motion.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({super.key, this.lines = 2});

  final int lines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SkeletonPulse(
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: Radii.rCard,
          border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Skeleton(widthFactor: 0.35, height: Space.sm),
            const SizedBox(height: Space.sm),
            for (var i = 0; i < lines; i++) ...[
              Skeleton(widthFactor: i.isEven ? 1 : 0.6, height: Space.md - Space.xxs / 2),
              if (i != lines - 1) const SizedBox(height: Space.xs),
            ],
          ],
        ),
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
    // ── THE ONE PLACE THE WHOLE APP GAINS AN ARRIVAL ────────────────────────────────────
    // This used to return the three branches directly, so a skeleton was present on one frame
    // and the rows were present on the next. See shared/motion/settle.dart for why that single
    // instant substitution is most of what the owner noticed against the competitor, and why
    // the fix belongs here rather than at the 31 call sites.
    if (value.hasValue) {
      return Settle(state: 'data', child: builder(value.requireValue));
    }
    if (value.hasError) {
      return Settle(state: 'error', child: FailureState(error: value.error!, onRetry: onRetry));
    }
    return Settle(state: 'loading', child: loading ?? const _Spinner());
  }
}

/// What a section looks like before it has anything to say, when its caller has no shape of its
/// own to offer: three rows' worth of the clay list skeleton. Rows rather than a spinner,
/// because nearly everything a warden waits for is a list.
class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.md),
        child: ListSkeleton(rows: 3),
      );
}

/// The spinner that stands in for a control while a write is in flight.
///
/// It exists because the same `SizedBox(width: 20, height: 20, child:
/// CircularProgressIndicator(strokeWidth: 2))` had been written out six times across the
/// warden sheets, at 18 in three of them and 20 in the other three. A busy indicator that
/// changes size between two sheets is the kind of difference nobody can name and everybody
/// notices. [replacing] keeps the row from collapsing when the control it stands in for is a
/// button with a height.
class InlineSpinner extends StatelessWidget {
  const InlineSpinner({super.key, this.replacing, this.onFill});

  /// A hairline is invisible on a spinner and 3 reads as a loading screen. 2 is the one this
  /// app uses, in one place.
  static const stroke = 2.0;

  /// The height of the control being stood in for, so the layout does not jump.
  final double? replacing;

  /// Pass `colorScheme.onPrimary` when the spinner sits INSIDE a filled button. The progress
  /// theme paints `scheme.primary`, which is that button's own fill — so the default spinner
  /// is forest on forest and invisible for the whole of the write it is reporting.
  final Color? onFill;

  @override
  Widget build(BuildContext context) {
    final dot = SizedBox(
      width: IconSize.lg,
      height: IconSize.lg,
      child: CircularProgressIndicator(strokeWidth: stroke, color: onFill),
    );
    if (replacing == null) return dot;
    return SizedBox(height: replacing, child: Center(child: dot));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLS
// ─────────────────────────────────────────────────────────────────────────────

/// A row sized for a thumb: 64dp minimum, the whole width tappable, in its own card.
///
/// The clay card — the card fill, the card radius, one hairline, flat at rest — for the rows a
/// sheet builds by hand (a bed, a visitor, a leave request). Whole-screen lists use the clay
/// [ListRowCard] instead, which brings its own art slot and chevron.
class TapRow extends StatelessWidget {
  const TapRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Space.sm + Space.hair,
      vertical: Space.sm,
    ),
    this.semanticLabel,
    this.tone,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  /// Draws the row's edge in a semantic tone instead of the neutral hairline — the way a row
  /// says it is selectable or that it needs attention. Canonical or resolved.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final edge = tone == null
        ? t.colorScheme.outlineVariant
        : context.tones.chipBorder(context.tones.resolve(tone!));
    final row = Material(
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.rCard,
        side: BorderSide(color: edge, width: Strokes.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    return semanticLabel == null
        ? row
        : Semantics(label: semanticLabel, button: onTap != null, container: true, child: row);
  }
}

/// Initials on a Mist disc, in forest. No photo: students.photo_url is a private storage KEY,
/// not a URL, and showing a broken image is worse than showing none.
///
/// The clay [InitialsDisc], so a resident's face is the same object on every screen and sheet
/// in the app. It carries no status colour: the state is said by the chip beside the name, and
/// a disc tinted red for "unpaid" was a second, louder copy of the same fact.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = Space.xxxl});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => InitialsDisc(name: name, size: size);
}

/// The mockups' metadata line: small muted glyphs, each with the value it labels.
///
/// warden-maintenance-dashboard.png sets every ticket's second line this way —
/// `📍 Room 102, Floor 2   👤 Rahul Sharma` — and resident-profile.png repeats it under the
/// current assignment. It reads faster than the `a · b · c` string this feature used, because
/// the glyph says which kind of fact each value is before you read the value.
///
/// It wraps rather than truncating: at 1.4x text scale two facts do not fit on one line of a
/// 320dp phone, and dropping the second one silently is worse than a second line.
class MetaLine extends StatelessWidget {
  const MetaLine(this.facts, {super.key});

  /// Glyph and value, in reading order. A null value is left out entirely — there is no
  /// placeholder dash, because a fact the app does not have is not a fact.
  final List<(IconData, String?)> facts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final shown = [
      for (final (icon, value) in facts)
        if (value != null && value.isNotEmpty) (icon, value),
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (icon, value) in shown)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: IconSize.xs, color: t.colorScheme.onSurfaceVariant),
              const SizedBox(width: Space.xxs),
              Text(value, style: t.textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

/// A labelled value on a resident's sheet.
///
/// Two columns on one line: the field name left in the secondary ink, the answer right in the
/// theme's ink at the row-title weight. Weight and colour separate them, not size or position.
/// The label wraps rather than truncating and the value is given the wider half, which is what
/// keeps a phone number and an address readable at large text.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.tone});
  final String label;
  final String value;

  /// Tints the value where the field carries a meaning — an outstanding balance, a check-out
  /// date. The design does exactly this with "Outstanding Amount" (4:813). Canonical or
  /// resolved.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs - Space.xxs / 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: t.textTheme.bodyMedium),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: t.textTheme.titleSmall?.copyWith(
                color: accent ?? t.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The title of a bottom sheet: the clay [SheetTitle]'s type, with room for a face and a state.
///
/// Outfit at the title step with the second line under it in the muted ink, an optional
/// [leading] (a resident's initials) and the state chip pushed to the trailing edge. Sheets that
/// are about a room or a queue rather than a person leave [leading] off.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // No drag handle here. showGlassSheet draws one, on the pane, for every sheet in the app.
    return Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: Space.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: t.textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Space.hair),
                Text(
                  subtitle!,
                  style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Space.xs),
          trailing!,
        ],
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
    if (!context.mounted) return false;
    showFailureSnack(context, error);
    return false;
  }
}

/// Says that something failed, in the words the database or the Edge Function used.
///
/// SPLIT OUT OF [runAction] rather than copied, because a second caller appeared: registering a
/// resident cannot go through runAction — it needs the RESULT of the write (the one-time
/// password) and it has an outcome that is neither success nor exception (a rejection the
/// server explained field by field). Two snackbars that drift apart in colour or duration is
/// exactly the difference nobody can name and everybody notices.
void showFailureSnack(BuildContext context, Object error) {
  final failure = AppFailure.from(error);
  // The snackbar keeps its themed background and says "this failed" with an icon instead.
  // Repainting the whole bar #DC3F3F put the message at 4.35:1 against its own white text — the
  // one message in the app that most needs reading.
  //
  // The bar is the theme's INVERSE surface — ink in the light theme, cream in the dark one —
  // so the glyph's red is picked against the bar, not against the page: the dark theme's error
  // ink on the light theme's ink bar (6.17:1), the light theme's on the dark theme's cream bar
  // (5.70:1).
  final onInkBar = Theme.of(context).brightness == Brightness.light;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(
      children: [
        Icon(Icons.error_outline_rounded,
            size: IconSize.md,
            color: onInkBar ? ApnivaasColors.errorDark : ApnivaasColors.errorInk),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(failure.message)),
      ],
    ),
    behavior: SnackBarBehavior.floating,
    duration: Motion.readMessage,
  ));
}
