import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/shared/glass/glass.dart';

/// Contrast is a measurable property, so it is tested rather than asserted in a comment.
///
/// The palette in tokens.dart quotes a ratio next to almost every colour. Comments rot; the
/// point of this file is that they cannot. Every ratio quoted there is recomputed here from
/// the token itself, and a colour nudged by eye fails `flutter test` with the number it
/// actually measured.
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
/// see [_over] — because a ratio against a colour that has alpha is meaningless.
double _ratio(Color a, Color b) {
  assert(a.a == 1.0 && b.a == 1.0, 'composite translucent colours before measuring');
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Flattens [fg] (which may be translucent) onto opaque [bg], the way the compositor will.
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

// The surfaces a colour can land on. Named so a failure says where.
const _lightSurfaces = <String, Color>{
  'surface #FFFFFF': NivoraColors.surface,
  'canvas #F6F8FC': NivoraColors.background,
  'container #EEF2F8': Color(0xFFEEF2F8),
};
const _darkSurfaces = <String, Color>{
  'bg #070B14': NivoraColors.darkBackground,
  'surface #101827': NivoraColors.darkSurface,
  'elevated #151F32': NivoraColors.darkElevated,
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
    _expectAtLeast(_ratio(fg, bg), need, '$name on $where');
  });
}

void main() {
  group('light theme — text is AA (4.5:1)', () {
    test('neutral ramp', () {
      _againstAll(_lightSurfaces, NivoraColors.textPrimary, 4.5, 'textPrimary');
      _againstAll(_lightSurfaces, NivoraColors.textSecondary, 4.5, 'textSecondary');
      _againstAll(_lightSurfaces, NivoraColors.mutedInk, 4.5, 'mutedInk');
    });

    test('brand as text', () {
      _againstAll(_lightSurfaces, NivoraColors.indigo, 4.5, 'indigo');
      _againstAll(_lightSurfaces, NivoraColors.softBlueInk, 4.5, 'softBlueInk');
    });

    test('semantic ink set', () {
      _againstAll(_lightSurfaces, NivoraColors.successInk, 4.5, 'successInk');
      _againstAll(_lightSurfaces, NivoraColors.warningInk, 4.5, 'warningInk');
      _againstAll(_lightSurfaces, NivoraColors.errorInk, 4.5, 'errorInk');
      _againstAll(_lightSurfaces, NivoraColors.infoInk, 4.5, 'infoInk');
    });

    test('the ramp is an actual hierarchy, not three shades of the same grey', () {
      // Each step must be visibly quieter than the one above it, or the hierarchy is a lie.
      final primary = _ratio(NivoraColors.textPrimary, NivoraColors.surface);
      final secondary = _ratio(NivoraColors.textSecondary, NivoraColors.surface);
      final muted = _ratio(NivoraColors.mutedInk, NivoraColors.surface);
      expect(primary, greaterThan(secondary * 1.5));
      expect(secondary, greaterThan(muted * 1.2));
      // ...but the quietest step is still AA. "Muted" means quieter, never fainter than AA.
      expect(muted, greaterThanOrEqualTo(4.5));
    });
  });

  group('dark theme — text is AA (4.5:1)', () {
    test('neutral ramp', () {
      _againstAll(_darkSurfaces, NivoraColors.darkTextPrimary, 4.5, 'darkTextPrimary');
      _againstAll(_darkSurfaces, NivoraColors.darkTextSecondary, 4.5, 'darkTextSecondary');
      _againstAll(_darkSurfaces, NivoraColors.darkMuted, 4.5, 'darkMuted');
    });

    test('brand as text', () {
      _againstAll(_darkSurfaces, NivoraColors.darkIndigo, 4.5, 'darkIndigo');
      _againstAll(_darkSurfaces, NivoraColors.softBlue, 4.5, 'softBlue');
    });

    test('semantic dark set', () {
      _againstAll(_darkSurfaces, NivoraColors.successDark, 4.5, 'successDark');
      _againstAll(_darkSurfaces, NivoraColors.warningDark, 4.5, 'warningDark');
      _againstAll(_darkSurfaces, NivoraColors.errorDark, 4.5, 'errorDark');
      _againstAll(_darkSurfaces, NivoraColors.infoDark, 4.5, 'infoDark');
    });
  });

  group('graphical objects and controls are 3:1 (WCAG 1.4.11)', () {
    test('canonical semantics clear 3:1 in BOTH themes', () {
      // These are the values painted without a BuildContext — chart bars, meter fills, icons.
      // They are a deliberate dual-theme compromise, so they are held to the graphics bar in
      // every theme rather than to the text bar in one.
      const canonical = <String, Color>{
        'success': NivoraColors.success,
        'warning': NivoraColors.warning,
        'error': NivoraColors.error,
        'info': NivoraColors.info,
        'textMuted': NivoraColors.textMuted,
      };
      canonical.forEach((name, c) {
        _againstAll(_lightSurfaces, c, 3.0, '$name (canonical, light)');
        _againstAll(_darkSurfaces, c, 3.0, '$name (canonical, dark)');
      });
    });

    test('a control border is the control, so it is 3:1 — not the card hairline', () {
      _againstAll(_lightSurfaces, NivoraColors.controlBorder, 3.0, 'controlBorder');
      _againstAll(_darkSurfaces, NivoraColors.darkControlBorder, 3.0, 'darkControlBorder');
      // And the decorative borders are deliberately BELOW that, which is the whole reason
      // there are three border tokens. If these ever climb to 3:1 someone has collapsed them
      // into one value and every card has grown a heavy outline.
      expect(_ratio(NivoraColors.hairline, NivoraColors.surface), lessThan(1.5));
      expect(_ratio(NivoraColors.cardBorder, NivoraColors.surface), lessThan(3.0));
    });
  });

  group('filled surfaces — the other direction', () {
    test('a filled button is legible from the inside', () {
      _expectAtLeast(
          _ratio(Colors.white, NivoraColors.indigo), 4.5, 'white on indigo (FilledButton)');
      _expectAtLeast(_ratio(Colors.white, NivoraColors.softBlueInk), 4.5, 'white on softBlueInk');
      _expectAtLeast(_ratio(Colors.white, NivoraColors.errorInk), 4.5, 'white on errorInk');
      _expectAtLeast(
          _ratio(Colors.white, NivoraColors.midnight), 4.5, 'white on midnight (snackbar)');
      _expectAtLeast(
          _ratio(NivoraColors.midnight, NivoraColors.darkIndigo), 4.5, 'midnight on darkIndigo');
      _expectAtLeast(
          _ratio(NivoraColors.midnight, NivoraColors.softBlue), 4.5, 'midnight on softBlue');
      _expectAtLeast(
          _ratio(NivoraColors.midnight, NivoraColors.errorDark), 4.5, 'midnight on errorDark');
    });

    test('both schemes agree with themselves about on-colours', () {
      final light = NivoraTheme.light().colorScheme;
      final dark = NivoraTheme.dark().colorScheme;
      _expectAtLeast(_ratio(light.onPrimary, light.primary), 4.5, 'light onPrimary');
      _expectAtLeast(_ratio(light.onSecondary, light.secondary), 4.5, 'light onSecondary');
      _expectAtLeast(_ratio(light.onSurface, light.surface), 4.5, 'light onSurface');
      _expectAtLeast(_ratio(light.onError, light.error), 4.5, 'light onError');
      _expectAtLeast(_ratio(dark.onPrimary, dark.primary), 4.5, 'dark onPrimary');
      _expectAtLeast(_ratio(dark.onSecondary, dark.secondary), 4.5, 'dark onSecondary');
      _expectAtLeast(_ratio(dark.onSurface, dark.surface), 4.5, 'dark onSurface');
      _expectAtLeast(_ratio(dark.onError, dark.error), 4.5, 'dark onError');
    });
  });

  group('status chips — the tightest case in the app', () {
    // 11px type on an 8–10% tint of itself. The tint moves the background TOWARDS the text,
    // so the ratio falls as the alpha rises; this is the pair most likely to be broken by
    // someone picking a plausible-looking alpha.
    void checkChips(NivoraSemantics tones, Map<String, Color> surfaces, String theme) {
      final byName = <String, Color>{
        'success': tones.success,
        'warning': tones.warning,
        'error': tones.error,
        'info': tones.info,
        'muted': tones.muted,
      };
      byName.forEach((name, ink) {
        surfaces.forEach((where, bg) {
          final fill = _over(tones.chipFill(ink), bg);
          _expectAtLeast(_ratio(ink, fill), 4.5, '$theme chip $name on $where');
        });
      });
    }

    test('light chips', () => checkChips(NivoraSemantics.light, _lightSurfaces, 'light'));
    test('dark chips', () => checkChips(NivoraSemantics.dark, _darkSurfaces, 'dark'));

    test('a chip border is visible against the surface it sits on', () {
      for (final entry in _lightSurfaces.entries) {
        final border = _over(NivoraSemantics.light.chipBorder(NivoraColors.errorInk), entry.value);
        expect(_ratio(border, entry.value), greaterThan(1.3),
            reason: 'light chip border invisible on ${entry.key}');
      }
    });

    test('resolve() maps canonical to the theme text value, and passes anything else through',
        () {
      expect(NivoraSemantics.light.resolve(NivoraColors.error), NivoraColors.errorInk);
      expect(NivoraSemantics.dark.resolve(NivoraColors.error), NivoraColors.errorDark);
      expect(NivoraSemantics.light.resolve(NivoraColors.textMuted), NivoraColors.mutedInk);
      // Not a canonical value: untouched.
      expect(NivoraSemantics.light.resolve(NivoraColors.indigo), NivoraColors.indigo);
    });
  });

  group('glass panes stay readable over what is actually behind them', () {
    // A pane paints its theme's surface at weight.opacity. What shows through is whatever is
    // behind, so the pane is only as legible as the worst backdrop that weight can sit over.
    // The weakest body text in each theme is the one that has to survive it.
    void checkPane(
      GlassWeight weight,
      Color veil,
      Color text,
      Map<String, Color> backdrops,
      String theme,
    ) {
      backdrops.forEach((where, backdrop) {
        final pane = _over(veil.withValues(alpha: weight.opacity), backdrop);
        _expectAtLeast(
          _ratio(text, pane),
          4.5,
          '$theme ${weight.name} pane over $where — weakest body text',
        );
      });
    }

    test('thin: a resting card, and only the canvas is behind it', () {
      checkPane(GlassWeight.thin, NivoraColors.surface, NivoraColors.mutedInk,
          {'canvas': NivoraColors.background}, 'light');
      checkPane(GlassWeight.thin, NivoraColors.darkSurface, NivoraColors.darkMuted,
          {'dark bg': NivoraColors.darkBackground, 'dark surface': NivoraColors.darkSurface},
          'dark');
    });

    test('regular: a header with a list of filled cards scrolling under it', () {
      checkPane(GlassWeight.regular, NivoraColors.surface, NivoraColors.mutedInk, {
        'canvas': NivoraColors.background,
        'a white card': NivoraColors.surface,
        'a filled indigo card': NivoraColors.indigo,
        'a success meter': NivoraColors.success,
      }, 'light');
      checkPane(GlassWeight.regular, NivoraColors.darkSurface, NivoraColors.darkMuted, {
        'dark bg': NivoraColors.darkBackground,
        'dark surface': NivoraColors.darkSurface,
        'dark elevated': NivoraColors.darkElevated,
        'a filled indigo card': NivoraColors.darkIndigo,
      }, 'dark');
    });

    test('thick: a sheet over literally anything, including the extremes', () {
      checkPane(GlassWeight.thick, NivoraColors.surface, NivoraColors.mutedInk, {
        'canvas': NivoraColors.background,
        'a filled indigo card': NivoraColors.indigo,
        'an error fill': NivoraColors.error,
        'solid brand navy': NivoraColors.midnight,
      }, 'light');
      checkPane(GlassWeight.thick, NivoraColors.darkSurface, NivoraColors.darkMuted, {
        'dark bg': NivoraColors.darkBackground,
        'dark elevated': NivoraColors.darkElevated,
        'a filled indigo card': NivoraColors.darkIndigo,
        'a warning fill': NivoraColors.warningDark,
        'pure white': Color(0xFFFFFFFF),
      }, 'dark');
    });

    test('the dark veil is the dark SURFACE, not white — the regression guard', () {
      // A white veil over a dark theme lightens the pane TOWARDS its own near-white text, so
      // the brighter the thing behind, the less readable the pane becomes. That is the bug
      // this model exists to fix, and it is not fixable by tuning the opacity: raising a white
      // veil walks the pane towards pure white, which is worse still.
      const bright = NivoraColors.darkIndigo; // a filled button scrolling under the pane

      // 1. The DIRECTIONAL claim, true at every weight: veiling with the surface beats veiling
      //    with white, and not marginally.
      for (final weight in GlassWeight.values) {
        final white = _ratio(NivoraColors.darkMuted,
            _over(const Color(0xFFFFFFFF).withValues(alpha: weight.opacity), bright));
        final surface = _ratio(NivoraColors.darkMuted,
            _over(NivoraColors.darkSurface.withValues(alpha: weight.opacity), bright));
        expect(surface, greaterThan(white * 1.5),
            reason: '${weight.name}: the white veil is no longer clearly worse — re-derive the '
                'model rather than trusting this test');
      }

      // 2. The ABSOLUTE claim, and only for the weights that actually face a bright backdrop.
      //    thin is deliberately excluded: it is documented as sitting over the page canvas and
      //    nothing else, which is what buys it the right to stay genuinely translucent. If a
      //    screen ever puts a thin pane over content, it needs regular, not a new number here.
      for (final weight in [GlassWeight.regular, GlassWeight.thick]) {
        _expectAtLeast(
            _ratio(NivoraColors.darkMuted,
                _over(NivoraColors.darkSurface.withValues(alpha: weight.opacity), bright)),
            4.5,
            '${weight.name} surface-veiled pane over a filled button');
        expect(
            _ratio(NivoraColors.darkMuted,
                _over(const Color(0xFFFFFFFF).withValues(alpha: weight.opacity), bright)),
            lessThan(4.5),
            reason: '${weight.name}: a white veil should still fail here');
      }
    });

    test('opacity rises with what the weight has to survive', () {
      expect(GlassWeight.thin.opacity, lessThan(GlassWeight.regular.opacity));
      expect(GlassWeight.regular.opacity, lessThan(GlassWeight.thick.opacity));
      // Blur is the expensive part. It stays modest at every weight.
      for (final w in GlassWeight.values) {
        expect(w.blur, lessThanOrEqualTo(20), reason: '${w.name} blur is a frame budget');
      }
    });

    test('a pane edge is visible in both themes', () {
      final lightPane = _over(
          NivoraColors.surface.withValues(alpha: GlassWeight.thin.opacity),
          NivoraColors.background);
      final lightEdge =
          _over(NivoraColors.midnight.withValues(alpha: GlassWeight.lightEdge), lightPane);
      expect(_ratio(lightEdge, lightPane), greaterThan(1.3),
          reason: 'the light pane edge has gone back to being invisible');

      final darkPane = _over(
          NivoraColors.darkSurface.withValues(alpha: GlassWeight.thin.opacity),
          NivoraColors.darkBackground);
      final darkEdge =
          _over(const Color(0xFFFFFFFF).withValues(alpha: GlassWeight.darkEdge), darkPane);
      expect(_ratio(darkEdge, darkPane), greaterThan(1.3),
          reason: 'the dark pane edge has gone back to being invisible');
    });
  });

  group('the tokens are actually wired into the themes', () {
    test('hint text is text, so it is AA — not the old 2.58:1 placeholder grey', () {
      for (final entry in {
        'light': (NivoraTheme.light(), NivoraColors.surface),
        'dark': (NivoraTheme.dark(), NivoraColors.darkElevated),
      }.entries) {
        final (theme, fieldFill) = entry.value;
        final hint = theme.inputDecorationTheme.hintStyle?.color;
        expect(hint, isNotNull, reason: '${entry.key} hintStyle lost its colour');
        _expectAtLeast(_ratio(hint!, fieldFill), 4.5, '${entry.key} hint on the field fill');
      }
    });

    test('an input border is the field, so it is 3:1 against the field fill', () {
      final light = NivoraTheme.light();
      final lightBorder = light.inputDecorationTheme.enabledBorder as OutlineInputBorder;
      _expectAtLeast(_ratio(lightBorder.borderSide.color, NivoraColors.surface), 3.0,
          'light input border');
      final dark = NivoraTheme.dark();
      final darkBorder = dark.inputDecorationTheme.enabledBorder as OutlineInputBorder;
      _expectAtLeast(_ratio(darkBorder.borderSide.color, NivoraColors.darkElevated), 3.0,
          'dark input border');
    });

    test('a drag handle is a control, so it is 3:1', () {
      _expectAtLeast(
          _ratio(NivoraTheme.light().bottomSheetTheme.dragHandleColor!, NivoraColors.surface),
          3.0,
          'light drag handle');
      _expectAtLeast(
          _ratio(NivoraTheme.dark().bottomSheetTheme.dragHandleColor!, NivoraColors.darkElevated),
          3.0,
          'dark drag handle');
    });

    test('NivoraSemantics is registered on both themes', () {
      expect(NivoraTheme.light().extension<NivoraSemantics>(), NivoraSemantics.light);
      expect(NivoraTheme.dark().extension<NivoraSemantics>(), NivoraSemantics.dark);
    });
  });

  group('typography', () {
    test('every slot that can hold a figure uses tabular figures', () {
      final text = NivoraTheme.light().textTheme;
      const tabular = FontFeature.tabularFigures();
      for (final entry in {
        'headlineLarge (the hero figure)': text.headlineLarge,
        'headlineMedium (a stat value)': text.headlineMedium,
        'titleSmall (a stat inside a row)': text.titleSmall,
        'labelSmall (chips and counts)': text.labelSmall,
      }.entries) {
        expect(entry.value?.fontFeatures, contains(tabular),
            reason: '${entry.key} lost tabular figures — money columns will shuffle');
      }
    });

    test('the scale is a hierarchy with real steps', () {
      final t = NivoraTheme.light().textTheme;
      final sizes = [
        t.headlineLarge!.fontSize!,
        t.displaySmall!.fontSize!,
        t.headlineMedium!.fontSize!,
        t.titleLarge!.fontSize!,
        t.titleMedium!.fontSize!,
        t.bodyMedium!.fontSize!,
        t.bodySmall!.fontSize!,
        t.labelSmall!.fontSize!,
      ];
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], lessThan(sizes[i - 1]),
            reason: 'step $i (${sizes[i]}) does not sit below ${sizes[i - 1]}');
      }
      // The hero number dwarfs body text — that is the whole point of a dashboard.
      expect(t.headlineLarge!.fontSize!, greaterThanOrEqualTo(t.bodyLarge!.fontSize! * 2));
      // Body text is 16px: this is read on a phone in a corridor, not at a desk.
      expect(t.bodyLarge!.fontSize, greaterThanOrEqualTo(16));
      // Almost nothing is bold, and nothing is w700.
      for (final s in [t.titleLarge, t.titleMedium, t.headlineLarge, t.labelLarge]) {
        expect(s!.fontWeight!.value, lessThanOrEqualTo(FontWeight.w600.value));
      }
    });
  });

  group('rhythm', () {
    test('spacing is a single 4dp scale with no one-offs', () {
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
    });

    test('radii are graduated, so a chip and a sheet are not equally round', () {
      expect(Radii.control, lessThan(Radii.card));
      expect(Radii.card, lessThan(Radii.surface));
      expect(Radii.surface, lessThan(Radii.sheet));
    });

    test('every border is one hairline; weight comes from colour, not width', () {
      expect(Strokes.hairline, 1.0);
      expect(Strokes.focus, greaterThan(Strokes.hairline));
    });
  });

  group('glass is an elevation cue, not a skin', () {
    testWidgets('nesting glass more than one deep trips the assert', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NivoraTheme.light(),
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
        reason: 'the nesting guard is the only thing stopping a screen becoming fog',
      );
    });

    testWidgets('a stat card is flat by default and glass only when asked', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NivoraTheme.light(),
          home: const Scaffold(
            body: Column(
              children: [
                GlassStatCard(label: 'Occupied', value: '42'),
                GlassStatCard(label: 'Collected', value: '₹1,20,000', emphasised: true),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(FlatSurface), findsOneWidget);
      expect(find.byType(GlassSurface), findsOneWidget);
    });

    testWidgets('the fallback keeps the geometry and drops only the filter', (tester) async {
      Future<Size> measure(bool fallback) async {
        Motion.glassFallback = fallback;
        await tester.pumpWidget(
          MaterialApp(
            theme: NivoraTheme.light(),
            home: const Scaffold(
              body: Center(
                child: GlassCard(child: SizedBox(width: 120, height: 60)),
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.getSize(find.byType(GlassCard));
      }

      final blurred = await measure(false);
      final opaque = await measure(true);
      Motion.glassFallback = false;
      expect(opaque, blurred, reason: 'the fallback must not reflow anything');
    });
  });
}
