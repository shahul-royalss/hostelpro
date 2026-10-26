/// The persona picked on "Who are you?", remembered on this phone until the account exists,
/// then forgotten (docs/self-signup-onboarding-spec.md, Flow 1).
///
/// A HINT, NEVER AUTHORITY. It decides which words Create your account shows and is sent once,
/// with the sign-up request; the server maps it to a role and the database refuses any other.
/// Nothing after sign-up reads it: routing goes by the role on the profile row.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/auth/social_sign_in.dart';

/// Where the hint is kept. A file, like the onboarding marker; a test swaps in memory.
abstract interface class PersonaStorage {
  Future<SignupPersona?> read();
  Future<void> write(SignupPersona? persona);
}

final class FilePersonaStorage implements PersonaStorage {
  const FilePersonaStorage();

  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'signup_persona'));

  @override
  Future<SignupPersona?> read() async {
    try {
      final f = await _file();
      return f.existsSync() ? SignupPersona.tryParse((await f.readAsString()).trim()) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SignupPersona? persona) async {
    try {
      final f = await _file();
      if (persona == null) {
        if (f.existsSync()) await f.delete();
      } else {
        await f.create(recursive: true);
        await f.writeAsString(persona.wire, flush: true);
      }
    } catch (e) {
      debugPrint('persona hint not saved: $e');
    }
  }
}

final class MemoryPersonaStorage implements PersonaStorage {
  SignupPersona? value;
  @override
  Future<SignupPersona?> read() async => value;
  @override
  Future<void> write(SignupPersona? persona) async => value = persona;
}

final personaStorageProvider = Provider<PersonaStorage>((_) => const FilePersonaStorage());

/// The picked persona, or null. Kept alive for the app's lifetime (not autoDispose) so a
/// callback that outlives its screen can still clear it after sign-up.
final pendingPersonaProvider =
    NotifierProvider<PendingPersona, SignupPersona?>(PendingPersona.new);

class PendingPersona extends Notifier<SignupPersona?> {
  bool _touched = false;

  @override
  SignupPersona? build() {
    final storage = ref.watch(personaStorageProvider);
    storage.read().then((saved) {
      // A pick made while the file was being read wins over what the file said.
      if (!_touched && ref.mounted) state = saved;
    });
    return null;
  }

  void pick(SignupPersona persona) {
    _touched = true;
    state = persona;
    ref.read(personaStorageProvider).write(persona);
  }

  /// The account exists now: forget the hint.
  void clear() {
    _touched = true;
    state = null;
    ref.read(personaStorageProvider).write(null);
  }
}
