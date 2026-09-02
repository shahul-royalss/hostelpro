library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/sign_in_again.dart';

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
///
/// THE RETURN IS RESOLVED FOR THE CURRENT THEME, not canonical. The switch names the meaning
/// with [NivoraColors.success] and friends, which is what makes it readable; `context.tones`
/// then swaps in the value that is legible on THIS theme's surfaces. Skipping that step is
/// what every status pill in the app was doing, and canonical `success` #188D43 measures
/// 3.87:1 as text on the dark elevated surface — a fail, in the one place the app uses colour
/// to carry a state.
Color toneFor(BuildContext context, WireValue status) {
  final t = Theme.of(context);
  return context.tones.resolve(switch (status) {
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
  });
}

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
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      );
}

/// A tinted circle with an icon in it — the design's `bg-TONE/10 p-2 rounded-full text-TONE`,
/// which is [NivoraSemantics.chipFill] at the exact tint the palette measured.
///
/// It is the mockups' most repeated ornament: the leading badge on a stat tile, the glyph
/// beside each row of PERSONAL DETAILS, the circle behind a Quick Action, the disc behind an
/// assigned technician. [square] switches to [Radii.rControl] for the places the design uses a
/// rounded square instead — the checklist rows on move-out-inspection.png.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.tone,
    this.size = Space.xxxl,
    this.iconSize = IconSize.lg,
    this.square = false,
  });

  final IconData icon;

  /// Canonical or resolved — resolved here either way, so a caller can keep naming the meaning.
  final Color? tone;
  final double size;
  final double iconSize;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final accent = context.tones.resolve(tone ?? Theme.of(context).colorScheme.primary);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.tones.chipFill(accent),
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? Radii.rControl : null,
      ),
      child: Icon(icon, size: iconSize, color: accent),
    );
  }
}

/// The design's badge geometry — `px-[6px] py-[2px] rounded-[4px]`, which is what every
/// status badge in the file is drawn at (4:767 PAID, 4:775 OVERDUE, 4:783 PARTIAL, 4:715
/// MAINTENANCE, 4:802 on the resident sheet).
const _badgeInset = EdgeInsets.symmetric(
  horizontal: Space.xxs + Space.xxs / 2,
  vertical: Space.xxs / 2,
);

/// A status, said once, the same way everywhere.
///
/// Takes the enum rather than a string so the wording comes from [WireValue.label] — the same
/// text the web app shows for the same row — and the colour from [toneFor]. The `.text` variant
/// is for the handful of states that are not a database enum ("No bed", "3 free").
///
/// THE SHAPE IS FIGMA'S STATUS BADGE, NOT A PILL. `screen-warden-students-list` (4:723) puts
/// one on every row and they are all the same object: a 4px-cornered rectangle, 6/2 padding,
/// the tone at 10% behind a full-strength 1px border of the tone, and the label uppercase in
/// the tone. No dot, and no capsule. The dot went because the label is already the redundant
/// cue a colour-blind reader needs — "OVERDUE" says overdue — and a dot in front of it was
/// stealing four points of the six the badge has to spare at 320dp.
///
/// [labelSmall] is the design's chip step (10/600 at +0.05em). The file draws these at 9px;
/// 9 is below the size a semibold uppercase label survives real text-scaling at, and the two
/// are indistinguishable at 1.0x. `.text` leaves its label's case alone, because what gets
/// passed there is a count or a phrase rather than a state, and "2 OF 3 OCCUPIED" is shouting.
class StatusPill extends StatelessWidget {
  // A named parameter cannot be private, so the enum cannot arrive as an initializing formal
  // for `_status`; it has to be copied across in the initialiser list.
  const StatusPill({super.key, required WireValue status, this.dot = false})
      : _status = status, // ignore: prefer_initializing_formals
        label = null,
        tone = null,
        _upper = true;

  const StatusPill.text({
    super.key,
    required this.label,
    required this.tone,
    this.dot = false,
  })  : _status = null,
        _upper = false;

  final WireValue? _status;
  final String? label;
  final Color? tone;

  /// Opt back into the leading dot for the one case that still earns it: a badge whose label
  /// is a COUNT rather than a state name ("3 free"), where the words carry no colour meaning
  /// of their own.
  final bool dot;

  final bool _upper;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final status = _status;
    // A `tone:` handed in from a screen is still canonical, so resolve it here too rather than
    // trusting the caller. resolve() passes an already-resolved colour through unchanged.
    final accent = tones.resolve(tone ?? toneFor(context, status!));
    final raw = label ?? status!.label;
    return Container(
      padding: _badgeInset,
      decoration: BoxDecoration(
        // chipFill, not a plausible-looking 0.12. The tint lightens the pane toward the text
        // sitting on it, so 0.12 measured 3.29:1 at worst — the alphas live in one place
        // precisely so a chip cannot be drawn at a number nobody measured.
        color: tones.chipFill(accent),
        borderRadius: Radii.rTiny,
        border: Border.all(color: tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            ToneDot(tone: accent, size: Space.xxs + Space.xxs / 2),
            const SizedBox(width: Space.xxs),
          ],
          Flexible(
            child: Text(
              _upper ? raw.toUpperCase() : raw,
              style: t.textTheme.labelSmall?.copyWith(color: accent),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's filter bar — `filter-bar` (4:660) on the dashboard and `chips` (4:747) on the
/// students list are the same object twice.
///
/// A row of `rounded-[100px]` chips, `px-[12px] py-[6px]`, label at 12/600. The SELECTED one is
/// filled with the gold and its label is the ground colour; the rest are the raised surface
/// behind the hairline with a secondary label. That is the app's one full-strength gold fill
/// outside the FAB, and it is what tells you which list you are looking at from across a
/// corridor.
///
/// It replaces Material's [ChoiceChip], which this feature used on three screens: the stock
/// chip is a 32dp capsule with a check mark that slides in, in the scheme's `secondaryContainer`
/// — none of which is in the file.
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? t.colorScheme.primary : t.colorScheme.surfaceContainer,
        borderRadius: Radii.rPill,
        child: InkWell(
          borderRadius: Radii.rPill,
          onTap: onTap,
          child: Container(
            // The design's chip is 30dp tall. 44 is the smallest target a warden holding a
            // phone one-handed hits reliably, and it is what the rest of this app's controls
            // already stand on.
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            decoration: BoxDecoration(
              borderRadius: Radii.rPill,
              border: Border.all(
                color: selected ? t.colorScheme.primary : t.colorScheme.outlineVariant,
                width: Strokes.hairline,
              ),
            ),
            child: Text(
              label,
              // labelMedium IS the design's 12/600, but the scale gives it the +0.05em
              // tracking a CAPS label needs. A chip label is sentence case ("On Leave"), and
              // caps tracking on sentence case reads as a spacing bug.
              style: t.textTheme.labelMedium?.copyWith(
                color: selected ? t.colorScheme.onPrimary : t.colorScheme.onSurfaceVariant,
                letterSpacing: 0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

/// A warden screen: the design's header bar, then content.
///
/// THE HEADER IS NODE 4:651 / 4:734, AND THE TWO ARE IDENTICAL. 56dp high with a bottom
/// hairline and nothing else — a small brand dot, the page name at 16/700 cream, and the
/// screen's controls as square icon buttons on the right. It is a bar content scrolls beneath,
/// not an AppBar; see GlassHeader, which owns the status-bar inset so no screen re-derives it.
///
/// WHAT WENT: the 20/700 title and the coloured `eyebrow` above it. Neither is in the file.
/// Figma's header carries one line of type, and the caps eyebrows it does draw are SECTION
/// headings down in the body ("QUICK ACTIONS", "RECENT COMPLAINTS") — that is [SectionLabel].
/// A screen that wants to say "Rent" now says it where the design says it.
///
/// [subtitle] survives as the design's 11/400 meta line because the app has real second facts
/// for it — the hostel's name, the month a ledger is showing — and the alternative is a header
/// that cannot say which month you are looking at.
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // `avatar-indicator` (4:654, 4:737): an 8px gold disc in front of the
                        // page name, on every warden frame in the file.
                        const ToneDot(tone: NivoraColors.primary),
                        const SizedBox(width: Space.xxs + Space.xxs / 2),
                        Flexible(
                          child: Text(
                            title,
                            style: t.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
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

/// The heading over a section of the page — `quick-actions-section` (4:691) and
/// `complaints-section` (4:708), which are the same object: 11px semibold, UPPERCASE, in the
/// quiet ink, with nothing else on the line.
///
/// IT USED TO BE A 20/700 GOLD TITLE WITH A RULE RUNNING OFF TO THE RIGHT. That came from the
/// superseded Stitch screens, and it is the single biggest reason the warden pages read louder
/// than the file does: Figma's sections are announced in a whisper and the CONTENT is what is
/// bold. The gold is spent on one thing per screen — the active filter chip — and a page with
/// four gold headings on it has nowhere left to put emphasis.
///
/// [trailing] survives for the floor summaries on the room grid, which the design's own list
/// headers do the same thing with ("STUDENT DIRECTORY … 48 students", 4:757).
class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Space.lg, 0, Space.sm),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: t.textTheme.labelMedium?.copyWith(color: context.tones.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// `label-caps`: the small uppercase heading the design puts INSIDE a card.
///
/// "TOTAL BEDS", "CURRENT ASSIGNMENT", "PERSONAL DETAILS", "ASSIGNMENT SUMMARY", "SELECTED
/// BED". [labelSmall] is that token exactly; a TextStyle cannot change case, so this does.
class CapsLabel extends StatelessWidget {
  const CapsLabel(this.label, {super.key, this.tone, this.dot = false});

  final String label;

  /// Canonical or resolved. Null takes the theme's secondary text colour, which is what the
  /// design's own muted eyebrows use.
  final Color? tone;

  /// The design marks a summary figure's label with its state's dot — `● OCCUPIED`, `● FREE`,
  /// `● MAINTENANCE` across the top of rooms-beds-directory.png.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot && accent != null) ...[
          ToneDot(tone: accent, size: Space.xxs + Space.xxs / 2),
          const SizedBox(width: Space.xxs + Space.xxs / 2),
        ],
        Flexible(
          child: Text(
            label.toUpperCase(),
            style: t.textTheme.labelSmall?.copyWith(color: accent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// One figure on the dashboard, in the shape `stats-grid` draws it (4:671, 4:676, 4:681,
/// 4:685).
///
/// `bg-[#111417] border border-[#292e33] p-[12px] gap-[4px]`, and inside it exactly three
/// things stacked: a 10px UPPERCASE eyebrow in the quiet ink, the figure at 16/700 in the
/// tone, and one 10px supporting line. Nothing else — no icon, no disc, no chrome.
///
/// WHAT WENT AND WHY. The tile used to lead with a 32dp tinted [IconBadge] and set the figure
/// at 20/700 beside it, which is a shape the Figma file draws nowhere: four haloed glyphs
/// across the top of a page are four things competing with the numbers they label. Dropping
/// them takes the tile from ~118dp to ~74dp, which is how the file fits FOUR of these plus
/// four quick actions plus a complaint above the fold.
///
/// The eyebrow is UPPERCASE, and that is the file's own `uppercase` class on 4:672 — not the
/// sentence case the superseded Stitch screens used.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;

  /// Canonical in, resolved at paint. Null leaves the figure cream — the design tones only the
  /// figures that carry a meaning ("₹89,200" red, "6 Pending" amber) and leaves "3 Approved"
  /// in the body colour.
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Semantics(
      button: onTap != null,
      label: '$label: $value${caption == null ? '' : '. $caption'}',
      child: Material(
        color: t.colorScheme.surface,
        borderRadius: Radii.rCard,
        child: InkWell(
          borderRadius: Radii.rCard,
          onTap: onTap,
          child: Container(
            // A MINIMUM, not a height: at 1.4x text scale a two-line caption needs the room,
            // and a fixed box clipped it. It is also the 48dp tap floor for a tile that opens
            // the list it counted.
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              borderRadius: Radii.rCard,
              border: Border.all(color: t.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CapsLabel(label),
                const SizedBox(height: Space.xxs),
                Text(
                  value,
                  // headlineSmall is 16/700 tabular — the design's KPI figure exactly, and
                  // tabular so a refreshing column of counts does not shuffle sideways.
                  style: t.textTheme.headlineSmall?.copyWith(color: accent),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (caption != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(caption!, style: t.textTheme.bodySmall,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The header's square icon button — `bell-icon-container` (4:656, 4:739).
///
/// `bg-[#171a1e] rounded-[8px] size-[32px]` with a 16px glyph in it. The painted box is the
/// design's 32; the TARGET around it is 48, because 32dp is under both Material's and Apple's
/// floor and the person hitting it is standing in a corridor. [badge] is the design's own
/// 8px alert dot at the top right (4:659) — shown only when there is something to alert about,
/// because a dot that is always on is decoration.
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
    final t = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: Space.huge, height: Space.huge),
      icon: SizedBox(
        width: Space.xxl,
        height: Space.xxl,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.colorScheme.surfaceContainer,
                  borderRadius: Radii.rControl,
                ),
                child: Icon(
                  icon,
                  size: IconSize.md,
                  // IconButton greys a disabled icon through IconTheme, which cannot reach
                  // past the DecoratedBox this one is wrapped in. Said here instead.
                  color: onPressed == null
                      ? t.colorScheme.onSurfaceVariant
                      : t.colorScheme.onSurface,
                ),
              ),
            ),
            if (badge)
              Positioned(
                top: Space.xxs + Space.xxs / 2,
                right: Space.xxs + Space.xxs / 2,
                child: Container(
                  width: Space.xs,
                  height: Space.xs,
                  decoration: BoxDecoration(
                    color: context.tones.error,
                    borderRadius: Radii.rTiny,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The design's aside: a filled well with a tinted glyph and a sentence in it.
///
/// assign-bed-review.png sets its billing notice exactly this way — `surface-container-highest`,
/// `rounded-lg`, a violet info glyph, body copy. Three screens in this feature had each drawn
/// their own version at their own alpha; this is the one the design specifies.
///
/// [tone] tints the whole well for an aside that carries a WARNING rather than a note — the
/// subscription banner, a refusal the server explained — using the measured chip recipe.
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

  /// Null draws the design's neutral well.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final accent = tone == null ? t.colorScheme.primary : tones.resolve(tone!);
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tone == null ? t.colorScheme.surfaceContainerHighest : tones.chipFill(accent),
        borderRadius: Radii.rControl,
        border: tone == null
            ? null
            : Border.all(color: tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: IconSize.md, color: accent),
          const SizedBox(width: Space.xs),
          Expanded(
            child: title == null
                ? child
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: t.textTheme.titleSmall?.copyWith(color: accent)),
                      child,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The mockups' haloed glyph: a tinted disc inside a ring of the same tone.
///
/// assign-bed-success.png and move-out-success.png both open with it, and it is the one piece
/// of ornament the design allows itself on an otherwise empty screen. Reused for the empty and
/// the failed states so that "nothing here", "this broke" and "that worked" are one size of
/// event drawn three colours apart, rather than three different shapes.
class StateHalo extends StatelessWidget {
  const StateHalo({super.key, required this.icon, this.tone});

  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final accent = context.tones.resolve(tone ?? Theme.of(context).colorScheme.primary);
    return Container(
      width: Space.huge + Space.xl, // 72
      height: Space.huge + Space.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.tones.chipFill(accent),
        shape: BoxShape.circle,
        border: Border.all(color: context.tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Icon(icon, size: IconSize.xl, color: accent),
    );
  }
}

/// Nothing to show — said in words that tell the warden whether that is good news.
///
/// THE ANATOMY IS NODE 4:1562, `screen-empty-error-skeleton`, which is the frame the owner
/// asked for and the one place the design specifies what an empty section looks like: a raised
/// card, a caps tag in the state's tone at the top left, then a centred glyph inside a 54px
/// square outlined at 1.5px, a 14/600 title and an 11/400 support line. [StateCard] and
/// [StateBody] in the glass layer are that frame; this is the warden's wording on top of it.
///
/// It replaces a 72dp tinted halo disc, which was the Stitch success screen's ornament and
/// appears nowhere in the Figma file.
class EmptyState extends StatelessWidget {
  const EmptyState({
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

  /// Null is the neutral "nothing here". Pass [NivoraColors.success] where an empty list is the
  /// good outcome — every complaint resolved, every leave decided.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: StateCard(
        // The design's badge names the STATE, not the content. Green where nothing left to do
        // is the win, neutral where the list is simply empty.
        badge: tone == null ? 'Nothing here' : 'All clear',
        tone: tone,
        child: StateBody(
          icon: icon,
          illustration: illustration,
          title: title,
          message: detail,
          tone: tone,
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
/// The error card is the same 4:1562 anatomy as [EmptyState] with the red badge (4:1590) and
/// the CREAM filled retry (4:1596). The design gives its error state no glyph at all — the
/// sentence is the message — and that is followed here.
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
        tone: NivoraColors.error,
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

/// The mockups' confirmation panel: a haloed tick, a headline, a sentence, a summary of what
/// was written, and the ways on from here.
///
/// assign-bed-success.png and move-out-success.png are the same layout twice, so this is one
/// widget. The summary is label/value rows under a `label-caps` heading — the design's own
/// "ASSIGNMENT SUMMARY" — and every value passed to it comes from what the SERVER returned,
/// never from what a form was holding.
class SuccessPanel extends StatelessWidget {
  const SuccessPanel({
    super.key,
    required this.title,
    required this.message,
    this.summaryTitle,
    this.summary = const <(String, String)>[],
    this.tone,
    this.actions = const <Widget>[],
  });

  final String title;
  final String message;
  final String? summaryTitle;

  /// Label / value pairs, drawn the design's way round: the quiet label left, the emphasised
  /// value right.
  final List<(String, String)> summary;
  final Color? tone;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone ?? NivoraColors.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(child: StateHalo(icon: Icons.check_circle_outline_rounded, tone: accent)),
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
                  CapsLabel(summaryTitle!),
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
/// The warden kit had no skeleton at all: the summary cards passed `SizedBox(height: 76)` as
/// their loading state, which is a blank gap that looks exactly like a section that failed
/// silently. This keeps the card's shape on screen so the page does not jump when the figures
/// land, and — unlike a spinner — it says WHERE the missing thing will be.
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({super.key, this.lines = 2});

  final int lines;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: Motion.slow)..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _bar(BuildContext context, double factor, double height) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: factor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            // `#1D2227` — the brightest fill in the file, and what the skeleton layout's own
            // bars are painted (4:1604, 4:1605, 4:1609, 4:1610). The hairline colour was too
            // close to the card to read as a placeholder at all.
            color: Theme.of(context).colorScheme.surfaceBright,
            borderRadius: Radii.rTiny,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final body = Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _bar(context, 0.35, Space.sm - Space.xxs / 2),
          const SizedBox(height: Space.sm),
          for (var i = 0; i < widget.lines; i++) ...[
            _bar(context, i.isEven ? 1 : 0.6, Space.md - Space.xxs / 2),
            if (i != widget.lines - 1) const SizedBox(height: Space.xs),
          ],
        ],
      ),
    );
    // Somebody who asked the OS for less motion still gets the placeholder; it just stops
    // breathing.
    if (MediaQuery.disableAnimationsOf(context)) return body;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1)
          .animate(CurvedAnimation(parent: _pulse, curve: Motion.move)),
      child: body,
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
        child: Center(child: CircularProgressIndicator(strokeWidth: InlineSpinner.stroke)),
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
  /// is indigo on indigo and invisible for the whole of the write it is reporting.
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

/// One of the four things a warden does most — `action-card` (4:693, 4:696, 4:700, 4:703).
///
/// A ROW, not a tile: `bg-[#171a1e] border border-[#292e33] rounded-[8px] p-[12px] gap-[10px]`
/// with a bare 14px glyph and a 12/600 label beside it. Four of them in a 2×2 grid come to
/// about 100dp of page in total, which is what leaves room for the section under them.
///
/// IT WAS AN 88dp TILE with a 48dp tinted disc above a centred label. That shape is from the
/// superseded Stitch dashboard; the Figma file draws no icon discs at all. The glyph keeps its
/// [tone] because the file tints these individually — its four are gold, blue, green and
/// amber — but it is a glyph on the surface now, not a badge.
///
/// The raised fill is the design's and it is what distinguishes an action from a statistic:
/// stat cards are `#111417`, actions are `#171A1E`. Height floors at 48dp — the design's card
/// comes out around 42, and the person tapping it is standing up holding a phone in one hand.
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
        color: t.colorScheme.surfaceContainer,
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: enabled ? onTap : null,
          child: Container(
            // A MINIMUM, not a height: a two-line label at 1.4x text scale needs the room, and
            // 48 is the tap floor the design's own 42 does not reach.
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(Space.sm),
            decoration: BoxDecoration(
              borderRadius: Radii.rControl,
              border: Border.all(color: t.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(icon, size: IconSize.sm, color: accent),
                const SizedBox(width: Space.xs + Space.xxs / 2),
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
        ),
      ),
    );
  }
}

/// A list row sized for a thumb: 64dp minimum, the whole width tappable.
///
/// `student-row` (4:761) is the shape: the card fill behind a hairline at `rounded-[8px]` with
/// 12dp of padding. The corner moved 12 → 8 with the restyle — 12 is what the file gives a
/// CARD, and a row in a list of twenty is a small card.
class TapRow extends StatelessWidget {
  const TapRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.sm),
    this.semanticLabel,
    this.tone,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  /// Draws the row's edge in a semantic tone instead of the neutral hairline — the way the
  /// mockups mark a row that is selectable or that needs attention (the violet-edged student
  /// row on assign-bed-select-student.png, the coral-edged damaged item on
  /// move-out-inspection.png). Canonical or resolved.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final edge = tone == null
        ? t.colorScheme.outlineVariant
        : context.tones.chipBorder(context.tones.resolve(tone!));
    final row = Material(
      color: t.colorScheme.surface,
      borderRadius: Radii.rControl,
      child: InkWell(
        borderRadius: Radii.rControl,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: Radii.rControl,
            border: Border.all(color: edge),
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
///
/// The ring is the design's — resident-profile.png rings every avatar in its own tone — and it
/// is also what stops a 10% tint disappearing into a card that is itself only 1.08:1 against
/// the ground.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.tone, this.size = Space.xxl});
  final String name;
  final Color? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = context.tones.resolve(tone ?? t.colorScheme.primary);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.tones.chipFill(accent),
        shape: BoxShape.circle,
        border: Border.all(color: context.tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Text(
        initials(name),
        style: t.textTheme.titleSmall?.copyWith(color: accent),
      ),
    );
  }
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

/// A labelled value — `sheet-details` (4:805, 4:808, 4:811) on the students-list sheet.
///
/// The design's row is two columns on one line: the field name left in the secondary ink at
/// 400, the answer right in cream at 600, both at the same size. Weight and colour separate
/// them, not size or position.
///
/// IT USED TO BE A STACK with a 32dp tinted glyph disc in front — the Stitch resident profile's
/// PERSONAL DETAILS shape. The Figma sheet has neither the disc nor the caps eyebrow, and at
/// six rows the stacked version was twice as tall for the same three facts. The label wraps
/// rather than truncating and the value is given the wider half, which is what keeps a phone
/// number and an address readable at 1.4x text scale.
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

/// The title bar of a bottom sheet — `sheet-header` (4:796).
///
/// An avatar, the name at 15/700 with an 11/400 second line under it, and the state badge
/// pushed to the right-hand edge. [leading] is the design's avatar; sheets that are about a
/// room or a queue rather than a person leave it off and look exactly as they did.
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
    // No drag handle here. showGlassSheet draws one, on the pane, for every sheet in the app;
    // this used to draw a second one directly beneath it.
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
              // 4:800 is `Inter:Bold text-[15px]`. [titleMedium] is the scale's 16/700 — the
              // nearest step that is a real token, and one the scale already calls "row and
              // card title". A 15/700 would mean re-resolving the face through google_fonts
              // at a paint site, which is a network call inside the widget tests.
              Text(
                title,
                style: t.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(subtitle!, style: t.textTheme.bodySmall,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
  // The snackbar keeps its themed midnight background (white on it is 18.72:1) and says "this
  // failed" with an icon instead. Repainting the whole bar #DC3F3F put the message at 4.35:1
  // against its own white text — the one message in the app that most needs reading. The accent
  // is the DARK theme's error ink because the bar is dark in both themes.
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: IconSize.md, color: NivoraColors.errorDark), // 7.35:1 on midnight
        const SizedBox(width: Space.sm),
        Expanded(child: Text(failure.message)),
      ],
    ),
    behavior: SnackBarBehavior.floating,
    duration: Motion.readMessage,
  ));
}
