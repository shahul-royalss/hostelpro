import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/router/router.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/shell/role_shell.dart';

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

void main() {
  NivoraSession sessionFor(UserRole role) => NivoraSession(
        userId: '00000000-0000-0000-0000-000000000001',
        role: role,
        fullName: 'Test User',
        status: 'active',
        mustChangePassword: false,
        email: 'test@example.com',
      );

  Future<void> pumpApp(WidgetTester tester, AuthPhase phase) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _StubAuth(phase)),
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

  testWidgets('a session owing a second factor stops at the MFA screen', (tester) async {
    await pumpApp(tester, const AuthNeedsMfa('factor-1'));

    expect(find.byType(RoleShell), findsNothing);
    expect(find.text('Welcome back'), findsNothing);
  });
}
