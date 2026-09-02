library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The client half of `supabase/functions/mobile-auth`.
///
/// ═══ WHY THIS FILE EXISTS ═══
///
/// This app used to check credentials by calling GoTrue itself —
/// `supabase.auth.signInWithPassword()`, which is a plain POST to
/// `/auth/v1/token?grant_type=password`. An audit measured that path twice: TWELVE consecutive
/// wrong-password attempts against a real account all came back 400 `invalid_credentials`, with
/// no 429, no lockout, and observed back-off DECREASING between attempts (1.37s → 0.53s).
/// Nothing on that path wrote to `public.audit_log` either, so `app.detect_suspicious_activity()`
/// — which raises an alert at five failures in fifteen minutes — could not see an attack that
/// was in progress. The web app has been throttled since day one because a browser talks to a
/// server action that holds the limiter; the phone had no server between it and GoTrue.
///
/// Everything here therefore goes through ONE endpoint that spends a durable Postgres counter
/// before a password is ever checked, keyed by identifier AND by IP, and writes the failure to
/// the audit trail either way.
///
/// ═══ THE THING THIS FILE DELIBERATELY DOES NOT DO ═══
///
/// It does not fall back to GoTrue when the Edge Function is unreachable. A fallback would be a
/// bypass switch with a public trigger: anyone able to make one function invocation fail — and
/// the endpoint is reachable by anyone holding the anon key, which ships inside the APK — would
/// get the unthrottled path back. So a function that cannot be reached produces
/// [AuthUnavailable] and sign-in stops, in the same fail-closed spirit as
/// `_shared/ratelimit.ts`. What the user is told ("this is not a problem with your password")
/// is the honest version of that, and it is a different sentence from a rejected credential.
///
/// ═══ NO CLIENT-SIDE DELAY, ANYWHERE ═══
///
/// There is no local attempt counter and no artificial wait in this file, on purpose. Neither
/// would be a control: the endpoint is public, and anything this app can decline to send, a
/// script written against the same public endpoint simply sends. The only counter that means
/// anything is the one in Postgres, on the other side of the network. This file's whole job is
/// to ASK for that verdict and then render it honestly.

/// The deployed function's slug. One endpoint, two actions.
const mobileAuthFunction = 'mobile-auth';

const _actionSignIn = 'signin';
const _actionMfa = 'mfa';

/// What the server decided. Four outcomes, because they want four different sentences.
///
/// The split that matters most is [AuthRejected] versus [AuthThrottled]: "that password is
/// wrong" and "you have run out of attempts" are opposite instructions to the person holding
/// the phone. Collapsing them — which is what a single `String?` return did before — sends
/// somebody off to reset a password that was never the problem.
sealed class AuthVerdict {
  const AuthVerdict();
}

/// The credential was accepted. Carries the tokens the function minted, and nothing else.
final class AuthGranted extends AuthVerdict {
  const AuthGranted({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// The server checked and said no.
///
/// The message is deliberately the same one for "no such account" and "wrong password". This
/// app's population is young residents whose PHONE NUMBER is their login id, so a message that
/// told the two apart would let anyone confirm which numbers live in which PG. The server
/// enforces that (it returns one sentence for both); this class just never invents a
/// distinction the server refused to make.
final class AuthRejected extends AuthVerdict {
  const AuthRejected(this.message);

  final String message;
}

/// The limiter tripped. NOT a verdict on the credential — it was never checked.
///
/// [retryAfter] is the server's own figure, taken from the response body rather than guessed
/// here, so the countdown a user is shown is the same window the database is actually holding.
final class AuthThrottled extends AuthVerdict {
  const AuthThrottled(this.message, this.retryAfter);

  final String message;
  final Duration retryAfter;

  /// Whether this refusal leaks anything about the account.
  ///
  /// It must not, and the reason is the whole point of throttling by IP as well as by
  /// identifier: a 429 that only ever appeared for accounts that exist would be a slower
  /// enumeration oracle rather than a fix. The server keys the counter on a HASH of whatever
  /// was typed and spends it before any lookup, so an address that belongs to nobody trips the
  /// limiter exactly as readily as a real one. Asserted in the tests.
  bool get revealsWhetherAccountExists => false;
}

/// We could not get an answer. Never render this as a credential problem.
final class AuthUnavailable extends AuthVerdict {
  const AuthUnavailable(this.message);

  final String message;
}

/// Signature of `SupabaseClient.functions.invoke`, narrowed to what this file uses.
///
/// Injected rather than reached for through the singleton so the decode below can be driven by
/// a test with no network and no initialised Supabase — the limiter tripping, the wording
/// differing from a rejection, and the recovery afterwards are all behaviours of THIS code,
/// and a test that cannot reach them is a test of nothing.
typedef FunctionInvoker = Future<FunctionResponse> Function(
  String name, {
  Object? body,
});

/// How long one call to the endpoint may take before the app stops waiting.
///
/// The same fifteen seconds [AuthController] already allowed each sign-in step, and for the
/// same reason: Dart's HTTP client has no default request timeout, so a backend that completes
/// the TLS handshake and then answers nothing leaves the button spinning for minutes. Kept
/// here rather than inherited so this class is complete on its own.
const authEndpointTimeout = Duration(seconds: 15);

class MobileAuthEndpoint {
  const MobileAuthEndpoint(this._invoke, {this.timeout = authEndpointTimeout});

  /// The real thing, bound to the app's one Supabase client.
  ///
  /// `functions.invoke` attaches the Authorization header itself, from the live session when
  /// there is one and from the anon key when there is not. That is exactly right for both
  /// actions: sign-in is called signed out and the anon key satisfies the gateway's `verify_jwt`
  /// while gating nothing (the limiter is the gate), and MFA is called with the caller's own
  /// aal1 token, which is what the function verifies to decide whose factor is being challenged.
  factory MobileAuthEndpoint.of(SupabaseClient db) => MobileAuthEndpoint(
        (name, {body}) => db.functions.invoke(name, body: body),
      );

  final FunctionInvoker _invoke;
  final Duration timeout;

  /// [loginEmail] must ALREADY be resolved by `resolveLoginEmail` — the caller passes the
  /// address, not the raw typed string.
  ///
  /// That is not laziness. The phone→address mapping exists twice already (Dart
  /// `resolveLoginEmail`, TypeScript `resolveLoginEmail`) and the two must stay byte-identical
  /// or the same resident cannot sign in on both clients. A third copy inside the Edge Function
  /// would not fail loudly if it drifted: it would map a real person onto an address that does
  /// not exist and answer "incorrect password" forever. It also keeps the limiter key stable —
  /// "+91 98765 43210" and "9876543210" have already collapsed to one address by the time they
  /// arrive, so they cannot buy two budgets.
  Future<AuthVerdict> signIn({
    required String loginEmail,
    required String password,
  }) =>
      _call(
        {'action': _actionSignIn, 'identifier': loginEmail, 'password': password},
        unavailable: signInUnavailable,
      );

  /// A six-digit TOTP is a 10^6 space on a thirty-second rotation; unthrottled, a script walks a
  /// meaningful fraction of it inside one window. The server allows six per ten minutes per
  /// account — the same number the web app uses — and counts by IP as well.
  Future<AuthVerdict> verifyMfa({
    required String factorId,
    required String code,
  }) =>
      _call(
        {'action': _actionMfa, 'factorId': factorId, 'code': code},
        unavailable: mfaUnavailable,
      );

  Future<AuthVerdict> _call(
    Map<String, Object?> body, {
    required String unavailable,
  }) async {
    try {
      final response = await _invoke(mobileAuthFunction, body: body).timeout(timeout);
      final granted = _grantFrom(response.data);
      // A 2xx with no tokens in it is a client/server shape disagreement, not a credential
      // verdict. Saying "wrong password" here would blame the user for our own bug.
      return granted ?? AuthUnavailable(unavailable);
    } on FunctionsHttpException catch (e) {
      return verdictFor(e.status, e.details, unavailable: unavailable);
    } on FunctionException catch (e) {
      // FunctionsFetchException (the request never left) and FunctionsRelayException (the
      // platform edge failed before our code ran). Both are "we could not ask the question".
      return AuthUnavailable(e.status == 0 ? unreachable : unavailable);
    } on TimeoutException {
      return AuthUnavailable(unavailable);
    }
    // AuthException is deliberately NOT caught: `functions.invoke` refreshes an expiring session
    // before sending, and when that refresh fails the right answer is "sign in again", which is
    // the caller's existing handling. Swallowing it here would turn an ended session into a
    // vague outage message.
  }

  static AuthGranted? _grantFrom(Object? data) {
    if (data is! Map) return null;
    final payload = data['data'];
    if (payload is! Map) return null;
    final access = payload['accessToken'];
    final refresh = payload['refreshToken'];
    if (access is! String || access.isEmpty) return null;
    if (refresh is! String || refresh.isEmpty) return null;
    return AuthGranted(accessToken: access, refreshToken: refresh);
  }

  /// Turns one HTTP status and one response body into one of the four verdicts.
  ///
  /// Public, and static, because this mapping IS the behaviour worth testing — that a 429 does
  /// not become "wrong password", that a 503 does not either, and that neither of them says
  /// anything about whether the account exists.
  static AuthVerdict verdictFor(
    int status,
    Object? details, {
    required String unavailable,
  }) {
    final serverMessage = _messageFrom(details);

    if (status == 429) {
      final wait = _retryAfterFrom(details);
      // The server's own sentence is preferred so the wording exists in ONE place and the
      // countdown it quotes is the window the database is really holding. The fallback is for a
      // 429 raised by something in front of our function, which has no NIVORA wording to offer.
      return AuthThrottled(serverMessage ?? throttleMessage(wait), wait);
    }

    // 5xx, a fetch failure (0), a gateway timeout, and a 404 from a function that is not there
    // are all the same fact: nobody checked the credential. This must never be worded as a
    // rejection — during the CAPTCHA outage this project is currently in, every password grant
    // fails this way, and telling those users their password is wrong would send every one of
    // them to reset a password that was never the problem.
    if (status == 0 || status == 404 || status == 408 || status >= 500) {
      return AuthUnavailable(serverMessage ?? unavailable);
    }

    if (status == 401) {
      // Not our envelope: the platform gateway refusing the bearer token before our code ran.
      return AuthRejected(serverMessage ?? sessionEnded);
    }

    // 400 and 403 — the function answered, and its message is already written for a person and
    // already refuses to distinguish "no such account" from "wrong password".
    return AuthRejected(serverMessage ?? genericRejection);
  }

  /// Pulls `error` out of the `{ ok: false, error: "..." }` envelope every NIVORA function
  /// returns. Length-capped: this string goes straight onto a screen, and a bounded quote of
  /// our own server is fine while an unbounded one is a layout bug waiting for a bad day.
  static String? _messageFrom(Object? details) {
    if (details is! Map) return null;
    final error = details['error'];
    if (error is! String) return null;
    final trimmed = error.trim();
    if (trimmed.isEmpty || trimmed.length > 240) return null;
    return trimmed;
  }

  static Duration _retryAfterFrom(Object? details) {
    final raw = details is Map ? details['retryAfterSeconds'] : null;
    final seconds = raw is num ? raw.round() : 0;
    // Never show "wait 0 seconds", and never trust a server figure so large it reads as a
    // permanent lockout — the longest window this system actually holds is fifteen minutes.
    if (seconds <= 0) return const Duration(minutes: 1);
    return Duration(seconds: seconds.clamp(1, 3600));
  }

  /// The sentence a throttle gets when the server offered none.
  static String throttleMessage(Duration wait) {
    final minutes = (wait.inSeconds / 60).ceil();
    return 'Too many attempts. Please wait $minutes minute${minutes == 1 ? '' : 's'} '
        'and try again.';
  }

  // ── The wording. Every one of these is a DIFFERENT sentence from every other, which is the
  // whole contract this file has with the screens above it.

  static const genericRejection = 'Incorrect email/phone or password.';

  static const signInUnavailable =
      'Sign-in is temporarily unavailable. This is not a problem with your password. '
      'Please try again in a minute.';

  static const mfaUnavailable =
      'Verification is temporarily unavailable. Please try again in a minute.';

  static const unreachable =
      'Cannot reach Nivora. Check your connection and try again.';

  static const sessionEnded = 'Your session has ended. Sign in again to continue.';
}

/// The endpoint the auth controller uses. Overridable in tests.
final mobileAuthEndpointProvider = Provider<MobileAuthEndpoint>(
  (ref) => MobileAuthEndpoint.of(Supabase.instance.client),
);
