library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import 'pay_rent_sheet.dart';
import 'student_providers.dart';
import 'widgets/common.dart';
import 'widgets/rent.dart';

/// Rent: what is owed this month, and every month that came before.
///
/// READS
///   public.rpc_fee_ledger  — this month, via `myRentThisMonthProvider`. The only source that
///                            answers for a month with no payment row yet (see that provider).
///   public.fee_payments    — the history, via `studentFeeHistoryProvider`. The select policy
///                            admits `student_id = app.current_student_id()`, so this is the
///                            resident's own history and no one else's.
///
/// A RESIDENT WITH NOTHING PAID HAS AN EMPTY HISTORY AND A NON-ZERO BALANCE AT THE SAME TIME.
/// That is not a contradiction and the screen must not present it as one: `fee_payments` only
/// gains a row when money is recorded. Verified against the live project — a resident on
/// ₹6,200 with no payments returns zero history rows and a ledger row reading
/// `amount_due 6200, amount_paid 0, status unpaid`.
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

    return RefreshIndicator(
      onRefresh: () async {
        refreshStudentData(ref);
        await awaitStudentRefresh(ref);
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
              onPay: row == null
                  ? null
                  : () => showPayRentSheet(context, periodMonth: month, rent: row),
            ),
          ),

          const SizedBox(height: Space.xl),
          const SectionHeading(
            title: 'Payment history',
            caption: 'Every month the hostel has recorded against your name.',
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
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing recorded yet',
                  message: 'A month appears here once the hostel records a payment for it. '
                      'Until then, what you owe is shown above.',
                  tone: NivoraColors.textMuted,
                );
              }
              return Column(
                children: [
                  for (final payment in page.items) ...[
                    FeePaymentTile(payment: payment),
                    const SizedBox(height: Space.xs),
                  ],
                  // Said out loud rather than silently truncated. This list grows by one row a
                  // month forever, and a resident of three years has thirty-six of them.
                  if (page.hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Text(
                        'Showing your most recent ${page.items.length} months. '
                        'Ask your warden for anything older.',
                        style: t.textTheme.bodySmall,
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
}
