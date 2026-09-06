import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/onboarding/onboarding_gate.dart';
import 'package:mobile/features/onboarding/onboarding_screen.dart';

/// The tour is a courtesy, and every test here is about it behaving like one: it must never
/// stand between somebody and their sign-in form, and it must not come back.
Widget _host(Widget child) => MaterialApp(theme: NivoraTheme.light(), home: child);

const _child = Scaffold(body: Center(child: Text('SIGN IN')));

void main() {
  setUp(() {
    OnboardingGate.seenOverride = null;
    OnboardingGate.markOverride = null;
  });
  tearDown(() {
    OnboardingGate.seenOverride = null;
    OnboardingGate.markOverride = null;
  });

  group('the gate', () {
    testWidgets('a returning user never sees it', (tester) async {
      OnboardingGate.seenOverride = () async => true;
      await tester.pumpWidget(_host(const OnboardingGate(child: _child)));
      await tester.pumpAndSettle();
      expect(find.text('SIGN IN'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('a first-time user gets it', (tester) async {
      OnboardingGate.seenOverride = () async => false;
      await tester.pumpWidget(_host(const OnboardingGate(child: _child)));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Every floor, room and bed'), findsOneWidget);
    });

    testWidgets('NEVER a spinner — the first frame is always the sign-in form', (tester) async {
      // The read is a local stat. Blocking on it would trade an invisible one-frame flash for
      // a blank screen on every launch forever, to answer a question that matters once.
      OnboardingGate.seenOverride = () async => false;
      await tester.pumpWidget(_host(const OnboardingGate(child: _child)));
      expect(find.text('SIGN IN'), findsOneWidget,
          reason: 'before the marker resolves, the child is what is on screen');
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('an unreadable marker skips the tour rather than blocking sign-in',
        (tester) async {
      OnboardingGate.seenOverride = () async => throw StateError('no support directory');
      await tester.pumpWidget(_host(const OnboardingGate(child: _child)));
      await tester.pump();
      expect(find.text('SIGN IN'), findsOneWidget);
    });

    testWidgets('skipping marks it seen and hands over', (tester) async {
      var marked = 0;
      OnboardingGate.seenOverride = () async => false;
      OnboardingGate.markOverride = () async => marked++;
      await tester.pumpWidget(_host(const OnboardingGate(child: _child)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(marked, 1, reason: 'marked before the swap, not after');
      expect(find.text('SIGN IN'), findsOneWidget);
    });

    testWidgets('reaching the end marks it seen', (tester) async {
      var marked = 0;
      OnboardingGate.seenOverride = () async => false;
      OnboardingGate.markOverride = () async => marked++;
      await tester.pumpWidget(_host(const OnboardingGate(child: _child)));
      await tester.pumpAndSettle();

      // Three Nexts to reach the fourth page, then the button becomes the acceptance.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Skip'), findsNothing,
          reason: 'nothing left to skip on the last page, so the control goes');
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(marked, 1);
      expect(find.text('SIGN IN'), findsOneWidget);
    });
  });

  group('the pages', () {
    testWidgets('are four, and none of them borrows the competitor\'s palette', (tester) async {
      await tester.pumpWidget(_host(OnboardingScreen(onDone: () {})));
      await tester.pumpAndSettle();

      final titles = <String>[
        'Every floor, room and bed',
        'Residents, not spreadsheets',
        'Rent that reaches the owner',
        'The day-to-day, in one place',
      ];
      for (var i = 0; i < titles.length; i++) {
        expect(find.text(titles[i]), findsOneWidget);
        if (i < titles.length - 1) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
    });

    testWidgets('page three is the claim a competitor cannot make', (tester) async {
      // Route is the reason this sentence is true, and it is the strongest thing NIVORA has to
      // say to a PG owner. If the copy ever loses it, the tour has lost its point.
      await tester.pumpWidget(_host(OnboardingScreen(onDone: () {})));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(
        find.textContaining('settles into the PG owner'),
        findsOneWidget,
      );
    });
  });
}
