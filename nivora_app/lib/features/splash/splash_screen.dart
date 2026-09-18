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

  /// THE MARK SETTLES. It does NOT fade in, and that is the fix for something a device caught
  /// that no test would have.
  ///
  /// Android 12 shows its own splash first — the launcher icon, which is this same mark, on the
  /// same background. So by the time Flutter draws, the logo has ALREADY been on screen for a
  /// second or more. Fading it up from zero made it blink out and back: logo, blank window while
  /// Flutter boots, blank again, then the logo dissolving in. Three frames of nothing between
  /// two frames of the same picture.
  ///
  /// Holding it at full opacity makes the handoff invisible — the system's logo and this one are
  /// the same artwork at the same place on the same colour, so the seam disappears and all the
  /// eye sees is the moment IVORA starts to unfold. Only a small scale settle is left, which
  /// reads as the mark coming to rest rather than as an arrival.
  late final Animation<double> _markScale;

  /// IVORA COMES OUT OF THE N. Driven as a width factor on a clip: at 0 the letters are folded
  /// entirely behind the N, at 1 they are fully out. Starting at 0.30 — before the N has quite
  /// settled — because two movements that overlap read as one gesture, where two that queue read
  /// as a list of instructions.
  late final Animation<double> _unfold;

  /// THERE IS NO `_recentre` ANY MORE, AND ITS ABSENCE IS THE FIX.
  ///
  /// It used to slide the whole lockup left by half of IVORA's width as the letters emerged, so
  /// that the FINISHED mark would be centred rather than the N being centred with the word
  /// hanging off it. The intent was right and the implementation double-counted: [Center]
  /// re-centres the row on every frame already, because [Align.widthFactor] changes the row's
  /// measured width as the clip opens. Doing it again by hand shifted the finished lockup left
  /// by half of IVORA ON TOP OF a row that was already centred — which is exactly what the
  /// product owner photographed: the mark jammed against the left edge with clear space on the
  /// right. See _Lockup for the one small offset that IS still needed, and why.

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

    // 1.06, not 1.18: a mark that is already visible when the animation starts should look
    // like it is settling, not like it is being thrown at the screen.
    _markScale = Tween<double>(begin: 1.06, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.40, curve: Curves.easeOutCubic),
    ));
    _unfold = CurvedAnimation(
      parent: _controller,
      // easeOutCubic, not the app's Motion.enter: the letters should decelerate hard at the end
      // so the mark lands rather than glides to a stop.
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
                markScale: _markScale.value,
                unfold: _unfold.value,
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
///
/// ── AND HOW IT ENDS UP IN THE MIDDLE ──────────────────────────────────────────────────────
///
/// By doing nothing. `widthFactor` changes the row's MEASURED width every frame, and the
/// [Center] above re-centres whatever it measures — so the mark starts centred on its own, and
/// slides left of its own accord as the letters take up room, finishing with the whole lockup
/// centred. The previous version also translated the row left by half of IVORA to "fix" this,
/// which applied the correction twice and pushed the finished mark hard against the left edge.
///
/// The one offset that IS still needed is [_trailingAir], and it is 3dp.
class _Lockup extends StatelessWidget {
  const _Lockup({required this.markScale, required this.unfold});

  final double markScale;
  final double unfold;

  /// The wordmark's size and tracking. 6 is wide enough to read as a mark at this size without
  /// the letters losing their relationship to each other.
  static const double fontSize = 44;
  static const double letterSpacing = 6;

  /// FLUTTER PUTS LETTER-SPACING AFTER THE LAST LETTER TOO.
  ///
  /// So the Text's measured box is [letterSpacing] wider than its ink, and a row centred on that
  /// box sits its ink half of that to the left. Three device-independent pixels is not much, and
  /// the ask was that the wordmark be centred "perfectly" — this is the difference between
  /// centring the picture and centring the box the picture came in.
  ///
  /// Scaled by [unfold] because the dead space only exists once the final A is out; before that
  /// the clip is cutting through a glyph.
  static const double _trailingAir = letterSpacing / 2;

  /// Inter's cap height is 1490/2048 of the em — the ratio published in the font's own metrics,
  /// not a number measured off a screenshot.
  static const double _capRatio = 1490 / 2048;

  /// HOW BIG THE N IS, AS A MULTIPLE OF THE LETTERS' CAP HEIGHT.
  ///
  /// The product owner has moved this three times, and the latest word stands:
  ///
  ///   - A flat 70dp against a 32dp cap: "the N goes so long". At twice the word's height the
  ///     eye read "[badge] IVORA" instead of NIVORA. That limit still holds.
  ///   - 1.0, exactly cap height, after "the N letter is longer than compared to other letters
  ///     I V O R A" (1.15 had measured 37px of ink against the letters' 34).
  ///   - 1.4, on 2026-09-16: "the N has to be some big compared other letters". This replaces
  ///     the equal-height request.
  ///
  /// WHY 1.4, PICKED BY RENDERING. The splash was drawn at 1.0, 1.30, 1.35, 1.40 and 1.45 on a
  /// 360dp screen at 3x, and the mark's ink over the I's ink measured 0.96, 1.24, 1.30, 1.34 and
  /// 1.40 (the I's ink is 33dp, a hair over the 32dp cap, because of anti-aliasing). At 1.30 the
  /// N is a tower poking above the word; at 1.45 it starts to stand in front of it. At 1.4 it is
  /// plainly the capital of NIVORA and still one word, because the two things that bind it to
  /// IVORA did not move: it stands on the same baseline, and the ink gap to the I is still 7dp.
  ///
  /// THIS NUMBER ONLY BECAME HONEST WHEN THE ASSET WAS RE-CUT. brand_mark.png used to carry a
  /// fringe of alpha 1-3 out to its edges — invisible, and 20% of the file's height. Flutter
  /// sizes the image BOX, so `height: 40` drew 32dp of visible mark and this ratio described
  /// something that was not on the screen. See scripts/cut-brand-mark.py.
  static const double _markToCap = 1.4;

  /// ── THE GAP IS 1.6dp, AND THAT IS NOT A TYPO ────────────────────────────────────────────
  ///
  /// "Same gapping, don't give more gap between them." The gap the eye sees is between INK, and
  /// most of the ink gap here is already spent before this SizedBox contributes anything: Inter
  /// sets the I with a left side bearing of about 5.4dp at this size, inside its own advance.
  ///
  /// Measured off a render of this very screen — mark ink ends at x=469, the I's ink starts at
  /// 495, and the text box starts at 489.6 — the four gaps BETWEEN the letters came out 8, 5, 9
  /// and 6 (letter-spacing 6, plus or minus each pair's bearings), a mean of 7. The mark-to-I
  /// gap was 25. Re-measured after the N grew to 1.4x: still 7dp (21px at 3x), since the gap
  /// hangs off the mark's trailing edge, not its height.
  ///
  /// So the target is the letters' own rhythm, and the arithmetic is: 7 wanted, 5.4 of it
  /// already provided by the bearing, 1.6 left to add. splash_opening_test.dart asserts the
  /// rendered result rather than these numbers, so a font change breaks the test rather than
  /// quietly reopening the gap.
  static const double _inkGap = 7.0;
  static const double _firstGlyphBearing = 5.4;

  /// The face is the app's own, not the platform default.
  ///
  /// This used to be a bare `TextStyle`, which on Android means Roboto — so the brand's name was
  /// set in one typeface on the splash and in another (Inter, via the text theme) on every
  /// masthead a second later. Two wordmarks that nearly match is worse than either.
  static TextStyle styleOf(ThemeData t) =>
      (t.textTheme.labelLarge ?? const TextStyle()).copyWith(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        // The light theme's ink: this screen is the light ground now, not the brand dark.
        color: NivoraColors.textPrimary,
        height: 1,
        letterSpacing: letterSpacing,
      );

  @override
  Widget build(BuildContext context) {
    final style = styleOf(Theme.of(context));
    final painter = TextPainter(
      text: TextSpan(text: 'IVORA', style: style),
      textDirection: TextDirection.ltr,
      // The same size the Text below is set at, which is the point of measuring with it.
      textScaler: TextScaler.noScaling,
    )..layout();

    // THE MARK STANDS ON THE LETTERS' BASELINE, which is where a letter would stand.
    //
    // Centring the two against each other — what this did before — lines up the middle of the
    // mark with the middle of the text's LINE BOX, and a line box has descender room under it
    // that all-caps type never uses. The mark therefore sat low by half that descender. Taking
    // the baseline from the painter rather than from a font constant means this stays true if
    // the face is ever swapped.
    final descent =
        painter.height - painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final capHeight = fontSize * _capRatio;
    final markHeight = capHeight * _markToCap;

    return Transform.translate(
      offset: Offset(_trailingAir * unfold, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
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
          Padding(
            padding: EdgeInsets.only(bottom: descent),
            child: Transform.scale(
              // Scale does not change the laid-out size, so the settle cannot disturb the
              // baseline it is standing on. It does paint the foot about 1dp low at frame zero,
              // but IVORA is folded away then, and the settle is over before the letters are
              // half out. splash_opening_test.dart holds it to that.
              scale: markScale,
              child: Image.asset(
                'assets/brand_mark.png',
                height: markHeight,
                // Decoded at the size it is painted — 3x covers every phone this ships to —
                // instead of holding the whole 405px-tall bitmap for a 45dp slot.
                cacheHeight: (markHeight * 3).round(),
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(width: _inkGap - _firstGlyphBearing),
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: unfold,
              // NOT SCALED WITH THE SYSTEM FONT SIZE. This is a logo, not text anyone reads,
              // and every proportion in this class is against a 44dp face. main.dart lets text
              // grow to 1.4x: at that size these letters grew and the mark did not, so the N
              // came out no taller than IVORA and hung 2dp below its baseline, which undoes the
              // owner's request for exactly the people who turned their font up.
              child: Text('IVORA', style: style, textScaler: TextScaler.noScaling),
            ),
          ),
        ],
      ),
    );
  }
}
