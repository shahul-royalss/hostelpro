// THE APP'S TYPEFACES, REGISTERED BEFORE ANY TEST RUNS.
//
// `flutter test` picks this file up for every test under test/ and runs [testExecutable] around
// each test file.
//
// ── WHY IT EXISTS ─────────────────────────────────────────────────────────────────────────
//
// A widget test does not load the fonts a pubspec declares. A style asking for 'Manrope' finds
// no such family and is laid out in the test binding's stand-in font, where every glyph is a
// square one em wide — "Try again" at 2.0x measures 246dp instead of 144. Every overflow
// and text-scale test in the suite would then be measuring a typeface nobody ships: wide enough
// to fail layouts that fit on a phone, and different enough to pass ones that do not.
//
// The Inter era never needed this, because google_fonts loaded each face through rootBundle on
// first use and the test binding serves the asset bundle. The theme now uses declared families
// (see the `fonts:` note in pubspec.yaml), so the faces are registered here instead — the same
// seven files, read off disk, under the same family names the pubspec gives them.
//
// Tests built on a stock ThemeData are untouched: they never ask for either family.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Family → files, exactly as declared under `fonts:` in pubspec.yaml.
const appFonts = <String, List<String>>{
  'Outfit': [
    'google_fonts/Outfit-Medium.ttf',
    'google_fonts/Outfit-SemiBold.ttf',
    'google_fonts/Outfit-Bold.ttf',
  ],
  'Manrope': [
    'google_fonts/Manrope-Regular.ttf',
    'google_fonts/Manrope-Medium.ttf',
    'google_fonts/Manrope-SemiBold.ttf',
    'google_fonts/Manrope-Bold.ttf',
  ],
  // Round 5: the Indian scripts, so a translated screen measures in the faces that ship.
  'NotoSansDevanagariUI': [
    'google_fonts/NotoSansDevanagariUI-Regular.ttf',
    'google_fonts/NotoSansDevanagariUI-Bold.ttf',
  ],
  'NotoSansTeluguUI': [
    'google_fonts/NotoSansTeluguUI-Regular.ttf',
    'google_fonts/NotoSansTeluguUI-Bold.ttf',
  ],
  'NotoSansTamilUI': [
    'google_fonts/NotoSansTamilUI-Regular.ttf',
    'google_fonts/NotoSansTamilUI-Bold.ttf',
  ],
  'NotoSansMalayalamUI': [
    'google_fonts/NotoSansMalayalamUI-Regular.ttf',
    'google_fonts/NotoSansMalayalamUI-Bold.ttf',
  ],
  'NotoSansKannadaUI': [
    'google_fonts/NotoSansKannadaUI-Regular.ttf',
    'google_fonts/NotoSansKannadaUI-Bold.ttf',
  ],
};

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final MapEntry(key: family, value: files) in appFonts.entries) {
    final loader = FontLoader(family);
    for (final path in files) {
      // Loudly, not `if (exists)`: a missing face is the silent-square failure this file
      // exists to prevent.
      final bytes = File(path).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  await testMain();
}
