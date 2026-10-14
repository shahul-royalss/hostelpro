/// The dispenser, and the feed.
///
/// A native reproduction of the animation the product owner supplied in
/// `reciept animation/` — a brushed-metal hood with a dark slit, paper that rolls out of it over
/// two and a half seconds with a flex towards the reader and a judder in the rollers, a cutter
/// that flashes across the mouth at the end, and a tear that frees the sheet from the machine.
///
/// ═══ WHAT WAS COPIED, AND WHAT WAS CHANGED ═══
/// Copied exactly: the 2.5s feed, its `cubic-bezier(0.16, 1, 0.3, 1)`, the 350ms blade flash,
/// the 550ms tear, the paper's forward flex as it emerges, the metal palette. Those are the
/// feel, and they are in [ReceiptMotion] / [ReceiptPrinter] so they can be read side by side
/// with the CSS.
///
/// Changed deliberately: in the prototype, tearing throws the receipt off the side of the
/// screen and resets the machine. Here it does the opposite — the sheet detaches, the machine
/// collapses away, and the receipt is what is left. A resident who has just paid rent is not
/// looking for a printer demo; they want the receipt, and the tear is the moment it becomes
/// theirs rather than the machine's.
///
/// ═══ NO WEBVIEW, AND NO IMAGES ═══
/// Every pixel is a Flutter render object. That is the product requirement, and it is also what
/// lets the same widget tree be captured to a PNG at three times the screen's density — see
/// receipt_export.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'receipt.dart';
import 'receipt_paper.dart';
import 'receipt_tokens.dart';

/// Where the paper is.
enum PrinterPhase {
  /// Nothing has come out yet.
  idle,

  /// Rolling out.
  feeding,

  /// Fully out, still attached to the machine.
  printed,

  /// Being torn off.
  tearing,

  /// Free of the machine. The receipt is the resident's.
  torn;

  /// True once the whole sheet is on screen — which is also the only point at which it is
  /// worth exporting, because a half-fed receipt is a half-drawn one.
  bool get isComplete => this == printed || this == torn;
}

/// The machine, the paper, and whatever controls the caller wants underneath them.
///
/// The stage owns the phase because the phase is a property of an animation, not of a screen.
/// [actions] is handed the current phase and a callback that tears the sheet off, so the caller
/// draws its own buttons without having to reach into an [AnimationController].
class ReceiptPrinterStage extends StatefulWidget {
  const ReceiptPrinterStage({
    super.key,
    required this.receipt,
    required this.paperKey,
    required this.actions,
  });

  final Receipt receipt;

  /// The key on the [RepaintBoundary] wrapped around the paper. The caller holds it so it can
  /// capture the sheet to a file; nothing else uses it.
  final GlobalKey paperKey;

  final Widget Function(BuildContext context, PrinterPhase phase, VoidCallback tear) actions;

  @override
  State<ReceiptPrinterStage> createState() => _ReceiptPrinterStageState();
}

class _ReceiptPrinterStageState extends State<ReceiptPrinterStage>
    with TickerProviderStateMixin {
  late final AnimationController _feed = AnimationController(
    vsync: this,
    duration: ReceiptMotion.feed,
  );
  late final AnimationController _cut = AnimationController(
    vsync: this,
    duration: ReceiptMotion.cut,
  );
  late final AnimationController _tear = AnimationController(
    vsync: this,
    duration: ReceiptMotion.tear,
  );

  PrinterPhase _phase = PrinterPhase.idle;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _feed.addStatusListener(_onFeedDone);
    _tear.addStatusListener(_onTearDone);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here rather than in initState because the decision depends on MediaQuery.
    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      // "Remove animations" is an accessibility setting, and a 2.5 second mechanical feed is
      // exactly the kind of motion it exists to switch off. The receipt is the point; the
      // printer is decoration. Jump to the printed sheet.
      _feed.value = 1;
      _phase = PrinterPhase.printed;
      return;
    }
    _phase = PrinterPhase.feeding;
    _feed.forward();
  }

  void _onFeedDone(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _phase = PrinterPhase.printed);
    // The blade crosses the mouth as the last of the paper clears it.
    _cut.forward(from: 0);
  }

  void _onTearDone(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() => _phase = PrinterPhase.torn);
  }

  void _startTear() {
    if (_phase != PrinterPhase.printed) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _tear.value = 1;
      setState(() => _phase = PrinterPhase.torn);
      return;
    }
    setState(() => _phase = PrinterPhase.tearing);
    _tear.forward(from: 0);
  }

  @override
  void dispose() {
    _feed.dispose();
    _cut.dispose();
    _tear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The stage is authored at one size — 400 logical pixels, the width of the machine —
        // and scaled DOWN to fit a narrow phone. Scaling is a paint-time transform, so the
        // paper's own layout width never changes and the exported image is full resolution on
        // every device.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: ReceiptPrinter.hoodWidth,
            child: AnimatedBuilder(
              animation: Listenable.merge([_feed, _cut, _tear]),
              builder: (context, _) => _Stage(
                receipt: widget.receipt,
                paperKey: widget.paperKey,
                feed: _feed.value,
                cut: _cut.value,
                tear: _tear.value,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        widget.actions(context, _phase, _startTear),
      ],
    );
  }
}

/// One frame of the machine and the paper in it.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.receipt,
    required this.paperKey,
    required this.feed,
    required this.cut,
    required this.tear,
  });

  final Receipt receipt;
  final GlobalKey paperKey;

  /// Raw controller values, 0..1. Curves are applied here so the machine and the paper stay in
  /// step with each other by construction.
  final double feed;
  final double cut;
  final double tear;

  /// Height of the hood assembly. The paper starts just inside it.
  static const _machineHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final t = ReceiptMotion.feedCurve.transform(feed);
    final torn = ReceiptMotion.tearCurve.transform(tear);

    // How much of the sheet has cleared the mouth. Never zero: the first frame is a sliver of
    // paper in the slit, not an empty machine.
    final revealed = ReceiptMotion.feedStart + (1 - ReceiptMotion.feedStart) * t;

    // The machine collapses upward as the sheet comes free, and the receipt rises to fill the
    // space it leaves.
    final machineFactor = 1 - torn;

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reserved height for the hood. The paper starts six pixels up inside it, so the
            // sheet emerges from behind the lip rather than in front of it.
            SizedBox(height: (_machineHeight - 6) * machineFactor),
            _Paper(
              receipt: receipt,
              paperKey: paperKey,
              feed: feed,
              revealed: revealed,
              torn: torn,
            ),
          ],
        ),
        // Positioned children do not size a Stack, so the machine can sit over the paper's top
        // edge without the layout depending on it.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: machineFactor,
            child: Opacity(
              opacity: (1 - torn).clamp(0.0, 1.0),
              child: _Machine(cut: cut),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sheet, mid-feed.
class _Paper extends StatelessWidget {
  const _Paper({
    required this.receipt,
    required this.paperKey,
    required this.feed,
    required this.revealed,
    required this.torn,
  });

  final Receipt receipt;
  final GlobalKey paperKey;
  final double feed;
  final double revealed;
  final double torn;

  @override
  Widget build(BuildContext context) {
    // The paper flexes towards the reader as it comes out and flattens as it settles — the
    // prototype's rotateX, which is what stops the feed reading as a rectangle sliding down.
    final flex = ReceiptMotion.flex * (1 - revealed);

    // Rollers. A sub-pixel shake at a constant rate in real time, damped to nothing as the feed
    // finishes. Driven by the RAW controller value so the frequency is even, while everything
    // else uses the curved one.
    final judder = feed > 0 && feed < 1
        ? math.sin(feed * 64) * ReceiptMotion.judder * (1 - revealed)
        : 0.0;

    // The tear: a tug to the right and a twist, then the sheet settles square again, free.
    final tug = math.sin(torn * math.pi);
    final tearX = tug * 16;
    final tearTilt = tug * -0.035;

    final transform = Matrix4.identity()
      ..setEntry(3, 2, ReceiptMotion.perspective)
      ..rotateX(flex)
      ..rotateZ(tearTilt);

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        // Reveals the top `revealed` fraction of the sheet. A printer feeds the head of a
        // receipt out first, so the masthead is what appears in the mouth.
        heightFactor: revealed,
        child: Transform(
          transform: transform,
          alignment: Alignment.topCenter,
          transformHitTests: false,
          child: Transform.translate(
            offset: Offset(judder + tearX, 0),
            child: Opacity(
              // Dim in the mouth, full once it is out. Matches the prototype's 0.4 -> 1 ramp.
              opacity: (0.45 + revealed * 1.6).clamp(0.0, 1.0),
              child: Center(
                // The boundary the export captures. It sits INSIDE every transform, clip and
                // opacity above, so `toImage` renders a square, opaque, full-size sheet however
                // the machine happens to be holding it at that moment.
                child: RepaintBoundary(
                  key: paperKey,
                  child: ReceiptSheet(receipt: receipt),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hood, the mouth and the blade.
class _Machine extends StatelessWidget {
  const _Machine({required this.cut});

  /// 0..1 across the blade's pass. 0 means no blade.
  final double cut;

  @override
  Widget build(BuildContext context) {
    const inset = (ReceiptPrinter.hoodWidth - ReceiptPrinter.slitWidth) / 2;

    return SizedBox(
      width: ReceiptPrinter.hoodWidth,
      height: 54,
      child: Stack(
        children: [
          // Top of the hood: brushed metal, lit from below the way a machined lip catches
          // room light.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: ReceiptPrinter.hoodTopHeight,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(ReceiptPrinter.radius),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ReceiptPrinter.metalShadow,
                    ReceiptPrinter.metalMid,
                    ReceiptPrinter.metalLight,
                    ReceiptPrinter.metalDark,
                  ],
                  stops: [0, 0.42, 0.62, 1],
                ),
              ),
            ),
          ),
          // The specular streak.
          Positioned(
            top: ReceiptPrinter.hoodTopHeight * 0.5,
            left: ReceiptPrinter.hoodWidth * 0.05,
            right: ReceiptPrinter.hoodWidth * 0.05,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [
                    Color(0x00FFFFFF),
                    ReceiptPrinter.highlight,
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),
          // The mouth.
          Positioned(
            top: ReceiptPrinter.hoodTopHeight - 6,
            left: inset,
            right: inset,
            child: Container(
              height: ReceiptPrinter.slitHeight,
              decoration: BoxDecoration(
                color: ReceiptPrinter.slit,
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF000000), Color(0xFF1C1206)],
                ),
              ),
            ),
          ),
          // The bottom lip, in front of everything, so the paper appears to pass behind it.
          Positioned(
            top: ReceiptPrinter.hoodTopHeight + 4,
            left: 0,
            right: 0,
            child: Container(
              height: ReceiptPrinter.hoodLipHeight,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(ReceiptPrinter.radius),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ReceiptPrinter.metalDark,
                    ReceiptPrinter.metalMid,
                    ReceiptPrinter.metalLight,
                  ],
                  stops: [0, 0.4, 1],
                ),
              ),
            ),
          ),
          // The blade. Widens from the centre, flares, and is gone in a third of a second.
          if (cut > 0 && cut < 1)
            Positioned(
              top: ReceiptPrinter.hoodTopHeight - 2,
              left: inset,
              right: inset,
              child: Transform.scale(
                scaleX: (0.1 + cut * 1.8).clamp(0.1, 1.0),
                child: Opacity(
                  opacity: (cut < 0.5 ? cut * 2 : (1 - cut) * 2).clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x00FFFFFF),
                          ReceiptPrinter.blade,
                          Color(0x00FFFFFF),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
