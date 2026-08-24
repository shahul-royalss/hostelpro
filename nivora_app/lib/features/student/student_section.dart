library;

import 'package:flutter/material.dart';

import 'complaints_screen.dart';
import 'fees_screen.dart';
import 'home_screen.dart';
import 'notices_screen.dart';
import 'profile_screen.dart';

/// The student app, as five tab bodies.
///
/// HOW THIS PLUGS INTO THE SHELL. `features/shell/role_shell.dart` owns the header, the
/// sign-out button and the `NavigationBar`, and already lists these five destinations for
/// `UserRole.student`. This file supplies the bodies and nothing else — one widget, driven by
/// the index the shell is already tracking, wired in `_RoleShellState._body`:
///
///     if (widget.role == UserRole.student) return StudentSection(tabIndex: _index);
///
/// [studentTabs] mirrors the shell's own list so the two can be checked against each other, and
/// so a sixth tab cannot be added on one side only.

/// The five destinations, in the order the shell draws them.
const studentTabs = <({String label, IconData icon})>[
  (label: 'Home', icon: Icons.home_rounded),
  (label: 'Fees', icon: Icons.receipt_long_rounded),
  (label: 'Complaints', icon: Icons.report_problem_rounded),
  (label: 'Notices', icon: Icons.campaign_rounded),
  (label: 'Profile', icon: Icons.person_rounded),
];

/// The body for one tab. Exposed separately so a screen can also be pushed on its own.
Widget studentScreenFor(int tabIndex) => switch (tabIndex) {
      0 => const StudentHomeScreen(),
      1 => const StudentFeesScreen(),
      2 => const StudentComplaintsScreen(),
      3 => const StudentNoticesScreen(),
      _ => const StudentProfileScreen(),
    };

/// Hosts the five bodies, building each one the first time it is opened and keeping it after.
///
/// WHY LAZY, AND WHY KEPT. Building all five up front would fire every query in the student app
/// on sign-in — five round trips on a resident's mobile data to render one screen. Discarding a
/// tab on the way out is the opposite mistake: several of these providers are `autoDispose`, so
/// leaving would throw the data away and coming back would refetch it, which on a slow
/// connection makes the app feel like it forgets things. An [IndexedStack] over the tabs that
/// have actually been visited gets both: nothing loads until it is asked for, and nothing is
/// reloaded once it has been. Scroll positions survive the round trip too.
class StudentSection extends StatefulWidget {
  const StudentSection({super.key, required this.tabIndex});

  final int tabIndex;

  @override
  State<StudentSection> createState() => _StudentSectionState();
}

class _StudentSectionState extends State<StudentSection> {
  final _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    final index = widget.tabIndex.clamp(0, studentTabs.length - 1);
    _visited.add(index);
    return IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < studentTabs.length; i++)
          _visited.contains(i) ? studentScreenFor(i) : const SizedBox.shrink(),
      ],
    );
  }
}
