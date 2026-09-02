library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perf/tab_warmer.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import 'data/sa_providers.dart';
import 'sa_hostels_screen.dart';
import 'sa_overview_screen.dart';
import 'sa_security_screen.dart';
import 'sa_subscriptions_screen.dart';

/// The Super Admin's four tabs.
///
/// AN IndexedStack, NOT A REBUILD PER TAB. Each tab keeps its scroll position, its search term
/// and its loaded pages while the admin is on another one. Coming back from a hostel's detail
/// to find the list scrolled back to the top — and four pages of rpc_sa_hostels refetched to
/// put it there — is the small betrayal that makes a tool feel disposable.
///
/// WIDGETS LAZY, DATA WARM. Only the Overview is built at mount, so rpc_sa_dashboard — the
/// product owner's first impression — has the network to itself for its first paint. The other
/// three tabs' DATA is then warmed in the background by a [TabWarmer], staggered so warm-up
/// never contends with what is on screen, and held for the session (see the lifetime policy in
/// lib/data/providers.dart). A tab's widget is built the first time it is tapped — by which
/// point its providers already hold data, so arrival renders the answer, never a skeleton —
/// and is kept in the stack afterwards. Building all four up front instead would fire every
/// console query in the same frame the Overview is trying to win.
///
/// THE SELECTED TAB IS A PROVIDER, not local state, so the Overview's figures can open the tab
/// that lists what they counted. "3 expired" lands on Subscriptions already filtered to
/// `expired`; the number and the list are then the same query and cannot disagree.
///
/// The tab labels and their ORDER match features/shell/role_shell.dart and [SaTabs] exactly.
/// role_shell is the place a reader looks to learn what a role's navigation is, and two files
/// disagreeing about which tab is third is a bug that only shows up as a mis-routed tap.
class SaShell extends ConsumerStatefulWidget {
  const SaShell({super.key});

  @override
  ConsumerState<SaShell> createState() => _SaShellState();
}

class _SaShellState extends ConsumerState<SaShell> {
  /// Tabs whose widget exists. The Overview is what sign-in lands on, so it starts here; the
  /// rest join on first visit and never leave, which is what preserves their scroll positions.
  final _visited = <int>{SaTabs.overview};

  TabWarmer? _warmer;

  @override
  void initState() {
    super.initState();
    // Every closure reads the SAME provider the tab's screen will watch — same query, same
    // RLS — so warming cannot widen a read; it only starts, early, a request the screen was
    // already entitled to make. The Overview's own reads (rpc_sa_dashboard, the onboarding
    // series, and the open-alert count this shell's badge watches) are NOT here: they are
    // dispatched by the first build below and get a full interval's head start.
    _warmer = TabWarmer([
      // Hostels' first page — and, because the default SaHostelQuery is value-equal to the
      // Subscriptions tab with no state picked, the Subscriptions tab's first page too.
      () => ref.read(saHostelListProvider(const SaHostelQuery()).future),
      // The Security console, on its default "Unacknowledged" filter.
      () => ref.read(saAlertsProvider(true).future),
      // The two lists the Overview's attention band deep-links to. "3 expired — tap to see
      // which" must land on the answer, not on a skeleton earning it.
      () => ref.read(
          saHostelListProvider(const SaHostelQuery(subState: SubscriptionState.expiring)).future),
      () => ref.read(
          saHostelListProvider(const SaHostelQuery(subState: SubscriptionState.expired)).future),
    ])
      ..start();
  }

  @override
  void dispose() {
    _warmer?.cancel();
    super.dispose();
  }

  /// Index-addressed to match [SaTabs]; the IndexedStack below substitutes a shrink box for
  /// any not yet visited.
  static const _tabs = <Widget>[
    SaOverviewScreen(),
    SaHostelsScreen(),
    SaSubscriptionsScreen(),
    SaSecurityScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final index = ref.watch(saTabProvider).clamp(0, SaTabs.count - 1);
    final openAlerts = ref.watch(saOpenAlertCountProvider);
    _visited.add(index);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < SaTabs.count; i++)
            if (_visited.contains(i)) _tabs[i] else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(saTabProvider.notifier).go(i),
        // 64dp keeps every destination above the 48dp minimum with room for the label.
        height: 64,
        backgroundColor: t.colorScheme.surface,
        // The design's own tint recipe rather than an alpha picked by eye — the same 10% that
        // sits behind every status badge in the file.
        indicatorColor: context.tones.chipFill(t.colorScheme.primary),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.grid_view_rounded), label: 'Overview'),
          const NavigationDestination(
              icon: Icon(Icons.apartment_rounded), label: 'Hostels'),
          const NavigationDestination(
              icon: Icon(Icons.card_membership_rounded), label: 'Subscriptions'),
          NavigationDestination(
            icon: _Badged(alerts: openAlerts, child: const Icon(Icons.shield_rounded)),
            label: 'Security',
          ),
        ],
      ),
    );
  }
}

/// A count on a tab icon — and, when the count could not be read, a mark that says so.
///
/// A badge reading "0" is visual noise that trains people to ignore badges, so zero draws
/// nothing and the absence of a badge is the message. STILL LOADING draws nothing either: a
/// number that appears a moment later is not worth a placeholder.
///
/// A FAILED READ IS THE THIRD CASE AND IT USED TO LOOK LIKE THE FIRST. Folding it into "no
/// badge" means the tab bar shows exactly what it shows on the best possible day — nothing to
/// answer for — at the moment the console cannot tell whether there is. This draws a "?"
/// instead: not a count, not silence, and the Security tab it points at carries the failure in
/// full with a retry on it.
class _Badged extends StatelessWidget {
  const _Badged({required this.alerts, required this.child});
  final AsyncValue<int> alerts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (alerts.hasError && !alerts.hasValue) {
      return Badge(
        label: const Text('?'),
        // Default badge colours: whatever this theme guarantees is legible on a badge. A tinted
        // one hand-mixed here is the kind of thing that reads as white-on-amber in dark mode.
        child: child,
      );
    }
    final value = alerts.value;
    if (value == null || value <= 0) return child;
    return Badge.count(count: value, child: child);
  }
}
