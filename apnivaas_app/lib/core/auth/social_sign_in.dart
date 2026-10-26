/// Self sign-up personas and the two sign-in providers that have no SDK in this build.
///
/// docs/self-signup-onboarding-spec.md, Flows 1–2. Facebook and Truecaller are integration
/// POINTS: an interface shaped like [GoogleIdTokenSource], a NotConfigured implementation, and a
/// build flag that keeps each button hidden while it is empty. Neither native SDK is in this
/// build. When one lands, it implements the interface and replaces the provider below; nothing
/// else in the app changes.
///
/// No secret lives here. The flags are public client identifiers; the app secret and the
/// Truecaller exchange live in the `mobile-auth` Edge Function only.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who the person said they are on "Who are you?". A HINT for one sign-up request, never
/// authority: the server maps it to a role and the database refuses every other role for a
/// self-created account (docs/self-signup-api.md §1).
enum SignupPersona {
  owner('owner'),
  tenant('tenant'),

  /// Round 3: a staff APPLICANT (role student, no PG) until an owner accepts them.
  staff('staff');

  const SignupPersona(this.wire);

  /// The exact value `mobile-auth` accepts.
  final String wire;

  static SignupPersona? tryParse(String? raw) {
    for (final p in values) {
      if (p.wire == raw) return p;
    }
    return null;
  }
}

/// Build flags. Empty (the default) hides the button.
abstract final class SocialSignInConfig {
  static const facebookAppId = String.fromEnvironment('FACEBOOK_APP_ID');
  static const truecallerClientId = String.fromEnvironment('TRUECALLER_CLIENT_ID');

  static bool get facebookEnabled => facebookAppId.isNotEmpty;
  static bool get truecallerEnabled => truecallerClientId.isNotEmpty;
}

/// What a provider hands back. The same three outcomes as Google's.
sealed class SocialCredentialOutcome {
  const SocialCredentialOutcome();
}

/// A Facebook user access token, or a Truecaller authorization code plus PKCE verifier.
final class SocialCredentialIssued extends SocialCredentialOutcome {
  const SocialCredentialIssued({required this.token, this.codeVerifier});

  /// Facebook: the user access token. Truecaller: the authorization code.
  final String token;

  /// Truecaller only: the PKCE verifier the code was requested with.
  final String? codeVerifier;
}

/// The person closed the provider's sheet. Nothing to say.
final class SocialCredentialCancelled extends SocialCredentialOutcome {
  const SocialCredentialCancelled();
}

final class SocialCredentialFailed extends SocialCredentialOutcome {
  const SocialCredentialFailed(this.message);
  final String message;
}

/// One provider's on-device half. [isAvailable] decides whether its button is drawn at all.
abstract interface class SocialCredentialSource {
  bool get isAvailable;
  Future<SocialCredentialOutcome> request();
}

/// The contract's own sentences for an unconfigured provider (docs/self-signup-api.md §1.2–1.3).
abstract final class SocialSignInWords {
  static const facebookNotSetUp = 'Facebook sign-in is not set up yet';
  static const truecallerNotSetUp = 'Truecaller sign-in is not set up yet';
}

/// The only implementation this build has. Visible when the flag is set (so a staging build can
/// show the button and prove the server's 503 `not_configured` path), and it answers in the
/// contract's words without asking anyone anything.
class SocialSignInNotConfigured implements SocialCredentialSource {
  const SocialSignInNotConfigured({required this.enabledByFlag, required this.message});

  final bool enabledByFlag;
  final String message;

  @override
  bool get isAvailable => enabledByFlag;

  @override
  Future<SocialCredentialOutcome> request() async => SocialCredentialFailed(message);
}

final facebookCredentialSourceProvider = Provider<SocialCredentialSource>(
  (ref) => SocialSignInNotConfigured(
    enabledByFlag: SocialSignInConfig.facebookEnabled,
    message: SocialSignInWords.facebookNotSetUp,
  ),
);

final truecallerCredentialSourceProvider = Provider<SocialCredentialSource>(
  (ref) => SocialSignInNotConfigured(
    enabledByFlag: SocialSignInConfig.truecallerEnabled,
    message: SocialSignInWords.truecallerNotSetUp,
  ),
);
