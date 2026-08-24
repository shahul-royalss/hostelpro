import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/session.dart';

void main() {
  group('resolveLoginEmail', () {
    // This mapping is shared with the web app. If it drifts, the SAME person cannot sign in on
    // both clients — which is exactly the kind of break a unit test should catch, not a user.
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
