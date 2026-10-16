library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/env.dart';

/// "Continue with Google": the half that talks to Google, and nothing more.
///
/// ═══ WHAT IT IS, ON ANDROID ═══
///
/// google_sign_in 7 is Credential Manager: Google's own account sheet, drawn by the system. No
/// browser and no web view, which is the rule this app is held to ("nothing has to go to the
/// browser"). It yields an ID token: a statement, signed by Google, that whoever holds this phone
/// controls a Google account whose email address Google has verified. Nothing else is asked for —
/// no scopes, no contacts, no Drive.
///
/// ═══ WHAT IT DELIBERATELY DOES NOT DO ═══
///
/// It does not hand the token to GoTrue (`signInWithIdToken`). The token goes to the mobile-auth
/// Edge Function, the endpoint the password already goes to, so a Google sign-in spends the same
/// per-address budget, lands in the same audit trail, and is refused for staff with a sentence
/// rather than a database error. See supabase/functions/mobile-auth/index.ts, section GOOGLE, and
/// db/migrations/2026-10-17-google-sign-in.sql for the guard GoTrue's public paths still meet.
///
/// ═══ THE NONCE ═══
///
/// A fresh random value per app launch. Google is handed sha256(raw) and writes it into the
/// token; the server is handed raw, and both it and GoTrue check that the pair matches, which ties
/// the token to a request this app made. Per launch rather than per tap only because google_sign_in
/// takes the nonce in initialize(), and initialize() may be called once per process.

/// What asking Google produced.
sealed class GoogleTokenOutcome {
  const GoogleTokenOutcome();
}

final class GoogleTokenIssued extends GoogleTokenOutcome {
  const GoogleTokenIssued({required this.idToken, required this.rawNonce});

  final String idToken;

  /// The value whose sha256 is inside [idToken]. The server needs both.
  final String rawNonce;
}

/// The person closed the sheet, or there was nothing to restore quietly. Rendered as nothing.
///
/// Also what Credential Manager reports for some misconfigurations (a wrong SHA-1, a Web client
/// ID from another project): google_sign_in_android's README says the plugin cannot tell those
/// apart from a real cancel. docs/google-sign-in.md lists them, because the screen cannot.
final class GoogleTokenCancelled extends GoogleTokenOutcome {
  const GoogleTokenCancelled();
}

final class GoogleTokenFailed extends GoogleTokenOutcome {
  const GoogleTokenFailed(this.message);

  final String message;
}

/// The seam the controller and the sign-in screen use. Faked in tests.
abstract interface class GoogleIdTokenSource {
  /// False when this build carries no Web client ID; the button is then not drawn at all.
  bool get isAvailable;

  /// The account sheet, because the person tapped "Continue with Google".
  Future<GoogleTokenOutcome> request();

  /// A returning user, with as little UI as Google allows. [GoogleTokenCancelled] when there is
  /// nothing to restore — never an error a person did not ask to see.
  Future<GoogleTokenOutcome> requestQuietly();

  /// Forget the Google account on this phone, so the next sign-in screen does not quietly sign it
  /// straight back in. Called on sign-out and after a refusal.
  Future<void> forget();
}

/// The sentences. Each says what to do next, and none blames a password.
abstract final class GoogleSignInWords {
  static const notSetUp =
      "Google sign-in isn't set up in this version of the app. Sign in with your phone number "
      'or email and password.';

  static const notOnThisPhone =
      "Google sign-in isn't available on this phone. Sign in with your phone number or email "
      'and password.';

  static const tryAgain = "Google sign-in didn't finish. Please try again.";
}

/// sha256 of [raw] as lowercase hex — the form GoTrue compares against the token's `nonce`.
String hashNonce(String raw) => sha256.convert(utf8.encode(raw)).toString();

/// 32 random bytes, base64url without padding.
String newRawNonce([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => source.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

class GoogleSignInTokenSource implements GoogleIdTokenSource {
  GoogleSignInTokenSource({required this.serverClientId, GoogleSignIn? plugin, String? rawNonce})
      : _plugin = plugin ?? GoogleSignIn.instance,
        _rawNonce = rawNonce ?? newRawNonce();

  /// The Web client ID. On Android the token's audience is this, not the Android client.
  final String serverClientId;
  final GoogleSignIn _plugin;
  final String _rawNonce;
  Future<void>? _ready;

  @override
  bool get isAvailable => serverClientId.isNotEmpty;

  /// Once per process, memoised: google_sign_in documents a second initialize() as undefined
  /// behaviour. A failed initialize is not memoised, so the next tap can try again.
  Future<void> _initialize() {
    return _ready ??= _plugin
        .initialize(serverClientId: serverClientId, nonce: hashNonce(_rawNonce))
        .catchError((Object e) {
      _ready = null;
      throw e;
    });
  }

  @override
  Future<GoogleTokenOutcome> request() => _ask(quietly: false);

  @override
  Future<GoogleTokenOutcome> requestQuietly() => _ask(quietly: true);

  Future<GoogleTokenOutcome> _ask({required bool quietly}) async {
    try {
      await _initialize();
      final GoogleSignInAccount? account;
      if (quietly) {
        account = await _plugin.attemptLightweightAuthentication();
      } else {
        if (!_plugin.supportsAuthenticate()) {
          return const GoogleTokenFailed(GoogleSignInWords.notOnThisPhone);
        }
        account = await _plugin.authenticate();
      }
      if (account == null) return const GoogleTokenCancelled();

      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        return quietly ? const GoogleTokenCancelled() : const GoogleTokenFailed(GoogleSignInWords.tryAgain);
      }
      return GoogleTokenIssued(idToken: idToken, rawNonce: _rawNonce);
    } on GoogleSignInException catch (e) {
      // debugPrint is stripped from release builds; the description is for whoever is debugging.
      debugPrint('Google sign-in: ${e.code} ${e.description}');
      if (quietly) return const GoogleTokenCancelled();
      return switch (e.code) {
        GoogleSignInExceptionCode.canceled => const GoogleTokenCancelled(),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          const GoogleTokenFailed(GoogleSignInWords.notSetUp),
        _ => const GoogleTokenFailed(GoogleSignInWords.tryAgain),
      };
    } catch (e) {
      debugPrint('Google sign-in failed: ${e.runtimeType} $e');
      return quietly ? const GoogleTokenCancelled() : const GoogleTokenFailed(GoogleSignInWords.tryAgain);
    }
  }

  @override
  Future<void> forget() async {
    try {
      await _initialize();
      await _plugin.signOut();
    } catch (e) {
      debugPrint('Google sign-out: ${e.runtimeType} $e');
    }
  }
}

/// A build with no Web client ID. Draws no button and asks Google for nothing.
class GoogleSignInNotConfigured implements GoogleIdTokenSource {
  const GoogleSignInNotConfigured();

  @override
  bool get isAvailable => false;

  @override
  Future<GoogleTokenOutcome> request() async => const GoogleTokenFailed(GoogleSignInWords.notSetUp);

  @override
  Future<GoogleTokenOutcome> requestQuietly() async => const GoogleTokenCancelled();

  @override
  Future<void> forget() async {}
}

final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>((ref) {
  const clientId = Env.googleWebClientId;
  return clientId.isEmpty
      ? const GoogleSignInNotConfigured()
      : GoogleSignInTokenSource(serverClientId: clientId);
});
