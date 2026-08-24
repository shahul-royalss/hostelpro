library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
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

    return WardenScreen(
      title: 'Collections',
      subtitle: monthLabel(month),
      child: PagedList<FeeLedgerRow>(
        value: ledger,
        onRefresh: () async {
          ref.invalidate(feeLedgerProvider(query));
          ref.invalidate(hostelStatsProvider);
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
          icon: Icons.receipt_long_outlined,
          title: filter == null
              ? 'Nobody on the ledger for ${monthLabel(month)}'
              : 'Nobody is ${filter.label.toLowerCase()} this month',
          detail: filter == null
              ? 'The ledger lists every current resident. Register someone to start it.'
              : 'Try another filter, or a different month.',
        ),
        itemBuilder: (context, row) => _LedgerRow(row: row, month: month),
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
        IconButton.filledTonal(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left_rounded),
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
        IconButton.filledTonal(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right_rounded),
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

        return Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: Radii.rCard,
            border: Border.all(color: t.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('COLLECTED', style: t.textTheme.labelSmall),
                        Text(money(data.feesCollected), style: t.textTheme.headlineMedium),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('OUTSTANDING', style: t.textTheme.labelSmall),
                      Text(
                        money(data.feesPending),
                        style: t.textTheme.titleSmall?.copyWith(
                          color: data.feesPending > 0 ? context.tones.error : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (ratio != null) ...[
                const SizedBox(height: Space.sm),
                ClipRRect(
                  borderRadius: Radii.rPill,
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: Space.xs,
                    // Track = still owed, fill = collected. Both resolved for this theme.
                    backgroundColor: context.tones.chipFill(NivoraColors.error),
                    valueColor: AlwaysStoppedAnimation(context.tones.success),
                  ),
                ),
              ],
              const SizedBox(height: Space.xs),
              Text(
                '${data.studentsPaid} paid · ${data.studentsUnpaid} still owing',
                style: t.textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeeFilterChips extends ConsumerWidget {
  const _FeeFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(feeFilterProvider);
    final notifier = ref.read(feeFilterProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: Space.xs),
            child: ChoiceChip(
              label: const Text('Everyone'),
              selected: selected == null,
              onSelected: (_) => notifier.set(null),
            ),
          ),
          for (final status in FeeStatus.values)
            Padding(
              padding: const EdgeInsets.only(right: Space.xs),
              child: ChoiceChip(
                label: Text(status.label),
                selected: selected == status,
                onSelected: (_) => notifier.set(status),
              ),
            ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.row, required this.month});
  final FeeLedgerRow row;
  final String month;

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
      semanticLabel:
          '${row.fullName}, ${row.status.label}, ${money(row.balance)} outstanding',
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
                    style: t.textTheme.titleMedium,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Space.xxs / 2),
                Text(placement,
                    style: t.textTheme.bodySmall,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
              StatusPill(status: row.status, dense: true),
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
