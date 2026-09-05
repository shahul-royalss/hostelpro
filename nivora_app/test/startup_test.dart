// THE FIRST FRAME, AND THE BLACK RECTANGLE THAT USED TO SIT WHERE IT SHOULD HAVE BEEN.
//
// The owner's screenshot was a completely black screen with only the status bar on it: no card,
// no text, no spinner. Nothing in the Flutter tree draws that, and that is the clue. Until the
// engine renders its first frame the screen belongs to Android, and android/app/src/main/res
// pins that window to a single flat colour — `@color/nivora_ground`, #0B0D0F — deliberately, so
// the handoff to the splash is invisible. A window with no logo and no text is invisible in the
// other direction too: while it is up there is nothing on screen to photograph or diagnose.
//
// `main()` used to `await Supabase.initialize()` BEFORE `runApp()`, so that window stayed up for
// the whole of it. The work behind that call is local — SharedPreferences, the keystore, the
// app_links platform channel — but it is UNBOUNDED, and an unbounded wait before the first frame
// is an app that "does not open" with no crash and no log line.
//
// The order is inverted now: runApp first, initialisation behind the frame it draws. These tests
// pin the two things that makes true.
//
//   1. THE APP DRAWS WHILE INITIALISATION IS STILL IN FLIGHT. Not "eventually" — with the
//      readiness future deliberately never completing, which is the wedged case.
//
//   2. NOTHING TOUCHES `Supabase.instance` IN THE MEANTIME. It throws until initialisation
//      finishes, so starting the UI early without a gate would only move the failure earlier.
//      Exactly one provider builds on the first frame — AuthController, through the router's
//      refresh listenable — and it now awaits [supabaseReadyProvider] before its first `_db`.
//      A regression here does not look like a failed test elsewhere; it looks like a black
//      screen on a phone, which is why the assertion is here and not implied.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/boot/startup.dart';
import 'package:mobile/features/splash/splash_screen.dart';
import 'package:mobile/shared/wordmark.dart';
import 'package:mobile/main.dart';

/// A readiness future with the manners of the failure being guarded against: it is accepted and
/// never answered. A delay would eventually complete and prove nothing.
Future<void> _neverReady() => Completer<void>().future;

void main() {
  testWidgets('the drawn wordmark still announces the app name', (tester) async {
    // Replacing Text('NIVORA') with a CustomPaint silently removes the app's name from the
    // accessibility tree unless the mark carries a label — a blind user opening the app would
    // be handed an unlabelled box. Rendered at full opacity, away from the splash's fade,
    // because that is what this test is about.
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          height: 70,
          child: NivoraWordmark(progress: 1, color: Color(0xFFF5F3EE)),
        ),
      ),
    ));

    expect(find.bySemanticsLabel('NIVORA'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the splash is on screen while initialisation is still running', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseReadyProvider.overrideWith((ref) => _neverReady())],
        child: const NivoraApp(),
      ),
    );
    // One frame. Not pumpAndSettle, which would hang on the splash's progress indicator — and
    // which would also let this pass for the wrong reason, by waiting for something.
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    // The wordmark is drawn geometry now, not a Text — so this asserts the mark is mounted AND
    // that it still announces the app's name. The name disappearing from the accessibility
    // tree is exactly the regression that swapping a Text for a CustomPaint invites.
    // The wordmark is drawn geometry now rather than a Text, so this asserts the mark itself
    // is mounted. Its accessibility label is asserted separately, below: on this frame the
    // reveal is still at zero and Opacity(0) legitimately drops its child from the semantics
    // tree, so looking for the label here would be testing the fade, not the label.
    expect(find.byType(NivoraWordmark), findsOneWidget);
    // The whole point: an initialisation that never finishes leaves the BRAND on screen, not
    // Android's flat window. Before this change there was no frame at all to hold it.
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing reaches for Supabase.instance before it exists', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseReadyProvider.overrideWith((ref) => _neverReady())],
        child: const NivoraApp(),
      ),
    );
    // Well past the first frame, and past every post-frame callback the shell schedules.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // `Supabase.instance.client` throws AssertionError when the app was never initialised —
    // which is the case in every test, including this one. So an exception here is not a
    // testing artefact to be swallowed; it is the exact production failure the gate prevents,
    // caught at the only moment it is cheap to see.
    expect(tester.takeException(), isNull);
    expect(find.byType(SplashScreen), findsOneWidget);
  });

  group('a startup that cannot succeed still explains itself', () {
    testWidgets('it says so, shows the raw error, and offers a way back', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        StartupFailure(
          error: 'SocketException: Failed host lookup',
          onRetry: () => retries++,
        ),
      );
      await tester.pump();

      expect(find.text('Nivora could not start'), findsOneWidget);
      // The raw message, for the person the screenshot gets sent to.
      expect(find.textContaining('SocketException'), findsOneWidget);

      // A failure with no way forward is the same bug as a blank screen, wearing a sentence.
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('it paints the brand ground, not a white rectangle', (tester) async {
      await tester.pumpWidget(const StartupFailure(error: 'boom'));
      await tester.pump();

      // The window behind this screen is #0B0D0F and the app is dark-only. This used to paint
      // #F6F8FC over it — the same flash android/app/src/main/res was changed to remove, kept
      // alive on the one screen nobody rehearses.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFF0B0D0F));
    });

    testWidgets('with no retry wired it is still legible, never blank', (tester) async {
      await tester.pumpWidget(const StartupFailure(error: 'boom'));
      await tester.pump();

      expect(find.text('Try again'), findsNothing);
      expect(find.text('Nivora could not start'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE COLD-START RESTORE, WHICH USED TO HOLD THE SPLASH FOR AS LONG AS THE SERVER LIKED
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // The second half of "the app does not open". Past the launch window, the splash itself is a
  // holding state: resolveRedirect keeps the user on it for exactly as long as the auth phase
  // is AsyncLoading with no value, which is exactly as long as the first session restore runs.
  //
  // signIn, verifyMfa and changePassword all wrapped their resolve in a deadline. THE RESTORE
  // DID NOT. Against this project's free-tier NANO — which flips PostgREST and Auth to
  // Unhealthy under memory pressure, accepts the connection and then answers nothing — the
  // `public.users` read never returned, so the phase never resolved and the splash spun with
  // no crash, no log line and no way for the person holding the phone to tell a dead server
  // from a slow one.
  //
  // Written as a PAIR, like data_deadline_test.dart: the deadline fires, AND a healthy restore
  // still passes straight through. "Times out every time" would satisfy the first alone, and a
  // deadline that fires on working traffic is a worse bug than no deadline at all.
  group('a session restore that is never answered gives up', () {
    // Overriding the deadline is how this runs in milliseconds rather than fifteen seconds.
    // What is under test is that a deadline EXISTS and is honoured, not its exact size.
    const quick = Duration(milliseconds: 40);

    test('the deadline fires instead of holding the splash forever', () async {
      final phase = await restoreWithin(
        () => Completer<AuthPhase>().future,
        deadline: quick,
      );

      // Resolved, therefore the router leaves the splash. That is the whole fix.
      expect(phase, isA<AuthSignedOut>());
    });

    test('and it arrives carrying a sentence, not silently', () async {
      final phase = await restoreWithin(
        () => Completer<AuthPhase>().future,
        deadline: quick,
      ) as AuthSignedOut;

      // The login screen renders this (see role_routing_test.dart). A refusal the user cannot
      // read is the same blank screen with more steps.
      expect(phase.message, serverNotResponding);
      expect(phase.message!.toLowerCase(), contains('not responding'));
      // And it must not be reported as a bad password: nobody said no, nobody said anything.
      expect(phase.message!.toLowerCase(), contains('not a problem with your'));
    });

    test('a restore that answers in time is passed through untouched', () async {
      final resolved = AuthNeedsMfa('factor-1');
      expect(await restoreWithin(() async => resolved, deadline: quick), same(resolved));
    });

    test('a restore that FAILS still fails — the deadline swallows nothing else', () async {
      // Only TimeoutException becomes a signed-out phase. A PostgrestException, a refusal, a
      // parse error: those keep throwing, land as AsyncError, and route to the login screen
      // the way they always did. Widening the catch would turn every real auth failure into a
      // "server is not responding" that sends the user to reboot their router.
      await expectLater(
        restoreWithin(() async => throw StateError('bad row'), deadline: quick),
        throwsA(isA<StateError>()),
      );
    });

    test('the restore deadline is the same one every other auth step gets', () {
      expect(restoreDeadline, const Duration(seconds: 15));
    });
  });

  test('the startup deadline exists and is a human span', () {
    // The value is a judgement call; that there IS one is not. Everything behind
    // Supabase.initialize() is local I/O, so a device that needs twenty seconds has a real
    // problem and the person holding it deserves to be told rather than left in front of a
    // black window forever.
    expect(startupDeadline.inSeconds, greaterThan(0));
    expect(startupDeadline.inMinutes, lessThan(1));
  });
}
