library;

import '../models/models.dart';
import 'repository.dart';

/// Rooms, beds and who is in them.
///
/// TABLES: public.rooms, public.beds.
/// RPCs:   public.rpc_room_occupancy().
final class RoomRepository extends Repository {
  const RoomRepository(super.db);

  /// The whole building, one row per room, with a live occupied count.
  ///
  /// Not paginated on purpose. This is what the room-grid screen draws, and a grid that
  /// paginates cannot show a building at a glance — which is the only reason to draw a grid.
  /// The RPC is one query with a correlated count per room; a 5 000-room ceiling (the check
  /// constraint on hostels.total_rooms) keeps it bounded.
  Future<List<RoomOccupancy>> occupancy(String hostelId) => guard(() async {
        final data = await db.rpc('rpc_room_occupancy', params: {'p_hostel_id': hostelId});
        return rpcRows(data, 'rpc_room_occupancy')
            .map(RoomOccupancy.fromJson)
            .toList(growable: false);
      });

  /// Raw room rows, optionally for one storey.
  Future<List<Room>> rooms(String hostelId, {String? floorId}) => guard(() async {
        var query = db.from('rooms').select(Room.columns).eq('hostel_id', hostelId);
        if (floorId != null) query = query.eq('floor_id', floorId);
        final rows = await query.order('room_number', ascending: true);
        return rows.map(Room.fromJson).toList(growable: false);
      });

  /// Beds in one room, in bed-number order.
  ///
  /// A student may call this for their OWN room only; the beds policy narrows it to
  /// `room_id = (their room)`. Asking for another room returns an empty list, not an error.
  Future<List<Bed>> bedsInRoom(String roomId) => guard(() async {
        final rows = await db
            .from('beds')
            .select(Bed.columns)
            .eq('room_id', roomId)
            .order('bed_number', ascending: true);
        return rows.map(Bed.fromJson).toList(growable: false);
      });

  /// Every unoccupied bed in the hostel — what a warden picks from when registering someone.
  ///
  /// Filters on `student_id is null` rather than `status = 'free'`. The two are kept in step by
  /// app.beds_guard, but student_id is the column the unique index and the FK are built on, so
  /// it is the one that decides whether the insert will actually succeed.
  Future<List<Bed>> freeBeds(String hostelId) => guard(() async {
        final rows = await db
            .from('beds')
            .select(Bed.columns)
            .eq('hostel_id', hostelId)
            .isFilter('student_id', null)
            .order('bed_number', ascending: true);
        return rows.map(Bed.fromJson).toList(growable: false);
      });

  /// Warden edit of a room's number or capacity (§4.2).
  ///
  /// Changing capacity does not just change a number: app.rooms_capacity_sync adds bed rows
  /// when it goes up and removes FREE beds when it goes down, refusing to strip a bed someone
  /// is sleeping in. So the returned room may come back with beds that did not exist a moment
  /// ago — re-read the beds after calling this rather than adjusting a local list.
  Future<Room> updateRoom({
    required String roomId,
    String? roomNumber,
    int? capacity,
  }) =>
      guard(() async {
        final patch = <String, dynamic>{
          'room_number': ?roomNumber,
          'capacity': ?capacity,
        };
        if (patch.isEmpty) {
          throw const InvalidInputFailure('Nothing to change.');
        }
        final row = await db
            .from('rooms')
            .update(patch)
            .eq('id', roomId)
            .select(Room.columns)
            .single();
        return Room.fromJson(row);
      });
}
