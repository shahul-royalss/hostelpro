import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/clay/clay.dart';
import '../../shared/finance/expense_stats_screen.dart';
import '../../shared/glass/glass.dart';
import '../auth/verify_email_screen.dart';
import 'notices/compose_notice_sheet.dart';
import 'notices/owner_notices_screen.dart';
import 'owner_complaints_screen.dart';
import 'owner_format.dart';
import 'owner_insights.dart';
import 'owner_pg_detail_screen.dart';
import 'owner_providers.dart';
import 'owner_tabs.dart';
import 'plan/plan_billing_screen.dart';
import '../shell/join_requests.dart';
import 'requests/staff_requests.dart';
import 'widgets/checkouts_notice.dart';
import '../../data/repositories/stay_repository.dart' show ownerCheckoutSummaryProvider;
import 'rooms/floor_plan_screen.dart';
import 'staff/owner_staff_screen.dart';
import 'tasks/owner_tasks_screen.dart';
import 'widgets/cashflow_chart.dart';
import 'widgets/owner_header.dart';
import 'widgets/states.dart' show ErrorNote, whenAsync;

/// HOME — "how is my PG business doing, and what is waiting on me?" — answered in the order an
/// owner asks it.
///
/// ── THE LAYOUT IS THE CANVAS'S OWNER HOME ────────────────────────────────────────────────
///
/// Under the forest header (drawn by the shell — see [OwnerHeader]): an Overview strip of stat
/// tiles led by the month's collections, the one gold banner when something has a deadline, the
/// quick actions, and the list of what needs the owner. Below the fold, the 30-day cash flow and
/// the noticeboard's latest. Three things about that are deliberate:
///
///  1. ONE HERO. The month's collections are the forest tile with the gold bar; every other
///     figure is a plain card. Two heroes would make neither the headline.
///  2. COLOUR ON A FIGURE IS INFORMATION. Pending fees is red and open complaints amber only
///     while there is something to be red or amber about; a settled month reads green. Nothing
///     else on the page is coloured for emphasis.
///  3. ONE BANNER, AT MOST. The subscription when it is running out, otherwise the rent still to
///     collect, otherwise nothing — the gold surface means "this has a deadline", and a second
///     one would make neither urgent.
///
/// EVERY NUMBER HERE IS COUNTED BY POSTGRES. rpc_hostel_stats returns all of them in one query
/// (db/schema.sql), and rpc_daily_finance returns the chart series zero-filled. Nothing on this
/// screen is derived from a page of rows that happened to be in memory, and nothing is
/// estimated: if a figure is not in the database it is not on the screen. That is why the
/// "today" tile is what the revenue LEDGER booked today and says so — rpc_hostel_stats has no
/// count of fee money taken today, and a tile calling the ledger "collected" would be a figure
/// this app made up.
///
/// READS: rpc_hostel_stats · rpc_daily_finance · announcements · hostels.
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
          child: EmptyState(
            icon: ClayIcons.rooms,
            title: 'No PG on your account yet',
            body:
                'Apnivaas sets up a PG against your account before it appears here. '
                'Contact your account manager if you were expecting one.',
          ),
        ),
        _ => const _FullPage(
            gutter: false,
            child: StatCarouselSkeleton(semanticLabel: 'Loading overview'),
          ),
      };
    }

    final period = ref.watch(currentPeriodMonthProvider);
    final statsQuery = StatsQuery(hostelId: hostelId, periodMonth: period);
    final stats = ref.watch(hostelStatsProvider(statsQuery));

    return RefreshIndicator(
      onRefresh: () async {
        refreshOwnerDashboard(ref, hostelId: hostelId, period: period);
        ref.invalidate(ownerCheckoutSummaryProvider);
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
      // NO HORIZONTAL PADDING ON THE LIST: the Overview strip bleeds to the screen edge and
      // brings the gutter as its own padding, so every other section is wrapped in [_Gutter].
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.huge),
        children: [
          // First, not under the figures: the ask is about this ACCOUNT, and hanging it under
          // the PG's numbers would read as being about the PG.
          const _Gutter(child: VerifyEmailBanner()),
          PlanEndedBanner(hostelId: hostelId),
          _Gutter(
            child: SectionHeader(
              title: 'Overview',
              trailing: StatusChip(label: monthLabel(period)),
            ),
          ),
          const SizedBox(height: OwnerRhythm.headingGap),
          whenAsync(
            stats,
            loading: () => const StatCarouselSkeleton(semanticLabel: 'Loading overview'),
            error: (error) => _Gutter(
              child: ErrorNote(
                error: error,
                onRetry: () => ref.invalidate(hostelStatsProvider(statsQuery)),
              ),
            ),
            data: (s) => s == null
                ? const _Gutter(
                    child: EmptyState(
                      compact: true,
                      icon: ClayIcons.analytics,
                      title: 'No figures for this PG',
                      body:
                          'The dashboard query came back empty. That normally means the PG '
                          'was created moments ago and has nothing in it yet.',
                    ),
                  )
                : _Overview(stats: s, hostelId: hostelId, period: period),
          ),
          whenAsync(
            stats,
            loading: () => const SizedBox.shrink(),
            error: (_) => const SizedBox.shrink(),
            data: (s) => s == null ? const SizedBox.shrink() : _DeadlineBanner(stats: s),
          ),
          const SizedBox(height: OwnerRhythm.sectionGap),
          // Not behind the query: every action here opens a screen that loads its own data, so
          // a dashboard whose figures failed is still the way to everything else.
          _Gutter(child: _QuickActions(hostelId: hostelId)),
          const JoinRequestsEntry(padding: EdgeInsets.fromLTRB(Space.md, OwnerRhythm.sectionGap, Space.md, 0)),
          const StaffRequestsEntry(padding: EdgeInsets.fromLTRB(Space.md, OwnerRhythm.sectionGap, Space.md, 0)),
          CheckoutsNotice(
            hostelId: hostelId,
            padding: const EdgeInsets.fromLTRB(Space.md, OwnerRhythm.sectionGap, Space.md, 0),
          ),
          whenAsync(
            stats,
            loading: () => const SizedBox.shrink(),
            error: (_) => const SizedBox.shrink(),
            data: (s) => s == null
                ? const SizedBox.shrink()
                : _Gutter(child: _NeedsAttention(stats: s, hostelId: hostelId)),
          ),
          const SizedBox(height: OwnerRhythm.sectionGap),
          _Gutter(child: _CashflowSection(period: period, stats: stats.value)),
          const SizedBox(height: OwnerRhythm.sectionGap),
          _Gutter(child: _NoticesSection(hostelId: hostelId)),
        ],
      ),
    );
  }
}

/// The page gutter, for every section that does not bleed.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: Space.md), child: child);
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERVIEW
// ─────────────────────────────────────────────────────────────────────────────

/// The Overview strip: money in, money owed, beds, complaints, today's ledger, and the way to
/// the expense trends — in that order, because that is the order the questions come in.
class _Overview extends StatelessWidget {
  const _Overview({required this.stats, required this.hostelId, required this.period});

  final HostelStats stats;
  final String hostelId;
  final String period;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final month = monthNameOnly(period);
    final billed = s.feesCollected + s.feesPending;
    final share = collectedShare(s);
    final rate = s.occupancyRate;
    final complaints = s.openComplaints;
    final unpaid = s.studentsUnpaid;

    return StatCarousel(
      children: [
        StatTile(
          style: StatTileStyle.hero,
          icon: ClayIcons.money,
          label: 'Collected in $month',
          value: money(s.feesCollected),
          // "of ₹84,000 billed · 60%" while anything is outstanding. With nothing outstanding the
          // sentence says more than the ratio beside a full bar does — "Every resident has paid
          // this month." — and it is the only place a month with nothing billed gets named.
          caption: s.feesPending > 0
              ? 'of ${money(billed)} billed${share == null ? '' : ' · ${percentLabel(share)}'}'
              : collectionsCaption(s),
          progress: share,
        ),
        StatTile(
          icon: ClayIcons.invoice,
          label: 'Pending fees',
          value: money(s.feesPending),
          // Red only while there is something to be red about. A settled month drawn in the
          // alarm colour teaches an owner to stop reading the colour.
          valueTone: s.feesPending > 0 ? ApnivaasColors.error : ApnivaasColors.success,
          caption: unpaid > 0 ? countLabel(unpaid, 'outstanding bill') : 'Nothing outstanding',
        ),
        StatTile(
          icon: ClayIcons.beds,
          label: 'Beds filled',
          // A PG with no beds configured has no ratio to print — "0/0" reads as a failed
          // business rather than an unfinished setup — so that one case gets the dash and the
          // sentence instead.
          value: rate == null ? '—' : '${s.occupiedBeds}/${s.totalBeds}',
          caption: rate == null ? 'No beds set up yet' : '${percentLabel(rate)} occupancy',
          // The room grid is the answer to "which beds are free".
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => OwnerPgDetailScreen(hostelId: hostelId)),
          ),
        ),
        StatTile(
          icon: ClayIcons.complaint,
          label: 'Complaints',
          value: complaints > 0 ? '$complaints open' : 'None open',
          valueTone: complaints > 0 ? ApnivaasColors.warning : ApnivaasColors.success,
          // TAPPABLE EVEN AT ZERO. "None open" is a claim about the building, and an owner is
          // entitled to check it — the list then shows what was resolved and by whom. A tile
          // that only responds when the news is bad teaches people not to trust the good news.
          // `public.complaints` has no priority or severity column, so there is no second fact
          // to state and the caption is the way in rather than an invented "2 urgent".
          caption: 'Tap to read them',
          onTap: () => Navigator.of(context).push(OwnerComplaintsScreen.route()),
        ),
        StatTile(
          icon: ClayIcons.receipt,
          label: 'Booked in today',
          value: money(s.revenueToday),
          // The revenue ledger, not fee collections — see the class doc. Named on the tile so
          // nobody adds it to the hero figure.
          caption: s.expensesToday > 0
              ? '${money(s.expensesToday)} booked out'
              : 'From the revenue ledger',
        ),
        StatTile(
          style: StatTileStyle.tonal,
          icon: ClayIcons.analytics,
          value: 'Expense trends',
          label: 'Month by month for this PG',
          onTap: () => Navigator.of(context).push(ExpenseStatsScreen.route(hostelId)),
        ),
      ],
    );
  }
}

/// The one gold banner: whatever on this PG has a deadline.
///
/// THE SUBSCRIPTION FIRST, AND WITH NO BUTTON. Renewal is a Super Admin write
/// (rls-policies.sql), so the next step is a phone call, never a control in this app — a
/// "Renew" here would be a dead end. Otherwise the month's outstanding rent, with the way to
/// the Money tab, because "who has paid" is the list that answers "who has not".
class _DeadlineBanner extends ConsumerWidget {
  const _DeadlineBanner({required this.stats});
  final HostelStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = subscriptionNotice(stats);
    final Widget banner;
    if (notice != null) {
      banner = ActionBanner(
        title: notice.title,
        message: notice.detail,
        icon: notice.severe ? ClayIcons.security : ClayIcons.calendar,
      );
    } else if (stats.feesPending > 0) {
      banner = ActionBanner(
        title: 'Rent still to collect',
        message: collectionsCaption(stats),
        icon: ClayIcons.rentReminder,
        actionLabel: 'See payments',
        actionSemanticLabel: 'See who has paid this month',
        onAction: () => ref.read(ownerTabProvider.notifier).go(OwnerTab.money),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, 0),
      child: banner,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUICK ACTIONS
// ─────────────────────────────────────────────────────────────────────────────

/// Eight things an owner does from here, each opening a screen or sheet that already existed.
///
/// NOTHING HERE IS NEW POWER. Posting a notice, assigning a task and editing the layout were
/// already the owner's; reading complaints, payments, rooms, staff and expenses already had
/// screens. What changed is that they are one tap from Home instead of two or three.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelName = ref.watch(hostelProvider(hostelId)).value?.name;
    void push(Route<void> route) => Navigator.of(context).push(route);

    return QuickActionGrid(
      actions: [
        QuickActionTile(
          icon: ClayIcons.announcement,
          label: 'Post a notice',
          onTap: () =>
              showComposeNoticeSheet(context, hostelId: hostelId, hostelName: hostelName),
        ),
        QuickActionTile(
          icon: ClayIcons.complaint,
          label: 'Read complaints',
          onTap: () => push(OwnerComplaintsScreen.route()),
        ),
        QuickActionTile(
          icon: ClayIcons.collectPayment,
          label: 'See who paid',
          onTap: () => ref.read(ownerTabProvider.notifier).go(OwnerTab.money),
        ),
        QuickActionTile(
          icon: ClayIcons.rooms,
          label: 'View rooms',
          onTap: () => push(
            MaterialPageRoute<void>(builder: (_) => OwnerPgDetailScreen(hostelId: hostelId)),
          ),
        ),
        QuickActionTile(
          icon: ClayIcons.tasks,
          label: 'Assign a task',
          onTap: () => showAssignTaskSheet(context, hostelId: hostelId),
        ),
        QuickActionTile(
          icon: ClayIcons.team,
          label: 'Manage staff',
          onTap: () => push(MaterialPageRoute<void>(builder: (_) => const OwnerStaffScreen())),
        ),
        QuickActionTile(
          icon: ClayIcons.expense,
          label: 'Track expenses',
          onTap: () => push(ExpenseStatsScreen.route(hostelId)),
        ),
        QuickActionTile(
          icon: ClayIcons.beds,
          label: 'Edit layout',
          onTap: () => push(FloorPlanScreen.route(hostelId)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEEDS YOUR ATTENTION
// ─────────────────────────────────────────────────────────────────────────────

/// The things actually outstanding that the Overview tiles do NOT already carry.
///
/// [attentionItems] is unchanged and still returns all five kinds — it is a pure function with
/// its own tests, and Home is not the only thing that may ever read it. Unpaid fees and open
/// complaints have tiles of their own above (and the rent its banner), so listing them again
/// here would be the same fact twice, a thumb's width apart.
///
/// The distinction the empty state has to keep: a filtered list that came out empty is not the
/// same as a clear morning. If the tiles are showing six unpaid residents, "Nothing is waiting
/// on you" would be a lie — so the section simply disappears, and the reassurance is only
/// printed when the UNFILTERED list is empty too.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({required this.stats, required this.hostelId});

  final HostelStats stats;
  final String hostelId;

  /// Carried by their own Overview tile.
  static const _onTheTiles = {AttentionKind.unpaidFees, AttentionKind.openComplaints};

  @override
  Widget build(BuildContext context) {
    final all = attentionItems(stats);
    final Widget body;
    if (all.isEmpty) {
      body = const EmptyState(
        compact: true,
        icon: ClayIcons.success,
        title: 'Nothing is waiting on you',
        body: 'Every resident has paid, no complaints are open and no tasks are due.',
      );
    } else {
      final items = [
        for (final item in all)
          if (!_onTheTiles.contains(item.kind)) item,
      ];
      if (items.isEmpty) return const SizedBox.shrink();
      body = ListGroup(
        children: [for (final item in items) _AttentionRow(item: item, hostelId: hostelId)],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: OwnerRhythm.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Needs your attention', size: SectionHeaderSize.card),
          const SizedBox(height: OwnerRhythm.headingGap),
          body,
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, required this.hostelId});

  final AttentionItem item;
  final String hostelId;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);
    // The row's action opens the screen where the thing is dealt with, when the owner has one.
    // Leave is the warden's to approve at the desk, so that row states the count and stops.
    final Widget? action = switch (item.kind) {
      AttentionKind.openTasks => PillButton(
          label: 'Open',
          semanticLabel: 'Open tasks',
          onPressed: () => navigator.push(OwnerTasksScreen.route()),
        ),
      AttentionKind.unhousedResidents => PillButton(
          label: 'Rooms',
          semanticLabel: 'Open rooms and beds',
          onPressed: () => navigator.push(
            MaterialPageRoute<void>(builder: (_) => OwnerPgDetailScreen(hostelId: hostelId)),
          ),
        ),
      _ => null,
    };
    return ListRow(
      icon: _art(item.kind),
      title: item.title,
      subtitle: item.detail ?? _hint(item.kind),
      trailing: action,
    );
  }

  /// A second line for the kinds [attentionItems] gives none: what the count is counting.
  static String? _hint(AttentionKind kind) => switch (kind) {
    AttentionKind.openTasks => 'Jobs on your manager that are not finished',
    AttentionKind.pendingLeaves => 'Residents waiting to hear about time away',
    _ => null,
  };

  /// The clay art at the head of each row: what KIND of thing is waiting. How urgent it is
  /// stays in the words.
  ///
  /// ── THE TWO KINDS THAT ARE NOT MAPPED, AND WHY THAT IS A GUARD RATHER THAN A GAP ────────
  ///
  /// [AttentionKind.unpaidFees] and [AttentionKind.openComplaints] are on the Overview tiles and
  /// are filtered out by [_NeedsAttention._onTheTiles] before a row is ever built, so neither
  /// can reach this function today. They throw rather than quietly drawing a row, so whoever
  /// un-filters them trips this on the first frame and decides deliberately whether the same
  /// fact should really appear twice on one screen.
  static String _art(AttentionKind kind) => switch (kind) {
    AttentionKind.openTasks => ClayIcons.tasks,
    AttentionKind.pendingLeaves => ClayIcons.leave,
    AttentionKind.unhousedResidents => ClayIcons.beds,
    AttentionKind.unpaidFees || AttentionKind.openComplaints => throw UnsupportedError(
      '$kind is carried by its own Overview tile and must not be drawn as an attention row. '
      'Decide deliberately before un-filtering it — see the doc on _art.',
    ),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// CASH FLOW
// ─────────────────────────────────────────────────────────────────────────────

class _CashflowSection extends ConsumerWidget {
  const _CashflowSection({required this.period, required this.stats});

  final String period;
  final HostelStats? stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final window = ref.watch(ownerFinanceWindowProvider);
    final series = window == null
        ? const AsyncValue<List<FinanceDay>>.loading()
        : ref.watch(dailyFinanceProvider(window));

    final days = series.value;
    final plotted = days != null && CashflowChart.hasPlot(days);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '$financeWindowDays-day cash flow', size: SectionHeaderSize.card),
        const SizedBox(height: Space.xxs),
        // Said explicitly, because these are NOT the fee collections above: revenues and
        // expenses are a separate ledger, and adding the two would double-count any PG that
        // also books rent as revenue.
        Text(
          'From the revenue and expense ledgers. '
          'Fee collections are counted separately above.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: OwnerRhythm.headingGap),
        FlatSurface(
          borderRadius: Radii.rSurface,
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The key sits inside the card, over the plot it names, rather than beside the
              // heading: a heading row with a legend in it has nowhere to go at large text on a
              // 320dp phone, and a key that has to wrap under its heading is a key nobody finds.
              if (plotted) ...[
                const Align(alignment: AlignmentDirectional.centerEnd, child: CashflowLegend()),
                const SizedBox(height: Space.xs),
              ],
              whenAsync(
                series,
                loading: () => const Skeleton(
                  height: CashflowChart.plotHeight,
                  radius: Radii.rControl,
                ),
                error: (error) => ErrorNote(
                  error: error,
                  compact: true,
                  onRetry:
                      window == null ? null : () => ref.invalidate(dailyFinanceProvider(window)),
                ),
                data: (days) => CashflowChart(days: days),
              ),
            ],
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
    return FlatSurface(
      borderRadius: Radii.rSurface,
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: '${monthNameOnly(period)} so far', size: SectionHeaderSize.form),
          const SizedBox(height: Space.sm),
          // Three money figures side by side need about 96dp each before the rupee amount
          // starts ellipsing, and a truncated ledger figure is worse than no figure at all.
          // Below that the same three become stacked label/value rows.
          //
          // THE THRESHOLD SCALES WITH THE TEXT. 96 was measured at 1.0x, so at 1.4x on a 320dp
          // phone three 96dp columns would pass and then ellipsise a crore down to `₹4,52,0…`.
          // The figures grow with the type; the width they need has to grow with it too.
          LayoutBuilder(
            builder: (context, constraints) {
              final figures = [
                (label: 'Booked in', value: money(stats.revenueMonth), tone: null),
                (label: 'Booked out', value: money(stats.expensesMonth), tone: null),
                (
                  label: 'Net',
                  value: money(net),
                  tone: net < 0 ? ApnivaasColors.error : ApnivaasColors.success,
                ),
              ];
              final needed = MediaQuery.textScalerOf(context).scale(_figureWidth);
              final wide = constraints.maxWidth / figures.length >= needed;
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
      ),
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
    final labelStyle = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final valueText = Text(
      value,
      style: t.textTheme.headlineSmall?.copyWith(color: accent),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (inline) {
      return Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          const SizedBox(width: Space.sm),
          valueText,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: Space.xxs),
        valueText,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTICES
// ─────────────────────────────────────────────────────────────────────────────

/// The last thing the owner said to the PG, and the way to everything else they have said.
///
/// ONE NOTICE, NOT A LIST. The one an owner checks before posting again, so they do not say the
/// same thing twice; the noticeboard behind "See all" has the rest. Writing a new one is the
/// first quick action above, which does NOT wait for this list — a failed read of what was
/// posted before says nothing about whether a new notice can be written, and an owner who needs
/// to tell the hostel the water is off should not be blocked by a query that timed out.
class _NoticesSection extends ConsumerWidget {
  const _NoticesSection({required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider(hostelId));
    final hostelName = ref.watch(hostelProvider(hostelId)).value?.name;
    void openBoard() => Navigator.of(context).push(OwnerNoticesScreen.route(hostelId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Notices',
          size: SectionHeaderSize.card,
          actionLabel: 'See all',
          onAction: openBoard,
        ),
        const SizedBox(height: Space.xxs),
        whenAsync(
          notices,
          loading: () => const ListSkeleton(rows: 1, semanticLabel: 'Loading notices'),
          // Compact, and in its own card: the pull-to-refresh on this page is the retry, and the
          // sections above it are still usable.
          error: (error) => FlatSurface(
            borderRadius: Radii.rSurface,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: ErrorNote(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(noticesProvider(hostelId)),
            ),
          ),
          data: (page) {
            if (page.isEmpty) {
              return ListRowCard(
                icon: ClayIcons.announcement,
                title: 'Nothing posted yet',
                subtitle: 'A notice reaches everyone you address it to, with a notification, '
                    'straight away.',
                trailing: PillButton(
                  label: 'Write one',
                  semanticLabel: 'Write a notice',
                  onPressed: () =>
                      showComposeNoticeSheet(context, hostelId: hostelId, hostelName: hostelName),
                ),
              );
            }
            final latest = page.items.first;
            // How many are on the loaded page — used only to say "and N older", never drawn as
            // a total. `noticesProvider` pages at twenty, so the real total is not known here
            // and is not claimed.
            final older = page.items.length - 1;
            return ListRowCard(
              icon: ClayIcons.announcement,
              title: latest.title,
              subtitle: [
                'Last posted',
                latest.audience.label,
                relativeTime(latest.createdAt),
                if (older > 0) '$older older on this page',
              ].join(' · '),
              onTap: openBoard,
            );
          },
        ),
      ],
    );
  }
}

class _FullPage extends StatelessWidget {
  const _FullPage({required this.child, this.gutter = true});
  final Widget child;

  /// False for a child that brings its own gutter, like the Overview skeleton.
  final bool gutter;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: gutter
        ? const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.huge)
        : const EdgeInsets.only(top: Space.lg, bottom: Space.huge),
    children: [child],
  );
}
