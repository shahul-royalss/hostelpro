/// BIOMETRIC APP LOCK (round 3, R3): fingerprint, face or the phone's PIN, on this phone only.
///
/// * On by default for owners, optional for everyone else (a switch in Security).
/// * Asks when the app opens with a saved session, and when it comes back after more than
///   [appLockBackgroundGrace] in the background. A fresh sign-in has just proved who it is, so
///   it does not ask again.
/// * Local only: the preference is a file on this phone and nothing biometric leaves it.
///
/// PRESENTATION, NOT AUTHORIZATION: the session's rights are the server's business. This keeps
/// a borrowed, unlocked phone from opening someone's PG.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'auth_controller.dart';
import 'session.dart';

/// Longer than this in the background and the lock asks again.
const appLockBackgroundGrace = Duration(seconds: 60);

/// The default before the person has chosen: on for owners only.
bool appLockDefaultFor(UserRole role) => role == UserRole.owner;

// ── The device half ─────────────────────────────────────────────────────────────────────────

enum UnlockResult { unlocked, failed, unavailable }

abstract interface class BiometricAuthenticator {
  /// Whether the phone has a screen lock (biometric or PIN) the lock can use.
  Future<bool> isSupported();

  Future<UnlockResult> authenticate(String reason);
}

final class LocalAuthAuthenticator implements BiometricAuthenticator {
  LocalAuthAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('app lock support check failed: $e');
      return false;
    }
  }

  @override
  Future<UnlockResult> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? UnlockResult.unlocked : UnlockResult.failed;
    } on LocalAuthException catch (e) {
      debugPrint('app lock: ${e.code.name}');
      return switch (e.code) {
        // No screen lock or no hardware: the lock cannot work, so it must not lock anyone out.
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware =>
          UnlockResult.unavailable,
        _ => UnlockResult.failed,
      };
    } catch (e) {
      debugPrint('app lock failed: $e');
      return UnlockResult.failed;
    }
  }
}

final biometricAuthenticatorProvider =
    Provider<BiometricAuthenticator>((_) => LocalAuthAuthenticator());

// ── The preference ──────────────────────────────────────────────────────────────────────────

/// Per account on this phone: `{userId: bool}`. Absent means "the default for the role".
abstract interface class AppLockPrefsStorage {
  Future<Map<String, bool>> read();
  Future<void> write(Map<String, bool> prefs);
}

final class FileAppLockPrefsStorage implements AppLockPrefsStorage {
  const FileAppLockPrefsStorage();

  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'app_lock.json'));

  @override
  Future<Map<String, bool>> read() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return {};
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (e.key is String && e.value is bool) e.key as String: e.value as bool,
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> write(Map<String, bool> prefs) async {
    try {
      final f = await _file();
      await f.create(recursive: true);
      await f.writeAsString(jsonEncode(prefs), flush: true);
    } catch (e) {
      debugPrint('app lock preference not saved: $e');
    }
  }
}

final class MemoryAppLockPrefsStorage implements AppLockPrefsStorage {
  MemoryAppLockPrefsStorage([Map<String, bool>? initial]) : value = {...?initial};
  Map<String, bool> value;
  @override
  Future<Map<String, bool>> read() async => {...value};
  @override
  Future<void> write(Map<String, bool> prefs) async => value = {...prefs};
}

final appLockPrefsStorageProvider =
    Provider<AppLockPrefsStorage>((_) => const FileAppLockPrefsStorage());

// ── The state ───────────────────────────────────────────────────────────────────────────────

@immutable
class AppLockState {
  const AppLockState({
    this.locked = false,
    this.prefs = const {},
    this.prefsLoaded = false,
    this.prompting = false,
    this.message,
  });

  final bool locked;
  final Map<String, bool> prefs;
  final bool prefsLoaded;

  /// The system prompt is up; lifecycle changes it causes are ignored.
  final bool prompting;

  /// Why the last attempt did not unlock, or null.
  final String? message;

  bool enabledFor(ApnivaasSession session) =>
      prefs[session.userId] ?? appLockDefaultFor(session.role);

  AppLockState copyWith({
    bool? locked,
    Map<String, bool>? prefs,
    bool? prefsLoaded,
    bool? prompting,
    String? message,
    bool clearMessage = false,
  }) =>
      AppLockState(
        locked: locked ?? this.locked,
        prefs: prefs ?? this.prefs,
        prefsLoaded: prefsLoaded ?? this.prefsLoaded,
        prompting: prompting ?? this.prompting,
        message: clearMessage ? null : (message ?? this.message),
      );
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

class AppLockController extends Notifier<AppLockState> {
  /// True until the first session of this process has been seen.
  bool _coldStart = true;

  /// A restored session whose lock decision waits for the preference file.
  bool _lockWhenLoaded = false;

  DateTime? _hiddenAt;
  Completer<void>? _loaded;

  /// The clock, swappable in tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  static const reason = 'Unlock Apnivaas';
  static const failedWords = "That didn't unlock Apnivaas. Tap Unlock to try again.";

  @override
  AppLockState build() {
    _loaded = Completer<void>();
    ref.read(appLockPrefsStorageProvider).read().then((prefs) {
      if (!ref.mounted) return;
      state = state.copyWith(prefs: {...prefs, ...state.prefs}, prefsLoaded: true);
      _loaded?.complete();
      if (_lockWhenLoaded) {
        _lockWhenLoaded = false;
        _lockIfEnabled();
      }
    });
    ref.listen<AsyncValue<AuthPhase>>(authControllerProvider, (prev, next) {
      final phase = next.value;
      if (phase is AuthSignedIn) {
        final before = prev?.value;
        final restored = _coldStart && before is! AuthSignedOut && before is! AuthNeedsMfa;
        _coldStart = false;
        if (restored) {
          state.prefsLoaded ? _lockIfEnabled() : _lockWhenLoaded = true;
        }
      } else if (phase is AuthSignedOut) {
        _coldStart = false;
        _lockWhenLoaded = false;
        if (state.locked || state.message != null) {
          state = state.copyWith(locked: false, clearMessage: true);
        }
      }
    }, fireImmediately: true);
    return const AppLockState();
  }

  ApnivaasSession? get _session => switch (ref.read(authControllerProvider).value) {
        AuthSignedIn(:final session) => session,
        _ => null,
      };

  Future<void> _lockIfEnabled() async {
    final session = _session;
    if (session == null || !state.enabledFor(session)) return;
    if (!await ref.read(biometricAuthenticatorProvider).isSupported()) return;
    if (!ref.mounted) return;
    state = state.copyWith(locked: true, clearMessage: true);
  }

  /// Called by [AppLockGate] from the app's lifecycle.
  void onHidden() {
    if (state.prompting) return;
    _hiddenAt ??= now();
  }

  void onShown() {
    final since = _hiddenAt;
    _hiddenAt = null;
    if (state.prompting || since == null || state.locked) return;
    if (now().difference(since) > appLockBackgroundGrace) _lockIfEnabled();
  }

  /// Shows the system prompt. Unlocks on success, or when the phone has no lock to use.
  Future<void> unlock() async {
    if (!state.locked || state.prompting) return;
    state = state.copyWith(prompting: true, clearMessage: true);
    final result = await ref.read(biometricAuthenticatorProvider).authenticate(reason);
    if (!ref.mounted) return;
    _hiddenAt = null;
    state = switch (result) {
      UnlockResult.unlocked || UnlockResult.unavailable =>
        state.copyWith(locked: false, prompting: false, clearMessage: true),
      UnlockResult.failed => state.copyWith(prompting: false, message: failedWords),
    };
  }

  /// The Security switch. Turning it on asks once, so nobody enables a lock they cannot open.
  /// Returns the sentence to show, or null.
  Future<String?> setEnabled(bool enabled) async {
    final session = _session;
    if (session == null) return null;
    await _loaded?.future;
    if (enabled) {
      final device = ref.read(biometricAuthenticatorProvider);
      if (!await device.isSupported()) {
        return 'Set a screen lock (fingerprint, face or PIN) on your phone first.';
      }
      state = state.copyWith(prompting: true);
      final result = await device.authenticate('Turn on app lock');
      if (!ref.mounted) return null;
      state = state.copyWith(prompting: false);
      if (result != UnlockResult.unlocked) {
        return result == UnlockResult.unavailable
            ? 'Set a screen lock (fingerprint, face or PIN) on your phone first.'
            : 'App lock was not turned on.';
      }
    }
    final prefs = {...state.prefs, session.userId: enabled};
    state = state.copyWith(prefs: prefs);
    await ref.read(appLockPrefsStorageProvider).write(prefs);
    return null;
  }
}
