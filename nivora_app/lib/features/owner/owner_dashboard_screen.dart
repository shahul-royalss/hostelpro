import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import 'owner_format.dart';
import 'owner_insights.dart';
import 'owner_pg_detail_screen.dart';
import 'owner_providers.dart';
import 'widgets/cashflow_chart.dart';
import 'widgets/meter.dart';
import 'widgets/states.dart';

/// "How is my PG business performing?" — answered in the order an owner asks it.
///
/// THE HIERARCHY IS THE DESIGN. One figure is large: the money collected this month. Everything
/// else is subordinate to it, because a screen where twenty numbers are the same size is a
/// screen with no answer on it — the reader has to do the ranking the designer refused to do.
///
/// EVERY NUMBER HERE IS COUNTED BY POSTGRES. rpc_hostel_stats returns all of them in one query
/// (db/schema.sql), and rpc_daily_finance returns the chart series zero-filled. Nothing on this
/// screen is derived from a page of rows that happened to be in memory, and nothing is
/// estimated: if a figure is not in the database it is not on the screen.
///
/// READS: rpc_hostel_stats · rpc_daily_finance · complaints · announcements · hostels.
class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(activeHostelIdProvider);
    final owned = ref.watch(myHostelsProvider);

    // No hostel resolved yet. Which of the three reasons it is matters: still loading, the
    // query failed, or this owner genuinely has no PG on the platform — and the last one is
    // not an error, it is a state the Super Admin has to resolve.
    if (hostelId == null) {
      return switch (owned) {
        AsyncError(:final error) => _FullPage(
            child: ErrorNote(error: error, onRetry: () => ref.invalidate(myHostelsProvider)),
          ),
        AsyncData() => const _FullPage(
            child: EmptyNote(
              icon: Icons.apartment_rounded,
              title: 'No PG on your account yet',
              message: 'Nivora sets up a PG against your account before it appears here. '
                  'Contact your account manager if you were expecting one.',
            ),
          ),
        _ => const _FullPage(child: _DashboardSkeleton()),
      };
    }

    final period = ref.watch(currentPeriodMonthProvider);
    final statsQuery = StatsQuery(hostelId: hostelId, periodMonth: period);
    final stats = ref.watch(hostelStatsProvider(statsQuery));

    return RefreshIndicator(
      onRefresh: () async {
        refreshOwnerDashboard(ref, hostelId: hostelId, period: period);
        try {
          // Hold the spinner until the headline figures are actually back, so letting go does
          // not immediately look finished while the numbers are still the old ones. BOUNDED,
          // because riverpod retries a failed provider on its own: `.future` would not complete
          // until one of those retries succeeded, and the spinner would turn all afternoon.
          await ref
              .read(hostelStatsProvider(statsQuery).future)
              .timeout(ownerRefreshTimeout);
        } catch (_) {
          // The error is already rendered by the section below; rethrowing here would only
          // turn a handled failure into an unhandled one.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
        children: [
          const _Greeting(),
          const SizedBox(height: Space.lg),
          whenAsync(
            stats,
            loading: () => const _DashboardSkeleton(),
            error: (error) => ErrorNote(
              error: error,
              onRetry: () => ref.invalidate(hostelStatsProvider(statsQuery)),
            ),
            data: (s) => s == null
                ? const EmptyNote(
                    icon: Icons.query_stats_rounded,
                    title: 'No figures for this PG',
                    message: 'The dashboard query came back empty. That normally means the PG '
                        'was created moments ago and has nothing in it yet.',
                  )
                : _Figures(stats: s, hostelId: hostelId, period: period),
          ),
          const SizedBox(height: Space.xl),
          _CashflowSection(hostelId: hostelId, period: period, stats: stats.value),
          const SizedBox(height: Space.xl),
          _ActivitySection(hostelId: hostelId),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${greetingFor(DateTime.now())}, ${firstName(session?.fullName)}',
          style: t.textTheme.titleLarge,
        ),
        const SizedBox(height: Space.xs),
        const _HostelSwitcher(),
      ],
    );
  }
}

/// Which PG the figures below belong to — and, for an owner with more than one, how to change
/// it. A single-PG owner gets a line of text, not a menu with one item in it.
class _HostelSwitcher extends ConsumerWidget {
  const _HostelSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final activeId = ref.watch(activeHostelIdProvider);
    final owned = ref.watch(myHostelsProvider);

    final list = owned.value;
    if (list == null) return const Skeleton(width: 160, height: 16);

    Hostel? active;
    for (final h in list) {
      if (h.id == activeId) active = h;
    }
    // An owner whose users.hostel_id points at a PG they do not own can still read it
    // (app.can_read_hostel admits staff of a hostel), so the name comes from the hostel row
    // itself in that case rather than from the ownership list.
    final fallbackName = active == null && activeId != null
        ? ref.watch(hostelProvider(activeId)).value?.name
        : null;
    final name = active?.name ?? fallbackName ?? 'This PG';

    if (list.length < 2) {
      return Row(
        children: [
          Icon(Icons.apartment_rounded, size: IconSize.sm, color: t.colorScheme.primary),
          const SizedBox(width: Space.xxs),
          Flexible(
            child: Text(name,
                style: t.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        borderRadius: Radii.rControl,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: () => _pick(context, ref, list, activeId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            decoration: BoxDecoration(
              borderRadius: Radii.rControl,
              border: Border.all(color: t.colorScheme.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.apartment_rounded, size: IconSize.sm, color: t.colorScheme.primary),
                const SizedBox(width: Space.xs),
                // Flexible, not a 200dp cap: at 1.4x scale a capped 200 still overflowed a
                // 320dp header, because the cap bounds the text and not the row.
                Flexible(
                  child: Text(name,
                      style: t.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Space.xxs),
                const Icon(Icons.expand_more_rounded, size: IconSize.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    List<Hostel> hostels,
    String? activeId,
  ) async {
    final chosen = await showGlassSheet<String>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your PGs', style: t.textTheme.titleLarge),
            const SizedBox(height: Space.sm),
            for (final h in hostels)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  h.id == activeId
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: h.id == activeId ? t.colorScheme.primary : t.colorScheme.outline,
                ),
                title: Text(h.name, style: t.textTheme.titleMedium),
                subtitle: Text(
                  h.address ?? '${h.totalRooms} rooms · ${h.totalFloors} floors',
                  style: t.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(ctx).pop(h.id),
              ),
          ],
        );
      },
    );
    if (chosen != null) {
      ref.read(selectedHostelIdProvider.notifier).select(chosen);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THE FIGURES
// ─────────────────────────────────────────────────────────────────────────────

class _Figures extends StatelessWidget {
  const _Figures({required this.stats, required this.hostelId, required this.period});

  final HostelStats stats;
  final String hostelId;
  final String period;

  @override
  Widget build(BuildContext context) {
    final notice = subscriptionNotice(stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          _SubscriptionBanner(notice: notice),
          const SizedBox(height: Space.md),
        ],
        _CollectionsHero(stats: stats, period: period),
        const SizedBox(height: Space.md),
        _OccupancyCard(stats: stats, hostelId: hostelId),
        const SizedBox(height: Space.md),
        _AttentionCard(stats: stats),
      ],
    );
  }
}

/// The subscription state, said plainly. Renewal is a Super Admin write (rls-policies.sql), so
/// this deliberately offers no button — a call to action that cannot act is worse than a fact.
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.notice});
  final ({String title, String detail, bool severe}) notice;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tones = context.tones;
    final tone = notice.severe ? tones.error : tones.warning;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: Radii.rCard,
        color: tones.chipFill(tone),
        border: Border.all(color: tones.chipBorder(tone), width: Strokes.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notice.severe ? Icons.lock_clock_rounded : Icons.schedule_rounded,
            size: IconSize.md,
            color: tone,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notice.title, style: t.textTheme.titleMedium),
                const SizedBox(height: Space.xxs),
                Text(notice.detail, style: t.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// THE hero. One figure, at a size nothing else on the screen competes with.
class _CollectionsHero extends StatelessWidget {
  const _CollectionsHero({required this.stats, required this.period});

  final HostelStats stats;
  final String period;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final billedTo = stats.studentsPaid + stats.studentsUnpaid;
    return GlassSurface(
      weight: GlassWeight.thin,
      padding: const EdgeInsets.all(Space.lg),
      semanticLabel: 'Collected in ${monthNameOnly(period)}: ${money(stats.feesCollected)}. '
          '${collectionsCaption(stats)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('COLLECTED IN ${monthNameOnly(period).toUpperCase()}',
              style: t.textTheme.labelSmall),
          const SizedBox(height: Space.xs),
          Text(money(stats.feesCollected), style: t.textTheme.headlineLarge),
          const SizedBox(height: Space.md),
          ProportionMeter(
            value: collectedShare(stats),
            tone: NivoraColors.success,
            semanticLabel: 'Share of this month\'s fees collected',
          ),
          const SizedBox(height: Space.sm),
          Text(collectionsCaption(stats), style: t.textTheme.bodyMedium),
          if (billedTo > 0) ...[
            const SizedBox(height: Space.xxs),
            Text('${stats.studentsPaid} of $billedTo residents have paid in full.',
                style: t.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Occupancy, with the sentence that makes it mean something. Tapping opens the room grid,
/// because "12 beds vacant" is a number whose next question is always "which ones?".
class _OccupancyCard extends StatelessWidget {
  const _OccupancyCard({required this.stats, required this.hostelId});

  final HostelStats stats;
  final String hostelId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final rate = stats.occupancyRate;
    return _PlainCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OwnerPgDetailScreen(hostelId: hostelId),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('OCCUPANCY', style: t.textTheme.labelSmall)),
              Icon(Icons.chevron_right_rounded,
                  size: IconSize.md, color: t.colorScheme.outline),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(occupancyHeadline(stats), style: t.textTheme.headlineMedium),
          const SizedBox(height: Space.sm),
          ProportionMeter(value: rate, semanticLabel: 'Beds occupied'),
          const SizedBox(height: Space.xs),
          Text(occupancyCaption(stats), style: t.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// The list of things actually outstanding — and nothing else. See [attentionItems]: zeroes are
/// omitted rather than drawn, so an empty card genuinely means a clear morning.
class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.stats});
  final HostelStats stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = attentionItems(stats);
    return _PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEEDS YOU', style: t.textTheme.labelSmall),
          if (items.isEmpty)
            const EmptyNote(
              icon: Icons.check_circle_outline_rounded,
              title: 'Nothing is waiting on you',
              message: 'Every resident has paid, no complaints are open and no tasks are due.',
              compact: true,
              tone: NivoraColors.success,
            )
          else
            for (final item in items) ...[
              const SizedBox(height: Space.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_icon(item.kind),
                      size: IconSize.md, color: context.tones.resolve(_tone(item.kind))),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: t.textTheme.titleMedium),
                        if (item.detail != null)
                          Text(item.detail!, style: t.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  IconData _icon(AttentionKind kind) => switch (kind) {
        AttentionKind.unpaidFees => Icons.payments_rounded,
        AttentionKind.openComplaints => Icons.report_problem_rounded,
        AttentionKind.openTasks => Icons.checklist_rounded,
        AttentionKind.pendingLeaves => Icons.luggage_rounded,
        AttentionKind.unhousedResidents => Icons.bed_rounded,
      };

  // Colour carries meaning here and only here: money owed and unresolved complaints are the
  // two that cost an owner something, so they are the two that are amber.
  Color _tone(AttentionKind kind) => switch (kind) {
        AttentionKind.unpaidFees => NivoraColors.warning,
        AttentionKind.openComplaints => NivoraColors.warning,
        AttentionKind.openTasks => NivoraColors.info,
        AttentionKind.pendingLeaves => NivoraColors.info,
        AttentionKind.unhousedResidents => NivoraColors.info,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// CASH FLOW
// ─────────────────────────────────────────────────────────────────────────────

class _CashflowSection extends ConsumerWidget {
  const _CashflowSection({required this.hostelId, required this.period, required this.stats});

  final String hostelId;
  final String period;
  final HostelStats? stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final window = ref.watch(ownerFinanceWindowProvider);
    final series = window == null
        ? const AsyncValue<List<FinanceDay>>.loading()
        : ref.watch(dailyFinanceProvider(window));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          title: 'Cash flow',
          // Said explicitly, because these are NOT the fee collections above: revenues and
          // expenses are a separate ledger, and adding the two would double-count any PG that
          // also books rent as revenue.
          caption: 'Last $financeWindowDays days, from the revenue and expense ledgers. '
              'Fee collections are counted separately above.',
        ),
        _PlainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              whenAsync(
                series,
                loading: () => const Skeleton(height: CashflowChart.plotHeight),
                error: (error) => ErrorNote(
                  error: error,
                  compact: true,
                  onRetry: window == null
                      ? null
                      : () => ref.invalidate(dailyFinanceProvider(window)),
                ),
                data: (days) => CashflowChart(days: days),
              ),
              if (stats != null) ...[
                const SizedBox(height: Space.md),
                Divider(color: t.colorScheme.outlineVariant, height: 1),
                const SizedBox(height: Space.sm),
                _MonthTotals(stats: stats!, period: period),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The calendar month's totals, spelled out under the 30-day chart. The two windows are
/// different on purpose and are labelled as such — a chart and a total that silently disagree
/// is how a dashboard loses an owner's trust.
class _MonthTotals extends StatelessWidget {
  const _MonthTotals({required this.stats, required this.period});

  final HostelStats stats;
  final String period;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final net = stats.revenueMonth - stats.expensesMonth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${monthNameOnly(period).toUpperCase()} SO FAR', style: t.textTheme.labelSmall),
        const SizedBox(height: Space.xs),
        // Three money figures side by side need about 96dp each before the rupee amount
        // starts ellipsing, and a truncated ledger figure is worse than no figure at all.
        // Below that the same three become stacked label/value rows, which is the layout a
        // 320dp phone at 1.4x wanted anyway.
        LayoutBuilder(
          builder: (context, constraints) {
            final figures = [
              (label: 'Booked in', value: money(stats.revenueMonth), tone: null),
              (label: 'Booked out', value: money(stats.expensesMonth), tone: null),
              (
                label: 'Net',
                value: money(net),
                tone: net < 0 ? NivoraColors.error : NivoraColors.success,
              ),
            ];
            final wide = constraints.maxWidth / figures.length >= 96;
            if (wide) {
              return Row(
                children: [
                  for (final f in figures)
                    Expanded(child: _Figure(label: f.label, value: f.value, tone: f.tone)),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in figures) ...[
                  if (f != figures.first) const SizedBox(height: Space.xs),
                  _Figure(label: f.label, value: f.value, tone: f.tone, inline: true),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.tone, this.inline = false});

  final String label;
  final String value;

  /// Canonical, resolved here. Null for a figure whose colour would mean nothing.
  final Color? tone;

  /// Label and value on one line, for the narrow layout.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    final valueText = Text(
      value,
      style: t.textTheme.titleSmall?.copyWith(color: accent),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (inline) {
      return Row(
        children: [
          Expanded(child: Text(label, style: t.textTheme.bodySmall)),
          const SizedBox(width: Space.sm),
          valueText,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.textTheme.bodySmall),
        const SizedBox(height: Space.xxs),
        valueText,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENT ACTIVITY
// ─────────────────────────────────────────────────────────────────────────────

class _ActivitySection extends ConsumerWidget {
  const _ActivitySection({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(ownerActivityProvider(hostelId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading(
          title: 'Recent activity',
          caption: 'Complaints raised and notices posted, newest first.',
        ),
        _PlainCard(
          child: whenAsync(
            feed,
            loading: () => const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Skeleton(),
                SizedBox(height: Space.sm),
                Skeleton(widthFactor: 0.7),
                SizedBox(height: Space.sm),
                Skeleton(widthFactor: 0.55),
              ],
            ),
            error: (error) => ErrorNote(
              error: error,
              compact: true,
              onRetry: () {
                ref.invalidate(complaintsProvider(ComplaintQuery(hostelId: hostelId)));
                ref.invalidate(noticesProvider(hostelId));
              },
            ),
            data: (items) => items.isEmpty
                ? const EmptyNote(
                    icon: Icons.inbox_rounded,
                    title: 'Nothing has happened yet',
                    message: 'Complaints your residents raise and notices you post appear here.',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(height: Space.md),
                        _ActivityRow(item: items[i]),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = item.complaintStatus;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          item.kind == ActivityKind.complaint
              ? Icons.report_problem_rounded
              : Icons.campaign_rounded,
          size: IconSize.md,
          color: t.colorScheme.outline,
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title,
                  style: t.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: Space.xxs),
              Row(
                children: [
                  if (status != null) ...[
                    StatusChip(
                      label: status.label,
                      tone: switch (status) {
                        ComplaintStatus.open => NivoraColors.warning,
                        ComplaintStatus.inProgress => NivoraColors.info,
                        ComplaintStatus.resolved => NivoraColors.success,
                      },
                    ),
                    const SizedBox(width: Space.xs),
                  ],
                  Flexible(
                    child: Text(
                      [if (item.detail != null) item.detail!, relativeTime(item.at)].join(' · '),
                      style: t.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SHAPES
// ─────────────────────────────────────────────────────────────────────────────

/// A card that is NOT glass.
///
/// Glass marks one step of elevation (see shared/glass/glass.dart). The hero is the thing that
/// floats on this screen; if every card were glass, none of them would be raised and the whole
/// page would read as fog.
class _PlainCard extends StatelessWidget {
  const _PlainCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surface,
      borderRadius: Radii.rCard,
      child: InkWell(
        borderRadius: Radii.rCard,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            borderRadius: Radii.rCard,
            border: Border.all(color: t.colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FullPage extends StatelessWidget {
  const _FullPage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [child],
      );
}

/// The dashboard's shape, before the numbers arrive. Same geometry as the real thing, so the
/// page does not jump when it fills in.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No fixed heights. They were sized for 1.0x text and at 1.4x the real cards grow
          // past them, so the page jumped downward the moment the numbers arrived — the one
          // thing a skeleton exists to prevent.
          SkeletonCard(lines: 3),
          SizedBox(height: Space.md),
          SkeletonCard(lines: 2),
          SizedBox(height: Space.md),
          SkeletonCard(lines: 2),
        ],
      );
}
