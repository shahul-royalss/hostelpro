library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import 'complaint_detail_sheet.dart';
import 'complaints_screen.dart';
import 'fees_screen.dart';
import 'menu_screen.dart';
import 'notices_screen.dart';
import 'profile_screen.dart';
import '../auth/verify_email_screen.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/complaint.dart';
import 'widgets/format.dart';
import 'widgets/rent.dart';

/// Home answers one question: what do I need to know or do today?
///
/// READS
///   public.students             — own row (`myStudentProvider`), for the hostel id.
///   public.rpc_fee_ledger       — this month's rent, room and bed (`myRentThisMonthProvider`).
///   public.st_hostel_contacts() — the hostel's name.
///   public.complaints           — the resident's own, still open.
///   public.announcements        — the notices they are allowed to see.
///   public.menus                — today's four meals, out of the week the manager writes.
///
/// WHAT THIS SCREEN DELIBERATELY DOES NOT READ: `rpc_hostel_stats`. It is SECURITY INVOKER, so
/// a student CAN call it and it does answer — with occupancy, collections and subscription
/// figures computed over only the rows RLS lets them see. Nothing leaks, but the result looks
/// like a hostel dashboard and is nothing of the kind: "3 beds, 1 resident, ₹3,000 collected"
/// is one person's own room and one person's own rent wearing the clothes of a management
/// report. Verified against the live project, as a signed-in resident. Drawing it would be
/// fabricating a statistic out of a real query, which is the harder kind to notice.
///
/// ── THE SHAPE, TOP TO BOTTOM ─────────────────────────────────────────────────────────────
///
/// The rent card, then an overview of four facts, then the things a resident DOES, then what
/// has changed — the order the owner's home uses, so the two halves of the product read as one.
/// The greeting itself is the shell's: the forest header above this body already says hello by
/// name, and a second "Hi" under it was the same sentence twice.
///
/// Every section is a read this screen already made. Nothing below asks the database for
/// anything new; it draws more of what was already in hand.
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

  /// The page gutter. The overview carousel bleeds past it on purpose, so the next tile peeks
  /// in; everything else sits inside it.
  static const _gutter = EdgeInsets.symmetric(horizontal: Space.md);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final month = ref.watch(currentPeriodMonthProvider);
    final rent = ref.watch(myRentThisMonthProvider);
    final hostelName = ref.watch(hostelContactsProvider).value?.hostelName;
    // Beside the heading while both fit on one line; under it once large text would leave
    // "Overview" breaking mid-word to make room for a building's name.
    final nameBelow = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final hostel = hostelName == null
        ? null
        : Text(
            hostelName,
            textAlign: nameBelow ? TextAlign.start : TextAlign.end,
            maxLines: nameBelow ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          );

    return RefreshIndicator(
      onRefresh: () {
        refreshStudentData(ref);
        return awaitStudentRefresh(context, ref);
      },
      child: ListView(
        padding: const EdgeInsets.only(top: Space.md, bottom: Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Draws nothing for the many residents whose login IS their phone number — there is
          // no address on those accounts to prove. It appears only for a resident whose warden
          // collected a real email, which is then that resident's login id.
          const Padding(padding: _gutter, child: VerifyEmailBanner()),

          // The rent card first, always. It is the reason this app gets opened, it carries the
          // screen's one filled button, and nothing may push "still to pay" off the first view.
          //
          // ONE READ, ONE SECTION. The rent and the room both come out of the same
          // `rpc_fee_ledger` row, so one failure is one fact and gets one panel — the room tile
          // below simply carries no figure while this card says what went wrong.
          Padding(
            padding: _gutter,
            child: AsyncSection<FeeLedgerRow?>(
              value: rent,
              onRetry: () => ref.invalidate(myRentThisMonthProvider),
              loading: const SkeletonCard(lines: 4),
              builder: (row) => RentCard(periodMonth: month, row: row),
            ),
          ),

          const SizedBox(height: Space.xl),
          Padding(
            padding: _gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Overview',
                  // The one fact that situates the reader: which building this is. Quiet, and
                  // absent rather than guessed while the contact read is still out.
                  trailing: hostel == null || nameBelow
                      ? null
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: hostel,
                        ),
                ),
                if (hostel != null && nameBelow) ...[const SizedBox(height: Space.hair), hostel],
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          _Overview(me: me, rent: rent),

          const SizedBox(height: Space.xl),
          Padding(
            padding: _gutter,
            child: _QuickActions(me: me),
          ),

          _Updates(me: me),
        ],
      ),
    );
  }
}

/// Opens a tab body as a pushed page. See [StudentPushPage] for why a tile pushes rather than
/// switching tabs.
void _open(BuildContext context, String title, Widget child) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StudentPushPage(title: title, child: child),
    ),
  );
}

/// The four facts a resident opens the app for, after the rent — as the kit's stat tiles.
///
/// Each carries at most one figure and is the entrance to the screen that holds the detail.
/// The reads are the same providers those screens use, so nothing new is fetched — a count is
/// drawn instead of a list.
///
/// A TILE NEVER INVENTS A NUMBER IT DOES NOT HAVE. Every value below is null while its read is
/// in flight and null if the read failed, and a null value draws the TONAL tile — the art, the
/// destination's name and where it leads, with no figure at all. A dash or a zero standing in
/// for "we do not know yet" is the kind of small lie a resident makes a decision on.
class _Overview extends ConsumerWidget {
  const _Overview({required this.me, required this.rent});

  final Student me;
  final AsyncValue<FeeLedgerRow?> rent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = rent.value;
    final openQuery = ComplaintQuery(hostelId: me.hostelId, openOnly: true);
    final open = ref.watch(complaintsProvider(openQuery)).value;
    final notices = ref.watch(noticesProvider(me.hostelId)).value;
    final menu = ref.watch(weeklyMenuProvider(me.hostelId)).value;
    final now = DateTime.now();
    final next = _nextMeal(now);

    final room = row?.roomNumber;
    final bed = row?.bedNumber;

    void openProfile() => _open(context, 'Profile', const StudentProfileScreen());
    void openComplaints() => _open(context, 'Complaints', const StudentComplaintsScreen());
    void openNotices() => _open(context, 'Notices', const StudentNoticesScreen());
    void openMenu() => _open(context, 'Mess menu', const StudentMenuScreen());

    // ONE MEAL, NOT FOUR. A day is breakfast, lunch, snacks and dinner, and none of that fits
    // in a tile — so the tile shows the meal the clock says is next, which is the one a
    // resident checking at 6pm actually wants. The full week is one tap away.
    final dishes = menu?.entryFor(MenuDay.of(now), next)?.items.trim();

    return StatCarousel(
      children: [
        room == null
            ? StatTile(
                style: StatTileStyle.tonal,
                icon: ClayIcons.beds,
                value: 'Your room',
                label: 'Your room and roommates',
                onTap: openProfile,
              )
            : StatTile(
                icon: ClayIcons.beds,
                value: 'Room $room',
                label: 'Your room',
                caption: bed == null ? null : 'Bed $bed',
                onTap: openProfile,
              ),
        open == null
            ? StatTile(
                style: StatTileStyle.tonal,
                icon: ClayIcons.complaint,
                value: 'Complaints',
                label: 'Raise one or follow it',
                onTap: openComplaints,
              )
            : StatTile(
                icon: ClayIcons.complaint,
                value: '${open.items.length}${open.hasMore ? '+' : ''}',
                label: 'Open complaints',
                // An open complaint is waiting on the hostel, not on the resident — said so,
                // rather than tinted as if something were wrong with them.
                caption: open.items.isEmpty ? 'Nothing waiting' : 'Waiting on the hostel',
                onTap: openComplaints,
              ),
        notices == null
            ? StatTile(
                style: StatTileStyle.tonal,
                icon: ClayIcons.announcement,
                value: 'Notices',
                label: 'Read the noticeboard',
                onTap: openNotices,
              )
            : StatTile(
                icon: ClayIcons.announcement,
                value: '${notices.items.length}${notices.hasMore ? '+' : ''}',
                label: 'Notices',
                caption: notices.items.isEmpty ? 'Nothing posted yet' : 'From your hostel',
                onTap: openNotices,
              ),
        menu == null
            ? StatTile(
                style: StatTileStyle.tonal,
                icon: ClayIcons.food,
                value: "Today's food",
                label: "The week's menu",
                onTap: openMenu,
              )
            : StatTile(
                icon: ClayIcons.food,
                value: next.label,
                label: "Today's food",
                // "Not set yet" is a sentence about who fills the menu in, not a failure: a
                // hostel that has not written this meal has not written it.
                caption: dishes == null || dishes.isEmpty ? 'Not set yet' : dishes,
                onTap: openMenu,
              ),
      ],
    );
  }
}

/// The things a resident DOES, as opposed to the things they check.
///
/// Reporting a problem opens the complaint sheet straight from here — the one action on this
/// screen that is a verb rather than a place. The others are the screens a resident most often
/// goes looking for, and the week's menu is reachable from nowhere else.
///
/// "Report a problem" and not "Raise a complaint": "complaint" is the one word here that does
/// not fit a quarter of a 360dp phone at the 1.4x text the app allows, and the grid gives up a
/// column rather than break a word — short words keep all four across. The sheet it opens still
/// says what it is.
///
/// FROM 1.8x TEXT IT IS A LIST. The grid lays its tiles out icon-beside-label there, two to a
/// row or one when a word needs the width; a ListGroup is the one-a-row answer in the shape this
/// screen's other lists already have, with every label at the full width.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.me});

  final Student me;

  static const _listFrom = 1.8;

  @override
  Widget build(BuildContext context) {
    final actions = <({String icon, String label, VoidCallback onTap})>[
      (
        icon: ClayIcons.complaint,
        label: 'Report a problem',
        onTap: () => raiseComplaint(context, me),
      ),
      (
        icon: ClayIcons.receipt,
        label: 'Fee history',
        onTap: () => _open(context, 'Fees', const StudentFeesScreen()),
      ),
      (
        icon: ClayIcons.food,
        label: 'Mess menu',
        onTap: () => _open(context, 'Mess menu', const StudentMenuScreen()),
      ),
      (
        icon: ClayIcons.announcement,
        label: 'Notices',
        onTap: () => _open(context, 'Notices', const StudentNoticesScreen()),
      ),
    ];

    if (MediaQuery.textScalerOf(context).scale(1) >= _listFrom) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Quick actions'),
          const SizedBox(height: Space.sm),
          ListGroup(
            children: [
              for (final a in actions) ListRow(icon: a.icon, title: a.label, onTap: a.onTap),
            ],
          ),
        ],
      );
    }
    return QuickActionGrid(
      actions: [
        for (final a in actions) QuickActionTile(icon: a.icon, label: a.label, onTap: a.onTap),
      ],
    );
  }
}

/// What has moved since the resident last looked: their complaints still open, and the newest
/// notice.
///
/// THE SAME TWO READS THE TILES COUNT, drawn as rows — a complaint by its title with its status
/// as the first words under it, a notice by its title — and capped short on purpose. This is a
/// glance, not the list; each row opens the thing itself, and the full lists, with their status
/// chips, live behind the tiles. A chip here would take the width the complaint's own words
/// need.
///
/// NOTHING TO SAY IS SAID BY ABSENCE. A section headed "Recent updates" over an empty card
/// would be furniture; while a read is out, failed, or empty, the section is simply not drawn,
/// and the tiles above already say how many of each there are.
class _Updates extends ConsumerWidget {
  const _Updates({required this.me});

  final Student me;

  /// A glance, not a list.
  static const _maxComplaints = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openQuery = ComplaintQuery(hostelId: me.hostelId, openOnly: true);
    final open = ref.watch(complaintsProvider(openQuery)).value?.items ?? const <Complaint>[];
    final notices = ref.watch(noticesProvider(me.hostelId)).value?.items ?? const <Notice>[];
    if (open.isEmpty && notices.isEmpty) return const SizedBox.shrink();

    final latest = notices.isEmpty ? null : notices.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.xl, Space.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Recent updates'),
          const SizedBox(height: Space.sm),
          ListGroup(
            children: [
              for (final c in open.take(_maxComplaints))
                ListRow(
                  icon: complaintClay(c.category),
                  title: c.title,
                  subtitle: '${c.status.label} · raised ${relativeTime(c.createdAt)}',
                  onTap: () => showComplaintDetailSheet(context, complaint: c),
                ),
              if (latest != null)
                ListRow(
                  icon: ClayIcons.announcement,
                  title: latest.title,
                  subtitle: 'Notice · ${relativeTime(latest.createdAt)}',
                  onTap: () => _open(context, 'Notices', const StudentNoticesScreen()),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The meal a resident is most likely asking about, by the clock.
///
/// Boundaries are the ones a PG actually runs to rather than clean quarters of the day: after
/// breakfast has been served you want lunch, and from late afternoon onward the only question
/// is dinner. Past dinner it rolls to breakfast, which is correct — at 11pm the next meal IS
/// tomorrow's breakfast, and the menu screen is where a resident goes to see the rest.
Meal _nextMeal(DateTime now) {
  final h = now.hour;
  if (h < 9) return Meal.breakfast;
  if (h < 14) return Meal.lunch;
  if (h < 17) return Meal.snacks;
  return Meal.dinner;
}
