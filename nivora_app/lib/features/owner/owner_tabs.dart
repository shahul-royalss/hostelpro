library;

import 'package:flutter/widgets.dart';

import 'owner_dashboard_screen.dart';
import 'owner_pg_list_screen.dart';
import 'staff/owner_staff_screen.dart';

/// The one thing the shell needs to know about this feature.
///
/// features/shell/role_shell.dart owns the owner's tab bar — Dashboard, PGs, Students,
/// Payments, More — and this maps the tabs that exist to their screens. It returns null for the
/// ones another feature owns, so the shell keeps drawing its "not built yet" placeholder for
/// those rather than this file pretending to cover them.
///
/// Kept as a single function on purpose: it is the entire contract between the shell and the
/// owner feature, so wiring the feature in (or out) is one line in one shared file.
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
Widget? ownerTabScreen(int index) => switch (index) {
      0 => const OwnerDashboardScreen(),
      1 => const OwnerPgListScreen(),
      4 => const OwnerStaffScreen(),
      _ => null,
    };
