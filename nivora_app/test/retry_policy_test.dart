// THE RETRY POLICY IS WHAT DECIDES HOW LONG A SPINNER LASTS.
//
// Riverpod's default schedule is ten attempts summing to 38.2 seconds, and it applied to every
// provider in the app — which is how an offline cold start held the splash for 38 seconds and
// the 2FA screen held "Checking your security settings" for the same. core/boot/retry_policy.dart
// replaces it on the root scope. These tests pin the three properties that matter:
//
//   1. The failures that cannot be helped by waiting are NEVER retried.
//   2. The one class that can be is retried briefly and then stops.
//   3. The whole schedule, worst case, fits inside a second — so no screen can ever again be
//      loading for longer than the person holding it would wait.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/boot/retry_policy.dart';
import 'package:mobile/data/models/failure.dart';

void main() {
  group('never retried, because waiting cannot help', () {
    final hopeless = <String, Object>{
      'offline': const OfflineFailure('no network'),
      'raw timeout': TimeoutException('12s', const Duration(seconds: 12)),
      'wrapped timeout': AppFailure.timedOut(
        TimeoutException('12s', const Duration(seconds: 12)),
        sideEffect: SideEffect.none,
      ),
      'access denied': const AccessDeniedFailure('no'),
      'read only': const ReadOnlyFailure('expired plan'),
      'not found': const NotFoundFailure('gone'),
      'conflict': const ConflictFailure('dup'),
      'invalid input': const InvalidInputFailure('bad'),
      'signed out': const SignedOutFailure('out'),
      'session expired': const SessionExpiredFailure('expired'),
      'programming error': StateError('bug'),
      // The auth restore is not wrapped in guard(), so its transport errors arrive raw. This
      // is the shape dart:io produces, matched by text because dart:io is not imported.
      'raw dead socket': Exception('SocketException: Failed host lookup: nivora.app'),
    };

    hopeless.forEach((name, error) {
      test(name, () {
        for (var attempt = 0; attempt < 12; attempt++) {
          expect(nivoraRetry(attempt, error), isNull,
              reason: '$name was scheduled for a retry on attempt $attempt');
        }
      });
    });
  });

  group('retried briefly, because a second try might land', () {
    final transient = <String, Object>{
      'server failure': const ServerFailure('503'),
      'unexpected failure': const UnexpectedFailure('?'),
      'unclassified exception': Exception('something odd'),
    };

    transient.forEach((name, error) {
      test('$name — exactly $maxQuickRetries attempts, then stop', () {
        final delays = <Duration>[];
        for (var attempt = 0; attempt < 12; attempt++) {
          final d = nivoraRetry(attempt, error);
          if (d == null) break;
          delays.add(d);
        }
        expect(delays.length, maxQuickRetries, reason: '$name: $delays');
        expect(delays, orderedEquals(const [Duration(milliseconds: 300), Duration(milliseconds: 600)]));
      });
    });
  });

  test('the worst-case schedule fits inside one second', () {
    // The property the whole file exists for. Riverpod's default sums to 38,200ms; a policy
    // that quietly grew back toward that would pass every test above and still hang a screen.
    var total = Duration.zero;
    for (var attempt = 0; attempt < 12; attempt++) {
      final d = nivoraRetry(attempt, const ServerFailure('503'));
      if (d == null) break;
      total += d;
    }
    expect(total, lessThan(const Duration(seconds: 1)), reason: 'total backoff was $total');
  });
}
