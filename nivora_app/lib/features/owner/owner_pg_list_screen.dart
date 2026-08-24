import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'owner_format.dart';
import 'owner_insights.dart';
import 'owner_pg_detail_screen.dart';
import 'owner_providers.dart';
import 'widgets/meter.dart';
import 'widgets/states.dart';

/// Every PG on this owner's account, and which of them needs them today.
///
/// READS: hostels (owned by this user) · rpc_hostel_stats (one call per PG).
///
/// ONE STATS CALL PER PG, and that is a deliberate ceiling rather than an oversight. An owner
/// holds a handful of properties — the switcher on the dashboard would be unusable at twenty —
/// so a card that says "24 of 36 beds · ₹33,800 pending" is worth a query, and each one is
/// cached by its own provider afterwards. If this list ever grows past a handful, the right fix
/// is a set-returning RPC over the owner's hostels, not twenty parallel round trips.
class OwnerPgListScreen extends ConsumerWidget {
  const OwnerPgListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned = ref.watch(myHostelsProvider);
    final activeId = ref.watch(activeHostelIdProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myHostelsProvider);
        try {
          await ref.read(myHostelsProvider.future).timeout(ownerRefreshTimeout);
        } catch (_) {
          // Shown in the body below.
        }
      },
      child: whenAsync(
        owned,
        loading: () => ListView(
          padding: const EdgeInsets.all(Space.md),
          children: const [
            SkeletonCard(lines: 3, height: 156),
            SizedBox(height: Space.md),
            SkeletonCard(lines: 3, height: 156),
          ],
        ),
        error: (error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Space.md),
          children: [
            ErrorNote(error: error, onRetry: () => ref.invalidate(myHostelsProvider)),
          ],
        ),
        data: (hostels) => hostels.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Space.md),
                children: const [
                  EmptyNote(
                    icon: Icons.apartment_rounded,
                    title: 'No PG on your account yet',
                    message: 'Nivora registers a PG against your account before it appears '
                        'here. Contact your account manager if you were expecting one.',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
                itemCount: hostels.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                itemBuilder: (context, i) => _PgCard(
                  hostel: hostels[i],
                  isActive: hostels[i].id == activeId,
                ),
              ),
      ),
    );
  }
}

class _PgCard extends ConsumerWidget {
  const _PgCard({required this.hostel, required this.isActive});

  final Hostel hostel;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final period = ref.watch(currentPeriodMonthProvider);
    final stats = ref.watch(
      hostelStatsProvider(StatsQuery(hostelId: hostel.id, periodMonth: period)),
    );

    return Material(
      color: t.colorScheme.surface,
      borderRadius: Radii.rCard,
      child: InkWell(
        borderRadius: Radii.rCard,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OwnerPgDetailScreen(hostelId: hostel.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            borderRadius: Radii.rCard,
            border: Border.all(color: t.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hostel.name,
                            style: t.textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: Space.xxs),
                        Text(
                          hostel.address ??
                              '${countLabel(hostel.totalFloors, 'floor')} · '
                                  '${countLabel(hostel.totalRooms, 'room')}',
                          style: t.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Icon(Icons.chevron_right_rounded,
                      size: IconSize.lg, color: t.colorScheme.outline),
                ],
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.xs,
                runSpacing: Space.xxs,
                children: [
                  if (isActive)
                    StatusChip(label: 'On your dashboard', tone: t.colorScheme.primary),
                  // A hostel that is not 'active' is read-only or suspended server-side
                  // (app.hostel_writable), so the state is worth saying out loud rather than
                  // letting staff discover it when a write is refused.
                  if (hostel.status != HostelStatus.active)
                    StatusChip(
                      label: hostel.status.label,
                      tone: hostel.status == HostelStatus.suspended
                          ? NivoraColors.error
                          : NivoraColors.warning,
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              whenAsync(
                stats,
                loading: () => const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Skeleton(height: Space.xs),
                    SizedBox(height: Space.xs),
                    Skeleton(widthFactor: 0.7),
                  ],
                ),
                error: (error) => ErrorNote(error: error, compact: true),
                data: (s) => s == null
                    ? Text('No figures for this PG yet.', style: t.textTheme.bodySmall)
                    : _PgFigures(stats: s, period: period),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PgFigures extends StatelessWidget {
  const _PgFigures({required this.stats, required this.period});

  final HostelStats stats;
  final String period;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final notice = subscriptionNotice(stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProportionMeter(value: stats.occupancyRate, semanticLabel: 'Beds occupied'),
        const SizedBox(height: Space.xs),
        Text(occupancyCaption(stats), style: t.textTheme.bodySmall),
        const SizedBox(height: Space.xs),
        Text(
          '${money(stats.feesCollected)} collected in ${monthNameOnly(period)} · '
          '${collectionsCaption(stats)}',
          style: t.textTheme.bodySmall,
        ),
        if (stats.openComplaints > 0) ...[
          const SizedBox(height: Space.xxs),
          Text(
            '${countLabel(stats.openComplaints, 'complaint')} still open.',
            // Resolved: canonical #A96D08 as 13px body text on the dark elevated surface
            // measures 3.83:1, and this line is the one that says money is missing.
            style: t.textTheme.bodySmall?.copyWith(color: tones.warning),
          ),
        ],
        if (notice != null) ...[
          const SizedBox(height: Space.xxs),
          Text(
            notice.title,
            style: t.textTheme.bodySmall?.copyWith(
              color: notice.severe ? tones.error : tones.warning,
            ),
          ),
        ],
      ],
    );
  }
}
