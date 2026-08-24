library;

import '../models/models.dart';
import 'repository.dart';

/// Reads about the tenant itself: the hostel row, its floors, and the contact card.
///
/// TABLES: public.hostels, public.floors.
/// RPCs:   public.st_hostel_contacts(), public.ow_update_hostel_rules().
final class HostelRepository extends Repository {
  const HostelRepository(super.db);

  /// The hostel a session is attached to.
  ///
  /// Returns null when the row is not visible. That is not necessarily "deleted": RLS
  /// (`app.can_read_hostel`) hides other tenants' hostels entirely, so an id from the wrong
  /// place looks exactly like a missing one — which is the intended behaviour.
  Future<Hostel?> byId(String hostelId) => guard(() async {
        final row = await db
            .from('hostels')
            .select(Hostel.columns)
            .eq('id', hostelId)
            .maybeSingle();
        return row == null ? null : Hostel.fromJson(row);
      });

  /// Storeys, lowest first. Small and bounded (1–50 by check constraint), so not paginated.
  Future<List<Floor>> floors(String hostelId) => guard(() async {
        final rows = await db
            .from('floors')
            .select(Floor.columns)
            .eq('hostel_id', hostelId)
            .order('floor_number', ascending: true);
        return rows.map(Floor.fromJson).toList(growable: false);
      });

  /// The names and numbers a resident is allowed to see.
  ///
  /// Goes through st_hostel_contacts() rather than joining public.users, because students
  /// cannot read that table at all (§4.8). The function resolves the caller's hostel itself,
  /// so there is nothing to pass and nothing to get wrong.
  Future<HostelContacts?> contacts() => guard(() async {
        final data = await db.rpc('st_hostel_contacts');
        final row = rpcRow(data, 'st_hostel_contacts');
        return row == null ? null : HostelContacts.fromJson(row);
      });

  /// Owner-only edit of the hostel rules text.
  ///
  /// The only field an owner may change on `hostels` — everything else on that table is Super
  /// Admin's. The RPC re-checks ownership AND the read-only gate server-side and raises 42501
  /// on either, which surfaces here as [AccessDeniedFailure] or [ReadOnlyFailure].
  Future<void> updateRules({
    required String hostelId,
    required String rules,
  }) =>
      guard(() async {
        await db.rpc('ow_update_hostel_rules', params: {
          'p_hostel_id': hostelId,
          'p_rules': rules,
        });
      });
}
