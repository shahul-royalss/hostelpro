import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';
import '../warden/warden_shell.dart';
import '../owner/owner_tabs.dart';
import '../student/student_section.dart';

/// Per-role navigation. Each role gets the tabs its job needs — the brief's point that forcing
/// every role through one navigation is what makes an operational tool feel generic.
const _tabs = <UserRole, List<({String label, IconData icon})>>{
  UserRole.owner: [
    (label: 'Dashboard', icon: Icons.grid_view_rounded),
    (label: 'PGs', icon: Icons.apartment_rounded),
    (label: 'Students', icon: Icons.people_alt_rounded),
    (label: 'Payments', icon: Icons.payments_rounded),
    (label: 'More', icon: Icons.more_horiz_rounded),
  ],
  UserRole.warden: [
    (label: 'Home', icon: Icons.home_rounded),
    (label: 'Students', icon: Icons.people_alt_rounded),
    (label: 'Rooms', icon: Icons.meeting_room_rounded),
    (label: 'Payments', icon: Icons.payments_rounded),
    (label: 'Complaints', icon: Icons.report_problem_rounded),
  ],
  UserRole.student: [
    (label: 'Home', icon: Icons.home_rounded),
    (label: 'Fees', icon: Icons.receipt_long_rounded),
    (label: 'Complaints', icon: Icons.report_problem_rounded),
    (label: 'Notices', icon: Icons.campaign_rounded),
    (label: 'Profile', icon: Icons.person_rounded),
  ],
  UserRole.manager: [
    (label: 'Home', icon: Icons.home_rounded),
    (label: 'Expenses', icon: Icons.trending_down_rounded),
    (label: 'Tasks', icon: Icons.checklist_rounded),
    (label: 'Menu', icon: Icons.restaurant_rounded),
  ],
  UserRole.superAdmin: [
    (label: 'Overview', icon: Icons.grid_view_rounded),
    (label: 'Hostels', icon: Icons.apartment_rounded),
    (label: 'Subscriptions', icon: Icons.card_membership_rounded),
  ],
};

class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key, required this.role});
  final UserRole role;

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // A role whose screens are built owns its own shell: its tabs need per-screen headers,
    // badges and a selected index that other screens can move. The placeholder below stays for
    // the roles still to come, and each takes this same one-line exit as it lands. The tab list
    // in [_tabs] remains the readable index of what every role's navigation is.
    if (widget.role == UserRole.warden) return const WardenShell();

    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final tabs = _tabs[widget.role] ?? const [];

    return Scaffold(
      body: Column(
        children: [
          GlassHeader(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.role.label.toUpperCase(), style: t.textTheme.labelSmall),
                      Text(
                        session?.fullName.isNotEmpty == true ? session!.fullName : 'Nivora',
                        style: t.textTheme.titleLarge,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
          ),
          Expanded(child: _body(t, tabs)),
        ],
      ),
      bottomNavigationBar: tabs.isEmpty
          ? null
          : NavigationBar(
              selectedIndex: _index.clamp(0, tabs.length - 1),
              onDestinationSelected: (i) => setState(() => _index = i),
              // 64dp keeps every destination above the 48dp minimum with room for the label.
              height: 64,
              backgroundColor: t.colorScheme.surface,
              indicatorColor: t.colorScheme.primary.withValues(alpha: 0.12),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final tab in tabs)
                  NavigationDestination(icon: Icon(tab.icon), label: tab.label),
              ],
            ),
    );
  }

  /// The screen behind the selected tab.
  ///
  /// Each role's feature directory exposes ONE function that maps a tab index to a screen, and
  /// this is where those are plugged in. Anything a feature has not built yet returns null and
  /// falls through to the placeholder below, which says so rather than rendering an empty page
  /// that looks finished.
  Widget _body(ThemeData t, List<({String label, IconData icon})> tabs) {
    if (widget.role == UserRole.owner) {
      final screen = ownerTabScreen(_index);
      if (screen != null) return screen;
    }
    // The student app keeps its own widget rather than a per-index function: it holds the tabs
    // already visited in an IndexedStack, so moving between Home and Fees does not refetch the
    // same rent row or lose a scroll position. See StudentSection.
    if (widget.role == UserRole.student) {
      return StudentSection(tabIndex: _index);
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tabs.isEmpty ? 'No navigation for this role' : tabs[_index].label,
              style: t.textTheme.headlineMedium,
            ),
            const SizedBox(height: Space.xs),
            Text(
              'This screen is not built yet. The shell, theme, routing and\n'
              'authentication are — see the migration status in the repo.',
              style: t.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
