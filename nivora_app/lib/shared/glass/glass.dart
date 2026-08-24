library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The glass layer.
///
/// One primitive — [GlassSurface] — plus [FlatSurface] for everything that does not deserve
/// glass, and thin wrappers over the two. Everything glass in Nivora goes through here, so
/// "make the panes a shade less transparent" is one edit in [GlassWeight].
///
/// ── WHAT A PANE IS ───────────────────────────────────────────────────────────────────────
///
/// A pane paints its own theme's `colorScheme.surface` at [GlassWeight.opacity] over a blurred
/// backdrop, and edges itself with a single hairline. That is all. In the light theme the veil
/// is white; in the dark theme it is #101827 — NOT white at a smaller number, which lightens a
/// dark pane toward its own near-white text and is illegible the moment anything bright
/// scrolls under it. The measured proof is in [GlassWeight]; do not "restore" a white tint.
///
/// ── THREE RULES THIS FILE ENFORCES ───────────────────────────────────────────────────────
///
/// 1. **Glass is an elevation cue, not a skin.** It marks a surface as floating ABOVE
///    something. A glass card on a glass panel inside a glass sheet reads as fog, so
///    [GlassSurface] asserts in debug when it finds itself nested more than one deep. When you
///    need an inner surface, that is what [FlatSurface] is for — and reaching for it is the
///    normal case, not the fallback. Roughly one pane per screen carries the thing that
///    matters; the rest sit quietly behind an outline.
///
/// 2. **Nothing here competes with the data.** There is no decorative gradient, no glow, no
///    inner highlight. An earlier version painted a white 22% diagonal sheen across every pane
///    to suggest a curved surface catching light; on a dashboard that sheen sat directly on
///    top of the number the screen exists to show. A pane earns its depth from the blur and
///    the hairline, and then gets out of the way.
///
/// 3. **The blur is optional; the layout is not.** When [Motion.glassFallback] is set — a
///    low-end device, or a user who has asked for reduced transparency — the BackdropFilter is
///    skipped and the identical box is painted opaque. Same geometry, same padding, same
///    radius, so nothing reflows and no screen needs a second design. Performance beats the
///    effect: a premium interface that drops frames is not premium.

/// Tracks glass depth down the tree so nesting can be caught in debug.
class _GlassDepth extends InheritedWidget {
  const _GlassDepth({required this.depth, required super.child});
  final int depth;

  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassDepth>()?.depth ?? 0;

  @override
  bool updateShouldNotify(_GlassDepth old) => old.depth != depth;
}

/// The only widget that actually paints glass.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.weight = GlassWeight.thin,
    this.borderRadius = Radii.rCard,
    this.padding,
    this.shadows = Shadows.level2,
    this.border,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final GlassWeight weight;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow> shadows;

  /// Overrides the default hairline on all four sides. A full-bleed bar wants an edge only
  /// where it meets content — see [GlassHeader]. Build it from [edgeColor].
  final BoxBorder? border;

  final VoidCallback? onTap;
  final String? semanticLabel;

  /// The hairline colour for a pane in the current theme. Ink on light, white on dark: the
  /// edge has to move AWAY from the pane's own fill, and the pane's fill is near-white in one
  /// theme and near-black in the other.
  static Color edgeColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: GlassWeight.darkEdge)
        : NivoraColors.midnight.withValues(alpha: GlassWeight.lightEdge);
  }

  @override
  Widget build(BuildContext context) {
    final depth = _GlassDepth.of(context);
    assert(
      depth < 2,
      'Glass nested $depth deep. Glass marks one step of elevation; stacking it reads as fog '
      'rather than depth. Use FlatSurface for the inner surface.',
    );

    final scheme = Theme.of(context).colorScheme;
    final edge = border ?? Border.all(color: edgeColor(context), width: Strokes.hairline);

    // The pane. In the fallback path the ONLY difference is that the veil is fully opaque and
    // the BackdropFilter is skipped — every other dimension is identical, which is the point.
    final opaque = Motion.glassFallback;
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque ? scheme.surface : scheme.surface.withValues(alpha: weight.opacity),
        borderRadius: borderRadius,
        border: edge,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (!opaque) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: weight.blur, sigmaY: weight.blur),
        child: surface,
      );
    }

    Widget result = DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(borderRadius: borderRadius, child: surface),
    );

    if (onTap != null) {
      result = Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(borderRadius: borderRadius, onTap: onTap, child: result),
      );
    }
    if (semanticLabel != null) {
      result = Semantics(label: semanticLabel, container: true, child: result);
    }
    return _GlassDepth(depth: depth + 1, child: result);
  }
}

/// An opaque surface with a hairline. No blur, no shadow, no elevation claim.
///
/// This is the DEFAULT surface in Nivora and glass is the exception, which is the opposite of
/// how the design reads if you only look at the widget names. Use this for anything that is
/// simply content on a page: list rows, stat tiles, grouped sections, anything inside a pane.
class FlatSurface extends StatelessWidget {
  const FlatSurface({
    super.key,
    required this.child,
    this.borderRadius = Radii.rCard,
    this.padding,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget result = Material(
      color: scheme.surface,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        // A null onTap leaves InkWell inert rather than absorbing the gesture.
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // outline (cardBorder, 1.48:1), not outlineVariant (hairline, 1.18:1). This is a
            // card's edge against the canvas, not a divider between two things already on the
            // same surface. theme.dart keeps those two jobs on separate tokens for exactly
            // this decision.
            border: Border.all(color: scheme.outline, width: Strokes.hairline),
          ),
          child: child,
        ),
      ),
    );
    if (semanticLabel != null) {
      result = Semantics(label: semanticLabel, container: true, child: result);
    }
    return result;
  }
}

/// A resting content card. Glass, so use it for the one thing on the screen that is elevated
/// above the rest — not for every row.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding, this.onTap, this.semanticLabel});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => GlassSurface(
        weight: GlassWeight.thin,
        padding: padding ?? const EdgeInsets.all(Space.md),
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: child,
      );
}

/// A bar content scrolls beneath. Handles its own top inset so screens do not each re-derive it.
///
/// Edged along the bottom only, and unshadowed. A drop shadow under a full-bleed bar is the
/// cheapest-looking thing in mobile design and it is redundant here: the bar is already a
/// [GlassWeight.regular] pane, so content visibly dims and blurs as it passes under. One
/// hairline says "the page starts here" without putting a grey smear over the first row.
class GlassHeader extends StatelessWidget {
  const GlassHeader({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => GlassSurface(
        weight: GlassWeight.regular,
        borderRadius: BorderRadius.zero,
        shadows: Shadows.level1,
        border: Border(
          bottom: BorderSide(color: GlassSurface.edgeColor(context), width: Strokes.hairline),
        ),
        padding: (padding ?? const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm))
            .add(EdgeInsets.only(top: MediaQuery.paddingOf(context).top)),
        child: child,
      );
}

/// One statistic.
///
/// Flat by default, on purpose. A grid of glass tiles is the "rainbow dashboard" the brief
/// warns against: six panes of equal elevation say nothing about which number matters, and the
/// blur under each one costs a frame to say it. [emphasised] opts a single tile into glass —
/// use it at most once per screen, for the figure the screen is about.
class GlassStatCard extends StatelessWidget {
  const GlassStatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone,
    this.onTap,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  /// Semantic accent. Left null for the common case — colour should mean something.
  final Color? tone;
  final VoidCallback? onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // A canonical tone is resolved to this theme's legible value. The icon it paints is a
    // graphical object either way, but the resolved value is the one that stays readable if a
    // caller ever passes the same tone to a Text. See NivoraSemantics.resolve.
    final accent = tone == null ? t.colorScheme.primary : context.tones.resolve(tone!);
    final semantics = '$label: $value${caption == null ? '' : '. $caption'}';

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: IconSize.sm, color: accent),
            const SizedBox(width: Space.xs),
          ],
          Expanded(
            child: Text(label.toUpperCase(), style: t.textTheme.labelSmall, maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: Space.xs),
        // headlineMedium is tabular — a refreshing column of figures must not shuffle.
        Text(value, style: t.textTheme.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (caption != null) ...[
          const SizedBox(height: Space.xxs),
          Text(caption!, style: t.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );

    if (emphasised) {
      return GlassSurface(
        weight: GlassWeight.thin,
        padding: const EdgeInsets.all(Space.md),
        onTap: onTap,
        semanticLabel: semantics,
        child: body,
      );
    }
    return FlatSurface(
      padding: const EdgeInsets.all(Space.md),
      onTap: onTap,
      semanticLabel: semantics,
      child: body,
    );
  }
}

/// The grab bar at the top of a sheet.
///
/// Drawn here rather than by Material, and the reason is geometry. `showModalBottomSheet`
/// honours `bottomSheetTheme.showDragHandle`, and when it does it puts a 48dp band ABOVE the
/// sheet's own child. That works for a sheet whose Material paints the background — the handle
/// lands on it. Ours does not: the background is transparent so the [GlassSurface] can be the
/// only pane. Measured, the stock handle sat at y 428–476 while the pane began at y 476, i.e.
/// a grey pill floating over the dimmed page with 48dp of empty barrier between it and the
/// sheet it belonged to, on every sheet in the app. Owning it moves it onto the pane and gives
/// a short phone back those 48dp.
class _SheetGrip extends StatelessWidget {
  const _SheetGrip();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Drag down to dismiss',
      child: Center(
        child: Container(
          width: Space.xxl + Space.xxs, // 36
          height: Space.xxs, // 4
          margin: const EdgeInsets.only(bottom: Space.md),
          decoration: BoxDecoration(
            // A control, so 3:1 applies — the same token the stock handle was wired to.
            color: Theme.of(context).brightness == Brightness.dark
                ? NivoraColors.darkControlBorder
                : NivoraColors.controlBorder,
            borderRadius: Radii.rPill,
          ),
        ),
      ),
    );
  }
}

/// Presents a glass bottom sheet. Centralised so every sheet in the app shares the same
/// geometry, drag handle and inset handling.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    // See [_SheetGrip]: the stock handle cannot land on a transparent-background sheet.
    showDragHandle: false,
    barrierColor: NivoraColors.midnight.withValues(alpha: 0.32),
    builder: (ctx) => Padding(
      // Keeps the sheet above the keyboard without each caller remembering to.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: GlassSurface(
        weight: GlassWeight.thick,
        borderRadius: Radii.rSheetTop,
        shadows: Shadows.level3,
        padding: EdgeInsets.only(
          left: Space.md, right: Space.md, top: Space.md,
          bottom: Space.md + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetGrip(),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    ),
  );
}
