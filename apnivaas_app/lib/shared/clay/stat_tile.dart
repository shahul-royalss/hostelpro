library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import 'clay_icons.dart';
import 'pressable.dart';
import 'skeleton.dart';
import 'status_chip.dart';
import 'word_fit.dart';

/// How a [StatTile] presents itself.
enum StatTileStyle {
  /// The warm white card with a hairline: a figure and what it counts.
  plain,

  /// THE ONE FIGURE A SCREEN LEADS WITH: forest in both themes, white figure, an optional gold
  /// progress bar. At most one per screen.
  hero,

  /// A Mist link tile — "View analytics": a title in place of a figure, and a destination.
  tonal,
}

/// One statistic: a clay icon, a big tabular figure, and the words that say what it counts.
///
/// No fixed height — 150dp at rest and taller whenever the text needs it — and the figure is
/// one line that scales down rather than truncating, so a lakh-sized rupee amount still fits a
/// 156dp tile at 2.0x text. The whole tile is ONE semantics node ("Collected in October,
/// ₹1,24,500, of ₹1,60,000 · 78%"), and a button when [onTap] is set.
///
/// [valueTone] colours the FIGURE with a status ink and leaves the tile itself untinted: the
/// caption carries the word, and a tile is never painted in its status.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.caption,
    this.delta,
    this.deltaTone = StatusTone.neutral,
    this.badge,
    this.valueTone,
    this.progress,
    this.onTap,
    this.style = StatTileStyle.plain,
    this.width,
    this.semanticLabel,
  });

  /// What the figure counts — "Today's collection". On a [StatTileStyle.tonal] tile this is the
  /// smaller line under the title.
  final String label;

  /// The figure, already formatted — "₹8,500", "42/48". On a tonal tile, its title.
  final String value;

  /// A [ClayIcons] path. 56dp on a plain or tonal tile; 78dp in the hero's corner, or 56 there
  /// too when the figure needs the whole line.
  final String? icon;

  /// The line under the figure — "of ₹1,60,000 · 78%".
  final String? caption;

  /// A change worth a chip — "+12%", "3 new" — drawn as a [StatusChip] in [deltaTone].
  final String? delta;
  final StatusTone deltaTone;

  /// Anything for the top trailing corner of a plain or tonal tile — a "Sample data" chip.
  final Widget? badge;

  /// A canonical or resolved status tone for the figure.
  final Color? valueTone;

  /// 0..1, drawn as the hero tile's gold bar. The percentage must also be in [caption]: a bar
  /// is never the only carrier of a number.
  final double? progress;

  final VoidCallback? onTap;
  final StatTileStyle style;

  /// A fixed width. Null takes the parent's width — except inside a [StatCarousel], which
  /// sizes its tiles itself.
  final double? width;

  /// Replaces the spoken summary when the visible strings do not read well aloud.
  final String? semanticLabel;

  /// The canvas's carousel widths at 1.0x text. They grow with the text scale up to 1.4x.
  static const heroWidth = 214.0;
  static const plainWidth = 156.0;
  static const minHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final hero = style == StatTileStyle.hero;
    final tonal = style == StatTileStyle.tonal;

    final Color fill = hero
        ? ApnivaasColors.forest
        : tonal
            ? (dark ? ApnivaasColors.darkMist : ApnivaasColors.mist)
            : t.colorScheme.surface;
    final Color? edge = hero || tonal ? null : t.colorScheme.outlineVariant;

    final spoken = semanticLabel ??
        [label, value, ?caption, ?delta].join(', ');

    final w = width ?? _CarouselSlot.widthOf(context, hero: hero);
    final Widget body =
        hero ? _heroBody(context, w) : _body(context, w, tonal: tonal, dark: dark);

    Widget tile = Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.rSurface,
        side: edge == null ? BorderSide.none : BorderSide(color: edge, width: Strokes.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: hero ? ApnivaasColors.headerButtonFill : null,
        highlightColor: hero ? ApnivaasColors.headerButtonFill : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: body,
        ),
      ),
    );

    tile = Semantics(
      container: true,
      button: onTap != null,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: PressScale(enabled: onTap != null, child: tile),
    );

    return w == null ? tile : SizedBox(width: w, child: tile);
  }

  Widget _body(BuildContext context, double? tileWidth, {required bool tonal, required bool dark}) {
    final t = Theme.of(context);
    final tones = context.tones;
    final valueStyle = tonal
        ? context.textRoles.tileTitle.copyWith(
            color: dark ? ApnivaasColors.onSurface : ApnivaasColors.forest)
        : t.textTheme.headlineMedium?.copyWith(
            color: valueTone == null ? null : tones.resolve(valueTone!));
    final labelStyle = tonal
        ? t.textTheme.bodySmall?.copyWith(
            color: dark ? ApnivaasColors.onSurfaceVariant : ApnivaasColors.mistInk)
        : t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);

    // The words' own column, when the tile's width is known. A word too long for it is set a
    // little smaller rather than broken in the middle (see [WordFit]): at 2.0x a half-width
    // tile set "12 outstanding bills" as "12 outstand" over "ing bills".
    final words = tileWidth == null ? null : tileWidth - (Space.sm + Space.hair) * 2;
    // From the text size at which the carousel becomes a wrap, a line more for the words: a
    // half-width tile at 2.0x holds about one word a line, and "12 outstanding bills" is three.
    final lines = MediaQuery.textScalerOf(context).scale(1) >= 1.6 ? 3 : 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm + Space.hair, Space.sm, Space.sm + Space.hair, Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null || badge != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ClayIcon(icon!, size: ClaySize.tile),
                const Spacer(),
                ?badge,
              ],
            ),
          SizedBox(height: tonal ? Space.sm - Space.hair : Space.xs),
          if (tonal)
            Text(value,
                style: valueStyle,
                textScaler: WordFit.scalerFor(context, value, valueStyle, words),
                maxLines: 2,
                overflow: TextOverflow.ellipsis)
          else
            _Figure(value, style: valueStyle),
          const SizedBox(height: Space.hair),
          Text(label,
              style: labelStyle,
              textScaler: WordFit.scalerFor(context, label, labelStyle, words),
              maxLines: lines,
              overflow: TextOverflow.ellipsis),
          if (caption != null) ...[
            const SizedBox(height: Space.hair),
            Text(caption!,
                style: labelStyle,
                textScaler: WordFit.scalerFor(context, caption!, labelStyle, words),
                maxLines: lines,
                overflow: TextOverflow.ellipsis),
          ],
          if (delta != null) ...[
            const SizedBox(height: Space.xs),
            StatusChip(label: delta!, tone: deltaTone),
          ],
        ],
      ),
    );
  }

  Widget _heroBody(BuildContext context, double? tileWidth) {
    final roles = context.textRoles;
    final sub = ApnivaasType.manrope(12, 16, FontWeight.w600, ApnivaasColors.headerSub);
    final figureStyle = roles.statValue.copyWith(color: ApnivaasColors.headerTitle);
    final art = icon == null ? null : _heroArtSize(context, tileWidth, figureStyle);
    final p = progress;
    return Stack(
      children: [
        if (art != null)
          PositionedDirectional(
            top: Space.xxs,
            end: Space.hair,
            child: ClayIcon(icon!, size: art),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm + Space.hair, Space.md, Space.sm + Space.hair),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                // The label stops short of the clay icon in the corner rather than running
                // under it.
                padding: EdgeInsetsDirectional.only(end: art == null ? 0 : _artInset(art)),
                child: Text(label, style: sub, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: Space.xl + Space.tight),
              Padding(
                // So does the figure beside the full-size art: it scales down before it would
                // touch the picture. Beside the smaller art it has the whole line, because that
                // art ends above it (see [_heroArtSize]).
                padding: EdgeInsetsDirectional.only(
                    end: art == ClaySize.hero ? _artInset(ClaySize.hero) : 0),
                child: _Figure(value, style: figureStyle),
              ),
              if (caption != null)
                Text(caption!,
                    style: sub.copyWith(fontWeight: FontWeight.w400),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              if (p != null) ...[
                const SizedBox(height: Space.xs),
                _GoldBar(value: p.clamp(0.0, 1.0)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// How far in from the hero's padded edge a corner picture of [art] dp begins.
  static double _artInset(double art) => art + Space.hair - Space.md;

  /// The hero's corner art: the full 78dp when the figure fits the line beside it, the 56dp
  /// tile size when it does not.
  ///
  /// The figure's line starts level with the lower half of a 78dp picture, so a lakh-sized
  /// "₹1,24,500" ran under it. Shrinking the figure into the column left beside the art would
  /// make the one number a screen leads with the smallest on it; instead the picture steps
  /// down to 56dp, which ends above that line, and the figure keeps the full width. Measured
  /// with a [TextPainter] rather than a LayoutBuilder, because a [StatCarousel] sizes its row
  /// intrinsically and a LayoutBuilder cannot answer an intrinsic question. A tile with no
  /// known width assumes it spans the page.
  double _heroArtSize(BuildContext context, double? tileWidth, TextStyle figureStyle) {
    final tile = tileWidth ?? MediaQuery.sizeOf(context).width - Space.md * 2;
    final room = tile - Space.md * 2 - _artInset(ClaySize.hero);
    final painter = TextPainter(
      text: TextSpan(text: value, style: figureStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final fits = painter.width <= room;
    painter.dispose();
    return fits ? ClaySize.hero : ClaySize.tile;
  }
}

/// A figure that scales down to fit its line instead of wrapping or truncating.
class _Figure extends StatelessWidget {
  const _Figure(this.value, {required this.style});

  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(value, style: style, maxLines: 1, softWrap: false),
      );
}

/// The hero tile's progress: gold on the forest track, 3.13:1 as a graphic.
class _GoldBar extends StatelessWidget {
  const _GoldBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: Radii.rPill,
        child: SizedBox(
          height: 7,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: ApnivaasColors.forestTrack)),
              FractionallySizedBox(
                widthFactor: value,
                heightFactor: 1,
                alignment: AlignmentDirectional.centerStart,
                child: const ColoredBox(color: ApnivaasColors.gold),
              ),
            ],
          ),
        ),
      );
}

/// Tells a [StatTile] it is in a carousel and how wide to be.
class _CarouselSlot extends InheritedWidget {
  const _CarouselSlot({
    required this.scale,
    required this.wrapWidth,
    required this.fullWidth,
    required super.child,
  });

  /// The text scale, clamped to 1.0–1.4.
  final double scale;

  /// Set when the carousel has become a two-column wrap: the width of one column, and of the
  /// whole row the hero takes.
  final double? wrapWidth;
  final double? fullWidth;

  static double? widthOf(BuildContext context, {required bool hero}) {
    final slot = context.dependOnInheritedWidgetOfExactType<_CarouselSlot>();
    if (slot == null) return null;
    final wrap = slot.wrapWidth;
    if (wrap != null) return hero ? slot.fullWidth : wrap;
    return (hero ? StatTile.heroWidth : StatTile.plainWidth) * slot.scale;
  }

  @override
  bool updateShouldNotify(_CarouselSlot old) =>
      old.scale != scale || old.wrapWidth != wrapWidth || old.fullWidth != fullWidth;
}

/// The row of stat tiles under "Overview": the hero first, the next tile peeking in.
///
/// It bleeds edge to edge — its own padding is the page gutter — so place it in a column
/// WITHOUT horizontal padding of its own, or pass [gutter] to match yours. Every tile in a row
/// is as tall as the tallest.
///
/// AT LARGE TEXT IT STOPS SCROLLING. From 1.6x on a phone under 400dp a sideways strip of
/// half-hidden tiles is a strip nobody can read, so it becomes a two-column wrap with the hero
/// across the full width.
class StatCarousel extends StatelessWidget {
  const StatCarousel({super.key, required this.children, this.gutter = Space.md});

  final List<Widget> children;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final rawScale = MediaQuery.textScalerOf(context).scale(1);
    final scale = rawScale.clamp(1.0, 1.4);
    final width = MediaQuery.sizeOf(context).width;

    if (rawScale >= 1.6 && width < 400) {
      return LayoutBuilder(builder: (context, c) {
        final full = c.maxWidth - gutter * 2;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: _CarouselSlot(
            scale: scale,
            wrapWidth: (full - Space.sm) / 2,
            fullWidth: full,
            child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: children),
          ),
        );
      });
    }

    return _CarouselSlot(
      scale: scale,
      wrapWidth: null,
      fullWidth: null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.xxs),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: Space.sm),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A [StatCarousel] still loading: one block in the shape of each tile — the hero's width first,
/// then [plainTiles] plain ones — under ONE pulse, so a screen reader hears [semanticLabel] once.
///
/// It is laid out BY a [StatCarousel], so it takes the carousel's widths, gutter and large-text
/// wrap exactly: nothing moves sideways when the figures land, and at 2.0x the blocks are
/// already the two-column wrap the real tiles will be, not a strip that turns into one.
class StatCarouselSkeleton extends StatelessWidget {
  const StatCarouselSkeleton({
    super.key,
    this.plainTiles = 2,
    this.semanticLabel = 'Loading',
    this.gutter = Space.md,
  });

  final int plainTiles;
  final String semanticLabel;
  final double gutter;

  @override
  Widget build(BuildContext context) => SkeletonPulse(
        semanticLabel: semanticLabel,
        child: StatCarousel(
          gutter: gutter,
          children: [
            const _TileBlock(hero: true),
            for (var i = 0; i < plainTiles; i++) const _TileBlock(hero: false),
          ],
        ),
      );
}

/// One tile's outline: the card, a disc where the clay icon goes, a wide bar for the figure and
/// a short one for the label, at the carousel slot's width and the tile's resting height.
class _TileBlock extends StatelessWidget {
  const _TileBlock({required this.hero});

  final bool hero;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: _CarouselSlot.widthOf(context, hero: hero),
      height: StatTile.minHeight,
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: Radii.rSurface,
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(height: ClaySize.tile, circle: true),
          Spacer(),
          Skeleton(widthFactor: 0.7, height: Space.lg),
          SizedBox(height: Space.xs),
          Skeleton(widthFactor: 0.5),
        ],
      ),
    );
  }
}
