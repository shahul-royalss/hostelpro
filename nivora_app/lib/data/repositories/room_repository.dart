library;

import '../models/models.dart';
import 'repository.dart';

/// THE ONE WRITE THAT RESHAPES A BUILDING, behind an interface.
///
/// Same shape and same reasoning as `OwnerStaffWrites`. The reads in this file are tested by
/// overriding the provider that holds the answer; this one cannot be, because its interesting
/// states are all things only the SERVER knows — a floor that still has somebody on it, a
/// hostel gone read-only, a plan whose floors have a hole in them. Those are the states worth
/// holding down in `flutter test`, and a test needs a stand-in for them that has no network and
/// no Supabase client in it.
///
/// [RoomRepository] implements this; `roomLayoutWritesProvider` hands it out by the interface.
abstract interface class RoomLayoutWrites {
  /// See [RoomRepository.setFloorPlan].
  Future<FloorPlanResult> setFloorPlan({
    required String hostelId,
    required List<FloorPlanEntry> plan,
  });
}

/// Rooms, beds and who is in them.
///
/// TABLES: public.rooms, public.beds.
/// RPCs:   public.rpc_room_occupancy(), public.ow_set_floor_plan().
final class RoomRepository extends Repository implements RoomLayoutWrites {
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
  /// ═══ AN EMPTY RESULT IS NOT AN EMPTY ROOM. THERE IS NO SUCH THING AS AN EMPTY ROOM ═══
  /// public.rooms.capacity is `check (capacity between 1 and 12)` (db/schema.sql:145) and
  /// app.rooms_capacity_sync creates one bed row per unit of capacity on insert and on every
  /// capacity change (db/schema.sql:701). Every room that exists therefore has at least one bed,
  /// always. Rooms are not soft-deleted either, so there is no lingering husk to explain it.
  ///
  /// So zero rows means the room is not reachable from this account: a student's beds policy
  /// narrows to `room_id = (their own room)`, and asking about anyone else's room is answered
  /// with silence rather than with 42501. The room sheet drew that silence as "This room has no
  /// beds", complete with an explanation of how bed rows follow capacity — a confident,
  /// well-written sentence about a room the reader is simply not allowed to look at.
  Future<List<Bed>> bedsInRoom(String roomId) => guard(() async {
        final rows = await db
            .from('beds')
            .select(Bed.columns)
            .eq('room_id', roomId)
            .order('bed_number', ascending: true);
        return rowsOrMissing(
          rows,
          missing: 'That room is not one this account can open.',
          why: 'beds for room $roomId came back empty; rooms.capacity >= 1 and '
              'app.rooms_capacity_sync guarantee a bed row for every room that exists, so the '
              'room is either gone or outside this caller\'s policy',
          // ...or the caller was `anon` because the session died on the way. Only a live token
          // earns the sentence above.
          standing: sessionStanding,
        ).map(Bed.fromJson).toList(growable: false);
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
      guardWrite(() async {
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
      }, unresolved: 'Reload the room before changing it again — a capacity change adds or '
          'removes bed rows, so the room may already look different.');

  /// THE OWNER MAPS THE BUILDING: how many floors, how many rooms on each, and how many beds
  /// the rooms this call CREATES are given. public.ow_set_floor_plan.
  ///
  /// [plan] is one entry per floor, numbered 1..N with none missing — the RPC refuses a gap,
  /// a duplicate, and anybody who is not this hostel's owner.
  ///
  /// ═══ WHAT THIS DOES NOT DO, SAID HERE SO NO CALLER HAS TO GUESS ═══
  /// [FloorPlanEntry.bedsPerNewRoom] reaches rooms that did not exist a moment ago and nothing
  /// else: an existing room keeps its capacity, and the way to change THAT is
  /// `showEditRoomSheet` one room at a time. Removing takes the highest-numbered EMPTY rooms on
  /// a floor, and any room with a resident in it is refused by name — "Room 102 still has
  /// residents in it. Move them to another bed first." Floors above N go the same way and are
  /// refused on the same terms.
  ///
  /// ═══ THE REFUSAL IS THE PRODUCT, SO IT TRAVELS INTACT ═══
  /// Every one of those refusals is a `P0001` carrying a sentence written for a person, and
  /// [AppFailure.from] passes a P0001 through unchanged into [InvalidInputFailure.message] (see
  /// models/failure.dart). Nothing is re-worded here, because the server's sentence NAMES THE
  /// ROOM and a tidier generic one would send an owner to walk the whole floor.
  ///
  /// ═══ [guardWrite], NOT [guard] ═══
  /// Applying the same plan twice is a no-op, so this is idempotent in the narrow sense. It is
  /// still a write whose timeout must not be reported as "nothing happened": the call that ran
  /// out of time may have been the one that deleted six rooms, and the honest thing to say is
  /// that nobody knows yet. [unresolved] therefore points at the screen that can answer it,
  /// which re-seeds itself from the building as it now stands.
  @override
  Future<FloorPlanResult> setFloorPlan({
    required String hostelId,
    required List<FloorPlanEntry> plan,
  }) =>
      guardWrite(() async {
        final data = await db.rpc('ow_set_floor_plan', params: {
          'p_hostel_id': hostelId,
          'p_plan': plan.map((entry) => entry.toJson()).toList(growable: false),
        });
        // `returns jsonb`, so PostgREST sends the object itself. rpcObject also accepts the
        // one-element array shape, which is what has kept the composite-returning RPCs in this
        // app working across PostgREST upgrades — the same tolerance costs nothing here.
        return FloorPlanResult.fromJson(rpcObject(data, 'ow_set_floor_plan'));
      }, unresolved: 'Open the layout again before changing it — it reads the building as it '
          'now stands, so it will show you whether the rooms were created or removed.');
}
