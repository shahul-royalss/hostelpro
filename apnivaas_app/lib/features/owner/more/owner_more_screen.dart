library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/clay/clay.dart';
import '../payments/upi_settings_screen.dart';
import '../../../shared/finance/expense_stats_screen.dart';
import '../../shell/staff_profile_sheet.dart';
import '../notices/owner_notices_screen.dart';
import '../owner_complaints_screen.dart';
import '../owner_pg_detail_screen.dart';
import '../owner_providers.dart';
import '../plan/plan_billing_screen.dart';
import '../../signup/owner/book_demo_screen.dart';
import '../staff/owner_staff_screen.dart';
import '../tasks/owner_tasks_screen.dart';
import '../widgets/owner_header.dart';

/// THE OWNER'S FIFTH TAB: everything that is not a daily question, grouped by what it is about.
///
/// It became a menu on 2026-09-12, when Tasks arrived beside Staff accounts. It now also holds
/// the PG's noticeboard, complaints and room grid — each one reachable from Home as well, but a
/// menu is where an owner looks when they have forgotten where something lives — and the
/// account itself, which until now was only the avatar in the header.
///
/// ONE ROW PER DESTINATION, EACH SAYING WHAT IS BEHIND IT. A menu of bare nouns makes somebody
/// tap three things to find the one they meant; the second line is what stops that — and it is
/// kept short enough to stay whole at large text, because a line that ends in "…" says nothing.
///
/// The shell draws the forest header ("More") above it.
class OwnerMoreScreen extends ConsumerWidget {
  const OwnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null while the owner's hostel list is in flight, and for an owner with no PG at all. The
    // destinations that are about one PG are disabled until there is one; the others handle it
    // themselves — each says which PG it is about.
    final hostelId = ref.watch(activeHostelIdProvider);
    void push(Route<void> route) => Navigator.of(context).push(route);

    return ListView(
      padding: OwnerRhythm.pagePadding,
      children: [
        const _Group(title: 'Your team'),
        ListGroup(
          children: [
            ListRow(
              icon: ClayIcons.team,
              title: 'Staff accounts',
              subtitle: 'Managers and wardens, each with their own login',
              onTap: () =>
                  push(MaterialPageRoute<void>(builder: (_) => const OwnerStaffScreen())),
            ),
            ListRow(
              icon: ClayIcons.tasks,
              title: 'Tasks',
              subtitle: 'Jobs for your manager, with a due date and a status',
              onTap: () => push(OwnerTasksScreen.route()),
            ),
          ],
        ),
        const SizedBox(height: OwnerRhythm.sectionGap),
        const _Group(title: 'Spending'),
        ListGroup(
          children: [
            ListRow(
              icon: ClayIcons.expense,
              title: 'Expenses month by month',
              subtitle: 'What this PG spends, beside the months before',
              onTap: () => push(ExpenseStatsScreen.route(hostelId)),
            ),
          ],
        ),
        const SizedBox(height: OwnerRhythm.sectionGap),
        const _Group(title: 'This PG'),
        ListGroup(
          children: [
            ListRow(
              icon: ClayIcons.announcement,
              title: 'Notices',
              subtitle: 'Everything posted to this PG',
              onTap: hostelId == null ? null : () => push(OwnerNoticesScreen.route(hostelId)),
              showChevron: hostelId != null,
            ),
            ListRow(
              icon: ClayIcons.complaint,
              title: 'Complaints',
              subtitle: 'What residents raised, and what happened since',
              onTap: () => push(OwnerComplaintsScreen.route()),
            ),
            ListRow(
              icon: ClayIcons.rooms,
              title: 'Rooms & beds',
              subtitle: 'Which rooms have space, and who is in each bed',
              onTap: hostelId == null
                  ? null
                  : () => push(
                        MaterialPageRoute<void>(
                          builder: (_) => OwnerPgDetailScreen(hostelId: hostelId),
                        ),
                      ),
              showChevron: hostelId != null,
            ),
          ],
        ),
        const SizedBox(height: OwnerRhythm.sectionGap),
        const _Group(title: 'Your plan'),
        ListGroup(
          children: [
            ListRow(
              icon: ClayIcons.invoice,
              title: 'Plan & billing',
              subtitle: 'Your plan, when it ends, and paying for the next one',
              onTap: hostelId == null ? null : () => push(PlanBillingScreen.route(hostelId)),
              showChevron: hostelId != null,
            ),
            ListRow(
              icon: ClayIcons.bankTransfer,
              title: 'UPI payments',
              subtitle: 'Your UPI ID for rent, and UPI payments waiting for your confirmation',
              onTap: hostelId == null ? null : () => push(UpiSettingsScreen.route(hostelId)),
              showChevron: hostelId != null,
            ),
            ListRow(
              icon: ClayIcons.calendar,
              title: 'Book a demo',
              subtitle: 'A free call to walk you through Apnivaas',
              onTap: () => push(BookDemoScreen.route()),
            ),
          ],
        ),
        const SizedBox(height: OwnerRhythm.sectionGap),
        const _Group(title: 'Account'),
        ListGroup(
          children: [
            ListRow(
              icon: ClayIcons.security,
              title: 'Your account',
              subtitle: 'Two-factor, password and sign out',
              onTap: () => showStaffProfile(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// A group's heading, with the rhythm under it every owner page uses.
class _Group extends StatelessWidget {
  const _Group({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: OwnerRhythm.headingGap),
        child: SectionHeader(title: title, size: SectionHeaderSize.card),
      );
}
