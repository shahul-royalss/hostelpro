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
    final openAlerts = ref.watch(saOpenAlertCountProvider).value;

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
            icon: _Badged(count: openAlerts, child: const Icon(Icons.shield_rounded)),
            label: 'Security',
          ),
        ],
      ),
    );
  }
}

/// A count on a tab icon, shown only when there is something to count.
///
/// A badge reading "0" is visual noise that trains people to ignore badges; the absence of one
/// is the message. Null — still loading, or the count could not be read — is likewise nothing
/// rather than a zero, because a security console that silently reads zero is worse than one
/// that says nothing.
class _Badged extends StatelessWidget {
  const _Badged({required this.count, required this.child});
  final int? count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = count;
    if (value == null || value <= 0) return child;
    return Badge.count(count: value, child: child);
  }
}
