library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/models.dart';
import '../../../data/providers.dart';
import '../../common/refresh.dart';
import '../../../shared/clay/clay.dart'
    show
        ClayIcons,
        ListGroup,
        ListRow,
        ListRowAmount,
        StatTile,
        StatTileStyle,
        StatusTone,
        TileSkeleton;
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
///
/// THE MONTH LIVES IN THE HEADER. Its name is the header's second line and the two arrows that
/// step it sit beside it, so the month a warden is reading and the control that changes it are
/// one object — and the page below starts with the money, not with a row of controls.
class WardenFeesScreen extends ConsumerWidget {
  const WardenFeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostelId = ref.watch(currentHostelIdProvider);
    if (hostelId == null) {
      return const WardenScreen(
        title: 'Collections',
        child: WardenEmptyState(
          icon: Icons.payments_rounded,
          title: 'No hostel on this account',
          detail: 'A warden is attached to one hostel. Ask the owner to check the assignment.',
        ),
      );
    }

    final month = ref.watch(selectedMonthProvider);
    final current = ref.watch(currentPeriodMonthProvider);
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

    // One month ahead is allowed — advance rent is ordinary. Further forward is not: a ledger
    // for a month nobody has lived through is a screen with nothing true on it.
    final canGoForward = month.compareTo(_next(current)) < 0;

    return WardenScreen(
      title: 'Collections',
      subtitle: month == current
          ? monthLabel(month)
          : '${monthLabel(month)} · ${month.compareTo(current) < 0 ? 'past month' : 'next month'}',
      actions: [
        HeaderAction(
          tooltip: 'Previous month',
          icon: Icons.chevron_left_rounded,
          onPressed: () => ref.read(selectedMonthProvider.notifier).step(-1),
        ),
        HeaderAction(
          tooltip: 'Next month',
          icon: Icons.chevron_right_rounded,
          onPressed:
              canGoForward ? () => ref.read(selectedMonthProvider.notifier).step(1) : null,
        ),
      ],
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
          padding: const EdgeInsets.only(bottom: Space.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MonthSummary(hostelId: hostelId, month: month),
              const SizedBox(height: Space.md),
              const _FeeFilterChips(),
            ],
          ),
        ),
        empty: WardenEmptyState(
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

  static String _next(String periodMonth) {
    final parts = periodMonth.split('-');
    return toPeriodMonth(DateTime(int.parse(parts[0]), int.parse(parts[1]) + 1));
  }
}

/// Where the month on screen stands: what has come in, how much of the billing that is, and
/// what is still owed.
///
/// The clay hero tile — forest, the figure in white, the gold bar for the share collected — the
/// same object as the home screen's "Collected" tile, so the two read as one fact seen from two
/// places. Under it, the two head-counts in words: how many have paid and how many still owe.
class _MonthSummary extends ConsumerWidget {
  const _MonthSummary({required this.hostelId, required this.month});
  final String hostelId;
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(
      hostelStatsProvider(StatsQuery(hostelId: hostelId, periodMonth: month)),
    );

    return AsyncSection<HostelStats?>(
      value: stats,
      loading: const TileSkeleton(semanticLabel: 'Loading the month'),
      builder: (data) {
        if (data == null) return const SizedBox.shrink();
        final total = data.feesCollected + data.feesPending;
        // Guarded rather than assumed: a month with no residents divides by zero, and a
        // progress bar that reports 100% collected on an empty hostel is a lie.
        final ratio = total <= 0 ? null : (data.feesCollected / total).clamp(0.0, 1.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatTile(
              style: StatTileStyle.hero,
              icon: ClayIcons.money,
              label: 'Collected in ${monthName(month)}',
              value: money(data.feesCollected),
              // The percentage is in words as well as in the bar: a bar alone is a shape, and
              // a screen reader cannot hear a shape.
              caption: ratio == null
                  ? 'Nothing billed yet'
                  : data.feesPending > 0
                      ? '${(ratio * 100).round()}% collected · '
                          '${money(data.feesPending)} outstanding'
                      : 'Everyone has paid',
              progress: ratio,
            ),
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xxs),
              child: MetaLine([
                (Icons.check_circle_outline_rounded, '${data.studentsPaid} paid'),
                (Icons.schedule_rounded, '${data.studentsUnpaid} still owing'),
              ]),
            ),
          ],
        );
      },
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

    // The filter is a NULLABLE status rather than a plain enum, so this builds the row out of
    // [FilterPill] directly instead of going through [FilterBar].
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

/// One resident's month: their initials, where they sleep, and the money — the balance in red
/// while there is one, what they paid in green once there is not — with the state as a chip
/// under it.
///
/// A CARD OF ITS OWN, like every row on the warden's lists, and the resident's refunds for the
/// month as a footnote inside the same card under a hairline: the refund belongs to this row,
/// not to the list.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.row, required this.month, this.refunds = const []});
  final FeeLedgerRow row;
  final String month;

  /// This resident's refunds for this month, from `public.payment_refunds`.
  final List<RefundInfo> refunds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final placement = row.roomNumber == null
        ? 'No bed'
        : row.bedNumber == null
            ? 'Room ${row.roomNumber}'
            : 'Room ${row.roomNumber} · Bed ${row.bedNumber}';
    final owes = row.balance > 0;

    return ListGroup(
      children: [
        ListRow(
          avatarName: row.fullName,
          title: row.fullName,
          subtitle: placement,
          semanticLabel: '${row.fullName}, $placement, ${row.status.label}, '
              '${money(row.balance)} outstanding'
              '${refunds.map((r) => ', ${money(r.amount)} '
                  '${r.isSettled ? 'refunded' : 'refund pending'}').join()}',
          // The row IS the action. A separate "collect" button would be a second target to hit
          // and a second thing to explain; the only reason to open a ledger row is to take
          // money.
          onTap: () => showRecordPaymentSheet(
            context,
            studentId: row.studentId,
            studentName: row.fullName,
            monthlyFee: row.monthlyFee,
            periodMonth: month,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListRowAmount(
                amount: owes ? money(row.balance) : money(row.amountPaid),
                status: row.status.label,
                tone: statusToneOf(row.status),
                amountTone: owes ? StatusTone.error : StatusTone.success,
              ),
              // The resident, one tap away from the money they owe — a person glyph rather than
              // a chevron, because the row itself already opens something else.
              IconButton(
                tooltip: 'Open resident',
                icon: const Icon(Icons.person_outline_rounded),
                color: t.colorScheme.onSurfaceVariant,
                onPressed: () => showStudentSheet(context, studentId: row.studentId),
              ),
            ],
          ),
        ),
        // ═══ THE WARDEN IS THE ONE WHO GETS ASKED, IN PERSON ═══
        //
        // A refund reaches this screen as a status that has quietly moved from PAID back to
        // PARTLY PAID or UNPAID — indistinguishable, at the desk, from a resident who simply
        // never paid. So the row says it in words, in the resident's own card, where a warden
        // reading the list finds it before the conversation starts rather than during it.
        //
        // [ApnivaasColors.info] and not the amber the status chip beside it may be wearing: two
        // different facts about the same month must not wear one colour. See [RefundNote] in
        // features/student/widgets/rent.dart for the full reasoning behind the tone; it is the
        // same decision, made once.
        //
        // A pending refund says so in its own words. The warden is the person who will be
        // asked "where is my money", and "instructed" and "gone" are the two different answers
        // to that question.
        if (refunds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in refunds)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.hair),
                    child: Row(
                      children: [
                        Icon(Icons.assignment_return_rounded,
                            size: IconSize.sm, color: context.tones.info),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: Text(
                            _refundLine(r),
                            style: t.textTheme.bodySmall?.copyWith(color: context.tones.info),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
