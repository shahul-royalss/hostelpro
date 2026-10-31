/// Which language this phone chose (round 5). Kept in one small file on the phone and nowhere
/// else: it is a preference about this handset, not a fact about the account, so a resident who
/// borrows a phone sees that phone's language, and the server never learns it.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'i18n.dart';

abstract interface class LanguageStorage {
  Future<AppLanguage?> read();
  Future<void> write(AppLanguage language);
}

final class FileLanguageStorage implements LanguageStorage {
  const FileLanguageStorage();

  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'app_language'));

  @override
  Future<AppLanguage?> read() async {
    try {
      final f = await _file();
      return f.existsSync() ? AppLanguage.tryParse((await f.readAsString()).trim()) : null;
    } catch (e) {
      // A phone whose storage cannot be read is not held behind a picker that could not save
      // the answer either: it runs in English, and Profile → Language still works.
      debugPrint('language read: ${e.runtimeType} $e');
      return AppLanguage.english;
    }
  }

  @override
  Future<void> write(AppLanguage language) async {
    try {
      final f = await _file();
      await f.create(recursive: true);
      await f.writeAsString(language.code, flush: true);
    } catch (e) {
      // Kept for this session either way; the choice is asked again on the next first launch.
      debugPrint('language write: ${e.runtimeType} $e');
    }
  }
}

final languageStorageProvider = Provider<LanguageStorage>((_) => const FileLanguageStorage());

/// Null until a language has been chosen on this phone: the first launch asks.
final languageProvider =
    AsyncNotifierProvider<LanguageController, AppLanguage?>(LanguageController.new);

class LanguageController extends AsyncNotifier<AppLanguage?> {
  @override
  Future<AppLanguage?> build() => ref.watch(languageStorageProvider).read();

  Future<void> choose(AppLanguage language) async {
    state = AsyncData(language);
    await ref.read(languageStorageProvider).write(language);
  }
}

/// The locale the app runs in: the choice, or English until there is one.
final appLocaleProvider = Provider<Locale>(
    (ref) => ref.watch(languageProvider).value?.locale ?? AppLanguage.english.locale);
