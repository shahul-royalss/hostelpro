import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/glass/glass.dart';
import '../../shared/motion/entrance.dart';
import '../auth/verify_email_screen.dart';
import 'notices/compose_notice_sheet.dart';
import 'notices/owner_notices_screen.dart';
import 'owner_complaints_screen.dart';
import 'owner_format.dart';
import 'owner_insights.dart';
import 'owner_pg_detail_screen.dart';
import 'owner_providers.dart';
import 'widgets/cashflow_chart.dart';
import 'widgets/states.dart';

/// "How is my PG business performing?" — answered in the order an owner asks it.
///
/// ── THE LAYOUT IS FIGMA 4:437, `screen-owner-dashboard` ───────────────────────────────────
///
/// A property bar, a 2×2 grid of KPI cards, a labelled cash-flow well, and a bare activity
/// list. Three things about that are deliberate and were not true of this screen before:
///
///  1. THE FIGURES ARE A GRID, not a column of full-width cards. Four numbers stacked at full
///     width is four screens' worth of scrolling to learn what one glance should tell you;
///     4:437 puts all four above the fold and lets SIZE, not position, rank them.
///  2. SECTIONS ARE LABELLED FROM OUTSIDE. `30-DAY CASH FLOW` and `RECENT ACTIVITY` are caps
///     labels on the page ground ([SectionLabel]), not `title-lg` headings inside a card. That
///     is what lets the chart well and the activity rows sit on the ground: they no longer
///     need a card to hang a title on, and the page stops being a stack of boxes.
///  3. COLOUR ON A FIGURE IS INFORMATION. Two of the four values are cream because they are
///     counts; pending fees is red and open complaints is amber because those two cost the
///     owner something. Nothing else on this screen is coloured for emphasis.
///
/// EVERY NUMBER HERE IS COUNTED BY POSTGRES. rpc_hostel_stats returns all of them in one query
/// (db/schema.sql), and rpc_daily_finance returns the chart series zero-filled. Nothing on this
/// screen is derived from a page of rows that happened to be in memory, and nothing is
/// estimated: if a figure is not in the database it is not on the screen. The mockup's fourth
/// card carries "4 critical escalations" under its complaint count; `public.complaints` has no
/// priority or severity column, so that line is absent rather than invented.
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
            message:
                'Nivora sets up a PG against your account before it appears here. '
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
          await ref.read(hostelStatsProvider(statsQuery).future).timeout(ownerRefreshTimeout);
        } catch (_) {
          // The error is already rendered by the section below; rethrowing here would only
          // turn a handled failure into an unhandled one.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.huge),
        children: [
          // Above the property bar, not below it: the ask is about this ACCOUNT, and hanging it
          // under the hostel switcher would read as being about the hostel currently selected.
          const VerifyEmailBanner(),
          const _PropertyBar(),
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
                    message:
                        'The dashboard query came back empty. That normally means the PG '
                        'was created moments ago and has nothing in it yet.',
                  )
                : _Figures(stats: s, hostelId: hostelId, period: period),
          ),
          const SizedBox(height: Space.lg),
          _CashflowSection(hostelId: hostelId, period: period, stats: stats.value),
          const SizedBox(height: Space.lg),
          _NoticesSection(hostelId: hostelId),
          const SizedBox(height: Space.lg),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

/// Who is reading, and which PG the figures below belong to.
///
/// 4:437's header is `● Nivora Premium PG ⌄` — a brand dot, the property in `title` weight, and
/// a chevron when there is somewhere to go. That replaced a bordered card with a
/// `CURRENT PROPERTY` eyebrow inside it: the property is not a statistic, it is the SCOPE of
/// every statistic under it, and drawing it as one more card said the opposite.
///
/// The greeting stays above it. The mockup has none — its header is the app's only chrome —
/// but this screen already sits under the shell's own bar, and the greeting is the one thing
/// on the page that is readable before any query resolves.
class _PropertyBar extends ConsumerWidget {
  const _PropertyBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final session = ref.watch(sessionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${greetingFor(DateTime.now())}, ${firstName(session?.fullName)}',
          style: t.textTheme.displaySmall,
        ),
        const SizedBox(height: Space.sm),
        const _HostelSwitcher(),
        const SizedBox(height: Space.sm),
        // The design's header rule. It is what makes the property line read as the scope of
        // everything below rather than as the first row of the grid.
        Divider(
          color: t.colorScheme.outlineVariant,
          height: Strokes.hairline,
          thickness: Strokes.hairline,
        ),
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
    if (list == null) return const Skeleton(width: 160, height: IconSize.md);

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

    final several = list.length >= 2;
    final row = Row(
      children: [
        // The design's brand dot — `w-2 h-2 rounded-full bg-[#c9a96e]`, the one piece of gold
        // in the header. Decorative, so it is hidden from the semantics tree.
        ExcludeSemantics(
          child: Container(
            width: Space.xs,
            height: Space.xs,
            decoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: Space.xs),
        // Flexible, not a fixed cap: at 1.4x scale a capped width still overflowed a 320dp
        // header, because the cap bounds the text and not the row.
        Flexible(
          child: Text(
            name,
            style: t.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (several)
          Icon(Icons.expand_more_rounded, size: IconSize.md, color: t.colorScheme.outline),
      ],
    );

    if (!several) {
      return Semantics(label: 'Current property: $name', container: true, child: row);
    }
    // A 44dp target on the whole row rather than on the chevron alone: the name is what a
    // person aims at, and the chevron is 16dp of glyph.
    return Semantics(
      button: true,
      label: 'Current property: $name. Tap to switch.',
      container: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: Radii.rControl,
          onTap: () => _pick(context, ref, list, activeId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: row,
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
        _KpiGrid(stats: stats, hostelId: hostelId, period: period),
        const SizedBox(height: Space.lg),
        _NeedsYou(stats: stats),
      ],
    );
  }
}

/// The subscription state, said plainly — Figma node 4:1520's `warning-banner` (4:1531).
///
/// Renewal is a Super Admin write (rls-policies.sql), so this deliberately offers no button.
/// The mockup draws one; see [NoticeBanner] for why it is not copied.
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.notice});
  final ({String title, String detail, bool severe}) notice;

  @override
  Widget build(BuildContext context) {
    return NoticeBanner(
      icon: notice.severe ? Icons.lock_clock_rounded : Icons.schedule_rounded,
      tone: notice.severe ? NivoraColors.error : NivoraColors.warning,
      eyebrow: notice.title,
      message: notice.detail,
    );
  }
}

/// 4:437's four cards, in its own order: money in, beds filled, money owed, work open.
///
/// The reading is diagonal on purpose and it is the mockup's, not a convenience of the grid:
/// the left column is money and the right column is the building, the top row is what is going
/// right and the bottom row is what is not.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.stats, required this.hostelId, required this.period});

  final HostelStats stats;
  final String hostelId;
  final String period;

  @override
  Widget build(BuildContext context) {
    final month = monthNameOnly(period);
    final billed = stats.feesCollected + stats.feesPending;
    final rate = stats.occupancyRate;
    final complaints = stats.openComplaints;
    final unpaid = stats.studentsUnpaid;

    // The two rows arrive in reading order — money first, then what is outstanding. One
    // movement with a direction, rather than four cards appearing at once where a skeleton was.
    // See [Entrance]: it runs once, never delays a frame, and is off entirely under "reduce
    // motion".
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Entrance(
          child: _TileRow(
            left: KpiTile(
              label: 'Collected in $month',
              value: money(stats.feesCollected),
              // The mockup's `of ₹6,20,000` slot. It falls back to the sentence when there is
              // nothing outstanding, because "of ₹84,000 billed" beside a full meter says less
              // than "Every resident has paid this month." does — and because that sentence is
              // the only place a month with nothing billed at all gets named.
              meta: stats.feesPending > 0
                  ? 'of ${money(billed)} billed'
                  : collectionsCaption(stats),
              meterValue: collectedShare(stats),
              meterTone: NivoraColors.success,
            ),
            right: KpiTile(
              label: 'Occupancy',
              // The figure IS the percentage here, so the meter does not repeat it.
              value: rate == null ? '—' : percentLabel(rate),
              // A PG with no beds configured has no ratio to print — "0 of 0 beds filled" reads
              // as a failed business rather than an unfinished setup — so that one case gets the
              // sentence instead of the figure.
              meta: rate == null ? occupancyCaption(stats) : occupancyHeadline(stats),
              meterValue: rate,
              showMeterPercent: false,
              // Unlike the mockup's card this one navigates, and a card that navigates has to
              // say so. The room grid is the answer to "which beds are free".
              trailing: Icon(
                Icons.chevron_right_rounded,
                size: IconSize.sm,
                color: Theme.of(context).colorScheme.outline,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => OwnerPgDetailScreen(hostelId: hostelId)),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Entrance(
          index: 1,
          child: _TileRow(
            left: KpiTile(
              label: 'Pending fees',
              value: money(stats.feesPending),
              // Red only while there is something to be red about. A settled month drawn in the
              // alarm colour teaches an owner to stop reading the colour.
              valueTone: stats.feesPending > 0 ? NivoraColors.error : NivoraColors.success,
              meta: unpaid > 0 ? countLabel(unpaid, 'outstanding bill') : 'Nothing outstanding',
            ),
            right: KpiTile(
              label: 'Complaints',
              value: complaints > 0 ? '$complaints open' : 'None open',
              valueTone: complaints > 0 ? NivoraColors.warning : NivoraColors.success,
              // The mockup's second line is "4 critical escalations". `public.complaints` has no
              // priority, severity or escalation column — see the schema — so there is no second
              // fact to state and the card stops at the count.
              //
              // TAPPABLE EVEN AT ZERO. "None open" is a claim about the building, and an owner is
              // entitled to check it — the list then shows what was resolved and by whom. A card
              // that only responds when the news is bad teaches people not to trust the good news.
              meta: 'Tap to read them',
              onTap: () => Navigator.of(context).push(OwnerComplaintsScreen.route()),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two cards abreast at the design's 8dp gutter, equal height.
///
/// [IntrinsicHeight] rather than `CrossAxisAlignment.stretch` alone: a Row inside a ListView
/// has an unbounded cross axis, and stretch on an unbounded axis throws. Two children is the
/// whole cost, and the alternative — letting a card whose caption wraps to three lines stand
/// taller than its neighbour — is the ragged bottom edge the grid exists to avoid.
class _TileRow extends StatelessWidget {
  const _TileRow({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: Space.xs),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// The things actually outstanding that the grid above does NOT already carry.
///
/// [attentionItems] is unchanged and still returns all five kinds — it is a pure function with
/// its own tests, and the dashboard is not the only thing that may ever read it. What changed
/// is that unpaid fees and open complaints are now cards of their own, so listing them again
/// here would be the same fact twice, three centimetres apart.
///
/// The distinction the empty state has to keep: a filtered list that came out empty is not the
/// same as a clear morning. If the grid is showing six unpaid residents, "Nothing is waiting on
/// you" would be a lie — so the section simply disappears, and the reassurance is only printed
/// when the UNFILTERED list is empty too.
class _NeedsYou extends StatelessWidget {
  const _NeedsYou({required this.stats});

  final HostelStats stats;

  /// Promoted to their own KPI card by [_KpiGrid].
  static const _onTheGrid = {AttentionKind.unpaidFees, AttentionKind.openComplaints};

  @override
  Widget build(BuildContext context) {
    final all = attentionItems(stats);
    if (all.isEmpty) {
      return const EmptyNote(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing is waiting on you',
        message: 'Every resident has paid, no complaints are open and no tasks are due.',
        compact: true,
        tone: NivoraColors.success,
      );
    }
    final items = [
      for (final item in all)
        if (!_onTheGrid.contains(item.kind)) item,
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(label: 'Needs you'),
        // Explicit children, not an itemBuilder: the state that remembers "already arrived"
        // has to survive, and a lazily-built row re-enters every time it is scrolled back to.
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.md),
          Entrance(
            index: i,
            child: _AttentionRow(item: items[i]),
          ),
        ],
      ],
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});
  final AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ToneBadge(icon: _icon(item.kind), tone: _tone(item.kind), circular: true),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: t.textTheme.labelLarge),
              if (item.detail != null) ...[
                const SizedBox(height: Space.xxs / 2),
                Text(item.detail!, style: t.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
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

    // 4:437's own arrangement: `30-DAY CASH FLOW` on the left of the heading row, the key on
    // the right, and the plot in a borderless raised well underneath. No outer card — the
    // section label is what groups it, which is the whole reason the label moved outside.
    final days = series.value;
    final plotted = days != null && CashflowChart.hasPlot(days);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          label: '$financeWindowDays-day cash flow',
          trailing: plotted ? const CashflowLegend() : null,
        ),
        // Said explicitly, because these are NOT the fee collections above: revenues and
        // expenses are a separate ledger, and adding the two would double-count any PG that
        // also books rent as revenue.
        Text(
          'From the revenue and expense ledgers. '
          'Fee collections are counted separately above.',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.sm),
        FlatSurface(
          // The design's well: `#171A1E`, one rung up the ramp from the page ground, and NO
          // hairline — the fill alone is the edge on 4:437.
          weight: GlassWeight.regular,
          border: false,
          borderRadius: Radii.rCard,
          padding: const EdgeInsets.all(Space.sm),
          child: whenAsync(
            series,
            loading: () => const Skeleton(height: CashflowChart.plotHeight),
            error: (error) => ErrorNote(
              error: error,
              compact: true,
              onRetry: window == null ? null : () => ref.invalidate(dailyFinanceProvider(window)),
            ),
            data: (days) => CashflowChart(days: days),
          ),
        ),
        if (stats != null) ...[
          const SizedBox(height: Space.md),
          _MonthTotals(stats: stats!, period: period),
        ],
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

  /// At 1.0x, the width a rupee figure of this app's size needs before it starts ellipsing.
  static const _figureWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final net = stats.revenueMonth - stats.expensesMonth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label: '${monthNameOnly(period)} so far'),
        // Three money figures side by side need about 96dp each before the rupee amount
        // starts ellipsing, and a truncated ledger figure is worse than no figure at all.
        // Below that the same three become stacked label/value rows.
        //
        // THE THRESHOLD SCALES WITH THE TEXT, which it did not before. 96 was measured at 1.0x,
        // so at 1.4x on a 320dp phone the row still passed the test — three 96dp columns — and
        // then ellipsised a crore down to `₹4,52,0…`. The figures grow with the type; the width
        // they need has to grow with it too. Same device as _RoomTile on the detail screen.
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
            final needed = MediaQuery.textScalerOf(context).scale(_figureWidth);
            final wide = constraints.maxWidth / figures.length >= needed;
            if (wide) {
              return Row(
                children: [
                  for (final f in figures)
                    Expanded(
                      child: _Figure(label: f.label, value: f.value, tone: f.tone),
                    ),
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
// NOTICES
// ─────────────────────────────────────────────────────────────────────────────

/// The owner's way in to writing a notice, and the last thing they said.
///
/// WHY THIS IS HERE AND NOT A TAB. The owner's five slots are declared in
/// features/shell/role_shell.dart and shared with every other role; that file is where a reader
/// learns what a role's navigation is, and renaming one of its labels from inside this feature
/// is how two files start disagreeing about which tab is third. So the dashboard carries the
/// section and [OwnerNoticesScreen] is pushed from it.
///
/// ONE NOTICE, NOT A LIST. The activity feed directly below already interleaves notices with
/// complaints; repeating five of them here would make the same rows appear twice on one screen
/// under two different headings. What this section adds that the feed cannot is the ACTION —
/// and the single most recent notice, which is the one an owner checks before posting again so
/// they do not say the same thing twice.
class _NoticesSection extends ConsumerWidget {
  const _NoticesSection({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider(hostelId));
    final hostelName = ref.watch(hostelProvider(hostelId)).value?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          label: 'Notices',
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(OwnerNoticesScreen.route(hostelId)),
            child: const Text('See all'),
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The compose control does NOT wait for the list. A failed read of what was
              // posted before says nothing about whether a new notice can be written, and an
              // owner who needs to tell the hostel the water is off should not be blocked by
              // a query that timed out.
              FilledButton.icon(
                onPressed: () =>
                    showComposeNoticeSheet(context, hostelId: hostelId, hostelName: hostelName),
                icon: const Icon(Icons.campaign_rounded, size: IconSize.md),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                label: const Text('Post a notice'),
              ),
              const SizedBox(height: Space.sm),
              whenAsync(
                notices,
                loading: () => const Skeleton(),
                // Compact, and no retry button: the pull-to-refresh on this page is the retry,
                // and the section above it is still usable.
                error: (error) => ErrorNote(
                  error: error,
                  compact: true,
                  onRetry: () => ref.invalidate(noticesProvider(hostelId)),
                ),
                data: (page) => page.isEmpty
                    ? Text(
                        'Nothing posted yet. A notice reaches everyone you address it to, '
                        'with a notification, straight away.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : _LatestNotice(notice: page.items.first, total: page.items.length),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The most recent notice, two lines of it.
class _LatestNotice extends StatelessWidget {
  const _LatestNotice({required this.notice, required this.total});

  final Notice notice;

  /// How many are on the loaded page — used only to decide whether to say "and N older",
  /// never drawn as a total count of the noticeboard. `noticesProvider` pages at twenty, so
  /// the real total is not known here and is not claimed.
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LAST POSTED', style: t.textTheme.labelSmall),
        const SizedBox(height: Space.xxs),
        Text(
          notice.title,
          style: t.textTheme.labelLarge,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.xxs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${notice.audience.label} · ${relativeTime(notice.createdAt)}',
              style: t.textTheme.labelSmall,
            ),
            if (total > 1) Text('· ${total - 1} older on this page', style: t.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECENT ACTIVITY
// ─────────────────────────────────────────────────────────────────────────────
class _FullPage extends StatelessWidget {
  const _FullPage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(Space.md), children: [child]);
}

/// The dashboard's shape, before the numbers arrive. Same geometry as the real thing — a 2×2
/// grid, not a column — so the page does not rearrange itself when it fills in.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // No fixed heights. They were sized for 1.0x text and at 1.4x the real cards grow
      // past them, so the page jumped downward the moment the numbers arrived — the one
      // thing a skeleton exists to prevent.
      _TileRow(left: SkeletonCard(lines: 2), right: SkeletonCard(lines: 2)),
      SizedBox(height: Space.xs),
      _TileRow(left: SkeletonCard(lines: 1), right: SkeletonCard(lines: 1)),
    ],
  );
}
