library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perf/tab_warmer.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import 'data/manager_models.dart';
import 'data/manager_providers.dart';
import 'expenses/manager_expenses_screen.dart';
import 'home/manager_home_screen.dart';
import 'menu/manager_menu_screen.dart';
import 'tasks/manager_tasks_screen.dart';
import '../../shared/motion/tab_swap.dart';

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

  /// The clay art for each tab, index for index with [_screens] and with
  /// features/shell/role_shell.dart. Home and Expenses are the nav set's own renders, each with a
  /// drawn "off" twin (see [ClayIcons.navPairs]); Tasks takes the pinned-notes board and Menu
  /// the thali, which [ClayNavBar] draws through its greyscale filter when they are not
  /// selected.
  static const _art = [
    ClayIcons.navHome,
    ClayIcons.navMoney,
    _tasksArt,
    ClayIcons.food,
  ];

  /// Named on its own because the Tasks destination is built in [_tasksTab], with its badge.
  static const _tasksArt = ClayIcons.tasks;

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
      // Tasks tab: the badge sends people here. Same TaskQuery the home screen's "Today's tasks"
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
      // The bar animated its own indicator and the page it commands did not, which reads as
      // the two being unconnected. TabSwap keeps this ONE IndexedStack — swapping it out for
      // an AnimatedSwitcher would change its key and throw away every tab's scroll position,
      // which is the whole reason an IndexedStack is here. See shared/motion/tab_swap.dart.
      body: TabSwap(
        index: index,
        child: IndexedStack(
          index: index,
          children: [
            for (var i = 0; i < _screens.length; i++)
              _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
          ],
        ),
      ),
      // The clay bar every role shares: the selected tab's art on a Mist pill with its label in
      // forest, the rest grey. It sizes itself from its label — 72dp at 1.0x, a little taller
      // with large text — and each tab is one button to a screen reader, "Tasks, tab 3 of 4,
      // 2 overdue". See shared/clay/nav_bar.dart.
      bottomNavigationBar: ClayNavBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(managerTabProvider.notifier).go(i),
        destinations: [
          ClayNavDestination(icon: _art[0], label: 'Home'),
          ClayNavDestination(icon: _art[1], label: 'Expenses'),
          _tasksTab(load),
          ClayNavDestination(icon: _art[3], label: 'Menu'),
        ],
      ),
    );
  }
}

/// The Tasks tab — with a count on it, and, when the count could not be read, a mark that says
/// so.
///
/// The badge is the OVERDUE figure, not the open one: a manager with a healthy list of four
/// jobs does not need a red dot following them around, and a badge that is always lit stops
/// meaning anything.
///
/// FOUR STATES, THREE FACES. A real zero and a count still in flight both draw no badge —
/// those two are safe to share, because a badge that appears a moment late costs nothing and
/// "0" is noise. A count that FAILED draws the bar's plain red dot instead: not a number, so it
/// cannot be read as one, and a screen reader hears "overdue count unavailable" after the tab's
/// name. Tapping through lands on a Tasks header that names the failure too.
///
/// [load] is null when there is no hostel on the account, so there is nothing to count in the
/// first place — distinct from a count that failed.
ClayNavDestination _tasksTab(AsyncValue<TaskLoad>? load) {
  const art = _ManagerShellState._tasksArt;
  // hasValue first, so a failed refresh does not replace a count that is already correct.
  if (load != null && load.hasValue) {
    final overdue = load.requireValue.overdue;
    if (overdue > 0) {
      return ClayNavDestination(
        icon: art,
        label: 'Tasks',
        badgeCount: overdue,
        badgeLabel: '$overdue overdue',
      );
    }
  } else if (load != null && load.hasError) {
    return const ClayNavDestination(
      icon: art,
      label: 'Tasks',
      hasBadge: true,
      badgeLabel: 'overdue count unavailable',
    );
  }
  return const ClayNavDestination(icon: art, label: 'Tasks'); // clear, still counting, or no PG
}
