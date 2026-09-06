import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// A glass card with a light travelling around its edge.
///
/// The reference builds this from four absolutely-positioned `motion.div`s — one per side, each
/// a white gradient sliver with its own duration, delay, opacity cycle and animated blur — plus
/// four corner dots on their own timers. Twelve animations.
///
/// Here it is ONE controller and one painter. Twelve independent tickers on a sign-in screen is
/// twelve chances to drop a frame on the cheap Android hardware this product is aimed at, and
/// the four sides are not actually independent: they are one light going round a rectangle. A
/// single 0→1 pass with each side reading a quarter of it is the same picture, and it cannot
/// drift out of phase with itself the way four timers can.
///
/// ── DECORATION THAT KNOWS IT IS DECORATION ────────────────────────────────────────────────
///
/// Under "reduce motion" the beam stops and the card keeps its border. Nothing here carries
/// meaning — no state, no progress, no attention — so holding it still costs the user nothing.
class BeamCard extends StatefulWidget {
  const BeamCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.xl),
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  State<BeamCard> createState() => _BeamCardState();
}

class _BeamCardState extends State<BeamCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final r = BorderRadius.circular(widget.radius);

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _BeamPainter(
          progress: still ? 0 : _c.value,
          radius: widget.radius,
          // THE GOLD, and it must be named explicitly now. This used to say
          // `NivoraColors.primary` with a comment reading "the gold, not white" — true when
          // primary WAS the gold. Primary is the brand violet now, so that line quietly became
          // a violet comet travelling round a violet-lit card, which is invisible.
          ink: NivoraColors.gold,
          // DARK ONLY, and this is not a preference. The comet is a light travelling round the
          // card's edge; a travelling light needs a dark edge to travel along. On the light
          // theme's white card the same paint renders as a tan smear parked in one corner —
          // I built it, looked at it on a device, and that is exactly what it did. There is
          // nothing to rescue with an alpha: the effect is wrong for the surface, so it does
          // not run on that surface.
          visible: !still && t.brightness == Brightness.dark,
        ),
        child: child,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          // Near-opaque, deliberately: this is the surface the form's labels and inputs sit on,
          // and it is what keeps them measurable against a ground that is now glowing. The
          // aurora shows THROUGH the card only as much as the alpha allows.
          //
          // THE CARD IS `surface`, NOT `surfaceContainer`. In the dark theme those are a rung
          // apart and either would have read as a card, so the wrong one went in unnoticed. In
          // the light theme surfaceContainer is the BAR fill #F7F8FC, and at 86% over a
          // violet-tinted ground it rendered the sign-in card as a grey slab instead of the
          // white card the scheme specifies. `surface` is the card in both themes by
          // definition — it is what GlassWeight.thin returns — so it is what this paints.
          color: t.colorScheme.surface.withValues(alpha: 0.92),
          border: Border.all(color: t.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              // A MODAL'S LIFT, TONED TO THE THEME. 45% black is a dark-theme shadow; on a
              // near-white page it is a grey smudge, which is what it was drawing. This is the
              // one surface in the app allowed to float — glass.dart:28-33 — so it keeps a
              // shadow, but it takes the scheme's own shadow colour and a light-appropriate
              // alpha rather than assuming the ground is near-black.
              color: t.colorScheme.shadow
                  .withValues(alpha: t.brightness == Brightness.dark ? 0.45 : 0.10),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter({
    required this.progress,
    required this.radius,
    required this.ink,
    required this.visible,
  });

  /// 0..1 around the whole perimeter.
  final double progress;
  final double radius;
  final Color ink;
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // The path IS the border, so the light follows the rounded corners instead of jumping the
    // gap between four straight slivers — which is the visible flaw in the four-div version.
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final total = metric.length;

    // A sixth of the perimeter, so the head is a comet rather than a dot or a ring.
    final tail = total / 6;
    final head = progress * total;

    // extractPath does not wrap, so a comet crossing the origin is drawn as two pieces.
    final start = head - tail;
    final segments = <Path>[];
    if (start < 0) {
      segments.add(metric.extractPath(total + start, total));
      segments.add(metric.extractPath(0, head));
    } else {
      segments.add(metric.extractPath(start, head));
    }

    for (final seg in segments) {
      canvas.drawPath(
        seg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [ink.withValues(alpha: 0), ink.withValues(alpha: 0.85)],
          ).createShader(rect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.progress != progress || old.ink != ink || old.visible != visible;
}
