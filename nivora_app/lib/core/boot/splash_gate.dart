import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// HOW LONG THE OPENING IS GUARANTEED TO LAST.
///
/// The product owner asked for the mark's animation to run for a second and a half and to
/// FINISH before anything replaces it — "whatever the speed our dashboard or login shows, firstly
/// it has to complete its animation". That is a real requirement rather than a preference: a
/// brand mark that is interrupted halfway on a fast connection and runs in full on a slow one is
/// not a brand mark, it is a loading indicator wearing one.
const splashMinimum = Duration(milliseconds: 1500);

/// Whether the opening animation has had its full [splashMinimum].
///
/// ── WHY A PROVIDER AND NOT A TIMER INSIDE THE SPLASH ──────────────────────────────────────
///
/// The screen cannot enforce this itself. What replaces it is the router's redirect, which reads
/// the auth phase and moves the moment a session resolves — on a warm start that is well under
/// 200ms, so the mark was being cut off mid-stroke. The redirect therefore has to be able to ask
/// "has the opening finished?", and the answer has to live somewhere the redirect can read
/// synchronously.
///
/// Riverpod's container outlives the splash widget, so this also survives the screen being
/// rebuilt — which matters, because a rebuild that restarted the clock would extend the wait
/// rather than bound it.
class SplashGate extends Notifier<bool> {
  @override
  bool build() {
    // Reduce-motion means no animation to protect, so nothing to wait for. A person who asked
    // the OS for less motion should not be given a longer wait than everyone else — that is the
    // same inversion the aurora's ticker had.
    if (_disableAnimations) return true;

    // A HELD Timer, NOT Future.delayed, and it is cancelled on dispose.
    //
    // The first version fired a bare `Future.delayed`. It worked, and it also left a live timer
    // behind whenever the container went away inside the window — which the widget tests caught
    // immediately ("Pending timers: Timer (duration: 0:00:01.500000)"), because Flutter's test
    // framework treats an outliving timer as the leak it is. In production the same shape is a
    // callback holding a reference to a disposed container: harmless today only because the
    // body checks `ref.mounted` first.
    //
    // Holding the handle and cancelling it is both correct and the thing that makes this
    // testable at all.
    final timer = Timer(splashMinimum, () {
      if (ref.mounted) state = true;
    });
    ref.onDispose(timer.cancel);
    return false;
  }

  /// Set from the widget tree once, because MediaQuery is not readable from a provider.
  static bool _disableAnimations = false;

  /// Called by the splash before the gate is first read. Idempotent.
  static void reportReducedMotion({required bool disabled}) {
    _disableAnimations = disabled;
  }

  /// Ends the wait immediately. For tests, so a widget test does not sit through 1.5 seconds
  /// of real time per case.
  @visibleForTesting
  void completeNow() => state = true;
}

final splashGateProvider = NotifierProvider<SplashGate, bool>(SplashGate.new);

/// A gate that is already open, for tests.
///
/// Every widget test that mounts the real router starts at [splashRoute] and expects to be
/// redirected the moment its stubbed auth phase resolves. With the real gate they would each
/// have to pump 1.5 seconds of fake time, which is 1.5 seconds per case of testing the clock
/// rather than the thing under test.
///
/// Declared HERE rather than in a test helper on purpose: the production default is the
/// conservative one — closed, and it opens on a timer — and a test that wants it open has to
/// say so at its call site. The alternative, making the default open and closing it in
/// production, is the arrangement where the shipped behaviour is the one nothing exercises.
///
///     ProviderScope(overrides: [splashGateProvider.overrideWith(OpenSplashGate.new)], ...)
class OpenSplashGate extends SplashGate {
  @override
  bool build() => true;
}
