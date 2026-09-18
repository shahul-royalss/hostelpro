import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/features/manager/widgets/manager_ui.dart' show ManagerScreen;
import 'package:mobile/features/super_admin/widgets/sa_ui.dart' show SaIconButton, SaScreen;
import 'package:mobile/features/warden/widgets/warden_ui.dart' show ToneDot, WardenScreen;
import 'package:mobile/shared/brow_header.dart';
import 'package:mobile/shared/glass/glass.dart';
import 'package:mobile/shared/wordmark.dart';

/// THE BRAND HEADER — held to the four things the owner's screenshot and brief asked for.
///
///  1. The lines are LIGHT, whatever theme the phone is in. The bug was the Super Admin
///     "Subscriptions" header drawn in the theme's dark ink on violet, so the SaScreen tests
///     read the colour the paragraph was actually laid out with, in both themes, and measure it.
///     The icon buttons in `actions` are read the same way, disabled ones included: a Material 3
///     IconButton does not take its colour from IconTheme alone.
///  2. The entrance runs once and then nothing ticks: `hasScheduledFrame` is the proof, because a
///     controller left running schedules a frame forever.
///  3. Reduce motion means no animation at all, from the first frame.
///  4. Nothing overflows at 320dp, with long strings, at the root's 1.4x text ceiling.

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A translucent ink flattened onto its ground, the way the compositor paints it.
double _on(Color ink, Color ground) => _ratio(Color.alphaBlend(ink, ground), ground);

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

const _titleBar = 7.0;
const _lineBar = 4.5;

/// Both grounds a line can sit on: the gradient's lightest stop (the worst case) and brandDeep.
void _expectLegible(Color ink, double bar, String what) {
  for (final ground in [BrowInk.bright, NivoraColors.brandDeep]) {
    final r = _on(ink, ground);
    expect(r, greaterThanOrEqualTo(bar),
        reason: '$what ${_hex(ink)} measures ${r.toStringAsFixed(2)}:1 on ${_hex(ground)}');
  }
}

Widget _host(Widget child, {ThemeData? theme, bool reduceMotion = false, double scale = 1}) {
  return MaterialApp(
    theme: theme ?? NivoraTheme.light(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(scale),
      ),
      child: app!,
    ),
    home: Scaffold(body: child),
  );
}

/// The colour a line was actually laid out with — the merged style on its paragraph, which is
/// what a call site leaking the theme's ink would change.
Color _inkOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!.color!;

void _expectAtRest(WidgetTester tester, String text) {
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)),
  );
  for (final fade in fades) {
    expect(fade.opacity.value, 1.0, reason: '"$text" is still fading');
  }
}

BrowLightPainter _lightOf(WidgetTester tester, Finder inHeaderWith) {
  final frame = find.ancestor(of: inHeaderWith, matching: find.byType(BrowHeaderFrame));
  return tester
      .widgetList<CustomPaint>(find.descendant(of: frame, matching: find.byType(CustomPaint)))
      .map((p) => p.painter)
      .whereType<BrowLightPainter>()
      .single;
}

Future<void> _pastEntrance(WidgetTester tester) async {
  await tester.pump(BrowEntrance.total);
  // The completed controller rebuilds the header into its final state on the next frame and is
  // disposed at the end of it.
  await tester.pump(const Duration(milliseconds: 16));
}

const _subscriptions = SaScreen(
  title: 'Subscriptions',
  subtitle: 'One subscription per hostel',
  child: SizedBox.shrink(),
);

void main() {
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the palette is arithmetic, not taste', () {
    test('both mixed colours are two tokens mixed, not new hexes', () {
      expect(_hex(BrowInk.bright), '#6341A4');
      expect(BrowInk.bright, Color.lerp(NivoraColors.brandDeep, NivoraColors.brand, 0.4));
      expect(_hex(BrowInk.eyebrow), '#E3D5BB');
      expect(BrowInk.deep, NivoraColors.brandDeep);
      expect(BrowInk.bright.a, 1.0, reason: 'the brow is opaque; a list scrolls under it');
    });

    test('title 7:1 and eyebrow / subtitle 4.5:1, on the LIGHTEST stop and on brandDeep', () {
      _expectLegible(BrowInk.title, _titleBar, 'title');
      _expectLegible(BrowInk.eyebrow, _lineBar, 'eyebrow');
      _expectLegible(BrowInk.subtitle, _lineBar, 'subtitle');

      // The figures quoted in brow_header.dart, recomputed so the comment cannot rot.
      String f(Color ink, Color ground) => _on(ink, ground).toStringAsFixed(2);
      expect(f(BrowInk.title, BrowInk.bright), '7.43');
      expect(f(BrowInk.eyebrow, BrowInk.bright), '5.15');
      expect(f(BrowInk.subtitle, BrowInk.bright), '5.43');
      expect(f(BrowInk.title, NivoraColors.brandDeep), '10.20');
      expect(f(BrowInk.eyebrow, NivoraColors.brandDeep), '7.07');
      expect(f(BrowInk.subtitle, NivoraColors.brandDeep), '7.22');
      // ignore: avoid_print
      print('BROW CONTRAST  lightest stop ${_hex(BrowInk.bright)}: '
          'title ${f(BrowInk.title, BrowInk.bright)} · eyebrow ${f(BrowInk.eyebrow, BrowInk.bright)} · '
          'subtitle ${f(BrowInk.subtitle, BrowInk.bright)}  |  brandDeep: '
          'title ${f(BrowInk.title, NivoraColors.brandDeep)} · '
          'eyebrow ${f(BrowInk.eyebrow, NivoraColors.brandDeep)} · '
          'subtitle ${f(BrowInk.subtitle, NivoraColors.brandDeep)}');
    });

    test('the motif never lifts a pixel above the lightest stop, so the ratios hold on it', () {
      // A long title can run under the motif on a narrow phone. The gradient grows with x and y,
      // so the motif's top-left corner is the lightest ground it ever sits on; the lines and the
      // lit window at rest must not composite lighter than the bright stop there.
      final ceiling = _luminance(BrowInk.bright);
      const sizes = [
        Size(320, 100),
        Size(320, 138),
        Size(320, 160),
        Size(320, 220),
        Size(411, 138),
        Size(800, 120),
      ];
      for (final size in sizes) {
        final rect = BrowMotif.rectFor(size);
        final t = BrowBackdropPainter.gradientT(rect.topLeft - const Offset(1, 1), size);
        final ground = Color.lerp(BrowInk.bright, BrowInk.deep, t)!;
        final line = Color.alphaBlend(
            Colors.white.withValues(alpha: BrowInk.motifStrokeAlpha), ground);
        final window = Color.alphaBlend(
            BrowInk.window.withValues(alpha: BrowInk.motifWindowAlpha), ground);
        expect(_luminance(line), lessThanOrEqualTo(ceiling),
            reason: 'motif line at $size (gradient at ${t.toStringAsFixed(2)})');
        expect(_luminance(window), lessThanOrEqualTo(ceiling),
            reason: 'lit window at $size (gradient at ${t.toStringAsFixed(2)})');
      }
    });

    test('the brand dot and the avatar initials hold on the lightest stop too', () {
      expect(_ratio(BrowInk.gold, BrowInk.bright), greaterThanOrEqualTo(3.0),
          reason: 'the gold dot is a graphic: WCAG 1.4.11');
      // The avatar is in the top-left corner, on the bright stop, as white on a 16% white disc.
      final disc = Color.alphaBlend(Colors.white.withValues(alpha: 0.16), BrowInk.bright);
      expect(_ratio(Colors.white, disc), greaterThanOrEqualTo(_lineBar));
    });

    test('icon buttons: the title white, and that white at 38% when disabled', () {
      expect(BrowInk.control, BrowInk.title);
      expect(BrowInk.controlDisabled, BrowInk.control.withValues(alpha: 0.38));
      _expectLegible(BrowInk.control, _lineBar, 'icon button');

      // An inactive control has no contrast floor, so the figures are pinned for the comment's
      // sake and held to one rule: the glyph composites LIGHTER than its ground. Dimmed brow ink,
      // not the theme's dark ink.
      String f(Color ground) => _on(BrowInk.controlDisabled, ground).toStringAsFixed(2);
      expect(f(BrowInk.bright), '2.43');
      expect(f(NivoraColors.brandDeep), '2.77');
      for (final ground in [BrowInk.bright, NivoraColors.brandDeep]) {
        expect(_luminance(Color.alphaBlend(BrowInk.controlDisabled, ground)),
            greaterThan(_luminance(ground)),
            reason: 'disabled icon on ${_hex(ground)}');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the owner\'s Subscriptions header', () {
    for (final name in ['light', 'dark']) {
      testWidgets('draws every line light in the $name theme, measured', (tester) async {
        // Built inside the test, not in the loop header: a theme resolves google_fonts styles,
        // and doing that before the test binding exists fails the font load and retries it later.
        final theme = name == 'light' ? NivoraTheme.light() : NivoraTheme.dark();
        await tester.pumpWidget(_host(_subscriptions, theme: theme));
        await _pastEntrance(tester);

        _expectAtRest(tester, 'SUPER ADMIN');
        _expectAtRest(tester, 'Subscriptions');
        _expectAtRest(tester, 'One subscription per hostel');

        final eyebrow = _inkOf(tester, 'SUPER ADMIN');
        final title = _inkOf(tester, 'Subscriptions');
        final subtitle = _inkOf(tester, 'One subscription per hostel');

        // The regression itself: these used to be the theme's own inks.
        expect(title, isNot(theme.textTheme.titleMedium!.color));
        expect(subtitle, isNot(theme.textTheme.bodySmall!.color));
        expect(eyebrow, isNot(theme.textTheme.labelSmall!.color));

        _expectLegible(title, _titleBar, 'title');
        _expectLegible(eyebrow, _lineBar, 'eyebrow');
        _expectLegible(subtitle, _lineBar, 'subtitle');
      });
    }

    testWidgets('keeps the status bar icons light and the curve', (tester) async {
      await tester.pumpWidget(_host(_subscriptions));
      await _pastEntrance(tester);
      final regions = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.ancestor(
          of: find.text('Subscriptions'),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      expect(regions.first.value.statusBarIconBrightness, Brightness.light);
      final clip = tester.widget<ClipPath>(
        find.ancestor(of: find.text('Subscriptions'), matching: find.byType(ClipPath)).first,
      );
      final path = clip.clipper!.getClip(const Size(400, 200));
      expect(path.contains(const Offset(200, 195)), isTrue);
      expect(path.contains(const Offset(4, 195)), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the other roles on the brow', () {
    testWidgets('a warden header: light title and subtitle, gold brand dot', (tester) async {
      await tester.pumpWidget(_host(
        const WardenScreen(title: 'Rooms', subtitle: 'Sunrise Residency', child: SizedBox()),
      ));
      await _pastEntrance(tester);
      _expectLegible(_inkOf(tester, 'Rooms'), _titleBar, 'warden title');
      _expectLegible(_inkOf(tester, 'Sunrise Residency'), _lineBar, 'warden subtitle');

      final dot = tester.widget<Container>(
        find.descendant(of: find.byType(ToneDot), matching: find.byType(Container)),
      );
      expect((dot.decoration! as BoxDecoration).color, BrowInk.gold);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a manager header: the subtitle is no longer the dark-ground grey',
        (tester) async {
      await tester.pumpWidget(_host(
        const ManagerScreen(title: 'Expenses', subtitle: 'Sunrise Residency', child: SizedBox()),
        theme: NivoraTheme.dark(),
      ));
      await _pastEntrance(tester);
      _expectLegible(_inkOf(tester, 'Expenses'), _titleBar, 'manager title');
      _expectLegible(_inkOf(tester, 'Sunrise Residency'), _lineBar, 'manager subtitle');
    });

    testWidgets('a masthead: the greeting and the signature are light too', (tester) async {
      await tester.pumpWidget(_host(
        const SaScreen(title: 'Overview', subtitle: 'Priya Nair', masthead: true, child: SizedBox()),
      ));
      await _pastEntrance(tester);
      expect(find.byType(AccountAvatar), findsOneWidget);
      expect(find.byType(MastheadBlock), findsOneWidget);
      _expectLegible(_inkOf(tester, 'Hello Priya'), _titleBar, 'greeting');
      _expectLegible(_inkOf(tester, 'NIVORA'), _lineBar, 'signature');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('controls on the brow take its ink too', () {
    // What the glyph is actually painted with. Icon lays its code point out as a RichText in the
    // colour it resolved, so a theme ink leaking in through a button style shows up here.
    Color glyph(WidgetTester tester, IconData icon) => tester
        .renderObject<RenderParagraph>(
          find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
        )
        .text
        .style!
        .color!;

    String describe(Color c) => '${_hex(c)} at ${(c.a * 100).round()}%';

    // What the Hostels, Rooms and Money headers really carry: unstyled IconButtons and a
    // PopupMenuButton, straight into `actions`. No screen disables one today, and the disabled
    // state is the one that leaked (#14161D at 38% on violet) before the frame named it.
    List<Widget> actions() => [
          IconButton(
            tooltip: 'Edit layout',
            icon: const Icon(Icons.dashboard_customize_outlined, size: IconSize.md),
            onPressed: () {},
          ),
          const IconButton(
            tooltip: 'Month by month',
            icon: Icon(Icons.bar_chart_rounded, size: IconSize.md),
            onPressed: null,
          ),
          PopupMenuButton<int>(
            tooltip: 'Record an expense',
            icon: const Icon(Icons.add_rounded, size: IconSize.md),
            itemBuilder: (_) => const [],
          ),
        ];

    final screens = <String, Widget Function()>{
      'SaScreen': () => SaScreen(title: 'Hostels', actions: actions(), child: const SizedBox()),
      'WardenScreen': () =>
          WardenScreen(title: 'Rooms', actions: actions(), child: const SizedBox()),
      'ManagerScreen': () =>
          ManagerScreen(title: 'Money', actions: actions(), child: const SizedBox()),
    };

    for (final name in ['light', 'dark']) {
      for (final screen in screens.entries) {
        testWidgets('${screen.key}: IconButtons, enabled and disabled, and a menu, $name theme',
            (tester) async {
          final theme = name == 'light' ? NivoraTheme.light() : NivoraTheme.dark();
          await tester.pumpWidget(_host(screen.value(), theme: theme));
          await _pastEntrance(tester);

          final enabled = glyph(tester, Icons.dashboard_customize_outlined);
          expect(enabled, BrowInk.control, reason: 'IconButton drew ${describe(enabled)}');
          _expectLegible(enabled, _lineBar, 'IconButton glyph');

          final menu = glyph(tester, Icons.add_rounded);
          expect(menu, BrowInk.control, reason: 'PopupMenuButton drew ${describe(menu)}');

          // Dimmer on purpose, but dimmed BROW ink rather than the theme's onSurface at 38%.
          final disabled = glyph(tester, Icons.bar_chart_rounded);
          expect(disabled, BrowInk.controlDisabled,
              reason: 'disabled IconButton drew ${describe(disabled)}');
        });
      }
    }
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the entrance', () {
    testWidgets('plays once, then NOTHING is scheduled — no perpetual ticker', (tester) async {
      await tester.pumpWidget(_host(_subscriptions));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'the entrance is running');
      expect(_lightOf(tester, find.text('Subscriptions')).progress, isNotNull,
          reason: 'a first appearance sweeps the light across');

      await tester.pump(const Duration(milliseconds: 120));
      final fading = tester
          .widgetList<FadeTransition>(
            find.ancestor(of: find.text('Subscriptions'), matching: find.byType(FadeTransition)),
          )
          .map((f) => f.opacity.value);
      expect(fading.any((v) => v < 1), isTrue, reason: 'the title has not risen in yet');

      expect(BrowEntrance.total, lessThanOrEqualTo(const Duration(milliseconds: 1100)));
      await _pastEntrance(tester);

      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'a controller left running schedules frames forever');
      expect(_lightOf(tester, find.text('Subscriptions')).progress, isNull);
      _expectAtRest(tester, 'Subscriptions');

      // And it stays quiet: a second of nothing schedules nothing.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('with reduce motion there is no animation at all, from the first frame',
        (tester) async {
      await tester.pumpWidget(_host(_subscriptions, reduceMotion: true));

      expect(tester.binding.transientCallbackCount, 0, reason: 'no ticker was ever started');
      // One more frame: the body's scroll view reports its first metrics to semantics after the
      // first layout and asks for a frame to do it. That is the framework, not an animation.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(_lightOf(tester, find.text('Subscriptions')).progress, isNull);
      final header = find.byType(BrowHeaderFrame);
      expect(find.descendant(of: header, matching: find.byType(FadeTransition)), findsNothing);
      expect(find.descendant(of: header, matching: find.byType(AnimatedSwitcher)), findsNothing);
      _expectLegible(_inkOf(tester, 'Subscriptions'), _titleBar, 'title');
    });

    testWidgets('a TAB CHANGE fades only the title in — the sweep is not replayed',
        (tester) async {
      final theme = NivoraTheme.light();
      Widget shell(int index, {required bool both}) => _host(
            IndexedStack(
              index: index,
              children: [
                const SaScreen(title: 'Hostels', child: SizedBox()),
                if (both) _subscriptions,
              ],
            ),
            theme: theme,
          );

      await tester.pumpWidget(shell(0, both: false));
      await _pastEntrance(tester);

      // The shells keep every visited tab in an IndexedStack, so a new tab's header mounts while
      // the previous one is still alive. That is the signal this is a tab change.
      await tester.pumpWidget(shell(1, both: true));

      expect(_lightOf(tester, find.text('Subscriptions')).progress, isNull,
          reason: 'no sweep, no ribbon replay on a tab change');
      final titleFades = tester
          .widgetList<FadeTransition>(
            find.ancestor(of: find.text('Subscriptions'), matching: find.byType(FadeTransition)),
          )
          .map((f) => f.opacity.value);
      expect(titleFades.any((v) => v < 1), isTrue, reason: 'the title fades in');
      _expectAtRest(tester, 'SUPER ADMIN');
      _expectAtRest(tester, 'One subscription per hostel');

      await tester.pump(BrowEntrance.titleSwap);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isFalse);
      _expectAtRest(tester, 'Subscriptions');
    });

    testWidgets('a title that changes inside one header cross-fades', (tester) async {
      // One ThemeData for both pumps. A fresh NivoraTheme is not == the last one, so MaterialApp's
      // AnimatedTheme would animate between them and that, not the header, would hold frames.
      final theme = NivoraTheme.light();
      await tester.pumpWidget(_host(const SaScreen(title: 'Hostels', child: SizedBox()), theme: theme));
      await _pastEntrance(tester);

      await tester.pumpWidget(
        _host(const SaScreen(title: 'Hostels · 12', child: SizedBox()), theme: theme),
      );
      await tester.pump(BrowEntrance.titleSwap ~/ 2);
      expect(find.text('Hostels'), findsOneWidget, reason: 'the old title is fading out');
      expect(find.text('Hostels · 12'), findsOneWidget, reason: 'the new one is fading in');
      expect(_lightOf(tester, find.text('Hostels · 12')).progress, isNull,
          reason: 'the sweep does not replay for a new title');

      await tester.pump(BrowEntrance.titleSwap);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Hostels'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('nothing overflows at 320dp', () {
    const longEyebrow = 'SUPER ADMIN · PLATFORM CONSOLE FOR EVERY HOSTEL';
    const longTitle = 'Subscriptions for every hostel on the platform, lapsed ones included';
    const longSubtitle = 'One subscription per hostel, renewed by the owner or by Nivora on request';

    final screens = <String, Widget>{
      'SaScreen with two actions': SaScreen(
        eyebrow: longEyebrow,
        title: longTitle,
        subtitle: longSubtitle,
        actions: [
          SaIconButton(icon: Icons.shield_rounded, tooltip: 'Security', onPressed: () {}),
          SaIconButton(icon: Icons.logout_rounded, tooltip: 'Sign out', onPressed: () {}),
        ],
        child: const SizedBox(),
      ),
      'WardenScreen with an action': WardenScreen(
        title: longTitle,
        subtitle: longSubtitle,
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add_rounded))],
        child: const SizedBox(),
      ),
      'ManagerScreen': const ManagerScreen(
        title: longTitle,
        subtitle: longSubtitle,
        child: SizedBox(),
      ),
      'a masthead': const SaScreen(
        title: 'Overview',
        subtitle: 'Venkataramanasubramaniam Raghunathan-Iyer',
        masthead: true,
        child: SizedBox(),
      ),
    };

    for (final scale in [1.0, 1.4]) {
      testWidgets('long strings, during and after the entrance, at ${scale}x', (tester) async {
        tester.view.physicalSize = const Size(960, 1706);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        for (final entry in screens.entries) {
          // An empty tree between screens, so each one gets its full first entrance — the
          // widest moment for the eyebrow, whose tracking starts loose.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(entry.value, scale: scale));
          await tester.pump(BrowEntrance.total * 0.25);
          expect(tester.takeException(), isNull, reason: '${entry.key} mid-entrance at ${scale}x');
          await _pastEntrance(tester);
          expect(tester.takeException(), isNull, reason: '${entry.key} at ${scale}x');
          expect(tester.binding.hasScheduledFrame, isFalse, reason: entry.key);
        }

        // The long title ellipsises rather than wrapping or pushing the actions off.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_host(screens['SaScreen with two actions']!, scale: scale));
        await _pastEntrance(tester);
        expect(tester.renderObject<RenderParagraph>(find.text(longTitle)).didExceedMaxLines,
            isTrue);
        expect(find.byType(SaIconButton), findsNWidgets(2));
      });
    }
  });
}
