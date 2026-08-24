import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/router/router.dart';

/// These tests exist because the first release build hung on the splash screen forever.
///
/// It never crashed and never logged an error, so nothing in the build output or the device log
/// pointed at it — the app simply appeared not to open. The decision was buried in a closure
/// inside a provider where no test could reach it. It is a pure function now, and the case that
/// shipped broken is the first assertion below.
void main() {
  NivoraSession sessionFor(UserRole role, {bool mustChangePassword = false}) => NivoraSession(
        userId: '00000000-0000-0000-0000-000000000001',
        role: role,
        fullName: 'Test User',
        status: 'active',
        mustChangePassword: mustChangePassword,
        email: 'test@example.com',
      );

  const loading = AsyncLoading<AuthPhase>();
  const signedOut = AsyncData<AuthPhase>(AuthSignedOut());

  group('the splash is never a terminal state', () {
    test('signed out on the splash goes to login — the bug that shipped', () {
      expect(resolveRedirect(phase: signedOut, here: splashRoute), loginRoute);
    });

    for (final role in UserRole.values) {
      test('a signed-in ${role.name} on the splash goes to their home', () {
        final phase = AsyncData<AuthPhase>(AuthSignedIn(sessionFor(role)));
        expect(resolveRedirect(phase: phase, here: splashRoute), roleHome[role]);
      });
    }

    test('an MFA-owed session on the splash goes to the MFA screen', () {
      const phase = AsyncData<AuthPhase>(AuthNeedsMfa('factor-1'));
      expect(resolveRedirect(phase: phase, here: splashRoute), mfaRoute);
    });

    test('a failed restore is treated as signed out, not as a reason to hold', () {
      final phase = AsyncError<AuthPhase>(Exception('boom'), StackTrace.empty);
      expect(resolveRedirect(phase: phase, here: splashRoute), loginRoute);
    });
  });

  group('the first restore holds, later loads do not', () {
    test('a value-less loading state holds on the splash', () {
      expect(resolveRedirect(phase: loading, here: splashRoute), isNull);
      expect(resolveRedirect(phase: loading, here: loginRoute), splashRoute);
    });

    // The hold condition is `isLoading && !hasValue`, and both halves are pinned above: a
    // value-less load holds, and any state carrying a value routes on its value. Riverpod
    // retains the previous value across invalidateSelf(), so a mid-session token refresh
    // arrives as loading-WITH-value and therefore does not interrupt the user. That exact
    // combination cannot be constructed through Riverpod's public API, so it is covered by
    // its two components rather than by reaching into the package's internals.
  });

  group('role isolation', () {
    test('one role cannot sit in another role subtree', () {
      final student = AsyncData<AuthPhase>(AuthSignedIn(sessionFor(UserRole.student)));
      expect(resolveRedirect(phase: student, here: '/owner'), '/student');
      expect(resolveRedirect(phase: student, here: '/owner/analytics'), '/student');
    });

    test('a role stays put inside its own subtree', () {
      final owner = AsyncData<AuthPhase>(AuthSignedIn(sessionFor(UserRole.owner)));
      expect(resolveRedirect(phase: owner, here: '/owner'), isNull);
      expect(resolveRedirect(phase: owner, here: '/owner/pgs'), isNull);
    });

    test('signed out anywhere private goes to login', () {
      for (final home in roleHome.values) {
        expect(resolveRedirect(phase: signedOut, here: home), loginRoute);
      }
    });

    test('signed out on login stays on login — no redirect loop', () {
      expect(resolveRedirect(phase: signedOut, here: loginRoute), isNull);
    });
  });

  test('an owed password change outranks the role home', () {
    final phase = AsyncData<AuthPhase>(
      AuthSignedIn(sessionFor(UserRole.owner, mustChangePassword: true)),
    );
    expect(resolveRedirect(phase: phase, here: splashRoute), changePasswordRoute);
    expect(resolveRedirect(phase: phase, here: '/owner'), changePasswordRoute);
    expect(resolveRedirect(phase: phase, here: changePasswordRoute), isNull);
  });
}
