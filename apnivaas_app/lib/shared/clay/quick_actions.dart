library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import 'clay_icons.dart';
import 'section_header.dart';
import 'word_fit.dart';

/// One quick action: a clay icon in a soft well, and the words for what it does.
///
/// The whole tile is one button named by its label — the icon is decoration beside words that
/// already say it. The well dips to 94% and fills with the brand at 12% under a finger, with a
/// selection click; under reduce motion only the fill changes.
class QuickActionTile extends StatefulWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticLabel,
  });

  /// A [ClayIcons] path.
  final String icon;

  /// Two lines at most at normal text sizes ("Collect payment", "Send announcement").
  final String label;

  /// Null draws the tile disabled: dimmed, and announced as unavailable.
  final VoidCallback? onTap;

  /// Spoken instead of [label].
  final String? semanticLabel;

  /// The well and the art inside it.
  static const wellSize = 64.0;

  @override
  State<QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<QuickActionTile> {
  bool _down = false;

  void _press(bool down) {
    if (widget.onTap == null || _down == down) return;
    setState(() => _down = down);
  }

  void _tap() {
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final still = MediaQuery.disableAnimationsOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final enabled = widget.onTap != null;
    final rest = dark ? ApnivaasColors.darkWell : ApnivaasColors.well;
    final pressed = Color.alphaBlend(
        (dark ? ApnivaasColors.headerTitle : ApnivaasColors.forest)
            .withValues(alpha: dark ? 0.08 : 0.12),
        rest);

    final well = AnimatedScale(
      scale: _down && !still ? 0.94 : 1,
      duration: _down ? Motion.press : Motion.fast,
      curve: Motion.enter,
      child: AnimatedContainer(
        duration: still ? Duration.zero : Motion.fast,
        width: QuickActionTile.wellSize,
        height: QuickActionTile.wellSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _down ? pressed : rest, borderRadius: Radii.rWell),
        child: ClayIcon(widget.icon,
            size: ClaySize.action, opacity: enabled ? 1 : Dim.readOnly),
      ),
    );

    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      maxLines: scale >= 1.5 ? 3 : 2,
      overflow: TextOverflow.ellipsis,
      style: t.textTheme.labelMedium?.copyWith(
        color: enabled ? null : t.colorScheme.onSurfaceVariant,
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      onTap: enabled ? _tap : null,
      child: Listener(
        onPointerDown: (_) => _press(true),
        onPointerUp: (_) => _press(false),
        onPointerCancel: (_) => _press(false),
        child: InkWell(
          onTap: enabled ? _tap : null,
          borderRadius: Radii.rCard,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xxs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [well, const SizedBox(height: Space.tight), label],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Quick actions" card: a heading, an optional "View all", and a grid of tiles.
///
/// THE COLUMN COUNT IS WORKED OUT, NOT FIXED. Four columns up to 1.5x text, three up to 1.8x,
/// and two above that with the tile laid out icon-beside-label so the words keep their width.
/// Three as well whenever the content is under 300dp wide — the 320dp phones. At 360dp the
/// four columns are 74dp each, which holds the 64dp well.
///
/// THEN THE WORDS GET A VOTE. That count is the most the width and text size allow; the grid
/// drops a column at a time — to a single column of icon-beside-label rows at the last — until
/// the longest word in any label fits its cell. A label wraps between words or not at all:
/// "Read complaints" at 1.4x on a 360dp phone used to set "complaint" on one line and "s" on
/// the next, and "Monthly" broke as "Monthl y" at 2.0x.
class QuickActionGrid extends StatelessWidget {
  const QuickActionGrid({
    super.key,
    required this.actions,
    this.title = 'Quick actions',
    this.actionLabel,
    this.onAction,
    this.contained = true,
  });

  final List<QuickActionTile> actions;

  /// Null drops the heading row.
  final String? title;

  /// "View all", for the sheet with every action.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// False draws the grid alone, without its card — for a screen that already has one.
  final bool contained;

  /// The most columns [width] and [textScale] allow. The grid uses fewer when a word would not
  /// fit (see the class note).
  static int columnsFor(double width, double textScale) {
    if (textScale >= 1.8) return 2;
    if (textScale >= 1.5 || width < 300) return 3;
    return 4;
  }

  static const _gap = Space.xxs;

  /// The width a label is set in, in a grid of [columns] across [width]: the whole cell under
  /// the well at three or four across, what the well leaves beside it at two or one.
  static double labelWidthFor(double width, int columns) {
    final cell = (width - _gap * (columns - 1)) / columns;
    if (columns >= 3) return cell;
    return cell - Space.xxs * 2 - ClaySize.list - Space.xs;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);

    final grid = LayoutBuilder(builder: (context, c) {
      final widest =
          WordFit.widestWord(context, actions.map((a) => a.label), t.textTheme.labelMedium);
      var columns = columnsFor(c.maxWidth, scale);
      while (columns > 1 && widest > labelWidthFor(c.maxWidth, columns)) {
        columns--;
      }
      const gap = _gap;
      final cell = (c.maxWidth - gap * (columns - 1)) / columns;
      final rows = <Widget>[];
      for (var i = 0; i < actions.length; i += columns) {
        final slice = actions.sublist(i, (i + columns).clamp(0, actions.length));
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: gap),
              SizedBox(
                width: cell,
                child: j < slice.length
                    ? (columns <= 2 ? _WideAction(tile: slice[j]) : slice[j])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ));
        if (i + columns < actions.length) rows.add(const SizedBox(height: Space.sm + Space.hair));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    });

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          SectionHeader(
            title: title!,
            size: SectionHeaderSize.card,
            actionLabel: actionLabel,
            onAction: onAction,
            padding: const EdgeInsets.symmetric(horizontal: Space.tight),
          ),
          const SizedBox(height: Space.xs),
        ],
        grid,
      ],
    );

    if (!contained) return body;
    // Flat, like every resting card: the fill and its hairline separate it (see [Shadows]).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: Radii.rSurface,
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Space.sm - Space.hair, Space.sm + Space.hair, Space.sm - Space.hair, Space.sm + Space.hair),
        child: body,
      ),
    );
  }
}

/// A quick action at very large text, or with a word too long for a narrow cell: the well
/// beside its label, so the words keep the width of the cell instead of being squeezed under a
/// 64dp well.
class _WideAction extends StatelessWidget {
  const _WideAction({required this.tile});

  final QuickActionTile tile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final enabled = tile.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tile.semanticLabel ?? tile.label,
      excludeSemantics: true,
      onTap: tile.onTap,
      child: InkWell(
        onTap: tile.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                tile.onTap!();
              },
        borderRadius: Radii.rCard,
        child: Padding(
          padding: const EdgeInsets.all(Space.xxs),
          child: Row(
            children: [
              Container(
                width: ClaySize.list,
                height: ClaySize.list,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dark ? ApnivaasColors.darkWell : ApnivaasColors.well,
                  borderRadius: Radii.rControl,
                ),
                child: ClayIcon(tile.icon, size: ClaySize.list - Space.xs),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(tile.label,
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: t.textTheme.labelMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
