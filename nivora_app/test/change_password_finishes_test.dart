import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/email_verification_service.dart';

import 'support/fake_verification.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/router/router.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// ═══ THE OWNER'S REPORT, AND WHAT IT TURNED OUT TO BE ═══
///
/// "when i changes the password still it stays at there and it is not showing any confirmation
/// screen and it has to take me from there to my dashboard" — with a screenshot of the form
/// fully filled, the strength meter reading GOOD, and the submit button a flat disabled slab
/// with a spinner and no error text.
///
/// Two independent faults, either of which strands the user. Both are asserted here.
///
/// ONE — THE SCREEN NEVER RELEASED THE BUTTON ON AN EXCEPTION. `_submit` awaited
/// `changePassword` with no try/catch: the only path that cleared `_busy` was a NORMAL return.
/// A future that completes with an ERROR skipped the setState entirely, so the button stayed
/// disabled, the fields stayed locked, the spinner stayed up and no sentence was ever written.
/// Short of killing the app there was no way back to a usable form. That is the picture in the
/// screenshot, and cases (b), (c) and (d) below pin it down.
///
/// TWO — SUCCESS LED NOWHERE. resolveRedirect has no arm for a signed-in user sitting on
/// /change-password once the flag is cleared: it is not the splash, not a public route and not
/// another role's subtree, so the function returns null — STAY PUT. The router was never going
/// to move anybody off this screen, and the controller re-resolving the session could not make
/// it, because "stay put" was already the router's honest answer. The screen has to leave under
/// its own power, which is what the last test in this file states.
class _ScriptedAuth extends AuthController {
  _ScriptedAuth(this._phase, this._behaviour);

  AuthPhase _phase;
  final Future<String?> Function(_ScriptedAuth self) _behaviour;

  int calls = 0;
  String? seenCurrentPassword;
  String? seenNewPassword;
  bool? seenForced;
  int signOuts = 0;

  @override
  Future<AuthPhase> build() async => _phase;

  @override
  Future<String?> changePassword({
    required String newPassword,
    required String currentPassword,
    required bool forced,
  }) {
    calls++;
    seenNewPassword = newPassword;
    seenCurrentPassword = currentPassword;
    seenForced = forced;
    return _behaviour(this);
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    publish(const AuthSignedOut());
  }

  /// What the real controller does at the end of a successful change.
  void publish(AuthPhase next) {
    _phase = next;
    state = AsyncData(next);
  }
}

void main() {
  /// A VERIFIED address by default, and that is now load-bearing rather than incidental.
  ///
  /// Finishing a password change hands an UNVERIFIED account to the verify-email screen before
  /// the dashboard — the sequence the product owner asked for. Every test below is about where
  /// the password change ARRIVES, so they need an account that is not owed that detour; the
  /// detour itself has its own test at the bottom of this file.
  NivoraSession sessionFor({
    required bool mustChangePassword,
    bool emailVerified = true,
  }) =>
      NivoraSession(
        userId: '00000000-0000-0000-0000-000000000001',
        role: UserRole.owner,
        fullName: 'New Owner',
        status: 'active',
        mustChangePassword: mustChangePassword,
        email: 'owner@example.com',
        // A DateTime cannot be a const default, so the flag is the parameter and the instant is
        // built here. Only its presence is ever read.
        emailVerifiedAt: emailVerified ? DateTime.utc(2026, 1, 1) : null,
      );

  late GoRouter router;

  String where() => router.routerDelegate.currentConfiguration.uri.path;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Mount the whole router, because WHERE THE USER ENDS UP is the thing under test.
  Future<_ScriptedAuth> pumpApp(
    WidgetTester tester, {
    required bool mustChangePassword,
    required Future<String?> Function(_ScriptedAuth self) behaviour,
    bool emailVerified = true,
  }) async {
    late _ScriptedAuth auth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The verify screen is reachable from the end of this flow now, and it reads the
          // verification service on build. Without an override that provider reaches for
          // Supabase.instance, which no widget test initialises.
          emailVerificationServiceProvider.overrideWithValue(FakeVerification()),
          authControllerProvider.overrideWith(() {
            auth = _ScriptedAuth(
              AuthSignedIn(sessionFor(
                mustChangePassword: mustChangePassword,
                emailVerified: emailVerified,
              )),
              behaviour,
            );
            return auth;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(
              routerConfig: router,
              theme: NivoraTheme.dark(),
              debugShowCheckedModeBanner: false,
            );
          },
        ),
      ),
    );
    await settle(tester);
    return auth;
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    required String currentLabel,
    String current = 'Temp1234!',
    String next = 'Correct1horse!',
  }) async {
    await tester.enterText(find.widgetWithText(TextFormField, currentLabel), current);
    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), next);
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), next);
    await tester.tap(find.widgetWithText(FilledButton, 'Save password'));
    await tester.pump();
  }

  /// The submit button as the user meets it: live, or a dead slab.
  bool saveIsEnabled() {
    final button = find.widgetWithText(FilledButton, 'Save password');
    if (button.evaluate().isEmpty) return false;
    return (button.evaluate().single.widget as FilledButton).onPressed != null;
  }

  group('a failed change leaves the button usable and names the cause', () {
    testWidgets('(b) the controller throws an AuthException', (tester) async {
      await pumpApp(
        tester,
        mustChangePassword: true,
        behaviour: (_) async => throw const AuthException('boom'),
      );
      await fillAndSubmit(tester, currentLabel: 'Temporary password');
      await settle(tester);

      expect(saveIsEnabled(), isTrue, reason: 'the button must never stay a dead slab');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('did not get an answer'), findsOneWidget);
      expect(where(), changePasswordRoute);
    });

    testWidgets('(c) the controller throws a transport error', (tester) async {
      await pumpApp(
        tester,
        mustChangePassword: true,
        behaviour: (_) async => throw Exception('Connection closed before full header'),
      );
      await fillAndSubmit(tester, currentLabel: 'Temporary password');
      await settle(tester);

      expect(saveIsEnabled(), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('did not get an answer'), findsOneWidget);
    });

    testWidgets('(d) the call never answers — the way out stays open', (tester) async {
      // A future that never completes. The password may or may not have reached the server, so
      // this screen must NOT invent a verdict — but it must not become a room with no door
      // either, which is what disabling Sign out alongside the submit made it.
      final stuck = Completer<String?>();
      final auth = await pumpApp(
        tester,
        mustChangePassword: true,
        behaviour: (_) => stuck.future,
      );
      await fillAndSubmit(tester, currentLabel: 'Temporary password');
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(CircularProgressIndicator), findsOneWidget,
          reason: 'it is honestly still working, and says so');
      final signOut = find.widgetWithText(TextButton, 'Sign out');
      expect((signOut.evaluate().single.widget as TextButton).onPressed, isNotNull,
          reason: 'the escape hatch may never be taken away');
      await tester.tap(signOut);
      await settle(tester);
      expect(auth.signOuts, 1);

      stuck.complete(null);
      await settle(tester);
    });

    testWidgets('a refusal the controller worded itself is shown verbatim', (tester) async {
      await pumpApp(
        tester,
        mustChangePassword: true,
        behaviour: (_) async => 'That temporary password is not right.',
      );
      await fillAndSubmit(tester, currentLabel: 'Temporary password');
      await settle(tester);

      expect(saveIsEnabled(), isTrue);
      expect(find.text('That temporary password is not right.'), findsOneWidget);
      expect(where(), changePasswordRoute);
    });
  });

  group('a successful change confirms, then arrives somewhere', () {
    testWidgets('(a) forced: a confirmation, then the role home', (tester) async {
      await pumpApp(
        tester,
        mustChangePassword: true,
        behaviour: (self) async {
          self.publish(AuthSignedIn(sessionFor(mustChangePassword: false)));
          return null;
        },
      );
      expect(where(), changePasswordRoute);

      await fillAndSubmit(tester, currentLabel: 'Temporary password');
      await tester.pump(const Duration(milliseconds: 50));

      // The confirmation the owner asked for, before the dashboard.
      expect(find.text('Password changed'), findsOneWidget);

      await settle(tester);
      expect(where(), '/owner', reason: 'it has to take the user to their dashboard');
    });

    testWidgets('(c) unverified: the email is proved before the dashboard', (tester) async {
      // The sequence the product owner asked for: a warden creates the account, the new user
      // signs in with the temporary password, sets their own, and only THEN is asked to prove
      // the address. Asking any earlier would be asking somebody to prove an address while
      // they still hold a credential that was read out to them by somebody else.
      await pumpApp(
        tester,
        mustChangePassword: true,
        emailVerified: false,
        behaviour: (self) async {
          self.publish(AuthSignedIn(
            sessionFor(mustChangePassword: false, emailVerified: false),
          ));
          return null;
        },
      );

      await fillAndSubmit(tester, currentLabel: 'Temporary password');
      await settle(tester);

      expect(find.text('Verify your email'), findsOneWidget,
          reason: 'an unverified account is asked to prove the address first');
      expect(where(), isNot('/owner'),
          reason: 'and is not quietly dropped on the dashboard behind it');
    });

    testWidgets('(a) voluntary: the same ending, from a screen nothing forced', (tester) async {
      await pumpApp(
        tester,
        mustChangePassword: false,
        behaviour: (self) async {
          self.publish(AuthSignedIn(sessionFor(mustChangePassword: false)));
          return null;
        },
      );
      // The router does not send an unforced account here; arrive the way settings does.
      router.go(changePasswordRoute);
      await settle(tester);
      expect(where(), changePasswordRoute);
      expect(find.text('Change your password'), findsOneWidget);

      await fillAndSubmit(tester, currentLabel: 'Current password');
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Password changed'), findsOneWidget);

      await settle(tester);
      expect(where(), '/owner');
    });
  });

  testWidgets('the voluntary path sends the current password too', (tester) async {
    // GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_CURRENT_PASSWORD is on for this project, so a
    // change with no current_password is a 400 whichever screen asked for it.
    final auth = await pumpApp(
      tester,
      mustChangePassword: false,
      behaviour: (self) async {
        self.publish(AuthSignedIn(sessionFor(mustChangePassword: false)));
        return null;
      },
    );
    router.go(changePasswordRoute);
    await settle(tester);

    await fillAndSubmit(tester, currentLabel: 'Current password', current: 'Chosen1self!');
    await settle(tester);

    expect(auth.calls, 1);
    expect(auth.seenForced, isFalse);
    expect(auth.seenCurrentPassword, 'Chosen1self!');
    expect(auth.seenNewPassword, 'Correct1horse!');
  });

  test('the router alone will never move a signed-in user off this screen', () {
    // The second fault, stated as the pure function it lives in. With the flag cleared,
    // /change-password is not the splash, not public and not another role's subtree — so
    // resolveRedirect answers "stay put", and the screen has to leave under its own power.
    final settled = AsyncData<AuthPhase>(
      AuthSignedIn(sessionFor(mustChangePassword: false)),
    );
    expect(resolveRedirect(phase: settled, here: changePasswordRoute), isNull);
  });
}
