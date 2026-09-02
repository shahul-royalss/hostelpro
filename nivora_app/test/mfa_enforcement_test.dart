import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/router/router.dart';

/// Two-factor ENFORCEMENT — the half that was decoration until 2026-08-31.
///
/// Enrolment (test/mfa_enroll_test.dart) could switch 2FA on. Nothing anywhere made it MATTER:
/// `MFA_REQUIRED_ROLES=super_admin,owner` in .env.local had exactly one reader, the Next.js
/// middleware, so for the Flutter client — which reaches PostgREST directly for nearly every
/// read — the second factor bought nothing. An auditor signed in as SUPER_ADMIN through the
/// same endpoint this app uses, with a password alone, and was issued a working token at aal1.
///
/// Enforcement now lives in two server-side places, and [mfaGate] is the client's mirror of
/// them. These tests pin the mirror, arm for arm, against what the server actually does:
///
///   · `app.mfa_satisfied()` — db/migrations/2026-08-31-mfa-enforcement.sql. A conjunct of
///     app.owned_hostel_ids(), app.user_hostel_id() and app.is_super_admin(), which between
///     them back all 65 live policies.
///   · `requireAssurance()` — supabase/functions/_shared/caller.ts, reached from every
///     requireCaller().
///
/// Verified against the live database on 2026-08-31 by impersonating real accounts:
///   owner WITH a factor @ aal1 → hostels 0, students 0, rooms 0, users 1 (own row only)
///   owner WITH a factor @ aal2 → hostels 1, students 1, rooms 16, users 4
///   super_admin, no factor @ aal1 → hostels 3, users 8 (GRACE)
///   owner, no factor @ aal1 → hostels 1, rooms 17 (GRACE)
///   warden @ aal1 → unaffected
///
/// Nothing here needs a network, a Supabase client or a real TOTP: [mfaGate] is pure, and
/// [resolveRedirect] is pure, so the two decisions that matter are both directly assertable.
void main() {
  NivoraSession sessionFor(UserRole role, {bool mustChangePassword = false}) => NivoraSession(
        userId: '00000000-0000-0000-0000-000000000001',
        role: role,
        fullName: 'Test User',
        status: 'active',
        mustChangePassword: mustChangePassword,
        email: 'test@example.com',
      );

  /// The roles Postgres refuses at aal1. Mirrors app.mfa_required_roles().
  const privileged = {UserRole.superAdmin, UserRole.owner};
  const unprivileged = {UserRole.manager, UserRole.warden, UserRole.student};

  group('the grace path — a privileged account with no factor is not locked out', () {
    // THE CASE THAT WOULD HAVE TAKEN THE PLATFORM DOWN. On the day enforcement shipped the
    // super admin had no factor and neither did two of the three owners. A flat
    // "privileged ⇒ aal2 or nothing" refuses them on their next request, and enrolling a
    // factor itself needs a working session — so there would have been no way back in.
    for (final role in privileged) {
      test('${role.wire} with no factor at aal1 is sent to enrol, not refused', () {
        expect(
          mfaGate(role: role, isAal2: false, hasVerifiedFactor: false),
          MfaGate.enrolmentOwed,
        );
      });
    }

    test('enrolment is the only screen that phase can reach', () {
      final phase = AsyncData<AuthPhase>(AuthNeedsMfaEnrolment(sessionFor(UserRole.owner)));

      // From the cold-start splash.
      expect(resolveRedirect(phase: phase, here: splashRoute), mfaEnrolRoute);
      // And from anywhere the user might try to navigate instead.
      expect(resolveRedirect(phase: phase, here: '/owner'), mfaEnrolRoute);
      expect(resolveRedirect(phase: phase, here: '/owner/pgs'), mfaEnrolRoute);
      expect(resolveRedirect(phase: phase, here: loginRoute), mfaEnrolRoute);
      expect(resolveRedirect(phase: phase, here: mfaRoute), mfaEnrolRoute);
      // Once there, it stays put — no redirect loop.
      expect(resolveRedirect(phase: phase, here: mfaEnrolRoute), isNull);
    });

    test('an owed enrolment outranks an owed password change', () {
      // Both are true of a brand-new owner on their first sign-in. The factor is owed FIRST —
      // the same order the web app routes (/mfa before /change-password) and the same order
      // requireSession() in caller.ts is built around. Getting this backwards strands a user
      // on a password screen they are refused, holding a factor they were never asked for.
      final phase = AsyncData<AuthPhase>(
        AuthNeedsMfaEnrolment(sessionFor(UserRole.owner, mustChangePassword: true)),
      );
      expect(resolveRedirect(phase: phase, here: splashRoute), mfaEnrolRoute);
      expect(resolveRedirect(phase: phase, here: changePasswordRoute), mfaEnrolRoute);
    });

    test('grace is per account and closes the moment that account enrols', () {
      // The same owner, before and after enrolling. Nothing is redeployed in between: the
      // `not exists (select 1 from auth.mfa_factors ...)` arm simply stops matching.
      expect(
        mfaGate(role: UserRole.owner, isAal2: false, hasVerifiedFactor: false),
        MfaGate.enrolmentOwed,
      );
      expect(
        mfaGate(role: UserRole.owner, isAal2: false, hasVerifiedFactor: true),
        MfaGate.codeOwed,
      );
    });
  });

  group('a genuine aal2 refusal — a factor that exists must be presented', () {
    // This is the enforcement. Server-side the same session reads ZERO rows: verified live by
    // impersonating the one owner who has held a factor since 2026-08-23.
    for (final role in privileged) {
      test('${role.wire} with a factor at aal1 must enter a code', () {
        expect(
          mfaGate(role: role, isAal2: false, hasVerifiedFactor: true),
          MfaGate.codeOwed,
        );
      });
    }

    test('the code screen is the only screen that phase can reach', () {
      const phase = AsyncData<AuthPhase>(AuthNeedsMfa('factor-1'));
      expect(resolveRedirect(phase: phase, here: splashRoute), mfaRoute);
      expect(resolveRedirect(phase: phase, here: '/owner'), mfaRoute);
      expect(resolveRedirect(phase: phase, here: '/super-admin'), mfaRoute);
      expect(resolveRedirect(phase: phase, here: mfaEnrolRoute), mfaRoute);
      expect(resolveRedirect(phase: phase, here: mfaRoute), isNull);
    });

    test('presenting the code satisfies the gate and releases the session', () {
      for (final role in privileged) {
        expect(
          mfaGate(role: role, isAal2: true, hasVerifiedFactor: true),
          MfaGate.satisfied,
          reason: 'aal2 is the whole of what the server asks for',
        );
      }

      // And the router then lets them to their own home rather than back to /mfa.
      final owner = AsyncData<AuthPhase>(AuthSignedIn(sessionFor(UserRole.owner)));
      expect(resolveRedirect(phase: owner, here: mfaRoute), roleHome[UserRole.owner]);
      expect(resolveRedirect(phase: owner, here: splashRoute), roleHome[UserRole.owner]);
    });

    test('aal2 satisfies the gate even with no factor listed on the token', () {
      // getAuthenticatorAssuranceLevel() reads the token; the factor list can lag it. aal2 is
      // proof a code was presented THIS SESSION, so it wins on its own — matching the server,
      // where `aal = 'aal2'` returns true before any table is read.
      expect(
        mfaGate(role: UserRole.superAdmin, isAal2: true, hasVerifiedFactor: false),
        MfaGate.satisfied,
      );
    });
  });

  group('roles the rule does not name are untouched', () {
    // app.mfa_satisfied() returns true for every role not in app.mfa_required_roles(), so a
    // manager, warden or student sees exactly the rows they saw before enforcement existed.
    // Verified live: warden @ aal1 still reads their hostel's rooms and users.
    for (final role in unprivileged) {
      test('${role.wire} with no factor at aal1 is signed straight in', () {
        expect(
          mfaGate(role: role, isAal2: false, hasVerifiedFactor: false),
          MfaGate.satisfied,
        );
      });

      test('${role.wire} who enrolled anyway is still asked for the code', () {
        // The ONE deliberate divergence from the server, which would let this session through.
        // Asking for more than the server demands can only refuse a session the server would
        // have allowed — never the other way round — and it is what someone who switched 2FA
        // on for themselves expects to happen.
        expect(
          mfaGate(role: role, isAal2: false, hasVerifiedFactor: true),
          MfaGate.codeOwed,
        );
      });
    }
  });

  test('the privileged list matches the one the server enforces', () {
    // A FOURTH copy of a list that must agree with app.mfa_required_roles(),
    // MFA_REQUIRED_ROLES in .env.local and DEFAULT_MFA_REQUIRED_ROLES in caller.ts. Nothing but
    // this assertion checks that the client copy has not drifted.
    expect(mfaRequiredRoles, privileged);
    for (final role in UserRole.values) {
      expect(
        mfaRequiredRoles.contains(role),
        role == UserRole.superAdmin || role == UserRole.owner,
        reason: '${role.wire} is on the wrong side of the privileged list',
      );
    }
  });

  test('every role and every combination resolves to exactly one gate', () {
    // Exhaustive: 5 roles x aal2 x hasFactor. No combination may fall through, and the table
    // below is the whole rule in one place, so a future edit that changes an arm has to change
    // a line here and say so.
    for (final role in UserRole.values) {
      for (final isAal2 in [true, false]) {
        for (final hasFactor in [true, false]) {
          final gate = mfaGate(role: role, isAal2: isAal2, hasVerifiedFactor: hasFactor);
          final expected = isAal2
              ? MfaGate.satisfied
              : hasFactor
                  ? MfaGate.codeOwed
                  : (privileged.contains(role) ? MfaGate.enrolmentOwed : MfaGate.satisfied);
          expect(
            gate,
            expected,
            reason: '${role.wire} aal2=$isAal2 factor=$hasFactor',
          );
        }
      }
    }
  });
}
