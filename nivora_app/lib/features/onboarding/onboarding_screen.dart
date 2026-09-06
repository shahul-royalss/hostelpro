import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';

/// WHAT THIS APP IS, said once, before anybody is asked to sign in.
///
/// ── WHY IT EXISTS ─────────────────────────────────────────────────────────────────────────
///
/// NIVORA had no onboarding at all. Not a thin one — none: a new user went from the splash
/// straight to a sign-in form, with no sentence anywhere telling them what the product does.
/// Grepping for it turned up nothing but a super-admin bar chart and two comments in the shells
/// saying they deliberately avoid a PageView. The competitor opens with four full-bleed pages
/// and it is the first thing anybody sees of it.
///
/// This is that device, with two departures.
///
/// THE COLOURS ARE NIVORA'S OWN DOMAINS, not theirs. Theirs are amber, teal, blue and orchid —
/// four accents with no relationship to each other or to anything else in their app. Each page
/// here is the deep form of the domain tone that owns the feature it describes: the brand for
/// the building, people-teal for residents, a deep green for money, terracotta for the daily
/// run of the place. The sequence is the product's own vocabulary, in order.
///
/// THE COPY SAYS WHAT NIVORA DOES, which differs from theirs in one way that matters: rent
/// settles into the PG owner's own account rather than the platform's. Page three says so,
/// because it is the thing an owner most needs to hear and the thing a competitor cannot claim
/// without having built Razorpay Route.
///
/// Every ground below carries its measured ratio for white. The lowest is 7.48:1.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called once, when the last page is accepted or the sequence is skipped. The caller writes
  /// the marker and swaps this screen out; this widget owns no persistence of its own.
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page(this.ground, this.icon, this.title, this.body);
  final Color ground;
  final IconData icon;
  final String title;
  final String body;
}

const _pages = <_Page>[
  _Page(
    NivoraColors.brandDeep, // white 10.20:1
    Icons.apartment_rounded,
    'Every floor, room and bed',
    'Map the building once. After that, putting a resident in a bed takes two taps.',
  ),
  _Page(
    Color(0xFF0F5F5B), // the people tone, deepened. white 7.48:1
    Icons.groups_2_rounded,
    'Residents, not spreadsheets',
    'Check someone in, move them rooms, check them out. Their history stays with them.',
  ),
  _Page(
    Color(0xFF1B5E43), // money. white 7.70:1
    Icons.account_balance_wallet_rounded,
    'Rent that reaches the owner',
    'Residents pay by UPI or card, or hand cash to the warden. Either way it settles into '
        'the PG owner’s own account.',
  ),
  _Page(
    Color(0xFF8A3D12), // the daily run of the place. white 7.62:1
    Icons.campaign_rounded,
    'The day-to-day, in one place',
    'This week’s menu, a notice that reaches every phone in the building, and a complaint '
        'you can actually close.',
  ),
];

const _ink = Color(0xFFFFFFFF);

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
    _controller.nextPage(duration: Motion.slow, curve: Motion.move);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final page = _pages[_index];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // All four grounds are dark, in both themes, so the status bar is light on every page.
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: AnimatedContainer(
        // The ground cross-fades rather than sliding with the page: the colour is the page's
        // identity, and a hard cut between four saturated fills is jarring on a swipe that can
        // be dragged halfway and released.
        duration: Motion.base,
        curve: Motion.move,
        color: page.ground,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _PageBody(page: _pages[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.xl,
                    vertical: Space.md,
                  ),
                  child: Row(
                    children: [
                      // SKIP goes away on the last page: there is nothing left to skip, and a
                      // control that does the same thing as the one beside it is a coin toss.
                      // The box stays, so the dots do not jump when it leaves.
                      SizedBox(
                        width: 96,
                        child: _last
                            ? const SizedBox.shrink()
                            : Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: widget.onDone,
                                  style: TextButton.styleFrom(foregroundColor: _ink),
                                  child: const Text('Skip'),
                                ),
                              ),
                      ),
                      Expanded(child: _Dots(count: _pages.length, index: _index)),
                      SizedBox(
                        width: 96,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _next,
                            style: TextButton.styleFrom(foregroundColor: _ink),
                            child: Text(
                              _last ? 'Get started' : 'Next',
                              style: t.textTheme.labelLarge?.copyWith(color: _ink),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - Space.xl * 2),
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // A line glyph, in white — the competitor's own choice and the right one. A filled
          // illustration at this size on a saturated ground turns into a blob.
          //
          // The size yields to the text scale rather than competing with it. At 2.0x the
          // heading and paragraph need roughly twice the room, and 96dp of decoration is the
          // first thing that should give it up — an icon at 56 still reads as the same icon,
          // where a clipped paragraph does not read at all.
          Icon(
            page.icon,
            size: 96 / MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.7),
            color: _ink,
          ),
          const SizedBox(height: Space.xxl),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: t.textTheme.displaySmall?.copyWith(color: _ink),
          ),
          const SizedBox(height: Space.md),
          Text(
            page.body,
            textAlign: TextAlign.center,
            // 82% white is 6.1:1 on the lightest of the four grounds — quieter than the
            // heading and still well clear of AA for body text.
            style: t.textTheme.bodyLarge?.copyWith(color: _ink.withValues(alpha: 0.82)),
          ),
        ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final on = i == index;
          return AnimatedContainer(
            duration: Motion.base,
            curve: Motion.move,
            margin: const EdgeInsets.symmetric(horizontal: Space.xxs / 2),
            height: Space.xs,
            // The current page's dot STRETCHES rather than merely brightening. Four discs that
            // differ only in alpha are hard to count at a glance; one that is a different
            // shape is not.
            width: on ? Space.xl : Space.xs,
            decoration: BoxDecoration(
              color: _ink.withValues(alpha: on ? 1 : 0.38),
              borderRadius: Radii.rPill,
            ),
          );
        }),
      );
}
