library;

import 'enums.dart';
import 'parse.dart';

/// One PG a warden or manager is ALLOWED into, as `public.my_staff_hostels()` returns it.
///
/// ── WHY A STAFF MEMBER CAN HAVE MORE THAN ONE PG NOW ─────────────────────────────────────
///
/// An owner with two buildings used to need two warden logins for the one person who looks
/// after both. `public.staff_hostel_access` records which PGs each warden and manager may work
/// in, and `users.hostel_id` stays what it always was: the ONE PG they are working in right
/// now. Every RLS policy in the schema still reads that single column through
/// `app.user_hostel_id()`, so a warden is scoped to one PG at a time exactly as before, and
/// "switching" is `public.staff_switch_hostel()` moving that column to another allowed PG.
///
/// NOTHING HERE IS A PERMISSION. The list decides whether a Switch PG control is drawn. What a
/// switch may target is decided by the RPC, SECURITY DEFINER, against the access table, and it
/// refuses a PG that is not on the list with its own sentence.
class StaffHostel {
  const StaffHostel({
    required this.hostelId,
    required this.name,
    required this.isActive,
    this.address,
    this.status,
  });

  final String hostelId;
  final String name;
  final String? address;

  /// Null when the server sends a status this build cannot name. The row is still a PG the
  /// person may work in, so it is drawn rather than thrown away; only the status line is lost.
  final HostelStatus? status;

  /// True for the PG `users.hostel_id` points at: the one every screen is showing.
  final bool isActive;

  factory StaffHostel.fromJson(Map<String, dynamic> row) {
    const src = 'my_staff_hostels';
    return StaffHostel(
      hostelId: reqString(row, src, 'hostel_id'),
      name: reqString(row, src, 'name'),
      address: optString(row, 'address'),
      status: HostelStatus.tryParse(optString(row, 'status')),
      isActive: reqBool(row, src, 'is_active'),
    );
  }
}

/// Which PGs a staff member may work in, after an owner changed them.
///
/// One row of `public.owner_set_staff_hostels()`. Exactly one row comes back with [isActive]
/// set: the PG they are working in now, which the RPC moves to the first remaining PG by name
/// when the owner takes their current one away.
class StaffHostelGrant {
  const StaffHostelGrant({required this.hostelId, required this.isActive});

  final String hostelId;
  final bool isActive;

  factory StaffHostelGrant.fromJson(Map<String, dynamic> row) {
    const src = 'owner_set_staff_hostels';
    return StaffHostelGrant(
      hostelId: reqString(row, src, 'hostel_id'),
      isActive: reqBool(row, src, 'is_active'),
    );
  }
}
