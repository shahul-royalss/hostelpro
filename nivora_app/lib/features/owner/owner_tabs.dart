library;

import 'package:flutter/widgets.dart';

import 'owner_dashboard_screen.dart';
import 'owner_pg_list_screen.dart';

/// The one thing the shell needs to know about this feature.
///
/// features/shell/role_shell.dart owns the owner's tab bar — Dashboard, PGs, Students,
/// Payments, More — and this maps the tabs that exist to their screens. It returns null for the
/// ones another feature owns, so the shell keeps drawing its "not built yet" placeholder for
/// those rather than this file pretending to cover them.
///
/// Kept as a single function on purpose: it is the entire contract between the shell and the
/// owner feature, so wiring the feature in (or out) is one line in one shared file.
Widget? ownerTabScreen(int index) => switch (index) {
      0 => const OwnerDashboardScreen(),
      1 => const OwnerPgListScreen(),
      _ => null,
    };
