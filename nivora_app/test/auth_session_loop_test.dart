// TWO-FACTOR SIGN-IN THAT WAS SLOW AND THEN FAILED, AND A LOGIN THAT WAS REFUSED WITH A
// SENTENCE THAT WAS NOT TRUE.
//
// ═══ WHAT WAS ACTUALLY MEASURED, ON THE LIVE PROJECT, 2026-08-31 (UTC) ═══
//
// `edge_logs` for nimxvgzscbanhtvgnjll show the mobile client issuing AuthController._resolve's
// own query —
//
//     GET /rest/v1/users?select=id,role,full_name,email,phone,hostel_id,status,
//                               must_change_password,email_verified_at&id=eq.<uid>
//
// — at these rates, per second, after single sign-ins:
//
//     23:14:47  80    23:14:48  107   23:14:49  279   23:14:50  170
//     23:17:04  149   23:17:05  825   23:17:08  317   23:17:12  462
//     22:58:04  799   23:00:14  530   23:06:52  583
//
// Six sign-ins that evening, every one of them followed by hundreds of identical profile reads a
// second. `auth_logs` over the same window: ZERO 5xx. The backend was fine. The client was
// asking one question several hundred times a second until PostgREST stopped keeping up, and the
// fifteen-second deadline in AuthController then rendered that as "The Nivora server is not
// responding right now."
//
// The loop is three reasonable things composed:
//   1. gotrue's `onAuthStateChange` is a ReplaySubject with an unbounded buffer
//      (gotrue_client.dart:94, 2.27.2) — every new subscriber gets the whole history first;
//   2. AuthController resubscribes on every rebuild (`ref.onDispose` nulls `_sub`);
//   3. the `signedIn` arm called `ref.invalidateSelf()`.
//
// These tests pin the rule that breaks it, and the two other honesty failures on the same path:
// a dead session blocking the sign-in before it is sent, and a 400 being reported as an outage.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/auth/auth_controller.dart';
import 'package:mobile/core/auth/auth_endpoint.dart';
import 'package:mobile/core/auth/session.dart';
import 'package:mobile/data/models/failure.dart';
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

void main() {
  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE RULE, WITH NO CLIENT AND NO NETWORK IN IT.
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('a replayed auth event is not a new fact', () {
    AuthEventAction act(
      AuthChangeEvent event, {
      String? eventToken,
      String? resolvedToken,
      bool holdsSession = true,
      bool installingSelf = false,
      bool signedOutByDeadToken = false,
    }) =>
        actionForAuthEvent(
          event: event,
          eventToken: eventToken,
          resolvedToken: resolvedToken,
          holdsSession: holdsSession,
          installingSelf: installingSelf,
          signedOutByDeadToken: signedOutByDeadToken,
        );

    test('THE LOOP: a signedIn for the session already resolved does not ask for a rebuild', () {
      // This single arm is the 825-reads-per-second. The replay hands back the same event, with
      // the same access token, on every resubscribe; answering it with invalidateSelf closes the
      // circuit.
      expect(
        act(AuthChangeEvent.signedIn, eventToken: 'tok-a', resolvedToken: 'tok-a'),
        AuthEventAction.ignore,
      );
    });

    test('a signedIn carrying a DIFFERENT token is a real sign-in and is resolved', () {
      // The fix must not be "stop listening". A second person signing in on the same handset
      // mints a new access token, and that has to reach the router.
      expect(
        act(AuthChangeEvent.signedIn, eventToken: 'tok-b', resolvedToken: 'tok-a'),
        AuthEventAction.reresolve,
      );
    });

    test('a first-ever signedIn, with nothing resolved yet, is resolved', () {
      expect(
        act(AuthChangeEvent.signedIn, eventToken: 'tok-a', resolvedToken: null),
        AuthEventAction.reresolve,
      );
    });

    test('the session signIn/verifyMfa is installing is not resolved twice', () {
      // setSession emits `signedIn` before it returns and the stream delivers to the listener
      // BEFORE the awaiting caller resumes, so this arm and the caller's own _resolve() were
      // two concurrent profile reads for one sign-in, racing to publish the phase.
      expect(
        act(AuthChangeEvent.signedIn, eventToken: 'tok-b', resolvedToken: 'tok-a',
            installingSelf: true),
        AuthEventAction.ignore,
      );
    });

    test('a signedOut that arrives while a session is HELD is history, not a sign-out', () {
      // gotrue calls _removeSession() before it emits — on the user's own tap
      // (gotrue_client.dart:1086) and on a dead refresh token (:1626) alike — so a genuine
      // sign-out never arrives with a session still in hand. One that does is the replay buffer
      // talking about a session that has since been replaced, and acting on it republished
      // AuthSignedOut over a live session: the router throwing a signed-in user back to the
      // login form, hundreds of times a second. That is what "it blocking me all the time"
      // looks like from the outside.
      expect(act(AuthChangeEvent.signedOut, holdsSession: true), AuthEventAction.ignore);
    });

    test('a real signedOut still reaches the router', () {
      // The fix must not make the app unable to sign anybody out.
      expect(
        act(AuthChangeEvent.signedOut, holdsSession: false),
        AuthEventAction.republishSignedOut,
      );
    });

    test('userUpdated for the same token is ignored, for a new token is resolved', () {
      expect(
        act(AuthChangeEvent.userUpdated, eventToken: 'tok-a', resolvedToken: 'tok-a'),
        AuthEventAction.ignore,
      );
      expect(
        act(AuthChangeEvent.userUpdated, eventToken: 'tok-b', resolvedToken: 'tok-a'),
        AuthEventAction.reresolve,
      );
    });

    test('a successful token refresh is normally nothing, and is the apology when owed', () {
      expect(act(AuthChangeEvent.tokenRefreshed), AuthEventAction.ignore);
      expect(
        act(AuthChangeEvent.tokenRefreshed, signedOutByDeadToken: true),
        AuthEventAction.reresolve,
      );
    });

    test('no event can ask for a rebuild twice in a row for the same session', () {
      // The property the loop violated, stated directly: once a token has been resolved, no
      // number of repeats of the same event can produce more work.
      const token = 'tok-a';
      for (final event in [
        AuthChangeEvent.signedIn,
        AuthChangeEvent.userUpdated,
        AuthChangeEvent.tokenRefreshed,
      ]) {
        for (var i = 0; i < 50; i++) {
          expect(
            act(event, eventToken: token, resolvedToken: token),
            AuthEventAction.ignore,
            reason: '$event replayed ${i + 1} times must stay a no-op',
          );
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE SAME THING, OVER A WIRE A TEST CAN COUNT.
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('one sign-in, one profile read', () {
    late List<String> requests;
    late SupabaseClient client;

    /// The row `_resolve` reads. A manager who still owes a password change — chudham20's shape,
    /// which is the account the owner could not get into.
    Map<String, Object?> managerRow() => {
          'id': 'user-1',
          'role': 'manager',
          'full_name': 'Manager',
          'email': 'manager@example.com',
          'phone': null,
          'hostel_id': 'hostel-1',
          'status': 'active',
          'must_change_password': true,
          'email_verified_at': null,
        };

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
          if (path.endsWith('/rest/v1/users')) return json([managerRow()]);
          if (path.endsWith('/auth/v1/logout')) return http.Response('', 204, request: request);
          return json({'ok': true});
        }),
      );
      addTearDown(client.dispose);
    });

    int profileReads() =>
        requests.where((r) => r == 'GET /rest/v1/users').length;

    ProviderContainer containerWith(MobileAuthEndpoint endpoint) {
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => _Auth(client)),
        mobileAuthEndpointProvider.overrideWith((ref) => endpoint),
      ]);
      addTearDown(container.dispose);
      // THE LISTENER IS LOAD-BEARING, not scaffolding. Riverpod rebuilds an invalidated provider
      // eagerly only while something is listening to it, and in the app something always is —
      // the router's refresh listenable. Without this the tests below would `read` a provider
      // that invalidates lazily and would never see the loop at all.
      container.listen(authControllerProvider, (_, _) {});
      return container;
    }

    /// An endpoint that grants a session whose access token is a real, unexpired JWT — which
    /// `setSession` requires, because it decodes `exp` before it will install anything.
    MobileAuthEndpoint granting({List<String>? invokedWhileHolding, SupabaseClient? watch}) =>
        MobileAuthEndpoint((name, {body}) async {
          invokedWhileHolding?.add(
            watch?.auth.currentSession == null ? 'clean' : 'holding-a-session',
          );
          return FunctionResponse(status: 200, data: {
            'ok': true,
            'data': {
              'accessToken': fakeJwt(expiresAt: DateTime.now().add(const Duration(hours: 1))),
              'refreshToken': 'refresh-2',
            },
          });
        });

    test('a successful sign-in reads the profile ONCE', () async {
      final container = containerWith(granting());
      await container.read(authControllerProvider.future);
      final before = profileReads();

      final message =
          await container.read(authControllerProvider.notifier).signIn(
                identifier: 'manager@example.com',
                password: 'pw',
              );
      // Let every microtask and every replayed event settle. Under the loop this window was
      // enough for hundreds of reads.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(message, isNull, reason: 'the sign-in was granted');
      expect(profileReads() - before, 1,
          reason: 'ONE resolve per sign-in. Two is the race; more is the loop.');
    });

    test('the manager reaches the change-password phase, not a blank screen', () async {
      // chudham20@gmail.com end to end: manager, must_change_password = TRUE, no factor. The
      // phase the router turns into /change-password.
      final container = containerWith(granting());
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).signIn(
            identifier: 'manager@example.com',
            password: 'pw',
          );

      final phase = container.read(authControllerProvider).value;
      expect(phase, isA<AuthSignedIn>());
      final session = (phase as AuthSignedIn).session;
      expect(session.role, UserRole.manager);
      expect(session.needsPasswordChange, isTrue);
    });

    test('rebuilding after a sign-in does not replay its way into another read', () async {
      // The loop's actual shape: a rebuild resubscribes, the ReplaySubject hands back the whole
      // history, and the `signedIn` in it asks for another rebuild. Invalidating by hand is that
      // first hop, made deliberately.
      final container = containerWith(granting());
      await container.read(authControllerProvider.future);
      await container.read(authControllerProvider.notifier).signIn(
            identifier: 'manager@example.com',
            password: 'pw',
          );
      final settled = profileReads();

      container.invalidate(authControllerProvider);
      await container.read(authControllerProvider.future);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // One read for the rebuild that was asked for, and nothing the replay added on top.
      expect(profileReads() - settled, 1);
    });

    test('the sign-in is not sent while this handset still holds a session', () async {
      // `functions.invoke` opens with `await _getAccessToken()` (supabase auth_http_client.dart:
      // 24), which refreshes an expired session before sending. When the stored refresh token is
      // one the server has forgotten that throws 400 `refresh_token_not_found` and the sign-in
      // never leaves the phone — which is why the auth log for the reported window holds two of
      // those 400s and no `mobile-auth` invocation beside them.
      final seen = <String>[];
      final container = containerWith(granting(invokedWhileHolding: seen, watch: client));
      await container.read(authControllerProvider.future);
      await installLiveSession(client, subject: 'user-1');

      await container.read(authControllerProvider.notifier).signIn(
            identifier: 'manager@example.com',
            password: 'pw',
          );

      expect(seen, ['clean'],
          reason: 'a sign-in is a fresh start; the old session must be gone before it is sent');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE SECOND FACTOR, WHICH IS WHAT THE OWNER WAS ACTUALLY DOING WHEN IT FAILED.
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('sign in, then a code', () {
    /// A real JWT, because `setSession` decodes `exp` and `getAuthenticatorAssuranceLevel`
    /// decodes `aal` — an opaque string would quietly land in the wrong arm of both.
    String jwt(String aal) {
      String seg(Map<String, Object?> c) =>
          base64Url.encode(utf8.encode(jsonEncode(c))).replaceAll('=', '');
      return '${seg(const {'alg': 'HS256', 'typ': 'JWT'})}.'
          '${seg({
            'sub': 'user-1',
            'role': 'authenticated',
            'aal': aal,
            'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          })}.not-a-real-signature';
    }

    const factorId = '3f2c6907-733f-401b-b100-b8bc1d31d105';

    late List<String> requests;
    late SupabaseClient client;
    late List<Object?> factors;

    setUp(() {
      requests = [];
      factors = [
        const {
          'id': factorId,
          'friendly_name': 'NIVORA',
          'factor_type': 'totp',
          'status': 'verified',
          'created_at': '2026-08-23T00:00:00.000Z',
          'updated_at': '2026-08-23T00:00:00.000Z',
        },
      ];
      client = SupabaseClient(
        'https://stub.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          requests.add('${request.method} $path');
          http.Response json(Object? body) => http.Response(
                jsonEncode(body),
                200,
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
              'factors': factors,
            });
          }
          if (path.endsWith('/rest/v1/users')) {
            return json([
              {
                'id': 'user-1',
                'role': 'owner',
                'full_name': 'Owner',
                'email': 'owner@example.com',
                'phone': null,
                'hostel_id': 'hostel-1',
                'status': 'active',
                'must_change_password': false,
                'email_verified_at': '2026-08-01T00:00:00.000Z',
              }
            ]);
          }
          if (path.endsWith('/auth/v1/logout')) return http.Response('', 204, request: request);
          return json({'ok': true});
        }),
      );
      addTearDown(client.dispose);
    });

    /// One endpoint standing in for both actions: sign-in hands back an aal1 session, the code
    /// hands back the aal2 one, exactly as `mobile-auth` does.
    MobileAuthEndpoint stepUp() => MobileAuthEndpoint((name, {body}) async {
          final action = (body as Map)['action'];
          return FunctionResponse(status: 200, data: {
            'ok': true,
            'data': {
              'accessToken': jwt(action == 'mfa' ? 'aal2' : 'aal1'),
              'refreshToken': action == 'mfa' ? 'refresh-aal2' : 'refresh-aal1',
            },
          });
        });

    ProviderContainer container() {
      final c = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => _Auth(client)),
        mobileAuthEndpointProvider.overrideWith((ref) => stepUp()),
      ]);
      addTearDown(c.dispose);
      c.listen(authControllerProvider, (_, _) {});
      return c;
    }

    test('password then code: two phases, and one profile read for each', () async {
      final c = container();
      await c.read(authControllerProvider.future);
      requests.clear();

      await c.read(authControllerProvider.notifier).signIn(
            identifier: 'owner@example.com',
            password: 'pw',
          );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final owed = c.read(authControllerProvider).value;
      expect(owed, isA<AuthNeedsMfa>());
      expect((owed! as AuthNeedsMfa).factorId, factorId);
      expect(requests.where((r) => r == 'GET /rest/v1/users').length, 1);

      requests.clear();
      final message = await c.read(authControllerProvider.notifier).verifyMfa(
            factorId: factorId,
            code: '123456',
          );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(message, isNull);
      expect(c.read(authControllerProvider).value, isA<AuthSignedIn>());
      expect(requests.where((r) => r == 'GET /rest/v1/users').length, 1,
          reason: 'verifying a code must read the profile once, not once per replayed event');
      // One /auth/v1/user, from setSession installing the stepped-up session. Nothing else.
      expect(requests.where((r) => r == 'GET /auth/v1/user').length, 1);
    });

    test('asking whether a privileged account has a factor does not spend its refresh token',
        () async {
      // gotrue's `mfa.listFactors()` opens with an unconditional `refreshSession()`
      // (gotrue_mfa_api.dart:176) — a POST /token?grant_type=refresh_token that ROTATES the
      // stored token, on the cold-start path, to answer a question about factors. When the
      // stored token has already been retired — which is what enrolling a factor does, since
      // verifying one logs out every other session — that comes back
      // 400 `refresh_token_not_found` and gotrue drops the session outright. A lookup must not
      // be able to end the session it is asking about.
      factors = const []; // this token's user object lists none: the branch that goes to the wire
      final c = container();
      await c.read(authControllerProvider.future);

      await c.read(authControllerProvider.notifier).signIn(
            identifier: 'owner@example.com',
            password: 'pw',
          );
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Privileged, aal1, no factor anywhere: enrolment is owed, and that is a routing decision
      // rather than a refusal.
      expect(c.read(authControllerProvider).value, isA<AuthNeedsMfaEnrolment>());
      expect(requests.where((r) => r.contains('/auth/v1/token')), isEmpty,
          reason: 'the factor lookup must be a GET /user, never a refresh-token grant');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  // THE SENTENCE.
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('a 400 on the refresh token is not an outage', () {
    late SupabaseClient client;

    setUp(() {
      client = SupabaseClient(
        'https://stub.supabase.co',
        'anon-key',
        httpClient: MockClient(
          (request) async => http.Response('{}', 200,
              request: request, headers: const {'content-type': 'application/json'}),
        ),
      );
      addTearDown(client.dispose);
    });

    Future<String?> signInThrowing(Object error) async {
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => _Auth(client)),
        mobileAuthEndpointProvider.overrideWith(
          (ref) => MobileAuthEndpoint((name, {body}) async => throw error),
        ),
      ]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      return container
          .read(authControllerProvider.notifier)
          .signIn(identifier: 'a@example.com', password: 'pw');
    }

    test('a revoked refresh token says the session ended, not that the server is down', () async {
      // The exact exception gotrue raises for the log line this work started from:
      //   400 Invalid Refresh Token: Refresh Token Not Found
      // `MobileAuthEndpoint` deliberately does not catch AuthException, so it arrives in
      // AuthController exactly like this.
      final message = await signInThrowing(const AuthApiException(
        'Invalid Refresh Token: Refresh Token Not Found',
        statusCode: '400',
        code: 'refresh_token_not_found',
      ));

      expect(message, isNotNull);
      expect(message!.toLowerCase(), isNot(contains('not responding')),
          reason: 'the server answered — with a 400. It is not an outage.');
      expect(message.toLowerCase(), contains('sign in again'),
          reason: 'the one thing that fixes an ended session');
      // And it must not be reported as a credential problem either.
      expect(message.toLowerCase(), isNot(contains('password is not right')));
    });

    test('every code that means the refresh token is finished gets that same answer', () {
      // The set failure.dart already knows about. Pinned here so this path cannot drift away
      // from the classifier the rest of the app uses.
      for (final code in [
        'refresh_token_not_found',
        'refresh_token_already_used',
        'session_expired',
        'session_not_found',
      ]) {
        final failure = AppFailure.from(AuthApiException('x', statusCode: '400', code: code));
        expect(failure, isA<SessionExpiredFailure>(), reason: code);
      }
    });

    test('a refresh that could not REACH the server is still reported as reachability', () async {
      // The opposite mistake. AuthRetryableFetchException means nobody answered, and calling
      // that an expired session would throw a working account out over a dropped packet.
      final message = await signInThrowing(
        AuthRetryableFetchException(message: 'Failed host lookup: stub.supabase.co'),
      );

      expect(message, isNotNull);
      expect(message!.toLowerCase(), contains('connection'));
      expect(message.toLowerCase(), isNot(contains('sign in again')));
    });

    test('a genuine deadline keeps the sentence that is true for it', () async {
      // "The server is not responding" is reserved, not abolished. A deadline this client set
      // and reached is exactly what it describes, and [restoreWithin] is the arm that still says
      // it — asserted here so the reservation is a pair of facts rather than a deletion.
      final phase = await restoreWithin(
        () => Future<AuthPhase>.delayed(const Duration(seconds: 5), () => const AuthSignedOut()),
        deadline: const Duration(milliseconds: 20),
      );

      expect(phase, isA<AuthSignedOut>());
      expect((phase as AuthSignedOut).message, serverNotResponding);
    });

    test('a second factor whose first-factor session died sends the user back to sign in',
        () async {
      // The MFA screen has nothing to offer somebody whose session ended — retyping the code
      // cannot work. Publish the signed-out phase so the router moves them, AND return the
      // sentence, so that a frame in which the router has not acted yet is never a cleared field
      // with nothing on it.
      final container = ProviderContainer(overrides: [
        authControllerProvider.overrideWith(() => _Auth(client)),
        mobileAuthEndpointProvider.overrideWith(
          (ref) => MobileAuthEndpoint((name, {body}) async => throw const AuthApiException(
                'Invalid Refresh Token: Refresh Token Not Found',
                statusCode: '400',
                code: 'refresh_token_not_found',
              )),
        ),
      ]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      final message = await container.read(authControllerProvider.notifier).verifyMfa(
            factorId: '11111111-2222-3333-4444-555555555555',
            code: '123456',
          );

      final phase = container.read(authControllerProvider).value;
      expect(phase, isA<AuthSignedOut>());
      expect((phase as AuthSignedOut).message, isNotNull);
      expect(phase.message!.toLowerCase(), contains('sign in again'));
      expect(message, phase.message);
      expect(message!.toLowerCase(), isNot(contains('not responding')));
    });
  });
}
