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
import 'package:mobile/shared/clay/app_header.dart';
import 'package:mobile/shared/glass/glass.dart';
import 'package:mobile/shared/wordmark.dart';

/// THE BROW HEADER — held to the things the owner's screenshot and the new design ask for.
///
///  1. The lines are LIGHT, whatever theme the phone is in. The bug was the Super Admin
///     "Subscriptions" header drawn in the theme's dark ink on the brand colour, so the SaScreen
///     tests read the colour the paragraph was actually laid out with, in both themes, and
///     measure it. The icon buttons in `actions` are read the same way, disabled ones included:
///     a Material 3 IconButton does not take its colour from IconTheme alone.
///  2. It is the forest header: the same backdrop and inks as [AppHeader], so the two cannot be
///     told apart.
///  3. NOTHING MOVES: no entrance, no controller, nothing scheduled after the first frame —
///     `hasScheduledFrame` is the proof. A changed string cross-fades, and under reduce motion
///     not even that.
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

/// Both grounds a line can sit on: the gradient's lightest stop (the worst case) and the forest.
void _expectLegible(Color ink, double bar, String what) {
  for (final ground in [BrowInk.bright, ApnivaasColors.brandDeep]) {
    final r = _on(ink, ground);
    expect(r, greaterThanOrEqualTo(bar),
        reason: '$what ${_hex(ink)} measures ${r.toStringAsFixed(2)}:1 on ${_hex(ground)}');
  }
}

Widget _host(Widget child, {ThemeData? theme, bool reduceMotion = false, double scale = 1}) {
  return MaterialApp(
    theme: theme ?? ApnivaasTheme.light(),
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

const _subscriptions = SaScreen(
  title: 'Subscriptions',
  subtitle: 'One subscription per hostel',
  child: SizedBox.shrink(),
);

void main() {
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the palette is the forest header\'s, measured', () {
    test('the grounds and the inks are the header tokens, not a second set', () {
      expect(_hex(BrowInk.bright), '#1F6150');
      expect(BrowInk.bright, ApnivaasColors.forestHigh);
      expect(BrowInk.deep, ApnivaasColors.brandDeep);
      expect(BrowInk.title, ApnivaasColors.headerTitle);
      expect(BrowInk.eyebrow, ApnivaasColors.headerGreeting);
      expect(BrowInk.subtitle, ApnivaasColors.headerSub);
      expect(BrowInk.bright.a, 1.0, reason: 'the brow is opaque; a list scrolls under it');
    });

    test('title 7:1 and eyebrow / subtitle 4.5:1, on the LIGHTEST stop and on the forest', () {
      _expectLegible(BrowInk.title, _titleBar, 'title');
      _expectLegible(BrowInk.eyebrow, _lineBar, 'eyebrow');
      _expectLegible(BrowInk.subtitle, _lineBar, 'subtitle');

      // The figures quoted in brow_header.dart, recomputed so the comment cannot rot.
      String f(Color ink, Color ground) => _on(ink, ground).toStringAsFixed(2);
      expect(f(BrowInk.title, BrowInk.bright), '7.28');
      expect(f(BrowInk.eyebrow, BrowInk.bright), '5.11');
      expect(f(BrowInk.subtitle, BrowInk.bright), '5.29');
      expect(f(BrowInk.title, ApnivaasColors.brandDeep), '9.51');
      expect(f(BrowInk.eyebrow, ApnivaasColors.brandDeep), '6.68');
      expect(f(BrowInk.subtitle, ApnivaasColors.brandDeep), '6.92');
    });

    test('the brand dot and the avatar initials hold on the lightest stop too', () {
      expect(_ratio(BrowInk.gold, BrowInk.bright), greaterThanOrEqualTo(3.0),
          reason: 'the gold dot is a graphic: WCAG 1.4.11');
      // The account avatar on a brow: white initials on a 16% white disc (glass.dart).
      final disc = Color.alphaBlend(Colors.white.withValues(alpha: 0.16), BrowInk.bright);
      expect(_ratio(Colors.white, disc), greaterThanOrEqualTo(_lineBar));
      expect(_ratio(Colors.white, disc).toStringAsFixed(2), '4.94');
    });

    test('icon buttons: the title white, and white at 38% when disabled', () {
      expect(BrowInk.control, BrowInk.title);
      expect(BrowInk.controlDisabled, ForestInk.disabled);
      expect(BrowInk.controlDisabled.a, closeTo(0.38, 0.005));
      _expectLegible(BrowInk.control, _lineBar, 'icon button');

      // An inactive control has no contrast floor, so the figures are pinned for the comment's
      // sake and held to one rule: the glyph composites LIGHTER than its ground — dimmed header
      // ink, not the theme's dark ink.
      String f(Color ground) => _on(BrowInk.controlDisabled, ground).toStringAsFixed(2);
      expect(f(BrowInk.bright), '2.43');
      expect(f(ApnivaasColors.brandDeep), '2.77');
      for (final ground in [BrowInk.bright, ApnivaasColors.brandDeep]) {
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
        final theme = name == 'light' ? ApnivaasTheme.light() : ApnivaasTheme.dark();
        await tester.pumpWidget(_host(_subscriptions, theme: theme));

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

    testWidgets('prints the same three lines as the forest header', (tester) async {
      await tester.pumpWidget(_host(_subscriptions));
      final header = HeaderText.of(tester.element(find.text('Subscriptions')));
      final title = tester.renderObject<RenderParagraph>(find.text('Subscriptions')).text.style!;
      expect(title.fontFamily, header.title.fontFamily);
      expect(title.fontSize, header.title.fontSize);
      expect(title.fontWeight, header.title.fontWeight);
      final sub =
          tester.renderObject<RenderParagraph>(find.text('One subscription per hostel')).text.style!;
      expect(sub.fontSize, header.subtitle.fontSize);
    });

    testWidgets('keeps the status bar icons light and the rounded bottom', (tester) async {
      await tester.pumpWidget(_host(_subscriptions));
      final regions = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.ancestor(
          of: find.text('Subscriptions'),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      expect(regions.first.value.statusBarIconBrightness, Brightness.light);
      final clip = tester.widget<ClipRRect>(
        find.ancestor(of: find.text('Subscriptions'), matching: find.byType(ClipRRect)).first,
      );
      expect(clip.borderRadius, Radii.rHeaderBottom);
      final painters = tester
          .widgetList<CustomPaint>(find.descendant(
            of: find.byType(BrowHeaderFrame),
            matching: find.byType(CustomPaint),
          ))
          .map((p) => p.painter)
          .whereType<HeaderBackdropPainter>();
      expect(painters, hasLength(1), reason: 'the brow paints the forest header backdrop');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('the other roles on the brow', () {
    testWidgets('a warden header: light title and subtitle, gold brand dot', (tester) async {
      await tester.pumpWidget(_host(
        const WardenScreen(title: 'Rooms', subtitle: 'Sunrise Residency', child: SizedBox()),
      ));
      _expectLegible(_inkOf(tester, 'Rooms'), _titleBar, 'warden title');
      _expectLegible(_inkOf(tester, 'Sunrise Residency'), _lineBar, 'warden subtitle');

      final dot = tester.widget<Container>(
        find.descendant(of: find.byType(ToneDot), matching: find.byType(Container)),
      );
      expect((dot.decoration! as BoxDecoration).color, BrowInk.gold);
      // One frame for the scroll view's first metrics — the framework, not an animation.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a manager header in the dark theme: light lines all the same', (tester) async {
      await tester.pumpWidget(_host(
        const ManagerScreen(title: 'Expenses', subtitle: 'Sunrise Residency', child: SizedBox()),
        theme: ApnivaasTheme.dark(),
      ));
      _expectLegible(_inkOf(tester, 'Expenses'), _titleBar, 'manager title');
      _expectLegible(_inkOf(tester, 'Sunrise Residency'), _lineBar, 'manager subtitle');
    });

    testWidgets('a masthead: the greeting and the signature are light too', (tester) async {
      await tester.pumpWidget(_host(
        const SaScreen(title: 'Overview', subtitle: 'Priya Nair', masthead: true, child: SizedBox()),
      ));
      expect(find.byType(AccountAvatar), findsOneWidget);
      expect(find.byType(MastheadBlock), findsOneWidget);
      _expectLegible(_inkOf(tester, 'Hello Priya'), _titleBar, 'greeting');
      _expectLegible(_inkOf(tester, 'Apnivaas'), _lineBar, 'signature');
      await tester.pump();
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
    // PopupMenuButton, straight into `actions`. The disabled state is the one that leaked
    // (the theme's dark ink at 38%) before the frame named it.
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
          final theme = name == 'light' ? ApnivaasTheme.light() : ApnivaasTheme.dark();
          await tester.pumpWidget(_host(screen.value(), theme: theme));

          final enabled = glyph(tester, Icons.dashboard_customize_outlined);
          expect(enabled, BrowInk.control, reason: 'IconButton drew ${describe(enabled)}');
          _expectLegible(enabled, _lineBar, 'IconButton glyph');

          final menu = glyph(tester, Icons.add_rounded);
          expect(menu, BrowInk.control, reason: 'PopupMenuButton drew ${describe(menu)}');

          // Dimmer on purpose, but dimmed header ink rather than the theme's onSurface at 38%.
          final disabled = glyph(tester, Icons.bar_chart_rounded);
          expect(disabled, BrowInk.controlDisabled,
              reason: 'disabled IconButton drew ${describe(disabled)}');
        });
      }
    }
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('nothing moves', () {
    testWidgets('nothing is scheduled after the first frame — no entrance, no ticker',
        (tester) async {
      await tester.pumpWidget(_host(_subscriptions));
      // One frame for the body's scroll view to report its first metrics to semantics: the
      // framework, not an animation.
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'a header that animates on arrival schedules frames');
      expect(
        find.descendant(of: find.byType(BrowHeaderFrame), matching: find.byType(FadeTransition))
            .evaluate()
            .where((e) => (e.widget as FadeTransition).opacity.value < 1),
        isEmpty,
        reason: 'every line is at rest from the first frame',
      );

      // And it stays quiet: a second of nothing schedules nothing.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('with reduce motion there is no transition anywhere in the header',
        (tester) async {
      await tester.pumpWidget(_host(_subscriptions, reduceMotion: true));
      expect(tester.binding.transientCallbackCount, 0, reason: 'no ticker was ever started');
      final header = find.byType(BrowHeaderFrame);
      expect(find.descendant(of: header, matching: find.byType(AnimatedSwitcher)), findsNothing);
      _expectLegible(_inkOf(tester, 'Subscriptions'), _titleBar, 'title');
    });

    testWidgets('a title that changes inside one header cross-fades, then settles',
        (tester) async {
      // One ThemeData for both pumps. A fresh ApnivaasTheme is not == the last one, so
      // MaterialApp's AnimatedTheme would animate between them and that, not the header, would
      // hold frames.
      final theme = ApnivaasTheme.light();
      await tester.pumpWidget(_host(const SaScreen(title: 'Hostels', child: SizedBox()), theme: theme));
      await tester.pump();

      await tester.pumpWidget(
        _host(const SaScreen(title: 'Hostels · 12', child: SizedBox()), theme: theme),
      );
      await tester.pump(Motion.base ~/ 2);
      expect(find.text('Hostels'), findsOneWidget, reason: 'the old title is fading out');
      expect(find.text('Hostels · 12'), findsOneWidget, reason: 'the new one is fading in');

      await tester.pump(Motion.base);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Hostels'), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('nothing overflows at 320dp', () {
    const longEyebrow = 'SUPER ADMIN · PLATFORM CONSOLE FOR EVERY HOSTEL';
    const longTitle = 'Subscriptions for every hostel on the platform, lapsed ones included';
    const longSubtitle = 'One subscription per hostel, renewed by the owner or by Apnivaas on request';

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

    for (final scale in [1.0, 1.4, 2.0]) {
      testWidgets('long strings at ${scale}x', (tester) async {
        tester.view.physicalSize = const Size(960, 1706);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        for (final entry in screens.entries) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(entry.value, scale: scale));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '${entry.key} at ${scale}x');
          expect(tester.binding.hasScheduledFrame, isFalse, reason: entry.key);
        }

        // The long title ellipsises rather than wrapping or pushing the actions off.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_host(screens['SaScreen with two actions']!, scale: scale));
        await tester.pump();
        expect(tester.renderObject<RenderParagraph>(find.text(longTitle)).didExceedMaxLines,
            isTrue);
        expect(find.byType(SaIconButton), findsNWidgets(2));
      });
    }
  });

  group('a tab keeps its whole name at large text', () {
    // At 2.0x on a 360dp phone every warden tab title beside a header action was cut to
    // "Rooms & b…". The name is what says which of five tabs you are standing in, so above 1.3x
    // the title takes a second line — the forest AppHeader's rule.
    testWidgets('one line up to 1.3x, a second line above it, and no ellipsis', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      for (final scale in [1.0, 1.3, 1.4, 2.0]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_host(
          WardenScreen(
            title: 'Rooms & beds',
            actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add_rounded))],
            child: const SizedBox(),
          ),
          scale: scale,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${scale}x');
        final title = tester.renderObject<RenderParagraph>(find.text('Rooms & beds'));
        expect(title.maxLines, scale > 1.3 ? 2 : 1, reason: '${scale}x');
        expect(title.didExceedMaxLines, isFalse,
            reason: '"Rooms & beds" was cut off at ${scale}x on a 360dp phone');
      }
    });
  });
}
