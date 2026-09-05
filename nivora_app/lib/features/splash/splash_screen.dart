import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/wordmark.dart';

/// The launch animation.
///
/// ── THE DECISION THIS FILE RECORDS ───────────────────────────────────────────────────────
///
/// This screen used to be deliberately STATIC, and the comment that stood here said so: an
/// animation had been rejected because the splash exists only to cover the session restore,
/// and anything that performs during a restore is a delay wearing a brand's clothes. The
/// product owner has overruled that — "when i opens the app firstly the nivora animation has
/// to display" — so there is an animation now, and the old note is deleted rather than left
/// contradicting the code underneath it.
///
/// The REASON behind the old decision survives as the constraint this animation is built to,
/// because that reason was never wrong:
///
///   1. IT NEVER HOLDS THE USER BACK. There is no minimum duration, no `await`, no completion
///      callback, and nothing here that navigation waits on. This widget only draws. The
///      router decides when the splash is replaced — see `resolveRedirect` — and it does that
///      the instant the first session restore resolves, which on a warm start is a frame or
///      two because supabase_flutter has already rehydrated the token from the keystore. If
///      that lands 80ms in, the reveal is cut off 80ms in. That is the correct outcome, not a
///      glitch to pad around.
///
///   2. SO IT IS BUILT TO BE CUT OFF. One controller, one curve, one composition: the wordmark
///      fades up while it settles the last 4% of its scale. There is no stagger, no second
///      phase, and nothing whose meaning depends on the animation finishing — so every frame
///      of it is a legitimate still of the same picture, and the cross-fade the router runs on
///      top (`FadeForwardsPageTransitionsBuilder`) picks up from wherever it got to. A
///      letter-by-letter reveal or a logo that assembles from pieces would look broken at
///      exactly the moment this screen is most likely to end.
///
///   3. IT IS CHEAP. Two render-object transitions over one `Text`. No `BackdropFilter`, no
///      shader, no image decode — the three things that actually cost a frame at startup, on
///      the budget handset whose owner reported "stuck, lag". `FadeTransition` and
///      `ScaleTransition` listen to the controller directly, so not one widget in this tree
///      rebuilds while it plays.
///
/// ── THE GROUND IS THE BRAND'S, IN BOTH THEMES ────────────────────────────────────────────
///
/// This is the one screen that does not follow `ThemeMode.system`. It paints
/// [NivoraColors.ground] and cream ink explicitly (17.56:1) whichever theme is on, because
/// the colour behind it — the Android launch window, `android/app/src/main/res` — is a single
/// static colour that cannot know the theme either. Pinning both to #0B0D0F is what removes
/// the flash: before this, the launch window resolved to `?android:colorBackground`, which is
/// WHITE on a light-mode phone, so the app opened with a white rectangle that snapped to
/// near-black the moment Flutter painted. A launch screen is brand, not chrome, and the brand
/// is dark.
///
/// ── A NOTE FOR TESTS ─────────────────────────────────────────────────────────────────────
///
/// The reveal itself finishes and stops. The slow-restore cue below it is a
/// `CircularProgressIndicator`, which never stops, so `pumpAndSettle` on this screen still
/// hangs — pump fixed durations instead, as the existing router tests already do.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  /// Where the slow-restore cue starts fading in, as a fraction of the reveal.
  ///
  /// It shares the wordmark's controller rather than owning one, so "the reveal has finished
  /// and we are STILL here" is expressed by a single clock instead of a timer that could fire
  /// after the screen is gone. On a warm start the splash is replaced before this point and
  /// the cue is never seen at all, which is the point: a spinner that flashes for 60ms is
  /// noise, and one that appears only when there is genuinely something to wait for is
  /// information.
  static const _cueStart = 0.75;

  late final AnimationController _controller;

  /// The wordmark's reveal. [Motion.enter] is the app's decelerating curve — motion that
  /// arrives rather than bounces.
  ///
  /// Typed as [CurvedAnimation] rather than [Animation] because a CurvedAnimation registers a
  /// listener on its parent and has to be disposed; the framework's leak tracker fails a test
  /// that forgets.
  late final CurvedAnimation _reveal;
  late final CurvedAnimation _cue;

  /// The signature's drawn width. Wide enough to read the letterforms on the narrowest phone
  /// this ships to and short of the screen edge on it.
  static const double _markWidth = 240;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.slow);
    _reveal = CurvedAnimation(parent: _controller, curve: Motion.enter);
    _cue = CurvedAnimation(
      parent: _controller,
      curve: const Interval(_cueStart, 1, curve: Motion.enter),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Remove animations" in the OS accessibility settings means exactly that. Jumping to the
    // end shows the finished composition — which, because the reveal has no second phase, is
    // the same picture the animation was heading for.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    // CurvedAnimation holds a listener on its parent; all three go before the controller.
    _reveal.dispose();
    _cue.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Not scaffoldBackgroundColor: see the header. This screen is the brand ground in both
      // themes, because the native window behind it is too.
      backgroundColor: NivoraColors.ground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // THE SIGNATURE WRITES ITSELF. This replaces a text wordmark that faded and
            // settled 4% of its scale. Same constraint as before and it still governs: nothing
            // waits for this, the router replaces the splash the instant the session restore
            // resolves, and every frame of a stroke being laid down is a legitimate still of
            // the same picture — so being cut off at 80ms looks like an interrupted signature
            // rather than a glitch.
            //
            // The path is the one the website draws on its sign-in screen, so the mark the app
            // opens with is the mark the user is about to see again. See shared/wordmark.dart
            // for why the geometry is parsed rather than shipped as an .svg.
            //
            // A fixed 3:1 box: the signature is a wide, short mark, and giving it a ratio
            // rather than a height keeps it the same relative size on a small phone and a
            // tablet. ScaleTransition is gone — a stroke that is still being drawn does not
            // also need to be growing.
            FadeTransition(
              opacity: _reveal,
              child: SizedBox(
                width: _markWidth,
                height: _markWidth / 3.4,
                child: AnimatedBuilder(
                  animation: _reveal,
                  builder: (context, _) => NivoraWordmark(
                    progress: _reveal.value,
                    color: NivoraColors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            // Reserved whether or not it is showing, so the wordmark does not shift downward
            // when a slow restore brings the cue in.
            SizedBox(
              height: IconSize.lg,
              child: FadeTransition(
                opacity: _cue,
                child: Center(
                  child: SizedBox(
                    width: IconSize.md,
                    height: IconSize.md,
                    child: const CircularProgressIndicator(
                      strokeWidth: Strokes.glyph,
                      // The gold, named rather than taken from the scheme, for the same
                      // reason as the ground: on a light-mode phone `colorScheme.primary` is
                      // the derived bronze #79590C, which measures 2.97:1 on #0B0D0F and
                      // fails WCAG 1.4.11. The design's own accent measures 8.70:1 there.
                      color: NivoraColors.primary,
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
