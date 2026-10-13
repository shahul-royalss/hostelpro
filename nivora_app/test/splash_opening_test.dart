// THE OPENING — the Apnivaas launch animation's behaviour, asserted without decoding an image.
//
// Images never decode under `flutter test` (the fake clock never lets the codec finish), so the
// WebP's frames never arrive here and nothing below may depend on them. That is not a gap, it is
// the most important case: a phone whose decoder stalls must still be let in, by the cap. What
// the PICTURE contains — frame count, timing, loop count, colours — is asserted from the file's
// own bytes in splash_asset_bytes_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/boot/splash_gate.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/features/splash/splash_screen.dart';

Widget _host({bool reduceMotion = false}) => ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: const SplashScreen(),
          ),
        ),
      ),
    );

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SplashScreen)));

String? _assetName(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  final provider = image.image;
  return provider is AssetImage ? provider.assetName : null;
}

Color? _ground(WidgetTester tester) =>
    tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;

void main() {
  // The reduce-motion flag is process-wide by design (MediaQuery is not readable from a
  // provider). Put it back so one case cannot leak into the next.
  tearDown(() => SplashGate.reportReducedMotion(disabled: false));

  testWidgets('plays the Apnivaas animation on the launch ground, named for screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host());

    expect(_assetName(tester), kSplashAnimationAsset);
    expect(_ground(tester), kSplashGround);
    expect(find.bySemanticsLabel('Apnivaas'), findsOneWidget);
    // The old opening's lockup is gone for good.
    expect(find.text('IVORA'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a decoder that never delivers a frame still lets everyone in, at the cap',
      (tester) async {
    await tester.pumpWidget(_host());
    final gate = _container(tester);

    expect(gate.read(splashGateProvider), isFalse, reason: 'the opening has only just begun');
    await tester.pump(splashCap - const Duration(milliseconds: 1));
    expect(gate.read(splashGateProvider), isFalse);
    await tester.pump(const Duration(milliseconds: 2));
    expect(gate.read(splashGateProvider), isTrue,
        reason: 'the cap is a promise: nobody is held longer than splashCap');
  });

  testWidgets('a tap skips it: the beige fades into the app canvas, then the gate opens',
      (tester) async {
    await tester.pumpWidget(_host());
    final gate = _container(tester);

    await tester.tapAt(const Offset(20, 20)); // the empty ground counts, not just the logo
    await tester.pump(); // the fade starts
    await tester.pump(const Duration(milliseconds: 100));
    final mid = _ground(tester)!;
    expect(mid, isNot(kSplashGround));
    expect(mid, isNot(NivoraColors.background));
    expect(gate.read(splashGateProvider), isFalse, reason: 'the gate waits for the fade');

    await tester.pump(const Duration(milliseconds: 150));
    expect(_ground(tester), NivoraColors.background);
    expect(gate.read(splashGateProvider), isTrue);
  });

  testWidgets('reduce motion shows the finished still and waits for nothing', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));

    expect(_assetName(tester), kSplashStillAsset);
    expect(_container(tester).read(splashGateProvider), isTrue,
        reason: 'someone who asked for less motion is not held in front of a still picture');
  });

  testWidgets('the slow-restore spinner appears only once the opening has finished',
      (tester) async {
    await tester.pumpWidget(_host());
    double spinnerOpacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(AnimatedOpacity),
        ))
        .opacity;

    expect(spinnerOpacity(), 0);
    await tester.pump(splashCap + const Duration(milliseconds: 10));
    expect(spinnerOpacity(), 1,
        reason: 'still here after the opening means the session really is slow to restore');
  });

  test('animation + hold + fade fit inside the cap, so the cap is a safety net, not the plan', () {
    const holdAndFade = Duration(milliseconds: 250 + 200);
    expect(splashAnimationLength + holdAndFade < splashCap, isTrue);
  });
}
