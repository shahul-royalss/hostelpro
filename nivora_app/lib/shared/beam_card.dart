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
          // The gold, not white. The reference's beam is white on a purple field; here the
          // field is NIVORA's purple and the accent that belongs on it is the brand's own.
          ink: NivoraColors.primary,
          visible: !still,
        ),
        child: child,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          // Near-opaque, deliberately: this is the surface the form's labels and inputs sit on,
          // and it is what keeps them measurable against a ground that is now glowing. The
          // aurora shows THROUGH the card only as much as 0.86 allows.
          color: t.colorScheme.surfaceContainer.withValues(alpha: 0.86),
          border: Border.all(color: t.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
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
