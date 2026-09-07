// THE OPENING.
//
// ── WHAT THIS REPLACED, AND WHY ───────────────────────────────────────────────────────────
//
// Until now this screen drew the wordmark as a handwriting animation — a path traced stroke by
// stroke — with "NIVORA WELCOMES YOU" fading in beneath it. The product owner's verdict was that
// it did not look nice, and on a second reading of it he is right for a reason worth writing
// down: a signature being drawn is a gesture about the ACT of writing, which says nothing about
// a company that manages buildings. It also made the mark look hand-made at exactly the moment
// the app is trying to look built.
//
// What he asked for instead is a better idea, and it is the brand's own shape:
//
//     the N arrives on its own, in the middle — and then IVORA comes out from inside it.
//
// That is a mark that ASSEMBLES rather than one that is drawn, and it earns the wordmark instead
// of just presenting it. The letters are type, set in the app's own display face, not a traced
// outline: "simply elegant typographic which represents our logo / brand".
//
// ── THE TIMING IS A CONTRACT, NOT A PREFERENCE ────────────────────────────────────────────
//
// 1,500ms, and it always finishes. See core/boot/splash_gate.dart: the router cannot leave this
// screen until the gate opens, so a warm start that resolves a session in 180ms still shows the
// whole opening. Without that the animation played in full only on a bad connection, which is
// precisely backwards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/boot/splash_gate.dart';
import '../../core/theme/tokens.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// THE N ARRIVES. It fades up and settles from very slightly large, which reads as a mark
  /// coming to rest rather than one being stamped. Finished by 40% so the second phase has
  /// something already-still to emerge from.
  late final Animation<double> _markIn;
  late final Animation<double> _markScale;

  /// IVORA COMES OUT OF THE N. Driven as a width factor on a clip: at 0 the letters are folded
  /// entirely behind the N, at 1 they are fully out. Starting at 0.30 — before the N has quite
  /// settled — because two movements that overlap read as one gesture, where two that queue read
  /// as a list of instructions.
  late final Animation<double> _unfold;

  /// The whole lockup drifts left by half of IVORA's width as those letters appear, so the
  /// FINISHED mark is centred rather than the N being centred and the word hanging off it.
  late final Animation<double> _recentre;

  /// The slow-restore cue. Shares this controller rather than owning a timer, so "the opening
  /// has finished and we are STILL here" is one clock. On a warm start the gate opens and the
  /// screen is replaced before this is ever seen, which is the point: a spinner that flashes for
  /// 60ms is noise; one that appears only when there is genuinely something to wait for is
  /// information.
  late final Animation<double> _cue;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: splashMinimum);

    _markIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.32, curve: Curves.easeOut),
    );
    _markScale = Tween<double>(begin: 1.18, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.40, curve: Curves.easeOutCubic),
    ));
    _unfold = CurvedAnimation(
      parent: _controller,
      // easeOutCubic, not the app's Motion.enter: the letters should decelerate hard at the end
      // so the mark lands rather than glides to a stop.
      curve: const Interval(0.30, 0.78, curve: Curves.easeOutCubic),
    );
    _recentre = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.78, curve: Curves.easeOutCubic),
    );
    _cue = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.86, 1, curve: Curves.easeOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    // Told to the gate as well as obeyed here: a person who asked the OS for less motion must
    // not be held for 1.5 seconds in front of a still picture.
    SplashGate.reportReducedMotion(disabled: still);
    if (still) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reading it here is what starts the 1.5s clock — the provider's build() schedules it — so
    // the wait begins when the screen does, not when the router first happens to ask.
    ref.watch(splashGateProvider);

    return Scaffold(
      // THE LIGHT GROUND, and it is the same value at every step of the launch.
      //
      // This painted NivoraColors.ground (#0B0D0F) to match the native window behind it. Both
      // premises changed on the same day: the app is themeMode.light now, and the light canvas
      // was redrawn to #EEF0F8. A near-black splash in a light-only app is a flash from dark to
      // light on every single launch, and it was going to be the first thing anyone saw.
      //
      // The chain is now one colour end to end — launcher plate, launch window (values/ AND
      // values-night/), this screen, and the first real screen. Nothing blinks.
      backgroundColor: NivoraColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _Lockup(
                markOpacity: _markIn.value,
                markScale: _markScale.value,
                unfold: _unfold.value,
                recentre: _recentre.value,
              ),
            ),
            const SizedBox(height: Space.xl),
            SizedBox(
              height: IconSize.lg,
              child: FadeTransition(
                opacity: _cue,
                child: const Center(
                  child: SizedBox(
                    width: IconSize.md,
                    height: IconSize.md,
                    child: CircularProgressIndicator(
                      strokeWidth: Strokes.glyph,
                      // The brand ink. Gold was right on the old near-black ground and is
                      // 2.24:1 on this one — the same arithmetic that moved the brand off gold
                      // in the first place. See NivoraColors.gold.
                      color: NivoraColors.brandInk,
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

/// The mark, and the letters that come out of it.
///
/// ── HOW "OUT OF THE N" IS ACTUALLY DONE ───────────────────────────────────────────────────
///
/// A ClipRect with a rightward-growing [Align] widthFactor. At 0 the clip has no width, so IVORA
/// occupies no space and is invisible — it is not off-screen or transparent, it is folded to
/// nothing at the N's trailing edge. As the factor grows the letters are revealed left-to-right
/// from precisely that edge, which is what makes them read as emerging FROM the N rather than
/// sliding in beside it.
///
/// Opacity is deliberately NOT animated on them. A fade would make the letters look like they
/// are arriving from elsewhere; the whole idea is that they were inside the N all along.
class _Lockup extends StatelessWidget {
  const _Lockup({
    required this.markOpacity,
    required this.markScale,
    required this.unfold,
    required this.recentre,
  });

  final double markOpacity;
  final double markScale;
  final double unfold;
  final double recentre;

  /// The mark's drawn height. The asset is 781x510, so this gives it about 107 of width.
  static const double _markHeight = 70;

  static const double _fontSize = 44;
  static const _style = TextStyle(
    fontSize: _fontSize,
    fontWeight: FontWeight.w800,
    // The light theme's ink: this screen is the light ground now, not the brand dark.
    color: NivoraColors.textPrimary,
    height: 1,
    // The tracking is the whole difference between a logo and a word. 6 is wide enough to read
    // as a mark at this size without the letters losing their relationship to each other.
    letterSpacing: 6,
  );

  @override
  Widget build(BuildContext context) {
    // Measured, not guessed: the drift has to be exactly half of what IVORA occupies, or the
    // finished lockup sits off-centre by however wrong the guess was.
    final ivoraWidth = _measure('IVORA');

    return Transform.translate(
      // Starts centred on the N and ends centred on the whole mark.
      offset: Offset(-ivoraWidth / 2 * recentre, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // THE REAL MARK, not a letter N set in Inter.
          //
          // I built this with a typographic N first and it was wrong: NIVORA's N is a drawn
          // thing — a house with an arched door and one lit amber window, which is the whole
          // idea of the company in one glyph — and Inter's N says none of that. The asset is
          // assets/brand_mark.png, cut from nivoralogo.png by trimming the padding and taking
          // everything above the largest run of transparent rows, which is the same measured
          // split scripts/gen-icons.mjs uses to make the launcher icon. So the mark here and
          // the icon the user just tapped are the same artwork.
          Opacity(
            opacity: markOpacity,
            child: Transform.scale(
              scale: markScale,
              child: Image.asset(
                'assets/brand_mark.png',
                height: _markHeight,
                // The mark is drawn at 781x510 and shown at 70 tall on a 3x screen, so this
                // decodes at the size it is painted instead of holding a 781px bitmap for a
                // 107px slot.
                cacheHeight: (_markHeight * 3).round(),
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          // A hair of air between the mark and the letters. The mark's own artwork has none.
          const SizedBox(width: Space.xs),
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: unfold,
              child: const Text('IVORA', style: _style),
            ),
          ),
        ],
      ),
    );
  }

  double _measure(String text) {
    final painter = TextPainter(
      text: const TextSpan(text: 'IVORA', style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}
