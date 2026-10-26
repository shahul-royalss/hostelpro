// THE CLAY KIT, HELD TO WHAT THE SCREENS WILL LEAN ON.
//
// Six screen reskins are built on these widgets, so what is pinned here is the contract they
// are promised: the tab bar selects and announces itself, the empty state says what it is and
// offers one way on, a stat tile and the forest header fit a 360dp phone at 2.0x text, and a
// list row keeps its trailing control a target of its own.
//
// IMAGES DO NOT DECODE IN `flutter test`, so nothing here looks at pixels: every assertion is
// about structure, semantics, geometry or the exceptions layout throws. A clay icon that fails
// to decode draws its fallback glyph, which is exactly what keeps these trees honest.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/theme.dart';
import 'package:mobile/core/theme/tokens.dart';
import 'package:mobile/shared/clay/clay.dart';
import 'package:mobile/shared/glass/glass.dart' show StateBody;
import 'package:mobile/shared/illustrations.dart';

/// A phone of [width] dp at [scale] text, in the light theme (or [theme]).
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double height = 780,
  double scale = 1,
  bool reduceMotion = false,
  ThemeData? theme,
  bool scroll = true,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? ApnivaasTheme.light(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: app!,
    ),
    home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
  ));
  await tester.pump();
}

const _tabs = [
  ClayNavDestination(icon: ClayIcons.navHome, label: 'Home'),
  ClayNavDestination(icon: ClayIcons.navProperty, label: 'PGs'),
  ClayNavDestination(icon: ClayIcons.navPeople, label: 'Tenants'),
  ClayNavDestination(
    icon: ClayIcons.navMoney,
    label: 'Payments',
    badgeCount: 3,
    badgeLabel: '3 due',
  ),
  ClayNavDestination(icon: ClayIcons.complaint, label: 'Complaints', hasBadge: true),
];

/// A shell's worth of state around a [ClayNavBar].
class _Shell extends StatefulWidget {
  const _Shell({this.onSelect});
  final ValueChanged<int>? onSelect;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: ClayNavBar(
          destinations: _tabs,
          selectedIndex: index,
          onDestinationSelected: (i) {
            widget.onSelect?.call(i);
            setState(() => index = i);
          },
        ),
      );
}

Future<void> _pumpShell(WidgetTester tester,
    {double width = 360, double scale = 1, bool reduceMotion = false, ValueChanged<int>? onSelect}) async {
  tester.view.physicalSize = Size(width * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ApnivaasTheme.light(),
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: app!,
    ),
    home: _Shell(onSelect: onSelect),
  ));
  await tester.pump();
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('ClayNavBar', () {
    testWidgets('a tap selects the tab and reports its index; the change settles', (tester) async {
      final picked = <int>[];
      await _pumpShell(tester, onSelect: picked.add);

      await tester.tap(find.text('Payments'));
      await tester.pumpAndSettle();
      expect(picked, [3]);
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'implicit animations only: nothing ticks once a change has landed');

      // The selected label takes the brand ink and the bold weight; the others the muted ink.
      final scheme = ApnivaasTheme.light().colorScheme;
      final on = tester.renderObject<RenderParagraph>(find.text('Payments')).text.style!;
      final off = tester.renderObject<RenderParagraph>(find.text('Home')).text.style!;
      expect(on.color, scheme.primary);
      expect(on.fontWeight, FontWeight.w700);
      expect(off.color, scheme.onSurfaceVariant);
      expect(off.fontWeight, FontWeight.w600);
    });

    testWidgets('every tab is one button node: its name, its place, what is waiting',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpShell(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Home, tab 1 of 5')),
        matchesSemantics(
          label: 'Home, tab 1 of 5',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          isFocusable: true,
        ),
      );
      expect(find.bySemanticsLabel('Payments, tab 4 of 5, 3 due'), findsOneWidget);
      expect(find.bySemanticsLabel('Complaints, tab 5 of 5, new'), findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('Payments, tab 4 of 5, 3 due')),
          isSemantics(isButton: true, isSelected: false));
      handle.dispose();
    });

    testWidgets('unselected art: the off-render where one exists, the icon grey otherwise',
        (tester) async {
      await _pumpShell(tester);
      final icons = tester.widgetList<ClayIcon>(find.byType(ClayIcon)).toList();
      // The Home tab is selected; its off-render is still in the tree (faded out) so the first
      // switch back never waits on a decode.
      final peopleOff = icons.singleWhere((i) => i.asset == ClayIcons.navPeopleOff);
      expect(peopleOff.greyscale, isFalse, reason: 'the supplied off-render is already grey');
      expect(peopleOff.opacity, Dim.navOff);
      final complaintOff =
          icons.where((i) => i.asset == ClayIcons.complaint && i.greyscale).toList();
      expect(complaintOff, hasLength(1),
          reason: 'a tab without off-art is drawn through the greyscale filter');
      // Never tinted otherwise, and decorative: the tab's words are in its semantics.
      expect(icons.every((i) => i.semanticLabel == null), isTrue);
    });

    testWidgets('grows for large text, stays under 88dp, and every target clears 48dp',
        (tester) async {
      final heights = <double>[];
      for (final scale in [1.0, 1.4]) {
        await _pumpShell(tester, scale: scale);
        heights.add(tester.getSize(find.byType(ClayNavBar)).height);
      }
      expect(heights[0], 72, reason: 'the bar is 72dp at 1.0x with no safe inset');
      expect(heights[1], greaterThan(heights[0]));
      expect(heights[1], lessThanOrEqualTo(88));

      await _pumpShell(tester);
      for (final label in ['Home', 'Payments', 'Complaints']) {
        final node = find.ancestor(of: find.text(label), matching: find.byType(InkResponse));
        final size = tester.getSize(node.first);
        expect(size.width, greaterThanOrEqualTo(48), reason: '$label target width');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$label target height');
      }
    });

    for (final width in [320.0, 360.0]) {
      testWidgets('five tabs at ${width.round()}dp and 2.0x text: nothing overflows',
          (tester) async {
        await _pumpShell(tester, width: width, scale: 2);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Complaints'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('with reduce motion every transition in the bar is instant', (tester) async {
      await _pumpShell(tester, reduceMotion: true);
      await tester.tap(find.text('Tenants'));
      await tester.pump();
      final bar = find.byType(ClayNavBar);
      final durations = [
        for (final w in tester.widgetList<ImplicitlyAnimatedWidget>(
            find.descendant(of: bar, matching: find.byWidgetPredicate((w) => w is ImplicitlyAnimatedWidget))))
          w.duration,
      ];
      expect(durations, isNotEmpty);
      expect(durations.every((d) => d == Duration.zero), isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel('Tenants, tab 3 of 5')),
          isSemantics(isSelected: true));
    });

    testWidgets('sits on the card with the bar shadow and pads for the gesture bar',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 72); // 24dp at 3x
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: ApnivaasTheme.light(), home: const _Shell()));
      await tester.pump();
      expect(tester.getSize(find.byType(ClayNavBar)).height, 72 + 24);
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(ClayNavBar), matching: find.byType(DecoratedBox)).first,
      );
      final d = box.decoration as BoxDecoration;
      expect(d.color, ApnivaasColors.card);
      expect(d.boxShadow, Shadows.bar);
      expect((d.border! as Border).top.color, ApnivaasColors.track);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('EmptyState', () {
    testWidgets('says what it is in real text, offers one action, and keeps the art silent',
        (tester) async {
      final handle = tester.ensureSemantics();
      var tapped = 0;
      await _pump(
        tester,
        EmptyState(
          icon: ClayIcons.addTenant,
          title: 'No tenants yet',
          body: 'Add your first tenant to start collecting rent.',
          actionLabel: 'Add tenant',
          onAction: () => tapped++,
        ),
      );
      expect(find.text('No tenants yet'), findsOneWidget);
      expect(find.text('Add your first tenant to start collecting rent.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add tenant'), findsOneWidget);

      final art = tester.widget<ClayIcon>(find.byType(ClayIcon));
      expect(art.asset, ClayIcons.addTenant);
      expect(art.size, ClaySize.promo);
      expect(art.semanticLabel, isNull, reason: 'the art is decoration over a sentence');

      await tester.tap(find.text('Add tenant'));
      expect(tapped, 1);
      handle.dispose();
    });

    testWidgets('the error variant is an honest sentence and a retry — and no retry without one',
        (tester) async {
      var retried = 0;
      await _pump(
        tester,
        EmptyState.error(
          message: 'Check your connection and try again.',
          onRetry: () => retried++,
        ),
      );
      expect(find.text("This didn't load"), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      expect(retried, 1);

      await _pump(tester, const EmptyState.error(message: 'The server refused this.'));
      expect(find.byType(FilledButton), findsNothing,
          reason: 'a control that cannot help is worse than no control');
    });

    for (final compact in [false, true]) {
      testWidgets('fits 320dp at 2.0x text${compact ? ', compact' : ''}', (tester) async {
        await _pump(
          tester,
          EmptyState(
            compact: compact,
            title: 'No complaints raised in Sunrise Residency this month',
            body: 'When a tenant raises a complaint it appears here with its room and status.',
            actionLabel: 'Raise a complaint for a tenant',
            onAction: () {},
          ),
          width: 320,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('StatTile', () {
    Widget carousel({VoidCallback? onTap}) => StatCarousel(
          children: [
            StatTile(
              style: StatTileStyle.hero,
              icon: ClayIcons.money,
              label: 'Collected in October',
              value: '₹12,24,500',
              caption: 'of ₹16,00,000 · 78%',
              progress: 0.78,
              onTap: onTap,
            ),
            const StatTile(icon: ClayIcons.beds, label: 'Beds occupied', value: '142/160'),
            const StatTile(
              icon: ClayIcons.lateFee,
              label: 'Overdue rent',
              value: '₹1,37,500',
              valueTone: ApnivaasColors.error,
              delta: '6 tenants',
              deltaTone: StatusTone.error,
            ),
            const StatTile(
              style: StatTileStyle.tonal,
              icon: ClayIcons.analytics,
              label: 'Trends and reports',
              value: 'View analytics',
            ),
          ],
        );

    testWidgets('at 2.0x on 360dp the carousel becomes a wrap and nothing overflows',
        (tester) async {
      await _pump(tester, carousel(), scale: 2);
      expect(tester.takeException(), isNull);
      // A sideways strip of half-hidden tiles is unreadable at this size: no scroll view.
      expect(
        find.descendant(of: find.byType(StatCarousel), matching: find.byType(Scrollable)),
        findsNothing,
      );
      // The hero takes the whole row, the rest two to a row.
      final hero = tester.getSize(find.byType(StatTile).first).width;
      final plain = tester.getSize(find.byType(StatTile).at(1)).width;
      expect(hero, greaterThan(plain * 1.9));
    });

    testWidgets('at 1.0x it scrolls sideways at the canvas widths', (tester) async {
      await _pump(tester, carousel());
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StatTile).first).width, StatTile.heroWidth);
      expect(tester.getSize(find.byType(StatTile).at(1)).width, StatTile.plainWidth);
      expect(tester.getSize(find.byType(StatTile).at(1)).height,
          greaterThanOrEqualTo(StatTile.minHeight));
    });

    testWidgets('a tile alone at 2.0x on 360dp, with a lakh-sized figure, fits', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: StatTile.plainWidth,
          child: StatTile(
            icon: ClayIcons.money,
            label: "Today's collection across every property",
            value: '₹12,34,56,789',
            caption: 'from 48 tenants',
          ),
        ),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      // The figure scales down on its one line rather than wrapping or truncating.
      expect(
        find.ancestor(of: find.text('₹12,34,56,789'), matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    });

    testWidgets('a lakh-sized hero figure never runs under the corner art', (tester) async {
      // The figure's line starts level with the lower half of the 78dp corner art, and at 1.0x
      // "₹1,24,500" ran under it. A figure that fits beside the full art keeps it; one that
      // does not gets the 56dp art, which ends above the figure's line, and the whole width.
      Widget hero(String value) => StatCarousel(children: [
            StatTile(
              style: StatTileStyle.hero,
              icon: ClayIcons.collectPayment,
              label: 'Collected in October',
              value: value,
              caption: 'of ₹1,60,000 · 78%',
              progress: 0.78,
            ),
          ]);

      for (final scale in [1.0, 1.4, 2.0]) {
        for (final value in ['₹8,500', '₹1,24,500', '₹12,24,500']) {
          await _pump(tester, hero(value), scale: scale);
          expect(tester.takeException(), isNull);
          final art = tester.getRect(find.byType(ClayIcon));
          final figure = tester.getRect(find.text(value));
          final beside = figure.right <= art.left + 0.5;
          final below = figure.top >= art.bottom - 0.5;
          expect(beside || below, isTrue,
              reason: '$value at ${scale}x: the figure $figure meets the art $art');
        }
      }

      await _pump(tester, hero('₹8,500'));
      expect(tester.widget<ClayIcon>(find.byType(ClayIcon)).size, ClaySize.hero,
          reason: 'a figure that fits beside the art keeps the full-size picture');
      await _pump(tester, hero('₹1,24,500'));
      expect(tester.widget<ClayIcon>(find.byType(ClayIcon)).size, ClaySize.tile,
          reason: 'a figure too long for the line beside the art gets the smaller picture');
    });

    testWidgets('at 2.0x a half-width tile sets its words whole, never broken inside one',
        (tester) async {
      // "12 outstanding bills" in a half-phone tile at 2.0x came out as "12 outstand" over
      // "ing bills". A word too long for the tile's column is set a little smaller instead,
      // and the words get a third line.
      const words = ['Pending fees', '12 outstanding bills', 'Booked in today', 'From the revenue ledger'];
      await _pump(
        tester,
        const StatCarousel(children: [
          StatTile(style: StatTileStyle.hero, label: 'Collected in October', value: '₹1,24,500'),
          StatTile(label: 'Pending fees', value: '₹35,500', caption: '12 outstanding bills'),
          StatTile(label: 'Booked in today', value: '₹8,500', caption: 'From the revenue ledger'),
        ]),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      for (final text in words) {
        final p = tester.renderObject<RenderParagraph>(find.text(text));
        expect(p.didExceedMaxLines, isFalse, reason: '"$text" was cut short');
        var start = 0;
        for (final word in text.split(' ')) {
          final tops = p
              .getBoxesForSelection(
                  TextSelection(baseOffset: start, extentOffset: start + word.length))
              .map((b) => b.top.round())
              .toSet();
          expect(tops, hasLength(1), reason: '"$word" in "$text" broke across lines');
          start += word.length + 1;
        }
      }
    });

    testWidgets('is ONE semantics node, and a button when it can be tapped', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, carousel(onTap: () {}));
      final hero = tester.getSemantics(find.bySemanticsLabel(
          'Collected in October, ₹12,24,500, of ₹16,00,000 · 78%'));
      expect(hero.flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel('Beds occupied, 142/160'), findsOneWidget);
      // The figure is not announced a second time on its own.
      expect(find.bySemanticsLabel('142/160'), findsNothing);
      handle.dispose();
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('AppHeader', () {
    Widget header() => AppHeader(
          greeting: 'Good morning, Venkataramanasubramaniam',
          title: 'Sunrise Residency for Working Professionals, Koramangala',
          subtitle: '3 properties · 142 tenants',
          onTitleTap: () {},
          titleSemanticLabel: 'Sunrise Residency, switch property',
          leading: HeaderAvatar(name: 'Lakshmi Venkataraman', onTap: () {}, semanticLabel: 'Your account'),
          actions: [HeaderBell(onPressed: () {}, unreadCount: 3)],
          bottom: HeaderSearchPill(onTap: () {}),
        );

    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.4, 2.0]) {
        testWidgets('long strings at ${width.round()}dp and ${scale}x: nothing overflows',
            (tester) async {
          await _pump(tester, header(), width: width, scale: scale);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the title wraps to two lines only above 1.3x', (tester) async {
      const title = 'Sunrise Residency for Working Professionals, Koramangala';
      await _pump(tester, header());
      expect(tester.widget<Text>(find.text(title)).maxLines, 1);
      await _pump(tester, header(), scale: 2);
      expect(tester.widget<Text>(find.text(title)).maxLines, 2);
    });

    testWidgets('light status icons, the 30dp corners, and its controls named', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, header());
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: find.byType(AppHeader),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      expect(region.value, ApnivaasTheme.onForest);
      expect(
        tester.widget<ClipRRect>(
          find.descendant(of: find.byType(AppHeader), matching: find.byType(ClipRRect)).first,
        ).borderRadius,
        Radii.rHeaderBottom,
      );
      expect(find.bySemanticsLabel('Notifications, 3 unread'), findsOneWidget);
      expect(find.bySemanticsLabel('Your account'), findsOneWidget);
      expect(find.bySemanticsLabel('Sunrise Residency, switch property'), findsOneWidget);
      expect(find.bySemanticsLabel('Search tenants, rooms, payments'), findsOneWidget);
      // Every header control is a 48dp target.
      expect(tester.getSize(find.byType(HeaderBell)), const Size.square(48));
      handle.dispose();
    });

    test('the stars stay inside the header, and halos only at the trailing edge', () {
      for (final size in const [Size(320, 140), Size(360, 210), Size(800, 260)]) {
        final stars = HeaderBackdropPainter.starsFor(size, 24);
        expect(stars, isNotEmpty);
        for (final s in stars) {
          final reach = s.dot.haloRadius ?? s.dot.radius;
          expect(s.center.dy + reach, lessThanOrEqualTo(size.height));
          expect(s.center.dx + reach, lessThanOrEqualTo(size.width));
          if (s.halo) {
            expect(s.center.dx, greaterThanOrEqualTo(size.width * HeaderStars.haloMinFraction - 1));
          }
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('ListRow', () {
    testWidgets('the words are one button node; the trailing control is its own target',
        (tester) async {
      final handle = tester.ensureSemantics();
      var opened = 0;
      var reminded = 0;
      await _pump(
        tester,
        ListGroup(children: [
          ListRow(
            avatarName: 'Priya Nair',
            title: 'Priya Nair',
            subtitle: 'Room 204 · ₹8,500 overdue',
            onTap: () => opened++,
            trailing: PillButton(
              label: 'Remind',
              semanticLabel: 'Remind Priya Nair',
              onPressed: () => reminded++,
            ),
          ),
          const ListRow(icon: ClayIcons.electricity, title: 'Meter readings', subtitle: 'Due Friday'),
        ]),
      );
      final row = tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Priya Nair\nRoom 204')));
      expect(row.flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel('Remind Priya Nair'), findsOneWidget);

      await tester.tap(find.text('Remind'));
      expect(reminded, 1);
      expect(opened, 0, reason: 'the trailing control is not swallowed by the row');
      await tester.tap(find.text('Room 204 · ₹8,500 overdue'));
      expect(opened, 1);
      // A list group draws one divider between two rows, none after the last.
      expect(find.descendant(of: find.byType(ListGroup), matching: find.byType(Divider)),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('a navigable row with nothing at its end draws the chevron itself',
        (tester) async {
      await _pump(tester, ListRowCard(title: 'Rooms', subtitle: '12 rooms', onTap: () {}));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('at 2.0x on 320dp the trailing control moves under the words', (tester) async {
      await _pump(
        tester,
        ListGroup(children: [
          ListRow(
            avatarName: 'Venkataramanasubramaniam Raghunathan',
            title: 'Venkataramanasubramaniam Raghunathan',
            subtitle: 'Room 204 · Bed B · ₹8,500 overdue since 5 October',
            trailing: const ListRowAmount(
              amount: '₹8,500',
              status: 'Overdue',
              tone: StatusTone.error,
            ),
          ),
        ]),
        width: 320,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      final words = tester.getBottomLeft(find.text('Venkataramanasubramaniam Raghunathan'));
      final amount = tester.getTopLeft(find.text('₹8,500'));
      expect(amount.dy, greaterThan(words.dy), reason: 'the amount wrapped below the name');
    });

    testWidgets('from 1.3x a phone-width row moves its trailing control under the words, and '
        'a tablet-width row keeps it beside them until 1.6x', (tester) async {
      // At 1.4x on a 360dp phone an amount, its status and a button beside them left a name
      // like "Aarav Sharma" broken over two lines in a 110dp column.
      Widget row() => ListGroup(children: [
            ListRow(
              avatarName: 'Aarav Sharma',
              title: 'Aarav Sharma',
              subtitle: 'Room 101 · Bed 1',
              onTap: () {},
              trailing: const ListRowAmount(amount: '₹7,000', status: 'Paid', tone: StatusTone.success),
            ),
          ]);
      bool wrapped() =>
          tester.getTopLeft(find.text('₹7,000')).dy >
          tester.getBottomLeft(find.text('Aarav Sharma')).dy;

      for (final (width, scale, expectWrap) in [
        (360.0, 1.0, false),
        (360.0, 1.2, false),
        (360.0, 1.3, true),
        (360.0, 1.4, true),
        (768.0, 1.4, false),
        (768.0, 1.6, true),
      ]) {
        await _pump(tester, Padding(padding: const EdgeInsets.all(Space.md), child: row()),
            width: width, scale: scale);
        expect(tester.takeException(), isNull);
        expect(wrapped(), expectWrap, reason: '${width}dp at ${scale}x');
        if (expectWrap) {
          final name = tester.renderObject<RenderParagraph>(find.text('Aarav Sharma'));
          final lines = name
              .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 12))
              .map((b) => b.top.round())
              .toSet();
          expect(lines, hasLength(1),
              reason: 'with the amount below, the name keeps one line at ${scale}x');
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════════════════
  group('banners and states', () {
    testWidgets('the gold banner drops its art before it squeezes the words', (tester) async {
      Widget banner() => ActionBanner(
            title: 'Meter readings due',
            message: 'Rooms 101–108 · due by Friday',
            icon: ClayIcons.electricity,
            actionLabel: 'Start',
            onAction: () {},
          );
      await _pump(tester, banner(), width: 390);
      expect(find.byType(ClayIcon), findsOneWidget);
      // 320dp at 2.0x still leaves the words 206dp beside the shrunken art, so it stays.
      await _pump(tester, banner(), width: 320, scale: 2);
      expect(tester.takeException(), isNull);
      expect(tester.widget<ClayIcon>(find.byType(ClayIcon)).size, ClaySize.banner);
      // A banner squeezed into a 260dp column would leave them 136dp: the art goes.
      await _pump(tester, SizedBox(width: 260, child: banner()), width: 320, scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byType(ClayIcon), findsNothing,
          reason: 'under 180dp of words the art gives way');
      expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    });

    testWidgets('the Mist banner and the note fit 320dp at 2.0x', (tester) async {
      await _pump(
        tester,
        const Column(children: [
          InfoBanner(
            title: 'How a demo works',
            message: 'A 20-minute call with someone who runs PGs, at a time you pick.',
            icon: ClayIcons.calendar,
          ),
          InfoNote(icon: Icons.schedule_rounded, message: 'Every slot is in Indian Standard Time.'),
        ]),
        width: 320,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
    });

    test('the quick-action grid works its columns out from width and text size', () {
      expect(QuickActionGrid.columnsFor(328, 1.0), 4);
      expect(QuickActionGrid.columnsFor(288, 1.0), 3, reason: 'a 320dp phone');
      expect(QuickActionGrid.columnsFor(328, 1.5), 3);
      expect(QuickActionGrid.columnsFor(328, 2.0), 2);
    });

    testWidgets('a section heading keeps its words; the trailing chip moves under it instead',
        (tester) async {
      // At 2.0x a month chip beside "Overview" left "Overvi" on one line and "ew" on the next.
      Widget header() => const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.md),
            child: SectionHeader(
              title: 'Overview',
              trailing: StatusChip(label: 'October 2026'),
            ),
          );

      await _pump(tester, header());
      final title = tester.getRect(find.text('Overview'));
      final chip = tester.getRect(find.text('October 2026'));
      expect((chip.center.dy - title.center.dy).abs(), lessThan(2),
          reason: 'at 1.0x the chip sits on the heading line');
      expect(chip.right, greaterThan(300), reason: 'at the end of the line');

      await _pump(tester, header(), scale: 2);
      expect(tester.takeException(), isNull);
      final heading = tester.renderObject<RenderParagraph>(find.text('Overview'));
      final tops = heading
          .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 8))
          .map((b) => b.top.round())
          .toSet();
      expect(tops, hasLength(1), reason: '"Overview" is one line at 2.0x');
      expect(tester.getRect(find.text('October 2026')).top,
          greaterThanOrEqualTo(tester.getRect(find.text('Overview')).bottom),
          reason: 'the chip gave way, under the heading');
    });

    testWidgets('a quick-action label wraps between words, never inside one', (tester) async {
      // The grid's column count is only the most it may use: it drops columns until the longest
      // word fits its cell. "Read complaints" at 1.4x on a 360dp phone set "complaint" on one
      // line and "s" on the next; at 2.0x "Monthly" broke as "Monthl y".
      const labels = [
        'Post a notice', 'Read complaints', 'See who paid', 'Track expenses', // the owner's
        'Resolve complaint', 'Leave requests', 'Record payment', 'Rooms & beds', // the warden's
        'Monthly bill', 'Record money in', 'Expense charts', // the manager's
        'Report a problem', 'Payment history', // the resident's
      ];
      for (final width in [320.0, 360.0, 411.0]) {
        for (final scale in [1.0, 1.3, 1.4, 1.6, 1.8, 2.0]) {
          await _pump(
            tester,
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: QuickActionGrid(actions: [
                for (final l in labels) QuickActionTile(icon: ClayIcons.tasks, label: l, onTap: () {}),
              ]),
            ),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          for (final label in labels) {
            final p = tester.renderObject<RenderParagraph>(find.text(label));
            expect(p.didExceedMaxLines, isFalse, reason: '"$label" cut short at ${scale}x, ${width}dp');
            var start = 0;
            for (final word in label.split(' ')) {
              final tops = p
                  .getBoxesForSelection(
                      TextSelection(baseOffset: start, extentOffset: start + word.length))
                  .map((b) => b.top.round())
                  .toSet();
              expect(tops, hasLength(1),
                  reason: '"$word" in "$label" broke across lines at ${scale}x on ${width}dp');
              start += word.length + 1;
            }
          }
        }
      }
    });

    testWidgets('a state body draws the clay art for a first-run state and a glyph otherwise',
        (tester) async {
      await _pump(
        tester,
        const StateBody(
          icon: Icons.campaign_outlined,
          illustration: EmptyArt.notices,
          title: 'No notices yet',
        ),
      );
      expect(tester.widget<ClayIcon>(find.byType(ClayIcon)).asset, ClayIcons.announcement);
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);

      await _pump(
        tester,
        const StateBody(icon: Icons.search_off_rounded, title: 'No match for “kumar”'),
      );
      expect(find.byType(ClayIcon), findsNothing,
          reason: '"no match" must not borrow the first-run art');
      expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    });

    testWidgets('skeleton presets are one live region each and fit 320dp at 2.0x',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const Column(children: [
          QuickActionsSkeleton(semanticLabel: 'Loading quick actions'),
          ListSkeleton(semanticLabel: 'Loading tenants'),
          TileSkeleton(width: StatTile.plainWidth, semanticLabel: 'Loading overview'),
        ]),
        width: 320,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      for (final label in ['Loading quick actions', 'Loading tenants', 'Loading overview']) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.flagsCollection.isLiveRegion, isTrue, reason: label);
      }
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the overview skeleton is laid out by the carousel it stands in for',
        (tester) async {
      // Three homes drew their own strip of blocks at hard-coded widths, which at 2.0x stayed
      // a sideways strip while the real tiles arrived as a two-column wrap.
      final handle = tester.ensureSemantics();
      // The tile blocks are the Containers at the tile's resting height.
      Size block(int i) => [
            for (final e in find
                .descendant(of: find.byType(StatCarouselSkeleton), matching: find.byType(Container))
                .evaluate())
              if ((e.widget as Container).constraints?.minHeight == StatTile.minHeight)
                (e.renderObject! as RenderBox).size,
          ][i];

      await _pump(tester, const StatCarouselSkeleton(semanticLabel: 'Loading overview'));
      expect(tester.takeException(), isNull);
      expect(block(0).width, StatTile.heroWidth);
      expect(block(1).width, StatTile.plainWidth);
      expect(tester.getSemantics(find.bySemanticsLabel('Loading overview')).flagsCollection
          .isLiveRegion, isTrue);

      await _pump(tester, const StatCarouselSkeleton(semanticLabel: 'Loading overview'), scale: 2);
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: find.byType(StatCarousel), matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(block(0).width, greaterThan(block(1).width * 1.9), reason: 'the hero spans the row');
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
