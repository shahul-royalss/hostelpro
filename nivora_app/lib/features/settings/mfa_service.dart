library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ═══════════════════════════════════════════════════════════════════════════════════════════
// TURNING TWO-FACTOR AUTHENTICATION ON, FROM THE PHONE
// ═══════════════════════════════════════════════════════════════════════════════════════════
//
// ── WHY THIS FILE EXISTS ─────────────────────────────────────────────────────────────────
//
// Until now the app could only VERIFY a factor that already existed: `grep -rni enroll lib`
// returned nothing, so `features/auth/mfa_screen.dart` was a door with no way to fit the lock.
// Across the whole platform exactly one factor had ever been enrolled — an owner's, on
// 2026-08-23 — because enrolment existed only in the web console.
//
// ── IT MIRRORS `lib/actions/mfa.ts`, DELIBERATELY ────────────────────────────────────────
//
// Both clients talk to the same GoTrue instance and the same `auth.mfa_factors` rows, so the
// two flows must not disagree about what a step means. Read alongside the web actions:
//
//   startTotpEnrollment   → MfaService.begin     clear stale unverified factors, then enroll
//   confirmTotpEnrollment → MfaService.confirm   challengeAndVerify → factor becomes verified
//   disableTotp           → MfaService.disable   challengeAndVerify (reauth), then unenroll
//   getMfaStatus          → MfaService.load      is there a verified TOTP factor
//
// THREE THINGS THE WEB ACTION DOES THAT THIS CANNOT, each noted again where it bites:
//
//  1. `rateLimit(...)` — the web limiter is a server-side counter reached through a server
//     action. A client-side copy would be a suggestion, not a limit. GoTrue's own per-factor
//     throttling is what actually holds here; its 429 becomes a sentence in `_failure`.
//  2. `audit('auth.mfa.enrolled' | 'auth.mfa.failed')` — `public.audit_log` is written from the
//     web app's server context. This client has no insert path to it, so enrolling from the
//     phone leaves NO audit row. Stated rather than papered over.
//  3. `required` (role ∈ `MFA_REQUIRED_ROLES`) — a Vercel environment variable read by
//     `lib/supabase/middleware.ts`. It is not in the database, so a phone cannot know it. This
//     file therefore never claims 2FA is mandatory for a role, and `MfaState` has no such
//     field. See the note beside the disable button in security_screen.dart.
//
// ── WHAT THE SERVER DOES *NOT* DO ────────────────────────────────────────────────────────
//
// Nothing in Postgres gates on assurance level: `db/rls-policies.sql` holds 65 `create policy`
// statements and not one of them mentions `aal`. Enrolling here genuinely protects the WEB
// session — the Next.js middleware bounces an aal1 session for a required role — and it makes
// every later sign-in on this app ask for a code. It does not, today, cause PostgREST to
// refuse anything to an aal1 token. This feature narrows that gap; it does not close it.

/// A TOTP enrolment that has been started but not yet confirmed.
///
/// The [secret] is the whole security value of this object. It lives in memory for the length of
/// one enrolment and is never written to a file, a log, or a provider that outlives the screen.
@immutable
class TotpEnrollment {
  const TotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.uri,
    this.qrSvg,
  });

  /// The unverified factor GoTrue just created. Confirming quotes it back.
  final String factorId;

  /// The base32 shared secret, for someone whose camera will not scan.
  final String secret;

  /// The `otpauth://` URI the QR encodes.
  final String uri;

  /// The QR as SVG markup, already unwrapped from GoTrue's data URI, or null when the server
  /// sent something this build cannot draw. Null is not a failure: the secret below it is a
  /// complete alternative, which is exactly why the secret is always on screen too.
  final String? qrSvg;
}

/// Whether this account has two-factor authentication switched on.
@immutable
class MfaState {
  const MfaState({required this.enrolled, this.factorId, this.addedOn});

  const MfaState.off()
      : enrolled = false,
        factorId = null,
        addedOn = null;

  /// True when a TOTP factor exists in the `verified` state.
  final bool enrolled;

  /// The verified factor, for the disable flow. Null when [enrolled] is false.
  final String? factorId;

  /// `auth.mfa_factors.created_at`, straight from the server. Real data, so it may be shown.
  final DateTime? addedOn;
}

/// A failure carrying a sentence a user can act on.
///
/// [retryable] separates "ask again" from "that will not work either", the same distinction the
/// data layer's `AppFailure` draws — kept here because MFA errors arrive as [AuthException] and
/// never pass through that layer.
@immutable
class MfaFailure implements Exception {
  const MfaFailure(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => 'MfaFailure($message)';
}

/// The seam the screen talks to, so a widget test can drive the flow without a Supabase client.
abstract class MfaService {
  /// Is a verified TOTP factor attached to this account?
  Future<MfaState> load();

  /// Create a new unverified factor and hand back what the user has to see.
  Future<TotpEnrollment> begin({String? friendlyName});

  /// Prove possession of the new factor. On success it becomes `verified`, this session is
  /// promoted to aal2, and GoTrue signs every OTHER session of this user out.
  Future<void> confirm({required String factorId, required String code});

  /// Turn 2FA off. Requires a currently valid code, so an unlocked phone someone else is
  /// holding cannot quietly undo the enrolment.
  Future<void> disable({required String factorId, required String code});
}

/// Unwraps the `qr_code` field GoTrue returns into SVG markup.
///
/// gotrue-dart hands back `data:image/svg+xml;utf-8,<svg …>` — it prepends that prefix itself in
/// `GoTrueMFAApi.enroll` — but the encoding is not guaranteed, and a percent-encoded or base64
/// body would draw as garbage rather than as a QR. Pure and total on purpose: it returns null
/// for anything it does not positively recognise, and the caller falls back to the typed key.
String? svgFromDataUri(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('<svg') || trimmed.startsWith('<?xml')) return trimmed;
  if (!trimmed.startsWith('data:')) return null;

  final comma = trimmed.indexOf(',');
  if (comma < 0) return null;
  final meta = trimmed.substring('data:'.length, comma).toLowerCase();
  if (!meta.contains('image/svg+xml')) return null;

  var body = trimmed.substring(comma + 1);
  if (meta.contains('base64')) {
    try {
      body = utf8.decode(base64.decode(body));
    } catch (_) {
      return null;
    }
  } else if (body.contains('%3C') || body.contains('%3c')) {
    try {
      body = Uri.decodeComponent(body);
    } catch (_) {
      return null;
    }
  }

  final markup = body.trim();
  return markup.startsWith('<svg') || markup.startsWith('<?xml') ? markup : null;
}

/// The real one, over supabase_flutter's MFA API.
class SupabaseMfaService implements MfaService {
  const SupabaseMfaService(this._auth);

  final GoTrueClient _auth;

  /// The same fifteen seconds `AuthController` gives a sign-in step, for the same reason its
  /// comment gives: Dart's HTTP client waits minutes on a connection that was accepted and
  /// never answered, and a spinner over a wedged backend is indistinguishable from a slow one.
  static const _networkTimeout = Duration(seconds: 15);

  @override
  Future<MfaState> load() async {
    try {
      final factors = await _auth.mfa.listFactors().timeout(_networkTimeout);
      // gotrue-dart already filters `totp` down to verified factors; supabase-js does not.
      // Filtering again costs nothing and makes this read the same either way. The mistake to
      // avoid is reporting "2FA is on" for a factor that was started and then abandoned.
      final verified = factors.totp
          .where((f) => f.factorType == FactorType.totp && f.status == FactorStatus.verified)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (verified.isEmpty) return const MfaState.off();
      final factor = verified.first;
      return MfaState(enrolled: true, factorId: factor.id, addedOn: factor.createdAt);
    } catch (e) {
      throw _failure(e, during: _Step.load);
    }
  }

  @override
  Future<TotpEnrollment> begin({String? friendlyName}) async {
    try {
      // The web action's first move, for the reason its comment gives: a user who backs out of
      // enrolment twice would otherwise leave two unverified factors behind, and GoTrue refuses
      // the next one with a friendly-name collision that reads like a bug in the app.
      final existing = await _auth.mfa.listFactors().timeout(_networkTimeout);
      for (final f in existing.all) {
        if (f.factorType == FactorType.totp && f.status != FactorStatus.verified) {
          await _auth.mfa.unenroll(f.id).timeout(_networkTimeout);
        }
      }

      // No `issuer:` argument, because the web action passes none either. Passing one here would
      // put a different label in the authenticator app depending on which client the person
      // happened to enrol from.
      final res = await _auth.mfa
          .enroll(factorType: FactorType.totp, friendlyName: friendlyName)
          .timeout(_networkTimeout);

      final totp = res.totp;
      if (totp == null) {
        // A non-TOTP factor came back for a TOTP request. There is nothing to show, and
        // guessing would mean drawing an empty QR next to an empty key.
        throw const MfaFailure('Nivora could not start the setup. Try again in a moment.');
      }

      // NOTHING HERE IS LOGGED. `debugPrint` is stripped in release, but a secret in a debug log
      // is still a secret sitting on a developer's machine, and gotrue's own doc-comment says to
      // avoid logging these three fields. The catch below logs the exception, never the payload.
      return TotpEnrollment(
        factorId: res.id,
        secret: totp.secret,
        uri: totp.uri,
        qrSvg: svgFromDataUri(totp.qrCode),
      );
    } catch (e) {
      throw _failure(e, during: _Step.begin);
    }
  }

  @override
  Future<void> confirm({required String factorId, required String code}) async {
    try {
      await _auth.mfa
          .challengeAndVerify(factorId: factorId, code: code)
          .timeout(_networkTimeout);
    } catch (e) {
      throw _failure(e, during: _Step.confirm);
    }
  }

  @override
  Future<void> disable({required String factorId, required String code}) async {
    try {
      // Reauthentication, exactly as `disableTotp` does it: the code is verified FIRST, and only
      // a session that has just proved possession may remove the factor. GoTrue also requires
      // aal2 to unenroll a verified factor, so this order is the one that works as well as the
      // one that is right.
      await _auth.mfa
          .challengeAndVerify(factorId: factorId, code: code)
          .timeout(_networkTimeout);
      await _auth.mfa.unenroll(factorId).timeout(_networkTimeout);
    } catch (e) {
      throw _failure(e, during: _Step.disable);
    }
  }
}

enum _Step { load, begin, confirm, disable }

/// Turns whatever came back into one sentence and a verdict on retrying.
///
/// The wrong-code wording differs from `AuthController._friendly`'s on purpose. At sign-in the
/// person has had this app working for weeks and a rejected code is nearly always a clock or a
/// typo. During enrolment the usual cause is a code read off the authenticator BEFORE the scan
/// finished, so the sentence says which code to use.
MfaFailure _failure(Object e, {required _Step during}) {
  if (e is MfaFailure) return e;

  if (e is TimeoutException) {
    return const MfaFailure(
      'The Nivora server did not answer. Check your connection and try again.',
    );
  }

  if (e is AuthException) {
    final m = e.message.toLowerCase();
    final status = e.statusCode;

    if (m.contains('invalid totp') ||
        m.contains('invalid code') ||
        m.contains('invalid mfa') ||
        m.contains('totp code') ||
        status == '422') {
      return MfaFailure(
        during == _Step.disable
            ? 'That code is not right. Codes change every 30 seconds — enter the one showing now.'
            : 'That code is not right. Use the code your authenticator app is showing NOW. '
                'Codes change every 30 seconds, and a phone clock that is a minute out will be '
                'refused every time.',
      );
    }
    if (m.contains('rate') || m.contains('too many') || status == '429') {
      return const MfaFailure(
        'Too many attempts. Wait a minute, then use the code showing at that point.',
        retryable: false,
      );
    }
    // Checked AFTER the code cases, never before: GoTrue answers a wrong TOTP with a 401 on
    // some versions, and reading that as "you are signed out" would throw a user off a screen
    // they are still entitled to be on. This branch needs the message to say so.
    if (m.contains('session missing') ||
        m.contains('jwt expired') ||
        m.contains('invalid jwt') ||
        m.contains('not authenticated')) {
      return const MfaFailure(
        'Your session has expired. Close this and sign in again.',
        retryable: false,
      );
    }
    if (m.contains('already exists') || m.contains('friendly name')) {
      return const MfaFailure(
        'A setup is already half-finished on this account. Close this and open it again.',
      );
    }
    if (m.contains('aal2') || m.contains('assurance')) {
      return const MfaFailure(
        'Nivora needs a fresh code before it can change this. Enter the current one.',
      );
    }
    if (m.contains('not found') || status == '404') {
      return const MfaFailure(
        'That authenticator is no longer on this account. Close this and open it again.',
        retryable: false,
      );
    }
    if (m.contains('network') || m.contains('failed host lookup')) {
      return const MfaFailure('Cannot reach Nivora. Check your connection and try again.');
    }
    if (const {'502', '503', '504', '522'}.contains(status)) {
      return const MfaFailure(
        'The Nivora server is not responding right now. Please try again in a few minutes.',
      );
    }
    // Whoever is debugging needs the real one; the user gets a sentence. Codes and secrets never
    // travel in an AuthException message, so this cannot leak one.
    debugPrint('mfa $during failed: ${e.runtimeType} status=$status ${e.message}');
    return const MfaFailure('Nivora could not complete that. Please try again.');
  }

  debugPrint('mfa $during failed (transport): ${e.runtimeType} $e');
  final m = e.toString().toLowerCase();
  if (m.contains('failed host lookup') ||
      m.contains('no address associated') ||
      m.contains('network is unreachable')) {
    return const MfaFailure('Cannot reach Nivora. Check your connection and try again.');
  }
  return const MfaFailure(
    'The Nivora server is not responding right now. Please try again in a few minutes.',
  );
}

/// The live service. Lazy, so a widget test that overrides it never touches [Supabase.instance]
/// — which throws when the app has not been initialised, i.e. in every test.
final mfaServiceProvider = Provider<MfaService>(
  (ref) => SupabaseMfaService(Supabase.instance.client.auth),
);

/// Whether 2FA is on for the signed-in account.
///
/// autoDispose so the answer is re-read each time the security screen is opened rather than held
/// for the life of the app. This is the one screen where a stale "off" would be read as "my
/// enrolment did not stick", and sent someone round the setup a second time.
final mfaStateProvider = FutureProvider.autoDispose<MfaState>(
  (ref) => ref.watch(mfaServiceProvider).load(),
);
