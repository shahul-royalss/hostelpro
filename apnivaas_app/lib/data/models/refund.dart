/// public.payment_refunds — money that went BACK, one row per refund.
///
/// ═══ WHY A LIST AND NOT A FIGURE ═══
/// A partial refund is the NORMAL case (a resident who overpaid ₹500 on ₹5,000 gets ₹500 back,
/// not ₹5,000), and a month can be refunded more than once. The schema is a child table per
/// refund with a unique index on `razorpay_refund_id` precisely so replaying a webhook cannot
/// double-count — see db/migrations/2026-09-02-payment-refunds.sql. So every screen here takes
/// a `List<RefundInfo>` and draws one line per row. **Nothing in this app adds two refunds
/// together**: two refunds are two facts, and a total the database never computed is a figure
/// this app is not allowed to state.
///
/// ═══ WHICH ROWS ARE TRUE ABOUT MONEY ═══
/// `refund.created`, `refund.processed` and `refund.failed` all land here, out of order, for the
/// same refund — so [status] is the whole difference between "the hostel has instructed a
/// refund" and "the money has left".
///
///   [RefundStatus.processed]  THE MONEY HAS GONE BACK. This is the one that reduced
///                             `fee_payments.amount_paid`, and therefore the one that explains
///                             a bill that moved without the resident doing anything.
///   [RefundStatus.pending]    an instruction exists; nothing has moved yet, on either side.
///                             Worth saying — a resident promised their money back should see
///                             it in flight — but it must never be worded as money returned.
///   [RefundStatus.failed]     nothing happened. The ledger was never moved, so there is
///                             nothing to explain and [visible] drops it.
///
/// ═══ PAISE ═══
/// `amount_paise` is a bigint, like `payment_intents.amount_paise`. [amount] renders it in
/// rupees. That division is a UNIT, not arithmetic on two figures — the no-arithmetic rule this
/// app holds itself to is about never showing a number the database did not hold, and 250000
/// paise and ₹2,500 are the same number in two units.
///
/// `reversed_amount` (rupees, what actually came off the ledger) deliberately is NOT the
/// display figure. It is null while a processed refund is still in the reconciliation queue —
/// the money has left Razorpay and the ledger has not caught up — and in that window the
/// resident's money is gone from the merchant account whatever the ledger says. [amount] is
/// what left. [reversedAmount] is kept for the one screen that ever needs to explain a
/// disagreement between the two.
library;

import 'enums.dart';
import 'parse.dart';

/// public.payment_refund_status
enum RefundStatus implements WireValue {
  /// Razorpay's `created`: instructed, not yet moved.
  pending('pending', 'Refund on its way'),

  /// The money has left the merchant account.
  processed('processed', 'Refunded'),

  /// The instruction died. No money moved.
  failed('failed', 'Refund failed');

  const RefundStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  static RefundStatus? tryParse(String? v) => wireOrNull(RefundStatus.values, v);
}

class RefundInfo {
  const RefundInfo({
    required this.id,
    required this.studentId,
    required this.periodMonth,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.processedAt,
    this.reversedAmount,
    this.reversedAt,
    this.reference,
  });

  /// The columns this app reads. `speed` and `failure_reason` are deliberately absent: the
  /// first is Razorpay's internal routing and the second is written for an operator, not for
  /// the resident it would be shown to.
  static const columns =
      'id, student_id, period_month, amount_paise, status, razorpay_refund_id, '
      'processed_at, reversed_amount, reversed_at, created_at';

  final String id;
  final String studentId;

  /// 'YYYY-MM'. The refund is attached to a MONTH, which is how it finds its fee row: the
  /// schema carries `period_month` on the refund itself rather than making the client walk
  /// `intent_id` back to a `payment_intents` row it may not be reading.
  final String periodMonth;

  /// What went back, in rupees. Always > 0 — the table has a check constraint saying so.
  final double amount;

  final RefundStatus status;

  /// When the money left the merchant account. Null on a pending refund.
  final DateTime? processedAt;

  /// What was subtracted from `fee_payments.amount_paid`, in rupees. Null while a processed
  /// refund is still waiting to be reversed. See the library doc for why this is not [amount].
  final double? reversedAmount;

  /// When the fee ledger actually moved. Null means the money has gone and the ledger has not
  /// caught up yet — a real, reconcilable state, not an error.
  final DateTime? reversedAt;

  /// `razorpay_refund_id`. The string a resident quotes when a bank statement and a ledger
  /// disagree, exactly as `fee_payments.id` is the receipt number.
  final String? reference;

  final DateTime createdAt;

  /// The date to print, and null when there is honestly none.
  ///
  /// `processed_at` for money that has moved; `created_at` for an instruction that has not.
  /// Never a substitute: a pending refund does not get the day it was requested presented as
  /// the day the money arrived, because those are different claims and the second one is the
  /// one a resident would act on.
  DateTime? get on => status == RefundStatus.processed ? processedAt : createdAt;

  /// True once the money has actually left. The rows that explain a moved bill.
  bool get isSettled => status == RefundStatus.processed;

  factory RefundInfo.fromJson(Map<String, dynamic> row) {
    const src = 'payment_refunds';
    return RefundInfo(
      id: reqString(row, src, 'id'),
      studentId: reqString(row, src, 'student_id'),
      periodMonth: reqString(row, src, 'period_month'),
      // bigint paise → rupees. The one unit conversion in this layer; see the library doc.
      amount: reqDouble(row, src, 'amount_paise') / 100,
      status: wireOrThrow(RefundStatus.values, row['status'], src, 'status'),
      processedAt: optTimestamp(row, src, 'processed_at'),
      reversedAmount: optDouble(row, src, 'reversed_amount'),
      reversedAt: optTimestamp(row, src, 'reversed_at'),
      reference: optString(row, 'razorpay_refund_id'),
      createdAt: reqTimestamp(row, src, 'created_at'),
    );
  }
}

/// The refunds a screen holds, addressable by the row they belong to.
///
/// ═══ WHY THE JOIN HAPPENS HERE AND NOT IN SQL ═══
/// The refund migration changed no existing function, so `rpc_fee_ledger` and
/// `rpc_recent_payments` return exactly what they always did. Rather than have four screens
/// each filter a flat list — and get the (student, month) key subtly different in one of them —
/// the list is indexed once, here, and every screen asks the same question the same way.
///
/// ═══ FAILED REFUNDS ARE DROPPED, AND THAT IS NOT HIDING ═══
/// A refund that failed moved no money on either side. There is nothing on the resident's bill
/// for it to explain and nothing for the warden to be asked about; drawing it would be telling
/// four people about an event that did not happen to them. The row is still in the database and
/// still in the audit trail, which is where an operator looks.
class RefundIndex {
  const RefundIndex(this._byKey);

  /// An index over rows that are TRUE ABOUT MONEY — see the class doc.
  ///
  /// Ordered within each key: settled refunds first (they are the ones that explain the bill),
  /// then by date, newest first. A month with two refunds therefore reads top-down in the order
  /// a person would ask about them.
  factory RefundIndex.of(Iterable<RefundInfo> refunds) {
    final byKey = <String, List<RefundInfo>>{};
    for (final r in refunds) {
      if (r.status == RefundStatus.failed) continue;
      byKey.putIfAbsent(_key(r.studentId, r.periodMonth), () => []).add(r);
    }
    for (final list in byKey.values) {
      list.sort((a, b) {
        if (a.isSettled != b.isSettled) return a.isSettled ? -1 : 1;
        return (b.on ?? b.createdAt).compareTo(a.on ?? a.createdAt);
      });
    }
    return RefundIndex(byKey);
  }

  /// Nothing known. What every screen holds while the read is in flight, and what they all hold
  /// forever if the read fails — a refund panel is not worth an error state of its own on a
  /// screen whose subject is the rent.
  static const empty = RefundIndex(<String, List<RefundInfo>>{});

  final Map<String, List<RefundInfo>> _byKey;

  static String _key(String studentId, String periodMonth) => '$studentId $periodMonth';

  /// The refunds against one resident's one month. Empty is the answer for almost every month
  /// in the building, and empty draws nothing.
  List<RefundInfo> forMonth(String studentId, String periodMonth) =>
      _byKey[_key(studentId, periodMonth)] ?? const [];

  bool get isEmpty => _byKey.isEmpty;
}
