library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/session.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../../shared/dashboard.dart';
import '../../../shared/glass/glass.dart';
import '../../common/refresh.dart';
import '../../common/staff_notices.dart';
import '../notices/warden_notices_screen.dart';
import '../../settings/security_screen.dart';
import '../../auth/verify_email_screen.dart';
import '../actions/assign_bed_sheet.dart';
import '../actions/register_student_sheet.dart';
import '../data/warden_models.dart';
import '../data/warden_providers.dart';
import '../widgets/warden_ui.dart';
import 'desk_sheets.dart';

/// What needs doing today.
///
/// NOT A DASHBOARD. An owner wants trends; a warden wants a to-do list, and the difference
/// decides everything on this screen. There is no chart, no month-on-month comparison and no
/// percentage that cannot be acted on. Every number here is a count of things that are
/// waiting, and every one of them opens the list it counted — a figure a warden cannot tap is a
/// figure that makes them go looking.
///
/// EVERY NUMBER IS COUNTED BY POSTGRES. Four of them come from one call to rpc_hostel_stats;
/// the visitors-on-site figure comes from public.visitors because the RPC counts a different
/// thing (see below). Nothing here is derived, sampled or estimated: a hostel management app
/// that invents a figure is worse than one with a gap, because the gap is honest.
class WardenHomeScreen extends ConsumerWidget {
  const WardenHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final hostelId = ref.watch(currentHostelIdProvider);

    if (hostelId == null) {
      return WardenScreen(
        title: 'Today',
        actions: const [_SecurityButton(), _SignOutButton()],
        child: const EmptyState(
          icon: Icons.home_work_outlined,
          title: 'No hostel on this account',
          detail: 'A warden is attached to exactly one hostel. Ask the owner to check the '
              'assignment — until then there is nothing to show.',
        ),
      );
    }

    final month = ref.watch(currentPeriodMonthProvider);
    // The same family key the collections screen uses for the current month, so opening that
    // tab reuses this fetch instead of making a second one.
    final stats = ref.watch(hostelStatsProvider(
      StatsQuery(hostelId: hostelId, periodMonth: month),
    ));
    final hostel = ref.watch(hostelProvider(hostelId)).value;
    final visitors = ref.watch(visitorsOnSiteProvider(hostelId));

    final firstName = (session?.fullName ?? '').split(' ').first;

    // Read outside the AsyncSection so the banner can be hoisted out of the scroll view and
    // run full width, which is the shape `screen-subscription-expired` (4:1520) gives it: a
    // strip the page hangs from, not another card in the stack.
    final loaded = stats.value;

    return WardenScreen(
      // No eyebrow. 4:651 is one line of type — a gold dot and the page name — and the caps
      // labels this design does draw are section headings down in the body.
      title: firstName.isEmpty ? 'Today' : 'Hello, $firstName',
      subtitle: hostel?.name,
      actions: const [_SecurityButton(), _SignOutButton()],
      child: Column(
        children: [
          // Before the subscription strip. A lapsed subscription is the hostel's problem and
          // the owner's to fix; an unproved address is this warden's own and is the one of the
          // two they can act on from here.
          const VerifyEmailBanner(),
          if (loaded != null && loaded.subscriptionState != SubscriptionState.active)
            _SubscriptionBanner(stats: loaded),
          Expanded(child: _Body(hostelId: hostelId, stats: stats, visitors: visitors)),
        ],
      ),
    );
  }
}

/// The scrolling half of the dashboard.
class _Body extends ConsumerWidget {
  const _Body({required this.hostelId, required this.stats, required this.visitors});

  final String hostelId;
  final AsyncValue<HostelStats?> stats;
  final AsyncValue<List<VisitorLog>> visitors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      // The four reads are thrown away together; the WAIT is on the one this screen is named
      // for. Bounded and spoken, because AsyncSection keeps the figures already drawn through
      // a failed reload — so without this a pull that did not work looked exactly like a pull
      // that did. See features/common/refresh.dart.
      onRefresh: () {
        final stats = hostelStatsProvider(StatsQuery(
          hostelId: hostelId,
          periodMonth: ref.read(currentPeriodMonthProvider),
        ));
        ref.invalidate(hostelStatsProvider);
        ref.invalidate(visitorsOnSiteProvider(hostelId));
        ref.invalidate(pendingLeavesProvider(hostelId));
        ref.invalidate(roomOccupancyProvider(hostelId));
        return settleRefresh(context, () => ref.read(stats.future));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AsyncSection<HostelStats?>(
            value: stats,
            onRetry: () => ref.invalidate(hostelStatsProvider),
            loading: const _AttentionSkeleton(),
            builder: (data) {
              if (data == null) {
                return const EmptyState(
                  icon: Icons.query_stats_rounded,
                  title: 'No figures came back',
                  detail: 'The hostel may not be readable from this account.',
                );
              }
              return _Attention(hostelId: hostelId, stats: data, visitors: visitors);
            },
          ),

          const SectionLabel(label: 'Quick actions'),
          const DashboardBand(label: 'Tools'),
          _QuickActions(hostelId: hostelId),

          const SectionLabel(label: 'Notices'),
          _Notices(hostelId: hostelId),

          const SectionLabel(label: 'The building'),
          const DashboardBand(label: 'Occupancy'),
          _Occupancy(hostelId: hostelId),
        ],
      ),
    );
  }
}

/// The four queues, two by two.
class _Attention extends ConsumerWidget {
  const _Attention({required this.hostelId, required this.stats, required this.visitors});

  final String hostelId;
  final HostelStats stats;
  final AsyncValue<List<VisitorLog>> visitors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSite = visitors.value?.length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Rent owed',
                value: '${stats.studentsUnpaid}',
                caption: stats.studentsUnpaid == 0
                    ? 'Everyone has paid'
                    : '${money(stats.feesPending)} outstanding',
                tone: stats.studentsUnpaid == 0 ? NivoraColors.success : NivoraColors.error,
                onTap: () {
                  // Land on exactly the people this number counted.
                  ref.read(feeFilterProvider.notifier).set(FeeStatus.unpaid);
                  ref.read(wardenTabProvider.notifier).go(3);
                },
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: StatTile(
                label: 'Complaints',
                value: '${stats.openComplaints}',
                caption: stats.openComplaints == 0 ? 'All resolved' : 'not resolved yet',
                tone: stats.openComplaints == 0 ? NivoraColors.success : NivoraColors.warning,
                onTap: () {
                  ref.read(complaintFilterProvider.notifier).set(ComplaintFilter.needsAction);
                  ref.read(wardenTabProvider.notifier).go(4);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Leave requests',
                value: '${stats.pendingLeaves}',
                caption: stats.pendingLeaves == 0 ? 'Nothing to decide' : 'awaiting a decision',
                tone: stats.pendingLeaves == 0 ? NivoraColors.success : NivoraColors.warning,
                onTap: () => showLeavesSheet(context, hostelId: hostelId),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: StatTile(
                label: 'Visitors on site',
                // Two DIFFERENT figures, never conflated. `visitors_today` counts check-ins
                // against the IST calendar day whether or not the guest has left; the headline
                // here is who has not signed out. A dash until the second query lands, rather
                // than borrowing the first one's number.
                value: onSite == null ? '—' : '$onSite',
                caption: '${stats.visitorsToday} logged today',
                tone: NivoraColors.info,
                onTap: () => showVisitorsSheet(context, hostelId: hostelId),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The four things a warden does over and over.
///
/// Each is a [DomainButton] in the colour of where it GOES — teal for the resident it
/// registers, violet for the bed it assigns, green for the ledger it opens, amber for the
/// complaint queue — so the four read as four destinations rather than four hairline boxes,
/// and each matches the plate on the tab it lands on. The screen's cream [FilledButton] is not
/// spent here: none of these is the action the home screen exists for; they are shortcuts to
/// the tabs that are. See [NivoraDomain] for the rule that keeps this from becoming a rainbow.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DomainButton(
                domain: NivoraDomain.people,
                icon: Icons.person_add_alt_1_rounded,
                label: 'Add resident',
                onPressed: () => showRegisterStudentSheet(context, hostelId: hostelId),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: DomainButton(
                domain: NivoraDomain.rooms,
                icon: Icons.bed_rounded,
                label: 'Assign bed',
                onPressed: () => showPlaceResidentSheet(context, ref, hostelId: hostelId),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Expanded(
              child: DomainButton(
                domain: NivoraDomain.money,
                icon: Icons.payments_rounded,
                label: 'Record payment',
                // Opens the collections list filtered to the people who still owe. A payment
                // needs a resident and a month before it needs a form, and that list is both.
                onPressed: () {
                  ref.read(feeFilterProvider.notifier).set(FeeStatus.unpaid);
                  ref.read(selectedMonthProvider.notifier).reset();
                  ref.read(wardenTabProvider.notifier).go(3);
                },
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: DomainButton(
                domain: NivoraDomain.complaints,
                icon: Icons.task_alt_rounded,
                label: 'Resolve complaint',
                onPressed: () {
                  ref.read(complaintFilterProvider.notifier).set(ComplaintFilter.needsAction);
                  ref.read(wardenTabProvider.notifier).go(4);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Beds free, at a glance, with a way into the grid.
/// What the owner has posted to this hostel.
///
/// ── THIS SECTION IS WHY THE WARDEN NOW HAS A NOTICEBOARD AT ALL ──────────────────────────
///
/// `app.announcements_after_insert` has always written this role a `notifications` row when the
/// owner posts to `all` or to `warden` — with `link` set to `/warden` — and until this section
/// existed there was nothing behind that link. The notification was real and the destination
/// was not. Measured on the live tenant: four notices, one per audience, produced six
/// notification rows, two of them the warden's.
///
/// TWO ROWS, NOT THE PAGE. This screen is a to-do list; the whole noticeboard belongs on its
/// own screen, which [WardenNoticesScreen] is.
class _Notices extends ConsumerWidget {
  const _Notices({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(noticesProvider(hostelId));

    return AsyncSection<PagedResult<Notice>>(
      value: page,
      onRetry: () => ref.invalidate(noticesProvider(hostelId)),
      loading: const SkeletonBlock(lines: 2),
      builder: (result) {
        if (result.isEmpty) {
          // No tone: an empty noticeboard is neither good news nor bad.
          return const EmptyState(
            icon: Icons.campaign_outlined,
            title: 'No notices yet',
            detail: 'Anything the owner posts to this hostel appears here.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaffNoticeList(
              hostelId: hostelId,
              page: result,
              viewerRole: UserRole.warden,
              limit: 2,
              // Embedded in this screen's own scroll view: a nested one here would fight the
              // page for the gesture.
              scrollable: false,
            ),
            const SizedBox(height: Space.sm),
            TapRow(
              semanticLabel: 'All notices',
              onTap: () => Navigator.of(context).push(WardenNoticesScreen.route(hostelId)),
              child: Row(
                children: [
                  // The notices domain's megaphone in its blue — the plate that heads a notice
                  // on every screen — so the way to the noticeboard is recognisable before the
                  // label is read. It was a gold disc, which is the colour of the account, not
                  // of an announcement.
                  const DomainIcon(domain: NivoraDomain.notices, icon: Icons.campaign_rounded),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      'All notices',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: IconSize.md,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Occupancy extends ConsumerWidget {
  const _Occupancy({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final rooms = ref.watch(roomOccupancyProvider(hostelId));

    return AsyncSection<List<RoomOccupancy>>(
      value: rooms,
      onRetry: () => ref.invalidate(roomOccupancyProvider(hostelId)),
      loading: const SkeletonBlock(lines: 2),
      builder: (list) {
        final beds = list.fold<int>(0, (sum, r) => sum + r.capacity);
        final taken = list.fold<int>(0, (sum, r) => sum + r.occupied);
        final free = beds - taken;
        // Null rather than zero when there are no beds: "no rooms set up" and "nobody has
        // moved in" are different situations and a warden acts differently on each.
        final ratio = beds == 0 ? null : taken / beds;

        return TapRow(
          onTap: () => ref.read(wardenTabProvider.notifier).go(2),
          padding: const EdgeInsets.all(Space.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The building's own colour at the head of the tile — the violet that marks the
              // Rooms tab it opens — so "The building" is found by its plate before its label,
              // under a section heading that stays the design's caps whisper. The figures keep
              // their STATUS tones: the state lives on the pill and the meter, the domain on
              // this icon, and neither is drawn on the other's object.
              const DomainIcon(domain: NivoraDomain.rooms, icon: Icons.apartment_rounded),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            beds == 0 ? 'No beds configured' : '$free free of $beds beds',
                            style: t.textTheme.titleMedium,
                          ),
                        ),
                        if (ratio != null)
                          StatusPill.text(
                            label: '${(ratio * 100).round()}% full',
                            tone: free == 0 ? NivoraColors.error : t.colorScheme.primary,
                            dot: true,
                          ),
                      ],
                    ),
                    if (ratio != null) ...[
                      const SizedBox(height: Space.sm),
                      ClipRRect(
                        borderRadius: Radii.rPill,
                        child: LinearProgressIndicator(
                          value: ratio,
                          // The design's meter, verbatim: `w-full bg-surface-bright h-1.5
                          // rounded-full` with `bg-primary h-full rounded-full` inside it. The
                          // height is the theme's 6, which is that `h-1.5`; the track used to
                          // be a green tint, which made a full building read as an alarm.
                          backgroundColor: t.colorScheme.surfaceBright,
                          valueColor: AlwaysStoppedAnimation(t.colorScheme.primary),
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.xs),
                    Text('${list.length} rooms · tap for the floor plan',
                        style: t.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Says the subscription is in trouble BEFORE a write fails.
///
/// Hard rule §4.4: once a subscription expires, Postgres refuses every write for the hostel
/// with 42501. A warden who has typed a whole registration form and then been refused has lost
/// the work and learned nothing; a line at the top of the home screen is the difference between
/// a policy and an ambush. It does not disable anything — the server is still the one deciding.
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.stats});
  final HostelStats stats;

  @override
  Widget build(BuildContext context) {
    final expired = stats.subscriptionState == SubscriptionState.expired;
    final tone = expired ? NivoraColors.error : NivoraColors.warning;
    final days = stats.subscriptionDaysLeft;

    // NODE 4:1520, `screen-subscription-expired`: a full-bleed band at the very top of the
    // screen, filled with 10% of its tone and underlined at full strength, with an alert
    // glyph, an eyebrow in the tone and the sentence in cream. It used to be the tinted info
    // well, which is the shape this design gives an aside INSIDE a card — the wrong scope for
    // a state that applies to the whole hostel.
    return NoticeBanner(
      icon: expired ? Icons.lock_outline_rounded : Icons.schedule_rounded,
      tone: tone,
      eyebrow: expired ? 'This hostel is read-only' : 'Subscription ending',
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

/// Two-factor enrolment. Every role's header carries one — see
/// features/settings/security_screen.dart.
class _SecurityButton extends StatelessWidget {
  const _SecurityButton();

  @override
  Widget build(BuildContext context) {
    return HeaderAction(
      tooltip: 'Security',
      icon: Icons.shield_outlined,
      onPressed: () => openSecurity(context),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HeaderAction(
      tooltip: 'Sign out',
      icon: Icons.logout_rounded,
      onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
    );
  }
}

/// The four cards' own shape, before the figures arrive.
///
/// It used to be a 244dp box with a spinner in the middle of it — which is a grey void where
/// the warden already knows four cards live, and 244 was a guess that stopped being right the
/// moment anyone raised their text size. Two rows of two placeholders keep the actual layout
/// on screen and size themselves.
class _AttentionSkeleton extends StatelessWidget {
  const _AttentionSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          Row(children: [
            Expanded(child: SkeletonBlock(lines: 2)),
            SizedBox(width: Space.xs),
            Expanded(child: SkeletonBlock(lines: 2)),
          ]),
          SizedBox(height: Space.xs),
          Row(children: [
            Expanded(child: SkeletonBlock(lines: 2)),
            SizedBox(width: Space.xs),
            Expanded(child: SkeletonBlock(lines: 2)),
          ]),
        ],
      );
}
