library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
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
    // Null while it loads, and null is drawn as NO badge rather than as a zero: a badge reading
    // "0" is noise that trains people to ignore badges.
    final overdue = hostelId == null
        ? null
        : ref.watch(taskLoadProvider(hostelId)).value?.overdue;

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
            icon: _Badged(count: overdue, child: const Icon(Icons.checklist_rounded)),
            label: 'Tasks',
          ),
          const NavigationDestination(icon: Icon(Icons.restaurant_rounded), label: 'Menu'),
        ],
      ),
    );
  }
}

/// A count on a tab icon, shown only when there is something to count.
///
/// The badge is the OVERDUE figure, not the open one: a manager with a healthy list of four
/// jobs does not need a red dot following them around, and a badge that is always lit stops
/// meaning anything.
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
