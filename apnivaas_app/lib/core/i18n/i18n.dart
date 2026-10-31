/// THE APP'S LANGUAGES (round 5): English, Hindi, Telugu, Tamil, Malayalam and Kannada.
///
/// HOW TEXT IS TRANSLATED. English is the key: a table per language maps an English sentence
/// to its translation, and [translate] looks it up. The clay kit's widgets (section headers,
/// rows, tiles, tabs, buttons, notes, headers) pass their text through [Tr.tr], so a screen
/// built from the kit speaks the chosen language wherever a translation exists, and English
/// wherever one does not yet — never a blank, never a key.
///
/// A key may carry placeholders, `{name}`: "Pay {amount} now". A sentence that matches one is
/// translated with the captured parts put back (each part is itself looked up, so a month name
/// is translated too). English costs nothing: it returns before any lookup.
library;

import 'package:flutter/widgets.dart';

import 'strings_hi.dart';
import 'strings_kn.dart';
import 'strings_ml.dart';
import 'strings_ta.dart';
import 'strings_te.dart';

enum AppLanguage {
  english('en', 'English', 'English'),
  hindi('hi', 'हिन्दी', 'Hindi'),
  telugu('te', 'తెలుగు', 'Telugu'),
  tamil('ta', 'தமிழ்', 'Tamil'),
  malayalam('ml', 'മലയാളം', 'Malayalam'),
  kannada('kn', 'ಕನ್ನಡ', 'Kannada');

  const AppLanguage(this.code, this.nativeName, this.englishName);

  /// The ISO 639-1 code: the [Locale] the app runs in.
  final String code;

  /// The language's name in its own script, as the picker shows it.
  final String nativeName;
  final String englishName;

  Locale get locale => Locale(code);

  static AppLanguage? tryParse(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

/// Every locale the app declares to Flutter, so Material's own words (OK, Cancel, the date
/// picker) follow the choice too.
final supportedAppLocales = [for (final l in AppLanguage.values) l.locale];

const _tables = <String, Map<String, String>>{
  'hi': hindiStrings,
  'te': teluguStrings,
  'ta': tamilStrings,
  'ml': malayalamStrings,
  'kn': kannadaStrings,
};

/// One compiled `{placeholder}` key: its regular expression and the names in order.
final class _Template {
  _Template(this.key)
      : names = [for (final m in _slot.allMatches(key)) m.group(1)!],
        pattern = RegExp('^${key.split(_slot).map(RegExp.escape).join('(.+?)')}\$');

  static final _slot = RegExp(r'\{(\w+)\}');
  final String key;
  final List<String> names;
  final RegExp pattern;
}

const _figureSlots = {'count', 'n', 'amount', 'value', 'room', 'bed', 'free', 'sharing'};
final _digit = RegExp(r'[0-9]');

final _templates = <String, List<_Template>>{};
final _cache = <String, Map<String, String>>{};

/// [english] in the language [code], with `{name}` slots filled from [args].
String translate(String english, String code, [Map<String, String>? args]) {
  var out = english;
  if (code != 'en') {
    final table = _tables[code];
    if (table != null) out = _lookup(english, code, table);
  }
  if (args != null) {
    for (final e in args.entries) {
      out = out.replaceAll('{${e.key}}', e.value);
    }
  }
  return out;
}

String _lookup(String english, String code, Map<String, String> table) {
  final cache = _cache.putIfAbsent(code, () => {});
  final hit = cache[english];
  if (hit != null) return hit;
  var out = table[english];
  if (out == null) {
    final templates = _templates.putIfAbsent(
        code, () => [for (final k in table.keys) if (k.contains('{')) _Template(k)]);
    for (final t in templates) {
      final m = t.pattern.firstMatch(english);
      if (m == null) continue;
      // A figure slot must hold a figure, so "Tap to open" never reads as "{count} open".
      var fits = true;
      for (var i = 0; i < t.names.length; i++) {
        if (_figureSlots.contains(t.names[i]) && !_digit.hasMatch(m.group(i + 1)!)) fits = false;
      }
      if (!fits) continue;
      var s = table[t.key]!;
      for (var i = 0; i < t.names.length; i++) {
        final part = m.group(i + 1)!;
        s = s.replaceAll('{${t.names[i]}}', _lookup(part, code, table));
      }
      out = s;
      break;
    }
  }
  out ??= english;
  // Bounded: the app's sentences are finite, but a sentence carrying a live figure is not.
  if (cache.length < 4000) cache[english] = out;
  return out;
}

extension Tr on BuildContext {
  /// [english] in the app's language, or as written while there is no translation for it.
  String tr(String english, [Map<String, String>? args]) =>
      translate(english, Localizations.maybeLocaleOf(this)?.languageCode ?? 'en', args);
}
