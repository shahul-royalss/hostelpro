library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
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
        actions: const [_SignOutButton()],
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

    return WardenScreen(
      title: firstName.isEmpty ? 'Today' : 'Hello, $firstName',
      subtitle: hostel?.name,
      actions: const [_SignOutButton()],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hostelStatsProvider);
          ref.invalidate(visitorsOnSiteProvider(hostelId));
          ref.invalidate(pendingLeavesProvider(hostelId));
          ref.invalidate(roomOccupancyProvider(hostelId));
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
                return Column(
                  children: [
                    if (data.subscriptionState != SubscriptionState.active)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.sm),
                        child: _SubscriptionBanner(stats: data),
                      ),
                    _Attention(hostelId: hostelId, stats: data, visitors: visitors),
                  ],
                );
              },
            ),

            const SectionLabel(label: 'Do it now'),
            _QuickActions(hostelId: hostelId),

            const SectionLabel(label: 'The building'),
            _Occupancy(hostelId: hostelId),
          ],
        ),
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
              child: _AttentionCard(
                icon: Icons.currency_rupee_rounded,
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
              child: _AttentionCard(
                icon: Icons.report_problem_rounded,
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
              child: _AttentionCard(
                icon: Icons.event_available_rounded,
                label: 'Leave requests',
                value: '${stats.pendingLeaves}',
                caption: stats.pendingLeaves == 0 ? 'Nothing to decide' : 'awaiting a decision',
                tone: stats.pendingLeaves == 0 ? NivoraColors.success : NivoraColors.warning,
                onTap: () => showLeavesSheet(context, hostelId: hostelId),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: _AttentionCard(
                icon: Icons.door_front_door_rounded,
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

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Canonical in, legible out. This figure is the loudest thing on the card.
    final accent = context.tones.resolve(tone);
    return Semantics(
      button: true,
      label: '$label: $value. $caption',
      child: Material(
        color: t.colorScheme.surface,
        borderRadius: Radii.rCard,
        child: InkWell(
          borderRadius: Radii.rCard,
          onTap: onTap,
          child: Container(
            // A MINIMUM. At 1.4x text scale the eyebrow, the figure and a two-line caption
            // come to roughly 145dp and the fixed 118 clipped the caption off the bottom.
            constraints: const BoxConstraints(minHeight: 118),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              borderRadius: Radii.rCard,
              border: Border.all(color: t.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: IconSize.sm, color: accent),
                    const SizedBox(width: Space.xxs),
                    Expanded(
                      child: Text(label.toUpperCase(), style: t.textTheme.labelSmall,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                // Spacer needs a bounded height, which a minHeight no longer gives it.
                const SizedBox(height: Space.sm),
                Text(value, style: t.textTheme.headlineMedium?.copyWith(color: accent)),
                const SizedBox(height: Space.xxs / 2),
                Text(caption, style: t.textTheme.bodySmall,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four things a warden does over and over.
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
              child: QuickAction(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Add resident',
                onTap: () => showRegisterStudentSheet(context, hostelId: hostelId),
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: QuickAction(
                icon: Icons.bed_rounded,
                label: 'Assign bed',
                onTap: () => showPlaceResidentSheet(context, ref, hostelId: hostelId),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            Expanded(
              child: QuickAction(
                icon: Icons.payments_rounded,
                label: 'Record payment',
                tone: NivoraColors.success,
                // Opens the collections list filtered to the people who still owe. A payment
                // needs a resident and a month before it needs a form, and that list is both.
                onTap: () {
                  ref.read(feeFilterProvider.notifier).set(FeeStatus.unpaid);
                  ref.read(selectedMonthProvider.notifier).reset();
                  ref.read(wardenTabProvider.notifier).go(3);
                },
              ),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: QuickAction(
                icon: Icons.task_alt_rounded,
                label: 'Resolve complaint',
                tone: NivoraColors.warning,
                onTap: () {
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
                    Text('${(ratio * 100).round()}% full', style: t.textTheme.bodySmall),
                ],
              ),
              if (ratio != null) ...[
                const SizedBox(height: Space.sm),
                ClipRRect(
                  borderRadius: Radii.rPill,
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: Space.xs,
                    // The TRACK is the free beds and the FILL is the taken ones, so the track
                    // is the one tinted green. Both alphas from the measured recipe.
                    backgroundColor: context.tones.chipFill(NivoraColors.success),
                    valueColor: AlwaysStoppedAnimation(t.colorScheme.primary),
                  ),
                ),
              ],
              const SizedBox(height: Space.xs),
              Text('${list.length} rooms · tap for the floor plan',
                  style: t.textTheme.bodySmall),
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
    final t = Theme.of(context);
    final tones = context.tones;
    final expired = stats.subscriptionState == SubscriptionState.expired;
    final tone = expired ? tones.error : tones.warning;
    final days = stats.subscriptionDaysLeft;

    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tones.chipFill(tone),
        borderRadius: Radii.rCard,
        border: Border.all(color: tones.chipBorder(tone), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(expired ? Icons.lock_outline_rounded : Icons.schedule_rounded,
              size: IconSize.md, color: tone),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expired ? 'This hostel is read-only' : 'Subscription ending',
                  style: t.textTheme.titleSmall?.copyWith(color: tone),
                ),
                Text(
                  expired
                      // days_left is returned unclamped, so a negative number is days EXPIRED
                      // and is reported as such rather than rounded up to zero.
                      ? 'The subscription lapsed${days != null && days < 0 ? ' ${-days} days ago' : ''}. '
                          'Registrations, payments and complaint updates will be refused until '
                          'the owner renews it.'
                      : 'Renewal is due${days != null ? ' in $days days' : ' soon'}. '
                          'Everything keeps working until then.',
                  style: t.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'Sign out',
      icon: const Icon(Icons.logout_rounded),
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
