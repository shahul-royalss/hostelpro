/// A resident's stay (round 3): the timeline (R2), months since check-in (R2) and check-out
/// requests (R6). Shapes follow docs/round3-api.md §3 and §7. Parsers are lenient: a field
/// this build cannot read becomes null rather than throwing.
library;

String? _s(Map row, String k) {
  final v = row[k];
  return v is String && v.trim().isNotEmpty ? v : null;
}

DateTime? _d(Map row, String k) => DateTime.tryParse(_s(row, k) ?? '');

double? _n(Map row, String k) {
  final v = row[k];
  return v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
}

int? _i(Map row, String k) {
  final v = row[k];
  return v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
}

List<Map<String, dynamic>> _rows(Object? data) => data is List
    ? [for (final r in data) if (r is Map<String, dynamic>) r]
    : const [];

Map<String, dynamic>? _one(Object? data) {
  final row = data is List ? (data.isEmpty ? null : data.first) : data;
  return row is Map<String, dynamic> ? row : null;
}

/// 'YYYY-MM-DD' for a `date` parameter.
String dateWire(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// True when [periodMonth] ('YYYY-MM') is before the month of [checkIn]. Lexical order of
/// 'YYYY-MM' is chronological order.
bool monthBeforeCheckIn(String periodMonth, DateTime checkIn) {
  final first = '${checkIn.year.toString().padLeft(4, '0')}-'
      '${checkIn.month.toString().padLeft(2, '0')}';
  return periodMonth.compareTo(first) < 0;
}

// ── Timeline (st_timeline) ─────────────────────────────────────────────────────────────────

enum TimelineKind {
  checkedIn('checked_in'),
  room('room'),
  due('due'),
  payment('payment'),
  complaint('complaint'),
  checkoutRequest('checkout_request'),
  checkoutDecision('checkout_decision'),
  checkedOut('checked_out'),
  upiClaim('upi_claim'),
  other('');

  const TimelineKind(this.wire);
  final String wire;

  static TimelineKind parse(String? raw) =>
      values.firstWhere((k) => k.wire == raw && k != other, orElse: () => other);
}

class TimelineEntry {
  const TimelineEntry({
    required this.at,
    required this.kind,
    required this.title,
    this.detail,
    this.amount,
    this.status,
    this.refId,
  });

  final DateTime at;
  final TimelineKind kind;
  final String title;
  final String? detail;
  final double? amount;
  final String? status;
  final String? refId;

  static TimelineEntry? tryParse(Map<String, dynamic> row) {
    final at = _d(row, 'at');
    final title = _s(row, 'title');
    if (at == null || title == null) return null;
    return TimelineEntry(
      at: at,
      kind: TimelineKind.parse(_s(row, 'kind')),
      title: title,
      detail: _s(row, 'detail'),
      amount: _n(row, 'amount'),
      status: _s(row, 'status'),
      refId: _s(row, 'ref_id'),
    );
  }

  static List<TimelineEntry> listFrom(Object? data) =>
      [for (final r in _rows(data)) ?tryParse(r)];
}

// ── Months since check-in (rpc_student_fee_months) ────────────────────────────────────────

class FeeMonth {
  const FeeMonth({
    required this.periodMonth,
    required this.amountDue,
    required this.amountPaid,
    required this.status,
    this.paidOn,
    this.mode,
  });

  final String periodMonth;
  final double amountDue;
  final double amountPaid;

  /// 'paid' | 'partial' | 'unpaid'.
  final String status;
  final DateTime? paidOn;
  final String? mode;

  static List<FeeMonth> listFrom(Object? data) => [
        for (final r in _rows(data))
          if (_s(r, 'period_month') case final month?)
            FeeMonth(
              periodMonth: month,
              amountDue: _n(r, 'amount_due') ?? 0,
              amountPaid: _n(r, 'amount_paid') ?? 0,
              status: _s(r, 'status') ?? 'unpaid',
              paidOn: _d(r, 'paid_on'),
              mode: _s(r, 'mode'),
            ),
      ];
}

// ── Check-out requests ─────────────────────────────────────────────────────────────────────

enum CheckoutStatus {
  pending('Waiting for the warden'),
  accepted('Accepted'),
  declined('Declined'),
  cancelled('Cancelled'),
  completed('Checked out');

  const CheckoutStatus(this.label);
  final String label;

  static CheckoutStatus? tryParse(String? raw) =>
      values.where((s) => s.name == raw).firstOrNull;

  /// Pending or accepted: the tenant cannot ask again.
  bool get isOpen => this == pending || this == accepted;
}

/// `st_request_checkout` / `st_my_checkout_request` / `wd_decide_checkout_request`.
class CheckoutRequest {
  const CheckoutRequest({
    required this.requestId,
    required this.status,
    required this.preferredDate,
    this.hostelId,
    this.studentId,
    this.reason,
    this.checkoutDate,
    this.decisionNote,
    this.decidedAt,
    this.completedAt,
    this.createdAt,
  });

  final String requestId;
  final CheckoutStatus status;
  final DateTime preferredDate;
  final String? hostelId;
  final String? studentId;
  final String? reason;
  final DateTime? checkoutDate;
  final String? decisionNote;
  final DateTime? decidedAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  static CheckoutRequest? tryParse(Object? data) {
    final row = _one(data);
    if (row == null) return null;
    final id = _s(row, 'request_id');
    final status = CheckoutStatus.tryParse(_s(row, 'status'));
    final preferred = _d(row, 'preferred_date');
    if (id == null || status == null || preferred == null) return null;
    return CheckoutRequest(
      requestId: id,
      status: status,
      preferredDate: preferred,
      hostelId: _s(row, 'hostel_id'),
      studentId: _s(row, 'student_id'),
      reason: _s(row, 'reason'),
      checkoutDate: _d(row, 'checkout_date'),
      decisionNote: _s(row, 'decision_note'),
      decidedAt: _d(row, 'decided_at'),
      completedAt: _d(row, 'completed_at'),
      createdAt: _d(row, 'created_at'),
    );
  }
}

/// One row of `wd_checkout_requests`.
class CheckoutRequestRow {
  const CheckoutRequestRow({
    required this.requestId,
    required this.studentId,
    required this.fullName,
    required this.status,
    required this.preferredDate,
    this.phone,
    this.roomNumber,
    this.bedNumber,
    this.reason,
    this.checkoutDate,
    this.decisionNote,
    this.createdAt,
  });

  final String requestId;
  final String studentId;
  final String fullName;
  final CheckoutStatus status;
  final DateTime preferredDate;
  final String? phone;
  final String? roomNumber;
  final int? bedNumber;
  final String? reason;
  final DateTime? checkoutDate;
  final String? decisionNote;
  final DateTime? createdAt;

  static List<CheckoutRequestRow> listFrom(Object? data) => [
        for (final r in _rows(data))
          if ((
            _s(r, 'request_id'),
            CheckoutStatus.tryParse(_s(r, 'status')),
            _d(r, 'preferred_date'),
          )
              case (final id?, final status?, final preferred?))
            CheckoutRequestRow(
              requestId: id,
              studentId: _s(r, 'student_id') ?? '',
              fullName: _s(r, 'full_name') ?? 'Resident',
              status: status,
              preferredDate: preferred,
              phone: _s(r, 'phone'),
              roomNumber: _s(r, 'room_number'),
              bedNumber: _i(r, 'bed_number'),
              reason: _s(r, 'reason'),
              checkoutDate: _d(r, 'checkout_date'),
              decisionNote: _s(r, 'decision_note'),
              createdAt: _d(r, 'created_at'),
            ),
      ];
}

/// `ow_checkout_summary`: counts and up to 20 recent items for the owner's home.
class CheckoutSummary {
  const CheckoutSummary({
    required this.pending,
    required this.scheduled,
    required this.recent,
    required this.items,
  });

  static const empty = CheckoutSummary(pending: 0, scheduled: 0, recent: 0, items: []);

  final int pending;
  final int scheduled;
  final int recent;
  final List<CheckoutSummaryItem> items;

  bool get isEmpty => pending == 0 && scheduled == 0 && recent == 0;

  static CheckoutSummary parse(Object? data) {
    final row = _one(data);
    if (row == null) return empty;
    return CheckoutSummary(
      pending: _i(row, 'pending') ?? 0,
      scheduled: _i(row, 'scheduled') ?? 0,
      recent: _i(row, 'recent') ?? 0,
      items: [
        for (final r in _rows(row['items']))
          if ((_s(r, 'request_id'), CheckoutStatus.tryParse(_s(r, 'status')))
              case (final id?, final status?))
            CheckoutSummaryItem(
              requestId: id,
              status: status,
              fullName: _s(r, 'full_name') ?? 'Resident',
              hostelName: _s(r, 'hostel_name'),
              roomNumber: _s(r, 'room_number'),
              preferredDate: _d(r, 'preferred_date'),
              checkoutDate: _d(r, 'checkout_date'),
              completedAt: _d(r, 'completed_at'),
            ),
      ],
    );
  }
}

class CheckoutSummaryItem {
  const CheckoutSummaryItem({
    required this.requestId,
    required this.status,
    required this.fullName,
    this.hostelName,
    this.roomNumber,
    this.preferredDate,
    this.checkoutDate,
    this.completedAt,
  });

  final String requestId;
  final CheckoutStatus status;
  final String fullName;
  final String? hostelName;
  final String? roomNumber;
  final DateTime? preferredDate;
  final DateTime? checkoutDate;
  final DateTime? completedAt;
}
