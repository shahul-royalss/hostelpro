import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// The face an empty list shows when empty is GOOD NEWS.
///
/// ── WHY THIS IS DRAWN AND NOT AN ASSET ────────────────────────────────────────────────────
///
/// The four [EmptyArt] PNGs are illustrations for a brand-new account with no data at all. This
/// is a different statement: the account is running, and there is nothing wrong. "No complaints"
/// is the one empty state in the product that a hostel actively WANTS to see, and the product
/// owner asked for a smile on it.
///
/// A fifth PNG would have been the obvious move. It is not the right one, because this mark has
/// to sit in five role dashboards on two grounds and take the colour of whichever domain owns
/// the screen — a raster asset baked in gold cannot do that, and five tinted copies of one face
/// is how a design system starts drifting. Twelve lines of geometry can, costs no bytes in the
/// APK, and is sharp at any size on any density.
///
/// ── THE GEOMETRY IS DELIBERATELY PLAIN ────────────────────────────────────────────────────
///
/// A circle, two dots, one arc. No gradient, no shadow, no wink, no colour of its own. It reads
/// at 40dp on a warden's phone and at 96dp on an empty screen, and it inherits [color] so the
/// complaints screen can draw it in the complaints tone while the notices screen draws the same
/// face in its own. The stroke is [Space.xxs] scaled to the box so the line weight matches the
/// rest of the interface at every size rather than looking hairline when it is large.
class SmileyMark extends StatelessWidget {
  const SmileyMark({super.key, this.size = 96, this.color});

  final double size;

  /// Defaults to the theme's outline — the same neutral every other empty state uses. Pass a
  /// domain tone on a screen where the absence means something.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.outline;
    return SizedBox.square(
      dimension: size,
      // Decorative: the real sentence is the Text under it, and a screen reader announcing
      // "smiling face" before "No complaints yet" adds nothing a blind resident needs.
      child: ExcludeSemantics(
        child: CustomPaint(painter: _SmileyPainter(ink)),
      ),
    );
  }
}

class _SmileyPainter extends CustomPainter {
  const _SmileyPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);

    // 1/24th of the box: 4dp at 96dp, 2dp at 48dp. Matches the interface's hairline at small
    // sizes and thickens honestly as the mark grows.
    final stroke = size.width / 24;

    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;

    // The face, inset by half the stroke so the ring is not clipped by the box.
    canvas.drawCircle(c, r - stroke / 2, line);

    // Two eyes at 38% across and 36% down, sized against the box so they never become specks.
    final eyeR = size.width * 0.055;
    canvas.drawCircle(Offset(size.width * 0.35, size.height * 0.38), eyeR, fill);
    canvas.drawCircle(Offset(size.width * 0.65, size.height * 0.38), eyeR, fill);

    // The smile: the bottom third of a circle concentric with the face. Drawn as an arc rather
    // than a bezier so it stays a true curve of the same circle at every size.
    final mouth = Rect.fromCircle(center: c, radius: r * 0.52);
    canvas.drawArc(mouth, math.pi * 0.18, math.pi * 0.64, false, line);
  }

  @override
  bool shouldRepaint(_SmileyPainter old) => old.ink != ink;
}

/// The whole "nothing here, and that is fine" state: the face, and one short line under it.
///
/// The product owner's instruction was specific — the smile goes in the MIDDLE, and the words
/// are only "No complaints yet" or "No complaints yet raised" depending on who is looking. So
/// this deliberately does NOT take a `message`. The long supporting paragraph that used to sit
/// under these states ("If something in the hostel is not working — food, cleaning, Wi-Fi...")
/// was explaining a feature to somebody already standing in it, and on the one screen where
/// empty is the good outcome it read as an apology for good news.
///
/// Centring is the CALLER's job, not this widget's: it is placed inside an always-scrollable
/// list so pull-to-refresh keeps working, and only that list knows the viewport height. See the
/// `empty` slot in each role's `paged_list.dart`.
class SmileyEmpty extends StatelessWidget {
  const SmileyEmpty({super.key, required this.title, this.tone});

  final String title;

  /// A domain tone, or null for the neutral outline every other empty state uses.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SmileyMark(size: 96, color: tone),
        const SizedBox(height: Space.lg),
        Text(
          title,
          textAlign: TextAlign.center,
          style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
