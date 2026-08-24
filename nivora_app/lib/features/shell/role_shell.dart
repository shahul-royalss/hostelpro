import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session.dart';
import '../../core/theme/tokens.dart';
import '../../shared/glass/glass.dart';

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
          Expanded(
            child: Center(
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
            ),
          ),
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
}
