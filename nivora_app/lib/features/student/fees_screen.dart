library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../shared/illustrations.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/rent.dart';

/// Rent: what is owed this month, every month that came before, and the receipt for each.
///
/// READS
///   public.rpc_fee_ledger  — this month, via `myRentThisMonthProvider`. The only source that
///                            answers for a month with no payment row yet (see that provider).
///   public.fee_payments    — the history, via `studentFeeHistoryProvider`. The select policy
///                            admits `student_id = app.current_student_id()`, so this is the
///                            resident's own history and no one else's.
///   public.payment_refunds — money that went BACK, via `studentRefundsProvider`. A child table
///                            rather than a column, because a month can be refunded twice; the
///                            same select-policy shape, so again their own rows only.
///
/// ═══ WHY THE REFUND READ CANNOT BLOCK THIS SCREEN ═══
/// `rz_reverse_fee` subtracts a processed refund from `fee_payments.amount_paid`, and the
/// status trigger then recomputes PAID into PARTLY PAID. A resident seeing that with no
/// explanation concludes the app lost their money — which is the entire reason the refund read
/// exists. But it is a THIRD read decorating the first two, so it is taken as
/// `.value ?? RefundIndex.empty` and never given a loading state, a retry or an error of its
/// own: if it fails, this screen is exactly the screen it was before the feature shipped. A
/// rent figure must not be unavailable because a qualifier on it was.
///
/// ═══ WHERE THE RECEIPT COMES FROM ═══
/// A warden takes cash at the desk, `wd_record_payment` writes a `fee_payments` row, and the
/// resident's side of that is this screen. The status word flipping to "Paid" is not enough on
/// its own — the owner asked for a receipt the resident can actually see — so the row itself
/// travels down to the cards: the rent card gets THIS month's row and every history tile is its
/// own. Both hand it to `Receipt.forFeePayment`, which refuses to build anything from a month
/// with nothing received against it, and both open the same printed document with the same
/// receipt number the warden's copy carries.
///
/// THE LEDGER ROW CANNOT DO THIS AND IS NOT ASKED TO. `rpc_fee_ledger` returns figures without a
/// payment id; a receipt built from it would have no number to look up in a dispute, which is
/// the one thing a receipt is for.
///
/// A RESIDENT WITH NOTHING PAID HAS AN EMPTY HISTORY AND A NON-ZERO BALANCE AT THE SAME TIME.
/// That is not a contradiction and the screen must not present it as one: `fee_payments` only
/// gains a row when money is recorded. Verified against the live project — a resident on
/// ₹6,200 with no payments returns zero history rows and a ledger row reading
/// `amount_due 6200, amount_paid 0, status unpaid`.
///
/// AND THE HISTORY IS PERMANENT. Nothing in `app.apply_retention()` names `fee_payments`, so no
/// month ever ages out of this list server-side. This screen used to shorten it anyway — one
/// page, then a line telling the resident to ask their warden for anything older — which made
/// the client the only place a permanent record got cut off. It pages now.
class StudentFeesScreen extends StatelessWidget {
  const StudentFeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResidentBuilder(builder: (context, ref, me) => _Fees(me: me));
  }
}

class _Fees extends ConsumerWidget {
  const _Fees({required this.me});
  final Student me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final month = ref.watch(currentPeriodMonthProvider);
    final rent = ref.watch(myRentThisMonthProvider);
    final history = ref.watch(studentFeeHistoryProvider(me.id));
    // See the class doc: decoration, never a gate.
    final refunds = ref.watch(studentRefundsProvider(me.id)).value ?? RefundIndex.empty;

    // `.value` and not `.requireValue`: this is a read of a SECOND provider used to decorate
    // the first, and every state it can be in — in flight, failed, empty — means the same
    // thing here, which is that the rent card has no receipt to offer yet. The history section
    // below owns saying what actually happened to that read.
    final thisMonth = _rowFor(history.value, month);

    return RefreshIndicator(
      onRefresh: () {
        refreshStudentData(ref);
        return awaitStudentRefresh(context, ref);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xxxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AsyncSection<FeeLedgerRow?>(
            value: rent,
            onRetry: () => ref.invalidate(myRentThisMonthProvider),
            loading: const SkeletonCard(lines: 4),
            builder: (row) => RentCard(
              periodMonth: month,
              row: row,
              payment: thisMonth,
              payerName: me.fullName,
              refunds: refunds.forMonth(me.id, month),
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeading(
            title: 'Payment history',
            // Not a promise this screen invented: no retention step touches fee_payments, so a
            // month recorded here stays here.
            caption: 'Every month the hostel has recorded against your name. '
                'Months are kept — nothing drops off as it ages.',
            // The money domain's green on the receipt glyph — the ledger's own colour, and the
            // one the Fees tab lights up in. The rows below keep their STATUS tones.
            domain: NivoraDomain.money,
            icon: Icons.receipt_long_rounded,
          ),

          AsyncSection<PagedResult<FeePayment>>(
            value: history,
            onRetry: () => ref.invalidate(studentFeeHistoryProvider(me.id)),
            loading: const Column(
              children: [
                SkeletonCard(lines: 2),
                SizedBox(height: Space.xs),
                SkeletonCard(lines: 2),
              ],
            ),
            builder: (page) {
              if (page.isEmpty) {
                return const EmptyNote(
                  illustration: EmptyArt.payments,
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing recorded yet',
                  message: 'A month appears here once the hostel records a payment for it. '
                      'Until then, what you owe is shown above.',
                );
              }
              return Column(
                children: [
                  for (final payment in page.items) ...[
                    FeePaymentTile(
                      payment: payment,
                      payerName: me.fullName,
                      refunds: refunds.forMonth(me.id, payment.periodMonth),
                    ),
                    const SizedBox(height: Space.xs),
                  ],
                  // The rest of the record, on request. This list grows by one row a month
                  // forever and a resident of two years has more than one page of it; the
                  // screen used to apologise for that in a sentence and now goes and gets it.
                  if (page.hasMore)
                    MoreMonths(
                      onLoadMore: () =>
                          ref.read(studentFeeHistoryProvider(me.id).notifier).loadMore(),
                    )
                  else if (page.items.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Text(
                        'That is every month on your record.',
                        style: t.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// The resident's own `fee_payments` row for [periodMonth], or null if this device has not
  /// got it. A loop rather than a `firstWhere`: null is an ordinary answer here — the first
  /// month a resident lives in the building has no payment row until the desk records one —
  /// and `firstWhere` would need a sentinel to say so.
  static FeePayment? _rowFor(PagedResult<FeePayment>? history, String periodMonth) {
    for (final row in history?.items ?? const <FeePayment>[]) {
      if (row.periodMonth == periodMonth) return row;
    }
    return null;
  }
}
