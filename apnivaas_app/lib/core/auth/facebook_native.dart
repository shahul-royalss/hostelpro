/// "Continue with Facebook", natively (round 5; the Facebook app is Published).
///
/// The Facebook APP signs the person in ([LoginBehavior.nativeOnly]): no browser and no web view,
/// which is this product's standing rule. The user access token it returns goes to mobile-auth's
/// `facebook` action, which checks it against this app with the Graph API and only then mints a
/// session (supabase/functions/_shared/identity.ts); nothing on the phone trusts it. Without the
/// Facebook app installed the person is told to install it or use another way in.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import 'social_sign_in.dart';

abstract final class FacebookWords {
  static const needsApp = 'Continue with Facebook needs the Facebook app on this phone. '
      'Install it, or sign in another way.';
  static const tryAgain = "Facebook sign-in didn't go through. Please try again.";
}

class FacebookNativeSource implements SocialCredentialSource {
  FacebookNativeSource({this.auth, bool? enabled})
      : _enabled = enabled ?? SocialSignInConfig.facebookEnabled;

  /// A test's stand-in; the plugin's own instance otherwise.
  final FacebookAuth? auth;
  final bool _enabled;

  FacebookAuth get _fb => auth ?? FacebookAuth.instance;

  @override
  bool get isAvailable => _enabled;

  @override
  Future<SocialCredentialOutcome> request() async {
    try {
      final result = await _fb.login(
        permissions: const ['public_profile', 'email'],
        loginBehavior: LoginBehavior.nativeOnly,
      );
      switch (result.status) {
        case LoginStatus.success:
          final token = result.accessToken?.tokenString ?? '';
          return token.isEmpty
              ? const SocialCredentialFailed(FacebookWords.tryAgain)
              : SocialCredentialIssued(token: token);
        case LoginStatus.cancelled:
        case LoginStatus.operationInProgress:
          return const SocialCredentialCancelled();
        case LoginStatus.failed:
          // The detail is for whoever is debugging; release builds strip debugPrint.
          debugPrint('Facebook sign-in failed: ${result.message}');
          return SocialCredentialFailed(failureWords(result.message));
      }
    } catch (e) {
      debugPrint('Facebook sign-in failed: ${e.runtimeType} $e');
      return SocialCredentialFailed(failureWords('$e'));
    }
  }

  /// The SDK's sentence for "the Facebook app is not there" varies by version; anything that
  /// names a missing app or an activity that could not start is that case.
  static String failureWords(String? message) {
    final m = (message ?? '').toLowerCase();
    const missing = ['not installed', 'could not be started', 'katana', 'no activity', 'native app'];
    return missing.any(m.contains) ? FacebookWords.needsApp : FacebookWords.tryAgain;
  }

  /// Forgets Facebook's session on this phone, after a sign-out, so the next "Continue with
  /// Facebook" asks again rather than signing the same person straight back in.
  Future<void> forget() async {
    try {
      await _fb.logOut();
    } catch (e) {
      debugPrint('Facebook log out: ${e.runtimeType} $e');
    }
  }
}
