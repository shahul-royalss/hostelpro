import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../shared/clay/clay_icons.dart';
import '../auth/auth_scaffold.dart' show AuthTopBar;

/// WHAT THIS APP IS, said once, before anybody is asked to sign in.
///
/// ── WHY IT EXISTS ─────────────────────────────────────────────────────────────────────────
///
/// Apnivaas had no onboarding at all. Not a thin one — none: a new user went from the splash
/// straight to a sign-in form, with no sentence anywhere telling them what the product does.
/// Grepping for it turned up nothing but a super-admin bar chart and two comments in the shells
/// saying they deliberately avoid a PageView. The competitor opens with four full-bleed pages
/// and it is the first thing anybody sees of it.
///
/// This is that device, with two departures.
///
/// THE PICTURES ARE APNIVAAS'S OWN. Each page is a small arrangement of the clay icons that
/// stand for its feature everywhere else in the app — the building with a room and a bed, two
/// residents with the move-in and move-out bags, the rent phone with the wallet and the bank,
/// the noticeboard megaphone with the menu and a complaint — on the cream page and the Mist disc
/// the app's empty states use. Until the Forest & Cream restyle each page was a different
/// saturated ground (brand violet, teal, green, terracotta); the clay carries what kind of page
/// it is now, so the ground can be the app's own and the tour arrives at the sign-in screen
/// without changing colour on the way.
///
/// THE COPY SAYS WHAT Apnivaas DOES, which differs from theirs in one way that matters: rent
/// settles into the PG owner's own account rather than the platform's. Page three says so,
/// because it is the thing an owner most needs to hear and the thing a competitor cannot claim
/// without having built Razorpay Route.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called once, when the last page is accepted or the sequence is skipped. The caller writes
  /// the marker and swaps this screen out; this widget owns no persistence of its own.
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page({
    required this.art,
    required this.first,
    required this.second,
    required this.title,
    required this.body,
  });

  /// The [ClayIcons] path at the centre of the page's picture, and the two that sit at its edge.
  final String art;
  final String first;
  final String second;
  final String title;
  final String body;
}

const _pages = <_Page>[
  _Page(
    art: ClayIcons.navProperty,
    first: ClayIcons.rooms,
    second: ClayIcons.beds,
    title: 'Every floor, room and bed',
    body: 'Map the building once. After that, putting a resident in a bed takes two taps.',
  ),
  _Page(
    art: ClayIcons.navPeople,
    first: ClayIcons.moveIn,
    second: ClayIcons.moveOut,
    title: 'Residents, not spreadsheets',
    body: 'Check someone in, move them rooms, check them out. Their history stays with them.',
  ),
  _Page(
    art: ClayIcons.collectPayment,
    first: ClayIcons.money,
    second: ClayIcons.bankTransfer,
    title: 'Rent that reaches the owner',
    body: 'Residents pay by UPI or card, or hand cash to the warden. Either way it settles into '
        'the PG owner’s own account.',
  ),
  _Page(
    art: ClayIcons.announcement,
    first: ClayIcons.food,
    second: ClayIcons.complaint,
    title: 'The day-to-day, in one place',
    body: 'This week’s menu, a notice that reaches every phone in the building, and a complaint '
        'you can actually close.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _last => _index == _pages.length - 1;

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    // A slide is motion somebody can ask the OS to spare them; the page still changes.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(_index + 1);
      return;
    }
    _controller.nextPage(duration: Motion.slow, curve: Motion.move);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, 0),
              // The sign-in screen's own brand bar, so the tour and the form it hands over to
              // are one page with the middle changing. SKIP goes away on the last page: there
              // is nothing left to skip, and a control that does the same thing as the one
              // under it is a coin toss. The brand sits at the leading edge either way, so
              // nothing moves when it leaves.
              child: AuthTopBar(
                trailing: _last
                    ? null
                    : TextButton(onPressed: widget.onDone, child: const Text('Skip')),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _PageBody(page: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Dots(count: _pages.length, index: _index),
                  const SizedBox(height: Space.lg),
                  FilledButton(
                    onPressed: _next,
                    // The large call to action: 56 tall, the 18 corner.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(Space.huge + Space.xs),
                      shape: const RoundedRectangleBorder(borderRadius: Radii.rButtonLarge),
                    ),
                    child: Text(_last ? 'Get started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page});
  final _Page page;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // THIS OVERFLOWED BY 67 PIXELS and test/responsive_test.dart is why I know the number: a
    // 320dp phone at 2.0x system text, which is Android's accessibility maximum. A centred
    // Column cannot yield, so a page that is one pixel too tall shows the hazard stripe.
    //
    // Scroll view first, centred inside a minimum height equal to the viewport: it stays
    // optically centred at every size that fits, and becomes scrollable at the sizes that do
    // not, instead of breaking. `LayoutBuilder` supplies the viewport height because a
    // SingleChildScrollView gives its child unbounded height and Center inside one would
    // otherwise collapse.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - Space.lg * 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The picture yields to the text scale rather than competing with it. At 2.0x the
              // heading and paragraph need roughly twice the room, and the decoration is the
              // first thing that should give it up — the clay still reads as the same picture
              // at 60%, where a clipped paragraph does not read at all.
              _Picture(
                page: page,
                scale: 1 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7),
              ),
              const SizedBox(height: Space.xxl),
              Semantics(
                header: true,
                child: Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: t.textTheme.displayMedium,
                ),
              ),
              const SizedBox(height: Space.sm),
              ConstrainedBox(
                // A paragraph keeps a readable measure on a tablet instead of one long line.
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page's picture: its clay icon on a Mist disc, with two smaller ones seated on card discs at
/// the disc's edge — what the feature is, and two things it holds. Decorative: the title under
/// it says the same thing in words, so the whole picture is out of the semantics tree.
class _Picture extends StatelessWidget {
  const _Picture({required this.page, required this.scale});

  final _Page page;

  /// 1 at normal text, down to 0.6 at the largest.
  final double scale;

  /// The Mist disc, and the box the arrangement is laid out in.
  static const _disc = 160.0;
  static const _box = Size(216, 192);

  /// A satellite's card disc.
  static const _seat = 64.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final mist = dark ? ApnivaasColors.darkMist : ApnivaasColors.mist;

    Widget seat(String icon) => SizedBox.square(
          dimension: _seat,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: t.colorScheme.outlineVariant, width: Strokes.hairline),
            ),
            child: Center(child: ClayIcon(icon, size: ClaySize.list)),
          ),
        );

    return ExcludeSemantics(
      child: SizedBox(
        width: _box.width * scale,
        height: _box.height * scale,
        child: FittedBox(
          child: SizedBox.fromSize(
            size: _box,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: _disc,
                  height: _disc,
                  decoration: BoxDecoration(color: mist, shape: BoxShape.circle),
                ),
                ClayIcon(page.art, size: ClaySize.promo),
                Positioned(top: Space.xs, right: Space.xxs, child: seat(page.first)),
                Positioned(bottom: Space.xs, left: Space.xxs, child: seat(page.second)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the reader is in the four pages.
///
/// The current page's dot STRETCHES rather than merely darkening. Four discs that differ only in
/// colour are hard to count at a glance; one that is a different shape is not. The row is one
/// semantics node saying the same thing in words.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Semantics(
      label: 'Page ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final on = i == index;
          return AnimatedContainer(
            duration: Motion.base,
            curve: Motion.move,
            margin: const EdgeInsets.symmetric(horizontal: Space.xxs / 2),
            height: Space.xs,
            width: on ? Space.xl : Space.xs,
            decoration: BoxDecoration(
              // Forest for where you are; Sage, a decorative green, for the pages either side.
              color: on ? t.colorScheme.primary : ApnivaasColors.sage,
              borderRadius: Radii.rPill,
            ),
          );
        }),
      ),
    );
  }
}
