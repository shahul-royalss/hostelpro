library;

import '../../../data/models/models.dart';
import '../../../data/models/parse.dart';

/// Two tables the shared data layer does not cover yet: public.leaves and public.visitors.
///
/// WHY THEY LIVE HERE AND NOT IN lib/data. rpc_hostel_stats hands a dashboard the COUNT of
/// pending leaves and of today's visitors, and counts are all the owner and manager dashboards
/// need. The warden is the only role that acts on the rows themselves — approving a leave and
/// checking a visitor out is desk work, not reporting — and the RLS policies say the same
/// thing: `leaves_update` and every visitors policy name the warden explicitly.
///
/// So these are modelled to the warden's need, in the warden's directory, rather than forking
/// the shared layer mid-flight. They follow its rules exactly — parsed by wire value, coerced
/// through parse.dart so a wrong column names itself, returned as models and never as maps —
/// and should be promoted into lib/data the moment a second role needs them.

/// public.leave_status.
enum LeaveStatus implements WireValue {
  pending('pending', 'Pending'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected');

  const LeaveStatus(this.wire, this.label);
  @override
  final String wire;
  @override
  final String label;

  bool get isDecided => this != LeaveStatus.pending;

  static LeaveStatus? tryParse(String? v) => wireOrNull(LeaveStatus.values, v);
}

/// public.leaves — a resident asking to be away between two dates.
///
/// [studentName] comes from an embedded select on public.students rather than a second query.
/// The embed is evaluated under the caller's RLS, so a role that cannot read students gets
/// null here rather than a name it was not entitled to — which is exactly the manager, who
/// cannot read this table at all.
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.hostelId,
    required this.studentId,
    required this.fromDate,
    required this.toDate,
    required this.status,
    required this.createdAt,
    this.reason,
    this.decidedBy,
    this.decidedAt,
    this.decisionNote,
    this.studentName,
    this.studentPhone,
  });

  /// `student:students(...)` is unambiguous: leaves.student_id is the only foreign key from
  /// this table to students, so PostgREST needs no disambiguating hint.
  static const columns =
      'id, hostel_id, student_id, from_date, to_date, reason, status, decided_by, '
      'decided_at, decision_note, created_at, student:students(full_name, phone)';

  final String id;
  final String hostelId;
  final String studentId;

  /// Plain `date` columns, inclusive at both ends (the table checks to_date >= from_date).
  final DateTime fromDate;
  final DateTime toDate;
  final String? reason;
  final LeaveStatus status;

  /// Set by the warden who decided it. `decided_at` is stamped by app.leaves_after_change.
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? decisionNote;
  final DateTime createdAt;

  /// Null when the caller may not read the resident's row.
  final String? studentName;
  final String? studentPhone;

  /// Inclusive, so a single-day leave is one night, not zero.
  int get nights => toDate.difference(fromDate).inDays + 1;

  factory LeaveRequest.fromJson(Map<String, dynamic> row) {
    const src = 'leaves';
    final student = row['student'];
    final embedded = student is Map<String, dynamic> ? student : null;
    return LeaveRequest(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      studentId: reqString(row, src, 'student_id'),
      fromDate: reqDate(row, src, 'from_date'),
      toDate: reqDate(row, src, 'to_date'),
      reason: optString(row, 'reason'),
      status: wireOrThrow(LeaveStatus.values, row['status'], src, 'status'),
      decidedBy: optString(row, 'decided_by'),
      decidedAt: optTimestamp(row, src, 'decided_at'),
      decisionNote: optString(row, 'decision_note'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      studentName: embedded == null ? null : optString(embedded, 'full_name'),
      studentPhone: embedded == null ? null : optString(embedded, 'phone'),
    );
  }
}

/// public.visitors — one row per guest, opened at check-in and closed at check-out.
///
/// A null [checkOutAt] IS the "still in the building" state; there is no status column. That is
/// why the warden's on-site list filters on `check_out_at is null` rather than on a flag which
/// could disagree with the timestamps.
class VisitorLog {
  const VisitorLog({
    required this.id,
    required this.hostelId,
    required this.studentId,
    required this.visitorName,
    required this.checkInAt,
    required this.createdAt,
    this.visitorPhone,
    this.relation,
    this.checkOutAt,
    this.loggedBy,
    this.studentName,
  });

  static const columns =
      'id, hostel_id, student_id, visitor_name, visitor_phone, relation, check_in_at, '
      'check_out_at, logged_by, created_at, student:students(full_name)';

  final String id;
  final String hostelId;

  /// The resident being visited. NOT NULL, and app.assert_student_in_hostel refuses a student
  /// from another hostel — the tenant check is a trigger, not something this client enforces.
  final String studentId;
  final String visitorName;
  final String? visitorPhone;

  /// Free text: "Father", "Friend". Not an enum in the schema, so not one here.
  final String? relation;
  final DateTime checkInAt;

  /// Null while the visitor is still on site.
  final DateTime? checkOutAt;
  final String? loggedBy;
  final DateTime createdAt;
  final String? studentName;

  bool get isOnSite => checkOutAt == null;

  factory VisitorLog.fromJson(Map<String, dynamic> row) {
    const src = 'visitors';
    final student = row['student'];
    final embedded = student is Map<String, dynamic> ? student : null;
    return VisitorLog(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      studentId: reqString(row, src, 'student_id'),
      visitorName: reqString(row, src, 'visitor_name'),
      visitorPhone: optString(row, 'visitor_phone'),
      relation: optString(row, 'relation'),
      checkInAt: reqTimestamp(row, src, 'check_in_at'),
      checkOutAt: optTimestamp(row, src, 'check_out_at'),
      loggedBy: optString(row, 'logged_by'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      studentName: embedded == null ? null : optString(embedded, 'full_name'),
    );
  }
}
