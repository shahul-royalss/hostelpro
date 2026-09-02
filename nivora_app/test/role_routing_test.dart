import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/router/router.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/legal/legal_providers.dart';
import 'package:mobile/features/legal/legal_repository.dart';
import 'package:mobile/features/settings/mfa_service.dart';
import 'package:mobile/features/settings/security_screen.dart';
import 'package:mobile/features/shell/role_shell.dart';

import 'fake_consent.dart';

/// Drives the REAL router through the REAL widget tree, with only the auth phase stubbed.
///
/// The pure-function tests in router_redirect_test.dart prove the routing DECISION. These prove
/// the wiring around it: that a cold start actually leaves the splash, that each role lands in
/// its own shell, and that a signed-out start reaches the login form. That gap is where the
/// shipped bug lived — the decision function did not exist yet, and nothing exercised the tree.
///
/// No network is involved, which matters on a machine whose TLS is intercepted by antivirus.
class _StubAuth extends AuthController {
  _StubAuth(this._phase);
  final AuthPhase _phase;

  @override
  Future<AuthPhase> build() async => _phase;
}

/// The enrolment screen is a real destination now (AuthNeedsMfaEnrolment routes to it), so
/// mounting it needs the seam it talks to — otherwise it reaches for `Supabase.instance`, which
/// throws in a test and turns "does this screen draw?" into "is Supabase initialised?".
class _OfflineMfa implements MfaService {
  @override
  Future<MfaState> load() async => const MfaState.off();

  @override
  Future<TotpEnrollment> begin({String? friendlyName}) async =>
      const TotpEnrollment(factorId: 'f', secret: 'JBSWY3DPEHPK3PXP', uri: 'otpauth://totp/x');

  @override
  Future<void> confirm({required String factorId, required String code}) async {}

  @override
  Future<void> disable({required String factorId, required String code}) async {}
}

void main() {
  NivoraSession sessionFor(UserRole role, {bool mustChangePassword = false}) => NivoraSession(
        userId: '00000000-0000-0000-0000-000000000001',
        role: role,
        fullName: 'Test User',
        status: 'active',
        mustChangePassword: mustChangePassword,
        email: 'test@example.com',
      );

  /// [consent] is the state of this user's agreement to the legal documents.
  ///
  /// ConsentGate wraps every role home in the router's table, so a signed-in destination is now
  /// reachable only by a user who has agreed. The default here is somebody who ALREADY HAS —
  /// which is the precondition every assertion below was written under, before the gate existed
  /// and made it explicit. The gate's own behaviour is proven in test/legal_consent_test.dart,
  /// and the two tests directly beneath the shell group pin the fact that it really does block.
  Future<void> pumpApp(
    WidgetTester tester,
    AuthPhase phase, {
    LegalConsentStore? consent,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _StubAuth(phase)),
          mfaServiceProvider.overrideWithValue(_OfflineMfa()),
          legalConsentStoreProvider
              .overrideWithValue(consent ?? FakeConsentStore.accepted()),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
            theme: NivoraTheme.light(),
            debugShowCheckedModeBanner: false,
          ),
        ),
      ),
    );
    // Let the async notifier resolve and the router settle. pumpAndSettle would hang on the
    // splash's CircularProgressIndicator, which never stops animating.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a signed-out cold start reaches the login form, not a stuck splash',
      (tester) async {
    await pumpApp(tester, const AuthSignedOut());

    expect(find.text('Welcome back'), findsOneWidget);
    // The exact symptom that shipped: the spinner still on screen with nothing behind it.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final role in UserRole.values) {
    testWidgets('a signed-in ${role.name} lands in their own shell', (tester) async {
      await pumpApp(tester, AuthSignedIn(sessionFor(role)));

      expect(find.byType(RoleShell), findsOneWidget);
      final shell = tester.widget<RoleShell>(find.byType(RoleShell));
      expect(shell.role, role);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE GATE IS ON THE ROUTE, NOT ON ONE SCREEN
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // The override in pumpApp lets every test above assume an agreed user, which is exactly the
  // kind of convenience that can quietly turn into "the gate is not wired up at all". These two
  // are the counterweight: with the SAME router and the SAME phases, a user who has not agreed
  // reaches no shell — for every role, including the three that render their own shell class
  // (warden, manager, super admin) and would be missed by a wrapper placed inside RoleShell.
  group('a user who has not agreed reaches no shell', () {
    for (final role in UserRole.values) {
      testWidgets('${role.name} is held at the gate', (tester) async {
        await pumpApp(
          tester,
          AuthSignedIn(sessionFor(role)),
          consent: FakeConsentStore.notAccepted(),
        );

        expect(find.byType(RoleShell), findsNothing,
            reason: 'a ${role.name} who has agreed to nothing was let into the product');
        expect(find.text('Please read and agree'), findsOneWidget);
      });
    }

    testWidgets('and is let through the moment they do agree', (tester) async {
      final store = FakeConsentStore.notAccepted();
      await pumpApp(tester, AuthSignedIn(sessionFor(UserRole.owner)), consent: store);

      expect(find.byType(RoleShell), findsNothing);

      // The tick, then the button. Both are required: the button is inert until the box is
      // ticked, which is what stops "Agree" being something a thumb hits on the way past.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('Agree and continue'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(store.writes, 1);
      expect(find.byType(RoleShell), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // NO PHASE DRAWS AN EMPTY FRAME
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // router_redirect_test.dart proves the DECISION never names a screen that does not exist.
  // This proves the other half: that the screen it names actually puts something on the glass.
  // The two are different failures. A route can be registered and still render nothing — a
  // Scaffold whose body is an error state that returns an empty box, a section awaiting a
  // future that never completes — and on a phone both look identical to a routing bug: a flat
  // #0B0D0F rectangle with the status bar on it and no way to tell what went wrong.
  //
  // The assertion is deliberately crude and therefore hard to fool: SOME TEXT IS ON SCREEN.
  // Not a specific string, which would only re-test whichever screen somebody had in mind, but
  // "a person looking at this phone can read something". A blank frame has no text at all.
  group('every phase renders something a person can read', () {
    for (final entry in <String, AuthPhase>{
      'signed out': const AuthSignedOut(),
      'signed out with a reason': const AuthSignedOut(message: 'This account has been deactivated.'),
      'a code is owed': const AuthNeedsMfa('factor-1'),
      // The phase with no widget coverage until now. Its route and its screen were added in
      // separate edits from the phase itself, and nothing ever mounted the three together.
      'enrolment is owed': AuthNeedsMfaEnrolment(sessionFor(UserRole.superAdmin)),
      for (final role in UserRole.values)
        'signed in as ${role.name}': AuthSignedIn(sessionFor(role)),
      for (final role in UserRole.values)
        'signed in as ${role.name}, password owed':
            AuthSignedIn(sessionFor(role, mustChangePassword: true)),
      // Constructible, therefore reachable. The router's fall-through arm has to land it on a
      // real screen rather than hold the splash.
      'AuthLoading as a value': const AuthLoading(),
    }.entries) {
      testWidgets('${entry.key} puts text on screen', (tester) async {
        await pumpApp(tester, entry.value);

        final text = find.byType(Text);
        expect(text, findsWidgets, reason: '${entry.key} rendered a frame with no text on it');
        // And it is not a frame of empty strings, which is the same blank with more widgets.
        final anythingLegible = tester
            .widgetList<Text>(text)
            .any((w) => (w.data ?? w.textSpan?.toPlainText() ?? '').trim().isNotEmpty);
        expect(anythingLegible, isTrue,
            reason: '${entry.key} rendered only empty strings — that is a blank screen');
      });
    }

    testWidgets('a session that owes enrolment lands on the enrolment screen and nowhere else',
        (tester) async {
      await pumpApp(tester, AuthNeedsMfaEnrolment(sessionFor(UserRole.superAdmin)));

      // The screen, not a role shell and not the login form. This is the assertion that the
      // grace arm the server grants actually has somewhere to go.
      expect(find.byType(SecurityScreen), findsOneWidget);
      expect(find.byType(RoleShell), findsNothing);
      expect(find.text('Welcome back'), findsNothing);
      expect(find.text('Security'), findsWidgets);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // WHY THE USER IS LOOKING AT A LOGIN FORM
  // ═══════════════════════════════════════════════════════════════════════════════════════
  //
  // [AuthSignedOut] has carried a `message` for as long as it has existed, and until now
  // NOTHING READ IT. Three sentences were composed with care and dropped: "This account has
  // been deactivated", "Your account is not set up yet", and — since the cold-start restore
  // got a deadline — the server-down sentence. Whoever hit one of them was teleported to an
  // empty form, which reads as "the app forgot me" and is answered by typing the same correct
  // password again and being thrown out again.
  //
  // LOADING, EMPTY, FAILED and REFUSED are four distinct states everywhere else in this app.
  // A refusal drawn as a blank form is that rule broken on the screen every user reaches.
  group('the login screen says why it was reached', () {
    testWidgets('a deactivated account is told, not silently returned to the form',
        (tester) async {
      await pumpApp(tester, const AuthSignedOut(message: 'This account has been deactivated.'));

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('This account has been deactivated.'), findsOneWidget);
    });

    testWidgets('a restore that timed out says the server is not answering', (tester) async {
      // The exact phase AuthController.build() now returns when the cold-start restore reaches
      // its deadline against a wedged backend, instead of holding the splash forever.
      const message = 'The Nivora server is not responding right now. This is not a problem '
          'with your password. Please try again in a few minutes.';
      await pumpApp(tester, const AuthSignedOut(message: message));

      expect(find.text(message), findsOneWidget);
      // A form to act on, in place of a spinner that cannot be acted on.
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('an ordinary sign-out shows no message at all', (tester) async {
      // The user chose this. Explaining it would be noise, and noise is what teaches people to
      // stop reading the line that matters.
      await pumpApp(tester, const AuthSignedOut());

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.textContaining('deactivated'), findsNothing);
      expect(find.textContaining('not responding'), findsNothing);
    });
  });

  testWidgets('a session owing a second factor stops at the MFA screen', (tester) async {
    await pumpApp(tester, const AuthNeedsMfa('factor-1'));

    expect(find.byType(RoleShell), findsNothing);
    expect(find.text('Welcome back'), findsNothing);
  });
}
