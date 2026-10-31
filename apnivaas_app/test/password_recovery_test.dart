import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/password_recovery.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/router/router.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/auth/reset_password_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Round 5: the "Forgot password" link opens "Set a new password" (it used to open an empty
/// sign-in screen, because the recovery event was ignored).

class _Auth extends AuthController {
  _Auth(this.answers);

  /// Returned in order by [completePasswordRecovery].
  final List<RecoveryOutcome> answers;
  final calls = <({String password, String? code})>[];
  int abandons = 0;

  @override
  Future<AuthPhase> build() async => const AuthSignedOut();

  @override
  Future<RecoveryOutcome> completePasswordRecovery(String newPassword, {String? code}) async {
    calls.add((password: newPassword, code: code));
    return answers.removeAt(0);
  }

  @override
  Future<void> abandonPasswordRecovery() async => abandons++;
}

Future<_Auth> _pump(WidgetTester tester, List<RecoveryOutcome> answers) async {
  final auth = _Auth(answers);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => auth)],
    child: MaterialApp(
      theme: ApnivaasTheme.light(),
      home: const ResetPasswordScreen(email: 'riya@example.com'),
    ),
  ));
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  final b = find.widgetWithText(FilledButton, 'Save new password');
  await tester.ensureVisible(b);
  await tester.tap(b);
  await tester.pumpAndSettle();
}

void main() {
  group('the recovery event', () {
    test('passwordRecovery holds the app on the reset screen', () {
      expect(
        actionForAuthEvent(
          event: AuthChangeEvent.passwordRecovery,
          eventToken: 't',
          resolvedToken: null,
          holdsSession: true,
          installingSelf: false,
          signedOutByDeadToken: false,
        ),
        AuthEventAction.recoverPassword,
      );
    });

    test('a dead link is told apart from a token refresh', () {
      expect(isDeadRecoveryLink(const AuthException('expired', code: 'flow_state_expired')), isTrue);
      expect(isDeadRecoveryLink(const AuthException('Code verifier could not be found in local '
          'storage.')), isTrue);
      expect(isDeadRecoveryLink(const AuthException('Invalid Refresh Token', statusCode: '400')),
          isFalse);
      expect(isDeadRecoveryLink(StateError('x')), isFalse);
    });
  });

  group('the router', () {
    final signedIn = AsyncValue<AuthPhase>.data(AuthSignedIn(ApnivaasSession.fromRow(const {
      'id': 'u1',
      'role': 'owner',
      'full_name': 'Riya Sen',
      'status': 'active',
      'must_change_password': false,
      'email_verified_at': '2026-10-01T00:00:00Z',
    })));
    const signedOut = AsyncValue<AuthPhase>.data(AuthSignedOut());

    test('while recovering, every route leads to the reset screen, once', () {
      for (final phase in [signedOut, signedIn]) {
        for (final here in appRoutes) {
          final to = resolveRedirect(phase: phase, here: here, recovering: true);
          expect(to, here == resetPasswordRoute ? isNull : resetPasswordRoute, reason: here);
        }
      }
    });

    test('the opening animation still finishes first', () {
      expect(
        resolveRedirect(
            phase: signedOut, here: splashRoute, openingFinished: false, recovering: true),
        isNull,
      );
    });

    test('nobody reaches the reset screen without a link', () {
      expect(resolveRedirect(phase: signedOut, here: resetPasswordRoute), loginRoute);
      expect(resolveRedirect(phase: signedIn, here: resetPasswordRoute), '/owner');
    });
  });

  group('Set a new password', () {
    testWidgets('mismatched passwords are caught on the phone', (tester) async {
      final auth = await _pump(tester, []);
      expect(find.text('Choose a new password for riya@example.com.'), findsOneWidget);
      await _type(tester, 'reset-new', 'Hostel@2026');
      await _type(tester, 'reset-confirm', 'Hostel@2027');
      await _save(tester);
      expect(find.text("Passwords don't match"), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('saves the password; a second factor is asked for when the server wants it',
        (tester) async {
      final auth = await _pump(tester, [
        (error: null, needsCode: true),
        (error: null, needsCode: false),
      ]);
      await _type(tester, 'reset-new', 'Hostel@2026');
      await _type(tester, 'reset-confirm', 'Hostel@2026');
      await _save(tester);

      expect(auth.calls.single, (password: 'Hostel@2026', code: null));
      expect(find.byKey(const ValueKey('reset-code')), findsOneWidget);
      expect(find.textContaining('Enter its 6-digit code'), findsOneWidget);

      await _type(tester, 'reset-code', '123456');
      await _save(tester);
      expect(auth.calls.last, (password: 'Hostel@2026', code: '123456'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a refusal is shown in words, and Back to sign in leaves', (tester) async {
      final auth = await _pump(tester, [
        (error: 'Choose a password different from your old one.', needsCode: false),
      ]);
      await _type(tester, 'reset-new', 'Hostel@2026');
      await _type(tester, 'reset-confirm', 'Hostel@2026');
      await _save(tester);
      expect(find.text('Choose a password different from your old one.'), findsOneWidget);

      await tester.ensureVisible(find.text('Back to sign in'));
      await tester.tap(find.text('Back to sign in'));
      await tester.pump();
      expect(auth.abandons, 1);
    });
  });
}
