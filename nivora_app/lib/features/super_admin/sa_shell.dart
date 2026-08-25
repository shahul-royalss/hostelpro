library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// THE SELECTED TAB IS A PROVIDER, not local state, so the Overview's figures can open the tab
/// that lists what they counted. "3 expired" lands on Subscriptions already filtered to
/// `expired`; the number and the list are then the same query and cannot disagree.
///
/// The tab labels and their ORDER match features/shell/role_shell.dart and [SaTabs] exactly.
/// role_shell is the place a reader looks to learn what a role's navigation is, and two files
/// disagreeing about which tab is third is a bug that only shows up as a mis-routed tap.
class SaShell extends ConsumerWidget {
  const SaShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final index = ref.watch(saTabProvider);
    final openAlerts = ref.watch(saOpenAlertCountProvider);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          SaOverviewScreen(),
          SaHostelsScreen(),
          SaSubscriptionsScreen(),
          SaSecurityScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index.clamp(0, SaTabs.count - 1),
        onDestinationSelected: (i) => ref.read(saTabProvider.notifier).go(i),
        // 64dp keeps every destination above the 48dp minimum with room for the label.
        height: 64,
        backgroundColor: t.colorScheme.surface,
        indicatorColor: t.colorScheme.primary.withValues(alpha: 0.12),
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
