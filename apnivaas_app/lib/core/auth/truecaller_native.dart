/// "Continue with Truecaller" (round 6), through the Truecaller app's own consent sheet.
///
/// No browser and no web view: Truecaller's OAuth SDK draws its sheet over this app and hands
/// back an AUTHORIZATION CODE. The code and the PKCE verifier it was asked with go to the
/// `mobile-auth` Edge Function, which exchanges them with Truecaller and reads the verified
/// number (docs/self-signup-api.md §1.3). This app never holds a Truecaller access token, and
/// the `state` it sets is checked on the way back so a stale or foreign answer is refused.
///
/// Only Truecaller users can use it (OPTION_VERIFY_ONLY_TC_USERS): anyone else is told to
/// install the app or use another way, never sent to a missed-call or OTP flow.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:truecaller_sdk/truecaller_sdk.dart';

import 'social_sign_in.dart';

abstract final class TruecallerWords {
  static const needsApp =
      'Install the Truecaller app and sign in to it, then try again — or use another way.';
  static const tryAgain = 'Truecaller could not sign you in. Try again, or use another way.';
}

/// The OAuth error codes that mean "the person chose not to", not "it broke": back pressed (2),
/// back pressed mid-way (13), and the footer's "use another method" (14).
const _cancelCodes = {2, 13, 14};

class TruecallerNativeSource implements SocialCredentialSource {
  TruecallerNativeSource({bool? enabled})
      : _enabled = enabled ?? SocialSignInConfig.truecallerEnabled;

  final bool _enabled;

  @override
  bool get isAvailable => _enabled;

  static String _state() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  @override
  Future<SocialCredentialOutcome> request() async {
    if (!_enabled) return const SocialCredentialFailed(SocialSignInWords.truecallerNotSetUp);
    try {
      await TcSdk.initializeSDK(
        sdkOption: TcSdkOptions.OPTION_VERIFY_ONLY_TC_USERS,
        consentHeadingOption: TcSdkOptions.SDK_CONSENT_HEADING_CONTINUE_WITH,
        footerType: TcSdkOptions.FOOTER_TYPE_ANOTHER_METHOD,
        ctaText: TcSdkOptions.CTA_TEXT_CONTINUE,
      );
      if (await TcSdk.isOAuthFlowUsable != true) {
        return const SocialCredentialFailed(TruecallerWords.needsApp);
      }
      final state = _state();
      await TcSdk.setOAuthState(state);
      await TcSdk.setOAuthScopes(const ['profile', 'phone', 'openid']);
      final verifier = await TcSdk.generateRandomCodeVerifier;
      if (verifier is! String || verifier.isEmpty) {
        return const SocialCredentialFailed(TruecallerWords.tryAgain);
      }
      final challenge = await TcSdk.generateCodeChallenge(verifier);
      if (challenge is! String || challenge.isEmpty) {
        return const SocialCredentialFailed(TruecallerWords.tryAgain);
      }
      await TcSdk.setCodeChallenge(challenge);

      // Listen BEFORE asking: the stream is a broadcast and does not replay.
      final answer = TcSdk.streamCallbackData.first.timeout(const Duration(minutes: 3));
      await TcSdk.getAuthorizationCode;
      final callback = await answer;
      switch (callback.result) {
        case TcSdkCallbackResult.success:
          final data = callback.tcOAuthData;
          if (data == null || data.state != state || data.authorizationCode.isEmpty) {
            return const SocialCredentialFailed(TruecallerWords.tryAgain);
          }
          return SocialCredentialIssued(token: data.authorizationCode, codeVerifier: verifier);
        case TcSdkCallbackResult.failure:
          final code = callback.error?.code;
          if (_cancelCodes.contains(code)) return const SocialCredentialCancelled();
          debugPrint('truecaller: failure $code');
          return const SocialCredentialFailed(TruecallerWords.tryAgain);
        default:
          return const SocialCredentialFailed(TruecallerWords.needsApp);
      }
    } on TimeoutException {
      return const SocialCredentialFailed(TruecallerWords.tryAgain);
    } on MissingPluginException {
      return const SocialCredentialFailed(SocialSignInWords.truecallerNotSetUp);
    } on PlatformException catch (e) {
      debugPrint('truecaller: ${e.code}');
      return const SocialCredentialFailed(TruecallerWords.tryAgain);
    }
  }
}
