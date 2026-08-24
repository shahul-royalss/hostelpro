library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The Liquid Glass layer.
///
/// One primitive — [GlassSurface] — and thin wrappers over it. Everything glass in Nivora goes
/// through here, so "make the glass slightly less transparent" is one edit in [GlassWeight].
///
/// TWO RULES THIS FILE ENFORCES, because they are what separates expensive-looking glass from
/// the cheap kind:
///
/// 1. **Glass is an elevation treatment, not a skin.** It marks a surface as floating ABOVE
///    something. A glass card on a glass panel inside a glass sheet reads as fog, so
///    [GlassSurface] asserts in debug when it finds itself nested more than one deep.
///
/// 2. **The blur is optional; the layout is not.** When [Motion.glassFallback] is set — a
///    low-end device, or the user asking for reduced transparency — the BackdropFilter is
///    skipped and an opaque tinted surface is painted instead. Identical geometry, so nothing
///    reflows and no screen needs a second design. Performance beats the effect: a premium
///    interface that drops frames is not premium.

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
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final GlassWeight weight;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow> shadows;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final depth = _GlassDepth.of(context);
    assert(
      depth < 2,
      'Glass nested $depth deep. Glass marks one step of elevation; stacking it reads as fog '
      'rather than depth. Use a plain Container for the inner surface.',
    );

    final dark = Theme.of(context).brightness == Brightness.dark;
    // On dark surfaces a white tint at the light-mode opacity washes the content out, and the
    // border has to be brighter than the fill to still read as an edge.
    final tint = (dark ? Colors.white.withValues(alpha: weight.tint * 0.55)
                       : Colors.white.withValues(alpha: weight.tint + 0.62));
    final border = dark
        ? Colors.white.withValues(alpha: weight.border * 0.30)
        : Colors.white.withValues(alpha: weight.border);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: borderRadius,
        border: Border.all(color: border, width: 1),
        // A barely-there vertical gradient. This is what gives a flat translucent rectangle the
        // sense of a curved pane catching light; without it glass looks like a grey box.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.06 : 0.22),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (!Motion.glassFallback) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: weight.blur, sigmaY: weight.blur),
        child: surface,
      );
    } else {
      // Opaque equivalent. Same box, no filter — the expensive part is the BackdropFilter,
      // not the decoration.
      surface = DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? NivoraColors.darkElevated : NivoraColors.surface,
          borderRadius: borderRadius,
          border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
        ),
        child: padding == null ? child : Padding(padding: padding!, child: child),
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

/// A resting content card.
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
class GlassHeader extends StatelessWidget {
  const GlassHeader({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => GlassSurface(
        weight: GlassWeight.regular,
        borderRadius: BorderRadius.zero,
        shadows: Shadows.level2,
        padding: (padding ?? const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm))
            .add(EdgeInsets.only(top: MediaQuery.paddingOf(context).top)),
        child: child,
      );
}

/// One statistic. Not glass by default on purpose: a grid of glass tiles is the "rainbow
/// dashboard" the brief warns against, so the emphasised variant is opt-in.
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
    final accent = tone ?? t.colorScheme.primary;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: Space.xs),
          ],
          Expanded(
            child: Text(label.toUpperCase(), style: t.textTheme.labelSmall, maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: Space.xs),
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
        semanticLabel: '$label: $value${caption == null ? '' : '. $caption'}',
        child: body,
      );
    }
    return Semantics(
      label: '$label: $value${caption == null ? '' : '. $caption'}',
      container: true,
      child: Material(
        color: t.colorScheme.surface,
        borderRadius: Radii.rCard,
        child: InkWell(
          borderRadius: Radii.rCard,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              borderRadius: Radii.rCard,
              border: Border.all(color: t.colorScheme.outlineVariant),
            ),
            child: body,
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
        child: builder(ctx),
      ),
    ),
  );
}
