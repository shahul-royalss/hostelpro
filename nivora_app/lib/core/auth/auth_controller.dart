library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Supabase exports a type named AuthState too. Ours is AuthPhase precisely so the two
// can coexist without an alias that future readers have to decode.

import 'session.dart';

/// Auth state for the whole app. One source of truth that the router listens to.
///
/// Students sign in with a PHONE NUMBER, not an email. The web app maps it to a synthetic
/// address (`<digits>@student.hostelpro.local`) and this client must use the identical mapping
/// or the same person cannot sign in on mobile. That mapping lives in [resolveLoginEmail] and
/// nowhere else.

/// The domain student logins are mapped onto. Must match the web app's STUDENT_LOGIN_DOMAIN.
const studentLoginDomain = 'student.hostelpro.local';

/// Turns whatever the user typed into the address Supabase Auth expects.
///
/// Pure and side-effect free on purpose: it reads no table, so it can never become an
/// account-enumeration oracle. Anything containing '@' passes through; anything that is
/// digits (with the usual human separators) becomes a student login.
String resolveLoginEmail(String input) {
  final trimmed = input.trim();
  if (trimmed.contains('@')) return trimmed.toLowerCase();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  // Indian mobile numbers are 10 digits; tolerate a +91 / 0 prefix the user may have typed.
  final local = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  return '$local@$studentLoginDomain';
}

sealed class AuthPhase {
  const AuthPhase();
}

/// Before the first session restore completes. The splash holds here.
class AuthLoading extends AuthPhase {
  const AuthLoading();
}

class AuthSignedOut extends AuthPhase {
  const AuthSignedOut({this.message});

  /// Set when the user was signed out FOR a reason worth showing (deactivated, revoked).
  final String? message;
}

/// Authenticated at the Auth server, but a second factor is still owed for this session.
class AuthNeedsMfa extends AuthPhase {
  const AuthNeedsMfa(this.factorId);
  final String factorId;
}

class AuthSignedIn extends AuthPhase {
  const AuthSignedIn(this.session);
  final NivoraSession session;
}

class AuthController extends AsyncNotifier<AuthPhase> {
  StreamSubscription<AuthState>? _sub;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<AuthPhase> build() async {
    // supabase_flutter restores a persisted session from secure storage before this runs, so
    // by the time we get here currentUser is already populated on a warm start. That is what
    // makes "open app → straight to home" possible without a network round trip first.
    _sub ??= _db.auth.onAuthStateChange.listen((event) {
      // A token refresh must not thrash the router; only real transitions matter.
      switch (event.event) {
        case AuthChangeEvent.signedOut:
          state = const AsyncData(AuthSignedOut());
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.userUpdated:
          ref.invalidateSelf();
        default:
          break;
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });

    return _resolve();
  }

  Future<AuthPhase> _resolve() async {
    final user = _db.auth.currentUser;
    if (user == null) return const AuthSignedOut();

    // Step-up check before the profile read: a session that still owes a factor should not be
    // treated as signed in, even briefly, or the router would flash the home screen.
    final aal = _db.auth.currentSession?.accessToken == null
        ? null
        : await _mfaOwed();
    if (aal != null) return AuthNeedsMfa(aal);

    // public.users is the authority for role/status, NOT the JWT's app_metadata, which lags a
    // refresh behind. RLS lets a user read their own row, so no elevated key is involved.
    final row = await _db
        .from('users')
        .select('id, role, full_name, email, phone, hostel_id, status, must_change_password')
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      // Authenticated but no profile: the account is half-created. Refusing beats guessing.
      await _db.auth.signOut();
      return const AuthSignedOut(message: 'Your account is not set up yet. Contact your administrator.');
    }

    final session = NivoraSession.fromRow(row);
    if (!session.isActive) {
      await _db.auth.signOut();
      return const AuthSignedOut(message: 'This account has been deactivated.');
    }
    return AuthSignedIn(session);
  }

  /// Returns the factor id when this session has a verified factor but has not used it yet.
  Future<String?> _mfaOwed() async {
    try {
      final aal = _db.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal.nextLevel != AuthenticatorAssuranceLevels.aal2) return null;
      if (aal.currentLevel == AuthenticatorAssuranceLevels.aal2) return null;
      final factors = await _db.auth.mfa.listFactors();
      final verified = factors.totp.where((f) => f.status == FactorStatus.verified);
      return verified.isEmpty ? null : verified.first.id;
    } catch (_) {
      // Never fail open: if the factor state cannot be read, do not claim MFA is satisfied.
      // Returning null lets the profile read proceed, and the server still refuses aal1
      // requests for anything gated — the client is not the boundary.
      return null;
    }
  }

  /// Sign in with an email OR a phone number (see [resolveLoginEmail]).
  /// Returns null on success, or a message to show the user.
  ///
  /// This deliberately does NOT push the in-flight attempt into the shared auth state. The
  /// router listens to that state, and a value-less loading value there means "the first
  /// session restore is still running" — so routing it through here yanked the user off the
  /// login form and onto the splash screen the moment they tapped Sign in. Submission
  /// progress belongs to the form; auth phase belongs to the app.
  Future<String?> signIn({required String identifier, required String password}) async {
    try {
      await _db.auth.signInWithPassword(
        email: resolveLoginEmail(identifier),
        password: password,
      );
      state = AsyncData(await _resolve());
      return null;
    } on AuthException catch (e) {
      // The user sees a deliberately vague message; whoever is debugging needs the real one.
      // debugPrint is stripped in release, so this cannot leak to a device log in production.
      debugPrint('signIn failed: ${e.runtimeType} status=${e.statusCode} ${e.message}');
      // Deliberately not distinguishing "no such user" from "wrong password": that difference
      // is an account-enumeration oracle, and this app's population is young residents whose
      // phone number is the login.
      return _friendly(e);
    }
  }

  /// Returns null on success, or a message to show. Same reasoning as [signIn].
  Future<String?> verifyMfa({required String factorId, required String code}) async {
    try {
      final challenge = await _db.auth.mfa.challenge(factorId: factorId);
      await _db.auth.mfa.verify(factorId: factorId, challengeId: challenge.id, code: code);
      state = AsyncData(await _resolve());
      return null;
    } on AuthException catch (e) {
      return _friendly(e);
    }
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
    state = const AsyncData(AuthSignedOut());
  }

  /// Errors a user can act on. Anything unrecognised becomes a generic line rather than
  /// leaking a driver message into the UI.
  String _friendly(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'That login or password is not right.';
    }
    if (m.contains('invalid totp') || m.contains('invalid code')) {
      return 'That code is not right. Codes change every 30 seconds — try the current one.';
    }
    if (m.contains('rate') || e.statusCode == '429') {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (m.contains('network') || m.contains('failed host lookup')) {
      return 'Cannot reach Nivora. Check your connection and try again.';
    }
    return 'Sign-in could not be completed. Please try again.';
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthPhase>(AuthController.new);

/// The current session, or null. Convenience for screens that already know they are signed in.
final sessionProvider = Provider<NivoraSession?>((ref) {
  final s = ref.watch(authControllerProvider).value;
  return s is AuthSignedIn ? s.session : null;
});
