library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import 'clay_icons.dart';
import 'status_chip.dart';

/// A card of rows — "Needs attention", "Recent payments": the warm white card with its hairline,
/// rows separated by the divider ink and nothing after the last.
///
/// Flat, like every resting card. Pass [ListRow]s; anything else is laid out the same way, so a
/// custom row keeps the rhythm as long as it brings its own 70dp.
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.padding});

  final List<Widget> children;

  /// Inside the card. Defaults to the canvas's 4 above and below, 14 at the sides.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.rSurface,
        side: BorderSide(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: Space.sm + Space.hair, vertical: Space.xxs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: Strokes.hairline, color: t.dividerTheme.color),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// One row: what it is (a clay icon or a person's initials), two lines saying which one, and
/// what can be done about it at the trailing edge.
///
/// ── THE ANATOMY ──────────────────────────────────────────────────────────────────────────
///
/// At least 70dp tall and growing with its text, never fixed. A 46dp leading disc, 12 to the
/// words; the title Manrope 14/20 w700 (one line, two from 1.3x), the subtitle 12/16 in the
/// muted ink (up to two lines, three from 1.3x, so a sentence saying what an action costs is
/// not cut off at large text). The trailing slot takes one of: a [PillButton] ("Remind"), a
/// [ListRowAmount], or nothing — a navigable row then draws a chevron by itself.
///
/// ── SEMANTICS ────────────────────────────────────────────────────────────────────────────
///
/// The leading art and the words are ONE node — the title, then the subtitle — and a button
/// when [onTap] is set. The trailing control is its own target outside that node, so "Remind"
/// is never swallowed into a row a screen reader announces as a whole.
///
/// ── NARROW OR LARGE TEXT ─────────────────────────────────────────────────────────────────
///
/// Under 280dp across, or from 1.6x text, a trailing widget moves below the words instead of
/// squeezing them: a 320dp phone at 2.0x still reads the whole name. On a phone-width row
/// ([roomyWidth]) it moves from 1.3x, where the title starts taking a second line: at 1.4x on
/// a 360dp phone an amount, its status and a button beside them left a name like
/// "Aarav Sharma" broken over two lines in a 110dp column.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.avatarName,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.showChevron,
  });

  final String title;
  final String? subtitle;

  /// A [ClayIcons] path drawn at 46dp. Decorative.
  final String? icon;

  /// A person's name, drawn as initials on a Mist disc when there is no [icon].
  final String? avatarName;

  /// Any 46dp leading widget, when neither an icon nor initials fit.
  final Widget? leading;

  /// A [PillButton], a [ListRowAmount], a [StatusChip] — its own target.
  final Widget? trailing;

  final VoidCallback? onTap;

  /// Replaces the spoken title and subtitle.
  final String? semanticLabel;

  /// Null draws the chevron whenever the row is navigable and has no [trailing].
  final bool? showChevron;

  static const minHeight = 70.0;

  /// The width under which a trailing widget moves below the words.
  static const wrapWidth = 280.0;

  /// The width under which it moves from 1.3x text rather than 1.6x. A tablet's row has room
  /// for the words beside it until the text is very large.
  static const roomyWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final chevron = showChevron ?? (onTap != null && trailing == null);

    final Widget? lead = leading ??
        (icon != null
            ? ClayIcon(icon!, size: ClaySize.list)
            : avatarName != null
                ? InitialsDisc(name: avatarName!)
                : null);

    final words = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: t.textTheme.titleMedium,
          maxLines: scale >= 1.3 ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: Space.hair),
          Text(
            subtitle!,
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            maxLines: scale >= 1.3 ? 3 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    return LayoutBuilder(builder: (context, c) {
      final wrap = trailing != null &&
          (c.maxWidth < wrapWidth || scale >= 1.6 || (scale >= 1.3 && c.maxWidth < roomyWidth));

      Widget main = Row(
        children: [
          if (lead != null) ...[
            ExcludeSemantics(child: SizedBox.square(dimension: ClaySize.list, child: lead)),
            const SizedBox(width: Space.sm),
          ],
          Expanded(child: words),
        ],
      );
      // MergeSemantics OUTSIDE the button: the title, the subtitle, the button flag and the tap
      // become one node. The other way round leaves an unlabelled button around a text node.
      main = MergeSemantics(
        child: Semantics(
          button: onTap != null,
          label: semanticLabel,
          excludeSemantics: semanticLabel != null,
          onTap: onTap,
          child: main,
        ),
      );

      final Widget body = wrap
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                main,
                const SizedBox(height: Space.xs),
                Padding(
                  padding: EdgeInsetsDirectional.only(
                      start: lead == null ? 0 : ClaySize.list + Space.sm),
                  child: Align(alignment: AlignmentDirectional.centerStart, child: trailing),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: main),
                if (trailing != null) ...[const SizedBox(width: Space.sm), trailing!],
                if (chevron) ...[
                  const SizedBox(width: Space.xs),
                  ExcludeSemantics(
                    child: Icon(Icons.chevron_right_rounded,
                        size: IconSize.lg, color: t.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            );

      return InkWell(
        onTap: onTap,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Align(alignment: AlignmentDirectional.centerStart, child: body),
          ),
        ),
      );
    });
  }
}

/// A [ListRow] alone in its own card — one item that is not part of a list.
class ListRowCard extends StatelessWidget {
  const ListRowCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.avatarName,
    this.leading,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    this.showChevron,
  });

  final String title;
  final String? subtitle;
  final String? icon;
  final String? avatarName;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool? showChevron;

  @override
  Widget build(BuildContext context) => ListGroup(
        children: [
          ListRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            avatarName: avatarName,
            leading: leading,
            trailing: trailing,
            onTap: onTap,
            semanticLabel: semanticLabel,
            showChevron: showChevron,
          ),
        ],
      );
}

/// A figure at a row's trailing edge, with the status word under it — "₹8,500 / Overdue".
///
/// Right-aligned and tabular, so a column of amounts lines up down a list.
class ListRowAmount extends StatelessWidget {
  const ListRowAmount({
    super.key,
    required this.amount,
    this.status,
    this.tone = StatusTone.neutral,
    this.amountTone,
  });

  /// Already formatted — "₹8,500".
  final String amount;

  /// The word under it, drawn as a [StatusChip] in [tone].
  final String? status;
  final StatusTone tone;

  /// Colours the figure with that tone's ink. Usually left null: the chip carries the state.
  final StatusTone? amountTone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final figureTone = amountTone;
    final style = ApnivaasType.tabular(t.textTheme.titleMedium ?? const TextStyle()).copyWith(
      color: figureTone == null ? null : context.tones.resolve(figureTone.canonical),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(amount, style: style, maxLines: 1),
        if (status != null) ...[
          const SizedBox(height: Space.xxs),
          StatusChip(label: status!, tone: tone),
        ],
      ],
    );
  }
}

/// A person, as initials on a Mist disc — a list row's leading slot, a staff card.
///
/// Forest on Mist, 7.54:1 (dark: the dark primary on the dark Mist, 6.43:1). One colour for
/// everybody: a hue per person is what made a name collide with a status before (see
/// `avatarToneFor` in glass.dart). Decorative unless [semanticLabel] is given — the name is
/// almost always printed beside it.
class InitialsDisc extends StatelessWidget {
  const InitialsDisc({super.key, required this.name, this.size = AvatarSize.list, this.semanticLabel});

  final String name;
  final double size;
  final String? semanticLabel;

  /// Up to two initials; one glyph rather than an empty disc, which reads as a failed load.
  static String initialsFor(String? name) {
    final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words.first.characters.first + words.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? ApnivaasColors.primary : ApnivaasColors.forest;
    final disc = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark ? ApnivaasColors.darkMist : ApnivaasColors.mist,
        ),
        // The initials never outgrow the disc, whatever the text scale.
        child: Center(
          child: MediaQuery.withNoTextScaling(
            child: Text(
              initialsFor(name),
              maxLines: 1,
              style: ApnivaasType.outfit(size * 0.35, size * 0.44, FontWeight.w600, ink),
            ),
          ),
        ),
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: disc);
    return Semantics(label: label, image: true, child: ExcludeSemantics(child: disc));
  }
}
