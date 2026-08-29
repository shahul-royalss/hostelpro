library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perf/tab_warmer.dart';
import '../../data/providers.dart';
import 'owner_dashboard_screen.dart';
import 'owner_pg_list_screen.dart';
import 'owner_providers.dart';
import 'staff/owner_staff_screen.dart';
import 'staff/staff_providers.dart';

/// The owner's five tab slots. features/shell/role_shell.dart owns the bar — Dashboard, PGs,
/// Students, Payments, More — and this file supplies the bodies behind it via [OwnerSection].
///
/// ── WHY STAFF IS UNDER "MORE" ────────────────────────────────────────────────────────────
///
/// The bar's five labels live in role_shell.dart and are shared with every other role, so this
/// file cannot rename one. "More" was the only tab with nothing behind it, and staff accounts
/// are the thing an owner needs least often and most urgently: it is opened when a warden
/// leaves, which is a handful of times a year and always in a hurry. Putting it behind a menu
/// with one item in it would be a speed bump on the only route to it, so More lands directly on
/// the screen for now. The moment a second thing belongs here, this becomes a small menu and
/// the index stays where it is.

/// How many destinations the owner's bar draws. Mirrors `_tabs[UserRole.owner]` in
/// role_shell.dart so the two can be checked against each other.
const ownerTabCount = 5;

/// The body for one tab, or null for a tab no feature has built yet (Students, Payments).
/// The shell supplies the "not built yet" placeholder for those, so this file cannot pretend
/// to cover them.
Widget? ownerTabScreen(int index) => switch (index) {
      0 => const OwnerDashboardScreen(),
      1 => const OwnerPgListScreen(),
      4 => const OwnerStaffScreen(),
      _ => null,
    };

/// Hosts the owner's tab bodies for the shell, and keeps every one of them warm.
///
/// Wired in `_RoleShellState._body` as one line, the same shape as StudentSection:
///
///     if (widget.role == UserRole.owner) {
///       return OwnerSection(tabIndex: _index, placeholder: ...);
///     }
///
/// TWO JOBS, BOTH IN SERVICE OF THE SAME CONTRACT — a tab tap must never show a skeleton once
/// the shell has been up for a moment (the performance contract in core/perf/tab_warmer.dart):
///
///  1. WARM-UP. `initState` starts a [TabWarmer] over the tabs the owner has not tapped yet,
///     in tap-likelihood order, staggered so the Dashboard's own first-paint requests — stats,
///     activity, the hostel list, all dispatched during its build — win the network. Each
///     warmer is `ref.read(provider.future)` on the exact provider the tab's screen watches,
///     under the same RLS, so warming cannot widen a read. Every warmed provider calls
///     `holdForSession`, so the fetched value stays for the shell's lifetime.
///
///  2. KEEPING VISITED TABS BUILT. An [IndexedStack] over the tabs actually visited (the
///     StudentSection pattern): nothing builds before it is asked for, nothing is torn down on
///     the way out, and scroll positions survive the round trip. Unbuilt tabs get the shell's
///     placeholder only while selected and a [SizedBox.shrink] otherwise.
class OwnerSection extends ConsumerStatefulWidget {
  const OwnerSection({super.key, required this.tabIndex, required this.placeholder});

  /// Which tab the shell's NavigationBar is on.
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
    // The Dashboard (home) is NOT in this list: it is the first thing built, so its own
    // requests are already on the wire before the first warmer fires. Order:
    //  1. The cash-flow window — rpc_daily_finance over 30 days is the heaviest single call
    //     this role makes, and on a phone the chart sits below the Dashboard's fold, where a
    //     ListView does not build it until scrolled to. Warming it here is what makes the
    //     scroll-down land on a drawn chart instead of a skeleton, without the call ever
    //     blocking the Dashboard's first paint.
    //  2. The PGs tab — the most likely next tap: every owned PG's per-card stats. The active
    //     PG's stats are already in flight from the Dashboard; reading the same provider joins
    //     that request rather than repeating it.
    //  3. Staff, behind More — rarely opened, so it warms last, but "rarely" is exactly when
    //     it is opened in a hurry.
    // Students and Payments have no screens yet, so there is nothing to warm for them.
    _warmer = TabWarmer([_warmCashflow, _warmPgCards, _warmStaff])..start();
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
    // One rpc_hostel_stats per PG — the same deliberate ceiling the PGs screen itself has
    // (see OwnerPgListScreen: a handful of PGs, each answer cached by its own provider).
    await Future.wait([
      for (final h in owned)
        ref.read(hostelStatsProvider(StatsQuery(hostelId: h.id, periodMonth: period)).future),
    ]);
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
    return IndexedStack(
      index: index,
      children: [for (var i = 0; i < ownerTabCount; i++) _child(context, i, index)],
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
