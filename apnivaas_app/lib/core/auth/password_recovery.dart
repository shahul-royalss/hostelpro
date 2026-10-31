/// A reset-password link was opened on this phone (round 5).
///
/// "Forgot password" emails a link back to the app. gotrue exchanges its code for a short
/// session and emits `AuthChangeEvent.passwordRecovery`; until 2026-10-31 nothing listened for
/// that, so the link opened the app on an empty sign-in screen with no way to set the password.
/// [AuthController] now turns the event into [PasswordRecovery.begin], and the router holds the
/// app on the "Set a new password" screen until [PasswordRecovery.end].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final passwordRecoveryProvider =
    NotifierProvider<PasswordRecovery, bool>(PasswordRecovery.new);

class PasswordRecovery extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() => state = true;

  void end() => state = false;
}

/// What sign-in says after a reset finished; drawn as good news, not as a refusal.
const passwordChangedMessage = 'Your password is changed. Sign in with your new password.';

/// The sentence for a link that could not be exchanged.
const deadRecoveryLinkMessage = 'That reset link has expired, was already used, or was opened '
    'on a different phone. Ask for a new one with "Forgot password".';

/// True for an error that comes from exchanging a reset link, never from a token refresh:
/// an expired or reused link, or one opened where the request was not made (the PKCE verifier
/// lives on the phone that asked).
bool isDeadRecoveryLink(Object error) {
  if (error is! AuthException) return false;
  const codes = {
    'flow_state_not_found',
    'flow_state_expired',
    'bad_code_verifier',
    'otp_expired',
    'bad_oauth_callback',
  };
  if (codes.contains(error.code)) return true;
  return error.message.toLowerCase().contains('code verifier');
}

/// What finishing a recovery came to: a sentence to show, and whether the account's second
/// factor is needed before the password can change.
typedef RecoveryOutcome = ({String? error, bool needsCode});
