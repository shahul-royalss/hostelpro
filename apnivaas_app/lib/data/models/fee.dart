library;

import 'enums.dart';
import 'parse.dart';

/// public.fee_payments — one row per student per month, created on first payment.
///
/// `status` is COMPUTED BY A TRIGGER (app.fee_status_compute) from amount_due and amount_paid.
/// Never send it; it would be overwritten anyway, and disagreeing with the trigger in the
/// client is how a receipt ends up saying "paid" for a part payment.
class FeePayment {
  const FeePayment({
    required this.id,
    required this.hostelId,
    required this.studentId,
    required this.periodMonth,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.paidOn,
    this.mode,
    this.notes,
    this.recordedBy,
  });

  static const columns =
      'id, hostel_id, student_id, period_month, amount_due, amount_paid, status, '
      'paid_on, mode, notes, recorded_by, created_at, updated_at';

  final String id;
  final String hostelId;
  final String studentId;

  /// 'YYYY-MM'. Constrained by a regex in the schema; build it with [toPeriodMonth].
  final String periodMonth;

  /// The rent that was owed for this month — a snapshot of students.monthly_fee at the time,
  /// so a later rent change does not silently rewrite an old month.
  final double amountDue;
  final double amountPaid;
  final FeeStatus status;

  /// Plain `date`. Null only on a row created with no payment at all.
  final DateTime? paidOn;
  final PaymentMode? mode;
  final String? notes;

  /// The staff user who recorded it.
  final String? recordedBy;
  final DateTime createdAt;
  final DateTime updatedAt;


  /// Never negative: an overpayment is not a debt.
  double get balance {
    final remaining = amountDue - amountPaid;
    return remaining > 0 ? remaining : 0;
  }

  factory FeePayment.fromJson(Map<String, dynamic> row) {
    const src = 'fee_payments';
    return FeePayment(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      studentId: reqString(row, src, 'student_id'),
      periodMonth: reqString(row, src, 'period_month'),
      amountDue: reqDouble(row, src, 'amount_due'),
      amountPaid: reqDouble(row, src, 'amount_paid'),
      status: wireOrThrow(FeeStatus.values, row['status'], src, 'status'),
      paidOn: optDate(row, src, 'paid_on'),
      mode: PaymentMode.tryParse(optString(row, 'mode')),
      notes: optString(row, 'notes'),
      recordedBy: optString(row, 'recorded_by'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}

/// One row of public.rpc_fee_ledger(hostel, 'YYYY-MM').
///
/// Not the same thing as a [FeePayment]. The ledger is every non-vacated resident LEFT JOINed
/// to that month's payment row, so residents who have paid nothing appear too — with
/// amount_due defaulted to their monthly fee and status 'unpaid'. Listing fee_payments instead
/// would show only the people who have already paid, which is the opposite of what a
/// collections screen is for.
class FeeLedgerRow {
  const FeeLedgerRow({
    required this.studentId,
    required this.fullName,
    required this.phone,
    required this.monthlyFee,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    this.photoUrl,
    this.roomNumber,
    this.bedNumber,
    this.paidOn,
    this.mode,
  });

  final String studentId;
  final String fullName;
  final String phone;

  /// Storage key. Null unless a photo was uploaded at registration.
  final String? photoUrl;

  /// Null while the resident has no room assigned.
  final String? roomNumber;
  final int? bedNumber;

  final double monthlyFee;

  /// coalesce(fee_payments.amount_due, students.monthly_fee) — see the class doc.
  final double amountDue;
  final double amountPaid;
  final FeeStatus status;
  final DateTime? paidOn;
  final PaymentMode? mode;


  double get balance {
    final remaining = amountDue - amountPaid;
    return remaining > 0 ? remaining : 0;
  }

  factory FeeLedgerRow.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_fee_ledger';
    return FeeLedgerRow(
      studentId: reqString(row, src, 'student_id'),
      fullName: reqString(row, src, 'full_name'),
      phone: reqString(row, src, 'phone'),
      photoUrl: optString(row, 'photo_url'),
      roomNumber: optString(row, 'room_number'),
      bedNumber: optInt(row, src, 'bed_number'),
      monthlyFee: reqDouble(row, src, 'monthly_fee'),
      amountDue: reqDouble(row, src, 'amount_due'),
      amountPaid: reqDouble(row, src, 'amount_paid'),
      status: wireOrThrow(FeeStatus.values, row['status'], src, 'status'),
      paidOn: optDate(row, src, 'paid_on'),
      mode: PaymentMode.tryParse(optString(row, 'mode')),
    );
  }
}

/// One row of public.rpc_recent_payments(hostel) — money that actually came in, with the name
/// of the person who took it.
///
/// WHY THIS IS NOT A [FeePayment]. A payment row on its own answers "how does this month
/// stand"; the owner's question is "who paid, and who took it", and neither name is on
/// `fee_payments` — `student_id` and `recorded_by` are uuids. The RPC does both joins under a
/// definer because a warden cannot read an owner's `users` row, so half of `recordedByName`
/// would otherwise come back null for rows an owner recorded themselves.
///
/// `amountPaid` IS THE MONTH'S TOTAL, NOT THE LAST HANDOVER. `wd_record_payment` upserts and
/// ADDS, so one row is one month per resident and it carries the cumulative figure. A list of
/// these is a list of months that have received money, most recently touched first — not a
/// transaction log, because the schema does not keep one.
class RecentPayment {
  const RecentPayment({
    required this.id,
    required this.studentId,
    required this.fullName,
    required this.periodMonth,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    required this.recordedAt,
    this.roomNumber,
    this.bedNumber,
    this.paidOn,
    this.mode,
    this.notes,
    this.recordedBy,
    this.recordedByName,
    this.recordedByRole,
  });

  final String id;
  final String studentId;

  /// The resident's name, from public.students.
  final String fullName;

  /// Null while the resident has no room assigned.
  final String? roomNumber;
  final int? bedNumber;

  /// 'YYYY-MM'.
  final String periodMonth;
  final double amountDue;

  /// Everything received against this month, cumulative. See the class doc.
  final double amountPaid;
  final FeeStatus status;

  /// The day the money changed hands, as the desk entered it. Can be backdated, which is why
  /// it is not what the list is ordered by.
  final DateTime? paidOn;
  final PaymentMode? mode;
  final String? notes;

  /// The staff account that recorded it, and its name — null for a row whose recorder has
  /// since been deleted, which is a fact worth showing rather than papering over.
  final String? recordedBy;
  final String? recordedByName;

  /// 'warden' | 'owner' | … — `users.role` as Postgres stores it. Kept as the WIRE value
  /// because this layer does not import `UserRole` (it lives in core/auth/session.dart, which
  /// no model may depend on); the screen that prints it owns the label.
  final String? recordedByRole;

  /// `fee_payments.updated_at` — when the desk last touched this month. The list's own order.
  final DateTime recordedAt;


  double get balance {
    final remaining = amountDue - amountPaid;
    return remaining > 0 ? remaining : 0;
  }

  factory RecentPayment.fromJson(Map<String, dynamic> row) {
    const src = 'rpc_recent_payments';
    return RecentPayment(
      id: reqString(row, src, 'id'),
      studentId: reqString(row, src, 'student_id'),
      fullName: reqString(row, src, 'full_name'),
      roomNumber: optString(row, 'room_number'),
      bedNumber: optInt(row, src, 'bed_number'),
      periodMonth: reqString(row, src, 'period_month'),
      amountDue: reqDouble(row, src, 'amount_due'),
      amountPaid: reqDouble(row, src, 'amount_paid'),
      status: wireOrThrow(FeeStatus.values, row['status'], src, 'status'),
      paidOn: optDate(row, src, 'paid_on'),
      mode: PaymentMode.tryParse(optString(row, 'mode')),
      notes: optString(row, 'notes'),
      recordedBy: optString(row, 'recorded_by'),
      recordedByName: optString(row, 'recorded_by_name'),
      recordedByRole: optString(row, 'recorded_by_role'),
      recordedAt: reqTimestamp(row, src, 'recorded_at'),
    );
  }
}
