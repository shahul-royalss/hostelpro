/// UPI payments straight to the owner (docs/round3-api.md §9).
///
/// The app checks formats only to help the person type; the server checks them again, and
/// a claim is only ever marked paid by a warden or the owner.
library;

import 'json_read.dart';

final _vpa = RegExp(r'^[a-z0-9][a-z0-9._-]{1,254}@[a-z][a-z0-9.-]{1,63}$');
final _utr = RegExp(r'^[A-Z0-9]{10,22}$');

/// Lower-cased with every space removed, as the server stores it.
String normalizeVpa(String raw) => raw.replaceAll(RegExp(r'\s'), '').toLowerCase();

/// Null when [raw] is a valid UPI ID, else the server's sentence.
String? vpaError(String raw) =>
    _vpa.hasMatch(normalizeVpa(raw)) ? null : 'Enter a valid UPI ID, like name@okhdfcbank.';

String? payeeNameError(String raw) {
  final n = raw.trim().length;
  return n >= 2 && n <= 80 ? null : 'Enter the payee name as your UPI app shows it.';
}

/// Upper-cased with every space removed, as the server stores it.
String normalizeUtr(String raw) => raw.replaceAll(RegExp(r'\s'), '').toUpperCase();

String? utrError(String raw) => _utr.hasMatch(normalizeUtr(raw))
    ? null
    : 'Enter the UTR / transaction ID from your UPI app (usually 12 digits).';

/// `upi://pay?...` with %20 for spaces (some UPI apps show a literal '+').
Uri buildUpiUri({
  required String vpa,
  required String payeeName,
  required double amount,
  required String note,
  required String ref,
}) {
  String e(String s) => Uri.encodeComponent(s);
  final tn = note.length > 60 ? note.substring(0, 60) : note;
  return Uri.parse('upi://pay?pa=${e(vpa)}&pn=${e(payeeName)}&am=${amount.toStringAsFixed(2)}'
      '&cu=INR&tn=${e(tn)}&tr=${e(ref)}');
}

/// `hostel_upi_settings` / `ow_set_upi_settings`.
class UpiSettings {
  const UpiSettings({
    required this.hostelId,
    required this.vpa,
    required this.payeeName,
    this.hostelName,
  });

  final String hostelId;
  final String vpa;
  final String payeeName;
  final String? hostelName;

  static UpiSettings? tryParse(Object? data) {
    final row = jOne(data);
    if (row == null) return null;
    final id = jStr(row, 'hostel_id');
    final vpa = jStr(row, 'upi_vpa');
    final payee = jStr(row, 'payee_name');
    if (id == null || vpa == null || payee == null) return null;
    return UpiSettings(
      hostelId: id,
      vpa: vpa,
      payeeName: payee,
      hostelName: jStr(row, 'hostel_name'),
    );
  }
}

enum ClaimStatus {
  pending('Waiting for confirmation'),
  confirmed('Confirmed'),
  rejected('Not confirmed'),
  cancelled('Cancelled');

  const ClaimStatus(this.label);
  final String label;

  static ClaimStatus? tryParse(String? raw) => values.where((s) => s.name == raw).firstOrNull;
}

/// A payment claim: the tenant's own (`st_*`) or a row of `wd_payment_claims`.
class PaymentClaim {
  const PaymentClaim({
    required this.claimId,
    required this.periodMonth,
    required this.amount,
    required this.utr,
    required this.status,
    this.studentId,
    this.fullName,
    this.roomNumber,
    this.upiVpa,
    this.decisionNote,
    this.createdAt,
  });

  final String claimId;
  final String periodMonth;
  final double amount;
  final String utr;
  final ClaimStatus status;
  final String? studentId;
  final String? fullName;
  final String? roomNumber;
  final String? upiVpa;
  final String? decisionNote;
  final DateTime? createdAt;

  static PaymentClaim? fromRow(Map row) {
    final id = jStr(row, 'claim_id');
    final status = ClaimStatus.tryParse(jStr(row, 'status'));
    final amount = jNum(row, 'amount');
    final month = jStr(row, 'period_month');
    if (id == null || status == null || amount == null || month == null) return null;
    return PaymentClaim(
      claimId: id,
      periodMonth: month,
      amount: amount,
      utr: jStr(row, 'utr') ?? '',
      status: status,
      studentId: jStr(row, 'student_id'),
      fullName: jStr(row, 'full_name'),
      roomNumber: jStr(row, 'room_number'),
      upiVpa: jStr(row, 'upi_vpa'),
      decisionNote: jStr(row, 'decision_note'),
      createdAt: jDate(row, 'created_at'),
    );
  }

  static PaymentClaim? tryParse(Object? data) {
    final row = jOne(data);
    return row == null ? null : fromRow(row);
  }

  static List<PaymentClaim> listFrom(Object? data) => [for (final r in jRows(data)) ?fromRow(r)];
}
