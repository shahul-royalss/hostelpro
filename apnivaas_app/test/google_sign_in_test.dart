// "CONTINUE WITH GOOGLE", FROM THE PHONE'S SIDE OF THE WIRE.
//
// What these tests can prove is the client: that the token goes to mobile-auth and nowhere else,
// with the nonce the server needs; that every server answer is rendered as the right one of the
// four verdicts, and never as "wrong password"; that a closed account sheet says nothing; that a
// refused Google account is forgotten so the next visit does not quietly retry it; that a
// deliberate sign-out stays signed out; and that a build without a Web client ID draws no button.
//
// What they cannot prove is the server: the signature check, the staff refusal and the identity
// guard live in supabase/functions/mobile-auth and db/migrations/2026-10-17-google-sign-in.sql,
// and the SQL is tested by 2026-10-17-google-sign-in.test.sql against a real database.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/auth_endpoint.dart';
import 'package:mobile/core/auth/google_id_token.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/features/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_session.dart';

/// The controller, pointed at a client a test can watch. See [AuthController.clientOverride].
class _Auth extends AuthController {
  _Auth(this._client);
  final SupabaseClient _client;

  @override
  Future<AuthPhase> build() {
    clientOverride = _client;
    return super.build();
  }
}

/// Google, scripted. Counts what was asked of it.
class _FakeGoogle implements GoogleIdTokenSource {
  _FakeGoogle({
    this.available = true,
    this.onRequest = const GoogleTokenIssued(idToken: 'google-id-token', rawNonce: 'raw-nonce-0123456789'),
    this.onQuiet = const GoogleTokenCancelled(),
  });

  final bool available;
  final GoogleTokenOutcome onRequest;
  final GoogleTokenOutcome onQuiet;
  int requests = 0;
  int quietRequests = 0;
  int forgets = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<GoogleTokenOutcome> request() async {
    requests++;
    return onRequest;
  }

  @override
  Future<GoogleTokenOutcome> requestQuietly() async {
    quietRequests++;
    return onQuiet;
  }

  @override
  Future<void> forget() async => forgets++;
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE ENDPOINT
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the Google token goes to mobile-auth, and its answers decode honestly', () {
    late List<Map<String, Object?>> sent;

    FunctionInvoker answering(Object step) => (name, {body}) async {
          expect(name, mobileAuthFunction, reason: 'never GoTrue directly');
          sent.add(Map<String, Object?>.from(body! as Map));
          if (step is FunctionException) throw step;
          return step as FunctionResponse;
        };

    setUp(() => sent = []);

    Future<AuthVerdict> google(Object step) => MobileAuthEndpoint(answering(step))
        .signInWithGoogle(idToken: 'google-id-token', nonce: 'raw-nonce-0123456789');

    test('the body is the google action, the token and the RAW nonce — nothing else', () async {
      await google(const FunctionResponse(status: 200, data: {
        'data': {'accessToken': 'a', 'refreshToken': 'r'},
      }));
      expect(sent.single, {
        'action': 'google',
        'idToken': 'google-id-token',
        'nonce': 'raw-nonce-0123456789',
      });
    });

    test('tokens back is a grant', () async {
      final verdict = await google(const FunctionResponse(status: 200, data: {
        'data': {'accessToken': 'a', 'refreshToken': 'r'},
      }));
      expect(verdict, isA<AuthGranted>());
    });

    test("the server's own sentence is shown for a refusal (no account, staff, deactivated)",
        () async {
      const staff =
          'Staff and administrator accounts sign in with the login they were given, not with Google.';
      final verdict = await google(
        const FunctionsHttpException(status: 403, details: {'ok': false, 'error': staff}),
      );
      expect(verdict, isA<AuthRejected>());
      expect((verdict as AuthRejected).message, staff);
    });

    test('a refusal with no sentence never falls back to "wrong password"', () async {
      final verdict = await google(const FunctionsHttpException(status: 400, details: null));
      expect((verdict as AuthRejected).message, MobileAuthEndpoint.googleRejected);
      expect(verdict.message.toLowerCase(), isNot(contains('password')));
    });

    test('an outage is an outage, in Google words', () async {
      final verdict = await google(const FunctionsHttpException(status: 503, details: null));
      expect(verdict, isA<AuthUnavailable>());
      expect((verdict as AuthUnavailable).message, MobileAuthEndpoint.googleUnavailable);
    });

    test('the limiter applies to Google exactly as to a password', () async {
      final verdict = await google(const FunctionsHttpException(status: 429, details: {
        'ok': false,
        'error': 'Too many attempts. Please wait 9 minutes and try again.',
        'retryAfterSeconds': 540,
      }));
      expect(verdict, isA<AuthThrottled>());
      expect((verdict as AuthThrottled).retryAfter, const Duration(seconds: 540));
    });

    test('the password path keeps its own fallback', () async {
      final verdict = await MobileAuthEndpoint(answering(
        const FunctionsHttpException(status: 400, details: null),
      )).signIn(loginEmail: 'r@example.com', password: 'pw');
      expect((verdict as AuthRejected).message, MobileAuthEndpoint.genericRejection);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE NONCE
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the nonce', () {
    test('Google gets sha256(raw) as lowercase hex — the form GoTrue compares', () {
      // FIPS 180-2 test vector.
      expect(hashNonce('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    test('a raw nonce is 32 random bytes, URL-safe, no padding, and never repeats', () {
      final a = newRawNonce();
      final b = newRawNonce();
      expect(a, hasLength(43));
      expect(a, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(a, isNot(b));
      // Deterministic with a seeded source, so the shape above is not luck.
      expect(newRawNonce(Random(1)), newRawNonce(Random(1)));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE CONTROLLER
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('AuthController.signInWithGoogle', () {
    late List<String> requests;
    late SupabaseClient client;

    setUp(() {
      requests = [];
      client = SupabaseClient(
        'https://stub.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          requests.add('${request.method} $path');
          http.Response json(Object? body, [int status = 200]) => http.Response(
                jsonEncode(body),
                status,
                request: request,
                headers: const {'content-type': 'application/json'},
              );
          if (path.endsWith('/auth/v1/user')) {
            return json({
              'id': 'user-1',
              'aud': 'authenticated',
              'role': 'authenticated',
              'app_metadata': <String, Object?>{},
              'user_metadata': <String, Object?>{},
              'created_at': '2026-01-01T00:00:00.000Z',
              'factors': <Object?>[],
            });
          }
          if (path.endsWith('/rest/v1/users')) {
            return json([
              {
                'id': 'user-1',
                'role': 'student',
                'full_name': 'Resident',
                'email': 'resident@gmail.com',
                'phone': null,
                'hostel_id': 'hostel-1',
                'status': 'active',
                'must_change_password': false,
                'email_verified_at': null,
              },
            ]);
          }
          if (path.endsWith('/auth/v1/logout')) return http.Response('', 204, request: request);
          return json({'ok': true});
        }),
      );
      addTearDown(client.dispose);
    });

    ({ProviderContainer container, List<Map<String, Object?>> calls}) world(
      _FakeGoogle google, {
      FunctionResponse? answer,
      FunctionsHttpException? refusal,
    }) {
      final calls = <Map<String, Object?>>[];
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => _Auth(client)),
        googleIdTokenSourceProvider.overrideWithValue(google),
        mobileAuthEndpointProvider.overrideWith(
          (ref) => MobileAuthEndpoint((name, {body}) async {
            calls.add(Map<String, Object?>.from(body! as Map));
            if (refusal != null) throw refusal;
            return answer ??
                FunctionResponse(status: 200, data: {
                  'ok': true,
                  'data': {
                    'accessToken': fakeJwt(expiresAt: DateTime.now().add(const Duration(hours: 1))),
                    'refreshToken': 'refresh-2',
                  },
                });
          }),
        ),
      ]);
      addTearDown(container.dispose);
      container.listen(authControllerProvider, (_, _) {});
      return (container: container, calls: calls);
    }

    test('a granted Google sign-in installs the session and publishes the phase', () async {
      final google = _FakeGoogle();
      final w = world(google);
      await w.container.read(authControllerProvider.future);

      final message = await w.container.read(authControllerProvider.notifier).signInWithGoogle();

      expect(message, isNull);
      expect(w.calls.single['action'], 'google');
      expect(w.calls.single['idToken'], 'google-id-token');
      expect(w.calls.single['nonce'], 'raw-nonce-0123456789');
      final phase = w.container.read(authControllerProvider).value;
      expect(phase, isA<AuthSignedIn>());
      expect((phase as AuthSignedIn).session.role, UserRole.student);
      expect(google.forgets, 0, reason: 'a successful account is remembered for next time');
    });

    test('a closed account sheet says nothing and asks the server nothing', () async {
      final google = _FakeGoogle(onRequest: const GoogleTokenCancelled());
      final w = world(google);
      await w.container.read(authControllerProvider.future);

      final message = await w.container.read(authControllerProvider.notifier).signInWithGoogle();

      expect(message, isNull);
      expect(w.calls, isEmpty);
    });

    test('a Google-side failure is shown when tapped, and swallowed when quiet', () async {
      final google = _FakeGoogle(
        onRequest: const GoogleTokenFailed(GoogleSignInWords.notSetUp),
        onQuiet: const GoogleTokenFailed(GoogleSignInWords.tryAgain),
      );
      final w = world(google);
      await w.container.read(authControllerProvider.future);
      final auth = w.container.read(authControllerProvider.notifier);

      expect(await auth.signInWithGoogle(), GoogleSignInWords.notSetUp);
      expect(await auth.signInWithGoogle(quietly: true), isNull);
      expect(w.calls, isEmpty);
    });

    test('a refusal is shown, and the refused Google account is forgotten', () async {
      const noAccount = 'No account uses someone@gmail.com yet. Sign in with your phone number or '
          'email and password, or ask your PG to add this address to your account.';
      final google = _FakeGoogle();
      final w = world(
        google,
        refusal: const FunctionsHttpException(status: 403, details: {'ok': false, 'error': noAccount}),
      );
      await w.container.read(authControllerProvider.future);

      final message = await w.container.read(authControllerProvider.notifier).signInWithGoogle();

      expect(message, noAccount);
      expect(google.forgets, 1, reason: 'or the next visit quietly retries the refused account');
      expect(w.container.read(authControllerProvider).value, isA<AuthSignedOut>());
    });

    test('an outage is not a refusal: the Google account is kept', () async {
      final google = _FakeGoogle();
      final w = world(google, refusal: const FunctionsHttpException(status: 503, details: null));
      await w.container.read(authControllerProvider.future);

      final message = await w.container.read(authControllerProvider.notifier).signInWithGoogle();

      expect(message, MobileAuthEndpoint.googleUnavailable);
      expect(google.forgets, 0);
    });

    test('a build without a Web client ID asks Google nothing', () async {
      final google = _FakeGoogle(available: false);
      final w = world(google);
      await w.container.read(authControllerProvider.future);
      final auth = w.container.read(authControllerProvider.notifier);

      expect(await auth.signInWithGoogle(), GoogleSignInWords.notSetUp);
      expect(await auth.signInWithGoogle(quietly: true), isNull);
      expect(google.requests + google.quietRequests, 0);
    });

    test('signing out forgets the Google account, so it stays signed out', () async {
      final google = _FakeGoogle();
      final w = world(google);
      await w.container.read(authControllerProvider.future);

      await w.container.read(authControllerProvider.notifier).signOut();
      await Future<void>.delayed(Duration.zero);

      expect(google.forgets, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE SCREEN
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the sign-in screen', () {
    late SupabaseClient client;

    setUp(() {
      client = SupabaseClient(
        'https://stub.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async => http.Response('{}', 200, request: request)),
      );
      addTearDown(client.dispose);
    });

    Widget app(GoogleIdTokenSource google) => ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(() => _Auth(client)),
            googleIdTokenSourceProvider.overrideWithValue(google),
          ],
          child: MaterialApp(theme: ApnivaasTheme.light(), home: const LoginScreen()),
        );

    Future<void> pump(WidgetTester tester, GoogleIdTokenSource google) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(google));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('no Web client ID, no button, and nothing asked of Google', (tester) async {
      final google = _FakeGoogle(available: false);
      await pump(tester, google);

      expect(find.text('Continue with Google'), findsNothing);
      expect(google.quietRequests, 0);
    });

    testWidgets('with Google configured: the button, and ONE quiet attempt on opening',
        (tester) async {
      final google = _FakeGoogle();
      await pump(tester, google);

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(google.quietRequests, 1, reason: 'the "automated" sign-in for a returning user');
      expect(google.requests, 0, reason: 'the account sheet opens only when asked');
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping it asks Google, and a Google-side failure is shown in words',
        (tester) async {
      final google = _FakeGoogle(onRequest: const GoogleTokenFailed(GoogleSignInWords.notOnThisPhone));
      await pump(tester, google);

      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(google.requests, 1);
      expect(find.text(GoogleSignInWords.notOnThisPhone), findsOneWidget);
    });

    testWidgets('a closed account sheet leaves the screen exactly as it was', (tester) async {
      final google = _FakeGoogle(onRequest: const GoogleTokenCancelled());
      await pump(tester, google);

      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(google.requests, 1);
      expect(find.text(GoogleSignInWords.tryAgain), findsNothing);
      expect(find.text(GoogleSignInWords.notSetUp), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
    });
  });
}
