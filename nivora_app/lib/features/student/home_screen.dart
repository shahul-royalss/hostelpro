library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../../shared/illustrations.dart';
import 'complaint_detail_sheet.dart';
import 'complaints_screen.dart';
import 'menu_screen.dart';
import 'notices_screen.dart';
import '../auth/verify_email_screen.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/complaint.dart';
import 'widgets/format.dart';
import 'widgets/menu.dart';
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
///   public.menus                — today's four meals, out of the week the manager writes.
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
      onRefresh: () {
        refreshStudentData(ref);
        return awaitStudentRefresh(context, ref);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Draws nothing for the many residents whose login IS their phone number — there is
          // no address on those accounts to prove. It appears only for a resident whose warden
          // collected a real email, which is then that resident's login id.
          const VerifyEmailBanner(),
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
                RentCard(periodMonth: month, row: row),
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

          // MONEY FIRST, FOOD SECOND. The menu sits BELOW the rent card and the two shortcuts
          // and above everything else: rent is why this app gets opened and must never be
          // pushed off the first screen, but "what is for dinner" is asked far more often than
          // "has my complaint moved", and it was worth the place ahead of those.
          //
          // TODAY ONLY, WITH THE WEEK ONE TAP AWAY. Seven days times four meals is twenty-eight
          // lines, which on a phone would bury the complaints and the noticeboard under a
          // fortnight of scrolling. See [StudentMenuScreen] for the full week.
          const SizedBox(height: Space.xl),
          _TodaysMenu(hostelId: me.hostelId),

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
    // The mockups' masthead is a quiet line over a loud one — "Welcome back," then the name at
    // headline-lg-mobile. Ours is the same shape with real data in both halves: the small line
    // names the hostel this account belongs to instead of a fixed pleasantry, and the big line
    // is the greeting the clock decides.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hostelName != null) ...[
          Text(hostelName!, style: t.textTheme.bodyMedium),
          const SizedBox(height: Space.xxs),
        ],
        Text('${greetingFor(DateTime.now())}, ${firstName(name)}',
            style: t.textTheme.displaySmall),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.me});
  final Student me;

  /// NEITHER OF THESE IS THE CREAM BUTTON, and neither is a hairline box any more.
  ///
  /// The cream fill is this design's one loud object — `bg-[#f5f3ee]` on `text-[#0b0d0f]`, the
  /// only maximally-bright surface in a near-black palette — and it is spent on the rent card's
  /// "Pay now" a short scroll above. "Complaint" used to be a second cream fill under it, which
  /// was two primary actions on one screen: the eye gets no answer to "what am I here to do".
  /// These two are shortcuts, not the point of the screen.
  ///
  /// They were the design's hairline outlined box (4:1587) for a while, which said "button" and
  /// nothing else. A [DomainButton] says where the button GOES: a soft fill in the destination's
  /// own colour — amber for complaints, blue for the noticeboard — with the label in that ink.
  /// It is Material's tonal weight, quieter than the cream and louder than an outline, and it is
  /// the same amber the open-complaint pill and the same blue the notices glyph already wear, so
  /// a resident who taps one lands on a screen that is recognisably the one they chose.
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DomainButton(
            domain: NivoraDomain.complaints,
            icon: Icons.add_comment_rounded,
            label: 'Complaint',
            onPressed: () => raiseComplaint(context, me),
          ),
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: DomainButton(
            domain: NivoraDomain.notices,
            icon: Icons.campaign_rounded,
            label: 'Notices',
            onPressed: () => _open(context, 'Notices', const StudentNoticesScreen()),
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

/// What is being served today, out of the one weekly read.
///
/// READS public.menus through `weeklyMenuProvider` — the SAME provider instance, with the same
/// family key, that [StudentMenuScreen] and the manager's own Menu tab watch. Today's four
/// meals are picked out of the week that is already in hand; there is no "today" query, because
/// a second query for four of twenty-eight rows this device already holds would be a round trip
/// bought with a resident's mobile data.
///
/// THREE THINGS "EMPTY" CAN MEAN HERE, AND THEY ARE NOT THE SAME SENTENCE. Nobody has planned
/// anything at all; the week is written but today is not; today is written but one of its four
/// meals is blank. The first two are said in words below and the third is [MealLine]'s job. A
/// single "no menu" for all three would tell a resident whose hostel has planned every other
/// day that their hostel does not do menus.
class _TodaysMenu extends ConsumerWidget {
  const _TodaysMenu({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = weeklyMenuProvider(hostelId);
    final menu = ref.watch(provider);
    final today = MenuDay.of(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: "Today's food",
          caption: today.label,
          // The saffron plate: the same glyph, in the same colour, that stands for the menu on
          // every screen it appears on. See [NivoraDomain].
          domain: NivoraDomain.food,
          trailing: SeeAllButton(
            label: 'Whole week',
            onPressed: () => _open(context, 'Meal menu', const StudentMenuScreen()),
          ),
        ),
        AsyncSection<WeeklyMenu>(
          value: menu,
          onRetry: () => ref.invalidate(provider),
          builder: (week) {
            if (week.plannedOn(today) == 0) {
              return EmptyNote(
                icon: Icons.restaurant_menu_rounded,
                title: week.isEmpty ? 'No menu put up yet' : 'Nothing set for today yet',
                // Both sentences are about who fills it in, because that is the only thing a
                // resident can act on: the menu is written by the manager and read-only here.
                message: week.isEmpty
                    ? 'Your hostel manager writes the week here.'
                    : 'The manager has planned other days — tap Whole week to look ahead.',
                // Not bad news, just an unwritten page — so the glyph keeps the section's own
                // saffron rather than the neutral outline a merely-empty list gets.
                tone: NivoraDomain.food.tone,
              );
            }
            // THE ONE DOMAIN-TINTED CARD ON THIS SCREEN. The rent card above carries a status
            // and keeps its status tone; this card carries none — it is simply the subject of
            // its section — so it may take the food colour on its ground. See [DayMenuCard.hero].
            return DayMenuCard(day: today, week: week, isToday: true, hero: true);
          },
        ),
      ],
    );
  }
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
          domain: NivoraDomain.complaints,
          trailing: SeeAllButton(
            onPressed: () => _open(context, 'Complaints', const StudentComplaintsScreen()),
          ),
        ),
        AsyncSection<PagedResult<Complaint>>(
          value: complaints,
          onRetry: () => ref.invalidate(complaintsProvider(query)),
          builder: (page) {
            if (page.isEmpty) {
              // The tone is passed EXPLICITLY now that [EmptyNote] no longer defaults to green.
              // This is one of the few empty states in the app where empty is genuinely good
              // news — nothing of yours is unresolved — so it earns the positive glyph. An
              // empty list that is merely empty gets the design's neutral outline instead.
              return const EmptyNote(
                icon: Icons.check_circle_outline_rounded,
                title: 'Nothing outstanding',
                message: 'Anything you raise will show its progress here.',
                tone: NivoraColors.success,
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
          domain: NivoraDomain.notices,
          trailing: SeeAllButton(
            onPressed: () => _open(context, 'Notices', const StudentNoticesScreen()),
          ),
        ),
        AsyncSection<PagedResult<Notice>>(
          value: notices,
          onRetry: () => ref.invalidate(noticesProvider(hostelId)),
          builder: (page) {
            if (page.isEmpty) {
              return const EmptyNote(
                illustration: EmptyArt.notices,
                icon: Icons.campaign_outlined,
                title: 'No notices yet',
                message: 'Announcements from the hostel owner appear here.',
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
