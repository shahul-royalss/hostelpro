library;

import '../models/models.dart';
import 'repository.dart';

/// The two calls a warden or manager makes about WHICH PG they are working in, behind an
/// interface.
///
/// An interface for the reason `OwnerStaffWrites` is one: the switch moves `users.hostel_id`,
/// which every RLS policy in the schema reads, and its interesting states (a PG the owner has
/// just taken away, a role that may not switch at all, a reload that fails after the move has
/// already landed) are the states worth holding down in `flutter test`. A test needs a stand-in
/// for that, and a Supabase client is not one.
abstract interface class StaffHostelAccess {
  /// Every PG the caller may work in, by name. public.my_staff_hostels().
  Future<List<StaffHostel>> myHostels();

  /// Moves the caller's active PG to [hostelId] and returns it. public.staff_switch_hostel().
  Future<String> switchTo(String hostelId);
}

/// public.my_staff_hostels() and public.staff_switch_hostel().
///
/// ── WHAT THE SERVER DECIDES, AND WHAT THIS FILE DOES NOT ─────────────────────────────────
///
/// Both functions are SECURITY DEFINER and both take the caller from `auth.uid()`, never from
/// an argument. There is no user id anywhere in this file to get wrong or to forge: a switch
/// can only ever move the signed-in person's own `users.hostel_id`, only to a PG
/// `public.staff_hostel_access` lists for them, and only while they are an ACTIVE warden or
/// manager. An owner, a resident and a super admin get the empty list and a refusal.
///
/// The target PG is an argument, and that is safe because it is not trusted: the RPC checks it
/// against the access table itself and answers 'You do not have access to that PG.' for
/// anything else. Nothing in this app narrows what may be asked; the database decides what is
/// allowed.
final class StaffAccessRepository extends Repository implements StaffHostelAccess {
  const StaffAccessRepository(super.db);

  /// Ordered by name on the server; exactly one row is [StaffHostel.isActive].
  ///
  /// EMPTY IS A REAL ANSWER AND NOT A FAILURE. The function returns no rows to anybody who is
  /// not an active warden or manager, and a single-PG warden gets one row. The screens read the
  /// length and nothing else: fewer than two means there is nothing to switch to, so no control
  /// is drawn, which is also exactly what a warden on today's schema sees.
  @override
  Future<List<StaffHostel>> myHostels() => guard(() async {
        final data = await db.rpc('my_staff_hostels');
        return rpcRows(data, 'my_staff_hostels')
            .map(StaffHostel.fromJson)
            .toList(growable: false);
      });

  /// A no-op on the server when [hostelId] is already active, so tapping the same PG twice, or
  /// retrying after a reload that failed, is always safe.
  ///
  /// The refusals are P0001 with sentences written for a person ('Only wardens and managers can
  /// switch PG.', 'You do not have access to that PG.'), which [AppFailure] passes through
  /// verbatim as an [InvalidInputFailure].
  @override
  Future<String> switchTo(String hostelId) => guard(() async {
        final data = await db.rpc('staff_switch_hostel', params: {'p_hostel_id': hostelId});
        if (data is String) return data;
        throw RowShapeError(
          'staff_switch_hostel',
          '(result)',
          'expected the uuid of the PG now active, got ${data.runtimeType}',
        );
      });
}
