library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perf/tab_warmer.dart';
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
/// A TAB IS BUILT ON FIRST VISIT, BUT ITS DATA IS ALREADY THERE. The old shell built all four
/// screens in the mount frame, which put six requests on the wire at once — the home screen's
/// own reads queueing behind the menu's on a phone radio. Now the mount frame builds home
/// alone (plus the badge's count), and a [TabWarmer] starts every other tab's first-page read
/// in the background, staggered, once home has had its head start. The warmed providers call
/// `holdForSession` (see manager_providers.dart), so by the time a tab is tapped its data is
/// sitting in the cache and the first build renders it synchronously — no skeleton, no
/// spinner. A skeleton on a tab tap after the shell has been up for a moment is a bug, and
/// test/manager_warmup_test.dart pins exactly that.
///
/// THE SELECTED TAB IS A PROVIDER, not local state, so the home screen's counts can open the
/// list they counted. See managerTabProvider.
///
/// The labels and their ORDER match features/shell/role_shell.dart exactly. That file is where
/// a reader goes to learn what a role's navigation is, and two files disagreeing about which
/// tab is third is a bug that only shows up as a mis-routed tap.
class ManagerShell extends ConsumerStatefulWidget {
  const ManagerShell({super.key});

  @override
  ConsumerState<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends ConsumerState<ManagerShell> {
  /// The four bodies, in navigation order. Index 0 is home and is always built.
  static const _screens = <Widget>[
    ManagerHomeScreen(),
    ManagerExpensesScreen(),
    ManagerTasksScreen(),
    ManagerMenuScreen(),
  ];

  /// Tabs that have been shown at least once, and are kept built (state, scroll, filters)
  /// from then on. Home is born visited.
  final _visited = <int>{0};

  TabWarmer? _warmer;

  @override
  void initState() {
    super.initState();
    // Order = tap likelihood. HOME IS NOT IN THE LIST: its screen is built in this same
    // frame and its watches dispatch before the first warmer fires (TabWarmer gives it a
    // full interval's head start). The last two are belt and braces — the badge below and
    // the home screen already hold those exact family instances live, so warming them is a
    // join on the in-flight fetch, never a second request.
    _warmer = TabWarmer([
      // Tasks tab: the badge sends people here. Same TaskQuery the home screen's "Next up"
      // uses, but on a short viewport that section can sit below the fold and never mount,
      // so the tab cannot lean on it having fetched.
      _warm((id) => ref.read(tasksProvider(TaskQuery(hostelId: id, openOnly: true)).future)),
      // Expenses tab, default view: money out, all categories.
      _warm((id) => ref.read(managerExpensesProvider(ExpenseQuery(hostelId: id)).future)),
      // Menu tab: the whole week in one request.
      _warm((id) => ref.read(weeklyMenuProvider(id).future)),
      // The "Money in" segment of the Expenses tab — not built until the segment is tapped,
      // so nothing else ever fetches it.
      _warm((id) => ref.read(managerRevenuesProvider(id).future)),
      _warm((id) => ref.read(taskLoadProvider(id).future)),
      _warm((id) => ref.read(managerFinanceProvider(id).future)),
    ])..start();
  }

  @override
  void dispose() {
    _warmer?.cancel();
    super.dispose();
  }

  /// Reads the hostel at FIRE time, not at mount: a warmer that runs after sign-out (or on an
  /// account with no hostel) must quietly do nothing rather than fetch under a stale key.
  Warmer _warm(Future<Object?> Function(String hostelId) read) => () {
        final id = ref.read(currentHostelIdProvider);
        if (id == null) return null;
        return read(id);
      };

  @override
  Widget build(BuildContext context) {
    // CLAMPED, like the owner's, the student's and the super admin's sections already are. See
    // warden_shell.dart for what an out-of-range IndexedStack index costs: not an exception a
    // user can report, but a body that draws nothing under a tab bar that still works.
    final index = ref.watch(managerTabProvider).clamp(0, _screens.length - 1);
    final hostelId = ref.watch(currentHostelIdProvider);
    _visited.add(index);

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
        children: [
          for (var i = 0; i < _screens.length; i++)
            _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
        ],
      ),
      // THE BAR IS THE THEME'S, NOT THIS FILE'S. NavigationBarThemeData in theme.dart already
      // sets the raised fill, the 64dp height, the always-on labels and — the one that matters
      // — the gold indicator at the design's own 10% chip alpha, measured once in
      // NivoraSemantics. The three overrides that used to be here restated two of those and
      // got the third wrong: a hand-typed `withValues(alpha: 0.12)` is exactly the kind of
      // plausible-looking number tokens.dart exists to stop.
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(managerTabProvider.notifier).go(i),
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
