library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'quick_actions.dart' show QuickActionGrid, QuickActionTile;

/// THE LOADING STATE: quiet blocks in the shape of what is coming, breathing slowly.
///
/// ── ONE CONTROLLER, ONE LAYER ────────────────────────────────────────────────────────────
///
/// A [SkeletonPulse] owns a single 1.2s opacity breath for everything beneath it, applied as
/// ONE fade over the whole group — not a ticker per bar, and not a shimmer sweep, which costs
/// a shader per bar per frame on the budget phones this ships to. The blocks themselves are
/// static boxes. [ListSkeleton], [TileSkeleton] and [QuickActionsSkeleton] bring their own
/// pulse; a bare [Skeleton] outside any pulse brings one too, so it is never accidentally
/// frozen.
///
/// IT STOPS WHEN IT IS NOT SEEN. A skeleton inside a hidden tab of a shell's IndexedStack is
/// laid out but never painted, and the pulse reads [Visibility.of] to stop its ticker there.
/// Under reduce motion there is no ticker at all: the blocks hold still at 80%.
///
/// It disappears the moment data arrives, because the caller stops building it — nothing here
/// waits, retries or decides anything. The group is ONE semantics node, a live region saying
/// what is loading; the blocks are excluded.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child, this.semanticLabel = 'Loading'});

  final Widget child;

  /// What a screen reader announces — "Loading overview".
  final String semanticLabel;

  /// True when [context] is already inside a pulse, so a nested group does not start another.
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PulseScope>() != null;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = !MediaQuery.disableAnimationsOf(context) && Visibility.of(context);
    if (run && _controller == null) {
      final c = AnimationController(vsync: this, duration: Motion.skeletonPulse ~/ 2);
      _controller = c;
      _opacity = Tween<double>(begin: 1, end: Dim.skeletonPulse)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
      c.repeat(reverse: true);
    } else if (!run && _controller != null) {
      _controller!.dispose();
      _controller = null;
      _opacity = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _opacity;
    final Widget blocks = opacity == null
        ? Opacity(opacity: Dim.skeletonStill, child: widget.child)
        : FadeTransition(opacity: opacity, child: widget.child);
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: _PulseScope(child: blocks),
    );
  }
}

class _PulseScope extends InheritedWidget {
  const _PulseScope({required super.child});

  @override
  bool updateShouldNotify(_PulseScope oldWidget) => false;
}

/// One placeholder block, sized like the thing it stands in for.
///
/// [widthFactor] is a share of the available width, so a line reads the same on a 320dp phone
/// and a tablet, and nothing overflows at 2.0x text — a block has no text to grow.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.widthFactor,
    this.height = Space.sm,
    this.radius,
    this.circle = false,
    this.onGround = false,
  });

  final double? width;
  final double? widthFactor;
  final double height;

  /// Defaults to half the height — a soft bar.
  final BorderRadius? radius;

  /// A disc of [height] — an avatar, a clay icon's place.
  final bool circle;

  /// True for a block sitting straight on the page ground rather than on a card.
  final bool onGround;

  /// The block colour for this theme and ground.
  static Color colorOf(BuildContext context, {bool onGround = false}) {
    if (Theme.of(context).brightness == Brightness.dark) return ApnivaasColors.surfaceBright;
    return onGround ? ApnivaasColors.skeletonOnGround : ApnivaasColors.skeleton;
  }

  @override
  Widget build(BuildContext context) {
    Widget box = Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: colorOf(context, onGround: onGround),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : (radius ?? BorderRadius.circular(height / 2)),
      ),
    );
    if (widthFactor != null && !circle) {
      box = FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: box,
      );
    }
    if (SkeletonPulse.isActive(context)) return box;
    return SkeletonPulse(child: box);
  }
}

/// A list group still loading: a card of [rows] 70dp rows, each a disc and two bars, with the
/// hairline dividers the real rows will have.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    this.rows = 3,
    this.leading = true,
    this.semanticLabel = 'Loading',
  });

  final int rows;

  /// The 46dp disc where a clay icon or an avatar will be.
  final bool leading;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SkeletonPulse(
      semanticLabel: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: Radii.rSurface,
          border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm + Space.hair, vertical: Space.xxs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows; i++) ...[
                if (i > 0) Divider(height: Strokes.hairline, color: t.dividerTheme.color),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 70),
                  child: Row(
                    children: [
                      if (leading) ...[
                        const Skeleton(height: ClaySize.list, circle: true),
                        const SizedBox(width: Space.sm),
                      ],
                      const Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Skeleton(widthFactor: 0.6),
                            SizedBox(height: Space.xs),
                            Skeleton(widthFactor: 0.4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The quick-action card still loading: the card, and [count] wells with a short bar under each,
/// on the column count the real [QuickActionGrid] starts from, so nothing jumps when it lands.
/// (The grid drops a column only when a label holds a word too long for its cell, which a
/// skeleton with no labels cannot know.)
class QuickActionsSkeleton extends StatelessWidget {
  const QuickActionsSkeleton({super.key, this.count = 8, this.semanticLabel = 'Loading'});

  final int count;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SkeletonPulse(
      semanticLabel: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.colorScheme.surface,
          borderRadius: Radii.rSurface,
          border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.sm - Space.hair, vertical: Space.sm + Space.hair),
          child: LayoutBuilder(builder: (context, c) {
            final columns = QuickActionGrid.columnsFor(c.maxWidth, scale);
            return Wrap(
              runSpacing: Space.sm + Space.hair,
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(
                    width: c.maxWidth / columns,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Skeleton(
                          width: QuickActionTile.wellSize,
                          height: QuickActionTile.wellSize,
                          radius: Radii.rWell,
                        ),
                        const SizedBox(height: Space.tight + Space.hair),
                        const Skeleton(width: Space.huge, height: Space.sm - Space.hair),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// A stat tile still loading: the tile's own shape — a disc where the clay icon goes, a wide
/// bar for the figure, a short one for the label. A whole Overview strip still loading is
/// `StatCarouselSkeleton` (stat_tile.dart), which the carousel itself lays out.
class TileSkeleton extends StatelessWidget {
  const TileSkeleton({super.key, this.width, this.semanticLabel = 'Loading'});

  /// Null takes the parent's width.
  final double? width;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: Radii.rSurface,
        border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(Space.sm + Space.hair, Space.sm, Space.sm + Space.hair, Space.sm),
        child: SizedBox(
          height: 150 - Space.sm * 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(height: ClaySize.tile, circle: true),
              Spacer(),
              Skeleton(widthFactor: 0.7, height: Space.lg),
              SizedBox(height: Space.xs),
              Skeleton(widthFactor: 0.5),
            ],
          ),
        ),
      ),
    );
    return SkeletonPulse(
      semanticLabel: semanticLabel,
      child: width == null ? tile : SizedBox(width: width, child: tile),
    );
  }
}
