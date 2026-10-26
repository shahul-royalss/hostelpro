/// Staff applicants (docs/round3-api.md §6).
library;

import 'json_read.dart';

enum StaffRequestStatus {
  pending('Waiting'),
  accepted('Accepted'),
  declined('Declined'),
  cancelled('Cancelled'),
  expired('Expired');

  const StaffRequestStatus(this.label);
  final String label;

  static StaffRequestStatus? tryParse(String? raw) =>
      values.where((s) => s.name == raw).firstOrNull;
}

/// The roles an owner may grant on accept.
enum StaffGrant {
  manager('manager', 'Manager', 'Runs the PG day to day, with tasks from you'),
  warden('warden', 'Warden', 'Looks after residents, rent and rooms');

  const StaffGrant(this.wire, this.label, this.caption);
  final String wire;
  final String label;
  final String caption;
}

String? _roleLabel(String? wire) => switch (wire) {
      'manager' => 'Manager',
      'warden' => 'Warden',
      _ => null,
    };

/// `stf_request_join` / `stf_my_join_request` / `stf_cancel_join_request` and the owner's decide.
class StaffJoinRequest {
  const StaffJoinRequest({
    required this.requestId,
    required this.hostelName,
    required this.status,
    this.hostelId,
    this.city,
    this.roleGranted,
    this.decisionNote,
  });

  final String requestId;
  final String hostelName;
  final StaffRequestStatus status;
  final String? hostelId;
  final String? city;
  final String? roleGranted;
  final String? decisionNote;

  String? get roleLabel => _roleLabel(roleGranted);

  static StaffJoinRequest? tryParse(Object? data) {
    final row = jOne(data);
    if (row == null) return null;
    final id = jStr(row, 'request_id');
    final status = StaffRequestStatus.tryParse(jStr(row, 'status'));
    if (id == null || status == null) return null;
    return StaffJoinRequest(
      requestId: id,
      hostelName: jStr(row, 'hostel_name') ?? 'the PG',
      status: status,
      hostelId: jStr(row, 'hostel_id'),
      city: jStr(row, 'city'),
      roleGranted: jStr(row, 'role_granted'),
      decisionNote: jStr(row, 'decision_note'),
    );
  }
}

/// One row of `ow_staff_requests`.
class StaffRequestRow {
  const StaffRequestRow({
    required this.requestId,
    required this.hostelId,
    required this.hostelName,
    required this.fullName,
    required this.status,
    this.phone,
    this.email,
    this.message,
    this.roleGranted,
    this.decisionNote,
    this.createdAt,
  });

  final String requestId;
  final String hostelId;
  final String hostelName;
  final String fullName;
  final StaffRequestStatus status;
  final String? phone;
  final String? email;
  final String? message;
  final String? roleGranted;
  final String? decisionNote;
  final DateTime? createdAt;

  String? get roleLabel => _roleLabel(roleGranted);

  static List<StaffRequestRow> listFrom(Object? data) => [
        for (final r in jRows(data))
          if ((jStr(r, 'request_id'), StaffRequestStatus.tryParse(jStr(r, 'status')))
              case (final id?, final status?))
            StaffRequestRow(
              requestId: id,
              hostelId: jStr(r, 'hostel_id') ?? '',
              hostelName: jStr(r, 'hostel_name') ?? 'PG',
              fullName: jStr(r, 'full_name') ?? 'Applicant',
              status: status,
              phone: jStr(r, 'phone'),
              email: jStr(r, 'email'),
              message: jStr(r, 'message'),
              roleGranted: jStr(r, 'role_granted'),
              decisionNote: jStr(r, 'decision_note'),
              createdAt: jDate(r, 'created_at'),
            ),
      ];
}
