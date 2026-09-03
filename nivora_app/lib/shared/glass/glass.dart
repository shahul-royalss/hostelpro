library;

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// The pane layer.
///
/// One primitive — [GlassSurface] — plus [FlatSurface] for everything that does not deserve
/// elevation, and thin wrappers over the two. Every raised surface in Nivora goes through
/// here, so "make the cards a step lighter" is one edit in [GlassWeight.surfaceOf].
///
/// ── THERE IS NO GLASS IN HERE, AND THERE ARE NO SHADOWS EITHER ───────────────────────────
///
/// The names survive because ~40 call sites across `features/` use them and renaming would be
/// a diff nobody could review; what they paint is the Figma design. A pane is a FLAT opaque
/// fill from the design's own three-surface ramp plus a 1px `#292E33` hairline. No
/// `BackdropFilter`, no `ImageFilter`, no alpha on the fill, and — new with the Figma
/// restyle — **no box-shadow**.
///
/// Both of those are the design, not a compromise:
///
/// * **No blur.** It is the most expensive thing this app can draw, the product owner's field
///   report from a real phone was "stuck, lag", and release builds have disabled it
///   unconditionally since the commit "Release builds never blur". Nothing in Figma asks for
///   any. Do not reintroduce it — not behind a flag, not "just for the sheet".
///
/// * **No shadow.** Not one of the nineteen `screen-*` frames carries a `box-shadow`. The
///   design separates a card from the ground with its hairline, and the arithmetic backs it:
///   the card #111417 is only 1.05:1 against the ground, but the hairline #292E33 is 1.42:1,
///   so the EDGE is what you actually see either way. A drop shadow would be adding a smear
///   to do a job the line already does. [Shadows.level2] is therefore an empty list, and the
///   only thing that still casts one is a modal sheet floating over a scrim.
///
/// ── THREE RULES THIS FILE ENFORCES ───────────────────────────────────────────────────────
///
/// 1. **A pane is an elevation cue, not a skin.** It marks a surface as sitting ABOVE
///    something. The ramp is three flat colours and stacking exhausts it: a `thin` card inside
///    a `thin` card is literally the same hex, and with no shadow left there is nothing at all
///    to see. [GlassSurface] therefore asserts in debug when it finds itself more than one
///    deep. When you need an inner surface, that is what [FlatSurface] is for — and reaching
///    for it is the normal case, not the fallback. The design does exactly this: its state
///    cards are the raised fill with `#111417` blocks inside them (4:1603, 4:1606).
///
/// 2. **Nothing here competes with the data.** No decorative gradient, no sheen, no inner
///    highlight. An earlier version painted a white 22% diagonal across every pane to suggest
///    a curved surface catching light; on a dashboard that sheen sat directly on top of the
///    number the screen exists to show. A pane earns its separation from its colour and its
///    hairline, and then gets out of the way.
///
/// 3. **Elevation is colour in the dark and shadow in the light.** In the dark theme the
///    design's ramp gets LIGHTER as it rises. In the light theme M3 inverts that — the card is
///    already the lightest surface — so all weights resolve to the same fill there and the
///    hairline does the separating. That decision is made in exactly one place,
///    [GlassWeight.surfaceOf], and nothing here second-guesses it.

/// Tracks pane depth down the tree so nesting can be caught in debug.
class _GlassDepth extends InheritedWidget {
  const _GlassDepth({required this.depth, required super.child});
  final int depth;

  static int of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassDepth>()?.depth ?? 0;

  @override
  bool updateShouldNotify(_GlassDepth old) => old.depth != depth;
}

/// The only widget that paints a raised pane.
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

  /// [Shadows.level2] is EMPTY — see the header. The parameter survives so a modal can pass
  /// [Shadows.level3], which is the one surface in the app that still floats.
  final List<BoxShadow> shadows;

  /// Overrides the default hairline on all four sides. A full-bleed bar wants an edge only
  /// where it meets content — see [GlassHeader]. Build it from [edgeColor].
  final BoxBorder? border;

  final VoidCallback? onTap;
  final String? semanticLabel;

  /// The hairline colour for a pane in the current theme.
  ///
  /// In the dark theme this is the design's own `#292E33`, which Figma uses for every card
  /// border, divider and avatar disc in the file — one border colour, used everywhere. It
  /// measures 1.35:1 over the card and 1.42:1 over the ground, which is deliberately quiet:
  /// an edge you see and never read.
  ///
  /// In the light theme the edge has to move the other way, so it is ink at
  /// [GlassWeight.lightEdge] (1.39:1 over the card) — the same visual register.
  static Color edgeColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.outlineVariant
        : NivoraColors.textPrimary.withValues(alpha: GlassWeight.lightEdge);
  }

  @override
  Widget build(BuildContext context) {
    final depth = _GlassDepth.of(context);
    assert(
      depth < 2,
      'A pane is nested $depth deep. The elevation ramp has three rungs and stacking exhausts '
      'it — the inner pane ends up the same fill as the one behind it and, since nothing casts '
      'a shadow any more, nothing at all shows. Use FlatSurface for the inner surface.',
    );

    final scheme = Theme.of(context).colorScheme;
    final edge = border ?? Border.all(color: edgeColor(context), width: Strokes.hairline);

    Widget content = padding == null ? child : Padding(padding: padding!, child: child);

    if (onTap != null) {
      // Inside the fill, not behind it. The pane used to be translucent, so an ink splash on
      // a Material underneath showed through; an opaque pane hides it completely and the card
      // just stops responding to touch as far as the eye can tell.
      content = Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: content),
      );
    }

    // One box: fill, hairline and (for a modal) shadow in a single decoration.
    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        color: weight.surfaceOf(scheme),
        borderRadius: borderRadius,
        border: edge,
        boxShadow: shadows,
      ),
      child: ClipRRect(borderRadius: borderRadius, child: content),
    );

    if (semanticLabel != null) {
      result = Semantics(label: semanticLabel, container: true, child: result);
    }
    return _GlassDepth(depth: depth + 1, child: result);
  }
}

/// An opaque surface with a hairline — content on a page.
///
/// This is the DEFAULT surface in Nivora and [GlassSurface] is the exception, which is the
/// opposite of how it reads if you only look at the widget names. Use this for anything that
/// is simply content: list rows, stat tiles, grouped sections, and everything inside a pane.
///
/// Since the design dropped shadows, the two are visually identical at the same weight and
/// the distinction is now purely about nesting: [GlassSurface] asserts when stacked, this does
/// not. Keep using it for inner surfaces — that is what stops the assert firing on a screen
/// somebody assembles later.
class FlatSurface extends StatelessWidget {
  const FlatSurface({
    super.key,
    required this.child,
    this.weight = GlassWeight.thin,
    this.borderRadius = Radii.rCard,
    this.padding,
    this.border = true,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;

  /// Which rung of the design's container ramp to paint. Defaults to a card.
  ///
  /// Step this UP when the surface sits on another one — a row inside a card wants
  /// [GlassWeight.regular], because in the dark theme a `thin` block on a `thin` card is the
  /// same hex and simply disappears. In the light theme every weight is the same white and
  /// the hairline does the separating, which is why this is a weight and not a colour.
  final GlassWeight weight;

  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// The design draws its inner blocks — the skeleton's KPI and list rows (4:1603, 4:1606) —
  /// as a bare fill with no edge, because a hairline inside a hairlined card reads as a table.
  /// Pass false for those.
  final bool border;

  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget result = Material(
      color: weight.surfaceOf(scheme),
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        // A null onTap leaves InkWell inert rather than absorbing the gesture.
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // outlineVariant #292E33 (1.35:1), NOT outline #6F747A (3.92:1). This is a card's
            // decorative edge; `outline` is a CONTROL border and WCAG 1.4.11 pushes it to 3:1,
            // which on a card reads as a text field. theme.dart keeps those two jobs on
            // separate tokens for exactly this decision — do not collapse them.
            border: border
                ? Border.all(color: scheme.outlineVariant, width: Strokes.hairline)
                : null,
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

/// A surface whose GROUND carries a meaning — overdue, resolved, free, expiring.
///
/// The card equivalent of a [StatusPill]: same tones, same alpha, one scale up. Use it for the
/// one thing on a screen that IS a state — the rent card, a KPI whose figure is the answer —
/// and not for a list where every row would get one, because a screen on which everything is
/// tinted has said nothing.
///
/// ── WHY THIS IS NOT THE DECORATIVE GRADIENT RULE 2 BANS ──────────────────────────────────
///
/// The pane doc above forbids a decorative wash across a surface, and it is right: an earlier
/// build painted a white diagonal sheen over every card and it landed on top of the number the
/// screen existed to show. This is a different thing and the difference is the whole
/// justification — the fill here is not decoration, it IS the datum. It is flat, it is opaque,
/// it is one of five measured tones, and it appears only where the app already had a status to
/// state. It is also FLAT rather than a gradient for exactly rule 2's reason: a ramp behind a
/// figure makes the figure's contrast depend on where in the card it happens to sit, which is
/// not a thing that can be measured once and trusted.
///
/// ── THE RULE THIS WIDGET EXISTS TO ENFORCE ───────────────────────────────────────────────
///
/// **No chip of the same tone may sit on this surface.** A chip's fill is a tint of its tone,
/// so over a ground that is already a tint of that tone it lands twice as far toward its own
/// label: measured, **3.98:1 in the dark theme**, a fail that no alpha rescues. The light
/// theme measures 5.03:1 and would have survived it — a light tint moves the ground away from
/// its dark text rather than toward it — but this widget serves both themes and takes the
/// worse one. So the ground does the chip's job and the status word sits on it at full
/// strength (4.56:1 dark, 5.83:1 light). Pass the word as [statusLabel] and this draws it
/// correctly; do not put a [StatusPill] inside [child].
///
/// The word is not optional when a tone is given, and that is the accessibility contract the
/// [StatusPill] doc already states: hue alone is unreadable to the ~8% of men with a red-green
/// deficiency, several residents per floor in a full PG. A tinted card with no word on it
/// would be exactly that failure at card scale.
class ToneSurface extends StatelessWidget {
  const ToneSurface({
    super.key,
    required this.child,
    required this.tone,
    this.statusLabel,
    this.weight = GlassWeight.thin,
    this.padding,
    this.rail = true,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;

  /// Canonical or resolved — resolved here, so callers keep naming the meaning. Null paints
  /// the plain surface, which lets a caller drop the tint for the "nothing is wrong" case
  /// without swapping widgets.
  final Color? tone;

  /// The status in a WORD, drawn in the tone at full strength on the tint. See the class note:
  /// this is the chip the ground replaces, and it is how the state survives a colour
  /// deficiency. Null only where the [child] already spells the state out itself.
  final String? statusLabel;

  final GlassWeight weight;
  final EdgeInsetsGeometry? padding;

  /// The full-strength strip down the leading edge. On by default: it is the part of the
  /// treatment that reads at a glance in a scrolling list, and it costs no contrast.
  final bool rail;

  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final tones = context.tones;
    final base = weight.surfaceOf(scheme);

    if (tone == null) {
      return FlatSurface(
        weight: weight,
        padding: padding ?? const EdgeInsets.all(Space.md),
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: child,
      );
    }

    final accent = tones.resolve(tone!);
    // Opaque, composited against the fill this surface would otherwise have painted — the
    // exact set the ratios in [NivoraSemantics.surfaceTintAlpha] were measured over.
    final fill = tones.tintedSurface(accent, base);

    Widget inner = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        // The tone's own hairline rather than outlineVariant. On a tinted ground the neutral
        // #292E33 edge all but vanishes, and the card loses the shape that made it read as one
        // object.
        border: Border.all(color: tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: statusLabel == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusLabel!.toUpperCase(),
                  // labelSmall is the same 10/600 step the chip's own label uses, so a tinted
                  // card and a pill state their status in identical type.
                  style: t.textTheme.labelSmall?.copyWith(color: accent),
                ),
                const SizedBox(height: Space.xs),
                child,
              ],
            ),
    );

    if (rail) {
      // A positioned strip under the clip rather than an uneven BorderSide: a BoxDecoration
      // asserts that a border with unequal sides cannot carry a borderRadius, and a
      // square-cornered card here would be the one square thing on the screen. Same
      // construction as [OutlineCard]'s rail, same token.
      inner = Stack(
        children: [
          inner,
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: Strokes.rail,
            child: ColoredBox(color: accent),
          ),
        ],
      );
    }

    Widget result = Material(
      color: fill,
      borderRadius: Radii.rCard,
      clipBehavior: rail ? Clip.antiAlias : Clip.none,
      child: InkWell(borderRadius: Radii.rCard, onTap: onTap, child: inner),
    );
    if (semanticLabel != null) {
      result = Semantics(label: semanticLabel, container: true, child: result);
    }
    return result;
  }
}

/// A resting content card. Use it for the one thing on the screen that is elevated above the
/// rest, not for every row.
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
/// The design's header (4:448, 4:1540) is 56 high with a bottom hairline and nothing else —
/// no fill change from the ground, no shadow. This paints [GlassWeight.regular] so the bar
/// stays opaque while content passes under it, which is what a header is for, and edges only
/// along the bottom.
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
        // 16 is the design's own screen and card padding.
        padding: (padding ?? const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm))
            .add(EdgeInsets.only(top: MediaQuery.paddingOf(context).top)),
        child: child,
      );
}

/// One statistic — the design's KPI card (4:460, 4:479, 4:1546).
///
/// Its anatomy is fixed by the mockups: a 10px uppercase eyebrow in the muted ink, the figure
/// at 20/700, then one supporting line at 11px. Flat by default, on purpose. A grid of
/// elevated tiles is the "rainbow dashboard" the brief warns against: six panes of equal
/// elevation say nothing about which number matters. [emphasised] opts a single tile into a
/// pane — use it at most once per screen, for the figure the screen is about.
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

  /// Semantic accent for the FIGURE. The design tones its KPI values — "₹1,37,500" is red and
  /// "12 Open" is amber (4:481, 4:485) — and leaves the rest cream. Left null for the common
  /// case, because colour should mean something.
  final Color? tone;
  final VoidCallback? onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    final semantics = '$label: $value${caption == null ? '' : '. $caption'}';

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: IconSize.xs, color: accent ?? t.colorScheme.primary),
            const SizedBox(width: Space.xs),
          ],
          Expanded(
            // labelSmall is the design's chip step: 10/600 at +0.05em. A TextStyle cannot
            // uppercase, so the string does it here.
            child: Text(label.toUpperCase(), style: t.textTheme.labelSmall, maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: Space.xxs / 2),
        // headlineMedium is 20/700 tabular — a refreshing column of figures must not shuffle
        // sideways.
        Text(
          value,
          style: accent == null
              ? t.textTheme.headlineMedium
              : t.textTheme.headlineMedium?.copyWith(color: accent),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption != null) ...[
          const SizedBox(height: Space.xxs / 2),
          Text(caption!, style: t.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );

    if (emphasised) {
      return GlassSurface(
        weight: GlassWeight.thin,
        padding: const EdgeInsets.all(Space.sm),
        onTap: onTap,
        semanticLabel: semantics,
        child: body,
      );
    }
    // A TONED FIGURE TINTS ITS OWN TILE, the same way [KpiTile] does — one behaviour for the
    // two stat cards in this app, so a tile does not depend on which screen it landed on.
    //
    // This is not the "rainbow dashboard" the class note warns about. That warning is about
    // giving six panes the same elevation, and about colour applied for emphasis rather than
    // for meaning; [tone] is documented as null for the common case precisely so it is only
    // ever set where the figure means something. A tile that is merely counting stays plain,
    // and on a screen where nothing is wrong nothing is tinted.
    //
    // No rail and no chip: a half-width tile has no room for the first, and the second is the
    // pairing [NivoraSemantics.surfaceTintAlpha] forbids.
    return ToneSurface(
      tone: tone,
      rail: false,
      padding: const EdgeInsets.all(Space.sm),
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
            // A control, so WCAG 1.4.11's 3:1 applies — the same token the stock handle uses.
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

/// Presents a bottom sheet. Centralised so every sheet in the app shares the same geometry,
/// drag handle and inset handling.
///
/// [GlassWeight.thick] is the raised surface. A sheet is the ONE place [Shadows.level3]
/// survives the Figma restyle: it is genuinely floating over a scrimmed page, and the design —
/// which draws no sheets at all — offers nothing to copy.
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
    // Deep, because the ground is already near-black: a barrier that only dims #0B0D0F by a
    // third does not read as a barrier at all.
    barrierColor: NivoraColors.midnight.withValues(alpha: 0.72),
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

// ═════════════════════════════════════════════════════════════════════════════════════════
// THE STATE LAYER — node 4:1562, `screen-empty-error-skeleton`
// ═════════════════════════════════════════════════════════════════════════════════════════
//
// The design specifies all three of the states a screen is in when it has no data, on one
// frame, and they share an anatomy: a raised card, a small caps badge in the tone of the
// state, then the state's own body. That anatomy is [StateCard], and the three bodies are
// [StateBadge] + whatever the state needs.
//
// Nothing here decides WHAT to say — the sentences come from `errorGuidance` and the calling
// screen, which read the real failure. This is the shape only.

/// The design's state badge (4:1576, 4:1589, 4:1600).
///
/// `bg-[rgba(<tone>,0.1)] border border-[<tone>] rounded-[4px] px-[6px] py-[2px]` with the
/// label in the tone at 9px bold. Both alphas come from [NivoraSemantics] so a badge and a
/// status chip carrying the same meaning are the same weight of colour, and so the one place
/// the ratio is tight is the one place it is measured.
///
/// The label is rendered at the scale's chip step (10/600) rather than the mockup's 9/700:
/// 9px is below the point at which a semibold uppercase label survives a real phone's
/// text-scaling, and the two look identical at 1.0.
class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.label, this.tone});

  final String label;

  /// Canonical or resolved. Null is the muted grey the design gives its skeleton badge.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final accent = tone == null ? tones.muted : tones.resolve(tone!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs / 2),
      decoration: BoxDecoration(
        color: tones.chipFill(accent),
        borderRadius: Radii.rTiny,
        border: Border.all(color: tones.chipBorder(accent), width: Strokes.hairline),
      ),
      child: Text(
        label.toUpperCase(),
        style: t.textTheme.labelSmall?.copyWith(color: accent),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The card all three states sit in — 4:1575 / 4:1588 / 4:1599, which are the same box.
///
/// `bg-[#171a1e] border border-[#292e33] rounded-[12px] p-[16px] gap-[12px]`, i.e. the RAISED
/// surface rather than the card one, so a state card reads as sitting on top of the page
/// rather than as another empty card in the list.
class StateCard extends StatelessWidget {
  const StateCard({super.key, required this.child, this.badge, this.tone});

  final Widget child;

  /// The caps tag the design puts at the top left. Omitted inside a card that already has its
  /// own heading, which is the [EmptyNote]-style compact case.
  final String? badge;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return FlatSurface(
      weight: GlassWeight.regular,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) ...[
            StateBadge(label: badge!, tone: tone),
            const SizedBox(height: Space.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// The warning strip from node 4:1520, `screen-subscription-expired`.
///
/// `bg-[rgba(213,166,76,0.1)] border-b border-[#d5a64c] p-[12px]` — a full-bleed band at the
/// very top of the screen, filled with 10% of its tone, underlined at full strength, with an
/// alert glyph, a CAPS eyebrow in the tone and the sentence itself in cream. The bottom-only
/// border is the point of the shape: it reads as a strip the page hangs from rather than as
/// another card in the stack, which is what a state that applies to the WHOLE screen should
/// look like.
///
/// WHAT IS NOT COPIED: the mockup puts a "Renew Subscription" button inside the band (4:1537)
/// and dims everything under it to [Dim.readOnly]. Only Super Admin can write
/// `public.subscriptions` (rls-policies.sql), so in this app renewal is a phone call and that
/// button could not do anything — a call to action that cannot act is worse than a plain
/// statement of fact. The dimming is likewise not applied: the server is the one refusing
/// writes, and greying a screen the user can still legitimately READ teaches them the app is
/// broken. [action] exists for the day renewal becomes something the owner can do in-app.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.eyebrow,
    required this.message,
    required this.tone,
    this.icon = Icons.warning_amber_rounded,
    this.action,
  });

  /// The CAPS line in the tone — "SUBSCRIPTION EXPIRED" (4:1535).
  final String eyebrow;

  /// The sentence, in cream. One or two lines; this is where the real dates and counts go.
  final String message;

  /// Canonical or resolved. Amber for expiring, red for expired.
  final Color tone;

  final IconData icon;

  /// The design's full-width CTA under the text. Null in this app — see the class note.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final accent = tones.resolve(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tones.chipFill(accent),
        border: Border(
          bottom: BorderSide(color: tones.chipBorder(accent), width: Strokes.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: IconSize.md, color: accent),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The design's own eyebrow is two words and set in caps. This one is
                    // not uppercased here, because the app's version carries a real figure
                    // read from the database — "Subscription expired 3 days ago" — and
                    // shouting a number is not the same typographic gesture as a two-word
                    // state label. The style is the design's; the case is the sentence's.
                    Text(eyebrow, style: t.textTheme.labelMedium?.copyWith(color: accent)),
                    const SizedBox(height: Space.xxs / 2),
                    // Cream, not the tone: the tone has already said how serious this is, and
                    // a full sentence in amber is harder to read than one in the body colour.
                    Text(message,
                        style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface)),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: Space.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// The centred block the design puts inside an empty or failed state (4:1578, 4:1591): an
/// optional glyph, a 14/600 title, an 11/400 support line, then one action.
///
/// The glyph is the design's own construction — a 54dp rounded square outlined at 1.5px in
/// [NivoraColors.outline] — rather than a filled icon disc, and the icon sits inside it. That
/// outline is why [Strokes.glyph] exists.
class StateBody extends StatelessWidget {
  const StateBody({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.illustration,
    this.action,
    this.link,
    this.tone,
  });

  final String title;
  final String? message;

  /// Drawn inside the design's outlined square. Omitted for an error, which the design gives
  /// no glyph at all — the sentence is the message.
  final IconData? icon;

  /// An asset path under `assets/illustrations/`, drawn at [ArtSize.emptyState] INSTEAD of the
  /// outlined glyph square.
  ///
  /// ONLY THE FIRST-RUN STATES GET ONE. A new owner's first four screens are empty by
  /// definition, and a bare 56dp glyph on all of them is what an unfinished app looks like. A
  /// list that is empty because a FILTER or a SEARCH excluded everything keeps the glyph: the
  /// artwork says "there is nothing here yet", which would be a lie over "no match for that".
  ///
  /// [icon] is still passed alongside it and is still the fallback — see the errorBuilder in
  /// [build]. A missing or corrupt asset must degrade to the glyph the state already had, not
  /// to a broken-image box and not to a blank card.
  ///
  /// THE ART CARRIES NO WORDS. Every one of these is a wordless drawing, and the title and
  /// message under it stay real Text, so they remain translatable, selectable and legible to a
  /// screen reader. That is also why the image itself is excluded from semantics: it is
  /// decoration over a sentence that already says the same thing.
  final String? illustration;

  /// The one button. `Retry` on the error card is the cream filled button; `Learn More` on the
  /// empty card is the hairline outlined one. Pass whichever the state deserves.
  final Widget? action;

  /// The gold underlined text link under the button — "Contact Support" (4:1598).
  final Widget? link;

  /// Tints the glyph. Null keeps it the design's neutral outline, which is right for a list
  /// that is merely empty: a reassuring green tick over "no data yet" is the interface
  /// congratulating itself.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? t.colorScheme.outline : context.tones.resolve(tone!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (illustration != null || icon != null) ...[
          Center(
            child: illustration == null
                ? _glyph(accent)
                : Image.asset(
                    illustration!,
                    width: ArtSize.emptyState,
                    height: ArtSize.emptyState,
                    fit: BoxFit.contain,
                    // Decoration over a sentence that already says this. Announcing it would
                    // read the state twice.
                    excludeFromSemantics: true,
                    // DECODE AT THE SIZE IT IS DRAWN. The assets are 480px so that a 3x phone
                    // gets them pixel-exact; without this the full 480x480 is decoded and held
                    // at ~900KB on every device including the 2x ones, which is real memory on
                    // the phone this app is actually shipped to.
                    cacheWidth:
                        (ArtSize.emptyState * MediaQuery.devicePixelRatioOf(context)).round(),
                    // A missing asset falls back to the glyph this state had before there was
                    // any artwork. An empty state that cannot draw its picture is still an
                    // empty state; a broken-image box is a bug report.
                    errorBuilder: (_, _, _) =>
                        icon == null ? const SizedBox.shrink() : _glyph(accent),
                  ),
          ),
          const SizedBox(height: Space.sm),
        ],
        Text(title, style: t.textTheme.labelLarge, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: Space.xxs),
          Text(message!, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
        if (action != null) ...[
          const SizedBox(height: Space.sm),
          Center(child: action!),
        ],
        if (link != null) ...[
          const SizedBox(height: Space.xs),
          Center(child: link!),
        ],
      ],
    );
  }

  /// The design's outlined glyph square (4:1579), unchanged. Still the default, and still what
  /// an illustration falls back to when its asset will not load.
  Widget _glyph(Color accent) => Container(
        // The design's square is 54; 56 is the same square on the 4dp grid.
        width: Space.huge + Space.xs,
        height: Space.huge + Space.xs,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: Radii.rControl,
          border: Border.all(color: accent, width: Strokes.glyph),
        ),
        child: Icon(icon, size: IconSize.xl - Space.xs, color: accent),
      );
}

// ═════════════════════════════════════════════════════════════════════════════════════════
// THE DOMAIN LAYER — colour as wayfinding.
// ═════════════════════════════════════════════════════════════════════════════════════════
//
// Three widgets, one recipe, one rule. The recipe is the design's own chip — a 10% wash of the
// tone with the glyph or label in the tone at full strength — which is the ONE tight contrast
// case in the app and is measured for every tone in test/theme_contrast_test.dart. So nothing
// here can paint a pairing that has not been checked.
//
// The rule is [NivoraDomain]'s: domain colour lives on ICONS, ACTIONS and AVATARS; status
// colour lives on SURFACES and FIGURES. A [DomainIcon] at the head of every menu row is what
// makes the menu recognisably the menu on every screen. A red [ToneSurface] behind an unpaid
// rent figure is what says it is unpaid today. They never occupy the same pixel.

/// How big a [DomainIcon] is. The box, and the glyph inside it, on the 4dp grid.
enum DomainIconSize {
  /// 28dp box, 14 glyph — the head of a row in a dense list, where [ToneBadge] used to sit.
  sm(28, IconSize.sm),

  /// 40dp box, 20 glyph — a list tile's leading slot and a section heading. The size Google's
  /// own lists draw their coloured icon containers at, and the default.
  md(40, IconSize.lg),

  /// 56dp box, 28 glyph — a hero card, or an empty state that belongs to one domain.
  lg(56, IconSize.xl - Space.xxs);

  const DomainIconSize(this.box, this.glyph);
  final double box;
  final double glyph;
}

/// The coloured icon container that opens a row, a section or a card — the single most
/// recognisable piece of furniture in a Google app, and now this one.
///
/// A tint of the domain's colour, the glyph in that colour at full strength, no border. The
/// border is the difference between this and a [StateBadge]: a badge is a state and its edge
/// says "chip", an icon container is an identity and sits quietly behind its glyph. Rounded
/// square by default (the vocabulary [IconTile] and [ToneBadge] already use); [circular] for
/// the one place a disc reads better, which is beside a person.
///
/// The glyph is a GRAPHIC, so WCAG 1.4.11's 3:1 is its bar — and the ink measures at least
/// 4.5:1 on a chip of itself, because that is the contract every ink in [NivoraSemantics]
/// meets. A [DomainIcon] can never be drawn too faint to see.
class DomainIcon extends StatelessWidget {
  const DomainIcon({
    super.key,
    required this.domain,
    this.icon,
    this.size = DomainIconSize.md,
    this.circular = false,
    this.semanticLabel,
  });

  final NivoraDomain domain;

  /// A glyph more specific than the domain's own — a plate for breakfast on a menu row whose
  /// domain is [NivoraDomain.food]. Null draws the domain's.
  final IconData? icon;
  final DomainIconSize size;
  final bool circular;

  /// Decoration by default: the row beside it already says what it is. Pass a label only when
  /// the icon is the only thing carrying the meaning.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final ink = tones.resolve(domain.tone);
    final box = Container(
      width: size.box,
      height: size.box,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tones.chipFill(ink),
        borderRadius: circular ? Radii.rPill : Radii.rCard,
      ),
      child: Icon(icon ?? domain.icon, size: size.glyph, color: ink),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: box)
        : Semantics(label: semanticLabel, image: true, child: box);
  }
}

/// The shortcut that says where it goes — a neutral control with a coloured mark.
///
/// A [FilledButton] is the design's one loud object and is reserved for the action a screen
/// exists for. An [OutlinedButton] is the hairline box for something quieter. This is a third
/// weight: the same quiet control, with the GLYPH AND LABEL in the destination's colour. Four
/// of these across a dashboard are four different colours naming four different places, which
/// a row of grey boxes could never do.
///
/// ── THE FILL IS NEUTRAL, AND THAT IS THE RULE BEING OBEYED RATHER THAN BENT ──────────────
///
/// This drew a tonal FILL in the domain's tint at first — Material's `FilledButton.tonal`,
/// which is a perfectly good control and was the wrong one here. [NivoraDomain]'s rule is that
/// domain colour lives on icons, actions and avatars while STATUS colour owns surfaces, and a
/// tinted button is a tinted surface: on the warden's home four of them sat directly under four
/// status-tinted stat tiles, so seven hues shared one screenful and two of them collided
/// outright — an amber "Resolve complaint" immediately below an amber "3 complaints", where the
/// same colour meant "the complaints area" on one and "there is open work" on the other.
///
/// Moving the colour off the ground and into the mark fixes that everywhere at once, and it is
/// the more Google-like shape besides: a coloured icon on a neutral row is what Settings, Drive
/// and Gmail all draw. It also leaves the tinted surface to mean exactly one thing again — the
/// single [DomainCard] a screen is allowed.
///
/// The label sits in the domain ink on [ColorScheme.surfaceContainer], which is one of the four
/// surfaces every ink in [NivoraSemantics] is measured AA against, so a 14px label here clears
/// 4.5:1 in both themes. The hairline is the neutral card edge, not the tone — a coloured edge
/// would put the colour back on the surface by another route.
class DomainButton extends StatelessWidget {
  const DomainButton({
    super.key,
    required this.domain,
    required this.label,
    required this.onPressed,
    this.icon,
    this.enabled = true,
    this.expand = true,
  });

  final NivoraDomain domain;
  final String label;
  final VoidCallback onPressed;

  /// The glyph before the label. Null draws the domain's own.
  final IconData? icon;
  final bool enabled;

  /// Full width, like every other button in the theme. False hugs the label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    // Disabled goes to the muted ink rather than a paler domain colour: a paler tint of the
    // tone is a value this palette has not measured, and the muted ink is AA everywhere.
    final ink = enabled ? tones.resolve(domain.tone) : tones.muted;
    final fill = t.colorScheme.surfaceContainer;

    return FilledButton.tonal(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        disabledBackgroundColor: fill,
        foregroundColor: ink,
        disabledForegroundColor: ink,
        // The neutral card edge, so the control reads as a control in the light theme — where
        // surfaceContainer is white and an unbordered button on an ivory page is invisible.
        side: BorderSide(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
        // 48: Material's floor and above Apple's 44, like the theme's own buttons.
        minimumSize: expand ? const Size.fromHeight(48) : const Size(0, 48),
        shape: const RoundedRectangleBorder(borderRadius: Radii.rControl),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        textStyle: t.textTheme.labelLarge,
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon ?? domain.icon, size: IconSize.md, color: ink),
          const SizedBox(width: Space.xs),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// A card whose GROUND is a domain's colour — the one hero surface a screen may have.
///
/// [ToneSurface] with the rail off and no status word, which is exactly what it is: the same
/// measured tint, the same tone-coloured hairline, and none of the state-carrying furniture.
/// Body text stays AA on every tint in both themes — that is proven in the tinted-surfaces
/// group of the contrast test — so anything a plain card can hold, this can.
///
/// ── AT MOST ONE PER SCREEN, AND NEVER ON A CARD THAT HAS A STATUS ───────────────────────
///
/// A screen where every card is tinted has said nothing. This is for the card that IS the
/// screen's subject — "Today's food" on the resident's home, "Your room" on their profile —
/// and not for a list. And a card that carries a status ("unpaid", "resolved") is a
/// [ToneSurface] in that status's tone, never this: state wins the surface, and the domain
/// shows only on the icon in the corner.
class DomainCard extends StatelessWidget {
  const DomainCard({
    super.key,
    required this.domain,
    required this.child,
    this.padding,
    this.onTap,
    this.semanticLabel,
  });

  final NivoraDomain domain;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => ToneSurface(
        tone: domain.tone,
        rail: false,
        padding: padding,
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: child,
      );
}

/// A stable colour for a person, from their name — the way Google Contacts gives every face a
/// hue so a list of strangers becomes a list of people you can tell apart.
///
/// ── THREE HUES, AND THE THREE IT LEAVES OUT ARE THE POINT ────────────────────────────────
///
/// The palette is exactly the domain tones that are NOT also a status: violet, teal, saffron.
/// `success`, `warning` and `info` are deliberately absent, and an earlier version of this
/// function included them — which was a real bug, not a stylistic one:
///
///   The SAME avatar widget carries a STATUS tone on several screens. The warden's fee ledger
///   passes the fee tone (paid green / partly amber / unpaid red), the resident roster passes
///   `toneFor(status)` (active green / on leave amber), and the desk sheets pass amber and blue
///   outright. On the screens that pass nothing — assign-bed, the complaint sheet, the owner's
///   roster — the colour fell through to this hash. So a resident whose NAME happened to hash
///   to amber wore the exact disc that means "on leave" on the list two taps away.
///
/// Removing those three closes it at the source: an identity colour can no longer collide with
/// a state colour, on any screen, for any name.
///
/// Gold is left out too, for a different reason: it is the brand's, and a face in the brand
/// colour would read as the account holder.
///
/// ── WHAT "STABLE" DOES AND DOES NOT PROMISE ──────────────────────────────────────────────
///
/// The same NAME always hashes to the same hue, in every session and on every screen that lets
/// this function choose. It is not a promise that a person looks identical everywhere: a caller
/// that passes `tone:` is stating a STATUS, and status wins the disc — that is the same rule
/// the rest of the domain layer follows, and it is why the ledger's amber avatar is correct
/// even though this function would have painted that resident teal.
///
/// Returns a CANONICAL tone — resolve it at the paint site with `context.tones.resolve`.
Color avatarToneFor(String? name) {
  const palette = [
    NivoraColors.rooms,
    NivoraColors.people,
    NivoraColors.food,
  ];
  final key = (name ?? '').trim().toLowerCase();
  if (key.isEmpty) return NivoraColors.textMuted;
  // FNV-1a over the code units: a few lines, no dependency, and stable across platforms in a
  // way `String.hashCode` is explicitly not guaranteed to be.
  var h = 0x811C9DC5;
  for (final unit in key.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return palette[h % palette.length];
}
