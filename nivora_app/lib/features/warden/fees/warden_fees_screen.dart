library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/glass/glass.dart';
import '../../../shared/illustrations.dart';
import '../actions/record_payment_sheet.dart';
import '../data/warden_providers.dart';
import '../students/student_sheet.dart';
import '../widgets/paged_list.dart';
import '../widgets/warden_ui.dart';

/// Who has paid, who has not, and taking money from the ones who have not.
///
/// BUILT ON rpc_fee_ledger, NOT ON public.fee_payments — the distinction is the whole screen.
/// fee_payments only has a row once somebody has paid something, so listing it on the first of
/// the month shows an empty table and a perfect collection rate. The ledger LEFT JOINs from
/// students, so every current resident appears with `coalesce(amount_due, monthly_fee)` and
/// status 'unpaid' until they pay. The defaulters are the rows that exist because of that join,
/// and they are the reason a warden opens this tab.
///
/// The summary above the list comes from rpc_hostel_stats FOR THE SAME MONTH, which is computed
/// from the same ledger function. Totals and rows therefore cannot drift apart — they are two
/// readings of one query, not two queries that ought to agree.
class WardenFeesScreen extends ConsumerWidget {
  const WardenFeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Collections',
        child: EmptyState(
          icon: Icons.payments_rounded,
          title: 'No hostel on this account',
          detail: 'A warden is attached to one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final month = ref.watch(selectedMonthProvider);
    final filter = ref.watch(feeFilterProvider);
    final query = FeeLedgerQuery(hostelId: hostelId, periodMonth: month, status: filter);
    final ledger = ref.watch(feeLedgerProvider(query));
    // ═══ A SECOND READ THAT MAY NOT BLOCK THE FIRST ═══
    // `public.payment_refunds` is a child table; no fee RPC returns it. This is a qualifier on
    // figures the ledger read already produced, so it is taken as `.value ?? empty`: while it
    // is in flight, and if it fails outright, the collections list draws exactly as it always
    // did. A refund line is worth having; it is not worth a warden being unable to take rent
    // because a secondary query timed out.
    final refunds =
        ref.watch(hostelRefundsProvider(StatsQuery(hostelId: hostelId, periodMonth: month)))
                .value ??
            RefundIndex.empty;

    return WardenScreen(
      title: 'Collections',
      subtitle: monthLabel(month),
      child: PagedList<FeeLedgerRow>(
        value: ledger,
        // Bounded, and it says what happened. See features/common/refresh.dart: an invalidate
        // that returns immediately retracts the spinner in the same frame, and AsyncSection
        // holds the old ledger through a failed reload — so a warden chasing rent could be
        // reading yesterday's rows with nothing on screen to say so.
        onRefresh: () {
          ref.invalidate(feeLedgerProvider(query));
          ref.invalidate(hostelStatsProvider);
          // The refund read is a second query behind the same rows; a refresh that left it
          // stale would show today's ledger annotated with yesterday's refunds.
          ref.invalidate(hostelRefundsProvider);
          return settleRefresh(context, () => ref.read(feeLedgerProvider(query).future));
        },
        onLoadMore: () => ref.read(feeLedgerProvider(query).notifier).loadMore(),
        header: Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _MonthStepper(),
              const SizedBox(height: Space.sm),
              _MonthSummary(hostelId: hostelId, month: month),
              const SizedBox(height: Space.sm),
              const _FeeFilterChips(),
            ],
          ),
        ),
        empty: EmptyState(
          // Only the whole month with nobody on it. "Nobody is unpaid this month" is a filter
          // result, not an empty ledger, and keeps the glyph.
          illustration: filter == null ? EmptyArt.payments : null,
          icon: Icons.receipt_long_outlined,
          title: filter == null
              ? 'Nobody on the ledger for ${monthLabel(month)}'
              : 'Nobody is ${filter.label.toLowerCase()} this month',
          detail: filter == null
              ? 'The ledger lists every current resident. Register someone to start it.'
              : 'Try another filter, or a different month.',
        ),
        itemBuilder: (context, row) => _LedgerRow(
          row: row,
          month: month,
          refunds: refunds.forMonth(row.studentId, month),
        ),
      ),
    );
  }
}

/// ‹ October 2026 ›
class _MonthStepper extends ConsumerWidget {
  const _MonthStepper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final month = ref.watch(selectedMonthProvider);
    final current = ref.watch(currentPeriodMonthProvider);
    // One month ahead is allowed — advance rent is ordinary. Further forward is not: a ledger
    // for a month nobody has lived through is a screen with nothing true on it.
    final canGoForward = month.compareTo(_next(current)) < 0;

    return Row(
      children: [
        // The file's only icon button is `bell-icon-container` (4:656): a 32dp raised square
        // at the 8 corner. Material's filledTonal circle in `secondaryContainer` is not a
        // shape this design draws.
        HeaderAction(
          tooltip: 'Previous month',
          icon: Icons.chevron_left_rounded,
          onPressed: () => ref.read(selectedMonthProvider.notifier).step(-1),
        ),
        Expanded(
          child: Column(
            children: [
              Text(monthLabel(month), style: t.textTheme.titleMedium, textAlign: TextAlign.center),
              if (month != current)
                Text(
                  month.compareTo(current) < 0 ? 'Past month' : 'Next month',
                  style: t.textTheme.labelSmall,
                ),
            ],
          ),
        ),
        HeaderAction(
          tooltip: 'Next month',
          icon: Icons.chevron_right_rounded,
          onPressed:
              canGoForward ? () => ref.read(selectedMonthProvider.notifier).step(1) : null,
        ),
      ],
    );
  }

  static String _next(String periodMonth) {
    final parts = periodMonth.split('-');
    return toPeriodMonth(DateTime(int.parse(parts[0]), int.parse(parts[1]) + 1));
  }
}

/// Collected against outstanding, for the month on screen.
///
/// THE SHAPE IS resident-profile.png's two-up: a pair of figure cards side by side, the money
/// already in in a neutral card and the money still owed in a card tinted its own colour, each
/// under a `label-caps` eyebrow. The meter runs the full width underneath, on the design's own
/// `bg-surface-bright` track.
class _MonthSummary extends ConsumerWidget {
  const _MonthSummary({required this.hostelId, required this.month});
  final String hostelId;
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final stats = ref.watch(
      hostelStatsProvider(StatsQuery(hostelId: hostelId, periodMonth: month)),
    );

    return AsyncSection<HostelStats?>(
      value: stats,
      loading: const SkeletonBlock(lines: 1),
      builder: (data) {
        if (data == null) return const SizedBox.shrink();
        final total = data.feesCollected + data.feesPending;
        // Guarded rather than assumed: a month with no residents divides by zero, and a
        // progress bar that reports 100% collected on an empty hostel is a lie.
        final ratio = total <= 0 ? null : (data.feesCollected / total).clamp(0.0, 1.0);
        final owing = data.feesPending > 0;

        return GlassCard(
          padding: const EdgeInsets.all(Space.md),
          semanticLabel: '${money(data.feesCollected)} collected, '
              '${money(data.feesPending)} outstanding',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: 'Collected',
                        value: money(data.feesCollected),
                        tone: NivoraColors.success,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: _Figure(
                        label: 'Outstanding',
                        value: money(data.feesPending),
                        tone: owing ? NivoraColors.error : null,
                        tinted: owing,
                      ),
                    ),
                  ],
                ),
              ),
              if (ratio != null) ...[
                const SizedBox(height: Space.md),
                ClipRRect(
                  borderRadius: Radii.rPill,
                  child: LinearProgressIndicator(
                    value: ratio,
                    // The design's meter: `bg-surface-bright` channel, `bg-primary` fill. The
                    // track used to be a red tint, which drew the eye to the part of the month
                    // that had not happened yet.
                    backgroundColor: t.colorScheme.surfaceBright,
                    valueColor: AlwaysStoppedAnimation(context.tones.success),
                  ),
                ),
              ],
              const SizedBox(height: Space.sm),
              MetaLine([
                (Icons.check_circle_outline_rounded, '${data.studentsPaid} paid'),
                (Icons.schedule_rounded, '${data.studentsUnpaid} still owing'),
              ]),
            ],
          ),
        );
      },
    );
  }
}

/// One half of the two-up: a `label-caps` eyebrow over a `title-md` figure, in a well of its
/// own when the figure carries a meaning.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.tone,
    this.tinted = false,
  });

  final String label;
  final String value;
  final Color? tone;

  /// Tints the whole well, the way the mockup's TOTAL DUES card is tinted coral. Reserved for
  /// the figure that is a call to act.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = tone == null ? null : context.tones.resolve(tone!);
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: tinted && accent != null
            ? context.tones.chipFill(accent)
            : t.colorScheme.surfaceContainer,
        borderRadius: Radii.rControl,
        border: Border.all(
          color: tinted && accent != null
              ? context.tones.chipBorder(accent)
              : t.colorScheme.outlineVariant,
          width: Strokes.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CapsLabel(label, tone: accent, dot: accent != null),
          const SizedBox(height: Space.xxs),
          Text(
            value,
            style: t.textTheme.headlineSmall?.copyWith(color: accent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The compact one-liner on a ledger row. The verb carries the status: `rz_reverse_fee` only
/// moves the ledger for a PROCESSED refund, so a pending one has not changed the figure beside
/// it and must not claim to have.
String _refundLine(RefundInfo r) {
  final amount = money(r.amount);
  final on = r.on;
  if (!r.isSettled) {
    return on == null ? '$amount refund pending' : '$amount refund requested ${shortDate(on)}';
  }
  return on == null ? '$amount refunded' : '$amount refunded ${shortDate(on)}';
}

class _FeeFilterChips extends ConsumerWidget {
  const _FeeFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(feeFilterProvider);
    final notifier = ref.read(feeFilterProvider.notifier);

    // `chips` (4:747). The filter is a NULLABLE status rather than a plain enum, so this
    // builds the row out of [FilterPill] directly instead of going through [FilterBar].
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: Space.xs),
            child: FilterPill(
              label: 'Everyone',
              selected: selected == null,
              onTap: () => notifier.set(null),
            ),
          ),
          for (final status in FeeStatus.values)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: FilterPill(
                label: status.label,
                selected: selected == status,
                onTap: () => notifier.set(status),
              ),
            ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.row, required this.month, this.refunds = const []});
  final FeeLedgerRow row;
  final String month;

  /// This resident's refunds for this month, from `public.payment_refunds`.
  final List<RefundInfo> refunds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tone = toneFor(context, row.status);
    final placement = row.roomNumber == null
        ? 'No bed'
        : row.bedNumber == null
            ? 'Room ${row.roomNumber}'
            : 'Room ${row.roomNumber} · Bed ${row.bedNumber}';

    return TapRow(
      semanticLabel: '${row.fullName}, ${row.status.label}, '
          '${money(row.balance)} outstanding'
          '${refunds.map((r) => ', ${money(r.amount)} '
              '${r.isSettled ? 'refunded' : 'refund pending'}').join()}',
      // The row IS the action. A separate "collect" button would be a second target to hit and
      // a second thing to explain; the only reason to open a ledger row is to take money.
      onTap: () => showRecordPaymentSheet(
        context,
        studentId: row.studentId,
        studentName: row.fullName,
        monthlyFee: row.monthlyFee,
        periodMonth: month,
      ),
      child: Row(
        children: [
          Avatar(name: row.fullName, tone: tone),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.fullName,
                    style: t.textTheme.titleSmall?.copyWith(color: t.colorScheme.onSurface),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xxs / 2),
                Text(placement,
                    style: t.textTheme.bodySmall,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                // ═══ THE WARDEN IS THE ONE WHO GETS ASKED, IN PERSON ═══
                //
                // A refund reaches this screen as a status that has quietly moved from PAID
                // back to PARTLY PAID or UNPAID — indistinguishable, at the desk, from a
                // resident who simply never paid. So the row says it in words, on the resident's
                // own line, where a warden reading the list finds it before the conversation
                // starts rather than during it.
                //
                // [NivoraColors.info] and not the amber the status pill beside it may be
                // wearing: two different facts about the same month must not wear one colour.
                // See [RefundNote] in features/student/widgets/rent.dart for the full reasoning
                // behind the tone; it is the same decision, made once.
                //
                // A pending refund says so in its own words. The warden is the person who will
                // be asked "where is my money", and "instructed" and "gone" are the two
                // different answers to that question.
                for (final r in refunds) ...[
                  const SizedBox(height: Space.xxs / 2),
                  Row(
                    children: [
                      Icon(Icons.assignment_return_rounded,
                          size: IconSize.sm, color: context.tones.info),
                      const SizedBox(width: Space.xxs),
                      Expanded(
                        child: Text(
                          _refundLine(r),
                          style: t.textTheme.bodySmall
                              ?.copyWith(color: context.tones.info),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                row.balance > 0 ? money(row.balance) : money(row.amountPaid),
                style: t.textTheme.titleSmall?.copyWith(
                  color: row.balance > 0 ? context.tones.error : context.tones.success,
                ),
              ),
              const SizedBox(height: Space.xxs),
              StatusPill(status: row.status),
            ],
          ),
          IconButton(
            tooltip: 'Open resident',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => showStudentSheet(context, studentId: row.studentId),
          ),
        ],
      ),
    );
  }
}
