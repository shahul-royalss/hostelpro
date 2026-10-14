import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_endpoint.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Brute-force protection, from the client's side of the wire.
///
/// ═══ WHAT THIS IS TESTING, AND WHY IT IS TESTED HERE ═══
///
/// An audit measured `/auth/v1/token?grant_type=password` twice: twelve consecutive
/// wrong-password POSTs for a real account, twelve 400s, no 429, no lockout, observed back-off
/// DECREASING (1.37s -> 0.53s), and not one `auth.login.failed` row — so
/// `app.detect_suspicious_activity()` was blind to an attack in progress. The fix put an Edge
/// Function between the phone and GoTrue that spends a durable Postgres counter, keyed by
/// identifier AND by IP, before any password is checked.
///
/// The counter itself lives in Postgres and is verified against the live database, not here —
/// a Dart test cannot prove a server-side limiter exists. What it CAN prove, and what actually
/// broke in the field, is the decode: whether this app tells a throttle apart from a rejection
/// and renders each one honestly. Collapsing those two was the original bug in the client, and
/// it is the one a regression would quietly reintroduce.
///
/// So these tests assert the three things the brief asked for — the limiter trips, its message
/// differs from invalid-credentials, and it recovers — plus the two properties that make the
/// throttle safe to ship: it leaks nothing about whether an account exists, and there is no
/// client-side delay anywhere on the path.
void main() {
  // ── A stand-in for the deployed function. Scripted, so each test states the server behaviour
  // it is about instead of hiding it in a shared fixture.
  FunctionInvoker serving(List<Object> script) {
    var i = 0;
    return (name, {body}) async {
      expect(name, mobileAuthFunction, reason: 'must call the throttled endpoint, not GoTrue');
      final step = script[i < script.length ? i : script.length - 1];
      i++;
      if (step is FunctionException) throw step;
      return step as FunctionResponse;
    };
  }

  FunctionResponse granted() => const FunctionResponse(
        status: 200,
        data: {
          'data': {'accessToken': 'access-token', 'refreshToken': 'refresh-token'},
        },
      );

  /// The 429 the Edge Function really returns: `throttled()` in `_shared/ratelimit.ts` puts the
  /// sentence in `error` and the figure in `retryAfterSeconds`.
  FunctionsHttpException throttled429({
    int retryAfterSeconds = 540,
    String message = 'Too many attempts. Please wait 9 minutes and try again.',
  }) =>
      FunctionsHttpException(
        status: 429,
        details: {'ok': false, 'error': message, 'retryAfterSeconds': retryAfterSeconds},
      );

  /// The 400 it returns for a credential that was checked and refused.
  FunctionsHttpException rejected400() => const FunctionsHttpException(
        status: 400,
        details: {'ok': false, 'error': 'Incorrect email/phone or password.'},
      );

  Future<AuthVerdict> signIn(FunctionInvoker invoker) =>
      MobileAuthEndpoint(invoker).signIn(loginEmail: 'r@example.com', password: 'pw');

  group('the limiter trips', () {
    test('a 429 is a throttle, never a credential verdict', () async {
      final verdict = await signIn(serving([throttled429()]));

      expect(verdict, isA<AuthThrottled>());
      // The distinction that matters: a throttle must not arrive as a rejection. Before the
      // client returned a sealed verdict this collapsed into one nullable String, and a
      // rate-limited user was told their password was wrong.
      expect(verdict, isNot(isA<AuthRejected>()));
    });

    test('the wait comes from the server, not from a guess on the client', () async {
      final verdict = await signIn(serving([throttled429(retryAfterSeconds: 540)]));

      // The countdown shown to a user has to be the window the database is really holding.
      // A locally invented figure would drift from it and either lie or look broken.
      expect((verdict as AuthThrottled).retryAfter, const Duration(seconds: 540));
    });

    test('a throttle never says "wait 0 seconds"', () async {
      // A window that has just rolled can legitimately report 0 left. Rendering that as
      // "wait 0 seconds" reads as a bug to the person holding the phone.
      final verdict = await signIn(serving([throttled429(retryAfterSeconds: 0)]));

      expect((verdict as AuthThrottled).retryAfter.inSeconds, greaterThan(0));
    });

    test('MFA is throttled by the same decoder', () async {
      // A six-digit TOTP is a 10^6 space on a 30-second rotation — the sharper of the two
      // endpoints, and it was equally unthrottled.
      final verdict = await MobileAuthEndpoint(serving([throttled429()]))
          .verifyMfa(factorId: '11111111-2222-3333-4444-555555555555', code: '123456');

      expect(verdict, isA<AuthThrottled>());
    });
  });

  group('the message differs from invalid-credentials', () {
    test('throttled and rejected are two different sentences', () async {
      final throttle = await signIn(serving([throttled429()])) as AuthThrottled;
      final reject = await signIn(serving([rejected400()])) as AuthRejected;

      expect(throttle.message, isNot(equals(reject.message)));
      // Not just different strings — the throttle must not be worded as a password problem at
      // all, or the difference is cosmetic and a user still goes off to reset a good password.
      expect(throttle.message.toLowerCase(), isNot(contains('password')));
      expect(throttle.message.toLowerCase(), contains('too many attempts'));
    });

    test('a 503 is not a rejection either', () async {
      // Not hypothetical: with CAPTCHA protection on, EVERY password grant fails without any
      // credential being examined. Wording that as "wrong password" would send every user in
      // the product to reset a password that was fine.
      final verdict = await signIn(serving([
        const FunctionsHttpException(status: 503, details: {'ok': false, 'error': 'x'}),
      ]));

      expect(verdict, isA<AuthUnavailable>());
      expect(verdict, isNot(isA<AuthRejected>()));
    });

    test('an unreachable function does not fall back to the unthrottled path', () async {
      // A fallback to GoTrue would be a bypass switch with a public trigger: anyone able to make
      // one invocation fail gets the unthrottled endpoint back. Fail closed instead.
      final verdict = await signIn(serving([const FunctionsFetchException()]));

      expect(verdict, isA<AuthUnavailable>());
      expect((verdict as AuthUnavailable).message, MobileAuthEndpoint.unreachable);
    });

    test('every sentence on the four paths is distinct', () async {
      final messages = <String>{
        (await signIn(serving([throttled429()])) as AuthThrottled).message,
        (await signIn(serving([rejected400()])) as AuthRejected).message,
        (await signIn(serving([const FunctionsFetchException()])) as AuthUnavailable).message,
        (await signIn(serving([
          const FunctionsHttpException(status: 500, details: <String, Object?>{}),
        ])) as AuthUnavailable)
            .message,
      };

      // Four outcomes that mean four different things must not share wording, or the screen
      // above cannot tell a user what to actually do next.
      expect(messages, hasLength(4));
    });
  });

  group('it recovers', () {
    test('a throttled account signs in normally once the window passes', () async {
      // The chosen policy is a window that EXPIRES, not an escalating lockout — verified
      // against the live database, where a key that had tripped was allowed again with a full
      // budget after its window aged out. A per-identifier lockout would be
      // attacker-triggerable: anyone who knows a resident's phone number could hold the real
      // person out of their own account.
      final endpoint = MobileAuthEndpoint(serving([throttled429(), granted()]));

      final first = await endpoint.signIn(loginEmail: 'r@example.com', password: 'pw');
      final second = await endpoint.signIn(loginEmail: 'r@example.com', password: 'pw');

      expect(first, isA<AuthThrottled>());
      expect(second, isA<AuthGranted>());
      expect((second as AuthGranted).accessToken, 'access-token');
    });

    test('the throttle leaves no client-side state that keeps blocking', () async {
      // There is deliberately no local attempt counter. If a 429 set one, the client would keep
      // refusing after the server had already forgiven — a lockout no operator could undo.
      final endpoint = MobileAuthEndpoint(serving([
        throttled429(),
        throttled429(),
        throttled429(),
        granted(),
      ]));

      for (var i = 0; i < 3; i++) {
        expect(await endpoint.signIn(loginEmail: 'r@example.com', password: 'pw'), isA<AuthThrottled>());
      }
      expect(await endpoint.signIn(loginEmail: 'r@example.com', password: 'pw'), isA<AuthGranted>());
    });
  });

  group('it does not leak whether the account exists', () {
    test('a 429 is byte-identical for a real and an unknown identifier', () async {
      // The server keys the counter on a HASH of whatever was typed and spends it BEFORE any
      // user lookup, so an address belonging to nobody trips the limiter exactly as readily as
      // a real one. A 429 that only ever appeared for real accounts would be a slower
      // enumeration oracle rather than a fix.
      final real = await MobileAuthEndpoint(serving([throttled429()]))
          .signIn(loginEmail: 'resident@example.com', password: 'pw') as AuthThrottled;
      final unknown = await MobileAuthEndpoint(serving([throttled429()]))
          .signIn(loginEmail: 'nobody@example.com', password: 'pw') as AuthThrottled;

      expect(unknown.message, real.message);
      expect(unknown.retryAfter, real.retryAfter);
      expect(unknown.revealsWhetherAccountExists, isFalse);
    });

    test('a rejection says the same thing for both', () async {
      // This population signs in with a PHONE NUMBER. Telling "no such account" apart from
      // "wrong password" would let anyone confirm which numbers live in which PG.
      final a = await MobileAuthEndpoint(serving([rejected400()]))
          .signIn(loginEmail: 'resident@example.com', password: 'pw') as AuthRejected;
      final b = await MobileAuthEndpoint(serving([rejected400()]))
          .signIn(loginEmail: 'nobody@example.com', password: 'pw') as AuthRejected;

      expect(a.message, b.message);
      expect(a.message, MobileAuthEndpoint.genericRejection);
    });
  });

  group('no client-side delay is standing in for the fix', () {
    test('a throttled sign-in returns immediately', () async {
      // A client-side wait is not a control: the endpoint is public and the anon key ships
      // inside the APK, so anything this app declines to send, a script simply sends. If a
      // sleep is ever added here it will slow the honest user and stop nobody — this fails if
      // one appears.
      final clock = Stopwatch()..start();
      await signIn(serving([throttled429(retryAfterSeconds: 540)]));
      clock.stop();

      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('each attempt is exactly one call to the endpoint', () async {
      // No local retry loop either: a client that retried a 429 on the user's behalf would
      // spend their remaining budget for them.
      var calls = 0;
      final endpoint = MobileAuthEndpoint((name, {body}) async {
        calls++;
        throw throttled429();
      });

      await endpoint.signIn(loginEmail: 'r@example.com', password: 'pw');

      expect(calls, 1);
    });

    test('the verdict for a 429 does not depend on how the client is feeling', () {
      // verdictFor is the whole mapping, and it is a pure function of (status, body). Nothing
      // about local attempt history can change what a 429 means.
      final verdict = MobileAuthEndpoint.verdictFor(
        429,
        {'error': 'Too many attempts. Please wait 2 minutes and try again.', 'retryAfterSeconds': 120},
        unavailable: MobileAuthEndpoint.signInUnavailable,
      );

      expect(verdict, isA<AuthThrottled>());
      expect((verdict as AuthThrottled).retryAfter, const Duration(seconds: 120));
    });
  });

  group('the envelope is decoded the way the server writes it', () {
    test('a 2xx with no tokens is an outage, not a rejection', () async {
      // A shape disagreement between client and server is our bug. Saying "wrong password"
      // here would blame the user for it.
      final verdict = await signIn(serving([
        const FunctionResponse(status: 200, data: {'ok': true, 'data': <String, Object?>{}}),
      ]));

      expect(verdict, isA<AuthUnavailable>());
    });

    test('a timeout is an outage', () async {
      final endpoint = MobileAuthEndpoint(
        (name, {body}) => Future.delayed(const Duration(seconds: 30), granted),
        timeout: const Duration(milliseconds: 50),
      );

      expect(
        await endpoint.signIn(loginEmail: 'r@example.com', password: 'pw'),
        isA<AuthUnavailable>(),
      );
    });

    test('an absurd retry-after is clamped rather than shown as a permanent lockout', () async {
      // The longest window this system actually holds is fifteen minutes. A figure far past
      // that is a bug or a hostile proxy, and either way must not read as "locked out forever".
      final verdict = await signIn(serving([throttled429(retryAfterSeconds: 999999)]));

      expect((verdict as AuthThrottled).retryAfter, lessThanOrEqualTo(const Duration(hours: 1)));
    });
  });
}
