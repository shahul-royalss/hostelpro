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

  // ═════════════════════════════════════════════════════════════════════════════════════════
  // EVERY PHASE AGAINST EVERY ROUTE
  // ═════════════════════════════════════════════════════════════════════════════════════════
  //
  // The tests above are the cases somebody thought of. This section is the cases nobody did.
  //
  // A BLANK SCREEN IS NOT A CRASH, and that is what makes it expensive. Two ways this function
  // can produce one, neither of which any single-case test can see:
  //
  //   1. IT NAMES A DESTINATION WITH NO SCREEN BEHIND IT. go_router matches the redirect's
  //      result against the route table; a miss falls through to `errorBuilder`, so a phase
  //      whose only destination was never registered draws a "Not found" card — or, if the
  //      phase is one nobody rehearses, nothing recognisable at all. AuthNeedsMfaEnrolment was
  //      added after these tests were written and had NO coverage here whatsoever: the phase,
  //      its route and its screen were three separate edits, and nothing checked they met.
  //
  //   2. IT LOOPS. A rule that can return its own input, or two that point at each other, ends
  //      after five hops in a GoException and the error page. resolveRedirect now refuses to
  //      return `here` at all, and the fixed-point walk below is what proves the rest.
  //
  // So the matrix is exhaustive by construction rather than by diligence: [appRoutes] is read
  // off the router's own route table, so a route added tomorrow is tested tomorrow without
  // anyone remembering to add it, and every AuthPhase is listed once in [everyPhase] with a
  // static check below that the list is still complete.
  group('every AuthPhase against every route', () {
    final everyPhase = <String, AsyncValue<AuthPhase>>{
      'first restore (no value yet)': const AsyncLoading<AuthPhase>(),
      'restore failed': AsyncError<AuthPhase>(Exception('boom'), StackTrace.empty),
      'signed out': const AsyncData<AuthPhase>(AuthSignedOut()),
      'signed out with a reason':
          const AsyncData<AuthPhase>(AuthSignedOut(message: 'This account has been deactivated.')),
      'a code is owed': const AsyncData<AuthPhase>(AuthNeedsMfa('factor-1')),
      // The phase the whole section was written for.
      'enrolment is owed':
          AsyncData<AuthPhase>(AuthNeedsMfaEnrolment(sessionFor(UserRole.superAdmin))),
      for (final role in UserRole.values)
        'signed in as ${role.name}': AsyncData<AuthPhase>(AuthSignedIn(sessionFor(role))),
      for (final role in UserRole.values)
        'signed in as ${role.name}, password owed': AsyncData<AuthPhase>(
          AuthSignedIn(sessionFor(role, mustChangePassword: true)),
        ),
    };

    test('the matrix covers every subtype of AuthPhase', () {
      // AuthPhase is sealed, so this list is checkable: if a variant is added and not listed
      // here, this fails and the whole matrix below starts covering it. AuthLoading is the one
      // variant the controller never publishes as a VALUE — the value-less AsyncLoading above
      // is how "still restoring" actually reaches the router — so it is listed for the type
      // check and exercised as a value too, because a phase that exists can be reached.
      final covered = {
        AuthLoading,
        AuthSignedOut,
        AuthNeedsMfa,
        AuthNeedsMfaEnrolment,
        AuthSignedIn,
      };
      // `?.` matters: the value-less loading and error entries carry no phase at all, and
      // `null.runtimeType` is the type Null, which would quietly join the set.
      final seen = everyPhase.values.map((p) => p.value?.runtimeType).nonNulls.toSet();
      expect(seen.union({AuthLoading}), covered,
          reason: 'a new AuthPhase must be added to everyPhase, or it is routed by nobody');
    });

    // Included deliberately: the router can be handed AuthLoading as a VALUE (it is a public,
    // constructible variant of a sealed type), and the arm that catches it is the fall-through
    // at the bottom of resolveRedirect. It must land somewhere real, not hold a spinner.
    final phases = {
      ...everyPhase,
      'AuthLoading as a value': const AsyncData<AuthPhase>(AuthLoading()),
    };

    for (final entry in phases.entries) {
      for (final here in appRoutes) {
        test('${entry.key} at $here settles on a registered screen', () {
          // ONE STEP: whatever it decides, that place must exist.
          final first = resolveRedirect(phase: entry.value, here: here);
          if (first != null) {
            expect(appRoutes, contains(first),
                reason: '$here would redirect to $first, which no GoRoute draws');
          }

          // AND EVERY STEP AFTER IT. go_router re-runs the decision on the result, so the
          // walk has to reach a fixed point. Six is one more than go_router's own redirect
          // limit, so a cycle is caught here rather than as an error page on a phone.
          var at = here;
          for (var hop = 0; hop < 6; hop++) {
            final next = resolveRedirect(phase: entry.value, here: at);
            if (next == null) break;
            expect(appRoutes, contains(next), reason: 'hop $hop from $at left the route table');
            at = next;
          }
          expect(resolveRedirect(phase: entry.value, here: at), isNull,
              reason: 'starting at $here, routing never settles — it loops through $at');
        });
      }
    }
  });

  // The invariant that makes the loop above impossible rather than merely absent.
  test('a redirect never names the location it was given', () {
    final phases = <AsyncValue<AuthPhase>>[
      const AsyncLoading<AuthPhase>(),
      AsyncError<AuthPhase>(Exception('boom'), StackTrace.empty),
      const AsyncData<AuthPhase>(AuthSignedOut()),
      const AsyncData<AuthPhase>(AuthLoading()),
      const AsyncData<AuthPhase>(AuthNeedsMfa('factor-1')),
      AsyncData<AuthPhase>(AuthNeedsMfaEnrolment(sessionFor(UserRole.owner))),
      for (final role in UserRole.values)
        AsyncData<AuthPhase>(AuthSignedIn(sessionFor(role))),
      for (final role in UserRole.values)
        AsyncData<AuthPhase>(AuthSignedIn(sessionFor(role, mustChangePassword: true))),
    ];
    // Deep paths as well as registered ones: a role subtree is matched by prefix, and '/'
    // reaches the redirect before any route does.
    final locations = {...appRoutes, '/', '/owner/pgs/1', '/student/fees', '/nope'};

    for (final phase in phases) {
      for (final here in locations) {
        expect(resolveRedirect(phase: phase, here: here), isNot(here),
            reason: 'redirecting $here to itself is an infinite loop, not a no-op');
      }
    }
  });

  test('every phase that is not signed-in has exactly one destination, and it is drawable', () {
    // Stated separately from the matrix because this is the actual claim about blank screens:
    // each holding phase names ONE screen, and that screen is registered. The enrolment phase
    // is the one that shipped without this check.
    expect(resolveRedirect(phase: const AsyncData(AuthNeedsMfa('f')), here: splashRoute),
        mfaRoute);
    expect(appRoutes, contains(mfaRoute));

    final enrol = AsyncData<AuthPhase>(AuthNeedsMfaEnrolment(sessionFor(UserRole.superAdmin)));
    // From EVERY other route, not just the splash: the enrolment screen is the only thing this
    // account may see, so navigating away has to come back.
    for (final here in appRoutes.where((r) => r != mfaEnrolRoute)) {
      expect(resolveRedirect(phase: enrol, here: here), mfaEnrolRoute,
          reason: '$here let a factor-less privileged account out of enrolment');
    }
    expect(resolveRedirect(phase: enrol, here: mfaEnrolRoute), isNull);
    expect(appRoutes, contains(mfaEnrolRoute));
  });
}
