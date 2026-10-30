import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/auth/auth_endpoint.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// R4.4: one automatic retry for a transient blip, never for a real answer.
void main() {
  const granted = FunctionResponse(
    status: 200,
    data: {
      'data': {'accessToken': 'a', 'refreshToken': 'r'},
    },
  );

  ({MobileAuthEndpoint endpoint, List<int> calls}) scripted(List<Object> script,
      {Duration timeout = authEndpointTimeout}) {
    final calls = <int>[];
    final endpoint = MobileAuthEndpoint(
      (name, {body}) async {
        final step = script[calls.length.clamp(0, script.length - 1)];
        calls.add(calls.length);
        if (step is FunctionException) throw step;
        if (step is Completer<FunctionResponse>) return step.future;
        return step as FunctionResponse;
      },
      timeout: timeout,
      retryDelay: const Duration(milliseconds: 10),
    );
    return (endpoint: endpoint, calls: calls);
  }

  Future<AuthVerdict> signIn(MobileAuthEndpoint e) =>
      e.signIn(loginEmail: 'r@example.com', password: 'pw');

  test('the first attempt waits 20 seconds and the retry about 1 second', () {
    expect(authEndpointTimeout, const Duration(seconds: 20));
    expect(authRetryDelay, const Duration(seconds: 1));
  });

  test('a 503 with no server message is retried once, and the retry can succeed', () async {
    final s = scripted([const FunctionsHttpException(status: 503, details: null), granted]);
    expect(await signIn(s.endpoint), isA<AuthGranted>());
    expect(s.calls, hasLength(2));
  });

  test('a 503 twice is retried only once, then shown as unavailable', () async {
    final s = scripted([const FunctionsHttpException(status: 503, details: null)]);
    final v = await signIn(s.endpoint);
    expect(v, isA<AuthUnavailable>());
    expect((v as AuthUnavailable).message, MobileAuthEndpoint.signInUnavailable);
    expect(s.calls, hasLength(2));
  });

  test('a 400 is never retried', () async {
    final s = scripted([
      const FunctionsHttpException(
          status: 400, details: {'ok': false, 'error': 'Incorrect email/phone or password.'}),
      granted,
    ]);
    expect(await signIn(s.endpoint), isA<AuthRejected>());
    expect(s.calls, hasLength(1));
  });

  test('a 429 is never retried', () async {
    final s = scripted([
      const FunctionsHttpException(status: 429, details: {'retryAfterSeconds': 60}),
      granted,
    ]);
    expect(await signIn(s.endpoint), isA<AuthThrottled>());
    expect(s.calls, hasLength(1));
  });

  test('a 5xx that carries the server\'s own sentence is not retried', () async {
    final s = scripted([
      const FunctionsHttpException(status: 503, details: {'ok': false, 'error': 'Down for upkeep.'}),
      granted,
    ]);
    expect(await signIn(s.endpoint), isA<AuthUnavailable>());
    expect(s.calls, hasLength(1));
  });

  test('a fetch failure and a 408 are retried', () async {
    final a = scripted([const FunctionsFetchException(), granted]);
    expect(await signIn(a.endpoint), isA<AuthGranted>());
    final b = scripted([const FunctionsHttpException(status: 408, details: null), granted]);
    expect(await signIn(b.endpoint), isA<AuthGranted>());
    expect(b.calls, hasLength(2));
  });

  test('a timeout is retried', () async {
    final s = scripted([Completer<FunctionResponse>(), granted],
        timeout: const Duration(milliseconds: 20));
    expect(await signIn(s.endpoint), isA<AuthGranted>());
    expect(s.calls, hasLength(2));
  });

  test('a one-time code is not resent after a 5xx it may have reached', () async {
    final s = scripted([const FunctionsHttpException(status: 500, details: null), granted]);
    expect(await s.endpoint.verifyMfa(factorId: 'f', code: '123456'), isA<AuthUnavailable>());
    expect(s.calls, hasLength(1));
  });
}
