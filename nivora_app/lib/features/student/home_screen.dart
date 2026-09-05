library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/dashboard.dart';
import 'complaints_screen.dart';
import 'fees_screen.dart';
import 'menu_screen.dart';
import 'notices_screen.dart';
import 'profile_screen.dart';
import '../auth/verify_email_screen.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/format.dart';
import 'widgets/menu.dart';
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
          GreetingHeader(
            name: firstName(me.fullName),
            // "Good evening · 5 Sep 2026". The reference puts the weather beside this; NIVORA
            // has none, and asking for a location permission to decorate a greeting would be a
            // poor trade. The hostel's name goes in the trailing slot instead — it is the one
            // fact that situates the reader, and it is what the old masthead showed.
            subtitle: '${greetingFor(DateTime.now())} · ${dayLabel(DateTime.now())}',
            trailing: contacts.value?.hostelName == null
                ? null
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      contacts.value!.hostelName,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
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
            loading: const SkeletonCard(lines: 4),
            // The room moved into the essentials band, so this block is the rent alone and no
            // longer needs a Column. The roommate count went with it — the band's Room tile
            // carries the room and bed, and the roommate list lives on Profile, which is the
            // screen that can show who they are rather than just how many.
            builder: (row) => RentCard(periodMonth: month, row: row),
          ),

          // ── THE ESSENTIALS BAND REPLACED FOUR STACKED SECTIONS ──────────────────────────
          //
          // This screen used to run: rent card, two shortcut buttons, today's menu, your open
          // complaints, latest notices — five full-width blocks, each with its own heading,
          // its own loading skeleton and its own error panel, all competing at the same
          // visual weight. That is the "messy" the product owner was pointing at, and the
          // reference they sent answers it the same way every good dashboard does: put the
          // NUMBERS in a compact coloured band and let a tap open the screen that has the
          // detail.
          //
          // Nothing was lost. Each tile is the entrance to the screen whose section used to
          // sit here, and every one of those screens already existed as a tab or a push page.
          // What went is the duplication of showing a resident their three most recent
          // notices on Home and then again, in full, on Notices.
          //
          // THE RENT CARD STAYS FULL WIDTH, above the band. It is not an essential among
          // others: it is the reason the app gets opened, it carries the one cream button on
          // the screen, and shrinking it into a quarter tile would bury the action this
          // product exists to make easy.
          const SizedBox(height: Space.xl),
          const DashboardBand(label: 'Essentials'),
          _Essentials(me: me, rent: rent),

          const SizedBox(height: Space.xl),
          const DashboardBand(label: 'Tools'),
          _Tools(me: me),

        ],
      ),
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

/// The four tiles a resident opens the app for, after the rent.
///
/// Each carries at most one number and is the entrance to the screen that used to occupy a
/// full-width section here. The reads are the same providers those sections used, so nothing
/// new is fetched — the difference is that a count is drawn instead of a list.
///
/// A TILE NEVER INVENTS A NUMBER IT DOES NOT HAVE. Every value below is null while its read is
/// in flight and null if the read failed, and a null value renders the compact tile: the icon
/// and the destination, without a figure. That is deliberate and it is the rule the old
/// sections followed too — a dash or a zero standing in for "we do not know yet" is the kind of
/// small lie a resident makes a decision on.
class _Essentials extends ConsumerWidget {
  const _Essentials({required this.me, required this.rent});

  final Student me;
  final AsyncValue<FeeLedgerRow?> rent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = rent.value;
    final openQuery = ComplaintQuery(hostelId: me.hostelId, openOnly: true);
    final open = ref.watch(complaintsProvider(openQuery)).value;
    final notices = ref.watch(noticesProvider(me.hostelId)).value;
    final menu = ref.watch(weeklyMenuProvider(me.hostelId)).value;
    final today = MenuDay.of(DateTime.now());

    final room = row?.roomNumber;
    final bed = row?.bedNumber;

    return EssentialsGrid(
      tiles: [
        EssentialTile(
          domain: NivoraDomain.rooms,
          icon: Icons.bed_rounded,
          title: 'Your room',
          label: room == null ? null : 'Allotted',
          value: room == null ? null : 'Room $room${bed == null ? '' : ' · Bed $bed'}',
          onTap: () => _open(context, 'Profile', const StudentProfileScreen()),
        ),
        EssentialTile(
          domain: NivoraDomain.complaints,
          icon: Icons.report_problem_rounded,
          title: 'Complaints',
          label: open == null ? null : 'Still open',
          value: open == null ? null : '${open.items.length}${open.hasMore ? '+' : ''}',
          // The dot is the one on the reference's fee tile: something here is waiting on
          // somebody. An open complaint is waiting on the warden, so it earns one.
          flagged: (open?.items.isNotEmpty ?? false),
          onTap: () => _open(context, 'Complaints', const StudentComplaintsScreen()),
        ),
        EssentialTile(
          domain: NivoraDomain.notices,
          icon: Icons.campaign_rounded,
          title: 'Notices',
          label: notices == null ? null : 'Posted',
          value: notices == null
              ? null
              : '${notices.items.length}${notices.hasMore ? '+' : ''}',
          onTap: () => _open(context, 'Notices', const StudentNoticesScreen()),
        ),
        EssentialTile(
          domain: NivoraDomain.food,
          icon: Icons.restaurant_rounded,
          title: "Today's food",
          label: menu == null ? null : _nextMeal(DateTime.now()).label,
          // ONE MEAL, NOT FOUR. A day is breakfast, lunch, snacks and dinner, and none of that
          // fits in a quarter tile — so the tile shows the meal the clock says is next, which
          // is the one a resident checking at 6pm actually wants. The full week is one tap
          // away on the menu screen, exactly as it was before.
          value: menu == null
              ? null
              : (menu.entryFor(today, _nextMeal(DateTime.now()))?.items.trim().isNotEmpty ??
                      false)
                  ? menu.entryFor(today, _nextMeal(DateTime.now()))!.items.trim()
                  : 'Not set yet',
          onTap: () => _open(context, 'Mess menu', const StudentMenuScreen()),
        ),
      ],
    );
  }
}

/// The things a resident DOES, as opposed to the things they check.
///
/// Untinted, under the coloured band, exactly as in the reference: if the tools were coloured
/// too there would be no band — just a screen of coloured boxes, which is what this rework is
/// answering.
class _Tools extends StatelessWidget {
  const _Tools({required this.me});

  final Student me;

  @override
  Widget build(BuildContext context) {
    return ToolsGrid(
      tools: [
        ToolTile(
          icon: Icons.add_comment_rounded,
          label: 'Raise a complaint',
          tone: NivoraColors.warning,
          onTap: () => raiseComplaint(context, me),
        ),
        ToolTile(
          icon: Icons.receipt_long_rounded,
          label: 'Fee history',
          tone: NivoraColors.primary,
          onTap: () => _open(context, 'Fees', const StudentFeesScreen()),
        ),
      ],
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
