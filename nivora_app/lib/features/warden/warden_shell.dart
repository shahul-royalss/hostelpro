library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/perf/tab_warmer.dart';
import '../../data/providers.dart';
import 'complaints/warden_complaints_screen.dart';
import 'data/warden_providers.dart';
import 'fees/warden_fees_screen.dart';
import 'home/warden_home_screen.dart';
import 'rooms/warden_rooms_screen.dart';
import 'students/warden_students_screen.dart';

/// The warden's five tabs.
///
/// AN IndexedStack, NOT A PageView OR A REBUILD PER TAB. Each screen keeps its scroll position,
/// its search term and its loaded pages while the warden is on another one. Coming back from
/// recording a payment to find the resident list scrolled back to A is the kind of small
/// betrayal that makes people stop using a tool — and re-fetching four pages of residents to
/// undo it costs the hostel's data allowance as well as the warden's patience.
///
/// HOME FIRST, THEN THE REST — WARMED IN THE BACKGROUND. Building all five screens in the
/// first frame fires every query in the warden app at once, and the dashboard the warden is
/// actually looking at queues behind the complaints list they are not. So only the home screen
/// is built up front; each other tab is mounted by a [TabWarmer] a beat later ([_warmOrder]),
/// or immediately on tap, whichever comes first. Mounting the screen IS the warm-up: its build
/// runs the very `ref.watch` calls a tap would have run — same providers, same family keys,
/// same RLS — so warming cannot widen a read, and a provider-list warm could never drift out
/// of sync with what the screens really watch. Once mounted a screen stays in the stack, its
/// providers hold their data for the session (see the lifetime policy in lib/data/providers.dart),
/// and a revisit renders instantly from the held value while any refresh happens behind it.
/// The result is the contract in core/perf/tab_warmer.dart: after the shell has been up for a
/// moment, tapping a tab never shows a skeleton.
///
/// THE SELECTED TAB IS A PROVIDER, not local state, so the home screen's counts can open the
/// list they counted. See wardenTabProvider.
///
/// The tab labels and their ORDER match features/shell/role_shell.dart exactly. That file is
/// the place a reader looks to learn what a role's navigation is, and two files disagreeing
/// about which tab is third is a bug that only shows up as a mis-routed tap.
class WardenShell extends ConsumerStatefulWidget {
  const WardenShell({super.key});

  @override
  ConsumerState<WardenShell> createState() => _WardenShellState();
}

class _WardenShellState extends ConsumerState<WardenShell> {
  /// Tabs whose screen has been mounted. Home always; the rest by warm-up or by tap. A tab
  /// never leaves this set while the shell lives — that is what keeps scroll positions and
  /// keeps every mounted screen's providers continuously watched.
  final _mounted = <int>{0};

  TabWarmer? _warmer;

  /// The order the warmer mounts the remaining tabs, most-tapped first: the resident roster
  /// (1) is the warden's main working list, then the two badge tabs — collections (3) and
  /// complaints (4) — whose numbers invite the tap. Rooms (2) goes last because the home
  /// screen's building section already fetched rpc_room_occupancy for the same hostel, so
  /// mounting it warms only widgets, not the network.
  static const _warmOrder = [1, 3, 4, 2];

  @override
  void initState() {
    super.initState();
    _warmer = TabWarmer([for (final tab in _warmOrder) () => _mount(tab)])..start();
  }

  @override
  void dispose() {
    _warmer?.cancel();
    super.dispose();
  }

  void _mount(int tab) {
    if (!mounted || _mounted.contains(tab)) return;
    setState(() => _mounted.add(tab));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final index = ref.watch(wardenTabProvider);
    final hostelId = ref.watch(currentHostelIdProvider);

    // A tap must never wait for the warmer: the selected tab is mounted in the same build
    // that shows it. (Before the warmer reaches a tab this is today's cold load — the warmer
    // exists to make that window a few hundred milliseconds wide instead of forever.)
    _mounted.add(index);

    // Already fetched by the home screen for the same key, so the badges cost nothing extra.
    // Null while it loads, and null is drawn as no badge rather than as a zero.
    final stats = hostelId == null
        ? null
        : ref
            .watch(hostelStatsProvider(StatsQuery(
              hostelId: hostelId,
              periodMonth: ref.watch(currentPeriodMonthProvider),
            )))
            .value;

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          const WardenHomeScreen(),
          _mounted.contains(1) ? const WardenStudentsScreen() : const SizedBox.shrink(),
          _mounted.contains(2) ? const WardenRoomsScreen() : const SizedBox.shrink(),
          _mounted.contains(3) ? const WardenFeesScreen() : const SizedBox.shrink(),
          _mounted.contains(4) ? const WardenComplaintsScreen() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(wardenTabProvider.notifier).go(i),
        // 64dp keeps every destination above the 48dp minimum with room for the label — at
        // 1.0x. NavigationBar honours this height literally, so at 1.4x the label was clipped
        // against the icon; scaling it and capping the growth keeps the bar off the content.
        height: MediaQuery.textScalerOf(context).scale(64).clamp(64.0, 88.0),
        backgroundColor: t.colorScheme.surface,
        indicatorColor: t.colorScheme.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.people_alt_rounded), label: 'Students'),
          const NavigationDestination(
              icon: Icon(Icons.meeting_room_rounded), label: 'Rooms'),
          NavigationDestination(
            icon: _Badged(
              count: stats?.studentsUnpaid,
              child: const Icon(Icons.payments_rounded),
            ),
            label: 'Payments',
          ),
          NavigationDestination(
            icon: _Badged(
              count: stats?.openComplaints,
              child: const Icon(Icons.report_problem_rounded),
            ),
            label: 'Complaints',
          ),
        ],
      ),
    );
  }
}

/// A count on a tab icon, shown only when there is something to count.
///
/// A badge reading "0" is visual noise that trains people to ignore badges; the absence of one
/// is the message. Null (still loading, or no hostel) is likewise nothing rather than a zero.
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
