import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/router/router.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/auth/change_password_screen.dart';

/// Every account this platform creates — an owner made by the super admin, staff made by an
/// owner, a student made by a warden — arrives with `must_change_password = true`. The router
/// sends all of them here before anything else, which makes this the single screen that stands
/// between a new user and the product.
///
/// It shipped as a placeholder: a Scaffold of Text widgets with no field, no button and no way
/// to sign out. A new owner installing the app was locked out on their first login, and would
/// have had no idea why. These tests exist so that cannot come back.
class _StubAuth extends AuthController {
  _StubAuth(this._phase);
  final AuthPhase _phase;

  @override
  Future<AuthPhase> build() async => _phase;
}

void main() {
  NivoraSession sessionFor({required bool mustChangePassword}) => NivoraSession(
        userId: '00000000-0000-0000-0000-000000000001',
        role: UserRole.owner,
        fullName: 'New Owner',
        status: 'active',
        mustChangePassword: mustChangePassword,
        email: 'owner@example.com',
      );

  Future<void> pump(WidgetTester tester, AuthPhase phase) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => _StubAuth(phase))],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            routerConfig: ref.watch(routerProvider),
            theme: NivoraTheme.light(),
            debugShowCheckedModeBanner: false,
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Mount the screen on its own, for the states the router will not route to.
  Future<void> pumpScreen(
    WidgetTester tester, {
    required bool mustChangePassword,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _StubAuth(AuthSignedIn(sessionFor(mustChangePassword: mustChangePassword))),
          ),
        ],
        child: MaterialApp(
          theme: NivoraTheme.light(),
          debugShowCheckedModeBanner: false,
          home: const ChangePasswordScreen(),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a new account owing a password change gets a usable form, not a dead end',
      (tester) async {
    await pump(tester, AuthSignedIn(sessionFor(mustChangePassword: true)));

    // The symptom that shipped: a title and nothing to do.
    expect(find.text('This screen is not built yet.'), findsNothing);

    expect(find.text('Set your password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'New password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Confirm new password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save password'), findsOneWidget);

    // The way out, so the screen can never trap someone who cannot finish right now.
    expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);

    // ── THIS ASSERTION USED TO SAY THE OPPOSITE, AND THE SERVER SETTLED IT ──
    // It read: "A forced change must NOT demand the temporary password the user just typed to
    // get here", and pinned `find.widgetWithText(TextFormField, 'Current password')` to
    // findsNothing. Measured against the live project on 2026-09-01:
    //
    //     PUT /auth/v1/user {"password":"…"}                     -> 400 current_password_required
    //     PUT /auth/v1/user {"password":"…","current_password":"…"} -> 200
    //
    // `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD` is on for this project, so the
    // two-field screen this test was protecting could not complete a single password change —
    // and every account on the platform is routed through it before it can reach anything else.
    // The old assertion was not defending a rule; it was defending a form that did not work.
    //
    // What replaces it keeps the part that was really at stake: the label. A person on this
    // screen is holding a temporary password somebody read out to them, and "Current password"
    // sends them looking for one they never chose.
    expect(find.widgetWithText(TextFormField, 'Temporary password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Current password'), findsNothing);
  });

  testWidgets('a voluntary change asks for the current password by that name', (tester) async {
    // The same field, the other reader: somebody who chose their own password and is changing
    // it. The router only ever sends an account here while the flag is set, so this one mounts
    // the screen directly rather than routing to it.
    await pumpScreen(tester, mustChangePassword: false);

    expect(find.text('Change your password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Current password'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Temporary password'), findsNothing);
  });

  testWidgets('the temporary password is required before anything is sent', (tester) async {
    // The field is not decoration. An empty one must stop the submit locally rather than spend
    // a round trip to be told `current_password_required` by GoTrue.
    await pump(tester, AuthSignedIn(sessionFor(mustChangePassword: true)));

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'correct1horse');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'), 'correct1horse');
    await tester.tap(find.widgetWithText(FilledButton, 'Save password'));
    await tester.pump();

    expect(find.text('Enter the temporary password you were given'), findsOneWidget);
  });

  testWidgets('the password rules match the web app, and are enforced before any request',
      (tester) async {
    await pump(tester, AuthSignedIn(sessionFor(mustChangePassword: true)));

    final next = find.widgetWithText(TextFormField, 'New password');
    final confirm = find.widgetWithText(TextFormField, 'Confirm new password');
    final save = find.widgetWithText(FilledButton, 'Save password');

    // Too short.
    await tester.enterText(next, 'ab1');
    await tester.enterText(confirm, 'ab1');
    await tester.tap(save);
    await tester.pump();
    expect(find.text('Use at least 8 characters'), findsOneWidget);

    // Long enough, but no digit.
    await tester.enterText(next, 'abcdefghij');
    await tester.enterText(confirm, 'abcdefghij');
    await tester.tap(save);
    await tester.pump();
    expect(find.text('Include at least one number'), findsOneWidget);

    // Long enough, but no letter.
    await tester.enterText(next, '1234567890');
    await tester.enterText(confirm, '1234567890');
    await tester.tap(save);
    await tester.pump();
    expect(find.text('Include at least one letter'), findsOneWidget);

    // Valid, but the confirmation disagrees.
    await tester.enterText(next, 'correct1horse');
    await tester.enterText(confirm, 'correct1hors');
    await tester.tap(save);
    await tester.pump();
    expect(find.text("Passwords don't match"), findsOneWidget);
  });

  testWidgets('an account that does NOT owe a change is never sent here', (tester) async {
    await pump(tester, AuthSignedIn(sessionFor(mustChangePassword: false)));

    expect(find.text('Set your password'), findsNothing);
    expect(find.text('Change your password'), findsNothing);
  });

  test('the forced flag decides the route, and it comes from the profile row', () {
    final owed = AsyncData<AuthPhase>(
      AuthSignedIn(sessionFor(mustChangePassword: true)),
    );
    // It outranks the role home, and outranks the splash.
    expect(resolveRedirect(phase: owed, here: splashRoute), changePasswordRoute);
    expect(resolveRedirect(phase: owed, here: '/owner'), changePasswordRoute);
    // And once satisfied, it stops diverting.
    final settled = AsyncData<AuthPhase>(
      AuthSignedIn(sessionFor(mustChangePassword: false)),
    );
    expect(resolveRedirect(phase: settled, here: splashRoute), '/owner');
  });
}
