import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';

void main() {
  group('resolveLoginEmail', () {
    // This mapping is shared with the web app (lib/utils.ts). If it drifts, the SAME person
    // cannot sign in on both clients — exactly the kind of break a unit test should catch,
    // not a user.
    //
    // It now has to carry BOTH student logins at once: a resident registered with an email
    // signs in as that email, and one registered without keeps the phone mapping. Neither may
    // cost the other access, which is why every case below is pinned.
    test('a plain phone number becomes a student login', () {
      expect(resolveLoginEmail('9000000001'), '9000000001@$studentLoginDomain');
    });

    test('human separators and a +91 prefix are tolerated', () {
      expect(resolveLoginEmail('+91 90000 00001'), '9000000001@$studentLoginDomain');
      expect(resolveLoginEmail('090000-00001'), '9000000001@$studentLoginDomain');
    });

    test('an email passes through, lowercased', () {
      expect(resolveLoginEmail('  Warden@Demo.App '), 'warden@demo.app');
    });

    // ── A STUDENT'S OWN EMAIL ────────────────────────────────────────────────
    // The reason this function was touched at all: a warden can now register a resident with
    // a real address, and that address IS their login. It must not be mistaken for anything
    // else on the way to GoTrue.
    test("a student's own email is not phone-mapped, whatever it contains", () {
      expect(resolveLoginEmail('aarav@example.com'), 'aarav@example.com');
      // Digits in the local part are not a phone number. The '@' decides first, always.
      expect(resolveLoginEmail('9000000001@example.com'), '9000000001@example.com');
      expect(resolveLoginEmail(' Aarav.Sharma+pg@Example.COM '), 'aarav.sharma+pg@example.com');
    });

    test('the synthetic address itself round-trips unchanged', () {
      // A student who was shown their synthetic address by some other route, or a support
      // engineer reproducing a sign-in, must reach the same account and not a second mapping.
      expect(
        resolveLoginEmail('9000000001@$studentLoginDomain'),
        '9000000001@$studentLoginDomain',
      );
    });

    // ── NEITHER ONE ──────────────────────────────────────────────────────────
    // These used to become "<something>@student.hostelpro.local" — an address that cannot
    // exist, sent as though it might, and a different string from the one the web app derives
    // for the same input. Now both clients hand the typo to the server unchanged.
    test('a string that is neither an email nor a phone number is not phone-mapped', () {
      expect(resolveLoginEmail('admin'), 'admin');
      expect(resolveLoginEmail('  ADMIN '), 'admin');
      // Too few digits to be an Indian mobile number.
      expect(resolveLoginEmail('12345'), '12345');
    });

    test('an empty box does not become a login id', () {
      // '' used to resolve to '@student.hostelpro.local'.
      expect(resolveLoginEmail(''), '');
      expect(resolveLoginEmail('   '), '');
    });

    test('a number too long to normalise is not silently truncated to ten digits', () {
      // The old rule took the LAST ten digits of ANY long string; the web app's
      // normalizePhone only ever strips a leading 91 (at 12 digits) or a leading 0 (at 11).
      // So '00919000000001' resolved to 9000000001@… on the phone and to
      // 00919000000001@… on the web: two different accounts for one typed number, and only
      // one of them the person's own. Both clients now derive the same string.
      expect(
        resolveLoginEmail('00919000000001'),
        '00919000000001@$studentLoginDomain',
      );
    });
  });

  group('UserRole', () {
    test('parses the exact wire values Postgres stores', () {
      expect(UserRole.tryParse('super_admin'), UserRole.superAdmin);
      expect(UserRole.tryParse('student'), UserRole.student);
    });

    test('an unknown role is null rather than a guess', () {
      // A build that does not know a role must not pick a permission set for it.
      expect(UserRole.tryParse('landlord'), isNull);
      expect(UserRole.tryParse(null), isNull);
    });
  });
}
