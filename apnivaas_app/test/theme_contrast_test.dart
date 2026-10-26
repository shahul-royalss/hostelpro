import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/core/theme/typography.dart';
import 'package:mobile/shared/clay/skeleton.dart';
import 'package:mobile/shared/glass/glass.dart';

import 'flutter_test_config.dart' show appFonts;

/// The design system, held to its own numbers.
///
/// Three jobs, and they are different:
///
/// 1. **The palette is the canvas, minus what failed.** Forest & Cream comes from the design
///    canvas (`apnivaas_canvas/project/*.dc.html`). Five of its values could not carry their own
///    contrast and were replaced; the group "the canvas values that failed" pins each original's
///    failure, so "restoring the design value" fails here with the number it measured.
///
/// 2. **Contrast is measurable, so it is measured.** tokens.dart quotes a ratio next to almost
///    every colour. Comments rot; these do not, because each is recomputed here from the token
///    itself. A colour nudged by eye fails with the number it actually measured.
///
/// 3. **The font bundle is checked, not assumed.** This project has twice shipped
///    byte-identical files under different weight names, which registers N copies of one face
///    and makes every heading render regular while the pubspec looks correct. The typography
///    group reads the seven `.ttf` files off disk — weight class, outlines, the rupee glyph,
///    tabular figures — and then lays text out in them to prove the engine resolves each weight.
///
/// The maths is WCAG 2.1 §1.4.3 (text, 4.5:1) and §1.4.11 (graphical objects and UI
/// components, 3:1), unmodified.

/// Relative luminance, WCAG 2.1. Colour components are 0..1 in Flutter's wide-gamut API.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// Contrast ratio between two OPAQUE colours. Anything translucent must be composited first —
/// see [_over] — because a ratio against a colour that still has alpha is meaningless.
double _ratio(Color a, Color b) {
  assert(a.a == 1.0 && b.a == 1.0, 'composite translucent colours before measuring');
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Flattens [fg] (which may be translucent) onto opaque [bg], the way the compositor will.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

/// A ratio as the two decimals the comments in tokens.dart quote.
String _fixed(Color a, Color b) => _ratio(a, b).toStringAsFixed(2);

// ── THE SURFACES A COLOUR CAN LAND ON ────────────────────────────────────────────────────
//
// Split in two on purpose, and the split is the contract:
//
//   *Surfaces  — everything a TEXT token can be printed on, including the darker light fills
//                (Mist, the neutral chip) and the darker dark ones. Text is AA on all of these.
//   *Grounds   — the rungs a status CHIP may sit on: the ground, a card, a well. A chip's fill
//                is a tint of its own ink, so a darker rung moves the fill towards the text;
//                Mist and the neutral chip are excluded, and the test that says why is in the
//                chip group.
//
// Keys carry the hex so a failure names the surface rather than an index.
const _lightSurfaces = <String, Color>{
  'cream #F6F2EA': ApnivaasColors.cream,
  'card #FFFDF9': ApnivaasColors.card,
  'well #EEF4EF': ApnivaasColors.well,
  'chip #EAE3D6': ApnivaasColors.lightField,
  'mist #DCE8DF': ApnivaasColors.mist,
  'selected #F2F8F3': ApnivaasColors.selectedSurface,
};
const _lightGrounds = <String, Color>{
  'cream #F6F2EA': ApnivaasColors.cream,
  'card #FFFDF9': ApnivaasColors.card,
  'well #EEF4EF': ApnivaasColors.well,
};

/// The four light fills a CONTROL can sit on — the field fill is the card, a radio can be on a
/// selected persona. The chip fill and Mist are not: nothing draws a text field on them.
const _lightControlGrounds = <String, Color>{
  'cream #F6F2EA': ApnivaasColors.cream,
  'card #FFFDF9': ApnivaasColors.card,
  'well #EEF4EF': ApnivaasColors.well,
  'selected #F2F8F3': ApnivaasColors.selectedSurface,
};

/// Where a CANONICAL (context-free) colour can be painted in light: the four neutral fills.
const _lightCanonicalGrounds = <String, Color>{
  'cream #F6F2EA': ApnivaasColors.cream,
  'card #FFFDF9': ApnivaasColors.card,
  'well #EEF4EF': ApnivaasColors.well,
  'chip #EAE3D6': ApnivaasColors.lightField,
};

const _darkSurfaces = <String, Color>{
  'ground #0D1613': ApnivaasColors.ground,
  'card #15221D': ApnivaasColors.surfaceContainerLow,
  'raised #1B2B25': ApnivaasColors.surfaceContainer,
  'chip #26342F': ApnivaasColors.surfaceContainerHighest,
  'bright #22352E': ApnivaasColors.surfaceBright,
  'mist #1D3A31': ApnivaasColors.darkMist,
  'well #1F302A': ApnivaasColors.darkWell,
  'selected #1A3029': ApnivaasColors.darkSelected,
};
const _darkGrounds = <String, Color>{
  'ground #0D1613': ApnivaasColors.ground,
  'card #15221D': ApnivaasColors.surfaceContainerLow,
  'raised #1B2B25': ApnivaasColors.surfaceContainer,
};

void _expectAtLeast(double measured, double required_, String what) {
  expect(
    measured,
    greaterThanOrEqualTo(required_),
    reason: '$what measured ${measured.toStringAsFixed(2)}:1, '
        'needs ${required_.toStringAsFixed(2)}:1',
  );
}

/// The opposite bar: a pair that must stay QUIET — a fill step that should be felt, not seen.
void _expectBelowRatio(Color a, Color b, double ceiling, String what) {
  final measured = _ratio(a, b);
  expect(
    measured,
    lessThan(ceiling),
    reason: '$what measured ${measured.toStringAsFixed(3)}:1, '
        'must stay under ${ceiling.toStringAsFixed(2)}:1',
  );
}

void _againstAll(Map<String, Color> surfaces, Color fg, double need, String name) {
  surfaces.forEach((where, bg) {
    _expectAtLeast(_ratio(fg, bg), need, '$name ${_hex(fg)} on $where');
  });
}

// ── THE FONT BUNDLE ──────────────────────────────────────────────────────────────────────

/// What one sfnt file actually contains, read off its table directory.
///
/// Deliberately hand-rolled rather than pulled in as a dependency: the whole point is to read
/// what actually shipped, and a page of table-walking is cheaper than trusting a filename.
typedef _Face = ({
  int weightClass,
  Uint8List glyf,
  bool hasFvar,
  bool hasRupee,
  Set<String> gsubFeatures,
});

_Face _sfnt(File f) {
  final d = f.readAsBytesSync();
  final v = ByteData.sublistView(d);
  final numTables = v.getUint16(4);
  final tables = <String, (int, int)>{};
  for (var i = 0; i < numTables; i++) {
    final o = 12 + 16 * i;
    tables[String.fromCharCodes(d.sublist(o, o + 4))] = (v.getUint32(o + 8), v.getUint32(o + 12));
  }
  final (os2, _) = tables['OS/2']!;
  final (glyfAt, glyfLength) = tables['glyf']!;
  return (
    weightClass: v.getUint16(os2 + 4),
    glyf: Uint8List.sublistView(d, glyfAt, glyfAt + glyfLength),
    hasFvar: tables.containsKey('fvar'),
    hasRupee: _cmapMaps(v, tables['cmap']!.$1, 0x20B9),
    gsubFeatures:
        tables.containsKey('GSUB') ? _gsubFeatures(v, tables['GSUB']!.$1) : const <String>{},
  );
}

/// Whether any cmap subtable maps [cp] to a real glyph (not .notdef). Formats 4 and 12 are the
/// two every Google Fonts file carries.
bool _cmapMaps(ByteData v, int cmap, int cp) {
  final count = v.getUint16(cmap + 2);
  for (var i = 0; i < count; i++) {
    final sub = cmap + v.getUint32(cmap + 4 + 8 * i + 4);
    switch (v.getUint16(sub)) {
      case 4:
        final segX2 = v.getUint16(sub + 6);
        for (var s = 0; s < segX2 ~/ 2; s++) {
          final end = v.getUint16(sub + 14 + 2 * s);
          final start = v.getUint16(sub + 16 + segX2 + 2 * s);
          if (cp < start || cp > end) continue;
          final delta = v.getInt16(sub + 16 + 2 * segX2 + 2 * s);
          final rangeAt = sub + 16 + 3 * segX2 + 2 * s;
          final range = v.getUint16(rangeAt);
          var glyph = 0;
          if (range == 0) {
            glyph = (cp + delta) & 0xFFFF;
          } else {
            glyph = v.getUint16(rangeAt + range + 2 * (cp - start));
            if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
          }
          if (glyph != 0) return true;
        }
      case 12:
        final groups = v.getUint32(sub + 12);
        for (var g = 0; g < groups; g++) {
          final start = v.getUint32(sub + 16 + 12 * g);
          final end = v.getUint32(sub + 20 + 12 * g);
          if (cp >= start && cp <= end && v.getUint32(sub + 24 + 12 * g) + (cp - start) != 0) {
            return true;
          }
        }
    }
  }
  return false;
}

/// The four-letter tags in a GSUB FeatureList — `tnum` is the one this app needs.
Set<String> _gsubFeatures(ByteData v, int gsub) {
  final list = gsub + v.getUint16(gsub + 6);
  final count = v.getUint16(list);
  return {
    for (var i = 0; i < count; i++)
      String.fromCharCodes(
          List.generate(4, (k) => v.getUint8(list + 2 + 6 * i + k))),
  };
}

/// The `fonts:` block of pubspec.yaml as family → (asset → weight). Parsed by indentation,
/// which is all YAML this block uses.
Map<String, Map<String, int>> _declaredFonts() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((l) => l == '  fonts:');
  expect(start, isNot(-1), reason: 'pubspec.yaml has no `fonts:` block under `flutter:`');
  final families = <String, Map<String, int>>{};
  String? family;
  String? asset;
  for (final raw in lines.skip(start + 1)) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    if (!raw.startsWith('    ')) break; // back out to the next `flutter:` key
    final line = raw.trim();
    if (line.startsWith('- family:')) {
      family = line.substring('- family:'.length).trim();
      families[family] = {};
    } else if (line.startsWith('- asset:')) {
      asset = line.substring('- asset:'.length).trim();
      families[family]![asset] = 400;
    } else if (line.startsWith('weight:')) {
      families[family]![asset!] = int.parse(line.substring('weight:'.length).trim());
    }
  }
  return families;
}

/// The weights each family ships, as the theme sees them. Not const: FontWeight is compared by
/// value, and Dart refuses a const set of a type that overrides `==`.
final _bundledWeights = <String, Set<FontWeight>>{
  ApnivaasType.display: {FontWeight.w500, FontWeight.w600, FontWeight.w700},
  ApnivaasType.family: {FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700},
};

double _widthOf(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the light scheme is Forest & Cream', () {
    final light = ApnivaasTheme.light();
    final scheme = light.colorScheme;

    test('the brand values are the canvas\'s, hex for hex', () {
      expect(_hex(ApnivaasColors.forest), '#174E43');
      expect(_hex(ApnivaasColors.leaf), '#3F7F68');
      expect(_hex(ApnivaasColors.sage), '#7A9684');
      expect(_hex(ApnivaasColors.mist), '#DCE8DF');
      expect(_hex(ApnivaasColors.cream), '#F6F2EA');
      expect(_hex(ApnivaasColors.card), '#FFFDF9');
      expect(_hex(ApnivaasColors.gold), '#E2AE4A');
      expect(_hex(ApnivaasColors.ink), '#1C2B26');
      expect(_hex(ApnivaasColors.inkMuted), '#55655E');
    });

    test('the ground is cream and colorScheme.surface is the CARD, not the ground', () {
      // ~150 call sites paint a card with colorScheme.surface. Wiring the ground there makes
      // every one of them vanish into the page.
      expect(light.scaffoldBackgroundColor, ApnivaasColors.cream);
      expect(scheme.surface, ApnivaasColors.card);
      expect(scheme.surfaceDim, ApnivaasColors.cream);
      expect(scheme.surfaceContainer, ApnivaasColors.well);
      expect(scheme.surfaceContainerHighest, ApnivaasColors.lightField);
      expect(scheme.onSurface, ApnivaasColors.ink);
      expect(scheme.onSurfaceVariant, ApnivaasColors.inkMuted);
      expect(scheme.outline, ApnivaasColors.controlBorder);
      expect(scheme.outlineVariant, ApnivaasColors.cardBorder);
    });

    test('forest is the brand in both directions — the link AND the button fill', () {
      expect(scheme.primary, ApnivaasColors.forest);
      expect(scheme.onPrimary, const Color(0xFFFFFFFF));
      _expectAtLeast(_ratio(ApnivaasColors.forest, ApnivaasColors.card), 4.5, 'forest on the card');
      _expectAtLeast(_ratio(const Color(0xFFFFFFFF), ApnivaasColors.forest), 4.5,
          'white on forest');
      expect(scheme.primaryContainer, ApnivaasColors.mist);
      expect(scheme.onPrimaryContainer, ApnivaasColors.forest);
    });

    test('the light aliases still point where the call sites expect', () {
      // Each legacy name kept its MEANING and took the new value, so unconverted screens moved
      // with the redesign instead of breaking.
      expect(ApnivaasColors.background, ApnivaasColors.cream);
      expect(ApnivaasColors.surface, ApnivaasColors.card);
      expect(ApnivaasColors.lightSheet, ApnivaasColors.card);
      expect(ApnivaasColors.chipNeutral, ApnivaasColors.lightField);
      expect(ApnivaasColors.textPrimary, ApnivaasColors.ink);
      expect(ApnivaasColors.textSecondary, ApnivaasColors.inkStrong);
      expect(ApnivaasColors.mutedInk, ApnivaasColors.inkMuted);
      expect(ApnivaasColors.lightPrimary, ApnivaasColors.forest);
      expect(ApnivaasColors.indigo, ApnivaasColors.forest, reason: 'the name is historical');
      expect(ApnivaasColors.brandDeep, ApnivaasColors.forest);
      expect(ApnivaasColors.brandInk, ApnivaasColors.forest);
      expect(ApnivaasColors.softBlueInk, ApnivaasColors.mistInk);
      expect(ApnivaasColors.seed, ApnivaasColors.forest);
      expect(ApnivaasColors.starDots, same(HeaderStars.dots));
      expect(ApnivaasColors.hairline, isNot(ApnivaasColors.cardBorder),
          reason: 'a divider and a card edge are two jobs and two tokens');
    });

    test('no purple is left anywhere in the live theme', () {
      // The redesign exists to remove the violet brow and the rainbow of domain hues. Every
      // colour the light theme can paint without a call site choosing it is checked for a
      // violet or magenta hue at any real saturation.
      final semantics = light.extension<ApnivaasSemantics>()!;
      final painted = <String, Color>{
        'primary': scheme.primary,
        'primaryContainer': scheme.primaryContainer,
        'secondary': scheme.secondary,
        'secondaryContainer': scheme.secondaryContainer,
        'tertiary': scheme.tertiary,
        'tertiaryContainer': scheme.tertiaryContainer,
        'error': scheme.error,
        'errorContainer': scheme.errorContainer,
        'surface': scheme.surface,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'onSurface': scheme.onSurface,
        'onSurfaceVariant': scheme.onSurfaceVariant,
        'outline': scheme.outline,
        'outlineVariant': scheme.outlineVariant,
        'inverseSurface': scheme.inverseSurface,
        'inversePrimary': scheme.inversePrimary,
        'scaffold': light.scaffoldBackgroundColor,
        'success': semantics.success,
        'warning': semantics.warning,
        'semantic error': semantics.error,
        'info': semantics.info,
        'muted': semantics.muted,
        'rooms': semantics.rooms,
        'people': semantics.people,
        'food': semantics.food,
        for (final (i, c) in ApnivaasColors.headerGradient.colors.indexed) 'header stop $i': c,
        for (final (i, s) in HeaderStars.dots.indexed) 'star $i': s.color,
        'banner top': ApnivaasColors.bannerTop,
        'banner bottom': ApnivaasColors.bannerBottom,
      };
      painted.forEach((name, c) {
        final hsl = HSLColor.fromColor(c);
        final violet = hsl.hue >= 250 && hsl.hue <= 330 && hsl.saturation > 0.15;
        expect(violet, isFalse,
            reason: '$name ${_hex(c)} is violet (hue ${hsl.hue.round()}°) — purple is back');
      });
    });

    test('gold is never light-theme text or a graphic on cream', () {
      // It lives on forest and on dark surfaces only. Restated as a number so nobody "brightens
      // up" a cream screen with a gold glyph.
      expect(_ratio(ApnivaasColors.gold, ApnivaasColors.cream), lessThan(3.0));
      expect(_ratio(ApnivaasColors.gold, ApnivaasColors.card), lessThan(3.0));
      expect(_fixed(ApnivaasColors.gold, ApnivaasColors.cream), '1.81');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the dark scheme is designed and measured, and stays wired', () {
    final dark = ApnivaasTheme.dark();
    final scheme = dark.colorScheme;

    test('surfaces — a four-rung ladder, and the rungs nothing needs are aliases', () {
      expect(_hex(ApnivaasColors.ground), '#0D1613');
      expect(_hex(ApnivaasColors.surfaceContainerLow), '#15221D');
      expect(_hex(ApnivaasColors.surfaceContainer), '#1B2B25');
      expect(_hex(ApnivaasColors.surfaceBright), '#22352E');
      expect(ApnivaasColors.surfaceContainerLowest, ApnivaasColors.ground);
      expect(ApnivaasColors.surfaceContainerHigh, ApnivaasColors.surfaceContainer);
      // In the dark, elevation gets LIGHTER as it rises.
      expect(_luminance(ApnivaasColors.surfaceContainerLow),
          greaterThan(_luminance(ApnivaasColors.ground)));
      expect(_luminance(ApnivaasColors.surfaceContainer),
          greaterThan(_luminance(ApnivaasColors.surfaceContainerLow)));
    });

    test('every on-colour on a dark fill is the ground itself', () {
      for (final on in [
        ApnivaasColors.onPrimary,
        ApnivaasColors.onSecondary,
        ApnivaasColors.onTertiary,
        ApnivaasColors.onErrorTone,
      ]) {
        expect(on, ApnivaasColors.ground);
      }
    });

    test('the container fills are the dark inks at the chip tint, flattened', () {
      // A container role that is secretly translucent composites twice the moment somebody
      // stacks it, so they are pinned flat — but they must still BE the tint.
      for (final e in {
        'secondary': (ApnivaasColors.secondary, ApnivaasColors.secondaryContainer),
        'tertiary': (ApnivaasColors.tertiary, ApnivaasColors.tertiaryContainer),
        'error': (ApnivaasColors.errorTone, ApnivaasColors.errorContainer),
        'info': (ApnivaasColors.infoDark, ApnivaasColors.darkInfoContainer),
      }.entries) {
        final (tone, container) = e.value;
        final expected = _over(
          tone.withValues(alpha: ApnivaasSemantics.dark.chipFillAlpha),
          ApnivaasColors.surfaceContainerLow,
        );
        expect(_hex(container), _hex(expected),
            reason: '${e.key}Container drifted off the tint it is defined as');
      }
    });

    test('the legacy names point at the dark tokens, so unconverted screens moved with us', () {
      expect(ApnivaasColors.darkBackground, ApnivaasColors.ground);
      expect(ApnivaasColors.darkSurface, ApnivaasColors.surfaceContainerLow);
      expect(ApnivaasColors.darkElevated, ApnivaasColors.surfaceContainer);
      expect(ApnivaasColors.midnight, ApnivaasColors.forestDeep);
      expect(ApnivaasColors.darkIndigo, ApnivaasColors.primary);
      expect(ApnivaasColors.softBlue, ApnivaasColors.secondary);
      expect(ApnivaasColors.darkTextPrimary, ApnivaasColors.onSurface);
      expect(ApnivaasColors.darkTextSecondary, ApnivaasColors.onSurfaceVariant);
      expect(ApnivaasColors.darkHairline, ApnivaasColors.outlineVariant);
      expect(ApnivaasColors.darkCardBorder, ApnivaasColors.outlineVariant);
      expect(ApnivaasColors.darkControlBorder, ApnivaasColors.outline);
      expect(ApnivaasColors.successDark, ApnivaasColors.tertiary);
      expect(ApnivaasColors.warningDark, ApnivaasColors.secondary);
      expect(ApnivaasColors.errorDark, ApnivaasColors.errorTone);
      expect(ApnivaasColors.brandDark, ApnivaasColors.primary);
    });

    test('the theme wires every one of those roles through, nothing literal', () {
      expect(dark.scaffoldBackgroundColor, ApnivaasColors.ground);
      expect(scheme.surface, ApnivaasColors.surfaceContainerLow);
      expect(scheme.surfaceDim, ApnivaasColors.ground);
      expect(scheme.surfaceBright, ApnivaasColors.surfaceBright);
      expect(scheme.surfaceContainer, ApnivaasColors.surfaceContainer);
      expect(scheme.primary, ApnivaasColors.brandDark);
      expect(scheme.onPrimary, ApnivaasColors.onPrimary);
      expect(scheme.primaryContainer, ApnivaasColors.mist);
      expect(scheme.secondary, ApnivaasColors.secondary);
      expect(scheme.tertiary, ApnivaasColors.tertiary);
      expect(scheme.error, ApnivaasColors.errorTone);
      expect(scheme.onSurface, ApnivaasColors.onSurface);
      expect(scheme.onSurfaceVariant, ApnivaasColors.onSurfaceVariant);
      expect(scheme.outline, ApnivaasColors.outline);
      expect(scheme.outlineVariant, ApnivaasColors.outlineVariant);
    });

    test('the brand block is the SAME object in both themes', () {
      // The header gradient, the forest hero tile and gold are identical on a light and a dark
      // phone; it is what makes the product recognisable before a word is read.
      final lightHeader = ApnivaasTheme.light().datePickerTheme.headerBackgroundColor;
      expect(lightHeader, ApnivaasColors.forest);
      expect(dark.datePickerTheme.headerBackgroundColor, ApnivaasColors.forest);
      expect(ApnivaasTheme.light().colorScheme.primaryContainer, scheme.primaryContainer,
          reason: 'Mist is the tonal fill in light and the filled button in dark — one value');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('text is AA — WCAG 1.4.3, 4.5:1, on EVERY surface of its theme', () {
    test('light neutral ramp', () {
      _againstAll(_lightSurfaces, ApnivaasColors.textPrimary, 4.5, 'textPrimary');
      _againstAll(_lightSurfaces, ApnivaasColors.textSecondary, 4.5, 'textSecondary');
      _againstAll(_lightSurfaces, ApnivaasColors.mutedInk, 4.5, 'mutedInk');
      _againstAll(_lightSurfaces, ApnivaasColors.mistInk, 4.5, 'mistInk');
    });

    test('light brand and semantic ink', () {
      _againstAll(_lightSurfaces, ApnivaasColors.lightPrimary, 4.5, 'lightPrimary');
      _againstAll(_lightSurfaces, ApnivaasColors.successInk, 4.5, 'successInk');
      _againstAll(_lightSurfaces, ApnivaasColors.warningInk, 4.5, 'warningInk');
      _againstAll(_lightSurfaces, ApnivaasColors.errorInk, 4.5, 'errorInk');
      _againstAll(_lightSurfaces, ApnivaasColors.infoInk, 4.5, 'infoInk');
      // The domain inks are the brand ink now, and held to exactly the same bar.
      _againstAll(_lightSurfaces, ApnivaasColors.foodInk, 4.5, 'foodInk');
      _againstAll(_lightSurfaces, ApnivaasColors.roomsInk, 4.5, 'roomsInk');
      _againstAll(_lightSurfaces, ApnivaasColors.peopleInk, 4.5, 'peopleInk');
    });

    test('the figures quoted in tokens.dart for the light ramp are the measured ones', () {
      expect(_fixed(ApnivaasColors.ink, ApnivaasColors.card), '14.53');
      expect(_fixed(ApnivaasColors.ink, ApnivaasColors.lightField), '11.57');
      expect(_fixed(ApnivaasColors.inkMuted, ApnivaasColors.card), '6.06');
      expect(_fixed(ApnivaasColors.inkMuted, ApnivaasColors.lightField), '4.83');
      expect(_fixed(ApnivaasColors.forest, ApnivaasColors.card), '9.36');
      expect(_fixed(ApnivaasColors.forest, ApnivaasColors.cream), '8.52');
      expect(_fixed(ApnivaasColors.warningInk, ApnivaasColors.lightField), '4.64',
          reason: 'the tightest status ink');
    });

    test('dark neutral ramp', () {
      _againstAll(_darkSurfaces, ApnivaasColors.onSurface, 4.5, 'onSurface');
      _againstAll(_darkSurfaces, ApnivaasColors.onSurfaceVariant, 4.5, 'onSurfaceVariant');
      _againstAll(_darkSurfaces, ApnivaasColors.darkMuted, 4.5, 'darkMuted');
    });

    test('dark brand and semantic ink', () {
      _againstAll(_darkSurfaces, ApnivaasColors.primary, 4.5, 'primary (mint)');
      _againstAll(_darkSurfaces, ApnivaasColors.successDark, 4.5, 'successDark');
      _againstAll(_darkSurfaces, ApnivaasColors.warningDark, 4.5, 'warningDark');
      _againstAll(_darkSurfaces, ApnivaasColors.errorDark, 4.5, 'errorDark');
      _againstAll(_darkSurfaces, ApnivaasColors.infoDark, 4.5, 'infoDark');
      _againstAll(_darkSurfaces, ApnivaasColors.foodDark, 4.5, 'foodDark');
      _againstAll(_darkSurfaces, ApnivaasColors.roomsDark, 4.5, 'roomsDark');
      _againstAll(_darkSurfaces, ApnivaasColors.peopleDark, 4.5, 'peopleDark');
    });

    test('a placeholder is text, measured against the fill it is actually drawn on', () {
      // The field fill is the card in light and the raised surface in dark. A placeholder is
      // not held to the darker fills because no field is drawn on them.
      _expectAtLeast(_ratio(ApnivaasColors.placeholder, ApnivaasColors.card), 4.5,
          'light placeholder on the field');
      _expectAtLeast(_ratio(ApnivaasColors.darkPlaceholder, ApnivaasColors.surfaceContainer), 4.5,
          'dark placeholder on the field');
    });

    test('each ramp is a hierarchy, not three shades of the same grey', () {
      for (final e in {
        'light': [ApnivaasColors.textPrimary, ApnivaasColors.textSecondary, ApnivaasColors.mutedInk],
        'dark': [ApnivaasColors.onSurface, ApnivaasColors.onSurfaceVariant, ApnivaasColors.darkMuted],
      }.entries) {
        final card = e.key == 'light' ? ApnivaasColors.card : ApnivaasColors.surfaceContainerLow;
        final ratios = e.value.map((c) => _ratio(c, card)).toList();
        for (var i = 1; i < ratios.length; i++) {
          expect(ratios[i], lessThan(ratios[i - 1]),
              reason: '${e.key} step $i does not read quieter than the one above it');
        }
      }
    });

    test('the filled surfaces carry their own legible inks', () {
      for (final e in <String, (Color, Color)>{
        'white on forest': (const Color(0xFFFFFFFF), ApnivaasColors.forest),
        'white on a pressed button': (const Color(0xFFFFFFFF), ApnivaasColors.forestPressed),
        'forest on Mist': (ApnivaasColors.forest, ApnivaasColors.mist),
        'ink on Mist': (ApnivaasColors.ink, ApnivaasColors.mist),
        'muted on Mist': (ApnivaasColors.inkMuted, ApnivaasColors.mist),
        'mistInk on Mist': (ApnivaasColors.mistInk, ApnivaasColors.mist),
        'ink on gold': (ApnivaasColors.ink, ApnivaasColors.gold),
        'banner title': (ApnivaasColors.bannerTitle, ApnivaasColors.bannerBottom),
        'banner body': (ApnivaasColors.bannerBody, ApnivaasColors.bannerBottom),
        'banner title, light stop': (ApnivaasColors.bannerTitle, ApnivaasColors.bannerTop),
        'banner body, light stop': (ApnivaasColors.bannerBody, ApnivaasColors.bannerTop),
        'error banner': (ApnivaasColors.errorInk, ApnivaasColors.errorContainerLight),
        'white on the error red': (const Color(0xFFFFFFFF), ApnivaasColors.errorInk),
        'hero tile caption': (ApnivaasColors.headerSub, ApnivaasColors.forest),
      }.entries) {
        final (on, fill) = e.value;
        _expectAtLeast(_ratio(on, fill), 4.5, '${e.key}: ${_hex(on)} on ${_hex(fill)}');
      }
    });

    test('both schemes agree with themselves about on-colours', () {
      for (final scheme in [ApnivaasTheme.dark().colorScheme, ApnivaasTheme.light().colorScheme]) {
        final label = scheme.brightness.name;
        for (final e in <String, (Color, Color)>{
          'primary': (scheme.primary, scheme.onPrimary),
          'primaryContainer': (scheme.primaryContainer, scheme.onPrimaryContainer),
          'secondary': (scheme.secondary, scheme.onSecondary),
          'secondaryContainer': (scheme.secondaryContainer, scheme.onSecondaryContainer),
          'tertiary': (scheme.tertiary, scheme.onTertiary),
          'tertiaryContainer': (scheme.tertiaryContainer, scheme.onTertiaryContainer),
          'error': (scheme.error, scheme.onError),
          'errorContainer': (scheme.errorContainer, scheme.onErrorContainer),
          'surface': (scheme.surface, scheme.onSurface),
          'inverseSurface': (scheme.inverseSurface, scheme.onInverseSurface),
        }.entries) {
          final (fill, on) = e.value;
          _expectAtLeast(_ratio(on, fill), 4.5, '$label ${e.key}');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('graphics and controls are 3:1 — WCAG 1.4.11', () {
    const canonical = <String, Color>{
      'success': ApnivaasColors.success,
      'warning': ApnivaasColors.warning,
      'error': ApnivaasColors.error,
      'info': ApnivaasColors.info,
      'textMuted': ApnivaasColors.textMuted,
      'brand': ApnivaasColors.brand,
    };

    test('the canonical set clears 3:1 on every neutral fill of BOTH themes', () {
      // These are the values painted with no BuildContext — chart bars, meter fills, a `tone:`
      // plumbed through an enum.
      canonical.forEach((name, c) {
        _againstAll(_lightCanonicalGrounds, c, 3.0, 'canonical $name');
        _againstAll(_darkGrounds, c, 3.0, 'canonical $name');
      });
    });

    test('one flat colour can serve both themes, and every canonical value sits in the window',
        () {
      // To clear 3:1 over the lightest dark rung a colour needs L above `needAbove`; to clear it
      // under the darkest light fill, L below `needBelow`. If the windows ever stop overlapping
      // the canonical set has to split, and this says so before the ratios do.
      final darkCeiling = _darkGrounds.values.map(_luminance).reduce(math.max);
      final lightFloor = _lightCanonicalGrounds.values.map(_luminance).reduce(math.min);
      final needAbove = 3.0 * (darkCeiling + 0.05) - 0.05;
      final needBelow = (lightFloor + 0.05) / 3.0 - 0.05;
      expect(needAbove, lessThan(needBelow),
          reason: 'the luminance windows no longer overlap: a colour would need L >= '
              '${needAbove.toStringAsFixed(4)} and L <= ${needBelow.toStringAsFixed(4)}');
      canonical.forEach((name, c) {
        expect(_luminance(c), inInclusiveRange(needAbove, needBelow), reason: '$name ${_hex(c)}');
      });
    });

    test('a control border is the control, so it is 3:1 — not the card hairline', () {
      _againstAll(_lightControlGrounds, ApnivaasColors.controlBorder, 3.0, 'controlBorder');
      _againstAll(_darkGrounds, ApnivaasColors.darkControlBorder, 3.0, 'darkControlBorder');
      _expectAtLeast(_ratio(ApnivaasColors.outline, ApnivaasColors.surfaceBright), 3.0,
          'dark control border on the brightest rung');
    });

    test('decorative edges are deliberately BELOW 3:1, which is why they are separate tokens',
        () {
      // A card edge held to 3:1 looks like a text field.
      expect(_ratio(ApnivaasColors.cardBorder, ApnivaasColors.card), lessThan(2.0));
      expect(_ratio(ApnivaasColors.cardBorder, ApnivaasColors.cream), lessThan(2.0));
      expect(_ratio(ApnivaasColors.hairline, ApnivaasColors.card),
          lessThan(_ratio(ApnivaasColors.cardBorder, ApnivaasColors.card)),
          reason: 'a divider must be quieter than a card edge — that is why they are two tokens');
      _darkSurfaces.forEach((where, bg) {
        expect(_ratio(ApnivaasColors.darkCardBorder, bg), lessThan(2.0),
            reason: 'the dark card hairline has become a control border on $where');
      });
    });

    test('the greens are graphics first, and two of them are never text where it fails', () {
      // Leaf reads as text on the card and NOT on the ground; sage is decoration only.
      _expectAtLeast(_ratio(ApnivaasColors.leaf, ApnivaasColors.card), 4.5, 'leaf on the card');
      expect(_ratio(ApnivaasColors.leaf, ApnivaasColors.cream), lessThan(4.5),
          reason: 'if leaf now passes on the ground, the forest-for-links rule can relax');
      _expectAtLeast(_ratio(ApnivaasColors.sage, ApnivaasColors.card), 3.0, 'sage as a graphic');
      expect(_ratio(ApnivaasColors.sage, ApnivaasColors.card), lessThan(4.5),
          reason: 'sage is decoration, never text');
    });

    test('gold earns its place only on forest', () {
      _expectAtLeast(_ratio(ApnivaasColors.gold, ApnivaasColors.forestHigh), 3.0,
          'the unread dot on the lightest header stop');
      _expectAtLeast(_ratio(ApnivaasColors.gold, ApnivaasColors.forestTrack), 3.0,
          'the hero tile progress on its track');
      expect(_fixed(ApnivaasColors.gold, ApnivaasColors.forestHigh), '3.60');
      expect(_fixed(ApnivaasColors.gold, ApnivaasColors.forestTrack), '3.13');
    });

    test('a focus ring and a light progress fill read on what they sit on', () {
      _expectAtLeast(_ratio(ApnivaasColors.forest, ApnivaasColors.card), 3.0, 'light focus ring');
      _expectAtLeast(_ratio(ApnivaasColors.primary, ApnivaasColors.surfaceContainerLow), 3.0,
          'dark focus ring');
      _expectAtLeast(_ratio(ApnivaasColors.forest, ApnivaasColors.track), 3.0,
          'forest progress on the light track');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // FIVE CANVAS VALUES COULD NOT CARRY THEIR OWN CONTRAST. Each original's failure is pinned
  // where the canvas actually draws it, next to the replacement that passes. Restoring a canvas
  // value fails here, with the number it measures.
  group('the canvas values that failed, and what replaced them', () {
    final searchFill = _over(ApnivaasColors.headerSearchFill, ApnivaasColors.forestHigh);

    test('the input and chip border #DDD5C8 → controlBorder', () {
      expect(_ratio(const Color(0xFFDDD5C8), ApnivaasColors.card), lessThan(3.0));
      _expectAtLeast(_ratio(ApnivaasColors.controlBorder, ApnivaasColors.card), 3.0,
          'controlBorder on the field fill');
      expect(_fixed(ApnivaasColors.controlBorder, ApnivaasColors.card), '3.53');
    });

    test('the radio ring #BFB6A8 → controlBorder', () {
      expect(_ratio(const Color(0xFFBFB6A8), ApnivaasColors.card), lessThan(3.0));
    });

    test('the placeholder #7B8A83 → placeholder', () {
      expect(_ratio(const Color(0xFF7B8A83), ApnivaasColors.card), lessThan(4.5));
      expect(_fixed(ApnivaasColors.placeholder, ApnivaasColors.card), '4.77');
    });

    test('the inactive tab label #6B7A73 → inkMuted', () {
      expect(_ratio(const Color(0xFF6B7A73), ApnivaasColors.card), lessThan(4.5));
      _expectAtLeast(_ratio(ApnivaasColors.inkMuted, ApnivaasColors.card), 4.5,
          'the inactive tab label on the bar');
    });

    test('the header search placeholder #CFE0D4 → headerPlaceholder', () {
      expect(_hex(searchFill), '#3A7465', reason: 'white at 12% over the lightest header stop');
      expect(_ratio(const Color(0xFFCFE0D4), searchFill), lessThan(4.5));
      expect(_fixed(const Color(0xFFCFE0D4), searchFill), '3.94');
      expect(_fixed(ApnivaasColors.headerPlaceholder, searchFill), '4.65');
    });

    test('leaf as text on the ground → forest', () {
      expect(_fixed(ApnivaasColors.leaf, ApnivaasColors.cream), '4.23');
      expect(_fixed(ApnivaasColors.forest, ApnivaasColors.cream), '8.52');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the forest header — every ink measured on its LIGHTEST stop', () {
    const worst = ApnivaasColors.forestHigh;

    test('the gradient is the canvas\'s 160deg and lightens top to bottom', () {
      const g = ApnivaasColors.headerGradient;
      expect(g.colors, [ApnivaasColors.forestDeep, ApnivaasColors.forest, ApnivaasColors.forestHigh]);
      expect(g.stops, [0, 0.55, 1]);
      expect((g.transform! as GradientRotation).radians, closeTo(-math.pi / 9, 1e-9));
      // Monotone, so the last stop is the worst case for light ink everywhere on the header.
      final l = g.colors.map(_luminance).toList();
      expect(l[0], lessThan(l[1]));
      expect(l[1], lessThan(l[2]));
    });

    test('title, greeting and meta lines', () {
      for (final ground in [worst, ApnivaasColors.forest, ApnivaasColors.forestDeep]) {
        _expectAtLeast(_ratio(ApnivaasColors.headerTitle, ground), 7.0, 'title on ${_hex(ground)}');
        _expectAtLeast(_ratio(ApnivaasColors.headerGreeting, ground), 4.5,
            'greeting on ${_hex(ground)}');
        _expectAtLeast(_ratio(ApnivaasColors.headerSub, ground), 4.5, 'meta on ${_hex(ground)}');
      }
      expect(_fixed(ApnivaasColors.headerTitle, worst), '7.28');
      expect(_fixed(ApnivaasColors.headerGreeting, worst), '5.11');
      expect(_fixed(ApnivaasColors.headerSub, worst), '5.29');
    });

    test('the search pill and the round buttons', () {
      final search = _over(ApnivaasColors.headerSearchFill, worst);
      _expectAtLeast(_ratio(const Color(0xFFFFFFFF), search), 4.5, 'typed text in the pill');
      _expectAtLeast(_ratio(ApnivaasColors.headerPlaceholder, search), 4.5, 'pill placeholder');
      expect(_fixed(const Color(0xFFFFFFFF), search), '5.42');
      final button = _over(ApnivaasColors.headerButtonFill, worst);
      _expectAtLeast(_ratio(ApnivaasColors.headerTitle, button), 3.0, 'a header glyph');
      expect(_fixed(ApnivaasColors.headerTitle, button), '6.01');
    });

    test('the stars stay out from behind the type, small and faint', () {
      // Trailing half, or hugging the top or bottom edge — never behind the greeting.
      for (final s in HeaderStars.dots) {
        final clear = s.x >= HeaderStars.referenceWidth / 2 || s.y <= 14 || s.y >= 150;
        expect(clear, isTrue, reason: 'a star at (${s.x}, ${s.y}) sits behind the greeting');
        expect(s.radius, inInclusiveRange(0.8, 1.7));
        expect(s.alpha, inInclusiveRange(0.0, 1.0));
        expect(s.x, inInclusiveRange(0, HeaderStars.referenceWidth));
        expect(s.y, inInclusiveRange(0, HeaderStars.referenceHeight));
        if (s.haloRadius != null) {
          expect(s.haloAlpha!, lessThanOrEqualTo(0.15), reason: 'a halo is a whisper');
        }
      }
      // A halo is the only thing that could lift a ground under type, and the painter draws one
      // only from haloMinFraction outward — so that fraction must clear the greeting.
      expect(HeaderStars.haloMinFraction, greaterThanOrEqualTo(0.75));
      expect(HeaderStars.dots.where((s) => s.haloRadius != null), isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('status chips — the tightest case in the app', () {
    Map<String, Color> inksOf(ApnivaasSemantics tones) => {
          'success': tones.success,
          'warning': tones.warning,
          'error': tones.error,
          'info': tones.info,
          'muted': tones.muted,
          'food': tones.food,
          'rooms': tones.rooms,
          'people': tones.people,
        };

    void checkChips(ApnivaasSemantics tones, Map<String, Color> grounds, String label) {
      inksOf(tones).forEach((name, ink) {
        grounds.forEach((where, bg) {
          final fill = _over(tones.chipFill(ink), bg);
          _expectAtLeast(_ratio(ink, fill), 4.5, '$label $name chip on $where');
        });
      });
    }

    test('light chips', () => checkChips(ApnivaasSemantics.light, _lightGrounds, 'light'));
    test('dark chips', () => checkChips(ApnivaasSemantics.dark, _darkGrounds, 'dark'));

    test('the fill alpha is 10%, and 0.12 is the last value that still clears AA', () {
      // A tint of the tone moves the fill TOWARDS the text, so the ratio falls as the alpha
      // rises. These are the numbers the comment on ApnivaasSemantics quotes.
      expect(ApnivaasSemantics.light.chipFillAlpha, 0.10);
      expect(ApnivaasSemantics.dark.chipFillAlpha, ApnivaasSemantics.light.chipFillAlpha,
          reason: 'one number for both themes, so a chip reads at the same weight in either');

      double worstAt(double alpha) => [
            for (final e in {
              ApnivaasSemantics.light: _lightGrounds,
              ApnivaasSemantics.dark: _darkGrounds,
            }.entries)
              for (final ink in inksOf(e.key).values)
                for (final bg in e.value.values)
                  _ratio(ink, _over(ink.withValues(alpha: alpha), bg)),
          ].reduce(math.min);
      expect(worstAt(0.10).toStringAsFixed(2), '4.64');
      expect(worstAt(0.12), greaterThanOrEqualTo(4.5));
      expect(worstAt(0.13), lessThan(4.5),
          reason: 'chips have more room than the comment says; re-derive the ceiling rather '
              'than leaving the number stale');
    });

    test('a chip never sits on Mist or the neutral chip fill — and here is why', () {
      // Both are darker than the ground, so a translucent chip lands closer to its own ink.
      // Recorded as a failure so the rule in ApnivaasSemantics cannot be "simplified" away.
      final warning = ApnivaasSemantics.light.warning;
      for (final bg in [ApnivaasColors.mist, ApnivaasColors.lightField]) {
        final fill = _over(ApnivaasSemantics.light.chipFill(warning), bg);
        expect(_ratio(warning, fill), lessThan(4.5), reason: 'warning chip on ${_hex(bg)}');
      }
      expect(_fixed(warning, _over(ApnivaasSemantics.light.chipFill(warning), ApnivaasColors.mist)),
          '4.13');
    });

    test('the neutral chip is opaque, so it reads wherever it lands', () {
      _expectAtLeast(_ratio(ApnivaasColors.inkMuted, ApnivaasColors.chipNeutral), 4.5,
          'light neutral chip');
      _expectAtLeast(
          _ratio(ApnivaasColors.onSurfaceVariant, ApnivaasColors.surfaceContainerHighest), 4.5,
          'dark neutral chip');
    });

    test('the chip border is FULL STRENGTH, so where one is drawn it is a real edge', () {
      expect(ApnivaasSemantics.dark.chipBorderAlpha, 1.0);
      for (final e in {
        'light': (ApnivaasSemantics.light, ApnivaasColors.errorInk, _lightGrounds),
        'dark': (ApnivaasSemantics.dark, ApnivaasColors.errorDark, _darkGrounds),
      }.entries) {
        final (tones, ink, grounds) = e.value;
        expect(tones.chipBorder(ink), ink);
        grounds.forEach((where, bg) {
          _expectAtLeast(_ratio(tones.chipBorder(ink), bg), 3.0, '${e.key} chip border on $where');
        });
      }
    });

    test('resolve() maps every canonical to the theme text value, and passes the rest through',
        () {
      expect(ApnivaasSemantics.light.resolve(ApnivaasColors.error), ApnivaasColors.errorInk);
      expect(ApnivaasSemantics.dark.resolve(ApnivaasColors.error), ApnivaasColors.errorDark);
      expect(ApnivaasSemantics.dark.resolve(ApnivaasColors.success), ApnivaasColors.tertiary);
      expect(ApnivaasSemantics.light.resolve(ApnivaasColors.textMuted), ApnivaasColors.mutedInk);
      expect(ApnivaasSemantics.dark.resolve(ApnivaasColors.food), ApnivaasColors.foodDark);
      expect(ApnivaasSemantics.light.resolve(ApnivaasColors.rooms), ApnivaasColors.roomsInk);
      expect(ApnivaasSemantics.dark.resolve(ApnivaasColors.people), ApnivaasColors.peopleDark);
      // EVERY SPELLING OF THE BRAND RESOLVES — including the dark scheme's mint, which two call
      // sites pass as a tone and which is 1.9:1 on cream if painted as given.
      for (final spelling in [
        ApnivaasColors.brand,
        ApnivaasColors.lightPrimary,
        ApnivaasColors.primary,
      ]) {
        expect(ApnivaasSemantics.light.resolve(spelling), ApnivaasColors.forest);
        expect(ApnivaasSemantics.dark.resolve(spelling), ApnivaasColors.primary);
      }
      // Not a canonical value: untouched.
      expect(ApnivaasSemantics.light.resolve(ApnivaasColors.gold), ApnivaasColors.gold);
      expect(ApnivaasSemantics.dark.resolve(ApnivaasColors.gold), ApnivaasColors.gold);
    });

    testWidgets('the fallback tones are the DARK set, for a widget pumped without the theme',
        (tester) async {
      late ApnivaasSemantics seen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          seen = context.tones;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen, ApnivaasSemantics.dark);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE DOMAIN TONES ARE RETIRED AS COLOURS. Rooms, people and food used to be violet, teal and
  // saffron; the clay icon says what kind of thing a row is now, so they collapsed to the brand,
  // and the domains that mean something keep the status tone they mean.
  group('the domain tones — the brand plus three meanings', () {
    test('each domain names exactly the tone the redesign gives it', () {
      expect(ApnivaasDomain.money.tone, ApnivaasColors.success);
      expect(ApnivaasDomain.complaints.tone, ApnivaasColors.warning);
      expect(ApnivaasDomain.notices.tone, ApnivaasColors.info);
      for (final d in [
        ApnivaasDomain.rooms,
        ApnivaasDomain.people,
        ApnivaasDomain.food,
        ApnivaasDomain.security,
      ]) {
        expect(d.tone, ApnivaasColors.brand, reason: '${d.name} is the brand');
      }
      expect(ApnivaasDomain.values.map((d) => d.tone).toSet(), hasLength(4));
    });

    test('every domain resolves to a theme ink, in both themes', () {
      for (final d in ApnivaasDomain.values) {
        for (final tones in [ApnivaasSemantics.dark, ApnivaasSemantics.light]) {
          expect(tones.resolve(d.tone), isNot(d.tone),
              reason: '${d.name} did not resolve, so the paint site cannot make it legible');
        }
      }
    });

    test('an identity avatar can never wear a STATUS colour', () {
      // THE REGRESSION THIS PINS WAS REAL. The same avatar widget carries a status tone on
      // several screens, so a name that hashed to amber wore the disc that means "on leave".
      // With the domain hues retired every identity disc is the brand, which is the strongest
      // form of the guarantee.
      const statusTones = <Color>[
        ApnivaasColors.success,
        ApnivaasColors.warning,
        ApnivaasColors.error,
        ApnivaasColors.info,
      ];
      final seen = <Color>{for (var i = 0; i < 4000; i++) avatarToneFor('Resident Number $i')};
      for (final tone in seen) {
        expect(statusTones.contains(tone), isFalse,
            reason: 'avatarToneFor produced ${_hex(tone)}, which is a STATUS tone');
        for (final tones in [ApnivaasSemantics.dark, ApnivaasSemantics.light]) {
          expect(tones.resolve(tone), isNot(tone),
              reason: '${_hex(tone)} has no theme ink, so the initials on it are unmeasured');
        }
      }
    });

    test('the same name always gets the same colour, and an empty name is neutral', () {
      expect(avatarToneFor('Aarav Sharma'), avatarToneFor('Aarav Sharma'));
      expect(avatarToneFor('  aarav sharma  '), avatarToneFor('Aarav Sharma'));
      expect(avatarToneFor(null), ApnivaasColors.textMuted);
      expect(avatarToneFor('   '), ApnivaasColors.textMuted);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE REFUND PAIRING — a refund is a FACT, NOT A FAULT, so it wears `info`: not the red that
  // means unpaid, not the amber that means still owing, not the green of a collection.
  group('the refund tone — a fact, not a fault', () {
    test('it is the info tone, and it is not any of the three rent tones', () {
      for (final e in {
        'light': ApnivaasSemantics.light,
        'dark': ApnivaasSemantics.dark,
      }.entries) {
        final tones = e.value;
        final refund = tones.resolve(ApnivaasColors.info);
        expect(refund, tones.info);
        expect(refund, isNot(tones.error));
        expect(refund, isNot(tones.warning));
        expect(refund, isNot(tones.success));
      }
    });

    test('the info ink reads on the WELL the refund note is drawn in, and on the card', () {
      for (final e in {
        'light': (ApnivaasTheme.light(), ApnivaasSemantics.light),
        'dark': (ApnivaasTheme.dark(), ApnivaasSemantics.dark),
      }.entries) {
        final (theme, tones) = e.value;
        final well = theme.colorScheme.surfaceContainer;
        _expectAtLeast(_ratio(tones.info, well), 4.5, '${e.key} refund ink on the well');
        _expectAtLeast(
            _ratio(tones.chipBorder(tones.info), well), 3.0, '${e.key} refund well border');
        _expectAtLeast(_ratio(tones.info, theme.colorScheme.surfaceContainerLow), 4.5,
            '${e.key} refund ink on the card');
      }
    });

    test("the owner's strip is 12px on a chip of its own tone — the tightest case there is",
        () {
      for (final e in {
        'light': (ApnivaasTheme.light(), ApnivaasSemantics.light),
        'dark': (ApnivaasTheme.dark(), ApnivaasSemantics.dark),
      }.entries) {
        final (theme, tones) = e.value;
        for (final ground in <String, Color>{
          'card': theme.colorScheme.surfaceContainerLow,
          'raised': theme.colorScheme.surfaceContainer,
        }.entries) {
          final fill = _over(tones.chipFill(tones.info), ground.value);
          _expectAtLeast(_ratio(tones.info, fill), 4.5, '${e.key} refund strip on ${ground.key}');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // TINTED SURFACES — a whole card carrying a meaning, instead of a chip in its corner.
  //
  // [ToneSurface] paints `tone @ surfaceTintAlpha` over the fill the surface would otherwise
  // have had, which is always `GlassWeight.surfaceOf`: card or well in light, card or raised in
  // dark. Those are the only grounds a tint is composited over, so they are the ones measured.
  group('tinted surfaces — a card that IS its status', () {
    const darkTintBases = <String, Color>{
      'card #15221D': ApnivaasColors.surfaceContainerLow,
      'raised #1B2B25': ApnivaasColors.surfaceContainer,
    };
    const lightTintBases = <String, Color>{
      'card #FFFDF9': ApnivaasColors.card,
      'well #EEF4EF': ApnivaasColors.well,
    };

    Map<String, Color> inksOf(ApnivaasSemantics tones) => {
          'success': tones.success,
          'warning': tones.warning,
          'error': tones.error,
          'info': tones.info,
          'muted': tones.muted,
          'brand': tones.brand,
        };

    void forEachTint(
      ApnivaasSemantics tones,
      Map<String, Color> bases,
      void Function(String name, Color ink, String where, Color tinted) body,
    ) {
      inksOf(tones).forEach((name, ink) {
        bases.forEach((where, base) => body(name, ink, where, tones.tintedSurface(ink, base)));
      });
    }

    test('body and secondary text stay AA on every tint, in both themes', () {
      for (final e in {
        'light': (ApnivaasSemantics.light, lightTintBases,
            [ApnivaasColors.textPrimary, ApnivaasColors.textSecondary]),
        'dark': (ApnivaasSemantics.dark, darkTintBases,
            [ApnivaasColors.onSurface, ApnivaasColors.onSurfaceVariant]),
      }.entries) {
        final (tones, bases, inks) = e.value;
        forEachTint(tones, bases, (name, _, where, tinted) {
          for (final text in inks) {
            _expectAtLeast(_ratio(text, tinted), 4.5,
                '${e.key} ${_hex(text)} on a $name-tinted $where');
          }
        });
      }
    });

    // THE PAIRING THE WHOLE TREATMENT RESTS ON. [StatusWord] draws the status in the tone at
    // full strength directly on the tint — no chip.
    test('the status WORD is AA in its own tone on its own tint, in both themes', () {
      for (final e in {
        'light': (ApnivaasSemantics.light, lightTintBases),
        'dark': (ApnivaasSemantics.dark, darkTintBases),
      }.entries) {
        final (tones, bases) = e.value;
        forEachTint(tones, bases, (name, ink, where, tinted) {
          _expectAtLeast(_ratio(ink, tinted), 4.5, '${e.key} $name word on a tinted $where');
        });
      }
    });

    // ═══ THE RULE, PINNED AS A FAILURE — IN BOTH THEMES NOW ═══
    //
    // Putting a StatusPill back on a tinted card looks like an improvement and is a contrast
    // failure, so the failure itself is asserted. Under the old palette only the dark theme
    // set this rule; the forest palette's darker light inks put the light theme under it too.
    double worstChipOnTint(ApnivaasSemantics tones, Map<String, Color> bases) {
      var worst = double.infinity;
      forEachTint(tones, bases, (name, ink, where, tinted) {
        worst = math.min(worst, _ratio(ink, _over(tones.chipFill(ink), tinted)));
      });
      return worst;
    }

    test('a chip of the SAME tone on a tinted card FAILS AA — hence StatusWord', () {
      for (final e in {
        'light': (ApnivaasSemantics.light, lightTintBases),
        'dark': (ApnivaasSemantics.dark, darkTintBases),
      }.entries) {
        final (tones, bases) = e.value;
        final worst = worstChipOnTint(tones, bases);
        expect(worst, lessThan(4.5),
            reason: '${e.key}: a chip on a tint of its own tone measured '
                '${worst.toStringAsFixed(2)}:1. If this now clears AA, re-derive the rule in '
                'ApnivaasSemantics.surfaceTintAlpha before letting a StatusPill onto a '
                'ToneSurface.');
      }
    });

    test("the dark tint reproduces the dark container colours, byte for byte", () {
      const card = ApnivaasColors.surfaceContainerLow;
      final tones = ApnivaasSemantics.dark;
      expect(_hex(tones.tintedSurface(ApnivaasColors.success, card)),
          _hex(ApnivaasColors.tertiaryContainer));
      expect(_hex(tones.tintedSurface(ApnivaasColors.warning, card)),
          _hex(ApnivaasColors.secondaryContainer));
      expect(_hex(tones.tintedSurface(ApnivaasColors.error, card)),
          _hex(ApnivaasColors.errorContainer));
    });

    test('the light error tint IS the light error container', () {
      expect(_hex(ApnivaasSemantics.light.tintedSurface(ApnivaasColors.error, ApnivaasColors.card)),
          _hex(ApnivaasColors.errorContainerLight));
    });

    test('the tint alpha IS the chip alpha — one weight of colour at two scales', () {
      expect(ApnivaasSemantics.surfaceTintAlpha, ApnivaasSemantics.dark.chipFillAlpha);
      expect(ApnivaasSemantics.surfaceTintAlpha, 0.10);
    });

    test('a tinted surface is OPAQUE, so nothing behind it can change what was measured', () {
      forEachTint(ApnivaasSemantics.dark, darkTintBases, (name, _, where, tinted) {
        expect(tinted.a, 1.0, reason: '$name on $where must not be translucent');
      });
      forEachTint(ApnivaasSemantics.light, lightTintBases, (name, _, where, tinted) {
        expect(tinted.a, 1.0, reason: '$name on $where must not be translucent');
      });
    });

    test('the leading rail clears 3:1 against its base and against its own tint', () {
      for (final e in {
        'light': (ApnivaasSemantics.light, lightTintBases),
        'dark': (ApnivaasSemantics.dark, darkTintBases),
      }.entries) {
        final (tones, bases) = e.value;
        inksOf(tones).forEach((name, ink) {
          bases.forEach((where, base) {
            _expectAtLeast(_ratio(ink, base), 3.0, '${e.key} $name rail on $where');
            _expectAtLeast(_ratio(ink, tones.tintedSurface(ink, base)), 3.0,
                '${e.key} $name rail against its own tint on $where');
          });
        });
      }
      expect(Strokes.rail, Space.xxs);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the panes are FLAT — no blur, and a resting card casts nothing', () {
    test('no blur survives anywhere in the pane layer', () {
      // Grepped rather than reasoned about. Comment lines are stripped first: the file explains
      // at length why the blur is absent, and naming a thing is not using it.
      final code = File('lib/shared/glass/glass.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final banned in ['BackdropFilter', 'ImageFilter', 'dart:ui']) {
        expect(code.contains(banned), isFalse,
            reason: '$banned is back in the pane layer. The owner\'s phone reported "stuck, '
                'lag"; the flat card is the same pixel at zero GPU cost.');
      }
    });

    test('a resting card casts NO shadow — fill and hairline separate it', () {
      // Across all six canvas boards the only shadow under a surface is the chosen persona's.
      expect(Shadows.level1, isEmpty);
      expect(Shadows.level2, isEmpty, reason: 'GlassSurface defaults to this on ~40 call sites');
      // So the edge has to be doing the work: the card is only a fill step off the ground.
      _expectBelowRatio(ApnivaasColors.card, ApnivaasColors.cream, 1.2, 'light card on cream');
      _expectBelowRatio(ApnivaasColors.surfaceContainerLow, ApnivaasColors.ground, 1.2,
          'dark card on its ground');
      _expectAtLeast(_ratio(ApnivaasColors.cardBorder, ApnivaasColors.cream), 1.1,
          'the light hairline against the ground');
      _expectAtLeast(_ratio(ApnivaasColors.outlineVariant, ApnivaasColors.surfaceContainerLow), 1.3,
          'the dark hairline against the card');
    });

    test('the shadows that remain are soft, low and forest — never black on cream', () {
      for (final e in {
        'lift': Shadows.lift,
        'bar': Shadows.bar,
        'level3': Shadows.level3,
        'dialog': Shadows.dialog,
        'glow': Shadows.glow,
      }.entries) {
        expect(e.value, isNotEmpty, reason: '${e.key} is a real elevation');
        for (final s in e.value) {
          final opaque = s.color.withValues(alpha: 1);
          expect([ApnivaasColors.forest, ApnivaasColors.forestDeep], contains(opaque),
              reason: '${e.key} is tinted ${_hex(opaque)}, not the brand');
          // 30% at the most — the FAB's halo, which is 0x4D.
          expect(s.color.a, lessThanOrEqualTo(0x4D / 255),
              reason: '${e.key} is heavier than a whisper');
        }
      }
      // A sheet rises from the bottom edge and casts up; a centred dialog casts down.
      expect(Shadows.level3.every((s) => s.offset.dy < 0), isTrue);
      expect(Shadows.dialog.every((s) => s.offset.dy > 0), isTrue);
    });

    test('the weight ladder: lighter as it rises in dark, a whisper below the card in light', () {
      final dark = ApnivaasTheme.dark().colorScheme;
      expect(GlassWeight.thin.surfaceOf(dark), ApnivaasColors.surfaceContainerLow);
      expect(GlassWeight.regular.surfaceOf(dark), ApnivaasColors.surfaceContainer);
      expect(GlassWeight.thick.surfaceOf(dark), ApnivaasColors.surfaceContainerHigh);
      var previous = _luminance(ApnivaasColors.ground);
      for (final w in GlassWeight.values) {
        final l = _luminance(w.surfaceOf(dark));
        expect(l, greaterThanOrEqualTo(previous), reason: '${w.name} sits BELOW the rung under it');
        previous = l;
      }

      final light = ApnivaasTheme.light().colorScheme;
      expect(GlassWeight.thin.surfaceOf(light), ApnivaasColors.card);
      expect(GlassWeight.regular.surfaceOf(light), ApnivaasColors.well);
      expect(GlassWeight.thick.surfaceOf(light), ApnivaasColors.card,
          reason: 'a sheet reads as a card lifted out, not as a tint');
      expect(_luminance(ApnivaasColors.well), lessThan(_luminance(ApnivaasColors.card)));
      _expectBelowRatio(ApnivaasColors.well, ApnivaasColors.card, 1.15,
          'the well is a whisper below the card, not a grey band');
    });

    test('a skeleton is quiet on purpose — seen, but not something to read', () {
      for (final e in {
        'on the card': (ApnivaasColors.skeleton, ApnivaasColors.card),
        'on the ground': (ApnivaasColors.skeletonOnGround, ApnivaasColors.cream),
      }.entries) {
        final (block, ground) = e.value;
        _expectAtLeast(_ratio(block, ground), 1.1, 'a skeleton block ${e.key}');
        _expectBelowRatio(block, ground, 1.4, 'a skeleton block ${e.key}');
      }
    });

    testWidgets('a dark pane edge is the dark hairline, and the light one is visible',
        (tester) async {
      late Color edge;
      await tester.pumpWidget(MaterialApp(
        theme: ApnivaasTheme.dark(),
        home: Builder(builder: (c) {
          edge = GlassSurface.edgeColor(c);
          return const SizedBox.shrink();
        }),
      ));
      expect(edge, ApnivaasColors.outlineVariant);

      late Color lightPaneEdge;
      await tester.pumpWidget(MaterialApp(
        theme: ApnivaasTheme.light(),
        home: Builder(builder: (c) {
          lightPaneEdge = GlassSurface.edgeColor(c);
          return const SizedBox.shrink();
        }),
      ));
      final pane = GlassWeight.thin.surfaceOf(ApnivaasTheme.light().colorScheme);
      expect(_ratio(_over(lightPaneEdge, pane), pane), greaterThan(1.2),
          reason: 'the light pane edge has gone back to being invisible');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the component themes carry the design', () {
    final light = ApnivaasTheme.light();
    final dark = ApnivaasTheme.dark();

    test('the filled button: forest and white in light, Mist and forest in dark', () {
      // In both it is the single most contrasty object on the screen.
      for (final e in {
        'light': (light, ApnivaasColors.forest, const Color(0xFFFFFFFF), ApnivaasColors.card),
        'dark': (dark, ApnivaasColors.mist, ApnivaasColors.forest, ApnivaasColors.surfaceContainerLow),
      }.entries) {
        final (theme, bg, fg, card) = e.value;
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor!.resolve({}), bg);
        expect(style.foregroundColor!.resolve({}), fg);
        _expectAtLeast(_ratio(fg, bg), 7.0, '${e.key} filled button label');
        _expectAtLeast(_ratio(bg, card), 7.0, '${e.key} filled button against the card');
      }
      final style = light.filledButtonTheme.style!;
      expect(style.backgroundColor!.resolve({WidgetState.pressed}), ApnivaasColors.forestPressed);
      expect(style.backgroundColor!.resolve({WidgetState.disabled}), ApnivaasColors.track);
    });

    test('the filled button geometry: 52dp, a 16-18dp corner, Outfit 16-17 at 600', () {
      final style = light.filledButtonTheme.style!;
      final min = style.minimumSize!.resolve({})!;
      expect(min.height, inInclusiveRange(52, 56));
      final shape = style.shape!.resolve({})! as RoundedRectangleBorder;
      final radius = (shape.borderRadius as BorderRadius).topLeft.x;
      expect(radius, inInclusiveRange(16, 18));
      final text = style.textStyle!.resolve({})!;
      expect(text.fontFamily, ApnivaasType.display);
      expect(text.fontWeight, FontWeight.w600);
      expect(text.fontSize, inInclusiveRange(16, 17));
      // Focus is a ring, never colour alone.
      expect(style.side!.resolve({WidgetState.focused})!.width, Strokes.focus);
    });

    test('outlined and text buttons are the brand, and every button is at least 48dp', () {
      final outlined = light.outlinedButtonTheme.style!;
      expect(outlined.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
      expect(outlined.side!.resolve({})!.color, ApnivaasColors.forest);
      expect(outlined.foregroundColor!.resolve({}), ApnivaasColors.forest);
      final text = light.textButtonTheme.style!;
      expect(text.minimumSize!.resolve({})!.height, greaterThanOrEqualTo(48));
      expect(text.foregroundColor!.resolve({}), ApnivaasColors.forest);
      final icon = light.iconButtonTheme.style!;
      expect(icon.minimumSize!.resolve({})!.shortestSide, greaterThanOrEqualTo(48));
      expect(light.materialTapTargetSize, MaterialTapTargetSize.padded);
    });

    test('a text field: the card fill, a 1.5px 3:1 border, a 2px forest focus', () {
      final input = light.inputDecorationTheme;
      expect(input.filled, isTrue);
      expect(input.fillColor, ApnivaasColors.card);
      final enabled = input.enabledBorder! as OutlineInputBorder;
      expect(enabled.borderSide.color, ApnivaasColors.controlBorder);
      expect(enabled.borderSide.width, Strokes.control);
      expect(enabled.borderRadius, Radii.rControl);
      final focused = input.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, ApnivaasColors.forest);
      expect(focused.borderSide.width, Strokes.focus);
      expect((input.errorBorder! as OutlineInputBorder).borderSide.color, ApnivaasColors.errorInk);
    });

    test('hint text and the input border are measured against the FIELD FILL', () {
      for (final e in {
        'light': (light, ApnivaasColors.card),
        'dark': (dark, ApnivaasColors.surfaceContainerHigh),
      }.entries) {
        final (theme, fill) = e.value;
        expect(theme.inputDecorationTheme.fillColor, fill);
        _expectAtLeast(_ratio(theme.inputDecorationTheme.hintStyle!.color!, fill), 4.5,
            '${e.key} hint on the field');
        final border =
            (theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder).borderSide.color;
        _expectAtLeast(_ratio(border, fill), 3.0, '${e.key} input border');
      }
    });

    test('a card: the card fill, a 20-24dp corner, a hairline and no elevation', () {
      final card = light.cardTheme;
      expect(card.color, ApnivaasColors.card);
      expect(card.elevation, 0);
      final shape = card.shape! as RoundedRectangleBorder;
      expect((shape.borderRadius as BorderRadius).topLeft.x, inInclusiveRange(20, 24));
      expect(shape.side.color, ApnivaasColors.cardBorder);
      expect(shape.side.width, Strokes.hairline);
    });

    test('a chip is a pill, and a chosen chip changes fill AND edge', () {
      final chip = light.chipTheme;
      expect(chip.shape, isA<StadiumBorder>());
      final side = chip.side! as WidgetStateBorderSide;
      final idle = side.resolve({})!.color;
      final chosen = side.resolve({WidgetState.selected})!.color;
      expect(idle, ApnivaasColors.controlBorder);
      expect(chosen, isNot(idle), reason: 'a selected chip must not be colour alone');
      expect(chip.color!.resolve({WidgetState.selected}), ApnivaasColors.forest);
    });

    test('a sheet: a 28dp top, a grip that clears 3:1, the brand barrier', () {
      for (final theme in [light, dark]) {
        final sheet = theme.bottomSheetTheme;
        final shape = sheet.shape! as RoundedRectangleBorder;
        expect((shape.borderRadius as BorderRadius).topLeft.x, 28);
        expect(sheet.showDragHandle, isTrue);
        final surface = GlassWeight.thick.surfaceOf(theme.colorScheme);
        _expectAtLeast(_ratio(sheet.dragHandleColor!, surface), 3.0,
            '${theme.brightness.name} drag handle');
      }
      expect(light.bottomSheetTheme.modalBarrierColor, ApnivaasColors.scrim);
    });

    test('a dialog and a date picker share the hero corner and the brand barrier', () {
      final dialog = light.dialogTheme;
      expect((dialog.shape! as RoundedRectangleBorder).borderRadius, Radii.rHero);
      expect(dialog.barrierColor, ApnivaasColors.scrim);
      expect(light.datePickerTheme.headerForegroundColor, ApnivaasColors.headerTitle);
    });

    test('the snackbar is ink on cream, inverted in dark, and both inks read', () {
      for (final e in {
        'light': (light, ApnivaasColors.ink),
        'dark': (dark, ApnivaasColors.onSurface),
      }.entries) {
        final (theme, bg) = e.value;
        final snack = theme.snackBarTheme;
        expect(snack.backgroundColor, bg);
        expect(snack.behavior, SnackBarBehavior.floating);
        _expectAtLeast(_ratio(snack.contentTextStyle!.color!, bg), 4.5, '${e.key} snackbar text');
        _expectAtLeast(_ratio(snack.actionTextColor!, bg), 4.5, '${e.key} snackbar action');
      }
    });

    test('the AppBar is cream and ink, flat, and sets the status bar', () {
      for (final theme in [light, dark]) {
        final bar = theme.appBarTheme;
        expect(bar.backgroundColor, theme.scaffoldBackgroundColor);
        expect(bar.foregroundColor, theme.colorScheme.onSurface);
        expect(bar.elevation, 0);
        expect(bar.scrolledUnderElevation, 0);
        expect(bar.surfaceTintColor, Colors.transparent);
        expect(bar.systemOverlayStyle, ApnivaasTheme.systemBars(theme.brightness));
      }
    });

    test('the fallback navigation bar reads: both label states AA on the bar, 64-72dp tall', () {
      for (final theme in [dark, light]) {
        final label = theme.brightness.name;
        final nav = theme.navigationBarTheme;
        final bar = nav.backgroundColor!;
        expect(bar, theme.colorScheme.surface, reason: 'the tab bar is the card');
        expect(nav.height, inInclusiveRange(64, 72));
        for (final states in [<WidgetState>{}, {WidgetState.selected}]) {
          final style = nav.labelTextStyle!.resolve(states)!;
          _expectAtLeast(_ratio(style.color!, bar), 4.5, '$label nav label $states');
        }
        _expectAtLeast(
          _ratio(theme.colorScheme.primary, _over(nav.indicatorColor!, bar)),
          4.5,
          '$label active nav label on its own pill',
        );
      }
    });

    test('the FAB is the filled button\'s colours, and its label reads on it', () {
      for (final theme in [light, dark]) {
        final fab = theme.floatingActionButtonTheme;
        expect(fab.backgroundColor, theme.filledButtonTheme.style!.backgroundColor!.resolve({}));
        _expectAtLeast(_ratio(fab.foregroundColor!, fab.backgroundColor!), 4.5,
            '${theme.brightness.name} FAB label');
        expect(fab.elevation, 0);
      }
    });

    test('a progress fill reads on its track', () {
      expect(light.progressIndicatorTheme.linearTrackColor, ApnivaasColors.track);
      for (final theme in [dark, light]) {
        final p = theme.progressIndicatorTheme;
        _expectAtLeast(_ratio(p.color!, p.linearTrackColor!), 3.0,
            '${theme.brightness.name} progress on its track');
      }
    });

    test('a list tile speaks the scale', () {
      final tile = light.listTileTheme;
      // Compared by what is drawn: ThemeData merges its text theme over the platform's, so the
      // slot it hands back is not the identical object the tile theme was given.
      for (final (tileStyle, slot) in [
        (tile.titleTextStyle!, light.textTheme.titleMedium!),
        (tile.subtitleTextStyle!, light.textTheme.bodySmall!),
      ]) {
        expect(tileStyle.fontFamily, slot.fontFamily);
        expect(tileStyle.fontSize, slot.fontSize);
        expect(tileStyle.fontWeight, slot.fontWeight);
      }
      expect(tile.selectedColor, ApnivaasColors.forest);
    });

    test('page transitions: fade-forwards on Android, the native slide on iOS', () {
      final builders = light.pageTransitionsTheme.builders;
      expect(builders[TargetPlatform.android], isA<FadeForwardsPageTransitionsBuilder>());
      expect(builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
    });

    test('both extensions are registered on both themes', () {
      expect(dark.extension<ApnivaasSemantics>(), ApnivaasSemantics.dark);
      expect(light.extension<ApnivaasSemantics>(), ApnivaasSemantics.light);
      expect(light.extension<ApnivaasTextRoles>(), isNotNull);
      expect(dark.extension<ApnivaasTextRoles>(), isNotNull);
      expect(light.extension<ApnivaasTextRoles>()!.cta.color, ApnivaasColors.ink);
    });

    test('the system bars follow the theme, and their icons are the OPPOSITE of its ground', () {
      final darkBars = ApnivaasTheme.systemBars(Brightness.dark);
      expect(darkBars.statusBarIconBrightness, Brightness.light);
      expect(darkBars.systemNavigationBarIconBrightness, Brightness.light);
      final lightBars = ApnivaasTheme.systemBars(Brightness.light);
      expect(lightBars.statusBarIconBrightness, Brightness.dark,
          reason: 'dark icons over the cream ground');
      expect(lightBars.systemNavigationBarIconBrightness, Brightness.dark);
      for (final s in <SystemUiOverlayStyle>[darkBars, lightBars]) {
        expect(s.statusBarColor, Colors.transparent);
        expect(s.systemNavigationBarColor, Colors.transparent);
        expect(s.systemNavigationBarContrastEnforced, isFalse);
      }
      // Over the forest header the icons are light in either theme.
      expect(ApnivaasTheme.onForest.statusBarIconBrightness, Brightness.light);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('typography — Outfit and Manrope, and the bundle is real', () {
    final text = ApnivaasType.textTheme(ApnivaasColors.ink, ApnivaasColors.inkMuted);

    test('the pubspec declares exactly the two families, and nothing in the folder ships loose',
        () {
      final declared = _declaredFonts();
      expect(declared.keys.toSet(), {ApnivaasType.display, ApnivaasType.family});
      expect(declared[ApnivaasType.display], {
        'google_fonts/Outfit-Medium.ttf': 500,
        'google_fonts/Outfit-SemiBold.ttf': 600,
        'google_fonts/Outfit-Bold.ttf': 700,
      });
      expect(declared[ApnivaasType.family], {
        'google_fonts/Manrope-Regular.ttf': 400,
        'google_fonts/Manrope-Medium.ttf': 500,
        'google_fonts/Manrope-SemiBold.ttf': 600,
        'google_fonts/Manrope-Bold.ttf': 700,
      });
      // `fonts:` bundles the files it names. Declaring the folder as an asset as well would
      // ship whatever else sits in it — today, the four Inter files kept for a script.
      final pubspec = File('pubspec.yaml').readAsLinesSync();
      expect(pubspec.where((l) => l.trim() == '- google_fonts/'), isEmpty);
      expect(pubspec.any((l) => l.contains('family: Inter')), isFalse);
    });

    test('the test runner registers the same seven files the pubspec declares', () {
      // flutter_test_config.dart loads the faces for every test; if it drifted from the pubspec
      // every layout test would be measuring a typeface nobody ships.
      final declared = _declaredFonts().map((k, v) => MapEntry(k, v.keys.toSet()));
      expect(appFonts.map((k, v) => MapEntry(k, v.toSet())), declared);
    });

    test('SEVEN FILES, SEVEN WEIGHTS, SEVEN DIFFERENT FACES', () {
      // Filenames prove nothing; the tables do.
      final seen = <String, Uint8List>{};
      _declaredFonts().forEach((family, files) {
        files.forEach((path, weight) {
          final f = File(path);
          expect(f.existsSync(), isTrue, reason: '$path is declared and missing');
          final face = _sfnt(f);
          expect(face.weightClass, weight,
              reason: '$path declares usWeightClass ${face.weightClass}, not $weight');
          expect(face.hasFvar, isFalse,
              reason: '$path is a VARIABLE font, which renders at its default weight here');
          seen[path] = face.glyf;
        });
      });
      expect(seen, hasLength(7));
      final names = seen.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final a = seen[names[i]]!;
          final b = seen[names[j]]!;
          final identical = a.length == b.length &&
              List.generate(a.length, (k) => a[k] == b[k]).every((x) => x);
          expect(identical, isFalse,
              reason: '${names[i]} and ${names[j]} are the same face shipped twice');
        }
      }
    });

    test('Manrope draws the rupee at every weight; Outfit has none, so it falls back', () {
      _declaredFonts().forEach((family, files) {
        for (final path in files.keys) {
          final face = _sfnt(File(path));
          expect(face.hasRupee, family == ApnivaasType.family,
              reason: family == ApnivaasType.family
                  ? '$path has lost U+20B9 — every amount in the app is in rupees'
                  : '$path has gained U+20B9; the Manrope fallback on Outfit styles can go');
          expect(face.gsubFeatures, contains('tnum'),
              reason: '$path has no tabular figures, so a refreshing amount would jitter');
        }
      });
      for (final style in _allSlots(text).where((s) => s.fontFamily == ApnivaasType.display)) {
        expect(style.fontFamilyFallback, [ApnivaasType.family],
            reason: 'an Outfit slot without the Manrope fallback draws ₹ as a missing glyph');
      }
    });

    test('the engine resolves each family and weight to a real, distinct face', () {
      // In the test binding's stand-in font every glyph is one em wide, so 'Try again' at 15px
      // measures 135. A real face is far narrower — and a bold one wider than a regular one,
      // which only happens if the weight picked a different file.
      final stand = _widthOf('Try again', const TextStyle(fontFamily: 'NotAFace', fontSize: 15));
      for (final family in [ApnivaasType.family, ApnivaasType.display]) {
        final weights = _bundledWeights[family]!.toList()..sort((a, b) => a.value - b.value);
        final widths = [
          for (final w in weights)
            _widthOf('Try again', TextStyle(fontFamily: family, fontSize: 15, fontWeight: w)),
        ];
        for (final w in widths) {
          expect(w, lessThan(stand * 0.75), reason: '$family did not load: measured $w');
        }
        expect(widths.last, greaterThan(widths.first),
            reason: '$family ${weights.last} drew no wider than ${weights.first}; the weights '
                'resolve to one face');
      }
      // The ₹ in an Outfit style is Manrope's ₹, at the same weight.
      final outfitRupee = _widthOf('₹', ApnivaasType.outfit(20, 24, FontWeight.w600, Colors.black));
      final manropeRupee =
          _widthOf('₹', ApnivaasType.manrope(20, 24, FontWeight.w600, Colors.black));
      expect(outfitRupee, closeTo(manropeRupee, 0.01));
    });

    test('every slot is one of the two families, at a weight that family ships', () {
      for (final style in _allSlots(text)) {
        expect(_bundledWeights.keys, contains(style.fontFamily),
            reason: 'a third family is back in the scale: ${style.fontFamily}');
        expect(_bundledWeights[style.fontFamily]!, contains(style.fontWeight),
            reason: '${style.fontFamily} ${style.fontWeight} is not bundled');
      }
    });

    test('the theme never touches google_fonts, so nothing can download', () {
      for (final f in Directory('lib/core/theme').listSync().whereType<File>()) {
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('google_fonts'), isFalse, reason: '${f.path} imports google_fonts');
        expect(code.contains("'Inter"), isFalse, reason: '${f.path} still names Inter');
      }
    });

    test('the scale is the design\'s, step for step', () {
      const d = ApnivaasType.display;
      const m = ApnivaasType.family;
      const expected = <String, (String, double, double, FontWeight)>{
        'displayLarge': (d, 28, 32, FontWeight.w700),
        'headlineLarge': (d, 28, 32, FontWeight.w700),
        'displayMedium': (d, 28, 32, FontWeight.w600),
        'displaySmall': (d, 22, 28, FontWeight.w600),
        'headlineMedium': (d, 22, 28, FontWeight.w700),
        'titleLarge': (d, 20, 26, FontWeight.w600),
        'headlineSmall': (d, 18, 24, FontWeight.w600),
        'titleMedium': (m, 14, 20, FontWeight.w700),
        'titleSmall': (m, 13, 18, FontWeight.w700),
        'bodyLarge': (m, 15, 22, FontWeight.w400),
        'bodyMedium': (m, 13, 18, FontWeight.w400),
        'bodySmall': (m, 12, 16, FontWeight.w400),
        'labelLarge': (m, 15, 20, FontWeight.w700),
        'labelMedium': (m, 12, 16, FontWeight.w700),
        'labelSmall': (m, 11, 14, FontWeight.w700),
      };
      final actual = _namedSlots(text);
      expected.forEach((slot, spec) {
        final (family, size, line, weight) = spec;
        final s = actual[slot]!;
        expect(s.fontFamily, family, reason: '$slot family');
        expect(s.fontSize, size, reason: '$slot size');
        expect(s.fontSize! * s.height!, closeTo(line, 0.001), reason: '$slot line height');
        expect(s.fontWeight, weight, reason: '$slot weight');
      });
      for (final s in actual.values) {
        expect(s.fontSize, greaterThanOrEqualTo(11), reason: 'nothing in the scale is under 11');
      }
    });

    test('the type roles outside the slots', () {
      final roles = ApnivaasTextRoles.of(ApnivaasColors.ink);
      for (final e in <String, (TextStyle, String, double, FontWeight)>{
        'cta': (roles.cta, ApnivaasType.display, 17, FontWeight.w600),
        'tileTitle': (roles.tileTitle, ApnivaasType.display, 17, FontWeight.w600),
        'heroHeadline': (roles.heroHeadline, ApnivaasType.display, 24, FontWeight.w600),
        'dateNumeral': (roles.dateNumeral, ApnivaasType.display, 19, FontWeight.w600),
        'fieldValue': (roles.fieldValue, ApnivaasType.family, 15, FontWeight.w500),
        'formSection': (roles.formSection, ApnivaasType.display, 15, FontWeight.w600),
        'statValue': (roles.statValue, ApnivaasType.display, 28, FontWeight.w700),
      }.entries) {
        final (style, family, size, weight) = e.value;
        expect(style.fontFamily, family, reason: e.key);
        expect(style.fontSize, size, reason: e.key);
        expect(style.fontWeight, weight, reason: e.key);
      }
    });

    test('sentence case: only the hero tightens and the smallest label opens up', () {
      expect(text.displayLarge!.letterSpacing, closeTo(-0.2, 1e-9));
      expect(text.labelSmall!.letterSpacing, closeTo(0.2, 1e-9));
      for (final e in _namedSlots(text).entries) {
        if (e.key == 'displayLarge' || e.key == 'headlineLarge' || e.key == 'labelSmall') continue;
        expect(e.value.letterSpacing, 0, reason: '${e.key} carries tracking');
      }
    });

    test('every slot that can hold a figure uses tabular figures', () {
      final roles = ApnivaasTextRoles.of(ApnivaasColors.ink);
      final numeric = <String, TextStyle>{
        'displayLarge': text.displayLarge!,
        'headlineLarge': text.headlineLarge!,
        'headlineMedium': text.headlineMedium!,
        'headlineSmall': text.headlineSmall!,
        'titleSmall': text.titleSmall!,
        'labelSmall': text.labelSmall!,
        'statValue': roles.statValue,
        'dateNumeral': roles.dateNumeral,
      };
      numeric.forEach((slot, style) {
        expect(style.fontFeatures?.map((f) => f.feature), contains('tnum'),
            reason: '$slot holds numbers and will jitter as they refresh');
      });
      expect(ApnivaasType.tabular(text.bodyMedium!).fontFeatures!.map((f) => f.feature),
          contains('tnum'));
    });

    test('weight() moves the weight and keeps the family — the engine picks the face', () {
      final base = text.bodyMedium!;
      final moved = ApnivaasType.weight(base, FontWeight.w700);
      expect(moved.fontWeight, FontWeight.w700);
      expect(moved.fontFamily, base.fontFamily);
      expect(moved.fontSize, base.fontSize);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('rhythm', () {
    test('spacing is a 4dp scale with two named half-steps', () {
      const scale = [
        Space.xxs, Space.xs, Space.sm, Space.md,
        Space.lg, Space.xl, Space.xxl, Space.xxxl, Space.huge,
      ];
      for (final v in scale) {
        expect(v % 4, 0, reason: '$v is off the 4dp grid');
      }
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
      expect(Space.hair, 2.0);
      expect(Space.tight, 6.0);
      expect(Space.md, 16.0, reason: 'the dashboard gutter');
      expect(Space.lg, 20.0, reason: 'the auth and form gutter');
    });

    test('the corners: cards 20-24, sheets 28, buttons 16-18, chips a pill', () {
      expect(Radii.card, inInclusiveRange(20, 24));
      expect(Radii.surface, inInclusiveRange(20, 24));
      expect(Radii.card, lessThanOrEqualTo(Radii.surface));
      expect(Radii.sheet, 28);
      expect(Radii.hero, 28);
      expect(Radii.button, inInclusiveRange(16, 18));
      expect(Radii.buttonLarge, inInclusiveRange(16, 18));
      expect(Radii.pill, greaterThanOrEqualTo(999));
      // Small to large, so nothing is rounder than the thing it sits in.
      const ladder = [
        Radii.check, Radii.tiny, Radii.control, Radii.button, Radii.buttonLarge,
        Radii.card, Radii.well, Radii.surface, Radii.sheet, Radii.header,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i], greaterThanOrEqualTo(ladder[i - 1]), reason: 'step $i');
      }
      expect(Radii.rSheetTop.topLeft.x, Radii.sheet);
      expect(Radii.rSheetTop.bottomLeft.x, 0);
    });

    test('every border is one hairline; a control and a focus ring thicken', () {
      expect(Strokes.hairline, 1.0);
      expect(Strokes.control, 1.5);
      expect(Strokes.glyph, 1.5);
      expect(Strokes.focus, 2.0);
    });

    test('the dims are the design\'s own numbers', () {
      expect(Dim.readOnly, 0.45);
      expect(Dim.skeletonPulse, inExclusiveRange(0, 1));
      expect(Dim.skeletonStill, inExclusiveRange(Dim.skeletonPulse, 1));
    });

    test('motion stays inside the 150–350ms band, and the press is quicker than any of it', () {
      for (final d in [Motion.fast, Motion.base, Motion.slow, Motion.exit]) {
        expect(d.inMilliseconds, inInclusiveRange(150, 350));
      }
      expect(Motion.press, lessThan(Motion.fast));
      expect(Motion.fast, lessThan(Motion.base));
      expect(Motion.base, lessThan(Motion.slow));
      expect(Motion.staggerCap * Motion.stagger.inMilliseconds, lessThanOrEqualTo(350),
          reason: 'a capped stagger still reads as one movement');
    });

    test('glyphs are small and the clay sizes are a single ladder', () {
      const glyphs = [IconSize.xs, IconSize.sm, IconSize.md, IconSize.lg, IconSize.action];
      for (var i = 1; i < glyphs.length; i++) {
        expect(glyphs[i], greaterThan(glyphs[i - 1]));
      }
      const clay = [
        ClaySize.navOff, ClaySize.nav, ClaySize.list, ClaySize.action, ClaySize.tile,
        ClaySize.banner, ClaySize.hero, ClaySize.promo, ClaySize.persona, ClaySize.heroArt,
      ];
      for (var i = 1; i < clay.length; i++) {
        expect(clay[i], greaterThan(clay[i - 1]), reason: 'clay step $i');
      }
      expect(ClaySize.action, inInclusiveRange(48, 56), reason: 'a quick-action icon');
      expect(ClaySize.promo, 96, reason: 'an empty state');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the pane layer behaves', () {
    testWidgets('nesting panes more than one deep trips the assert', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ApnivaasTheme.dark(),
          home: const GlassSurface(
            child: GlassSurface(
              child: GlassSurface(child: SizedBox(width: 10, height: 10)),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isAssertionError,
          reason: 'the nesting guard is the only thing stopping a screen exhausting the ramp');
    });

    testWidgets('a stat card is flat by default and elevated only when asked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ApnivaasTheme.dark(),
          home: const Scaffold(
            body: Column(
              children: [
                GlassStatCard(label: 'Occupied', value: '42'),
                GlassStatCard(label: 'Collected', value: '0', emphasised: true),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(FlatSurface), findsOneWidget);
      expect(find.byType(GlassSurface), findsOneWidget);
    });

    testWidgets('a pane paints its weight\'s surface, flat and opaque', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ApnivaasTheme.dark(),
          home: const Scaffold(
            body: Center(
              child: GlassSurface(weight: GlassWeight.thick, child: SizedBox(width: 100, height: 40)),
            ),
          ),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(GlassSurface), matching: find.byType(DecoratedBox)).first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, ApnivaasColors.surfaceContainerHigh);
      expect(d.color!.a, 1.0, reason: 'a pane fill with alpha is the old translucent model');
      expect(d.boxShadow, isEmpty, reason: 'a resting pane casts nothing');
      expect((d.border! as Border).top.color, ApnivaasColors.outlineVariant);
    });

    testWidgets('a tappable pane still shows its ink, now that the fill is opaque',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ApnivaasTheme.dark(),
          home: Scaffold(
            body: Center(
              child: GlassCard(onTap: () {}, child: const SizedBox(width: 100, height: 40)),
            ),
          ),
        ),
      );
      final inkWell = find.byType(InkWell);
      expect(inkWell, findsOneWidget);
      final fill = find.descendant(of: find.byType(GlassCard), matching: find.byType(DecoratedBox));
      expect(tester.getTopLeft(inkWell).dy, greaterThanOrEqualTo(tester.getTopLeft(fill.first).dy),
          reason: 'the InkWell is outside the pane fill and its splash will be hidden');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the owner\'s state layer', () {
    testWidgets('a state card is the RAISED surface with a badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ApnivaasTheme.dark(),
          home: const Scaffold(
            body: StateCard(badge: 'Error', child: SizedBox(width: 100, height: 20)),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(StateCard), matching: find.byType(Material)).first,
      );
      expect(material.color, ApnivaasColors.surfaceContainer);
      expect(find.byType(StateBadge), findsOneWidget);
    });

    // THE SKELETON THE SCREENS ACTUALLY DRAW. These four used to hold the owner's old dark
    // skeleton bar to account — a widget no screen drew any more, which painted the dark fill on
    // the cream theme. They now hold the clay skeleton (shared/clay/skeleton.dart) to the same
    // promises: the right block for the ground it sits on, a pulse that stops when nobody can
    // see it, a still placeholder under reduce motion, and blocks that read against their card.
    testWidgets('a skeleton block is the warm beige on a card, its own shade on the page, and '
        'the dark ladder\'s brightest fill in dark', (tester) async {
      Future<Color> fill(ThemeData theme, {bool onGround = false}) async {
        // A fresh app each time: a MaterialApp handed a new theme ANIMATES to it, and the first
        // frame after the swap would still be the old theme's.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(body: Center(child: Skeleton(width: 50, onGround: onGround))),
        ));
        final box = tester.widget<Container>(
          find.descendant(of: find.byType(Skeleton), matching: find.byType(Container)).first,
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(_hex(await fill(ApnivaasTheme.light())), _hex(ApnivaasColors.skeleton));
      expect(_hex(await fill(ApnivaasTheme.light(), onGround: true)),
          _hex(ApnivaasColors.skeletonOnGround));
      expect(_hex(await fill(ApnivaasTheme.dark())), _hex(ApnivaasColors.surfaceBright));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a skeleton STOPS when it goes off-screen, and nothing ticks after it',
        (tester) async {
      // An IndexedStack lays its other children out and keeps them alive but never PAINTS them,
      // so a naive pulse keeps burning frames on a tab nobody can see. The clay pulse reads
      // [Visibility.of], which the IndexedStack answers false for every child it is not showing.
      // The switch is made without a tap, so no ink ripple is left animating to muddy the count.
      var selected = 0;
      late StateSetter select;
      await tester.pumpWidget(MaterialApp(
        theme: ApnivaasTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            select = setState;
            return IndexedStack(
              index: selected,
              children: const [
                Center(child: Skeleton(width: 50)),
                SizedBox.shrink(),
              ],
            );
          }),
        ),
      ));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0),
          reason: 'a visible skeleton animates');

      select(() => selected = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(Skeleton, skipOffstage: false), findsOneWidget,
          reason: 'the hidden tab is kept alive, skeleton and all');
      expect(tester.binding.transientCallbackCount, 0,
          reason: 'the skeleton is laid out but no longer painted, and kept pulsing');
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'nothing is animating, so nothing should be scheduling frames');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reduced motion stops the pulse without hiding the placeholder', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: Skeleton(width: 50))),
        ),
      ));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byType(Skeleton), findsOneWidget);
      final still = tester.widget<Opacity>(
        find.descendant(of: find.byType(SkeletonPulse), matching: find.byType(Opacity)).first,
      );
      expect(still.opacity, Dim.skeletonStill, reason: 'held still at 80%, never faded out');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a list skeleton puts its blocks on the CARD fill, and they read against it',
        (tester) async {
      for (final theme in [ApnivaasTheme.light(), ApnivaasTheme.dark()]) {
        await tester.pumpWidget(const SizedBox.shrink()); // a fresh app: see the first test
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(body: ListSkeleton()),
        ));
        final card = tester.widget<DecoratedBox>(
          find.descendant(of: find.byType(ListSkeleton), matching: find.byType(DecoratedBox)).first,
        );
        final cardFill = (card.decoration as BoxDecoration).color!;
        expect(cardFill, theme.colorScheme.surface);
        final block = tester.widget<Container>(
          find.descendant(of: find.byType(Skeleton), matching: find.byType(Container)).first,
        );
        final blockFill = (block.decoration! as BoxDecoration).color!;
        _expectAtLeast(_ratio(blockFill, cardFill), 1.1,
            'a skeleton block against the card it sits on (${theme.brightness.name})');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// Every slot the scale defines, by name.
Map<String, TextStyle> _namedSlots(TextTheme t) => {
      'displayLarge': t.displayLarge!,
      'displayMedium': t.displayMedium!,
      'displaySmall': t.displaySmall!,
      'headlineLarge': t.headlineLarge!,
      'headlineMedium': t.headlineMedium!,
      'headlineSmall': t.headlineSmall!,
      'titleLarge': t.titleLarge!,
      'titleMedium': t.titleMedium!,
      'titleSmall': t.titleSmall!,
      'bodyLarge': t.bodyLarge!,
      'bodyMedium': t.bodyMedium!,
      'bodySmall': t.bodySmall!,
      'labelLarge': t.labelLarge!,
      'labelMedium': t.labelMedium!,
      'labelSmall': t.labelSmall!,
    };

/// Every slot the scale defines, for the checks that apply to all of them.
List<TextStyle> _allSlots(TextTheme t) => _namedSlots(t).values.toList();
