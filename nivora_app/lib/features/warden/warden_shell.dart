library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// THE SELECTED TAB IS A PROVIDER, not local state, so the home screen's counts can open the
/// list they counted. See wardenTabProvider.
///
/// The tab labels and their ORDER match features/shell/role_shell.dart exactly. That file is
/// the place a reader looks to learn what a role's navigation is, and two files disagreeing
/// about which tab is third is a bug that only shows up as a mis-routed tap.
class WardenShell extends ConsumerWidget {
  const WardenShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final index = ref.watch(wardenTabProvider);
    final hostelId = ref.watch(currentHostelIdProvider);

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
        children: const [
          WardenHomeScreen(),
          WardenStudentsScreen(),
          WardenRoomsScreen(),
          WardenFeesScreen(),
          WardenComplaintsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(wardenTabProvider.notifier).go(i),
        // 64dp keeps every destination above the 48dp minimum with room for the label.
        height: 64,
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
