library;

import '../models/models.dart';
import 'repository.dart';

/// What a warden does with money at the desk, as an INTERFACE.
///
/// TYPED SEPARATELY FROM THE REPOSITORY, for the same reason `StudentRegistrations` is (see
/// warden_repository.dart): these two are the writes where the interesting states are all
/// refusals from Postgres — a resident who has checked out, a month with nothing to correct, a
/// figure above the schema's ceiling — and holding those down in `flutter test` needs a fake in
/// the slot. Every read below stays on the concrete [FeeRepository]; a test overrides the
/// provider that returns it.
abstract interface class RentDesk {
  /// Record money handed over at the desk. ADDS to whatever the month already has.
  Future<FeePayment> recordPayment({
    required String studentId,
    required String periodMonth,
    required double amount,
    required PaymentMode mode,
    DateTime? paidOn,
    String? notes,
  });

  /// SET what the month has received, because the last entry was wrong. Not a payment.
  Future<FeePayment> correctPayment({
    required String studentId,
    required String periodMonth,
    required double amountPaid,
    PaymentMode? mode,
    DateTime? paidOn,
    String? notes,
  });
}

/// Rent: what is owed, what came in.
///
/// TABLES: public.fee_payments.
/// RPCs:   public.rpc_fee_ledger(), public.rpc_recent_payments(),
///         public.wd_record_payment(), public.wd_correct_payment().
final class FeeRepository extends Repository implements RentDesk {
  const FeeRepository(super.db);

  /// The collections list for a month: every current resident, paid or not.
  ///
  /// USE THIS, NOT a select on fee_payments, for anything a warden collects money from.
  /// fee_payments only has rows for people who have already paid something — listing it would
  /// show a perfect collection rate on the first of the month, when in fact nobody has paid.
  /// The RPC left-joins from students, so the defaulters are the rows with status 'unpaid'.
  ///
  /// PAGINATED. `.range()` on an RPC is applied by PostgREST to the function's result set, so
  /// this pages the ledger without the function running once per row.
  Future<PagedResult<FeeLedgerRow>> ledger({
    required String hostelId,
    required String periodMonth,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
    FeeStatus? status,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        var query = db.rpc('rpc_fee_ledger', params: {
          'p_hostel_id': hostelId,
          'p_period_month': periodMonth,
        });
        if (status != null) query = query.eq('status', status.wire);

        final data = await query.range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rpcRows(data, 'rpc_fee_ledger')
              .map(FeeLedgerRow.fromJson)
              .toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  /// A resident's payment history, most recent month first.
  ///
  /// Paginated: this grows by one row a month forever, and a resident who has been in the
  /// building three years has thirty-six.
  Future<PagedResult<FeePayment>> forStudent({
    required String studentId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        final rows = await db
            .from('fee_payments')
            .select(FeePayment.columns)
            .eq('student_id', studentId)
            // period_month is 'YYYY-MM', so lexical order IS chronological order. That is why
            // the column is text with a regex constraint rather than a date.
            .order('period_month', ascending: false)
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rows.map(FeePayment.fromJson).toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  /// One resident's row for one month, if it exists yet.
  Future<FeePayment?> forMonth({
    required String studentId,
    required String periodMonth,
  }) =>
      guard(() async {
        // A null from here is drawn as a sentence about the reader ("not visible",
        // "belongs to another hostel", "no record for this account"). That sentence is
        // earned only when a live credential asked — a dead session makes this an
        // anonymous read whose null means nothing. See Repository.requireLiveSession.
        requireLiveSession('fee_payments.forMonth');
        final row = await db
            .from('fee_payments')
            .select(FeePayment.columns)
            .eq('student_id', studentId)
            .eq('period_month', periodMonth)
            .maybeSingle();
        return row == null ? null : FeePayment.fromJson(row);
      });

  /// Record a payment, or top up a part payment already recorded.
  ///
  /// Goes through wd_record_payment because the upsert is not expressible safely from here:
  /// the function ADDS to amount_paid on conflict rather than replacing it, snapshots the
  /// student's current monthly_fee as amount_due, and refuses a payment for someone who has
  /// checked out. An INSERT from the client would need a read-then-write and would lose a
  /// second cashier's payment made in between.
  ///
  /// Server-side refusals arrive as [InvalidInputFailure] carrying the database's own wording
  /// ("Amount must be greater than zero", "That student has been checked out"), which is
  /// already written for the person standing at the desk.
  @override
  Future<FeePayment> recordPayment({
    required String studentId,
    required String periodMonth,
    required double amount,
    required PaymentMode mode,
    DateTime? paidOn,
    String? notes,
  }) =>
      guardWrite(() async {
        final data = await db.rpc('wd_record_payment', params: {
          'p_student_id': studentId,
          'p_period_month': periodMonth,
          'p_amount': amount,
          'p_mode': mode.wire,
          if (paidOn != null) 'p_paid_on': toDateWire(paidOn),
          'p_notes': ?notes,
        });
        // Declared `returns public.fee_payments` — a composite, so one object rather than an
        // array. Getting this wrong is a runtime-only failure, which is why it is asserted.
        return FeePayment.fromJson(rpcObject(data, 'wd_record_payment'));
      }, unresolved: 'Open this resident\'s payments for that month before entering it again '
          '— a second entry ADDS to what is already recorded rather than replacing it, so they '
          'would be credited twice.');

  /// Correct what a month has received, when the last entry was wrong.
  ///
  /// SETS, WHERE [recordPayment] ADDS — and that difference is the whole reason this exists.
  /// wd_record_payment is an upsert that tops up, which is right for a second instalment and
  /// useless for a typo: a warden who keys ₹7,000 instead of ₹700 cannot subtract, and entering
  /// it again only makes the figure worse. [amountPaid] is what the month SHOULD say, in total.
  ///
  /// ZERO IS A LEGITIMATE CORRECTION and the server treats it as one: it clears `paid_on` and
  /// `mode` with the amount, because a month that received nothing was not paid on a day by a
  /// method. That is how a payment recorded against the wrong resident is undone.
  ///
  /// The server refuses a month with no row at all ("There is nothing recorded for that month
  /// to correct."), a negative total, and anything above the schema's ₹1,00,00,000 ceiling —
  /// each with wording already written for the person at the desk. It also writes an audit row
  /// carrying the figure before and after, which no other write in this app does.
  ///
  /// NOT unresolved-safe in the way a payment is: re-sending the same correction is harmless
  /// precisely because it sets rather than adds, so the `unresolved` sentence says so.
  @override
  Future<FeePayment> correctPayment({
    required String studentId,
    required String periodMonth,
    required double amountPaid,
    PaymentMode? mode,
    DateTime? paidOn,
    String? notes,
  }) =>
      guardWrite(() async {
        final data = await db.rpc('wd_correct_payment', params: {
          'p_student_id': studentId,
          'p_period_month': periodMonth,
          'p_amount_paid': amountPaid,
          if (mode != null) 'p_mode': mode.wire,
          if (paidOn != null) 'p_paid_on': toDateWire(paidOn),
          'p_notes': ?notes,
        });
        return FeePayment.fromJson(rpcObject(data, 'wd_correct_payment'));
      }, unresolved: 'Check the resident\'s payments for that month. A correction SETS the '
          'total rather than adding to it, so sending the same one twice is safe.');

  /// Refunds against one RESIDENT — every month, because their history screen shows every
  /// month. public.payment_refunds.
  ///
  /// ═══ WHY THIS IS A SEPARATE READ AND NOT A COLUMN ═══
  /// The refund migration changed no existing function, so `rpc_fee_ledger` and
  /// `rpc_recent_payments` return exactly what they always did, and `fee_payments` grew no
  /// column. A refund is a child row — one per refund, keyed by `razorpay_refund_id`, because a
  /// month can be refunded twice and a single column cannot hold two figures idempotently. So
  /// the fee rows and the refunds are two reads that a [RefundIndex] puts back together.
  ///
  /// ═══ NOT PAGINATED, DELIBERATELY ═══
  /// The fee history IS paginated — it grows by a row a month forever. Refunds do not: they are
  /// rare by construction (they exist only for online payments, and only where something went
  /// wrong enough to send money back), and a resident with more than a handful has a problem
  /// this list is the smallest part of. Paging them would mean a page of refunds that did not
  /// line up with the page of months on screen, which is the one thing this read must not do.
  ///
  /// RLS scopes this to the caller: `payment_refunds_select` allows a resident their own rows
  /// and a warden or owner their hostel's. The `.eq()` is there so the server does less work.
  Future<List<RefundInfo>> refundsForStudent(String studentId) => guard(() async {
        final rows = await db
            .from('payment_refunds')
            .select(RefundInfo.columns)
            .eq('student_id', studentId)
            .order('created_at', ascending: false)
            .limit(_refundCeiling);
        return rows.map(RefundInfo.fromJson).toList(growable: false);
      });

  /// Refunds against one HOSTEL. [periodMonth] narrows it to one month.
  ///
  /// TWO CALLERS, TWO SHAPES, ON PURPOSE. The warden's collections list is one month at a time
  /// and passes it; the owner's "who paid" is a running list that walks backwards through
  /// months as it pages, so it asks for the hostel's refunds outright. Both are served by
  /// `payment_refunds_hostel_idx (hostel_id, created_at desc)`.
  Future<List<RefundInfo>> refundsForHostel({
    required String hostelId,
    String? periodMonth,
  }) =>
      guard(() async {
        var query =
            db.from('payment_refunds').select(RefundInfo.columns).eq('hostel_id', hostelId);
        if (periodMonth != null) query = query.eq('period_month', periodMonth);
        final rows =
            await query.order('created_at', ascending: false).limit(_refundCeiling);
        return rows.map(RefundInfo.fromJson).toList(growable: false);
      });

  /// A ceiling rather than a page. If a hostel ever genuinely exceeds this in one month the
  /// screen is not the problem, but an unbounded read on a screen that draws one line per row
  /// is — so the query is bounded and the bound is far above any real month.
  static const _refundCeiling = 500;

  /// Who paid, most recently recorded first. public.rpc_recent_payments.
  ///
  /// THE OWNER'S QUESTION, AND IT CANNOT BE ANSWERED FROM fee_payments ALONE: that table holds
  /// `student_id` and `recorded_by` as uuids, and the `users` row behind the second one is not
  /// readable to every role that needs the name (an owner's account is not attached to the
  /// warden's hostel). The RPC does both joins under a definer and refuses, rather than
  /// returning nothing, to anyone who may not see a hostel's money — so an empty page here
  /// means "nobody has paid yet", never "you were not allowed to ask".
  ///
  /// PAGINATED. One row per resident per month that received money; a full building over a year
  /// is thousands.
  Future<PagedResult<RecentPayment>> recentPayments({
    required String hostelId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        final data = await db
            .rpc('rpc_recent_payments', params: {'p_hostel_id': hostelId})
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rpcRows(data, 'rpc_recent_payments')
              .map(RecentPayment.fromJson)
              .toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });
}
