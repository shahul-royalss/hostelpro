library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perf/tab_warmer.dart';
import '../../shared/clay/clay.dart';
import '../../data/models/models.dart';
import 'data/sa_providers.dart';
import 'sa_hostels_screen.dart';
import 'sa_overview_screen.dart';
import 'sa_security_screen.dart';
import 'sa_subscriptions_screen.dart';
import '../../shared/motion/tab_swap.dart';

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
        saHostelListProvider(const SaHostelQuery(subState: SubscriptionState.expiring)).future,
      ),
      () => ref.read(
        saHostelListProvider(const SaHostelQuery(subState: SubscriptionState.expired)).future,
      ),
    ])..start();
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

  /// The area each tab belongs to, which is the colour its selected pill takes: the violet of
  /// the building on Hostels, the ledger green on Subscriptions, and the brand gold on the two
  /// that are the platform's own. A tab is a domain and never a state — see [ApnivaasDomain].
  @override
  Widget build(BuildContext context) {
    final index = ref.watch(saTabProvider).clamp(0, SaTabs.count - 1);
    final openAlerts = ref.watch(saOpenAlertCountProvider);
    _visited.add(index);

    return Scaffold(
      body: TabSwap(
        index: index,
        child: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < SaTabs.count; i++)
              if (_visited.contains(i)) _tabs[i] else const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: ClayNavBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(saTabProvider.notifier).go(i),
        destinations: [
          const ClayNavDestination(icon: ClayIcons.navHome, label: 'Overview'),
          const ClayNavDestination(icon: ClayIcons.navProperty, label: 'Hostels'),
          const ClayNavDestination(icon: ClayIcons.navMoney, label: 'Subscriptions'),
          securityDestination(openAlerts),
        ],
      ),
    );
  }
}

/// The Security tab, badged with the open-alert count. A count it could not read is marked
/// (a dot, spoken as unavailable) rather than drawn as the best possible day; zero draws nothing.
@visibleForTesting
ClayNavDestination securityDestination(AsyncValue<int> alerts) {
  const art = ClayIcons.security;
  if (alerts.hasError && !alerts.hasValue) {
    return const ClayNavDestination(
      icon: art,
      label: 'Security',
      hasBadge: true,
      badgeLabel: 'open alert count unavailable',
    );
  }
  final value = alerts.value ?? 0;
  if (value <= 0) return const ClayNavDestination(icon: art, label: 'Security');
  return ClayNavDestination(
    icon: art,
    label: 'Security',
    badgeCount: value,
    badgeLabel: '$value open',
  );
}
