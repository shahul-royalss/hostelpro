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
          //
          // ONE READ, ONE SECTION, EVEN THOUGH IT DRAWS TWO CARDS. The rent and the room both
          // come out of the same `rpc_fee_ledger` row, so one failure is one fact and gets one
          // panel. Two [AsyncSection]s bound to the same [AsyncValue] used to stack the
          // identical error twice, one under the other, on the first screen a resident sees.
          AsyncSection<FeeLedgerRow?>(
            value: rent,
            onRetry: () => ref.invalidate(myRentThisMonthProvider),
            loading: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonCard(lines: 4),
                SizedBox(height: Space.sm),
                SkeletonCard(lines: 1),
              ],
            ),
            builder: (row) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RentCard(
                  periodMonth: month,
                  row: row,
                  onPay: row == null
                      ? null
                      : () => showPayRentSheet(context, periodMonth: month, rent: row),
                ),
                const SizedBox(height: Space.sm),
                RoomBedCard(
                  roomNumber: row?.roomNumber,
                  bedNumber: row?.bedNumber,
                  // The roommate count is a SEPARATE read and keeps its own states. The whole
                  // AsyncValue goes across, not `roommates.value?.length`, which collapsed
                  // "still loading" and "st_my_roommates() failed" into the same silence and so
                  // deleted the line outright when the read failed.
                  roommates: roommates,
                ),
              ],
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

  /// The hostel's name, or nothing.
  ///
  /// Null covers three things and renders identically in all of them: the contact card is still
  /// loading, the read failed, and the resident has no readable hostel record. That is a
  /// deliberate exception to the rule the rest of this screen follows, and it is safe for one
  /// reason only — a withheld subtitle states nothing, so there is no wrong action to take on
  /// it. Profile draws the same card with a real failure panel, which is where the question
  /// "why can I not see my hostel" gets answered. What this must never do is print a name it
  /// does not have.
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
            icon: const Icon(Icons.add_comment_rounded, size: IconSize.md),
            label: const Text('Complaint'),
          ),
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _open(context, 'Notices', const StudentNoticesScreen()),
            icon: const Icon(Icons.campaign_rounded, size: IconSize.md),
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
  ///
  /// SILENT UNLESS THE READ SUCCEEDED. While it is in flight there is no count to state. When
  /// it FAILED there is none either, and `.value` does not go null on a failed refresh — it
  /// keeps the last page — so reading it directly would have left "1 complaint still open"
  /// standing as a heading over the panel that says the list could not be read.
  static String? _openCaption(AsyncValue<PagedResult<Complaint>> complaints) {
    final page = complaints.hasError ? null : complaints.value;
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
          caption: _openCaption(complaints),
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
