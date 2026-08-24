/// The paper itself — a printed rent receipt, drawn natively.
///
/// ═══ NATIVE, NOT A WEBVIEW ═══
/// The product owner supplied the look as an HTML/CSS/JS prototype
/// (`reciept animation/index.html`). None of it is embedded: the serrated cutter edge is a
/// [CustomClipper], the perforated rules and the barcode are [CustomPainter]s, and the feed is
/// a Flutter animation (see receipt_printer.dart). Everything the resident sees is a Flutter
/// render object, which is what makes it exportable as an image, readable by a screen reader,
/// and legal under the "nothing goes to a browser" requirement.
///
/// ═══ THIS WIDGET INVENTS NO VALUES ═══
/// Every string it draws comes off a [Receipt], and a [Receipt] can only be built from a row
/// the server wrote. There is no placeholder text, no "—" standing in for a missing figure and
/// no default amount: a fact the database does not have is a line this paper does not print.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'receipt.dart';
import 'receipt_tokens.dart';

/// A printed receipt, at its natural size.
///
/// Fixed width by design ([ReceiptPaper.width]). Paper does not reflow to the window it is
/// held in front of, and a receipt that stretched to fill a tablet would stop reading as an
/// object. The caller centres it.
class ReceiptSheet extends StatelessWidget {
  const ReceiptSheet({super.key, required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _CutterEdge(),
      child: Container(
        width: ReceiptPaper.width,
        color: ReceiptPaper.stock,
        child: Stack(
          children: [
            // The sheet's own thickness: a whisper of shade down both long edges. Purely
            // decorative, and behind everything, so it can never sit over a figure.
            const Positioned.fill(child: _PaperEdges()),
            Padding(
              padding: ReceiptPaper.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Masthead(receipt: receipt),
                  const SizedBox(height: 20),
                  _Headline(receipt: receipt),
                  const SizedBox(height: 18),
                  const _Perforation(),
                  const SizedBox(height: 14),
                  for (final line in receipt.facts) _FactRow(line: line),
                  const SizedBox(height: 14),
                  const _Perforation(),
                  const SizedBox(height: 14),
                  for (final line in receipt.amounts) _AmountRow(line: line),
                  const SizedBox(height: 12),
                  const _Perforation(),
                  const SizedBox(height: 12),
                  _Total(receipt: receipt),
                  const SizedBox(height: 20),
                  const _Perforation(),
                  const SizedBox(height: 18),
                  _Footer(receipt: receipt),
                  // Clearance for the cutter's teeth, which bite up into the sheet.
                  const SizedBox(height: ReceiptPaper.toothDepth + 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPE
//
// One mono face, five sizes. A thermal printer has one font and so does this: the hierarchy is
// carried by size, weight and letter-spacing, exactly as it is on a real receipt.
// ─────────────────────────────────────────────────────────────────────────────

TextStyle _mono({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = ReceiptPaper.ink,
  double spacing = 0,
  double height = 1.35,
}) =>
    TextStyle(
      fontFamily: ReceiptPaper.monoFamily,
      fontFamilyFallback: ReceiptPaper.monoFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
      // Money in a column that does not line up is money that looks wrong.
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

/// Who issued this, and what it is.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final hostel = receipt.hostelName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // No hostel name is a real state — the screen that opened this may not have had the
        // contact card yet. The masthead simply omits it rather than printing a placeholder
        // where a business name belongs.
        if (hostel != null)
          Text(
            hostel.toUpperCase(),
            textAlign: TextAlign.center,
            style: _mono(size: 13, weight: FontWeight.w700, spacing: 1.1),
          ),
        if (hostel != null) const SizedBox(height: 4),
        Text(
          'RENT RECEIPT',
          textAlign: TextAlign.center,
          style: _mono(size: 9.5, color: ReceiptPaper.inkSoft, spacing: 2.6),
        ),
      ],
    );
  }
}

/// The figure, and what it is the figure of.
class _Headline extends StatelessWidget {
  const _Headline({required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          receipt.amountText,
          textAlign: TextAlign.center,
          style: _mono(size: 32, weight: FontWeight.w700, spacing: -0.6, height: 1.1),
        ),
        const SizedBox(height: 6),
        Text(
          receipt.amountCaption,
          textAlign: TextAlign.center,
          style: _mono(size: 10.5, color: ReceiptPaper.inkSoft),
        ),
        const SizedBox(height: 2),
        Text(
          receipt.metaText,
          textAlign: TextAlign.center,
          style: _mono(size: 9, color: ReceiptPaper.inkSoft, spacing: 0.9),
        ),
      ],
    );
  }
}

/// A non-money line: label left, value right.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.line});
  final ReceiptLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.label, style: _mono(size: 10.5, color: ReceiptPaper.inkSoft)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              line.value,
              textAlign: TextAlign.right,
              style: _mono(size: 10.5, weight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// A money line. Same shape, heavier value, because this is the column people scan.
class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.line});
  final ReceiptLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line.label,
              style: _mono(
                size: 11,
                color: line.emphasis ? ReceiptPaper.ink : ReceiptPaper.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            line.value,
            style: _mono(size: 11, weight: line.emphasis ? FontWeight.w700 : FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// The verdict line. On a desk receipt this is the trigger's own status word.
class _Total extends StatelessWidget {
  const _Total({required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            receipt.totalLabel,
            style: _mono(size: 12, weight: FontWeight.w700, spacing: 1.4),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          receipt.totalValue,
          style: _mono(size: 15, weight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// The tail: a thank you, the code strip, and the reference in full.
class _Footer extends StatelessWidget {
  const _Footer({required this.receipt});
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'THANK YOU',
          style: _mono(size: 9.5, weight: FontWeight.w600,
              color: ReceiptPaper.inkSoft, spacing: 2.2),
        ),
        const SizedBox(height: 14),
        // Decorative. See _CodeStripPainter — it is a printed flourish in the shape of a code
        // strip, not a scannable barcode, and the machine-readable truth is the reference
        // printed underneath it in full.
        SizedBox(
          height: 30,
          width: ReceiptPaper.width * 0.66,
          child: CustomPaint(painter: _CodeStripPainter(receipt.reference)),
        ),
        const SizedBox(height: 8),
        Text(
          receipt.referenceLabel,
          style: _mono(size: 7.5, color: ReceiptPaper.inkSoft, spacing: 1.6),
        ),
        const SizedBox(height: 2),
        // Full, unabbreviated, and wrapping rather than ellipsised: a truncated payment id is
        // worse than no payment id, because it looks usable and is not.
        Text(
          receipt.reference,
          textAlign: TextAlign.center,
          style: _mono(size: 9.5, weight: FontWeight.w500, spacing: 0.6),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE PAPER'S PHYSICAL DETAILS
// ─────────────────────────────────────────────────────────────────────────────

/// The serrated bite a POS cutter leaves along the bottom of a torn receipt.
///
/// One tooth per [ReceiptPaper.toothWidth] of width, so the teeth stay the same physical size
/// whatever the sheet is. The count is clamped: a handful of enormous teeth reads as a
/// decoration, and a hundred tiny ones read as a fringe.
class _CutterEdge extends CustomClipper<Path> {
  const _CutterEdge();

  @override
  Path getClip(Size size) {
    const depth = ReceiptPaper.toothDepth;
    final teeth = (size.width / ReceiptPaper.toothWidth).round().clamp(6, 60);
    final step = size.width / teeth;
    final shoulder = size.height - depth;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, shoulder);

    for (var i = teeth - 1; i >= 0; i--) {
      path
        ..lineTo(i * step + step / 2, size.height)
        ..lineTo(i * step, shoulder);
    }

    return path..close();
  }

  @override
  bool shouldReclip(_CutterEdge oldClipper) => false;
}

/// A dotted rule. Drawn rather than made of Text('- - - -') so it stays crisp at the pixel
/// ratios the export uses.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: CustomPaint(painter: _PerforationPainter()));
}

class _PerforationPainter extends CustomPainter {
  const _PerforationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReceiptPaper.rule
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.square;
    const dash = 3.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset(math.min(x + dash, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PerforationPainter oldDelegate) => false;
}

/// The faint shading down both long edges that makes a flat rectangle read as a sheet.
class _PaperEdges extends StatelessWidget {
  const _PaperEdges();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                ReceiptPaper.edgeShade,
                Color(0x00000000),
                Color(0x00000000),
                ReceiptPaper.edgeShade,
              ],
              stops: [0, 0.045, 0.955, 1],
            ),
          ),
        ),
      );
}

/// The code strip under the footer.
///
/// ═══ THIS IS NOT A BARCODE AND MUST NOT PRETEND TO BE ONE ═══
/// It encodes nothing. Bar widths are derived from the reference's own code units purely so
/// that the same receipt always draws the same strip — reprint a receipt and it looks like the
/// same document, which is the whole reason a printed one carries a strip at all. Implementing
/// a real Code 128 would put a scannable claim on a financial document that no system in this
/// product can read back, which is worse than a flourish that is honestly a flourish. The
/// reference is printed as text directly beneath, and that is the machine-readable half.
class _CodeStripPainter extends CustomPainter {
  const _CodeStripPainter(this.seed);

  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ReceiptPaper.inkFaint;
    final units = seed.codeUnits;
    if (units.isEmpty) return;

    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final unit = units[i % units.length];
      // 1–4px bars and 1–3px gaps. Deterministic in the reference, and dense enough to read as
      // a printed strip at both screen and export scale.
      final bar = 1.0 + (unit % 4);
      final gap = 1.0 + ((unit >> 2) % 3);
      final width = math.min(bar, size.width - x);
      if (width <= 0) break;
      canvas.drawRect(Rect.fromLTWH(x, 0, width, size.height), paint);
      x += bar + gap;
      i++;
    }
  }

  @override
  bool shouldRepaint(_CodeStripPainter oldDelegate) => oldDelegate.seed != seed;
}
