library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/perf/tab_warmer.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay_icons.dart';
import 'owner_dashboard_screen.dart';
import 'owner_payments_screen.dart';
import 'owner_pg_list_screen.dart';
import 'owner_providers.dart';
import 'owner_students_screen.dart';
import 'more/owner_more_screen.dart';
import 'staff/staff_providers.dart';
import '../../shared/motion/tab_swap.dart';

/// The owner's five tabs, in the order the bar draws them: Home · Money · People · Property ·
/// More — the shape RentOk taught PG owners to expect, mapped onto the sections this app already
/// had.
///
/// ── WHERE EACH OLD SECTION WENT ──────────────────────────────────────────────────────────
///
/// Dashboard is Home. Payments ("who paid") is Money. Students is People, which also carries the
/// way into staff accounts, because the question "who works here" sits next to "who lives here".
/// PGs — the list, each PG's room grid and its floor plan — is Property. More keeps staff, tasks
/// and the expense charts, and is now where the account itself is reached as well.
///
/// The bar itself is drawn by features/shell/role_shell.dart from [ownerTabs]; this file supplies
/// the labels, the clay art and the bodies, so the two can no longer disagree about which tab is
/// third.
enum OwnerTab {
  home('Home', ClayIcons.navHome),
  money('Money', ClayIcons.navMoney),
  people('People', ClayIcons.navPeople),
  property('Property', ClayIcons.navProperty),
  // No off-render was supplied for the gear, so the bar draws it through the greyscale filter
  // when unselected — see ClayNavDestination.
  more('More', ClayIcons.settings);

  const OwnerTab(this.label, this.icon);

  /// One word, sentence case, under the tab's art.
  final String label;

  /// The tab's [ClayIcons] path.
  final String icon;
}

/// The bar's tabs, in order.
const ownerTabs = OwnerTab.values;

/// How many destinations the owner's bar draws.
const ownerTabCount = 5;

/// Which tab the owner is on.
///
/// A PROVIDER, NOT THE SHELL'S OWN STATE, for the same reason the warden's is: the home screen
/// has to be able to act on a number rather than only print it. "₹33,800 still to collect" with a
/// way to the payments is a tool; the same sentence with no way anywhere is a fact. Keyed on the
/// user id like the PG switcher, so a different person signing in on this phone starts on Home.
class OwnerTabIndex extends Notifier<int> {
  @override
  int build() {
    ref.watch(sessionProvider.select((s) => s?.userId));
    return 0;
  }

  void go(OwnerTab tab) => state = tab.index;

  void select(int index) => state = index.clamp(0, ownerTabCount - 1);
}

final ownerTabProvider = NotifierProvider<OwnerTabIndex, int>(OwnerTabIndex.new);

/// "Put the cursor in the resident search" — asked by the home header's search pill, answered by
/// the People tab.
///
/// A flag rather than a callback, because the People tab may not exist yet when the pill is
/// tapped: an IndexedStack builds a tab the first time it is shown, so the screen reads this once
/// when it mounts and listens for it afterwards, and clears it when it has acted on it.
class OwnerSearchRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void consume() => state = false;
}

final ownerSearchRequestProvider =
    NotifierProvider<OwnerSearchRequest, bool>(OwnerSearchRequest.new);

/// The body for one tab, or null for a tab slot nothing has claimed.
/// The shell supplies the "not built yet" placeholder for those, so this file cannot pretend
/// to cover them.
Widget? ownerTabScreen(int index) => switch (index) {
  0 => const OwnerDashboardScreen(),
  1 => const OwnerPaymentsScreen(),
  2 => const OwnerStudentsScreen(),
  3 => const OwnerPgListScreen(),
  4 => const OwnerMoreScreen(),
  _ => null,
};

/// Hosts the owner's tab bodies for the shell, and keeps every one of them warm.
///
/// Wired in `_RoleShellState._body` as one line, the same shape as StudentSection:
///
///     if (widget.role == UserRole.owner) {
///       return OwnerSection(tabIndex: index, placeholder: ...);
///     }
///
/// TWO JOBS, BOTH IN SERVICE OF THE SAME CONTRACT — a tab tap must never show a skeleton once
/// the shell has been up for a moment (the performance contract in core/perf/tab_warmer.dart):
///
///  1. WARM-UP. `initState` starts a [TabWarmer] over the tabs the owner has not tapped yet,
///     in the bar's order, staggered so Home's own first-paint requests — stats, notices, the
///     hostel list, all dispatched during its build — win the network. Each warmer is
///     `ref.read(provider.future)` on the exact provider the tab's screen watches, under the
///     same RLS, so warming cannot widen a read. Every warmed provider calls `holdForSession`,
///     so the fetched value stays for the shell's lifetime.
///
///  2. KEEPING VISITED TABS BUILT. An [IndexedStack] over the tabs actually visited (the
///     StudentSection pattern): nothing builds before it is asked for, nothing is torn down on
///     the way out, and scroll positions survive the round trip. Unbuilt tabs get the shell's
///     placeholder only while selected and a [SizedBox.shrink] otherwise.
class OwnerSection extends ConsumerStatefulWidget {
  const OwnerSection({super.key, required this.tabIndex, required this.placeholder});

  /// Which tab the shell's bar is on.
  final int tabIndex;

  /// What to draw for a tab slot nothing has built yet. The copy belongs to role_shell.dart,
  /// which knows the tab's label; this widget only knows where to put it.
  final WidgetBuilder placeholder;

  @override
  ConsumerState<OwnerSection> createState() => _OwnerSectionState();
}

class _OwnerSectionState extends ConsumerState<OwnerSection> {
  final _visited = <int>{};
  TabWarmer? _warmer;

  @override
  void initState() {
    super.initState();
    // Home is NOT in this list: it is the first thing built, so its own requests are already on
    // the wire before the first warmer fires. Order:
    //  1. The cash-flow window — rpc_daily_finance over 30 days is the heaviest single call
    //     this role makes, and on a phone the chart sits below Home's fold, where a ListView
    //     does not build it until scrolled to. Warming it here is what makes the scroll-down
    //     land on a drawn chart instead of a skeleton, without the call ever blocking Home's
    //     first paint.
    //  2. Money — "who paid", one page of rpc_recent_payments. Home already answers HOW MUCH
    //     came in; the tab next to it answers WHO, which is the follow-up question.
    //  3. People — the roster's first page.
    //  4. Property — every owned PG's per-card stats. The active PG's stats are already in
    //     flight from Home; reading the same provider joins that request rather than
    //     repeating it.
    //  5. Staff, behind People and More — rarely opened, so it warms last, but "rarely" is
    //     exactly when it is opened in a hurry.
    _warmer = TabWarmer([_warmCashflow, _warmPayments, _warmStudents, _warmPgCards, _warmStaff])
      ..start();
  }

  @override
  void dispose() {
    _warmer?.cancel();
    super.dispose();
  }

  /// The PG the owner screens are on, waiting for the owned list if the default has not
  /// resolved yet. Errors (including a dispose mid-await) surface to the TabWarmer, which
  /// swallows them — that tab simply cold-loads, which is today's behaviour.
  Future<String?> _activeHostelId() async {
    final current = ref.read(activeHostelIdProvider);
    if (current != null) return current;
    // Resolving the owned list is what resolves the default choice.
    await ref.read(myHostelsProvider.future);
    return ref.read(activeHostelIdProvider);
  }

  Future<void> _warmCashflow() async {
    var window = ref.read(ownerFinanceWindowProvider);
    if (window == null) {
      await ref.read(myHostelsProvider.future);
      window = ref.read(ownerFinanceWindowProvider);
    }
    if (window == null) return; // No PG on the account: nothing to chart, nothing to warm.
    await ref.read(dailyFinanceProvider(window).future);
  }

  Future<void> _warmPgCards() async {
    final owned = await ref.read(myHostelsProvider.future);
    final period = ref.read(currentPeriodMonthProvider);
    // One rpc_hostel_stats per PG — the same deliberate ceiling the Property tab itself has
    // (see OwnerPgListScreen: a handful of PGs, each answer cached by its own provider).
    await Future.wait([
      for (final h in owned)
        ref.read(hostelStatsProvider(StatsQuery(hostelId: h.id, periodMonth: period)).future),
    ]);
  }

  /// The roster's FIRST page only, with no search term — the same StudentQuery the screen
  /// builds when it opens cold. A term-scoped warm would be a different family key and would
  /// warm a cache the screen never reads.
  Future<void> _warmStudents() async {
    final hostelId = await _activeHostelId();
    if (hostelId == null) return;
    await ref.read(studentsProvider(StudentQuery(hostelId: hostelId)).future);
  }

  Future<void> _warmPayments() async {
    final hostelId = await _activeHostelId();
    if (hostelId == null) return;
    await ref.read(recentPaymentsProvider(hostelId).future);
  }

  Future<void> _warmStaff() async {
    final hostelId = await _activeHostelId();
    if (hostelId == null) return;
    await ref.read(ownerStaffProvider(hostelId).future);
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.tabIndex.clamp(0, ownerTabCount - 1);
    _visited.add(index);
    // The bar animated its own indicator and the page it commands did not, which reads as
    // the two being unconnected. TabSwap keeps this ONE IndexedStack — swapping it out for
    // an AnimatedSwitcher would change its key and throw away every tab's scroll position,
    // which is the whole reason an IndexedStack is here. See shared/motion/tab_swap.dart.
    return TabSwap(
      index: index,
      child: IndexedStack(
        index: index,
        children: [for (var i = 0; i < ownerTabCount; i++) _child(context, i, index)],
      ),
    );
  }

  Widget _child(BuildContext context, int i, int selected) {
    final screen = ownerTabScreen(i);
    if (screen == null) {
      // A placeholder holds no state worth keeping, so it is only ever built while selected —
      // and built fresh each time, because its copy shows the selected tab's label.
      return i == selected ? widget.placeholder(context) : const SizedBox.shrink();
    }
    return _visited.contains(i) ? screen : const SizedBox.shrink();
  }
}
