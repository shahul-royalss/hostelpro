import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/shared/brow.dart';
import 'package:mobile/shared/glass/glass.dart';

/// THE BROW — the one device taken wholesale from the competitor teardown.
///
/// What is worth pinning here is not that it draws (a glance tells you that) but the three
/// things that were wrong the first time it was built and would be silently wrong again:
/// the status bar's icons, the header's fill, and the brow being the SAME colour in both
/// themes rather than a theme-resolved one.
Widget _host({required Widget child, Brightness brightness = Brightness.light}) => MaterialApp(
      theme: brightness == Brightness.light ? NivoraTheme.light() : NivoraTheme.dark(),
      home: Scaffold(backgroundColor: Colors.transparent, body: child),
    );

void main() {
  group('the brow', () {
    testWidgets('paints the brand block, and the SAME one in both themes', (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(_host(
          brightness: b,
          child: const BrandBrow(child: SizedBox.expand()),
        ));
        // Scoped to the ClipPath's own subtree: `find.byType(ColoredBox).first` picks up a
        // transparent box the Scaffold puts higher in the tree, which is how this test failed
        // the first time it ran.
        final box = tester.widget<ColoredBox>(
          find.descendant(of: find.byType(ClipPath), matching: find.byType(ColoredBox)),
        );
        expect(box.color, NivoraColors.brandDeep,
            reason: 'the brow is #4D2896 in $b — it is the one surface a light phone and a '
                'dark phone render identically, which is what makes it a brand mark');
      }
    });

    testWidgets('flips the status bar to light icons, because the band is dark in both themes',
        (tester) async {
      // The bug this prevents: the root sets the overlay style from the theme's brightness,
      // which is right everywhere else. On a light-mode phone that means DARK status icons,
      // and dark icons on #4D2896 are a clock nobody can read.
      await tester.pumpWidget(_host(child: const BrandBrow(child: SizedBox.expand())));
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(region.value.statusBarIconBrightness, Brightness.light);
    });

    testWidgets('draws nothing at all when disabled', (tester) async {
      await tester.pumpWidget(_host(
        child: const BrandBrow(enabled: false, child: SizedBox.expand()),
      ));
      expect(find.byType(ClipPath), findsNothing);
      expect(find.byType(AnnotatedRegion<SystemUiOverlayStyle>), findsNothing);
    });

    testWidgets('the curve is a real curve — the clip is not the full rectangle',
        (tester) async {
      const clipper = BrandBrow(child: SizedBox.expand());
      await tester.pumpWidget(_host(child: clipper));
      final clip = tester.widget<ClipPath>(find.byType(ClipPath));
      final path = clip.clipper!.getClip(const Size(400, 300));
      // The centre of the bottom edge bulges BELOW the corners: that is the whole device.
      expect(path.contains(const Offset(200, 295)), isTrue,
          reason: 'the middle of the band reaches further down than its corners');
      expect(path.contains(const Offset(4, 295)), isFalse,
          reason: 'the corners stop short, which is what makes it read as an arc');
    });
  });

  group('a header on the brow', () {
    testWidgets('goes transparent and white, instead of covering the colour', (tester) async {
      await tester.pumpWidget(_host(
        child: const BrandBrow(
          child: GlassHeader(onBrow: true, child: Text('Rooms')),
        ),
      ));
      // The failure this catches: leaving the normal bar fill on, which paints a near-white
      // slab over the band and strands a stripe of brand below the header.
      expect(find.byType(GlassSurface), findsNothing,
          reason: 'an on-brow header paints no surface of its own');
      final style = DefaultTextStyle.of(
        tester.element(find.text('Rooms')),
      ).style;
      expect(style.color, const Color(0xFFFFFFFF),
          reason: 'white is 10.20:1 on the brow, in both themes');
    });

    testWidgets('an ordinary header still paints its bar', (tester) async {
      await tester.pumpWidget(_host(child: const GlassHeader(child: Text('Rooms'))));
      expect(find.byType(GlassSurface), findsOneWidget);
    });
  });
}
