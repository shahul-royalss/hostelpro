import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import '../../shared/glass/glass.dart';
import 'owner_format.dart';
import 'owner_insights.dart';
import 'owner_pg_detail_screen.dart';
import 'owner_providers.dart';
import 'widgets/meter.dart';
import 'widgets/owner_header.dart';
import 'widgets/states.dart' show ErrorNote, whenAsync;

/// Every PG on this owner's account, and which of them needs them today — the Property tab.
///
/// Each card opens that PG's room grid, and the floor plan is one tap further in (see
/// [OwnerPgDetailScreen]). The shell draws the forest header ("Your PGs") above it.
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
          padding: OwnerRhythm.pagePadding,
          children: const [ListSkeleton(rows: 2, semanticLabel: 'Loading your PGs')],
        ),
        error: (error) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: OwnerRhythm.pagePadding,
          children: [
            ErrorNote(error: error, onRetry: () => ref.invalidate(myHostelsProvider)),
          ],
        ),
        data: (hostels) => hostels.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: OwnerRhythm.pagePadding,
                children: const [
                  EmptyState(
                    icon: ClayIcons.rooms,
                    title: 'No PG on your account yet',
                    body: 'Apnivaas registers a PG against your account before it appears '
                        'here. Contact your account manager if you were expecting one.',
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: OwnerRhythm.pagePadding,
                children: [
                  SectionHeader(
                    title: hostels.length == 1 ? 'Registered PG' : 'Registered PGs',
                    size: SectionHeaderSize.card,
                  ),
                  const SizedBox(height: OwnerRhythm.headingGap),
                  // Two or more PGs is when "which one am I looking at" becomes a question, so
                  // that is when the answer is written down: the badge on one card, and how to
                  // move it.
                  if (hostels.length >= 2) ...[
                    const InfoNote(
                      icon: Icons.info_outline_rounded,
                      message: 'Home, Money and People show the PG marked as on your '
                          'dashboard. Change it from its name at the top of Home.',
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                  for (var i = 0; i < hostels.length; i++) ...[
                    if (i > 0) const SizedBox(height: Space.sm),
                    _PgCard(hostel: hostels[i], isActive: hostels[i].id == activeId),
                  ],
                ],
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

    // The PG card, top to bottom: the building's clay art beside its name and address with the
    // status chip opposite, then the labelled figures — beds occupied over a meter, and the
    // month's collections. The status is the one thing that differs between cards before the
    // figures arrive, so it gets the corner.
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OwnerPgDetailScreen(hostelId: hostel.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ClayIcon(ClayIcons.rooms, size: ClaySize.list),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hostel.name,
                        style: t.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Space.hair),
                    Text(
                      hostel.address ??
                          '${countLabel(hostel.totalFloors, 'floor')} · '
                              '${countLabel(hostel.totalRooms, 'room')}',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.xs),
              // EVERY card is badged, `Active` in green as readily as `Suspended` in red. Drawing
              // the chip only when something was wrong meant a healthy PG and a PG whose status
              // had not loaded looked identical. A hostel that is not 'active' is read-only or
              // suspended server-side (app.hostel_writable), and that is worth saying out loud
              // rather than letting staff find out when a write fails.
              StatusChip(
                label: hostel.status.label,
                dot: hostel.status != HostelStatus.active,
                tone: switch (hostel.status) {
                  HostelStatus.active => StatusTone.success,
                  HostelStatus.suspended => StatusTone.error,
                  _ => StatusTone.warning,
                },
              ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: Space.xs),
            const Padding(
              padding: EdgeInsetsDirectional.only(start: ClaySize.list + Space.sm),
              child: StatusChip(label: 'On your dashboard', tone: StatusTone.brand),
            ),
          ],
          const SizedBox(height: Space.sm),
          Divider(height: Strokes.hairline, color: t.dividerTheme.color),
          const SizedBox(height: Space.sm),
          whenAsync(
            stats,
            loading: () => const SkeletonPulse(
              semanticLabel: 'Loading figures',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Skeleton(widthFactor: 0.6),
                  SizedBox(height: Space.xs),
                  Skeleton(height: Space.xs),
                  SizedBox(height: Space.sm),
                  Skeleton(widthFactor: 0.7),
                ],
              ),
            ),
            error: (error) => ErrorNote(error: error, compact: true),
            data: (s) => s == null
                ? Text(
                    'No figures for this PG yet.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  )
                : _PgFigures(stats: s, period: period),
          ),
        ],
      ),
    );
  }
}

/// The design's `label ……… value` row — a caption on the left, the figure hard right.
class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value, this.emphasis = false});

  final String label;
  final String value;

  /// The card's closing figure — `Monthly Revenue` on 4:536, set a step larger than the rows
  /// above it.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // WRAP, NOT ROW, and the reason is a crore. `Row(Expanded(label), Text(value))` hands the
    // value unbounded width, so a `₹4,82,50,000` never ellipsises — it just overflows, which
    // is what this did at 1.4x on a 320dp phone. Giving the value a `Flexible` instead would
    // truncate it, and a truncated ledger figure is worse than no figure at all.
    //
    // A Wrap keeps them on one line, pushed apart, while they both fit, and drops the value
    // onto its own line when they do not — which is the same answer _MonthTotals reaches on
    // the dashboard, and it never lies about a number.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: Space.sm,
      runSpacing: Space.xxs,
      children: [
        Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: emphasis ? t.textTheme.headlineSmall : t.textTheme.titleSmall,
          maxLines: 1,
        ),
      ],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `Beds occupied ……… 42/48` over its meter. A PG with no beds set up gets
        // the sentence instead: "0/0" beside an empty bar is a drawing of a failed business,
        // where the truth is an unfinished setup.
        if (stats.totalBeds == 0)
          Text(
            occupancyCaption(stats),
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          )
        else ...[
          _StatLine(
            label: 'Beds occupied',
            value: '${stats.occupiedBeds}/${stats.totalBeds}',
          ),
          const SizedBox(height: Space.xs),
          ProportionMeter(value: stats.occupancyRate, semanticLabel: 'Beds occupied'),
        ],
        const SizedBox(height: Space.sm),
        // The closing row is the month's money. It is filled with FEE COLLECTIONS, not
        // `revenues.amount`: the two are separate ledgers (see the Revenue model), adding them
        // double-counts any PG that also books rent as revenue, and collections are what an
        // owner means by a property's month. The label says which one it is.
        _StatLine(
          label: 'Collected in ${monthNameOnly(period)}',
          value: money(stats.feesCollected),
          emphasis: true,
        ),
        if (stats.openComplaints > 0) ...[
          const SizedBox(height: Space.xs),
          Text(
            '${countLabel(stats.openComplaints, 'complaint')} still open.',
            // The resolved warning INK, never the canonical tone: the canonical amber is rated as
            // a graphic only, and this line is text.
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
