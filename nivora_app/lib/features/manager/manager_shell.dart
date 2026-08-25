library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'data/manager_models.dart';
import 'data/manager_providers.dart';
import 'expenses/manager_expenses_screen.dart';
import 'home/manager_home_screen.dart';
import 'menu/manager_menu_screen.dart';
import 'tasks/manager_tasks_screen.dart';

/// The manager's four tabs.
///
/// AN IndexedStack, NOT A PageView OR A REBUILD PER TAB. Each screen keeps its scroll position,
/// its filter chips and its loaded pages while the manager is on another one. Coming back from
/// booking an expense to find the ledger scrolled to the top and the category filter cleared is
/// the kind of small betrayal that makes people stop using a tool — and re-fetching three pages
/// of expenses to undo it costs the hostel's data allowance as well as the manager's patience.
///
/// THE SELECTED TAB IS A PROVIDER, not local state, so the home screen's counts can open the
/// list they counted. See managerTabProvider.
///
/// The labels and their ORDER match features/shell/role_shell.dart exactly. That file is where
/// a reader goes to learn what a role's navigation is, and two files disagreeing about which
/// tab is third is a bug that only shows up as a mis-routed tap.
class ManagerShell extends ConsumerWidget {
  const ManagerShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final index = ref.watch(managerTabProvider);
    final hostelId = ref.watch(currentHostelIdProvider);

    // Already fetched by the home screen under the same key, so the badge costs nothing extra.
    //
    // THE WHOLE AsyncValue, not `.value?.overdue`. That expression is null while the count is
    // in flight, null when the count FAILED and null when RLS refused it — and all three drew
    // exactly what a genuine zero draws: no badge. A tab that silently stops reporting late
    // jobs is indistinguishable from a tab with no late jobs, which is the reading that lets
    // work sit past its date for a week.
    final load = hostelId == null ? null : ref.watch(taskLoadProvider(hostelId));

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          ManagerHomeScreen(),
          ManagerExpensesScreen(),
          ManagerTasksScreen(),
          ManagerMenuScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(managerTabProvider.notifier).go(i),
        // 64dp keeps every destination above the 48dp minimum with room for the label.
        height: 64,
        backgroundColor: t.colorScheme.surface,
        indicatorColor: t.colorScheme.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.trending_down_rounded), label: 'Expenses'),
          NavigationDestination(
            icon: _Badged(load: load, child: const Icon(Icons.checklist_rounded)),
            label: 'Tasks',
          ),
          const NavigationDestination(icon: Icon(Icons.restaurant_rounded), label: 'Menu'),
        ],
      ),
    );
  }
}

/// A count on a tab icon — and, when the count could not be read, a mark that says so.
///
/// The badge is the OVERDUE figure, not the open one: a manager with a healthy list of four
/// jobs does not need a red dot following them around, and a badge that is always lit stops
/// meaning anything.
///
/// FOUR STATES, THREE FACES. A real zero and a count still in flight both draw no badge —
/// those two are safe to share, because a badge that appears a moment late costs nothing and
/// "0" is noise. A count that FAILED draws "!" instead: not a number, so it cannot be read as
/// one, and tapping through to Tasks lands on a header that now names the failure.
class _Badged extends StatelessWidget {
  const _Badged({required this.load, required this.child});

  /// Null when there is no hostel on the account, so there is nothing to count in the first
  /// place — distinct from a count that failed.
  final AsyncValue<TaskLoad>? load;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = load;
    if (value == null) return child;

    // hasValue first, so a failed refresh does not replace a count that is already correct.
    if (value.hasValue) {
      final overdue = value.requireValue.overdue;
      if (overdue <= 0) return child;
      return Badge.count(count: overdue, child: child);
    }

    if (value.hasError) {
      return Semantics(
        label: 'Overdue jobs unknown: the count could not be read',
        child: Badge(label: const Text('!'), child: child),
      );
    }

    return child; // still counting
  }
}
