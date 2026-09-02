import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
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
                // One extra leading item: the design's `REGISTERED HOSTELS` section label.
                itemCount: hostels.length + 1,
                // The section label carries its own trailing space; adding the card gutter on
                // top of it would put 24dp under a 12px label.
                separatorBuilder: (_, i) =>
                    SizedBox(height: i == 0 ? 0 : Space.sm),
                itemBuilder: (context, i) => i == 0
                    ? const SectionLabel(label: 'Registered hostels')
                    : _PgCard(
                        hostel: hostels[i - 1],
                        isActive: hostels[i - 1].id == activeId,
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

    // Figma 4:536's own hostel card, top to bottom: the name with its status badge opposite,
    // the address under it, then the labelled figures — a `Beds Occupied  42/48` row over a
    // meter, and `Monthly Revenue` opposite its amount.
    //
    // THE ICON BADGE THAT USED TO LEAD THIS ROW IS GONE. Every card in the list carried the
    // same `apartment` glyph, which is a picture of the word "hostel" on a screen headed
    // REGISTERED HOSTELS. The mockup gives the slot to the status badge instead, which is the
    // one thing that differs between the cards.
    return GlassCard(
      padding: const EdgeInsets.all(Space.sm),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hostel.name,
                        style: t.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Space.xxs / 2),
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
              // 4:536 badges EVERY card, `ACTIVE` in green as readily as `SUSPENDED` in red.
              // This used to draw the chip only when something was wrong, which meant a healthy
              // PG and a PG whose status had not loaded looked identical. A hostel that is not
              // 'active' is read-only or suspended server-side (app.hostel_writable), and that
              // is worth saying out loud rather than letting staff find out when a write fails.
              StatusChip(
                label: hostel.status.label,
                dot: hostel.status != HostelStatus.active,
                tone: switch (hostel.status) {
                  HostelStatus.active => NivoraColors.success,
                  HostelStatus.suspended => NivoraColors.error,
                  _ => NivoraColors.warning,
                },
              ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: Space.xs),
            StatusChip(label: 'On your dashboard', tone: t.colorScheme.primary),
          ],
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
        Text(label, style: t.textTheme.bodySmall),
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
        // The mockup's `Beds Occupied ……… 42/48` over its meter. A PG with no beds set up gets
        // the sentence instead: "0/0" beside an empty bar is a drawing of a failed business,
        // where the truth is an unfinished setup.
        if (stats.totalBeds == 0)
          Text(occupancyCaption(stats), style: t.textTheme.bodySmall)
        else ...[
          _StatLine(
            label: 'Beds occupied',
            value: '${stats.occupiedBeds}/${stats.totalBeds}',
          ),
          const SizedBox(height: Space.xs),
          ProportionMeter(value: stats.occupancyRate, semanticLabel: 'Beds occupied'),
        ],
        const SizedBox(height: Space.sm),
        // 4:536's closing row is `Monthly Revenue`. It is filled with FEE COLLECTIONS, not
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
