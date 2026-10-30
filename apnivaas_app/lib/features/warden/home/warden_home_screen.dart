library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../data/repositories/stay_repository.dart';
import '../checkout/warden_checkouts_screen.dart';
import '../../../shared/clay/clay.dart';
import '../../../shared/motion/settle.dart';
import '../../auth/verify_email_screen.dart';
import '../../common/refresh.dart';
import '../../common/staff_hostel_switcher.dart';
import '../../common/staff_notices.dart';
import '../../shell/staff_profile_sheet.dart';
import '../../shell/join_requests.dart';
import '../../../shared/person_avatar.dart';
import '../actions/assign_bed_sheet.dart';
import '../actions/register_student_sheet.dart';
import '../data/warden_models.dart';
import '../data/warden_providers.dart';
import '../notices/warden_notices_screen.dart';
import '../widgets/warden_ui.dart';
import 'desk_sheets.dart';
import 'rent_needed.dart';
import '../../../data/repositories/tenant_admin_repository.dart' show rentlessResidentsProvider;
import '../claims/payment_claims_screen.dart';

/// What needs doing today.
///
/// NOT A DASHBOARD OF TRENDS. An owner wants trends; a warden wants a to-do list, and the
/// difference decides everything on this screen. There is no chart and no month-on-month
/// comparison. The overview says where the month stands — what has come in, what is still owed,
/// how many beds are free, who is in the building — and the list under the quick actions is the
/// work itself, each line with the one button that starts it. Every figure opens the list it
/// counted: a figure a warden cannot tap is a figure that makes them go looking.
///
/// EVERY NUMBER IS COUNTED BY POSTGRES. All but one come from one call to rpc_hostel_stats; the
/// visitors-on-site figure comes from public.visitors because the RPC counts a different thing
/// (see [_Overview]). Nothing here is derived, sampled or estimated: a hostel management app
/// that invents a figure is worse than one with a gap, because the gap is honest.
class WardenHomeScreen extends ConsumerWidget {
  const WardenHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);

    if (hostelId == null) {
      return const Column(
        children: [
          _HomeHeader(hostelId: null),
          Expanded(
            child: EmptyState(
              icon: ClayIcons.navProperty,
              title: 'No hostel on this account',
              body: 'Ask the owner to give you access to a PG. Until then there is nothing to '
                  'show.',
            ),
          ),
        ],
      );
    }

    final month = ref.watch(currentPeriodMonthProvider);
    // The same family key the collections screen uses for the current month, so opening that
    // tab reuses this fetch instead of making a second one.
    final stats = ref.watch(hostelStatsProvider(
      StatsQuery(hostelId: hostelId, periodMonth: month),
    ));
    final visitors = ref.watch(visitorsOnSiteProvider(hostelId));

    return Column(
      children: [
        // A fixed object the page passes under, not the first row of the scroll view: a
        // greeting that scrolls off the forest lands in the theme's ink on whatever is under it.
        _HomeHeader(hostelId: hostelId),
        Expanded(
          child: _Body(hostelId: hostelId, month: month, stats: stats, visitors: visitors),
        ),
      ],
    );
  }
}

/// The forest header: today's date over the greeting, the account at the leading edge, the
/// noticeboard at the trailing one, and the resident search under them all.
///
/// The PG is NOT the title here, unlike the owner's home: a warden's PG is named, with its
/// Switch PG control, by [StaffHostelBar] directly beneath — which also does the work of
/// noticing when the PG moved on another device — and saying it twice a thumb apart would be
/// the header and the card arguing about whose fact it is.
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.hostelId});

  final String? hostelId;

  /// "Saturday, 24 October". The day is what a warden's morning is organised around.
  static final _today = DateFormat('EEEE, d MMMM');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionProvider)?.fullName.trim() ?? '';
    // First name only: a full name read aloud is a database row, not a greeting.
    final first = name.split(RegExp(r'\s+')).first;
    final id = hostelId;

    return AppHeader(
      greeting: _today.format(DateTime.now()),
      title: first.isEmpty ? 'Today' : 'Hello, $first',
      // Profile, "Change photo", two-factor, Switch PG, change password and sign out.
      leading: MyHeaderAvatar(onTap: () => showStaffProfile(context)),
      actions: [
        if (id != null)
          // NO BADGE, deliberately. Nothing in the schema records which notices this warden
          // has read, so a count of "unread" would be a number this app made up.
          HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            label: 'Notices',
            onPressed: () => Navigator.of(context).push(WardenNoticesScreen.route(id)),
          ),
      ],
      bottom: id == null
          ? null
          : HeaderSearchPill(
              hint: 'Search residents by name or phone',
              onTap: () {
                ref.read(wardenSearchRequestProvider.notifier).request();
                ref.read(wardenTabProvider.notifier).go(1);
              },
            ),
    );
  }
}

/// The scrolling half of the screen.
class _Body extends ConsumerWidget {
  const _Body({
    required this.hostelId,
    required this.month,
    required this.stats,
    required this.visitors,
  });

  final String hostelId;
  final String month;
  final AsyncValue<HostelStats?> stats;
  final AsyncValue<List<VisitorLog>> visitors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = stats.value;

    return RefreshIndicator(
      // The reads are thrown away together; the WAIT is on the one this screen is named for.
      // Bounded and spoken, because the figures already drawn stay through a failed reload — so
      // without this a pull that did not work looked exactly like a pull that did. See
      // features/common/refresh.dart.
      onRefresh: () {
        final stats = hostelStatsProvider(StatsQuery(
          hostelId: hostelId,
          periodMonth: ref.read(currentPeriodMonthProvider),
        ));
        ref.invalidate(hostelStatsProvider);
        ref.invalidate(visitorsOnSiteProvider(hostelId));
        ref.invalidate(pendingLeavesProvider(hostelId));
        ref.invalidate(roomOccupancyProvider(hostelId));
        // So a PG the owner has just given this warden access to brings the Switch PG control
        // with it on a pull, rather than only after the next sign-in.
        ref.invalidate(myStaffHostelsProvider);
        ref.invalidate(rentlessResidentsProvider);
        return settleRefresh(context, () => ref.read(stats.future));
      },
      // NO HORIZONTAL PADDING ON THE LIST: the overview strip bleeds to the screen edge and
      // brings the gutter as its own padding, so every other section is wrapped in [_Gutter].
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.huge),
        children: [
          // First, and above the PG: an unproved address is this warden's own, and the one
          // thing on the screen about the ACCOUNT rather than the building.
          const _Gutter(child: VerifyEmailBanner()),
          // Which PG every figure below belongs to — and the Switch PG control, for a warden
          // with two or more.
          _Gutter(child: StaffHostelBar(hostelId: hostelId)),
          const JoinRequestsEntry(padding: EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0)),
          PaymentClaimsEntry(hostelId: hostelId, padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0)),
          RentNeededEntry(
              hostelId: hostelId, padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0)),
          if (loaded != null && loaded.subscriptionState != SubscriptionState.active)
            _Gutter(top: Space.md, child: _SubscriptionBanner(stats: loaded)),
          _Gutter(
            top: Space.xl,
            child: SectionHeader(
              title: 'Overview',
              trailing: StatusChip(label: monthLabel(month)),
            ),
          ),
          const SizedBox(height: Space.sm),
          _overview(ref),
          _Gutter(top: Space.xl, child: _QuickActions(hostelId: hostelId)),
          if (loaded != null)
            _Gutter(
              top: Space.xl,
              child: _NeedsAttention(hostelId: hostelId, stats: loaded),
            ),
          _Gutter(top: Space.xl, child: _Notices(hostelId: hostelId)),
        ],
      ),
    );
  }

  /// The overview strip in its three states. The previous figures win over a refresh in flight
  /// — a warden mid-sentence with a resident should not lose the number they are reading because
  /// the page refreshed underneath them — and [Settle] gives the change of state its arrival.
  Widget _overview(WidgetRef ref) {
    if (stats.hasValue) {
      final data = stats.requireValue;
      return Settle(
        state: 'data',
        child: data == null
            ? const _Gutter(
                child: EmptyState(
                  compact: true,
                  icon: ClayIcons.analytics,
                  title: 'No figures came back',
                  body: 'The hostel may not be readable from this account.',
                ),
              )
            : _Overview(hostelId: hostelId, month: month, stats: data, visitors: visitors),
      );
    }
    if (stats.hasError) {
      return Settle(
        state: 'error',
        child: _Gutter(
          child: FailureState(
            error: stats.error!,
            onRetry: () => ref.invalidate(hostelStatsProvider),
          ),
        ),
      );
    }
    return const Settle(
      state: 'loading',
      child: StatCarouselSkeleton(semanticLabel: 'Loading the overview'),
    );
  }
}

/// A section of the page, held off the screen edge.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.child, this.top = 0});
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(Space.md, top, Space.md, 0),
        child: child,
      );
}

/// Where the month stands, as a strip of tiles: the money in, the money owed, the beds free
/// and the people in the building.
///
/// The one forest tile is what has been COLLECTED, with the gold bar for how much of the month's
/// billing that is — the figure a warden is asked about first. Each tile opens what it counts.
class _Overview extends ConsumerWidget {
  const _Overview({
    required this.hostelId,
    required this.month,
    required this.stats,
    required this.visitors,
  });

  final String hostelId;
  final String month;
  final HostelStats stats;
  final AsyncValue<List<VisitorLog>> visitors;

  /// Opens the collections list on this month, with [filter] on — so the list the warden lands
  /// on is the list the figure counted.
  void _openLedger(WidgetRef ref, FeeStatus? filter) {
    ref.read(feeFilterProvider.notifier).set(filter);
    ref.read(selectedMonthProvider.notifier).reset();
    ref.read(wardenTabProvider.notifier).go(3);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billed = stats.feesCollected + stats.feesPending;
    // Guarded rather than assumed: a month with nothing billed divides by zero, and a bar that
    // reports 100% collected on an empty hostel is a lie.
    final share = billed <= 0 ? null : (stats.feesCollected / billed).clamp(0.0, 1.0);
    final beds = stats.totalBeds;
    final free = (beds - stats.occupiedBeds).clamp(0, beds);
    // Two DIFFERENT figures, never conflated. `visitors_today` counts check-ins against the IST
    // calendar day whether or not the guest has left; the headline is who has not signed out. A
    // dash until the second query lands, rather than borrowing the first one's number.
    final onSite = visitors.value?.length;

    return StatCarousel(
      children: [
        StatTile(
          style: StatTileStyle.hero,
          icon: ClayIcons.money,
          label: 'Collected in ${monthName(month)}',
          value: money(stats.feesCollected),
          caption: stats.feesPending > 0
              ? 'of ${money(billed)} billed · ${(share! * 100).round()}%'
              : billed > 0
                  ? 'Everyone has paid'
                  : 'Nothing billed yet',
          progress: share,
          onTap: () => _openLedger(ref, null),
        ),
        StatTile(
          icon: ClayIcons.invoice,
          label: 'Still to collect',
          value: money(stats.feesPending),
          caption: stats.studentsUnpaid == 0
              ? 'Everyone has paid'
              : 'from ${countOf(stats.studentsUnpaid, 'resident')}',
          // Red only while there is something to be red about. A settled month drawn in the
          // alarm colour teaches a warden to stop reading the colour.
          valueTone: stats.feesPending > 0 ? ApnivaasColors.error : ApnivaasColors.success,
          onTap: () => _openLedger(ref, FeeStatus.unpaid),
        ),
        StatTile(
          icon: ClayIcons.beds,
          label: 'Beds free',
          // Null rather than zero when there are no beds: "no rooms set up" and "nobody has
          // moved in" are different situations and a warden acts differently on each.
          value: beds == 0 ? '—' : '$free',
          caption: beds == 0
              ? 'No beds set up yet'
              : 'of $beds · ${(stats.occupiedBeds / beds * 100).round()}% full',
          onTap: () => ref.read(wardenTabProvider.notifier).go(2),
        ),
        StatTile(
          icon: ClayIcons.visitor,
          label: 'Visitors on site',
          value: onSite == null ? '—' : '$onSite',
          caption: '${stats.visitorsToday} logged today',
          onTap: () => showVisitorsSheet(context, hostelId: hostelId),
        ),
      ],
    );
  }
}

/// The things a warden does over and over, one tap from Home.
///
/// NOTHING HERE IS NEW POWER. Each tile opens a sheet or a tab the warden already had: the
/// registration form, the bed placement flow, the collections list filtered to the people who
/// still owe, the complaint queue, the leave and visitor desks, the noticeboard and the room
/// grid. What changed is that they are one tap away instead of two or three.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return QuickActionGrid(
      actions: [
        QuickActionTile(
          icon: ClayIcons.addTenant,
          label: 'Add resident',
          onTap: () => showRegisterStudentSheet(context, hostelId: hostelId),
        ),
        QuickActionTile(
          icon: ClayIcons.beds,
          label: 'Assign bed',
          onTap: () => showPlaceResidentSheet(context, ref, hostelId: hostelId),
        ),
        QuickActionTile(
          icon: ClayIcons.collectPayment,
          label: 'Record payment',
          // Opens the collections list filtered to the people who still owe. A payment needs a
          // resident and a month before it needs a form, and that list is both.
          onTap: () {
            ref.read(feeFilterProvider.notifier).set(FeeStatus.unpaid);
            ref.read(selectedMonthProvider.notifier).reset();
            ref.read(wardenTabProvider.notifier).go(3);
          },
        ),
        QuickActionTile(
          icon: ClayIcons.complaint,
          label: 'Resolve complaint',
          onTap: () {
            ref.read(complaintFilterProvider.notifier).set(ComplaintFilter.needsAction);
            ref.read(wardenTabProvider.notifier).go(4);
          },
        ),
        QuickActionTile(
          icon: ClayIcons.leave,
          label: 'Leave requests',
          onTap: () => showLeavesSheet(context, hostelId: hostelId),
        ),
        QuickActionTile(
          icon: ClayIcons.visitor,
          label: 'Visitors',
          onTap: () => showVisitorsSheet(context, hostelId: hostelId),
        ),
        QuickActionTile(
          icon: ClayIcons.announcement,
          label: 'Notices',
          onTap: () => Navigator.of(context).push(WardenNoticesScreen.route(hostelId)),
        ),
        QuickActionTile(
          icon: ClayIcons.rooms,
          label: 'Rooms & beds',
          onTap: () => ref.read(wardenTabProvider.notifier).go(2),
        ),
      ],
    );
  }
}

/// The work waiting on the warden, each line with the one button that starts it.
///
/// The counts are the overview's own call, so a line here and a tile above can never disagree.
/// A queue with nothing in it is simply not listed; only when ALL of them are empty does the
/// section say so — "Nothing is waiting on you" is a claim about the whole desk, and printing it
/// while the tiles show money owed would be a lie.
class _NeedsAttention extends ConsumerWidget {
  const _NeedsAttention({required this.hostelId, required this.stats});

  final String hostelId;
  final HostelStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unpaid = stats.studentsUnpaid;
    final complaints = stats.openComplaints;
    final leaves = stats.pendingLeaves;
    final checkouts = ref.watch(pendingCheckoutCountProvider) ?? 0;

    final rows = <Widget>[
      if (unpaid > 0)
        ListRow(
          icon: ClayIcons.rentReminder,
          title: '${countOf(unpaid, 'resident')} ${unpaid == 1 ? 'owes' : 'owe'} rent',
          subtitle: '${money(stats.feesPending)} outstanding this month',
          trailing: PillButton(
            label: 'Collect',
            semanticLabel: 'Collect rent from the residents who owe',
            onPressed: () {
              // Land on exactly the people this line counted.
              ref.read(feeFilterProvider.notifier).set(FeeStatus.unpaid);
              ref.read(selectedMonthProvider.notifier).reset();
              ref.read(wardenTabProvider.notifier).go(3);
            },
          ),
        ),
      if (complaints > 0)
        ListRow(
          icon: ClayIcons.complaint,
          title: '${countOf(complaints, 'complaint')} open',
          // rpc_hostel_stats counts open AND in progress, which is exactly the queue's
          // "needs action" filter — the list the button opens.
          subtitle: 'Open or in progress, not resolved yet',
          trailing: PillButton(
            label: 'Resolve',
            semanticLabel: 'Open the complaints that need action',
            onPressed: () {
              ref.read(complaintFilterProvider.notifier).set(ComplaintFilter.needsAction);
              ref.read(wardenTabProvider.notifier).go(4);
            },
          ),
        ),
      if (leaves > 0)
        ListRow(
          icon: ClayIcons.leave,
          title: countOf(leaves, 'leave request'),
          subtitle: 'Waiting for your decision',
          trailing: PillButton(
            label: 'Review',
            semanticLabel: 'Review the leave requests',
            onPressed: () => showLeavesSheet(context, hostelId: hostelId),
          ),
        ),
      if (checkouts > 0)
        ListRow(
          icon: ClayIcons.moveOut,
          title: countOf(checkouts, 'check-out request'),
          subtitle: 'Residents asking to leave',
          trailing: PillButton(
            label: 'Review',
            semanticLabel: 'Review the check-out requests',
            onPressed: () => Navigator.of(context).push(CheckoutRequestsScreen.route(hostelId)),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Needs your attention', size: SectionHeaderSize.card),
        const SizedBox(height: Space.sm),
        if (rows.isEmpty)
          const EmptyState(
            compact: true,
            icon: ClayIcons.success,
            title: 'Nothing is waiting on you',
            body: 'Everyone has paid, no complaint is open and no leave is waiting.',
          )
        else
          ListGroup(children: rows),
      ],
    );
  }
}

/// What the owner has posted to this hostel.
///
/// ── THIS SECTION IS WHY THE WARDEN HAS A NOTICEBOARD AT ALL ─────────────────────────────
///
/// `app.announcements_after_insert` has always written this role a `notifications` row when the
/// owner posts to `all` or to `warden` — with `link` set to `/warden` — and until this section
/// existed there was nothing behind that link. The notification was real and the destination
/// was not.
///
/// TWO NOTICES, NOT THE BOARD. This screen is a to-do list; the whole noticeboard belongs on its
/// own screen, which [WardenNoticesScreen] is, behind "View all".
class _Notices extends ConsumerWidget {
  const _Notices({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(noticesProvider(hostelId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Notices',
          size: SectionHeaderSize.card,
          actionLabel: 'View all',
          onAction: () => Navigator.of(context).push(WardenNoticesScreen.route(hostelId)),
        ),
        const SizedBox(height: Space.xs),
        AsyncSection<PagedResult<Notice>>(
          value: page,
          onRetry: () => ref.invalidate(noticesProvider(hostelId)),
          loading: const ListSkeleton(rows: 2, semanticLabel: 'Loading notices'),
          builder: (result) {
            if (result.isEmpty) {
              return const EmptyState(
                compact: true,
                icon: ClayIcons.announcement,
                title: 'No notices yet',
                body: 'Anything the owner posts to this hostel appears here.',
              );
            }
            return StaffNoticeList(
              hostelId: hostelId,
              page: result,
              viewerRole: UserRole.warden,
              limit: 2,
              // Embedded in this screen's own scroll view: a nested one here would fight the
              // page for the gesture.
              scrollable: false,
            );
          },
        ),
      ],
    );
  }
}

/// Says the subscription is in trouble BEFORE a write fails.
///
/// Hard rule §4.4: once a subscription expires, Postgres refuses every write for the hostel
/// with 42501. A warden who has typed a whole registration form and then been refused has lost
/// the work and learned nothing; a banner at the top of the home screen is the difference
/// between a policy and an ambush. It does not disable anything — the server is still the one
/// deciding — and it carries no button, because renewing is the owner's call, not a control in
/// this app.
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.stats});
  final HostelStats stats;

  @override
  Widget build(BuildContext context) {
    final expired = stats.subscriptionState == SubscriptionState.expired;
    final days = stats.subscriptionDaysLeft;

    // The screen's one gold task banner: it is the deadline on this PG.
    return ActionBanner(
      icon: expired ? ClayIcons.security : ClayIcons.calendar,
      title: expired ? 'This hostel is read-only' : 'Subscription ending',
      message: expired
          // days_left is returned unclamped, so a negative number is days EXPIRED and is
          // reported as such rather than rounded up to zero.
          ? 'The subscription lapsed${days != null && days < 0 ? ' ${-days} days ago' : ''}. '
              'Registrations, payments and complaint updates will be refused until '
              'the owner renews it.'
          : 'Renewal is due${days != null ? ' in $days days' : ' soon'}. '
              'Everything keeps working until then.',
    );
  }
}
