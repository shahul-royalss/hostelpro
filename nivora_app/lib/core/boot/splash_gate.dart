import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// THE LAUNCH GROUND, #EBE3D8 — the warm beige the Apnivaas launch animation is drawn on.
///
/// Every surface between the launcher tap and the end of the animation paints this one value:
/// the pre-Android-12 launch window (res/drawable/launch_background.xml, LaunchTheme), the
/// Android 12+ system splash (res/values-v31/ AND res/values-night-v31/styles.xml), the window
/// behind Flutter (NormalTheme), the iOS launch screen (LaunchScreen.storyboard) and the Flutter
/// splash itself. They are copies of `@color/splash_ground` in res/values/colors.xml.
///
/// IT IS MEASURED, NOT PICKED. The animation's outer ring is blended into one flat colour when
/// scripts/gen-icons.mjs builds assets/brand/apnivaas_splash.webp, and lossy WebP moves a flat
/// colour by about one level when it encodes it. This is the DECODED border of the shipped file;
/// a one-level square seam around the logo is visible on a phone in a dark room.
/// test/splash_asset_bytes_test.dart holds the Dart, Android and iOS copies to this value.
const kSplashGround = Color(0xFFEBE3D8);

/// The launch animation, and the still it settles on.
///
/// Played ONCE (the WebP's own loop count is 1), silent — WebP carries no audio, which is the
/// point: the source video's sound effect must never play over someone's music.
const kSplashAnimationAsset = 'assets/brand/apnivaas_splash.webp';
const kSplashStillAsset = 'assets/brand/apnivaas_splash_still.webp';

/// How many frames the animation has. The splash counts decoded frames against this to know the
/// last one is on screen. test/splash_asset_bytes_test.dart reads the WebP's ANMF chunks and fails
/// if this and the file ever disagree — a stale count would either cut the logo off before it
/// finished or hold everyone until [splashCap].
const kSplashFrameCount = 60;

/// How long the animation runs: 60 frames of 32ms. Also read straight off the file by the test.
const splashAnimationLength = Duration(milliseconds: 1920);

/// THE HARD CAP. Whatever happens — a budget phone janking through its first frames, a decoder
/// that stalls, a frame callback that never comes — the opening never holds anyone longer than
/// this. A brand moment that can trap a signed-in user behind it is a bug wearing a logo.
///
/// It is the animation plus the 200ms fade into the app plus a little slack for a slow first
/// frame, not a round number.
const splashCap = Duration(milliseconds: 2500);

/// Whether the opening has finished: the last frame shown and faded, tapped away, or capped.
///
/// ── WHY A PROVIDER AND NOT A TIMER INSIDE THE SPLASH ──────────────────────────────────────
///
/// The screen cannot enforce this itself. What replaces it is the router's redirect, which reads
/// the auth phase and moves the moment a session resolves — on a warm start that is well under
/// 200ms, so the logo would be cut off mid-sweep. The redirect therefore has to be able to ask
/// "has the opening finished?", and the answer has to live somewhere the redirect can read
/// synchronously.
///
/// Riverpod's container outlives the splash widget, so this also survives the screen being
/// rebuilt — which matters, because a rebuild that restarted the clock would extend the wait
/// rather than bound it. And because the container lives as long as the process, the opening
/// plays on a FRESH start only: resuming the app from the background never shows it again.
///
/// ── WHY THE ANIMATION OPENS IT, NOT A CLOCK ───────────────────────────────────────────────
///
/// The old opening was a Flutter animation on a fixed 1.5s, so a timer and the picture could not
/// disagree. A decoded WebP can: its first frames may arrive late on a budget phone, so a
/// wall-clock gate would open mid-sweep there and hold an already finished logo on a fast one.
/// The splash therefore calls [finish] when the LAST frame has been shown (and faded), and the
/// timer here is only the [splashCap] safety net behind it.
class SplashGate extends Notifier<bool> {
  @override
  bool build() {
    // Reduce-motion means no animation to protect, so nothing to wait for. A person who asked
    // the OS for less motion is shown the finished still and is not held in front of it.
    if (_disableAnimations) return true;

    // A HELD Timer, NOT Future.delayed, and it is cancelled on dispose — an outliving timer is a
    // callback holding a disposed container, and Flutter's test framework rightly fails on it.
    final timer = Timer(splashCap, finish);
    ref.onDispose(timer.cancel);
    return false;
  }

  /// Ends the opening. Called by the splash when the last frame has been shown and faded, or
  /// when the person taps to skip; also what the [splashCap] timer calls. Idempotent.
  void finish() {
    if (ref.mounted && !state) state = true;
  }

  /// Set from the widget tree once, because MediaQuery is not readable from a provider.
  static bool _disableAnimations = false;

  /// Called by the splash before the gate is first read. Idempotent.
  static void reportReducedMotion({required bool disabled}) {
    _disableAnimations = disabled;
  }

  /// Ends the wait immediately. For tests, so a widget test does not sit through the cap in
  /// real time per case.
  @visibleForTesting
  void completeNow() => state = true;
}

final splashGateProvider = NotifierProvider<SplashGate, bool>(SplashGate.new);

/// A gate that is already open, for tests.
///
/// Every widget test that mounts the real router starts at [splashRoute] and expects to be
/// redirected the moment its stubbed auth phase resolves. With the real gate they would each
/// have to pump the whole cap of fake time, which is testing the clock rather than the thing
/// under test.
///
/// Declared HERE rather than in a test helper on purpose: the production default is the
/// conservative one — closed, and it opens on the animation or the cap — and a test that wants
/// it open has to say so at its call site.
///
///     ProviderScope(overrides: [splashGateProvider.overrideWith(OpenSplashGate.new)], ...)
class OpenSplashGate extends SplashGate {
  @override
  bool build() => true;
}
