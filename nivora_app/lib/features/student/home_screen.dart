library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'complaint_detail_sheet.dart';
import 'complaints_screen.dart';
import 'notices_screen.dart';
import 'pay_rent_sheet.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/complaint.dart';
import 'widgets/format.dart';
import 'widgets/notice.dart';
import 'widgets/rent.dart';

/// Home answers one question: what do I need to know or do today?
///
/// READS
///   public.students             — own row (`myStudentProvider`), for the name and the hostel id.
///   public.rpc_fee_ledger       — this month's rent, room and bed (`myRentThisMonthProvider`).
///   public.st_my_roommates()    — how many people share the room.
///   public.st_hostel_contacts() — the hostel's name.
///   public.complaints           — the resident's own, still open.
///   public.announcements        — the two most recent notices they are allowed to see.
///
/// WHAT THIS SCREEN DELIBERATELY DOES NOT READ: `rpc_hostel_stats`. It is SECURITY INVOKER, so
/// a student CAN call it and it does answer — with occupancy, collections and subscription
/// figures computed over only the rows RLS lets them see. Nothing leaks, but the result looks
/// like a hostel dashboard and is nothing of the kind: "3 beds, 1 resident, ₹3,000 collected"
/// is one person's own room and one person's own rent wearing the clothes of a management
/// report. Verified against the live project, as a signed-in resident. Drawing it would be
/// fabricating a statistic out of a real query, which is the harder kind to notice.
class StudentHomeScreen extends StatelessWidget {
  const StudentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResidentBuilder(builder: (context, ref, me) => _Home(me: me));
  }
}

class _Home extends ConsumerWidget {
  const _Home({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(currentPeriodMonthProvider);
    final rent = ref.watch(myRentThisMonthProvider);
    final roommates = ref.watch(roommatesProvider);
    final contacts = ref.watch(hostelContactsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        refreshStudentData(ref);
        await awaitStudentRefresh(ref);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _Greeting(name: me.fullName, hostelName: contacts.value?.hostelName),
          const SizedBox(height: Space.md),

          // The rent card first, always. It is the reason this app gets opened.
          AsyncSection<FeeLedgerRow?>(
            value: rent,
            onRetry: () => ref.invalidate(myRentThisMonthProvider),
            loading: const SkeletonCard(lines: 4),
            builder: (row) => RentCard(
              periodMonth: month,
              row: row,
              onPay: row == null
                  ? null
                  : () => showPayRentSheet(context, periodMonth: month, rent: row),
            ),
          ),

          const SizedBox(height: Space.sm),
          AsyncSection<FeeLedgerRow?>(
            value: rent,
            onRetry: () => ref.invalidate(myRentThisMonthProvider),
            loading: const SkeletonCard(lines: 1),
            builder: (row) => RoomBedCard(
              roomNumber: row?.roomNumber,
              bedNumber: row?.bedNumber,
              roommates: roommates.value?.length,
            ),
          ),

          const SizedBox(height: Space.md),
          _QuickActions(me: me),

          const SizedBox(height: Space.xl),
          _OpenComplaints(me: me),

          const SizedBox(height: Space.xl),
          _LatestNotices(hostelId: me.hostelId),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.hostelName});
  final String name;

  /// Null while the contact card is still loading. The greeting renders without it rather than
  /// holding the whole screen for one line of text.
  final String? hostelName;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${greetingFor(DateTime.now())}, ${firstName(name)}',
            style: t.textTheme.displaySmall),
        if (hostelName != null) ...[
          const SizedBox(height: Space.xxs),
          Text(hostelName!, style: t.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => raiseComplaint(context, me),
            icon: const Icon(Icons.add_comment_rounded, size: 20),
            label: const Text('Complaint'),
          ),
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _open(context, 'Notices', const StudentNoticesScreen()),
            icon: const Icon(Icons.campaign_rounded, size: 20),
            label: const Text('Notices'),
          ),
        ),
      ],
    );
  }
}

/// Opens a tab body as a pushed page. See [StudentPushPage] for why "see all" pushes rather
/// than switching tabs.
void _open(BuildContext context, String title, Widget child) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StudentPushPage(title: title, child: child),
    ),
  );
}

class _OpenComplaints extends ConsumerWidget {
  const _OpenComplaints({required this.me});
  final Student me;

  /// Two is enough to know whether anything needs chasing. The rest are one tap away.
  static const _shown = 2;

  /// How many are still open, and never a number that might be wrong.
  ///
  /// `hasMore` means the server had another page, so the count on this device is a FLOOR rather
  /// than a total. It says "20+" in that case instead of stating a figure it cannot back up.
  static String? _openCaption(PagedResult<Complaint>? page) {
    if (page == null) return null;
    if (page.hasMore) return '${page.items.length}+ still open';
    if (page.isEmpty) return 'Nothing open';
    return '${countLabel(page.items.length, 'complaint')} still open';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // openOnly narrows to what is still outstanding — the home screen is about today, and a
    // complaint that was resolved last month is history, not news.
    final query = ComplaintQuery(hostelId: me.hostelId, openOnly: true);
    final complaints = ref.watch(complaintsProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Your complaints',
          caption: _openCaption(complaints.value),
          trailing: TextButton(
            onPressed: () => _open(context, 'Complaints', const StudentComplaintsScreen()),
            child: const Text('See all'),
          ),
        ),
        AsyncSection<PagedResult<Complaint>>(
          value: complaints,
          onRetry: () => ref.invalidate(complaintsProvider(query)),
          builder: (page) {
            if (page.isEmpty) {
              return const EmptyNote(
                icon: Icons.check_circle_outline_rounded,
                title: 'Nothing outstanding',
                message: 'Anything you raise will show its progress here.',
              );
            }
            return Column(
              children: [
                for (final complaint in page.items.take(_shown)) ...[
                  ComplaintTile(
                    complaint: complaint,
                    onTap: () => showComplaintDetailSheet(context, complaint: complaint),
                  ),
                  const SizedBox(height: Space.xs),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LatestNotices extends ConsumerWidget {
  const _LatestNotices({required this.hostelId});
  final String hostelId;

  static const _shown = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider(hostelId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: 'Notices',
          caption: 'From the hostel owner.',
          trailing: TextButton(
            onPressed: () => _open(context, 'Notices', const StudentNoticesScreen()),
            child: const Text('See all'),
          ),
        ),
        AsyncSection<PagedResult<Notice>>(
          value: notices,
          onRetry: () => ref.invalidate(noticesProvider(hostelId)),
          builder: (page) {
            if (page.isEmpty) {
              return const EmptyNote(
                icon: Icons.campaign_outlined,
                title: 'No notices yet',
                message: 'Announcements from the hostel owner appear here.',
                tone: NivoraColors.textMuted,
              );
            }
            return Column(
              children: [
                for (final notice in page.items.take(_shown)) ...[
                  NoticeTile(notice: notice),
                  const SizedBox(height: Space.xs),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
