/// Four small parts every form in the entry screens shares: the primary button that keeps its
/// colour while it works, the line that says what went wrong, the Mist well a step's clay icon
/// sits in, and the tick row a person agrees with.
///
/// They live here rather than in shared/clay/ because they are the entry screens' own — sign-in,
/// the second factor, the password and email gates, security, consent, account deletion and the
/// payment buttons — and those screens are the only ones written against them so far.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/clay/clay_icons.dart';

/// THE SCREEN'S ONE PRIMARY ACTION — a [FilledButton] that stays forest while it works.
///
/// ── WHY NOT A PLAIN FILLED BUTTON WITH A SPINNER IN IT ──────────────────────────────────────
///
/// Every form here disables its button while a request is in flight, because a second tap is a
/// second request: a second reauthentication spent against the throttle, a second mail that kills
/// the first link. A disabled filled button paints the theme's disabled pair — the track beige
/// with a grey ink — and the spinners these screens used to put inside it were drawn in white.
/// White on #E6DED2 is a spinner nobody can see, on the one control the person is watching. So
/// while [busy] the button is still disabled, but it keeps its own fill and ink: the spinner
/// reads as "working", not as "unavailable".
///
/// It is still a [FilledButton] — several tests find the screen's primary action by that type
/// and read its `onPressed` — and the label is still a plain [Text] when it is not busy.
class BusyFilledButton extends StatelessWidget {
  const BusyFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.icon,
    this.danger = false,
  });

  final String label;

  /// Null draws the ordinary disabled button. Ignored while [busy].
  final VoidCallback? onPressed;

  final bool busy;

  /// Shown beside the spinner while [busy] — "Opening…". Null shows the spinner alone, and a
  /// screen reader hears "Working".
  final String? busyLabel;

  /// A glyph before the label. The spinner takes its place while busy.
  final IconData? icon;

  /// The error fill, for the one action in this area that destroys something: a deletion request.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final theme = FilledButtonTheme.of(context).style;
    const resting = <WidgetState>{};
    final fill = danger ? t.colorScheme.error : theme?.backgroundColor?.resolve(resting);
    final ink = danger ? t.colorScheme.onError : theme?.foregroundColor?.resolve(resting);

    final ButtonStyle? style = switch ((busy, danger)) {
      (false, false) => null,
      (true, false) => FilledButton.styleFrom(
          disabledBackgroundColor: fill,
          disabledForegroundColor: ink,
        ),
      (false, true) => FilledButton.styleFrom(backgroundColor: fill, foregroundColor: ink),
      (true, true) => FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: ink,
          disabledBackgroundColor: fill,
          disabledForegroundColor: ink,
        ),
    };

    final spinner = SizedBox.square(
      dimension: IconSize.lg,
      child: CircularProgressIndicator(strokeWidth: Strokes.focus, color: ink),
    );

    if (icon != null || (busy && busyLabel != null)) {
      return FilledButton.icon(
        onPressed: busy ? null : onPressed,
        style: style,
        icon: busy ? spinner : (icon == null ? null : Icon(icon, size: IconSize.md)),
        label: Text(busy ? (busyLabel ?? label) : label),
      );
    }
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: style,
      child: busy ? Semantics(label: 'Working', child: spinner) : Text(label),
    );
  }
}

/// What a form says back: a sentence in the tone's text ink, led by a glyph, announced the moment
/// it appears.
///
/// NEVER COLOUR ALONE. The glyph and the words carry the meaning; the ink only agrees with them.
/// The ink is `context.tones`, the theme-resolved TEXT colour — the canonical error red measures
/// 4.05:1 on a card, which is below AA for type, and tokens.dart says so in as many words.
class FormNote extends StatelessWidget {
  const FormNote(this.message, {super.key, this.tone = FormNoteTone.error, this.textAlign});

  final String message;
  final FormNoteTone tone;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final (Color ink, IconData glyph) = switch (tone) {
      FormNoteTone.error => (tones.error, Icons.error_outline_rounded),
      FormNoteTone.warning => (tones.warning, Icons.schedule_rounded),
      FormNoteTone.success => (tones.success, Icons.check_circle_outline_rounded),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Sits the glyph on the first line's x-height rather than on its ascender.
            padding: const EdgeInsets.only(top: Space.hair / 2),
            child: ExcludeSemantics(child: Icon(glyph, size: IconSize.md, color: ink)),
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              message,
              textAlign: textAlign,
              style: t.textTheme.bodyMedium?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three things a [FormNote] can say.
enum FormNoteTone { error, warning, success }

/// A clay icon seated in a Mist well — the badge over a step's heading, and the leading art of a
/// card that has no list to sit in.
///
/// The quick-action well's shape (64dp, radius 22) in Mist rather than the near-white well, so
/// it holds its own on the cream ground as well as on a card. Decorative: the heading beside or
/// under it always says the same thing in words.
class ClayWell extends StatelessWidget {
  const ClayWell(this.icon, {super.key, this.compact = false});

  /// A [ClayIcons] path.
  final String icon;

  /// 46dp art in a 56dp well, for a card heading; otherwise 54 in 64.
  final bool compact;

  /// The well's side.
  static const size = 64.0;
  static const compactSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final side = compact ? compactSize : size;
    return SizedBox.square(
      dimension: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? ApnivaasColors.darkMist : ApnivaasColors.mist,
          borderRadius: Radii.rWell,
        ),
        child: Center(
          child: ClayIcon(icon, size: compact ? ClaySize.list : ClaySize.action),
        ),
      ),
    );
  }
}

/// A tick and the sentence it agrees to: one row, one target, one thing a screen reader says.
///
/// THE BOX SITS ON THE COLUMN'S EDGE, level with the fields and the button around it. A stock
/// [Checkbox] pads itself to a 48dp square and centres its 18dp mark in that, so beside a
/// full-width button it read as indented by 15dp — on the consent bar, account deletion and the
/// saved-key line alike. Here the whole row is the target instead, as wide as the column and
/// never shorter than 48dp, so the box can be laid out at its drawn size. It is centred on the
/// sentence's first line at every text size, and the words wrap beside it rather than under it.
///
/// The transparent [Material] is the row's own: its ink needs one, and the nearest thing above
/// it is usually a decorated box, which Flutter asserts on.
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.value, required this.onChanged, required this.label});

  final bool value;

  /// Null draws the row disabled, box and words alike.
  final ValueChanged<bool>? onChanged;

  final String label;

  /// The box's laid-out square: Material's 18dp mark and the 3dp of ground it draws around it.
  static const box = 24.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface);
    final firstLine =
        MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 13) * (style?.height ?? 1.4);
    final change = onChanged;
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: change == null ? null : () => change(!value),
          borderRadius: Radii.rControl,
          child: Padding(
            // 12 above and below the 24dp box: the 48dp floor, before the words grow it.
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: math.max(0, (firstLine - box) / 2)),
                  child: SizedBox.square(
                    dimension: box,
                    child: Checkbox(
                      value: value,
                      onChanged: change == null ? null : (v) => change(v ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: VisualDensity.minimumDensity,
                        vertical: VisualDensity.minimumDensity,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: math.max(0, (box - firstLine) / 2)),
                    child: Text(label, style: style),
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
