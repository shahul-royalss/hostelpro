import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/shared/brow.dart';
import 'package:mobile/shared/brow_header.dart';
import 'package:mobile/shared/clay/app_header.dart';
import 'package:mobile/shared/glass/glass.dart';

/// THE BROW — the one device taken wholesale from the competitor teardown, now the forest
/// header's own backdrop.
///
/// What is worth pinning here is not that it draws (a glance tells you that) but the things
/// that were wrong the first time it was built and would be silently wrong again: the status
/// bar's icons, the header's fill, and the brow being the SAME paint in both themes rather than
/// a theme-resolved one.
Widget _host({required Widget child, Brightness brightness = Brightness.light}) => MaterialApp(
      theme: brightness == Brightness.light ? ApnivaasTheme.light() : ApnivaasTheme.dark(),
      home: Scaffold(backgroundColor: Colors.transparent, body: child),
    );

/// The backdrop painters under [of].
Iterable<HeaderBackdropPainter> _backdrops(WidgetTester tester, Finder of) => tester
    .widgetList<CustomPaint>(find.descendant(of: of, matching: find.byType(CustomPaint)))
    .map((p) => p.painter)
    .whereType<HeaderBackdropPainter>();

void main() {
  group('the brow', () {
    testWidgets('paints the forest header backdrop, and the SAME one in both themes',
        (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(_host(
          brightness: b,
          child: const BrandBrow(child: SizedBox.expand()),
        ));
        final painters = _backdrops(tester, find.byType(BrandBrow)).toList();
        expect(painters, hasLength(1),
            reason: 'the brow is the header gradient and its stars in $b — the one surface a '
                'light phone and a dark phone render identically');
        expect(painters.single.stars, isTrue);
      }
      // The gradient it paints is the header's, and every stop is opaque: content scrolls past
      // it and nothing may show through.
      for (final c in ApnivaasColors.headerGradient.colors) {
        expect(c.a, 1.0);
      }
    });

    testWidgets('flips the status bar to light icons, because the band is dark in both themes',
        (tester) async {
      // The root sets the overlay style from the theme's brightness, which is right everywhere
      // else. On a light-mode phone that means DARK status icons, and dark icons on forest are
      // a clock nobody can read.
      await tester.pumpWidget(_host(child: const BrandBrow(child: SizedBox.expand())));
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(region.value.statusBarIconBrightness, Brightness.light);
      expect(region.value, ApnivaasTheme.onForest);
    });

    testWidgets('draws nothing at all when disabled', (tester) async {
      await tester.pumpWidget(_host(
        child: const BrandBrow(enabled: false, child: SizedBox.expand()),
      ));
      expect(_backdrops(tester, find.byType(BrandBrow)), isEmpty);
      expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsNothing);
    });

    testWidgets("the bottom edge is the header's rounded corners, not the old dip",
        (tester) async {
      await tester.pumpWidget(_host(child: const BrandBrow(height: 200, child: SizedBox.expand())));
      final clip = tester.widget<ClipRRect>(
        find.descendant(of: find.byType(BrandBrow), matching: find.byType(ClipRRect)),
      );
      expect(clip.borderRadius, Radii.rHeaderBottom);
      expect(find.descendant(of: find.byType(BrandBrow), matching: find.byType(ClipPath)),
          findsNothing);
    });
  });

  group('a header on the brow', () {
    testWidgets('IS the forest header — opaque gradient, rounded, white ink', (tester) async {
      await tester.pumpWidget(_host(child: const GlassHeader(onBrow: true, child: Text('Rooms'))));

      // OPAQUE, not transparent. The first design made it see-through over a full-height brow
      // and the list scrolled up THROUGH it — a header that is not opaque is not a header.
      expect(find.byType(GlassSurface), findsNothing,
          reason: 'it paints the header backdrop directly, not a pane');
      expect(_backdrops(tester, find.byType(BrowHeaderFrame)), hasLength(1));
      expect(BrowInk.bright, ApnivaasColors.forestHigh);
      expect(BrowInk.bright.a, 1.0);

      final style = DefaultTextStyle.of(tester.element(find.text('Rooms'))).style;
      expect(style.color, ApnivaasColors.headerTitle,
          reason: 'white is 7.28:1 on the lightest stop of the header, in both themes');
      expect(
        tester.widget<IconTheme>(find.ancestor(
          of: find.text('Rooms'),
          matching: find.byType(IconTheme),
        ).first).data.color,
        ApnivaasColors.headerTitle,
        reason: 'a header that flipped only the text would go half-white',
      );
    });

    testWidgets('has the 30dp bottom corners, and its content clears them', (tester) async {
      await tester.pumpWidget(_host(child: const GlassHeader(onBrow: true, child: Text('R'))));
      final clip = tester.widget<ClipRRect>(
        find.descendant(of: find.byType(BrowHeaderFrame), matching: find.byType(ClipRRect)),
      );
      expect(clip.borderRadius, Radii.rHeaderBottom);
      expect(GlassHeader.browDip, AppHeader.bottomInset,
          reason: 'the brow and the forest header leave the same room under their content');
    });

    testWidgets('an ordinary header is the cream bar with a hairline, in the theme ink',
        (tester) async {
      await tester.pumpWidget(_host(child: const GlassHeader(child: Text('Rooms'))));
      expect(find.byType(GlassSurface), findsNothing);
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(GlassHeader), matching: find.byType(DecoratedBox)).first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, ApnivaasColors.cream);
      expect((d.border! as Border).bottom.color, ApnivaasColors.cardBorder);
      expect(d.boxShadow, isNull, reason: 'a bar on the page casts nothing');
    });
  });
}
