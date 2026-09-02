import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/features/owner/widgets/states.dart' as owner;
import 'package:mobile/shared/glass/glass.dart';
import 'package:mobile/shared/illustrations.dart';
import 'package:mobile/shared/motion/entrance.dart';

/// The three things the "make it colourful" pass added, held to their own rules.
///
/// `theme_contrast_test.dart` owns the arithmetic — every ratio and the container identity are
/// measured there. This file owns the BEHAVIOUR: that the artwork reaches the owner's screens,
/// that a tinted card paints the colour the arithmetic assumed and does not grow a chip, and
/// that the entrance obeys the switch that turns it off.
void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Brightness? brightness}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light ? NivoraTheme.light() : NivoraTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ───────────────────────────────────────────────────────────────────────────
  group('the owner\'s first-run screens draw the artwork, not a glyph', () {
    // The four screens a brand-new PG owner opens are empty by definition. They had the same
    // 56dp outlined square the "no match for that" state uses, which is what an unfinished app
    // looks like on the day somebody starts paying for it.
    testWidgets('a first-run empty state shows its drawing', (tester) async {
      await pump(
        tester,
        const owner.EmptyNote(
          icon: Icons.people_outline_rounded,
          illustration: EmptyArt.residents,
          title: 'No residents yet',
          message: 'Residents appear here as your warden registers them.',
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      // Instead of the glyph, never beside it — two drawings of one idea.
      expect(find.byIcon(Icons.people_outline_rounded), findsNothing);
      // The words are never baked into the picture: they stay translatable and selectable.
      expect(find.text('No residents yet'), findsOneWidget);
    });

    testWidgets('a SEARCH miss keeps the glyph — the drawing would be a lie', (tester) async {
      // "Nothing here yet" and "no match for that" are different facts. The owner roster passes
      // null for the illustration whenever a search term is active, and this is that contract.
      await pump(
        tester,
        const owner.EmptyNote(
          icon: Icons.search_off_rounded,
          title: 'Nobody matches “kumar”',
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('a tinted card is its own status', () {
    Color fillOf(WidgetTester tester) {
      final material = tester.widget<Material>(
        find
            .descendant(of: find.byType(ToneSurface), matching: find.byType(Material))
            .first,
      );
      return material.color!;
    }

    testWidgets('dark: the ground is the tone over the card fill — the container hex',
        (tester) async {
      await pump(
        tester,
        const ToneSurface(tone: NivoraColors.error, child: Text('Rent')),
      );
      // #241D20 — which is also NivoraColors.errorContainer. See theme_contrast_test.dart.
      expect(
        fillOf(tester).toARGB32() & 0xFFFFFF,
        NivoraColors.errorContainer.toARGB32() & 0xFFFFFF,
      );
    });

    testWidgets('light: the SAME call paints a light tint, not the dark one', (tester) async {
      // The rule the brief is emphatic about: a tint that reads on #0B0D0F can be invisible on
      // #FFF8F3. One widget, one tone, two grounds — and they must not be the same colour.
      await pump(
        tester,
        const ToneSurface(tone: NivoraColors.error, child: Text('Rent')),
        brightness: Brightness.light,
      );
      final light = fillOf(tester).toARGB32() & 0xFFFFFF;

      expect(light, isNot(NivoraColors.errorContainer.toARGB32() & 0xFFFFFF),
          reason: 'the dark container hex on a white card would be a near-black box');
      // It is a tint OF WHITE: still bright, but no longer neutral.
      expect(light, greaterThan(0xE0E0E0),
          reason: 'a light tint must stay a light surface');
    });

    testWidgets('no tone paints the plain surface, so "nothing is wrong" is not coloured',
        (tester) async {
      await pump(tester, const ToneSurface(tone: null, child: Text('Rent')));
      expect(find.byType(FlatSurface), findsOneWidget);
    });

    testWidgets('the status word is drawn in its tone, and there is no chip', (tester) async {
      await pump(
        tester,
        const ToneSurface(
          tone: NivoraColors.error,
          statusLabel: 'Unpaid',
          child: Text('₹6,200'),
        ),
      );

      // The WORD survives, because that is the half a red-green deficiency depends on.
      final label = tester.widget<Text>(find.text('UNPAID'));
      expect(label.style?.color, NivoraColors.errorDark);

      // And no StateBadge/StatusPill got nested inside it. A chip of the same tone on this
      // ground measures 3.98:1 in the dark theme — see NivoraSemantics.surfaceTintAlpha.
      expect(
        find.descendant(of: find.byType(ToneSurface), matching: find.byType(StateBadge)),
        findsNothing,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('the entrance arrives once and can be switched off', () {
    testWidgets('reduce motion returns the child untouched — no animation at all',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: Entrance(child: Text('Collected'))),
          ),
        ),
      );
      // Not a faster animation. None: that switch is set by people for whom movement on screen
      // is a symptom. Scoped INSIDE the Entrance — MaterialApp's own page route is built from
      // FadeTransitions and finding those would make this test pass for the wrong reason.
      expect(
        find.descendant(of: find.byType(Entrance), matching: find.byType(FadeTransition)),
        findsNothing,
      );
      expect(find.text('Collected'), findsOneWidget);
    });

    testWidgets('the child is laid out and hit-testable from the first frame', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Entrance(
              index: 4,
              child: GestureDetector(
                onTap: () => taps++,
                child: const Text('Collected'),
              ),
            ),
          ),
        ),
      );
      // ONE frame — mid-stagger, before this item's own interval has even opened.
      await tester.pump();
      expect(find.text('Collected'), findsOneWidget);

      // A resident who taps a row before it has finished arriving gets the row. The entrance
      // changes how the child is painted, never whether it exists.
      await tester.tap(find.text('Collected'));
      expect(taps, 1);

      await tester.pumpAndSettle();
    });

    testWidgets('it settles — nothing here runs continuously', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Entrance(index: 3, child: Text('Collected')))),
      );
      // pumpAndSettle throws if frames never stop. A looping entrance would hang here, which
      // is the cheapest possible guard against somebody making this pulse.
      await tester.pumpAndSettle();

      final fade = tester.widget<FadeTransition>(
        find.descendant(of: find.byType(Entrance), matching: find.byType(FadeTransition)),
      );
      expect(fade.opacity.value, 1.0);
    });

    testWidgets('the stagger is capped, so a long list does not compute a long ramp',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Entrance(index: 500, child: Text('Row')))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Row'), findsOneWidget);
      expect(Motion.stagger * Motion.staggerCap + Motion.base,
          lessThan(const Duration(milliseconds: 700)),
          reason: 'the longest an item may wait before it has arrived');
    });
  });
}
