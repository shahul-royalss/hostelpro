// THE OPENING — the Apnivaas launch animation.
//
// ── WHAT IT IS ────────────────────────────────────────────────────────────────────────────
//
// The owner supplied the animation as a 6-second portrait video: a green ribbon sweeps in, folds
// into the A-house, four glass windows appear, and the "Apnivaas" wordmark settles under it. It is
// shipped as an animated WebP (assets/brand/apnivaas_splash.webp, built by scripts/gen-icons.mjs
// --splash): the centre square that holds the logo, at twice the speed, played once, silent.
//
// WHY A WEBP AND NOT THE VIDEO. Flutter's engine decodes animated WebP itself on Android and iOS,
// so this needs no new dependency — no video plugin with its own native player, async start and a
// blank texture before the first frame, no audio focus to steal from someone's music. And WHY
// THE CENTRE SQUARE: the logo lives there, and the portrait frame's corners are empty ground.
//
// ── THE SEAMS, AND WHY THERE ARE NONE ─────────────────────────────────────────────────────
//
// Android 12+ always shows a system splash before Flutter draws. res/values-v31 (and
// values-night-v31, because the night qualifier outranks the API level one) make it plain beige
// with NO icon, in [kSplashGround] — the decoded border colour of the WebP. The video's first
// quarter-second is empty ground too, so the hand-off is beige to beige to ribbon: nothing
// blinks. (Keeping the launcher icon on the system splash gives "logo, blank, logo builds", the
// exact stutter the previous opening's comments warned about.)
//
// The animation is keyed onto transparency (scripts/gen-splash.mjs), so the only colour around
// the logo is the one painted here, [kSplashGround] (#EBE3D8, the native launch colour). The app's
// own ground is the cream page ([ApnivaasColors.background], #F6F2EA), a step lighter, so
// the opening FADES into it before it lets go: the sign-in or home screen that follows then
// arrives on the ground it is already standing on, rather than as a hard cut from one warm white
// to another. The spinner below is the brand forest.
//
// ── WHEN IT ENDS ──────────────────────────────────────────────────────────────────────────
//
// When the last frame has been shown, held for a breath and faded — or the moment the person taps
// to skip. [SplashGate] holds the router on this screen until then, and its own timer is a hard
// [splashCap] behind it, so a janky first frame or a stalled decoder can never trap anyone here.
// Fresh starts only: the gate lives as long as the process, so a resume never replays it.
// Reduce-motion shows the finished still and waits for nothing.

import 'dart:math' as math;

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
  /// How long the finished logo is held before the fade. Long enough to be SEEN as finished,
  /// short enough that animation + hold + fade stays inside [splashCap].
  static const _hold = Duration(milliseconds: 250);

  /// The fade from the brand beige into the app's canvas, logo going with it.
  static const _fadeLength = Duration(milliseconds: 200);

  late final AnimationController _fade =
      AnimationController(vsync: this, duration: _fadeLength);

  /// Whether the OS asked for less motion. Read in didChangeDependencies, because MediaQuery is.
  bool _still = false;

  /// Set once the ending has been scheduled, from the last frame, a tap or a failed decode, so
  /// two of them arriving together end the opening once.
  bool _ending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    // Told to the gate as well as obeyed here: a person who asked the OS for less motion must
    // not be held in front of a still picture.
    SplashGate.reportReducedMotion(disabled: _still);
  }

  @override
  void dispose() {
    _fade.dispose();
    // Two 720px images decoded for one screen nobody will see again this run. Let them go.
    const AssetImage(kSplashAnimationAsset).evict();
    const AssetImage(kSplashStillAsset).evict();
    super.dispose();
  }

  /// Ends the opening: optionally holds the finished logo, fades into the app's canvas, then
  /// opens the gate so the router may move on.
  Future<void> _end({required bool hold}) async {
    if (_ending) return;
    _ending = true;
    if (hold) await Future<void>.delayed(_hold);
    if (!mounted) return;
    await _fade.forward();
    if (!mounted) return;
    ref.read(splashGateProvider.notifier).finish();
  }

  /// Called for every frame the image reports. FRAME COUNTING, NOT A CLOCK: the gate opens when
  /// the picture has actually finished, however fast or slow this phone decoded it.
  void _onFrame(int frame) {
    if (_ending || frame < kSplashFrameCount - 1) return;
    // Never change state during build; frameBuilder runs inside it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _end(hold: true));
  }

  void _onDecodeFailed() {
    if (_ending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _end(hold: false));
  }

  @override
  Widget build(BuildContext context) {
    // Reading it here is what starts the cap — the provider's build() schedules it — so the
    // safety net begins when the screen does, not when the router first happens to ask.
    final opened = ref.watch(splashGateProvider);
    final width = MediaQuery.sizeOf(context).width;
    final side = math.min(width * 0.8, 300.0);

    return GestureDetector(
      // TAP ANYWHERE TO SKIP. Opaque so the empty ground counts, not just the logo.
      behavior: HitTestBehavior.opaque,
      onTap: _still ? null : () => _end(hold: false),
      child: AnimatedBuilder(
        animation: _fade,
        builder: (context, child) => Scaffold(
          backgroundColor: Color.lerp(kSplashGround, ApnivaasColors.background, _fade.value),
          body: child,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: ReverseAnimation(_fade),
                child: SizedBox.square(
                  dimension: side,
                  child: _still
                      ? Image.asset(
                          kSplashStillAsset,
                          semanticLabel: 'Apnivaas',
                          filterQuality: FilterQuality.medium,
                        )
                      : Image.asset(
                          kSplashAnimationAsset,
                          semanticLabel: 'Apnivaas',
                          filterQuality: FilterQuality.medium,
                          // Not gaplessPlayback-dependent and not cached at a smaller size: the
                          // 720px frames are drawn at up to 300dp, and decoding at a smaller
                          // size would soften the wordmark exactly where it is read.
                          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                            if (frame != null) _onFrame(frame);
                            return child;
                          },
                          errorBuilder: (context, error, stack) {
                            // A missing or undecodable asset must not hold anyone until the cap.
                            _onDecodeFailed();
                            return const SizedBox.shrink();
                          },
                        ),
                ),
              ),
              const SizedBox(height: Space.xl),
              // THE SLOW-RESTORE CUE. Only once the opening has finished and we are STILL here —
              // i.e. the saved session is genuinely taking a while. On a normal start the router
              // leaves the moment the gate opens, before this has faded in at all: a spinner that
              // flashes for 60ms is noise; one that appears only when there is something to wait
              // for is information.
              SizedBox(
                height: IconSize.lg,
                child: AnimatedOpacity(
                  opacity: opened ? 1 : 0,
                  duration: Motion.base,
                  child: const Center(
                    child: SizedBox(
                      width: IconSize.md,
                      height: IconSize.md,
                      child: CircularProgressIndicator(
                        strokeWidth: Strokes.glyph,
                        color: ApnivaasColors.brandInk,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
