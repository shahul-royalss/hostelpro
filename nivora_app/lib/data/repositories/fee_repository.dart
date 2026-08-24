library;

import '../models/models.dart';
import 'repository.dart';

/// Rent: what is owed, what came in.
///
/// TABLES: public.fee_payments.
/// RPCs:   public.rpc_fee_ledger(), public.wd_record_payment().
final class FeeRepository extends Repository {
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
  Future<FeePayment> recordPayment({
    required String studentId,
    required String periodMonth,
    required double amount,
    required PaymentMode mode,
    DateTime? paidOn,
    String? notes,
  }) =>
      guard(() async {
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
      });
}
