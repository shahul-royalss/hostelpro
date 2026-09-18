library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/theme/tokens.dart';
import 'brow.dart';
import 'wordmark.dart';

/// THE BRAND HEADER — the brow every role's dashboard opens with.
///
/// ── WHY IT WAS REBUILT ───────────────────────────────────────────────────────────────────────
///
/// The owner's screenshot of the Super Admin "Subscriptions" tab: "SUPER ADMIN / Subscriptions /
/// One subscription per hostel" in dark grey on deep purple, "uncomfortable to read" on "the top
/// header of every dashboard". The brow merged a white [DefaultTextStyle], but every call site
/// built its lines with `Theme.of(context).textTheme.titleMedium` and friends, and those styles
/// carry the theme's own ink — #14161D in light — which beats an inherited colour. Four headers,
/// four copies of the same leak.
///
/// So the ink is no longer the caller's to choose. [BrowTitleBlock] takes STRINGS, and [BrowText]
/// resolves the colour inside the header, last, after any style the caller could have passed.
/// Icon buttons in `actions` get the same guarantee from the frame's [IconButtonTheme], disabled
/// ones included; the frame's build method says why [IconTheme] alone did not give it.
///
/// ── THE PALETTE, AND WHY A GRADIENT IS STILL MEASURED ONCE ───────────────────────────────────
///
/// brow.dart keeps [BrandBrow] flat so that contrast is "measured once rather than per
/// pixel-row". This header is a diagonal gradient and keeps that promise a different way: every
/// ink below is measured against the LIGHTEST stop, [BrowInk.bright], which is the worst pixel any
/// line can land on. The motif is kept in the dark half of the gradient and faint enough that it
/// never lifts a pixel above that stop — `test/brow_header_test.dart` checks that at 320dp with a
/// tall header, which is where the dark half is narrowest.
///
///   ink                     lightest stop #6341A4    brandDeep #4D2896
///   title    #FFFFFF        7.43:1                   10.20:1
///   eyebrow  #E3D5BB        5.15:1                    7.07:1
///   subtitle #F5F3EE @86%   5.43:1                    7.22:1
///   icon     #FFFFFF        7.43:1                   10.20:1
///   disabled #FFFFFF @38%   2.43:1                    2.77:1   inactive, so WCAG sets no floor
///
/// ── THE ENTRANCE, AND THE RULES IT KEEPS ─────────────────────────────────────────────────────
///
/// Once, when a header first appears: a gold light crosses the brow, the eyebrow fades in while
/// its tracking settles, the title rises 8dp, the subtitle follows, the ribbon along the curve
/// spreads out from the centre and the house's window lights. [BrowEntrance.total] is 1,020ms.
///
///  * NOTHING KEEPS TICKING. The controller completes, the header rebuilds into its static
///    final state and the controller is disposed at the end of that frame. A dashboard that
///    ticks forever is a battery drain and the "stuck, lag" report the release builds were
///    already fixed for.
///  * A TAB CHANGE IS NOT A FIRST APPEARANCE. Each tab owns its own header inside the shell's
///    IndexedStack, so "the header changed" arrives as a second header mounting while the first
///    is still alive. That one only fades its title in; the sweep is not replayed. A title that
///    changes inside one header cross-fades.
///  * REDUCE MOTION MEANS NONE. With [MediaQuery.disableAnimationsOf] on, no controller is made
///    and the final state is drawn on the first frame.
///  * THE GPU PAYS FOR ALMOST NOTHING. No blur, no image, no shader beyond two linear gradients.
///    The gradient and motif sit in their own [RepaintBoundary] and are painted once; only the
///    light layer and the three lines repaint while the entrance runs.

// ─────────────────────────────────────────────────────────────────────────────
// PALETTE
// ─────────────────────────────────────────────────────────────────────────────

/// Every colour the brow paints. Derived from tokens.dart, never typed in: the bright stop and
/// the eyebrow are two tokens mixed, so moving the brand moves the header with it.
abstract final class BrowInk {
  /// Where the gradient ends — the bottom-right corner, under the motif.
  static const deep = NivoraColors.brandDeep;

  /// How far the bright stop is taken from [deep] towards [NivoraColors.brand].
  ///
  /// 0.4 is the brightest mix that still carries a white title at 7:1: it lands on #6341A4, 7.43:1.
  /// At 0.5 the stop measures 6.85:1, and the brand itself (`brandInk` #6C4AA5) only 6.64:1.
  static const brightMix = 0.4;

  /// THE LIGHTEST STOP, #6341A4 — the top-left corner, and the ground every ink is measured on.
  static final bright = Color.lerp(deep, NivoraColors.brand, brightMix)!;

  /// The title. 7.43:1 on [bright].
  static const title = Colors.white;

  /// The eyebrow and the NIVORA signature: the gold taken 60% of the way to the cream ink, #E3D5BB.
  /// Gold itself is 4.56:1 on brandDeep but only 3.32:1 on [bright], which is fine for a line
  /// and not for 10px type. 5.15:1 on [bright].
  static final eyebrow = Color.lerp(NivoraColors.gold, NivoraColors.onSurface, 0.6)!;

  /// The meta line: the cream ink at 86%, one step under the title. 5.43:1 on [bright].
  static final subtitle = NivoraColors.onSurface.withValues(alpha: 0.86);

  /// Icon buttons on the brow, a PopupMenuButton's glyph included: the title's white.
  static const control = title;

  /// A disabled icon button: that white at Material's 38% disabled opacity, 2.43:1 on [bright].
  /// An inactive control has no 3:1 floor under WCAG 1.4.11; what matters is that it dims towards
  /// the ground. Left to the theme it is onSurface at 38%, which is near-black in light.
  static final controlDisabled = control.withValues(alpha: 0.38);

  /// The ribbon, the sweep and the brand dot. 3.32:1 on [bright] and 4.56:1 on [deep], so the dot
  /// clears WCAG 1.4.11's 3:1 as a graphic wherever it sits.
  static const gold = NivoraColors.gold;

  /// The one lit window in the motif — the design's amber.
  static const window = NivoraColors.secondary;

  /// The motif's white lines and dark panes. Faint on purpose: see [BrowMotif].
  static const motifStrokeAlpha = 0.06;

  /// The lit window at rest.
  static const motifWindowAlpha = 0.12;

  /// The eyebrow's settled tracking. Caps at 10px need air to read as a label.
  static const eyebrowTracking = 1.2;
}

// ─────────────────────────────────────────────────────────────────────────────
// TIMING
// ─────────────────────────────────────────────────────────────────────────────

/// The entrance, as fractions of one controller so every part stays in step.
abstract final class BrowEntrance {
  /// Three slow beats: 1,020ms.
  static final total = Motion.slow * 3;

  /// What a header mounted by a tab change gets instead: the title fades, nothing else moves.
  static const titleSwap = Motion.base;

  /// The gold light, off one edge and out the other.
  static const sweep = Interval(0.0, 0.70, curve: Motion.move);

  /// The ribbon spreading from the centre of the curve to both corners.
  static const ribbon = Interval(0.18, 0.82, curve: Motion.enter);

  /// The window lights as the sweep reaches it, flares, then settles to its resting glow.
  static const window = Interval(0.40, 1.0);

  static const eyebrow = Interval(0.06, 0.46, curve: Motion.enter);
  static const title = Interval(0.20, 0.62, curve: Motion.enter);
  static const subtitle = Interval(0.36, 0.80, curve: Motion.enter);

  /// How far the title rises into place, in dp.
  static const titleRise = 8.0;

  /// The subtitle's smaller rise — it follows rather than repeats.
  static const subtitleRise = 4.0;

  /// Extra tracking the eyebrow starts with before it settles, in dp.
  static const eyebrowSpread = 2.4;

  /// The sweep's strongest alpha, at mid-crossing. Transient, and under the lines rather than
  /// over them, so it is strong enough to be seen rather than measured.
  static const sweepPeak = 0.30;

  /// How far above its rest the window flares while it lights.
  static const windowFlare = 0.22;
}

/// Which entrance a header plays. See the class doc of this file.
enum BrowEntranceKind { full, titleOnly }

/// The three lines a brow header carries.
enum BrowLine { eyebrow, title, subtitle }

// ─────────────────────────────────────────────────────────────────────────────
// THE FRAME
// ─────────────────────────────────────────────────────────────────────────────

/// The brow itself: gradient, motif, ribbon, the one-shot entrance, and the light ink scope.
///
/// Built by `GlassHeader(onBrow: true)`, which owns the padding; screens do not use this directly.
class BrowHeaderFrame extends StatefulWidget {
  const BrowHeaderFrame({
    super.key,
    required this.padding,
    required this.dip,
    required this.child,
  });

  /// Already includes the status-bar inset and the dip, so the curve is empty space under the
  /// content rather than a crescent cutting into it.
  final EdgeInsetsGeometry padding;

  /// How far the centre of the bottom edge bulges below the bar.
  final double dip;

  final Widget child;

  @override
  State<BrowHeaderFrame> createState() => _BrowHeaderFrameState();
}

class _BrowHeaderFrameState extends State<BrowHeaderFrame> with SingleTickerProviderStateMixin {
  /// Brow headers alive right now. A header that mounts while another is alive is a tab change
  /// (the previous tab's header is still in the IndexedStack), not the brow first appearing.
  static int _live = 0;

  late final BrowEntranceKind _kind;
  AnimationController? _controller;
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    _kind = _live == 0 ? BrowEntranceKind.full : BrowEntranceKind.titleOnly;
    _live++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here, not in initState, because MediaQuery cannot be read there — and re-read on every
    // change, because the switch lives in the OS and can be flipped while the app is open.
    final still = MediaQuery.disableAnimationsOf(context);
    if (!_decided) {
      _decided = true;
      if (still) return;
      _controller = AnimationController(
        vsync: this,
        duration: _kind == BrowEntranceKind.full ? BrowEntrance.total : BrowEntrance.titleSwap,
      )
        ..addStatusListener(_onStatus)
        ..forward();
    } else if (still) {
      // Mid-entrance: jump to the end. A build follows didChangeDependencies on its own.
      _settle();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) setState(_settle);
  }

  /// Drops the controller from the tree now and disposes it once this frame is done — by then
  /// nothing built from it is still listening.
  void _settle() {
    final controller = _controller;
    if (controller == null) return;
    _controller = null;
    SchedulerBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  @override
  void dispose() {
    _live--;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = BrowInk.control;
    final t = Theme.of(context);
    final progress = _controller?.view;
    final textStyle = (t.textTheme.bodyMedium ?? const TextStyle()).copyWith(color: ink);
    // IconTheme is not enough for an IconButton. Material 3 resolves it as a button style and
    // borrows IconTheme's colour only when the SDK does not take it for its own default (an
    // `identical` check in IconButton's themeStyleOf), and a DISABLED one never borrows it: it
    // falls through to onSurface at 38%, #14161D in light. So both states are named here, over
    // whatever the app's own IconButtonTheme says about size and shape.
    final iconButtons = IconButton.styleFrom(
      foregroundColor: ink,
      disabledForegroundColor: BrowInk.controlDisabled,
    ).merge(IconButtonTheme.of(context).style);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark icons on the brow are a clock nobody can read, and on a light-mode phone the root
      // sets exactly that. Same fix as BrandBrow's, for the same reason.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ClipPath(
        clipper: BrowClipper(dip: widget.dip),
        child: Stack(
          children: [
            // Painted once and cached: nothing in it moves.
            const Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: BrowBackdropPainter())),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: BrowLightPainter(
                    progress: _kind == BrowEntranceKind.full ? progress : null,
                    dip: widget.dip,
                  ),
                ),
              ),
            ),
            Padding(
              padding: widget.padding,
              child: RepaintBoundary(
                child: _BrowMotion(
                  progress: progress,
                  kind: _kind,
                  // Each is needed. Unstyled Text inherits the text style, Icon the icon theme and
                  // IconButton the button theme, and the slots that DO name a colour — the avatar,
                  // the brand dot — read BrowScope instead.
                  child: BrowScope(
                    child: IconTheme.merge(
                      data: const IconThemeData(color: ink),
                      child: IconButtonTheme(
                        data: IconButtonThemeData(style: iconButtons),
                        child: DefaultTextStyle.merge(style: textStyle, child: widget.child),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hands the running entrance to the lines inside the header. Null progress is the final state.
class _BrowMotion extends InheritedWidget {
  const _BrowMotion({required this.progress, required this.kind, required super.child});

  final Animation<double>? progress;
  final BrowEntranceKind kind;

  @override
  bool updateShouldNotify(_BrowMotion old) => old.progress != progress || old.kind != kind;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINT
// ─────────────────────────────────────────────────────────────────────────────

/// The diagonal gradient and the house motif. Static.
class BrowBackdropPainter extends CustomPainter {
  const BrowBackdropPainter();

  /// The gradient's position (0 = [BrowInk.bright], 1 = [BrowInk.deep]) at [point] in a header
  /// of [size]. It runs corner to corner, so it grows with both x and y.
  static double gradientT(Offset point, Size size) {
    final span = size.width * size.width + size.height * size.height;
    if (span == 0) return 0;
    return ((point.dx * size.width + point.dy * size.height) / span).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrowInk.bright, BrowInk.deep],
        ).createShader(rect),
    );
    BrowMotif.paintStructure(canvas, size);
  }

  @override
  bool shouldRepaint(BrowBackdropPainter oldDelegate) => false;
}

/// The Nivora mark as a whisper: the arched doorway, the diagonal, and the tower with its 2x2
/// windows, one of them lit. Drawn in a 100x92 unit box, the mark's own proportions.
///
/// IT LIVES IN THE DARK HALF, AND THAT IS A CONTRAST RULE, NOT TASTE. A title can run under it
/// on a narrow phone. Kept to the trailing edge, its top-left corner sits at least halfway down
/// the gradient, and at 6% (lines) and 12% (window) nothing it paints there is lighter than
/// [BrowInk.bright] — so every ratio in this file's header still holds on top of it.
abstract final class BrowMotif {
  static const _unitW = 100.0;
  static const _unitH = 92.0;

  /// Tall enough to read as a building behind the title, capped so large text does not blow it
  /// up into the middle of the bar.
  static const maxHeight = 112.0;

  static Rect rectFor(Size size) {
    final h = math.min(size.height * 0.9, maxHeight);
    final w = h * _unitW / _unitH;
    // 14% bleeds off the trailing edge, so it reads as a building beside the header rather than
    // a logo placed inside it.
    return Rect.fromLTWH(size.width - w * 0.86, size.height - h - size.height * 0.04, w, h);
  }

  /// The lit pane: top-right of the grid, as on the mark.
  static Rect litPane(Rect motif) {
    final s = motif.height / _unitH;
    return Rect.fromLTWH(motif.left + 87 * s, motif.top + 30 * s, 6 * s, 6 * s);
  }

  static void paintStructure(Canvas canvas, Size size) {
    final r = rectFor(size);
    final s = r.height / _unitH;
    double x(double u) => r.left + u * s;
    double y(double v) => r.top + v * s;
    final ink = Colors.white.withValues(alpha: BrowInk.motifStrokeAlpha);

    final lines = Path()
      // The arch over the doorway, running into the diagonal.
      ..moveTo(x(2), y(92))
      ..lineTo(x(2), y(36))
      ..cubicTo(x(2), y(16), x(16), y(6), x(30), y(6))
      ..cubicTo(x(40), y(6), x(47), y(12), x(52), y(20))
      ..lineTo(x(74), y(61))
      // The door.
      ..moveTo(x(8), y(92))
      ..lineTo(x(8), y(52))
      ..cubicTo(x(8), y(43), x(13), y(38), x(19), y(38))
      ..cubicTo(x(25), y(38), x(30), y(43), x(30), y(52))
      ..lineTo(x(30), y(92))
      // The underside of the diagonal, parallel to its top.
      ..moveTo(x(34), y(46))
      ..lineTo(x(59), y(92))
      // The tower and its slanted roof.
      ..moveTo(x(74), y(92))
      ..lineTo(x(74), y(22))
      ..lineTo(x(98), y(8))
      ..lineTo(x(98), y(92));
    canvas.drawPath(
      lines,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final fill = Paint()..color = ink;
    canvas.drawCircle(Offset(x(25), y(68)), math.max(1.0, 1.3 * s), fill);
    for (final (u, v) in const [(79.0, 30.0), (79.0, 38.0), (87.0, 38.0)]) {
      canvas.drawRect(Rect.fromLTWH(x(u), y(v), 6 * s, 6 * s), fill);
    }
  }
}

/// The moving light: the sweep, the lit window and the gold ribbon along the curve.
///
/// With [progress] null it paints the resting state and never repaints on its own.
class BrowLightPainter extends CustomPainter {
  BrowLightPainter({required this.progress, required this.dip}) : super(repaint: progress);

  final Animation<double>? progress;
  final double dip;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = progress?.value ?? 1.0;
    _sweep(canvas, size, p);
    _window(canvas, size, p);
    _ribbon(canvas, size, p);
  }

  void _sweep(Canvas canvas, Size size, double p) {
    final travel = BrowEntrance.sweep.transform(p);
    final strength = math.sin(math.pi * travel);
    if (strength <= 0.01) return;
    // A band leaning like "/", wide enough to read as light rather than a stripe. It starts and
    // ends fully off-screen, so there is no pop at either end.
    final band = math.max(size.height * 1.2, size.width * 0.3);
    final left = -band * 1.5 + (size.width + band * 2) * travel;
    final gold = BrowInk.gold;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gold.withValues(alpha: 0),
            gold.withValues(alpha: BrowEntrance.sweepPeak * strength),
            gold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(left, 0, band, band * 0.42)),
    );
  }

  void _window(Canvas canvas, Size size, double p) {
    final on = BrowEntrance.window.transform(p);
    final alpha = BrowInk.motifWindowAlpha * on + BrowEntrance.windowFlare * math.sin(math.pi * on);
    if (alpha <= 0) return;
    canvas.drawRect(
      BrowMotif.litPane(BrowMotif.rectFor(size)),
      Paint()..color = BrowInk.window.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  void _ribbon(Canvas canvas, Size size, double p) {
    final spread = BrowEntrance.ribbon.transform(p);
    if (spread <= 0) return;
    // The clip's own curve (see BrowClipper), lifted by a point so the stroke sits inside it
    // instead of being cut in half by it.
    final h = size.height - dip - 1;
    final curve = Path()
      ..moveTo(0, h)
      ..quadraticBezierTo(size.width / 2, h + dip * 2, size.width, h);
    final half = spread / 2;
    Shader light(double alpha) => LinearGradient(
          colors: [
            BrowInk.gold.withValues(alpha: 0),
            BrowInk.gold.withValues(alpha: alpha),
            BrowInk.gold.withValues(alpha: 0),
          ],
          stops: [0.5 - half, 0.5, 0.5 + half],
        ).createShader(Offset.zero & size);
    // A wide faint pass under a thin bright one: reads as a glow without a blur.
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..shader = light(0.16),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Strokes.glyph
        ..shader = light(0.9),
    );
  }

  @override
  bool shouldRepaint(BrowLightPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.dip != dip;
}

// ─────────────────────────────────────────────────────────────────────────────
// LINES
// ─────────────────────────────────────────────────────────────────────────────

/// Plays one line's part of the entrance around whatever [builder] draws.
///
/// [builder] receives the extra tracking the eyebrow is still carrying (0 for the other lines
/// and whenever nothing is animating), so a widget that is not a [BrowText] — the NIVORA
/// signature — can take part in the same settle.
class BrowReveal extends StatelessWidget {
  const BrowReveal({super.key, required this.line, required this.builder});

  final BrowLine line;
  final Widget Function(BuildContext context, double spread) builder;

  @override
  Widget build(BuildContext context) {
    final motion = context.dependOnInheritedWidgetOfExactType<_BrowMotion>();
    final progress = motion?.progress;
    if (progress == null || MediaQuery.disableAnimationsOf(context)) return builder(context, 0);

    if (motion!.kind == BrowEntranceKind.titleOnly) {
      if (line != BrowLine.title) return builder(context, 0);
      return FadeTransition(
        opacity: progress.drive(CurveTween(curve: Motion.enter)),
        child: builder(context, 0),
      );
    }

    switch (line) {
      case BrowLine.eyebrow:
        final v = progress.drive(CurveTween(curve: BrowEntrance.eyebrow));
        return FadeTransition(
          opacity: v,
          child: AnimatedBuilder(
            animation: v,
            builder: (context, _) => builder(context, BrowEntrance.eyebrowSpread * (1 - v.value)),
          ),
        );
      case BrowLine.title:
      case BrowLine.subtitle:
        final title = line == BrowLine.title;
        final v = progress.drive(
          CurveTween(curve: title ? BrowEntrance.title : BrowEntrance.subtitle),
        );
        final rise = title ? BrowEntrance.titleRise : BrowEntrance.subtitleRise;
        return FadeTransition(
          opacity: v,
          child: AnimatedBuilder(
            animation: v,
            // Built once; only the offset changes per frame.
            child: builder(context, 0),
            builder: (context, child) =>
                Transform.translate(offset: Offset(0, rise * (1 - v.value)), child: child),
          ),
        );
    }
  }
}

/// One line of brow type, in the brow's own ink.
///
/// THE COLOUR IS APPLIED HERE, LAST. [style] may set size, weight or line height and nothing it
/// says about colour survives — which is the whole fix for the dark-ink leak.
class BrowText extends StatelessWidget {
  const BrowText.eyebrow(this.text, {super.key, this.textAlign = TextAlign.start, this.style})
      : line = BrowLine.eyebrow;

  const BrowText.title(this.text, {super.key, this.textAlign = TextAlign.start, this.style})
      : line = BrowLine.title;

  const BrowText.subtitle(this.text, {super.key, this.textAlign = TextAlign.start, this.style})
      : line = BrowLine.subtitle;

  final String text;
  final BrowLine line;
  final TextAlign textAlign;
  final TextStyle? style;

  /// The resolved style for [line]. Public so a test can hold the numbers to account.
  static TextStyle styleFor(BuildContext context, BrowLine line, [TextStyle? base]) {
    final tt = Theme.of(context).textTheme;
    final slot = switch (line) {
      // chip 10/600, the same caps eyebrow the console always used, with more air.
      BrowLine.eyebrow => (tt.labelSmall ?? const TextStyle())
          .copyWith(letterSpacing: BrowInk.eyebrowTracking),
      // 4:135 sets the header's own title at 16/700, not at 20; the bar must not outweigh the
      // KPI figures under it.
      BrowLine.title => tt.titleMedium ?? const TextStyle(),
      // meta 11/400.
      BrowLine.subtitle => tt.bodySmall ?? const TextStyle(),
    };
    final ink = switch (line) {
      BrowLine.eyebrow => BrowInk.eyebrow,
      BrowLine.title => BrowInk.title,
      BrowLine.subtitle => BrowInk.subtitle,
    };
    return slot.merge(base).copyWith(color: ink);
  }

  @override
  Widget build(BuildContext context) {
    assert(
      BrowScope.of(context),
      'BrowText paints light ink and belongs inside GlassHeader(onBrow: true).',
    );
    final resolved = styleFor(context, line, style);
    final label = line == BrowLine.eyebrow ? text.toUpperCase() : text;
    final still = MediaQuery.disableAnimationsOf(context);

    return BrowReveal(
      line: line,
      builder: (context, spread) {
        final paragraph = Text(
          label,
          style: spread == 0
              ? resolved
              : resolved.copyWith(letterSpacing: (resolved.letterSpacing ?? 0) + spread),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
        if (still) return paragraph;
        // A changed string cross-fades rather than snapping: the loading title giving way to the
        // real one, or a count appearing in a title.
        return AnimatedSwitcher(
          duration: BrowEntrance.titleSwap,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.enter,
          layoutBuilder: (current, previous) => Stack(
            alignment: textAlign == TextAlign.center
                ? Alignment.center
                : AlignmentDirectional.centerStart,
            children: [...previous, ?current],
          ),
          child: KeyedSubtree(key: ValueKey<String>(label), child: paragraph),
        );
      },
    );
  }
}

/// THE ONE TITLE BLOCK every brow header is built from.
///
/// Eyebrow, title and subtitle are strings, never widgets, so no call site can hand the brow a
/// line styled in the theme's ink. [leading] and [actions] are widgets because they are controls
/// and glyphs: an unstyled [Icon], [IconButton] or [PopupMenuButton] takes the brow's ink from the
/// frame, and a slot that names its own colour reads BrowScope. A TextButton or OutlinedButton is
/// not themed for the brow, and none sits on one.
///
/// Every line is one line and ellipsises, so the bar keeps the design's height rhythm — 14 + 24
/// + 16 of type inside the header's own 12dp padding — whatever the strings are.
class BrowTitleBlock extends StatelessWidget {
  const BrowTitleBlock({
    super.key,
    required String this.title,
    this.eyebrow,
    this.subtitle,
    this.leading,
    this.actions = const [],
  })  : _mastheadName = null,
        leadingExtent = 0;

  /// The dashboard treatment: the greeting and the NIVORA signature centred on the SCREEN, with
  /// [leading] (the account avatar) at the start and an empty box of [leadingExtent] opposite it,
  /// so the block is not pushed off-centre by exactly one avatar. No leading, no box.
  const BrowTitleBlock.masthead({
    super.key,
    required String name,
    this.leading,
    this.leadingExtent = AvatarSize.header + Space.xs * 2,
  })  : title = null,
        eyebrow = null,
        subtitle = null,
        actions = const [],
        _mastheadName = name;

  final String? title;
  final String? eyebrow;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  /// The width of the empty twin opposite [leading] on a masthead. The default is the account
  /// avatar's 44dp disc inside 8dp of padding either side.
  final double leadingExtent;

  final String? _mastheadName;

  @override
  Widget build(BuildContext context) {
    final name = _mastheadName;
    if (name != null) {
      final block = MastheadBlock(name: name);
      if (leading == null) return Center(child: block);
      return Row(
        children: [
          leading!,
          Expanded(child: Center(child: block)),
          SizedBox(width: leadingExtent),
        ],
      );
    }

    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: Space.xs)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) BrowText.eyebrow(eyebrow!),
              BrowText.title(title!),
              if (subtitle != null) BrowText.subtitle(subtitle!),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}
