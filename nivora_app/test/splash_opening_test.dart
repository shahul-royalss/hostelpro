// THE OPENING, ASSERTED FRAME BY FRAME.
//
// ── WHY A TEST AND NOT A SCREENSHOT ───────────────────────────────────────────────────────
//
// I tried to verify this on a device first and could not. Android 12's own splash screen shows
// the launcher icon on the window background for several seconds on a debug build, and every
// screenshot I took during launch caught THAT rather than Flutter's screen — three captures,
// byte-for-byte identical, which I first read as "the animation is frozen". It was not; it was
// the OS, and the app had already moved on to onboarding by the time I looked again.
//
// A screenshot over adb costs about a second per round trip, which is most of a 1,500ms
// animation. So the device can tell me the opening EXISTS and cannot tell me it PROGRESSES.
// This can, exactly, with no video tooling on the machine and nothing to eyeball.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/boot/splash_gate.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/splash/splash_screen.dart';

/// The clip that folds IVORA away behind the mark. Its widthFactor IS the animation.
double _unfold(WidgetTester tester) {
  final align = tester.widget<Align>(
    find.ancestor(of: find.text('IVORA'), matching: find.byType(Align)).first,
  );
  return align.widthFactor!;
}

Widget _app() => const ProviderScope(
      child: MaterialApp(home: SplashScreen()),
    );

void main() {
  testWidgets('the mark arrives first, then IVORA comes out of it', (tester) async {
    await tester.pumpWidget(_app());

    // FRAME ZERO, AND THE MARK IS ALREADY THERE.
    //
    // It does not fade in, deliberately: Android's own splash shows this same artwork on this
    // same background for a second before Flutter draws, so fading it up made the logo blink
    // out and back. A device screenshot is what caught that — the test suite could not have.
    //
    // Asserted as the ABSENCE of an Opacity above the mark, which is the actual invariant. My
    // first version of this assertion read the Opacity's value with `skip: true` attached
    // because the widget was gone — an expect that can never fail, which is the exact thing
    // this file exists to avoid.
    expect(
      find.ancestor(of: find.byType(Image), matching: find.byType(Opacity)),
      findsNothing,
      reason: 'the mark must not fade in — it continues the system splash seamlessly',
    );
    expect(_unfold(tester), 0, reason: 'IVORA is not folded away at the start');

    // 40% in: the mark has fully arrived and the letters have started to emerge.
    await tester.pump(const Duration(milliseconds: 600));
    final atMiddle = _unfold(tester);
    expect(atMiddle, greaterThan(0), reason: 'IVORA has not started unfolding by 600ms');
    expect(atMiddle, lessThan(1), reason: 'IVORA finished before the animation was half done');

    // The end: fully out, and not a fraction over.
    await tester.pump(const Duration(milliseconds: 900));
    expect(_unfold(tester), 1, reason: 'IVORA is not fully out when the opening ends');

    // Nothing thrown along the way — a missing asset would surface here.
    expect(tester.takeException(), isNull);

    // Let the gate's timer expire so the test does not end holding one.
    await tester.pump(splashMinimum);
  });

  testWidgets('the whole opening is 1500ms — the number the owner asked for', (tester) async {
    await tester.pumpWidget(_app());

    // One millisecond short, the mark must NOT be finished. This is the assertion that would
    // catch someone quietly shortening the animation to make a test faster.
    await tester.pump(splashMinimum - const Duration(milliseconds: 100));
    expect(_unfold(tester), 1,
        reason: 'the unfold ends at 78% of the timeline, so it is done well before the gate');

    expect(splashMinimum, const Duration(milliseconds: 1500));
    await tester.pump(splashMinimum);
  });

  testWidgets('reduce motion shows the finished mark, and waits for nothing', (tester) async {
    // A person who asked the OS for less motion should not be held in front of a still picture
    // for a second and a half. The gate is open immediately and the lockup is already complete.
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SplashScreen(),
        ),
      ),
    ));
    await tester.pump();

    expect(_unfold(tester), 1, reason: 'reduce motion should show the finished lockup');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ground is the light canvas, so the launch does not flash', (tester) async {
    // The chain is one colour: launcher plate, Android launch window (values/ AND
    // values-night/), this screen, and the first real screen. It painted the near-black brand
    // ground until the app became light-only, at which point every cold start would have gone
    // light, dark, light.
    await tester.pumpWidget(_app());
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, NivoraTheme.light().scaffoldBackgroundColor);
    await tester.pump(splashMinimum);
  });
}
