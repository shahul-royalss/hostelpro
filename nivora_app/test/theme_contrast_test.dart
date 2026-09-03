import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/core/theme/typography.dart';
import 'package:mobile/features/owner/widgets/states.dart';
import 'package:mobile/shared/glass/glass.dart';

/// The design system, held to its own numbers.
///
/// Three jobs, and they are different:
///
/// 1. **The dark scheme IS the design.** Every hex in it was read out of Figma file
///    `8qkhZArLAz9KVOIiWF8ZTG`, so the first group below pins them literally. If one of those
///    tests fails, either somebody adjusted the design by eye in Dart — which is the wrong
///    place to adjust it — or Figma changed and `design-figma/DESIGN-SYSTEM.md` needs
///    re-exporting first. The light scheme is not drawn at all; it is `fromSeed` output, and
///    the second group re-derives it to prove the pinned consts have not become hand-picked.
///
/// 2. **Contrast is measurable, so it is measured.** tokens.dart quotes a ratio next to almost
///    every colour. Comments rot; these do not, because every one is recomputed here from the
///    token itself. A colour nudged by eye fails with the number it actually measured. Three
///    design values could not carry their own contrast and were lifted along their own hue;
///    the tests below pin how far each moved, so "lifted minimally" stays true.
///
/// 3. **The font bundle is checked, not assumed.** This project has twice shipped
///    byte-identical files under different weight names, which registers N copies of the same
///    400 face and makes every heading render regular while the pubspec looks correct. The
///    typography group reads the five `.ttf` files off disk and proves they are five different
///    faces at five different weights.
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

// ── THE SURFACES A COLOUR CAN LAND ON ────────────────────────────────────────────────────
//
// Split in two on purpose, and the split is the contract:
//
//   *Surfaces  — everything, including the light input fill and the dark `surface-bright`.
//                TEXT tokens must be AA on all of these, because a hint sits on the fill and
//                a label can land on a badge.
//   *Grounds   — the rungs a CHIP can sit on. In the dark theme that is three, because the
//                design's sheet and input fill ARE the raised surface; `surface-bright` is
//                excluded because nothing paints a chip on a skeleton bar or an icon badge,
//                and a 10% chip there measures 4.16:1.
//
// Keys carry the hex so a failure names the surface rather than an index.
const _lightSurfaces = <String, Color>{
  'canvas #FFF8F3': NivoraColors.background,
  'card #FFFFFF': NivoraColors.surface,
  'sheet #F1E7D9': NivoraColors.lightSheet,
  'field #EBE1D4': NivoraColors.lightField,
};
const _lightGrounds = _lightSurfaces;

const _darkSurfaces = <String, Color>{
  'ground #0B0D0F': NivoraColors.ground,
  'card #111417': NivoraColors.surfaceContainerLow,
  'raised #171A1E': NivoraColors.surfaceContainer,
  'bright #1D2227': NivoraColors.surfaceBright,
};
const _darkGrounds = <String, Color>{
  'ground #0B0D0F': NivoraColors.ground,
  'card #111417': NivoraColors.surfaceContainerLow,
  'raised #171A1E': NivoraColors.surfaceContainer,
};

void _expectAtLeast(double measured, double required_, String what) {
  expect(
    measured,
    greaterThanOrEqualTo(required_),
    reason: '$what measured ${measured.toStringAsFixed(2)}:1, '
        'needs ${required_.toStringAsFixed(2)}:1',
  );
}

void _againstAll(Map<String, Color> surfaces, Color fg, double need, String name) {
  surfaces.forEach((where, bg) {
    _expectAtLeast(_ratio(fg, bg), need, '$name ${_hex(fg)} on $where');
  });
}

// ── THE FONT BUNDLE ──────────────────────────────────────────────────────────────────────

/// The five faces the scale asks for, in weight order. Filenames are the contract: google_fonts
/// resolves a bundled asset by parsing `Inter-<Variant>.ttf`, so `Inter-ExtraBold.ttf` IS w800.
const _interFaces = <String, int>{
  'Inter-Regular.ttf': 400,
  'Inter-SemiBold.ttf': 600,
  'Inter-Bold.ttf': 700,
  'Inter-ExtraBold.ttf': 800,
};

/// Reads `OS/2.usWeightClass` and the byte range of one table out of an sfnt file.
///
/// Deliberately hand-rolled rather than pulled in as a dependency: the whole point is to read
/// what actually shipped, and thirty lines of table-directory walking is cheaper than trusting
/// a filename.
({int weightClass, Uint8List glyf, bool hasFvar}) _sfnt(File f) {
  final d = f.readAsBytesSync();
  final view = ByteData.sublistView(d);
  final numTables = view.getUint16(4);
  final tables = <String, (int, int)>{};
  for (var i = 0; i < numTables; i++) {
    final o = 12 + 16 * i;
    final tag = String.fromCharCodes(d.sublist(o, o + 4));
    tables[tag] = (view.getUint32(o + 8), view.getUint32(o + 12));
  }
  final os2 = tables['OS/2']!;
  final glyf = tables['glyf']!;
  return (
    weightClass: view.getUint16(os2.$1 + 4),
    glyf: Uint8List.sublistView(d, glyf.$1, glyf.$1 + glyf.$2),
    hasFvar: tables.containsKey('fvar'),
  );
}

void main() {
  // Keeps google_fonts able to reach the bundled Inter files instead of printing a page of
  // binding warnings on every run.
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the dark scheme IS the Figma design, hex for hex', () {
    final dark = NivoraTheme.dark();
    final scheme = dark.colorScheme;

    test('surfaces — three of them, plus one brighter fill', () {
      expect(_hex(NivoraColors.ground), '#0B0D0F');
      expect(_hex(NivoraColors.surfaceContainerLow), '#111417');
      expect(_hex(NivoraColors.surfaceContainer), '#171A1E');
      expect(_hex(NivoraColors.surfaceBright), '#1D2227');

      // The design ships nothing below its background and nothing between its raised surface
      // and #1D2227, so these three roles are aliases rather than invented neighbours.
      expect(NivoraColors.surfaceContainerLowest, NivoraColors.ground);
      expect(NivoraColors.surfaceContainerHigh, NivoraColors.surfaceContainer);
      expect(NivoraColors.surfaceContainerHighest, NivoraColors.surfaceContainer);
    });

    test('key colours', () {
      expect(_hex(NivoraColors.primary), '#C9A96E', reason: 'the gold accent');
      expect(_hex(NivoraColors.primaryContainer), '#F5F3EE', reason: 'the CREAM filled button');
      expect(_hex(NivoraColors.secondary), '#D5A64C', reason: 'the amber');
      expect(_hex(NivoraColors.tertiary), '#5FAE82', reason: 'positive');
      // Every on-colour in the dark scheme is the ground itself — the design never puts white
      // on a fill, it puts its own near-black.
      for (final on in [
        NivoraColors.onPrimary,
        NivoraColors.onPrimaryContainer,
        NivoraColors.onSecondary,
        NivoraColors.onTertiary,
        NivoraColors.onErrorTone,
      ]) {
        expect(on, NivoraColors.ground);
      }
    });

    test('ink and lines', () {
      expect(_hex(NivoraColors.onSurface), '#F5F3EE', reason: 'warm cream, NOT white');
      expect(_hex(NivoraColors.onSurfaceVariant), '#A2A6AB');
      expect(_hex(NivoraColors.outline), '#6F747A', reason: 'the design tertiary, as a shape');
      expect(_hex(NivoraColors.outlineVariant), '#292E33', reason: 'the one hairline');
    });

    test('the container fills are the design\'s own 10% tint, flattened', () {
      // `rgba(213,166,76,0.1)` and friends, composited over the card. A container role that is
      // secretly translucent composites twice the moment somebody stacks it, so they are
      // pinned flat — but they must still BE the tint.
      for (final e in {
        'secondary': (NivoraColors.secondary, NivoraColors.secondaryContainer),
        'tertiary': (NivoraColors.tertiary, NivoraColors.tertiaryContainer),
        'error': (NivoraColors.errorTone, NivoraColors.errorContainer),
      }.entries) {
        final (tone, container) = e.value;
        final expected = _over(
          tone.withValues(alpha: NivoraSemantics.dark.chipFillAlpha),
          NivoraColors.surfaceContainerLow,
        );
        for (final ch in [
          ((expected.r - container.r).abs(), 'red'),
          ((expected.g - container.g).abs(), 'green'),
          ((expected.b - container.b).abs(), 'blue'),
        ]) {
          expect(ch.$1 * 255, lessThanOrEqualTo(1.0),
              reason: '${e.key}Container drifted off the design tint in ${ch.$2}: '
                  '${_hex(expected)} vs ${_hex(container)}');
        }
      }
    });

    test('the legacy names point at the design, so unconverted screens moved with us', () {
      expect(NivoraColors.darkBackground, NivoraColors.ground);
      expect(NivoraColors.darkSurface, NivoraColors.surfaceContainerLow);
      expect(NivoraColors.darkElevated, NivoraColors.surfaceContainer);
      expect(NivoraColors.midnight, NivoraColors.surfaceContainerLowest);
      expect(NivoraColors.darkIndigo, NivoraColors.primary);
      expect(NivoraColors.softBlue, NivoraColors.secondary);
      expect(NivoraColors.darkTextPrimary, NivoraColors.onSurface);
      expect(NivoraColors.darkTextSecondary, NivoraColors.onSurfaceVariant);
      expect(NivoraColors.darkHairline, NivoraColors.outlineVariant);
      expect(NivoraColors.darkCardBorder, NivoraColors.outlineVariant);
      expect(NivoraColors.darkControlBorder, NivoraColors.outline);
      expect(NivoraColors.successDark, NivoraColors.tertiary);
      expect(NivoraColors.warningDark, NivoraColors.secondary);
      expect(NivoraColors.errorDark, NivoraColors.errorTone);
    });

    test('the theme wires every one of those roles through, nothing literal', () {
      expect(dark.scaffoldBackgroundColor, NivoraColors.ground);
      // `surface` is the CARD, not the ground. 17 call sites paint a card with it and the
      // ground would make every one of them vanish.
      expect(scheme.surface, NivoraColors.surfaceContainerLow);
      expect(scheme.surfaceDim, NivoraColors.ground);
      expect(scheme.surfaceBright, NivoraColors.surfaceBright);
      expect(scheme.surfaceContainerLow, NivoraColors.surfaceContainerLow);
      expect(scheme.surfaceContainer, NivoraColors.surfaceContainer);
      expect(scheme.primary, NivoraColors.primary);
      expect(scheme.onPrimary, NivoraColors.onPrimary);
      expect(scheme.primaryContainer, NivoraColors.primaryContainer);
      expect(scheme.secondary, NivoraColors.secondary);
      expect(scheme.tertiary, NivoraColors.tertiary);
      expect(scheme.error, NivoraColors.errorTone);
      expect(scheme.onSurface, NivoraColors.onSurface);
      expect(scheme.onSurfaceVariant, NivoraColors.onSurfaceVariant);
      expect(scheme.outline, NivoraColors.outline);
      expect(scheme.outlineVariant, NivoraColors.outlineVariant);
    });

    test('THE FILLED BUTTON IS CREAM — the design\'s most distinctive decision', () {
      // 4:83 "Continue" and 4:1596 "Retry" are bg #F5F3EE with #0B0D0F text. Wiring
      // FilledButton to `primary` instead would make every CTA in the app gold, which is the
      // exact "fix" DESIGN-SYSTEM.md warns against.
      final style = NivoraTheme.dark().filledButtonTheme.style!;
      const enabled = <WidgetState>{};
      expect(style.backgroundColor!.resolve(enabled), NivoraColors.primaryContainer);
      expect(style.foregroundColor!.resolve(enabled), NivoraColors.onPrimaryContainer);
      _expectAtLeast(
        _ratio(NivoraColors.onPrimaryContainer, NivoraColors.primaryContainer),
        4.5,
        'the cream button\'s own label',
      );

      // The light theme cannot use it — a cream button on a cream page is not a button — so it
      // keeps M3's derived primary pairing.
      final lightStyle = NivoraTheme.light().filledButtonTheme.style!;
      expect(lightStyle.backgroundColor!.resolve(enabled), NivoraTheme.light().colorScheme.primary);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the light scheme is DERIVED from #C9A96E, never drawn', () {
    final derived = ColorScheme.fromSeed(seedColor: NivoraColors.seed);

    test('the seed is the design\'s own accent, not a colour invented for the light theme', () {
      expect(NivoraColors.seed, NivoraColors.primary);
    });

    test('every pinned light const is still what fromSeed produces', () {
      expect(NivoraColors.background, derived.surface, reason: 'canvas');
      expect(NivoraColors.surface, derived.surfaceContainerLowest, reason: 'card');
      expect(NivoraColors.lightSheet, derived.surfaceContainerHigh);
      expect(NivoraColors.lightField, derived.surfaceContainerHighest);
      expect(NivoraColors.textPrimary, derived.onSurface);
      expect(NivoraColors.textSecondary, derived.onSurfaceVariant);
      expect(NivoraColors.lightPrimary, derived.primary);
      expect(NivoraColors.softBlueInk, derived.secondary);
      expect(NivoraColors.controlBorder, derived.outline);
      expect(NivoraColors.cardBorder, derived.outlineVariant);
      expect(NivoraColors.indigo, NivoraColors.lightPrimary);
      expect(NivoraColors.hairline, NivoraColors.lightField);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('text is AA — WCAG 1.4.3, 4.5:1, on EVERY surface of its theme', () {
    test('light neutral ramp', () {
      _againstAll(_lightSurfaces, NivoraColors.textPrimary, 4.5, 'textPrimary');
      _againstAll(_lightSurfaces, NivoraColors.textSecondary, 4.5, 'textSecondary');
      _againstAll(_lightSurfaces, NivoraColors.mutedInk, 4.5, 'mutedInk');
    });

    test('light brand and semantic ink', () {
      _againstAll(_lightSurfaces, NivoraColors.lightPrimary, 4.5, 'lightPrimary');
      _againstAll(_lightSurfaces, NivoraColors.softBlueInk, 4.5, 'softBlueInk');
      _againstAll(_lightSurfaces, NivoraColors.successInk, 4.5, 'successInk');
      _againstAll(_lightSurfaces, NivoraColors.warningInk, 4.5, 'warningInk');
      _againstAll(_lightSurfaces, NivoraColors.errorInk, 4.5, 'errorInk');
      _againstAll(_lightSurfaces, NivoraColors.infoInk, 4.5, 'infoInk');
      // The three domain inks are held to exactly the same bar as the four semantic ones.
      _againstAll(_lightSurfaces, NivoraColors.foodInk, 4.5, 'foodInk');
      _againstAll(_lightSurfaces, NivoraColors.roomsInk, 4.5, 'roomsInk');
      _againstAll(_lightSurfaces, NivoraColors.peopleInk, 4.5, 'peopleInk');
    });

    test('dark neutral ramp', () {
      _againstAll(_darkSurfaces, NivoraColors.onSurface, 4.5, 'onSurface');
      _againstAll(_darkSurfaces, NivoraColors.onSurfaceVariant, 4.5, 'onSurfaceVariant');
      _againstAll(_darkSurfaces, NivoraColors.darkMuted, 4.5, 'darkMuted');
    });

    test('dark brand and semantic ink', () {
      _againstAll(_darkSurfaces, NivoraColors.primary, 4.5, 'primary (gold)');
      _againstAll(_darkSurfaces, NivoraColors.successDark, 4.5, 'successDark');
      _againstAll(_darkSurfaces, NivoraColors.warningDark, 4.5, 'warningDark');
      _againstAll(_darkSurfaces, NivoraColors.errorDark, 4.5, 'errorDark');
      _againstAll(_darkSurfaces, NivoraColors.infoDark, 4.5, 'infoDark');
      _againstAll(_darkSurfaces, NivoraColors.foodDark, 4.5, 'foodDark');
      _againstAll(_darkSurfaces, NivoraColors.roomsDark, 4.5, 'roomsDark');
      _againstAll(_darkSurfaces, NivoraColors.peopleDark, 4.5, 'peopleDark');
    });

    test('THE THREE FIGMA VALUES THAT HAD TO MOVE, AND BY HOW LITTLE', () {
      // Each of these is a hex the designer actually used as TEXT, which does not clear 4.5:1
      // where the design itself puts it. The fix is in the colour and it is minimal: same hue,
      // same saturation, lifted in lightness until the tightest case passes. Pinning the
      // ORIGINAL's failure is what stops somebody "restoring the design value" later.
      const design = <String, (Color, Color, int)>{
        // name          design hex                     shipped                delta cap
        'tertiary ink': (Color(0xFF6F747A), NivoraColors.darkMuted, 30),
        'badge blue': (Color(0xFF5577AD), NivoraColors.infoDark, 30),
        'badge red': (Color(0xFFC96B6B), NivoraColors.errorDark, 10),
      };
      design.forEach((name, v) {
        final (original, shipped, cap) = v;

        // The original fails somewhere it is actually drawn. For two of the three that is
        // plain text on a surface; for the red it is only the chip case, which is why the
        // precondition is the same contract the shipped value has to meet rather than just
        // the plain one.
        double worstOf(Color c) => [
              ..._darkSurfaces.values.map((bg) => _ratio(c, bg)),
              ..._darkGrounds.values
                  .map((bg) => _ratio(c, _over(NivoraSemantics.dark.chipFill(c), bg))),
            ].reduce(math.min);
        expect(worstOf(original), lessThan(4.5),
            reason: '$name ${_hex(original)} now passes on its own — the lift can be reverted');

        // ...the shipped value clears it everywhere, including on a chip of itself...
        _againstAll(_darkSurfaces, shipped, 4.5, name);
        final worstChip = _darkGrounds.values
            .map((bg) => _ratio(
                shipped, _over(NivoraSemantics.dark.chipFill(shipped), bg)))
            .reduce(math.min);
        _expectAtLeast(worstChip, 4.5, '$name on a chip of itself');

        // ...and it moved the minimum it could. Anything beyond this is redesigning by eye.
        for (final ch in [
          ((shipped.r - original.r).abs() * 255, 'red'),
          ((shipped.g - original.g).abs() * 255, 'green'),
          ((shipped.b - original.b).abs() * 255, 'blue'),
        ]) {
          expect(ch.$1, lessThanOrEqualTo(cap.toDouble()),
              reason: '$name moved ${ch.$1.round()} points of ${ch.$2} off the design value '
                  '${_hex(original)} → ${_hex(shipped)}; the cap is $cap');
        }
      });
    });

    test('each ramp is a hierarchy, not three shades of the same grey', () {
      for (final e in {
        'light': [
          NivoraColors.textPrimary,
          NivoraColors.textSecondary,
          NivoraColors.mutedInk,
        ],
        'dark': [
          NivoraColors.onSurface,
          NivoraColors.onSurfaceVariant,
          NivoraColors.darkMuted,
        ],
      }.entries) {
        final card = e.key == 'light' ? NivoraColors.surface : NivoraColors.surfaceContainerLow;
        final ratios = e.value.map((c) => _ratio(c, card)).toList();
        for (var i = 1; i < ratios.length; i++) {
          expect(ratios[i], lessThan(ratios[i - 1]),
              reason: '${e.key} step $i does not read quieter than the one above it');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('graphics and controls are 3:1 — WCAG 1.4.11', () {
    test('the canonical set clears 3:1 on every surface of BOTH themes', () {
      // These are the values painted with no BuildContext — chart bars, meter fills, a tone:
      // plumbed through an enum. Each is the corresponding FIGMA tone taken to the lightness
      // that maximises its worst case across all eight surfaces.
      const canonical = <String, Color>{
        'success': NivoraColors.success,
        'warning': NivoraColors.warning,
        'error': NivoraColors.error,
        'info': NivoraColors.info,
        'textMuted': NivoraColors.textMuted,
        'food': NivoraColors.food,
        'rooms': NivoraColors.rooms,
        'people': NivoraColors.people,
      };
      canonical.forEach((name, c) {
        _againstAll(_lightSurfaces, c, 3.0, 'canonical $name');
        _againstAll(_darkSurfaces, c, 3.0, 'canonical $name');
      });
    });

    test('a single flat colour CAN now serve both extremes, which it could not before', () {
      // The previous palette's windows were disjoint and the old test proved the
      // impossibility. The new ground is darker (#0B0D0F, not #0B1326) and the new light
      // surfaces are warmer and less extreme, so the windows overlap and the canonical set is
      // a real dual-theme colour rather than a compromise. If this ever inverts again, the
      // canonical set has to split and this test says so before the ratios do.
      final darkCeiling = _darkSurfaces.values.map(_luminance).reduce(math.max);
      final lightFloor = _lightSurfaces.values.map(_luminance).reduce(math.min);
      final needAbove = 3.0 * (darkCeiling + 0.05) - 0.05; // to clear 3:1 on the lightest dark
      final needBelow = (lightFloor + 0.05) / 3.0 - 0.05; //  to clear 3:1 under the darkest light
      expect(needAbove, lessThan(needBelow),
          reason: 'the luminance windows no longer overlap: a colour would need L >= '
              '${needAbove.toStringAsFixed(4)} and L <= ${needBelow.toStringAsFixed(4)}');

      // And every canonical value actually sits inside that window.
      for (final c in [
        NivoraColors.success,
        NivoraColors.warning,
        NivoraColors.error,
        NivoraColors.info,
        NivoraColors.textMuted,
        NivoraColors.food,
        NivoraColors.rooms,
        NivoraColors.people,
      ]) {
        expect(_luminance(c), inInclusiveRange(needAbove, needBelow), reason: _hex(c));
      }
    });

    test('a control border is the control, so it is 3:1 — not the card hairline', () {
      // The dark field fill IS the design's raised surface, which is the tightest case.
      _againstAll(_darkSurfaces, NivoraColors.darkControlBorder, 3.0, 'darkControlBorder');
      _againstAll(_lightGrounds, NivoraColors.controlBorder, 3.0, 'controlBorder');
    });

    test('decorative borders are deliberately BELOW 3:1, which is why they are separate tokens',
        () {
      // A card edge held to 3:1 looks like a text field. The design draws one hairline colour
      // and it is quiet on purpose.
      _darkSurfaces.forEach((where, bg) {
        expect(_ratio(NivoraColors.darkCardBorder, bg), lessThan(2.0),
            reason: 'the dark card hairline has become a control border on $where');
      });
      expect(_ratio(NivoraColors.cardBorder, NivoraColors.surface), lessThan(2.0));
      expect(_ratio(NivoraColors.hairline, NivoraColors.surface),
          lessThan(_ratio(NivoraColors.cardBorder, NivoraColors.surface)),
          reason: 'a divider must be quieter than a card edge — that is the whole reason '
              'they are two tokens');
    });

    test('the design\'s tertiary survives as a SHAPE even though it failed as text', () {
      // #6F747A draws the empty-state glyph's 1.5px outline and a text field's border. 3:1
      // applies there and it clears it on every surface, which is exactly why it was kept
      // rather than replaced wholesale.
      _againstAll(_darkSurfaces, NivoraColors.outline, 3.0, 'outline (the design tertiary)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('filled surfaces — legible from the inside', () {
    test('the design\'s own on-colour pairings', () {
      for (final e in <String, (Color, Color)>{
        'gold': (NivoraColors.primary, NivoraColors.onPrimary),
        'cream button': (NivoraColors.primaryContainer, NivoraColors.onPrimaryContainer),
        'amber': (NivoraColors.secondary, NivoraColors.onSecondary),
        'green': (NivoraColors.tertiary, NivoraColors.onTertiary),
        'red': (NivoraColors.errorTone, NivoraColors.onErrorTone),
        'secondaryContainer': (NivoraColors.secondaryContainer, NivoraColors.onSecondaryContainer),
        'tertiaryContainer': (NivoraColors.tertiaryContainer, NivoraColors.onTertiaryContainer),
        'errorContainer': (NivoraColors.errorContainer, NivoraColors.onErrorContainer),
      }.entries) {
        final (fill, on) = e.value;
        _expectAtLeast(_ratio(on, fill), 4.5, '${e.key}: ${_hex(on)} on ${_hex(fill)}');
      }
    });

    test('the cream button is the highest-contrast control in the app', () {
      // 17.56:1, on the control that matters most. Anything that made it merely adequate would
      // be a regression worth arguing about.
      _expectAtLeast(
        _ratio(NivoraColors.onPrimaryContainer, NivoraColors.primaryContainer),
        15.0,
        'the cream CTA',
      );
    });

    test('the snackbar is the deepest well and its text still reads', () {
      _expectAtLeast(
        _ratio(NivoraColors.onSurface, NivoraColors.midnight),
        4.5,
        'snackbar text',
      );
      for (final theme in [NivoraTheme.dark(), NivoraTheme.light()]) {
        expect(theme.snackBarTheme.backgroundColor, NivoraColors.midnight);
      }
    });

    test('both schemes agree with themselves about on-colours', () {
      for (final scheme in [NivoraTheme.dark().colorScheme, NivoraTheme.light().colorScheme]) {
        final label = scheme.brightness.name;
        for (final e in <String, (Color, Color)>{
          'primary': (scheme.primary, scheme.onPrimary),
          'secondary': (scheme.secondary, scheme.onSecondary),
          'tertiary': (scheme.tertiary, scheme.onTertiary),
          'error': (scheme.error, scheme.onError),
          'surface': (scheme.surface, scheme.onSurface),
        }.entries) {
          final (fill, on) = e.value;
          _expectAtLeast(_ratio(on, fill), 4.5, '$label ${e.key}');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('status chips — the tightest case in the app', () {
    void checkChips(NivoraSemantics tones, Map<String, Color> grounds, String label) {
      final inks = <String, Color>{
        'success': tones.success,
        'warning': tones.warning,
        'error': tones.error,
        'info': tones.info,
        'muted': tones.muted,
        'food': tones.food,
        'rooms': tones.rooms,
        'people': tones.people,
      };
      inks.forEach((name, ink) {
        grounds.forEach((where, bg) {
          final fill = _over(tones.chipFill(ink), bg);
          _expectAtLeast(_ratio(ink, fill), 4.5, '$label $name chip on $where');
        });
      });
    }

    test('light chips', () => checkChips(NivoraSemantics.light, _lightGrounds, 'light'));
    test('dark chips', () => checkChips(NivoraSemantics.dark, _darkGrounds, 'dark'));

    test('the fill alpha is the design\'s own 10%, and it is AT ITS CEILING', () {
      // Figma draws every state badge and the subscription banner at `rgba(<tone>, 0.1)`. That
      // is also the most the palette can take: a tint of the tone lightens the fill TOWARDS
      // the text, so the ratio falls as the alpha rises.
      expect(NivoraSemantics.dark.chipFillAlpha, 0.10);
      expect(NivoraSemantics.light.chipFillAlpha, NivoraSemantics.dark.chipFillAlpha,
          reason: 'one number for both themes, so a chip reads at the same weight in either');

      for (final e in {
        'light': (NivoraSemantics.light, _lightGrounds),
        'dark': (NivoraSemantics.dark, _darkGrounds),
      }.entries) {
        final (tones, grounds) = e.value;
        final inks = [
          tones.success, tones.warning, tones.error, tones.info, tones.muted,
          tones.food, tones.rooms, tones.people,
        ];
        double worstAt(double alpha) => inks
            .expand((ink) => grounds.values
                .map((bg) => _ratio(ink, _over(ink.withValues(alpha: alpha), bg))))
            .reduce(math.min);
        expect(worstAt(tones.chipFillAlpha), greaterThanOrEqualTo(4.5));
        // 0.11 is the last value that clears AA at all and 0.12 fails, so the design's own
        // 0.10 buys exactly one point of headroom. If this ever passes at 0.12 the palette has
        // been lightened and the comment in tokens.dart is stale.
        expect(worstAt(0.12), lessThan(4.5),
            reason: '${e.key} chips have room the comment says they do not; re-derive the '
                'ceiling rather than leaving the number stale');
      }
    });

    test('the chip border is FULL STRENGTH, which is the design\'s own badge', () {
      // `border border-[#5577ad]`, no alpha. The tones here are muted rather than saturated,
      // so a 1px edge at full strength is a defined chip and not a warning light.
      expect(NivoraSemantics.dark.chipBorderAlpha, 1.0);
      for (final e in {
        'light': (NivoraSemantics.light, NivoraColors.errorInk, _lightGrounds),
        'dark': (NivoraSemantics.dark, NivoraColors.errorDark, _darkGrounds),
      }.entries) {
        final (tones, ink, grounds) = e.value;
        expect(tones.chipBorder(ink), ink);
        grounds.forEach((where, bg) {
          _expectAtLeast(_ratio(tones.chipBorder(ink), bg), 3.0,
              '${e.key} chip border on $where');
        });
      }
    });

    test('resolve() maps canonical to the theme text value, and passes anything else through',
        () {
      expect(NivoraSemantics.light.resolve(NivoraColors.error), NivoraColors.errorInk);
      expect(NivoraSemantics.dark.resolve(NivoraColors.error), NivoraColors.errorDark);
      expect(NivoraSemantics.dark.resolve(NivoraColors.success), NivoraColors.tertiary);
      expect(NivoraSemantics.light.resolve(NivoraColors.textMuted), NivoraColors.mutedInk);
      expect(NivoraSemantics.dark.resolve(NivoraColors.food), NivoraColors.foodDark);
      expect(NivoraSemantics.light.resolve(NivoraColors.rooms), NivoraColors.roomsInk);
      expect(NivoraSemantics.dark.resolve(NivoraColors.people), NivoraColors.peopleDark);
      // Not a canonical value: untouched.
      expect(NivoraSemantics.light.resolve(NivoraColors.indigo), NivoraColors.indigo);
    });

    testWidgets('the fallback tones are the DARK set — this is a dark-first app',
        (tester) async {
      late NivoraSemantics seen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          seen = context.tones;
          return const SizedBox.shrink();
        }),
      ));
      expect(seen, NivoraSemantics.dark);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE DOMAIN TONES — three new hues, derived by the same method and held to the same bar.
  //
  // Everything above already covers them: the canonical set is in the luminance window, the
  // inks are AA plain and on a chip, the tints keep body text legible. What is pinned HERE is
  // the derivation itself — that each ink is its canonical moved along its own hue by the
  // minimum that passes, and not a colour somebody liked. "Minimum" is asserted the only way it
  // can be: one step back towards the canonical, and the contract fails.
  group('the domain tones — derived, not picked', () {
    const domains = <String, (Color, Color, Color)>{
      //          canonical             dark ink                 light ink
      'food': (NivoraColors.food, NivoraColors.foodDark, NivoraColors.foodInk),
      'rooms': (NivoraColors.rooms, NivoraColors.roomsDark, NivoraColors.roomsInk),
      'people': (NivoraColors.people, NivoraColors.peopleDark, NivoraColors.peopleInk),
    };

    /// The ink's own contract, in one place: AA plain on every surface of its theme AND AA on a
    /// 10% chip of itself over every ground a chip sits on.
    bool passes(Color ink, Map<String, Color> surfaces, Map<String, Color> grounds) {
      final plain = surfaces.values.every((bg) => _ratio(ink, bg) >= 4.5);
      final chip = grounds.values.every((bg) =>
          _ratio(ink, _over(ink.withValues(alpha: NivoraSemantics.surfaceTintAlpha), bg)) >=
          4.5);
      return plain && chip;
    }

    Color shifted(Color c, double dl) {
      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor();
    }

    test('each ink keeps its canonical\'s hue and saturation — moved in lightness only', () {
      domains.forEach((name, v) {
        final (canonical, dark, light) = v;
        final c = HSLColor.fromColor(canonical);
        for (final e in {'dark': dark, 'light': light}.entries) {
          final ink = HSLColor.fromColor(e.value);
          // A few degrees of hue and a few points of saturation are 8-bit rounding, not a
          // redesign; a hue that has moved 30° is a different colour wearing the name.
          expect((ink.hue - c.hue).abs(), lessThan(6),
              reason: '$name ${e.key} ink changed hue: ${c.hue.round()}° → ${ink.hue.round()}°');
          expect((ink.saturation - c.saturation).abs(), lessThan(0.08),
              reason: '$name ${e.key} ink changed saturation');
        }
        // And in the direction the theme needs: lighter for dark, darker for light.
        expect(HSLColor.fromColor(dark).lightness, greaterThan(c.lightness), reason: name);
        expect(HSLColor.fromColor(light).lightness, lessThan(c.lightness), reason: name);
      });
    });

    test('each ink is the MINIMUM lift — one step back towards the canonical, and it fails', () {
      domains.forEach((name, v) {
        final (_, dark, light) = v;
        expect(passes(dark, _darkSurfaces, _darkGrounds), isTrue, reason: '$name dark ink');
        expect(passes(shifted(dark, -0.01), _darkSurfaces, _darkGrounds), isFalse,
            reason: '$name dark ink has slack — it was lifted further than it needed to be, '
                'which is redesigning by eye');
        expect(passes(light, _lightSurfaces, _lightGrounds), isTrue, reason: '$name light ink');
        expect(passes(shifted(light, 0.01), _lightSurfaces, _lightGrounds), isFalse,
            reason: '$name light ink has slack');
      });
    });

    test('an identity avatar can never wear a STATUS colour', () {
      // THE REGRESSION THIS PINS WAS REAL AND SHIPPED IN AN EARLIER DRAFT. avatarToneFor hashed
      // a name into six tones, three of which were success/warning/info — and the same Avatar
      // widget carries a status tone on several screens (the warden's fee ledger passes the fee
      // tone, the roster passes active/on-leave, the desk sheets pass amber and blue outright).
      // On the screens that pass nothing the hash chose, so a resident whose NAME hashed to
      // amber wore the disc that means "on leave" on the list two taps away.
      // A plain list, not a const Set: Color overrides == and Dart refuses it in a const set.
      const statusTones = <Color>[
        NivoraColors.success,
        NivoraColors.warning,
        NivoraColors.error,
        NivoraColors.info,
      ];
      // Enough names that every slot of any small palette is hit many times over.
      final seen = <Color>{};
      for (var i = 0; i < 4000; i++) {
        seen.add(avatarToneFor('Resident Number $i'));
      }
      for (final tone in seen) {
        expect(statusTones.contains(tone), isFalse,
            reason: 'avatarToneFor produced ${_hex(tone)}, which is a STATUS tone — an identity '
                'disc in that colour is indistinguishable from a state on the same widget');
      }
      // …and it is still doing its job: more than one colour, all of them resolvable.
      expect(seen.length, greaterThan(1), reason: 'every face would be the same colour');
      for (final tone in seen) {
        for (final tones in [NivoraSemantics.dark, NivoraSemantics.light]) {
          expect(tones.resolve(tone), isNot(tone),
              reason: '${_hex(tone)} has no theme ink, so the initials on it are unmeasured');
        }
      }
    });

    test('the same name always gets the same colour, and an empty name is neutral', () {
      expect(avatarToneFor('Aarav Sharma'), avatarToneFor('Aarav Sharma'));
      // Case and surrounding space are not identity.
      expect(avatarToneFor('  aarav sharma  '), avatarToneFor('Aarav Sharma'));
      // Nothing to hash: the muted grey, not an arbitrary slot.
      expect(avatarToneFor(null), NivoraColors.textMuted);
      expect(avatarToneFor('   '), NivoraColors.textMuted);
    });

    test('every domain names a tone this palette can resolve, and gold passes through', () {
      for (final d in NivoraDomain.values) {
        for (final tones in [NivoraSemantics.dark, NivoraSemantics.light]) {
          final ink = tones.resolve(d.tone);
          // A domain that resolved to its own canonical would be one the paint site cannot
          // make legible — except security, which is the scheme's primary and is meant to.
          if (d == NivoraDomain.security) {
            expect(ink, NivoraColors.primary, reason: 'security is the brand gold, unresolved');
          } else {
            expect(ink, isNot(d.tone), reason: '${d.name} did not resolve to a theme ink');
          }
        }
      }
      // Seven domains, six distinct tones plus the brand: no two areas share a colour except
      // by the documented decision that complaints and open work are both amber.
      final tones = NivoraDomain.values.map((d) => d.tone).toSet();
      expect(tones.length, NivoraDomain.values.length);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // THE REFUND PAIRING — measured, because a refund got a tone without getting a colour.
  //
  // A refund is a FACT, NOT A FAULT: nobody did anything wrong when money goes back, so it may
  // not wear `error` (which means 'unpaid'), nor `warning` (which already means 'due / still
  // owing' and would make a refunded month look like one that needs chasing), nor `success`
  // (money leaving the hostel is not a collection). It wears `info` — the blue this palette
  // already spends on "here is something you should know".
  //
  // THAT CHOICE ADDS NO COLOUR AND NO PAIRING, which is the point of it, and the first test
  // below is what keeps that claim true. The rest measure the three grounds the refund
  // surfaces actually paint on — and one of them, `colorScheme.surfaceContainer` in the LIGHT
  // theme, is fromSeed output rather than a design hex, so it is not covered by _lightSurfaces
  // and would otherwise go unmeasured.
  //
  //   RefundNote     (features/student/widgets/rent.dart)   info ink on the well, info border
  //   the tile line  (features/student/widgets/rent.dart)   info ink on the card
  //   the ledger row (features/warden/fees/…)               info ink on the row
  //   _RefundStrip   (features/owner/owner_payments_screen)  12px info ink on a chip of itself
  group('the refund tone — a fact, not a fault', () {
    test('it is the info tone, and it is not any of the three rent tones', () {
      for (final e in {
        'light': NivoraSemantics.light,
        'dark': NivoraSemantics.dark,
      }.entries) {
        final tones = e.value;
        final refund = tones.resolve(NivoraColors.info);
        expect(refund, tones.info,
            reason: '${e.key}: the refund ink must be the palette info ink, not a new colour');
        expect(refund, isNot(tones.error),
            reason: '${e.key}: a refund painted in the alarm colour accuses the resident of '
                'arrears for having been given money back');
        expect(refund, isNot(tones.warning),
            reason: '${e.key}: warning already means due / still owing');
        expect(refund, isNot(tones.success),
            reason: '${e.key}: money leaving the hostel is not a collection');
      }
    });

    test('the info ink reads on the WELL the refund note is drawn in', () {
      // `t.colorScheme.surfaceContainer` — the same well [PayAtDeskNote] uses, one rung inside
      // the rent card. On light this is fromSeed output and appears in no other group here.
      for (final e in {
        'light': (NivoraTheme.light(), NivoraSemantics.light),
        'dark': (NivoraTheme.dark(), NivoraSemantics.dark),
      }.entries) {
        final (theme, tones) = e.value;
        final well = theme.colorScheme.surfaceContainer;
        _expectAtLeast(_ratio(tones.info, well), 4.5, '${e.key} refund ink on the well');
        // WCAG 1.4.11: the 1px edge that makes the well read as its own panel is a graphic.
        _expectAtLeast(
            _ratio(tones.chipBorder(tones.info), well), 3.0, '${e.key} refund well border');
      }
    });

    test('the info ink reads on the CARD, where the history row and ledger row print it', () {
      for (final e in {
        'light': (NivoraTheme.light(), NivoraSemantics.light),
        'dark': (NivoraTheme.dark(), NivoraSemantics.dark),
      }.entries) {
        final (theme, tones) = e.value;
        _expectAtLeast(_ratio(tones.info, theme.colorScheme.surfaceContainerLow), 4.5,
            '${e.key} refund ink on the card');
      }
    });

    test("the owner's strip is 12px on a chip of its own tone — the tightest case there is",
        () {
      // The strip's fill is a 10% tint of the very ink printed on it, so the ground moves
      // TOWARDS the text. This is the same contract `status chips` holds every tone to; it is
      // repeated here against the real theme surfaces because this is the one place the app
      // sets 12px type on it.
      for (final e in {
        'light': (NivoraTheme.light(), NivoraSemantics.light),
        'dark': (NivoraTheme.dark(), NivoraSemantics.dark),
      }.entries) {
        final (theme, tones) = e.value;
        for (final ground in <String, Color>{
          'card': theme.colorScheme.surfaceContainerLow,
          'raised': theme.colorScheme.surfaceContainer,
        }.entries) {
          final fill = _over(tones.chipFill(tones.info), ground.value);
          _expectAtLeast(
              _ratio(tones.info, fill), 4.5, '${e.key} refund strip on ${ground.key}');
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  // TINTED SURFACES — a whole card carrying a meaning, instead of a chip in its corner.
  //
  // [ToneSurface] paints `tone @ surfaceTintAlpha` over the fill the surface would otherwise
  // have had, and that fill is always `GlassWeight.surfaceOf` — card or raised on dark, the
  // single white on light. Those three are the ONLY grounds a tint is ever composited over, so
  // they are the only ones measured here.
  //
  // `bright #1D2227` is deliberately absent, exactly as it is from the chip grounds: that rung
  // is the input fill, and a tinted text field is a field that looks like a state.
  group('tinted surfaces — a card that IS its status', () {
    const darkTintBases = <String, Color>{
      'card #111417': NivoraColors.surfaceContainerLow,
      'raised #171A1E': NivoraColors.surfaceContainer,
    };
    const lightTintBases = <String, Color>{
      'card #FFFFFF': NivoraColors.surface,
    };

    Map<String, Color> inksOf(NivoraSemantics tones) => {
          'success': tones.success,
          'warning': tones.warning,
          'error': tones.error,
          'info': tones.info,
          'muted': tones.muted,
          // A [DomainCard] is a ToneSurface in a domain tone, so the domain inks are tints too.
          'food': tones.food,
          'rooms': tones.rooms,
          'people': tones.people,
        };

    /// Every (tone, base) tint a ToneSurface can actually paint, in one theme.
    void forEachTint(
      NivoraSemantics tones,
      Map<String, Color> bases,
      void Function(String name, Color ink, String where, Color tinted) body,
    ) {
      inksOf(tones).forEach((name, ink) {
        bases.forEach((where, base) {
          body(name, ink, where, tones.tintedSurface(ink, base));
        });
      });
    }

    void checkBodyText(
      NivoraSemantics tones,
      Map<String, Color> bases,
      Map<String, Color> inks,
      String label,
    ) {
      forEachTint(tones, bases, (name, _, where, tinted) {
        inks.forEach((textName, text) {
          _expectAtLeast(
            _ratio(text, tinted),
            4.5,
            '$label $textName on a $name-tinted $where',
          );
        });
      });
    }

    test('dark: body and secondary text stay AA on every tint', () {
      checkBodyText(NivoraSemantics.dark, darkTintBases, {
        'onSurface': NivoraColors.onSurface,
        'onSurfaceVariant': NivoraColors.onSurfaceVariant,
      }, 'dark');
    });

    test('light: body and secondary text stay AA on every tint', () {
      checkBodyText(NivoraSemantics.light, lightTintBases, {
        'textPrimary': NivoraColors.textPrimary,
        'textSecondary': NivoraColors.textSecondary,
      }, 'light');
    });

    // THE PAIRING THE WHOLE TREATMENT RESTS ON. [StatusWord] draws the status in the tone at
    // full strength directly on the tint — no chip — and this is that case.
    test('the status WORD is AA in its own tone on its own tint, in both themes', () {
      for (final e in {
        'light': (NivoraSemantics.light, lightTintBases),
        'dark': (NivoraSemantics.dark, darkTintBases),
      }.entries) {
        final (tones, bases) = e.value;
        forEachTint(tones, bases, (name, ink, where, tinted) {
          _expectAtLeast(_ratio(ink, tinted), 4.5, '${e.key} $name word on a tinted $where');
        });
      }
    });

    // ═══ THE RULE, PINNED AS A FAILURE — AND IT IS THE DARK THEME THAT SETS IT ═══
    //
    // This is the reason [StatusWord] exists at all, and it is the one thing a future edit is
    // most likely to undo: putting a StatusPill back on a tinted card looks like an
    // improvement and is a contrast failure. So the failure itself is asserted.
    //
    // THE TWO THEMES GENUINELY DIFFER HERE, which is why they are asserted separately rather
    // than as one worst-case. A dark tint moves the ground toward its own light text and the
    // chip stacks into it; a light tint moves white away from its dark text and the chip has
    // room to spare. The widget still refuses the chip in BOTH, because one widget that grew a
    // chip on one theme and not the other would be two designs.
    double worstChipOnTint(NivoraSemantics tones, Map<String, Color> bases) {
      var worst = double.infinity;
      forEachTint(tones, bases, (name, ink, where, tinted) {
        worst = math.min(worst, _ratio(ink, _over(tones.chipFill(ink), tinted)));
      });
      return worst;
    }

    test('dark: a chip of the SAME tone on a tinted card FAILS AA — hence StatusWord', () {
      final worst = worstChipOnTint(NivoraSemantics.dark, darkTintBases);
      expect(
        worst,
        lessThan(4.5),
        reason: 'a chip on a tint of its own tone measured ${worst.toStringAsFixed(2)}:1. If '
            'this now clears AA the dark tones have changed — re-derive the rule in '
            'NivoraSemantics.surfaceTintAlpha before letting a StatusPill back onto a '
            'ToneSurface.',
      );
    });

    test("light: the same stack would have been legible — the rule is the dark theme's", () {
      // Recorded, not relied on. It is the evidence for the sentence in tokens.dart that says
      // the light theme has room the dark one does not, and it is what stops someone reading
      // the rule above as "tints are dangerous" when the real finding is narrower.
      expect(worstChipOnTint(NivoraSemantics.light, lightTintBases),
          greaterThanOrEqualTo(4.5));
    });

    // ═══ THE TINT WAS ALREADY IN THE FILE ═══
    //
    // The best evidence that this recipe is the design's and not an invention: composite each
    // dark tone over the card at the tint alpha and you land exactly on the container colour
    // the designer picked by hand, for all three tones that have one. If a tone is ever nudged,
    // this fails and the container it no longer reproduces has to be re-derived with it —
    // which is the point. A tinted card is the design's container rung, not a fourth palette.
    test("the dark tint reproduces the design's own container colours, byte for byte", () {
      const card = NivoraColors.surfaceContainerLow;
      final tones = NivoraSemantics.dark;
      // Compared as the 8-bit hex that actually reaches a display. `Color` now carries double
      // components, so `alphaBlend` lands a fraction of one 255th away from the hand-picked
      // constant and Color equality would fail on a difference no screen can show.
      expect(_hex(tones.tintedSurface(NivoraColors.success, card)),
          _hex(NivoraColors.tertiaryContainer),
          reason: 'success tint must equal tertiaryContainer');
      expect(_hex(tones.tintedSurface(NivoraColors.warning, card)),
          _hex(NivoraColors.secondaryContainer),
          reason: 'warning tint must equal secondaryContainer');
      expect(_hex(tones.tintedSurface(NivoraColors.error, card)),
          _hex(NivoraColors.errorContainer),
          reason: 'error tint must equal errorContainer');
    });

    test('the tint alpha IS the chip alpha — one weight of colour at two scales', () {
      expect(NivoraSemantics.surfaceTintAlpha, NivoraSemantics.dark.chipFillAlpha);
      expect(NivoraSemantics.surfaceTintAlpha, 0.10);
    });

    test('a tinted surface is OPAQUE, so nothing behind it can change what was measured', () {
      forEachTint(NivoraSemantics.dark, darkTintBases, (name, _, where, tinted) {
        expect(tinted.a, 1.0, reason: '$name on $where must not be translucent');
      });
      forEachTint(NivoraSemantics.light, lightTintBases, (name, _, where, tinted) {
        expect(tinted.a, 1.0, reason: '$name on $where must not be translucent');
      });
    });

    // The rail is a graphic, so 1.4.11's 3:1 is the bar rather than 4.5:1 — and it is never
    // the only carrier of its meaning, because the row it edges still spells the status out.
    test('the leading rail clears 3:1 on the surfaces it is drawn against', () {
      for (final e in {
        'light': (NivoraSemantics.light, lightTintBases),
        'dark': (NivoraSemantics.dark, darkTintBases),
      }.entries) {
        final (tones, bases) = e.value;
        inksOf(tones).forEach((name, ink) {
          bases.forEach((where, base) {
            _expectAtLeast(_ratio(ink, base), 3.0, '${e.key} $name rail on $where');
            // And against the tint it sits beside, which is the edge actually seen.
            _expectAtLeast(_ratio(ink, tones.tintedSurface(ink, base)), 3.0,
                '${e.key} $name rail against its own tint on $where');
          });
        });
      }
    });

    test("the rail is the design's own border-l-4", () {
      expect(Strokes.rail, Space.xxs);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the panes are FLAT — no blur, and now no shadow either', () {
    test('no blur survives anywhere in the pane layer', () {
      // Grepped rather than reasoned about. Release builds already disable BackdropFilter
      // unconditionally, so a reintroduced one would only ever be seen in debug — which is
      // exactly how it would get merged. Comment lines are stripped first: the file explains
      // at length why the blur is absent, and naming a thing is not using it.
      final code = File('lib/shared/glass/glass.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
          .join('\n');
      for (final banned in ['BackdropFilter', 'ImageFilter', 'dart:ui']) {
        expect(code.contains(banned), isFalse,
            reason: '$banned is back in the pane layer. The owner\'s phone reported "stuck, '
                'lag"; the flat card is the same pixel at zero GPU cost.');
      }
    });

    test('a resting card casts NO shadow — the design separates with a hairline', () {
      expect(Shadows.level1, isEmpty);
      expect(Shadows.level2, isEmpty,
          reason: 'not one Figma frame carries a box-shadow; the #292E33 edge is the separator');
      // And the edge has to be doing the work, because the card itself is invisible without it.
      expect(_ratio(NivoraColors.surfaceContainerLow, NivoraColors.ground), lessThan(1.1));
      _expectAtLeast(
        _ratio(NivoraColors.outlineVariant, NivoraColors.ground),
        1.3,
        'the hairline against the ground',
      );
      // A modal is the one thing left that genuinely floats.
      expect(Shadows.level3, isNotEmpty);
    });

    test('the weight ladder is the design\'s three surfaces and it never falls', () {
      final dark = NivoraTheme.dark().colorScheme;
      expect(GlassWeight.thin.surfaceOf(dark), NivoraColors.surfaceContainerLow);
      expect(GlassWeight.regular.surfaceOf(dark), NivoraColors.surfaceContainer);
      expect(GlassWeight.thick.surfaceOf(dark), NivoraColors.surfaceContainerHigh);

      // In the dark, elevation gets LIGHTER as it rises. `thick` sits level with `regular`
      // because the design ships nothing above its raised surface — a sheet is separated by
      // the scrim and level3, not by another rung of near-black.
      var previous = _luminance(NivoraColors.ground);
      for (final w in GlassWeight.values) {
        final l = _luminance(w.surfaceOf(dark));
        expect(l, greaterThanOrEqualTo(previous),
            reason: '${w.name} sits BELOW the rung under it');
        previous = l;
      }
      expect(_luminance(GlassWeight.regular.surfaceOf(dark)),
          greaterThan(_luminance(GlassWeight.thin.surfaceOf(dark))),
          reason: 'a card and a bar must not be the same fill');

      // The light theme elevates by shadow instead: the card is already the lightest surface,
      // so stepping "up" would mean stepping toward grey.
      final light = NivoraTheme.light().colorScheme;
      for (final w in GlassWeight.values) {
        expect(w.surfaceOf(light), light.surface, reason: '${w.name} tinted the light theme');
      }
    });

    testWidgets('a dark pane edge is the design\'s own hairline, not a white alpha',
        (tester) async {
      late Color edge;
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.dark(),
        home: Builder(builder: (c) {
          edge = GlassSurface.edgeColor(c);
          return const SizedBox.shrink();
        }),
      ));
      expect(edge, NivoraColors.outlineVariant);

      late Color lightPaneEdge;
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.light(),
        home: Builder(builder: (c) {
          lightPaneEdge = GlassSurface.edgeColor(c);
          return const SizedBox.shrink();
        }),
      ));
      final pane = GlassWeight.thin.surfaceOf(NivoraTheme.light().colorScheme);
      expect(_ratio(_over(lightPaneEdge, pane), pane), greaterThan(1.3),
          reason: 'the light pane edge has gone back to being invisible');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the tokens are actually wired into the themes', () {
    test('hint text is text, so it is AA against the FIELD FILL', () {
      for (final e in {
        'dark': (NivoraTheme.dark(), NivoraColors.surfaceContainerHighest),
        'light': (NivoraTheme.light(), NivoraColors.lightField),
      }.entries) {
        final (theme, fill) = e.value;
        expect(theme.inputDecorationTheme.fillColor, fill);
        final hint = theme.inputDecorationTheme.hintStyle!.color!;
        _expectAtLeast(_ratio(hint, fill), 4.5, '${e.key} hint on the field');
      }
    });

    test('an input border is the control, so it is 3:1 against its own fill', () {
      for (final e in {
        'dark': (NivoraTheme.dark(), NivoraColors.surfaceContainerHighest),
        'light': (NivoraTheme.light(), NivoraColors.lightField),
      }.entries) {
        final (theme, fill) = e.value;
        final border =
            (theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder).borderSide.color;
        _expectAtLeast(_ratio(border, fill), 3.0, '${e.key} input border');
      }
    });

    test('a drag handle is a control, so it is 3:1 on the sheet it sits on', () {
      for (final e in {
        'dark': (NivoraTheme.dark(), GlassWeight.thick.surfaceOf(NivoraTheme.dark().colorScheme)),
        'light':
            (NivoraTheme.light(), GlassWeight.thick.surfaceOf(NivoraTheme.light().colorScheme)),
      }.entries) {
        final (theme, sheet) = e.value;
        _expectAtLeast(
            _ratio(theme.bottomSheetTheme.dragHandleColor!, sheet), 3.0, '${e.key} drag handle');
      }
    });

    test('the bottom bar reads: both label states are AA on the bar\'s own fill', () {
      for (final theme in [NivoraTheme.dark(), NivoraTheme.light()]) {
        final label = theme.brightness.name;
        final bar = theme.navigationBarTheme.backgroundColor!;
        expect(bar, GlassWeight.regular.surfaceOf(theme.colorScheme));
        for (final states in [<WidgetState>{}, {WidgetState.selected}]) {
          final style = theme.navigationBarTheme.labelTextStyle!.resolve(states)!;
          _expectAtLeast(_ratio(style.color!, bar), 4.5, '$label nav label $states');
        }
        // The active pill is the design's chip recipe: 10% of the accent.
        final indicator = theme.navigationBarTheme.indicatorColor!;
        _expectAtLeast(
          _ratio(theme.colorScheme.primary, _over(indicator, bar)),
          4.5,
          '$label active nav label on its own pill',
        );
      }
    });

    test('the FAB is the design\'s gold, and its label reads on it', () {
      final fab = NivoraTheme.dark().floatingActionButtonTheme;
      expect(fab.backgroundColor, NivoraColors.primary);
      _expectAtLeast(_ratio(fab.foregroundColor!, fab.backgroundColor!), 4.5, 'FAB label');
      expect(fab.elevation, 0, reason: 'nothing in this design is elevated');
    });

    test('the meter track is the hairline as a filled channel, and the fill reads on it', () {
      for (final theme in [NivoraTheme.dark(), NivoraTheme.light()]) {
        final track = theme.progressIndicatorTheme.linearTrackColor!;
        expect(track, theme.colorScheme.outlineVariant);
        _expectAtLeast(_ratio(theme.progressIndicatorTheme.color!, track), 3.0,
            '${theme.brightness.name} meter fill on its track');
      }
    });

    test('NivoraSemantics is registered on both themes', () {
      expect(NivoraTheme.dark().extension<NivoraSemantics>(), NivoraSemantics.dark);
      expect(NivoraTheme.light().extension<NivoraSemantics>(), NivoraSemantics.light);
    });

    test('the system bars follow the theme, and their icons are the OPPOSITE of its ground', () {
      // Nothing set this before, and most screens draw a GlassHeader rather than an AppBar —
      // the one widget that sets it on its own — so Android's default dark icons sat on the
      // #0B0D0F ground and the clock was unreadable on the sign-in screen. Pinned here so a
      // theme edit cannot quietly put it back.
      final dark = NivoraTheme.systemBars(Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light,
          reason: 'light icons over the dark ground');
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);

      final light = NivoraTheme.systemBars(Brightness.light);
      expect(light.statusBarIconBrightness, Brightness.dark,
          reason: 'dark icons over the ivory ground');
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);

      for (final s in <SystemUiOverlayStyle>[dark, light]) {
        // Edge to edge: the app's own ground runs under both bars, so both are transparent and
        // the three-button bar's grey scrim is off — the bar is already on an opaque surface.
        expect(s.statusBarColor, Colors.transparent);
        expect(s.systemNavigationBarColor, Colors.transparent);
        expect(s.systemNavigationBarContrastEnforced, isFalse);
      }
    });

    test('the AppBar is stripped rather than half-styled', () {
      for (final theme in [NivoraTheme.dark(), NivoraTheme.light()]) {
        expect(theme.appBarTheme.backgroundColor, Colors.transparent);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.appBarTheme.scrolledUnderElevation, 0);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('typography — Inter only, and the bundle is real', () {
    test('Plus Jakarta Sans is gone from the pubspec and from disk', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('Plus Jakarta Sans'), isFalse);
      expect(pubspec.contains('PlusJakartaSans'), isFalse);
      expect(File('google_fonts/PlusJakartaSans-Variable.ttf').existsSync(), isFalse,
          reason: 'the unused variable font is still shipping in the APK');
      // The whole directory is declared as an asset, which is how google_fonts finds the faces.
      expect(pubspec.contains('- google_fonts/'), isTrue);
    });

    test('FIVE FILES, FIVE WEIGHTS, FIVE DIFFERENT FACES', () {
      // The trap this exists for: four byte-identical files once shipped as four weights, so
      // Flutter registered four copies of the same 400 face and every heading rendered
      // regular while the pubspec looked correct. Filenames prove nothing; the tables do.
      final seen = <String, Uint8List>{};
      _interFaces.forEach((name, weight) {
        final f = File('google_fonts/$name');
        expect(f.existsSync(), isTrue, reason: '$name is not bundled');
        final info = _sfnt(f);
        expect(info.weightClass, weight,
            reason: '$name declares usWeightClass ${info.weightClass}, not $weight');
        expect(info.hasFvar, isFalse,
            reason: '$name is a VARIABLE font; google_fonts resolves static faces by filename '
                'and a variable file registered this way renders at its default weight');
        seen[name] = info.glyf;
      });

      final names = seen.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final a = seen[names[i]]!;
          final b = seen[names[j]]!;
          final identical = a.length == b.length &&
              List.generate(a.length, (k) => a[k] == b[k]).every((x) => x);
          expect(identical, isFalse,
              reason: '${names[i]} and ${names[j]} have identical outlines — they are the same '
                  'face shipped twice');
        }
      }
    });

    test('the hero really is ExtraBold, and every slot resolves to a bundled weight', () {
      final text = NivoraType.textTheme(NivoraColors.onSurface, NivoraColors.onSurfaceVariant);
      expect(text.displayLarge!.fontWeight, FontWeight.w800,
          reason: 'the design\'s hero is 32/800 and the file for it is bundled');
      expect(text.headlineLarge!.fontWeight, FontWeight.w800);
      expect(text.displayMedium!.fontWeight, FontWeight.w800);

      final bundled = <FontWeight>{
        FontWeight.w400,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w800,
      };
      for (final style in _allSlots(text)) {
        expect(bundled, contains(style.fontWeight),
            reason: 'a slot asks for ${style.fontWeight} and no such Inter file is bundled — '
                'with allowRuntimeFetching off it lands on the nearest weight instead');
      }
    });

    testWidgets('every weight resolves from the BUNDLE with fetching off', (tester) async {
      // main.dart sets allowRuntimeFetching = false so a missing face cannot become a silent
      // download on a customer's first launch. This reproduces that setting and renders one
      // string per slot.
      //
      // The failure has to be caught through debugPrint rather than takeException, and that is
      // the whole reason this test is worth writing: google_fonts loads a face on a future it
      // then `.ignore()`s, so a missing weight NEVER throws anywhere the framework can see it.
      // It prints, falls back to the platform font, and the app just quietly looks wrong.
      final was = GoogleFonts.config.allowRuntimeFetching;
      GoogleFonts.config.allowRuntimeFetching = false;
      final messages = <String>[];
      final realDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => GoogleFonts.config.allowRuntimeFetching = was);

      final text = NivoraType.textTheme(NivoraColors.onSurface, NivoraColors.onSurfaceVariant);
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              for (final style in _allSlots(text))
                Text('₹ 8,500', style: style, maxLines: 1),
            ],
          ),
        ),
      ));
      // Bounded: a weight that is genuinely missing can leave google_fonts waiting on a
      // load path that never resolves, and a hanging test is a worse signal than a failing one.
      await tester.runAsync(
        () => GoogleFonts.pendingFonts()
            .timeout(const Duration(seconds: 5), onTimeout: () => const <void>[]),
      );
      await tester.pump();
      // Restored HERE rather than in a tearDown: the framework asserts every foundation debug
      // variable is back to its default before tearDowns run.
      debugPrint = realDebugPrint;

      final failures = messages.where((m) => m.contains('unable to load font')).toList();
      expect(failures, isEmpty,
          reason: 'a weight in the scale is not in the bundle: $failures');
    });

    test('every slot is Inter and nothing else', () {
      final text = NivoraType.textTheme(NivoraColors.onSurface, NivoraColors.onSurfaceVariant);
      for (final style in _allSlots(text)) {
        // google_fonts resolves to `Inter_<variant>` with `Inter` as the fallback.
        expect(style.fontFamily, startsWith('Inter'),
            reason: 'a second family is back in the scale');
        expect(style.fontFamilyFallback, contains(NivoraType.family));
      }
    });

    test('the scale is the design\'s, step for step', () {
      final text = NivoraType.textTheme(NivoraColors.onSurface, NivoraColors.onSurfaceVariant);
      const expected = <String, (double, FontWeight)>{
        'displayLarge': (32, FontWeight.w800),
        'headlineLarge': (32, FontWeight.w800),
        'displayMedium': (24, FontWeight.w800),
        'displaySmall': (24, FontWeight.w700),
        'headlineMedium': (20, FontWeight.w700),
        'titleLarge': (20, FontWeight.w700),
        'headlineSmall': (16, FontWeight.w700),
        'titleMedium': (16, FontWeight.w700),
        'bodyLarge': (15, FontWeight.w400),
        'labelLarge': (14, FontWeight.w600),
        'titleSmall': (13, FontWeight.w600),
        'bodyMedium': (13, FontWeight.w400),
        'labelMedium': (12, FontWeight.w600),
        'bodySmall': (11, FontWeight.w400),
        'labelSmall': (10, FontWeight.w600),
      };
      final actual = <String, TextStyle>{
        'displayLarge': text.displayLarge!,
        'headlineLarge': text.headlineLarge!,
        'displayMedium': text.displayMedium!,
        'displaySmall': text.displaySmall!,
        'headlineMedium': text.headlineMedium!,
        'titleLarge': text.titleLarge!,
        'headlineSmall': text.headlineSmall!,
        'titleMedium': text.titleMedium!,
        'bodyLarge': text.bodyLarge!,
        'labelLarge': text.labelLarge!,
        'titleSmall': text.titleSmall!,
        'bodyMedium': text.bodyMedium!,
        'labelMedium': text.labelMedium!,
        'bodySmall': text.bodySmall!,
        'labelSmall': text.labelSmall!,
      };
      expected.forEach((slot, spec) {
        final (size, weight) = spec;
        expect(actual[slot]!.fontSize, size, reason: '$slot size');
        expect(actual[slot]!.fontWeight, weight, reason: '$slot weight');
      });

      // Every size in the scale is a size that appears in the Figma file.
      final inFigma = <double>{32, 24, 20, 16, 15, 14, 13, 12, 11, 10};
      for (final s in actual.values) {
        expect(inFigma, contains(s.fontSize), reason: '${s.fontSize} is not a size Figma uses');
      }
    });

    test('the caps labels carry the design\'s tracking, and the body does not', () {
      final text = NivoraType.textTheme(NivoraColors.onSurface, NivoraColors.onSurfaceVariant);
      // +0.05em: 0.6 at 12px, 0.5 at 10px.
      expect(text.labelMedium!.letterSpacing, closeTo(12 * 0.05, 0.01));
      expect(text.labelSmall!.letterSpacing, closeTo(10 * 0.05, 0.01));
      expect(text.bodyMedium!.letterSpacing, 0);
      // The hero tightens instead — a 32px figure at default tracking looks loose.
      expect(text.displayLarge!.letterSpacing, lessThan(0));
    });

    test('every slot that can hold a figure uses tabular figures', () {
      final text = NivoraType.textTheme(NivoraColors.onSurface, NivoraColors.onSurfaceVariant);
      final numeric = <String, TextStyle>{
        'displayLarge': text.displayLarge!,
        'headlineLarge': text.headlineLarge!,
        'displayMedium': text.displayMedium!,
        'headlineMedium': text.headlineMedium!,
        'headlineSmall': text.headlineSmall!,
        'titleSmall': text.titleSmall!,
        'labelSmall': text.labelSmall!,
      };
      numeric.forEach((slot, style) {
        expect(style.fontFeatures, isNotNull, reason: '$slot has no font features at all');
        expect(style.fontFeatures!.map((f) => f.feature), contains('tnum'),
            reason: '$slot holds numbers and will jitter as they refresh');
      });
    });

    test('weight() actually swaps the FACE, not just the number', () {
      // The trap: with static faces the weight is baked into the resolved family name, so a
      // bare copyWith(fontWeight:) changes the number and keeps the old file.
      final text = NivoraType.textTheme(NivoraColors.onSurface, NivoraColors.onSurfaceVariant);
      final base = text.bodyMedium!; // w400
      final moved = NivoraType.weight(base, FontWeight.w700);
      expect(moved.fontWeight, FontWeight.w700);
      expect(moved.fontFamily, isNot(base.fontFamily),
          reason: 'the resolved family did not change, so the face did not either');
      expect(moved.fontSize, base.fontSize, reason: 'weight() must not disturb the size');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('rhythm', () {
    test('spacing carries the design\'s own scale and stays on the 4dp grid', () {
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
      // Figma pads at 16, gaps sections at 20 and blocks at 24, and steps down 12 / 8 / 4.
      for (final v in [4.0, 8.0, 12.0, 16.0, 20.0, 24.0]) {
        expect(scale, contains(v), reason: 'the design uses $v and the scale dropped it');
      }
      expect(Space.md, 16.0, reason: 'the card and screen padding');
    });

    test('the radius vocabulary is exactly the design\'s four steps', () {
      // 14 screen · 12 card · 8 button/input/icon · 4 badge. Built through a list rather than a
      // set literal because `surface` and `sheet` deliberately share 14.
      final named = <double>[
        Radii.tiny, Radii.control, Radii.card, Radii.surface, Radii.sheet, Radii.pill,
      ];
      expect(named.toSet(), {4.0, 8.0, 12.0, 14.0, 999.0});
      expect(Radii.tiny, lessThan(Radii.control));
      expect(Radii.control, lessThan(Radii.card));
      expect(Radii.card, lessThan(Radii.surface));
      expect(Radii.sheet, Radii.surface, reason: 'a sheet takes the screen\'s own corner');
    });

    test('every border is one hairline; only a glyph and a focus ring thicken', () {
      expect(Strokes.hairline, 1.0);
      expect(Strokes.glyph, 1.5, reason: 'the empty-state square, 4:1579');
      expect(Strokes.focus, greaterThan(Strokes.hairline));
    });

    test('the design\'s two dims are the design\'s own numbers', () {
      expect(Dim.readOnly, 0.45, reason: 'the disabled body on 4:1539');
      expect(Dim.skeletonPulse, inExclusiveRange(0, 1));
    });

    test('motion stays inside the 150–350ms band', () {
      for (final d in [Motion.fast, Motion.base, Motion.slow]) {
        expect(d.inMilliseconds, inInclusiveRange(150, 350));
      }
      expect(Motion.fast, lessThan(Motion.base));
      expect(Motion.base, lessThan(Motion.slow));
    });

    test('icons are the design\'s sizes, which are small', () {
      const sizes = [IconSize.xs, IconSize.sm, IconSize.md, IconSize.lg];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThan(sizes[i - 1]));
      }
      // Figma's header glyph is 16 inside a 32 button; the biggest glyph outside an
      // illustration is 20.
      expect(IconSize.md, 16.0);
      expect(IconSize.lg, 20.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the pane layer behaves', () {
    testWidgets('nesting panes more than one deep trips the assert', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NivoraTheme.dark(),
          home: const GlassSurface(
            child: GlassSurface(
              child: GlassSurface(child: SizedBox(width: 10, height: 10)),
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isAssertionError,
        reason: 'the nesting guard is the only thing stopping a screen exhausting the ramp',
      );
    });

    testWidgets('a stat card is flat by default and elevated only when asked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NivoraTheme.dark(),
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
          theme: NivoraTheme.dark(),
          home: const Scaffold(
            body: Center(
              child: GlassSurface(
                weight: GlassWeight.thick,
                child: SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        ),
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(GlassSurface), matching: find.byType(DecoratedBox)).first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, NivoraColors.surfaceContainerHigh);
      expect(d.color!.a, 1.0, reason: 'a pane fill with alpha is the old translucent model');
      expect(d.boxShadow, isEmpty, reason: 'a resting pane no longer casts one');
      expect((d.border! as Border).top.color, NivoraColors.outlineVariant);
    });

    testWidgets('a tappable pane still shows its ink, now that the fill is opaque',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NivoraTheme.dark(),
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
      expect(
        tester.getTopLeft(inkWell).dy,
        greaterThanOrEqualTo(tester.getTopLeft(fill.first).dy),
        reason: 'the InkWell is outside the pane fill and its splash will be hidden',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════════════════
  group('the state layer — Figma node 4:1562', () {
    testWidgets('a state card is the RAISED surface with the design\'s hairline',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NivoraTheme.dark(),
          home: const Scaffold(
            body: StateCard(badge: 'Error', child: SizedBox(width: 100, height: 20)),
          ),
        ),
      );
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(StateCard), matching: find.byType(Material)).first,
      );
      expect(material.color, NivoraColors.surfaceContainer);
      expect(find.byType(StateBadge), findsOneWidget);
    });

    testWidgets('the skeleton bar is the design\'s own #1D2227', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Skeleton(width: 50))),
      ));
      final box = tester.widget<Container>(find.byType(Container).first);
      final d = box.decoration as BoxDecoration;
      expect(_hex(d.color!), '#1D2227');
    });

    testWidgets('a skeleton STOPS when it goes off-screen, and the shared ticker stops with it',
        (tester) async {
      // The owner asked for skeletons while loading. An IndexedStack lays its other children
      // out and keeps them alive but never PAINTS them, so a naive pulse keeps burning frames
      // on a tab nobody can see. The gate is the paint probe, not a flag any shell has to set:
      // tab 1 holds no skeleton at all, so once it is selected the subscriber count and the
      // shared ticker must both go to nothing.
      var selected = 0;
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                TextButton(onPressed: () => setState(() => selected = 1), child: const Text('go')),
                Expanded(
                  child: IndexedStack(
                    index: selected,
                    children: const [
                      Center(child: Skeleton(width: 50)),
                      SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump(); // the post-frame callback that follows the first paint
      expect(shimmerClockState().subscribers, 1, reason: 'a visible skeleton animates');
      expect(shimmerClockState().running, isTrue);

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60)); // past the grace window
      expect(shimmerClockState().subscribers, 0,
          reason: 'the skeleton is laid out but no longer painted, and kept pulsing');
      expect(shimmerClockState().running, isFalse,
          reason: 'nothing is animating, so nothing should be scheduling frames');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reduced motion stops the pulse without hiding the placeholder',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: Center(child: Skeleton(width: 50))),
        ),
      ));
      await tester.pump();
      expect(shimmerClockState().subscribers, 0);
      expect(find.byType(Skeleton), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a skeleton card puts its bars on the CARD fill, not the raised one',
        (tester) async {
      // #1D2227 on #111417 is the pairing Figma draws (1.15:1). On the raised surface the bars
      // would be 1.09:1 and effectively invisible, which is why 4:1602 nests a lower rung.
      await tester.pumpWidget(MaterialApp(
        theme: NivoraTheme.dark(),
        home: const Scaffold(body: SkeletonCard()),
      ));
      final inner = tester.widget<Material>(
        find.descendant(of: find.byType(FlatSurface), matching: find.byType(Material)).last,
      );
      expect(inner.color, NivoraColors.surfaceContainerLow);
      _expectAtLeast(
        _ratio(NivoraColors.surfaceBright, NivoraColors.surfaceContainerLow),
        1.1,
        'a shimmer bar against the block it sits in',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// Every slot the scale defines, for the checks that apply to all of them.
List<TextStyle> _allSlots(TextTheme t) => [
      t.displayLarge!, t.displayMedium!, t.displaySmall!,
      t.headlineLarge!, t.headlineMedium!, t.headlineSmall!,
      t.titleLarge!, t.titleMedium!, t.titleSmall!,
      t.bodyLarge!, t.bodyMedium!, t.bodySmall!,
      t.labelLarge!, t.labelMedium!, t.labelSmall!,
    ];
