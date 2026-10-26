library;

import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'brow.dart';
import 'clay/app_header.dart';
import 'clay/word_fit.dart';
import 'wordmark.dart';

/// THE BROW HEADER — what `GlassHeader(onBrow: true)` draws for the role screens built on it
/// (SaScreen, WardenScreen, ManagerScreen, the shell masthead).
///
/// It is the forest header ([AppHeader]) under another API: the same gradient, the same dot
/// stars, the same 30dp bottom corners and the same three inks, so a screen still on
/// [BrowTitleBlock] and a screen already on [AppHeader] cannot be told apart at the top.
///
/// ── THE INK IS NOT THE CALLER'S TO CHOOSE ────────────────────────────────────────────────
///
/// The owner's screenshot of the Super Admin "Subscriptions" tab — dark grey on the old violet,
/// "uncomfortable to read" — came from call sites building the lines with the theme's own text
/// styles, whose ink beats an inherited colour. So [BrowTitleBlock] takes STRINGS, and
/// [BrowText] resolves the colour inside the header, last, after any style a caller passed.
/// Icon buttons in `actions` get the same guarantee from [ForestInk], disabled ones included.
///
/// ── THE INKS, MEASURED ON THE LIGHTEST STOP ──────────────────────────────────────────────
///
///   ink                      forestHigh #1F6150    forest #174E43
///   title     #FFFFFF        7.28:1                9.51:1
///   eyebrow   #BFE0CC        5.11:1                6.68:1
///   subtitle  #CFE0D4        5.29:1                6.92:1
///   disabled  #FFFFFF @38%   2.43:1                2.77:1   inactive, so WCAG sets no floor
///
/// ── NOTHING MOVES ────────────────────────────────────────────────────────────────────────
///
/// The violet brow played a one-second entrance — a gold sweep, a ribbon, a lit window, lines
/// rising in. The design's header is static, so all of that is gone: the backdrop is painted
/// once into its own layer, no controller exists, and nothing is scheduled after the first
/// frame. The one movement left is a changed string cross-fading into its place (a loading
/// title giving way to the real one), and under reduce motion not even that.

// ─────────────────────────────────────────────────────────────────────────────
// PALETTE
// ─────────────────────────────────────────────────────────────────────────────

/// Every colour the brow paints — the forest header's own inks, named for the brow's lines.
abstract final class BrowInk {
  /// The middle stop of the header gradient, where most of a line sits.
  static const deep = ApnivaasColors.brandDeep;

  /// THE LIGHTEST STOP, #1F6150 — the ground every ink below is measured on.
  static const bright = ApnivaasColors.forestHigh;

  /// The title. 7.28:1 on [bright].
  static const title = ApnivaasColors.headerTitle;

  /// The eyebrow and the Apnivaas signature: the header's greeting ink. 5.11:1 on [bright].
  static const eyebrow = ApnivaasColors.headerGreeting;

  /// The meta line: the header's caption ink. 5.29:1 on [bright].
  static const subtitle = ApnivaasColors.headerSub;

  /// Icon buttons on the brow, a PopupMenuButton's glyph included: the title's white.
  static const control = title;

  /// A disabled icon button: white at Material's 38%. It dims towards the ground rather than
  /// going dark; left to the theme it would be onSurface at 38%, near-black in light.
  static const controlDisabled = ForestInk.disabled;

  /// The brand dot. 3.60:1 on [bright], 4.71:1 on [deep] — a graphic, so 3:1 is its bar.
  static const gold = ApnivaasColors.gold;
}

/// The three lines a brow header carries.
enum BrowLine { eyebrow, title, subtitle }

// ─────────────────────────────────────────────────────────────────────────────
// THE FRAME
// ─────────────────────────────────────────────────────────────────────────────

/// The brow itself: the forest backdrop, the rounded bottom corners, the light status-bar
/// icons and the light ink scope.
///
/// Built by `GlassHeader(onBrow: true)`, which owns the padding; screens do not use this directly.
class BrowHeaderFrame extends StatelessWidget {
  const BrowHeaderFrame({super.key, required this.padding, required this.child});

  /// Already includes the status-bar inset and the header's bottom inset.
  final EdgeInsetsGeometry padding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      // Dark icons on forest are a clock nobody can read, and on a light-mode phone the root
      // sets exactly that.
      value: ApnivaasTheme.onForest,
      child: ClipRRect(
        borderRadius: Radii.rHeaderBottom,
        child: Stack(
          children: [
            // Painted once and cached: nothing in it moves, and a badge changing in the
            // content above does not repaint it.
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: HeaderBackdropPainter(topInset: MediaQuery.paddingOf(context).top),
                ),
              ),
            ),
            Padding(padding: padding, child: ForestInk(child: child)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LINES
// ─────────────────────────────────────────────────────────────────────────────

/// One line of brow type, in the brow's own ink.
///
/// THE COLOUR IS APPLIED HERE, LAST. [style] may set size, weight or line height and nothing it
/// says about colour survives — which is the whole fix for the dark-ink leak.
class BrowText extends StatelessWidget {
  const BrowText.eyebrow(this.text, {super.key, this.textAlign = TextAlign.start, this.style})
      : line = BrowLine.eyebrow,
        maxLines = 1,
        textScaler = null;

  /// [maxLines] is one unless the caller makes room for more; [BrowTitleBlock] gives a page
  /// title a second line above 1.3x text, and a [textScaler] that keeps its longest word whole.
  const BrowText.title(
    this.text, {
    super.key,
    this.textAlign = TextAlign.start,
    this.style,
    this.maxLines = 1,
    this.textScaler,
  }) : line = BrowLine.title;

  const BrowText.subtitle(this.text, {super.key, this.textAlign = TextAlign.start, this.style})
      : line = BrowLine.subtitle,
        maxLines = 1,
        textScaler = null;

  final String text;
  final BrowLine line;
  final TextAlign textAlign;
  final TextStyle? style;
  final int maxLines;

  /// Null takes the reader's text scale.
  final TextScaler? textScaler;

  /// The resolved style for [line] — [HeaderText]'s greeting, title and subtitle. Public so a
  /// test can hold the numbers to account.
  static TextStyle styleFor(BuildContext context, BrowLine line, [TextStyle? base]) {
    final header = HeaderText.of(context);
    final slot = switch (line) {
      BrowLine.eyebrow => header.greeting,
      BrowLine.title => header.title,
      BrowLine.subtitle => header.subtitle,
    };
    final ink = switch (line) {
      BrowLine.eyebrow => BrowInk.eyebrow,
      BrowLine.title => BrowInk.title,
      BrowLine.subtitle => BrowInk.subtitle,
    };
    return slot.merge(base).copyWith(color: ink);
  }

  @override
  Widget build(BuildContext context) {
    assert(
      BrowScope.of(context),
      'BrowText paints light ink and belongs inside GlassHeader(onBrow: true).',
    );
    final resolved = styleFor(context, line, style);
    final paragraph = Text(
      text,
      style: resolved,
      maxLines: maxLines,
      textScaler: textScaler,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
    if (MediaQuery.disableAnimationsOf(context)) return paragraph;
    // A changed string cross-fades rather than snapping. The first string simply appears:
    // AnimatedSwitcher does not animate its initial child.
    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.enter,
      layoutBuilder: (current, previous) => Stack(
        alignment:
            textAlign == TextAlign.center ? Alignment.center : AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey<String>(text), child: paragraph),
    );
  }
}

/// THE ONE TITLE BLOCK every brow header is built from.
///
/// Eyebrow, title and subtitle are strings, never widgets, so no call site can hand the brow a
/// line styled in the theme's ink. [leading] and [actions] are widgets because they are controls
/// and glyphs: an unstyled [Icon], [IconButton] or [PopupMenuButton] takes the brow's ink from the
/// frame, and a slot that names its own colour reads BrowScope. A TextButton or OutlinedButton is
/// not themed for the brow, and none sits on one.
///
/// Every line is one line and ellipsises, so the header keeps its rhythm whatever the strings
/// are; it grows with the text scale rather than clipping. The one exception is the title above
/// 1.3x text, which takes a second line — [AppHeader]'s rule — because at 2.0x a tab's name
/// beside a header action was cut to "Rooms & b…", and that name is what says which tab this is.
/// A one-word name too long for its line ("Collections" beside two buttons) is set a little
/// smaller rather than broken in the middle ([WordFit]).
class BrowTitleBlock extends StatelessWidget {
  const BrowTitleBlock({
    super.key,
    required String this.title,
    this.eyebrow,
    this.subtitle,
    this.leading,
    this.actions = const [],
  })  : _mastheadName = null,
        leadingExtent = 0;

  /// The dashboard treatment: the greeting and the Apnivaas signature centred on the SCREEN, with
  /// [leading] (the account avatar) at the start and an empty box of [leadingExtent] opposite it,
  /// so the block is not pushed off-centre by exactly one avatar. No leading, no box.
  const BrowTitleBlock.masthead({
    super.key,
    required String name,
    this.leading,
    this.leadingExtent = AvatarSize.header + Space.xs * 2,
  })  : title = null,
        eyebrow = null,
        subtitle = null,
        actions = const [],
        _mastheadName = name;

  final String? title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  /// The width of the empty twin opposite [leading] on a masthead. The default is the account
  /// avatar's 44dp disc inside 8dp of padding either side.
  final double leadingExtent;

  final String? _mastheadName;

  @override
  Widget build(BuildContext context) {
    final name = _mastheadName;
    if (name != null) {
      final block = MastheadBlock(name: name);
      if (leading == null) return Center(child: block);
      return Row(
        children: [
          leading!,
          Expanded(child: Center(child: block)),
          SizedBox(width: leadingExtent),
        ],
      );
    }

    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: Space.sm)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                BrowText.eyebrow(eyebrow!),
                const SizedBox(height: Space.hair),
              ],
              LayoutBuilder(
                builder: (context, box) => BrowText.title(
                  title!,
                  maxLines: MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 2 : 1,
                  textScaler: WordFit.scalerFor(
                    context,
                    title!,
                    BrowText.styleFor(context, BrowLine.title),
                    box.maxWidth,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: Space.hair),
                BrowText.subtitle(subtitle!),
              ],
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: Space.xxs), a],
      ],
    );
  }
}
