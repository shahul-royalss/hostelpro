library;

import 'parse.dart';

/// ONE FLOOR'S LINE IN A PLAN THE OWNER IS COMPOSING.
///
/// NOT A ROW OF ANY TABLE. `public.floors` and `public.rooms` are what a building IS; this is
/// what an owner is ASKING FOR, on its way to `public.ow_set_floor_plan(hostel, plan)`. The two
/// agree only after a save has succeeded, which is why nothing here is ever parsed back out of
/// the database — a screen that seeded itself from a [FloorPlanEntry] would be showing the
/// owner their own request and calling it the building.
class FloorPlanEntry {
  const FloorPlanEntry({
    required this.floor,
    required this.rooms,
    required this.bedsPerNewRoom,
  });

  /// 1-based, and contiguous across the whole plan. ow_set_floor_plan answers a gap with
  /// "Floors must be numbered 1 to N with none missing.", so a screen composing these may never
  /// let one open — which is also why [copyWith] cannot change it.
  final int floor;

  /// How many rooms this floor should END UP with — not how many to add. 1..200 on the server.
  final int rooms;

  /// ═══ THIS APPLIES TO THE ROOMS THE SERVER CREATES, AND TO NOTHING ELSE ═══
  /// An existing room keeps the capacity it already has. Raising this number does not give the
  /// rooms already on the floor another bed each, and a screen that says it does is promising
  /// something the RPC will not do. Per-room bed counts are changed one room at a time with
  /// `showEditRoomSheet`, which is the only place the occupied count of THAT room is known and
  /// therefore the only place it is safe to take a bed away.
  ///
  /// Named `bedsPerNewRoom` and not `beds` for exactly that reason: the wire key is `beds`, and
  /// every call site that reads this field should have to say the longer, truer word.
  final int bedsPerNewRoom;

  /// The wire shape: `{"floor":1,"rooms":4,"beds":3}`.
  ///
  /// The key is `beds`, which is p_plan's vocabulary rather than this class's. Renaming it to
  /// match the Dart field would not fail to compile and would not fail a round trip either —
  /// ow_set_floor_plan would simply read a missing bed count for every floor.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'floor': floor,
        'rooms': rooms,
        'beds': bedsPerNewRoom,
      };

  /// [floor] is deliberately absent. A plan is a contiguous 1..N list and renumbering one line
  /// of it in place is how a hole gets punched in that list; floors are added and dropped at
  /// the END of the plan, never renumbered in the middle.
  FloorPlanEntry copyWith({int? rooms, int? bedsPerNewRoom}) => FloorPlanEntry(
        floor: floor,
        rooms: rooms ?? this.rooms,
        bedsPerNewRoom: bedsPerNewRoom ?? this.bedsPerNewRoom,
      );

  @override
  bool operator ==(Object other) =>
      other is FloorPlanEntry &&
      other.floor == floor &&
      other.rooms == rooms &&
      other.bedsPerNewRoom == bedsPerNewRoom;

  @override
  int get hashCode => Object.hash(floor, rooms, bedsPerNewRoom);

  @override
  String toString() => 'FloorPlanEntry(floor: $floor, rooms: $rooms, beds: $bedsPerNewRoom)';
}

/// WHAT THE SERVER DID — the single jsonb object ow_set_floor_plan returns.
///
/// Every number here was counted by Postgres inside the same transaction that made the change,
/// so [summary] is a report and not a prediction. The screen's own before-the-tap preview is
/// the prediction, and the two are deliberately computed in different places: if they ever
/// disagree, the one that ran in the database is the one that is true.
class FloorPlanResult {
  const FloorPlanResult({
    required this.floors,
    required this.roomsAdded,
    required this.roomsRemoved,
    required this.roomsTotal,
    required this.bedsTotal,
  });

  /// How many storeys the building now has.
  final int floors;

  /// Rooms created by this call. Adding is always allowed.
  final int roomsAdded;

  /// Rooms deleted by this call — only ever EMPTY ones, because the RPC refuses any room that
  /// still holds a resident and names it in the refusal.
  final int roomsRemoved;
  final int roomsTotal;
  final int bedsTotal;

  static FloorPlanResult fromJson(Map<String, dynamic> row) {
    const src = 'ow_set_floor_plan';
    return FloorPlanResult(
      floors: reqInt(row, src, 'floors'),
      roomsAdded: reqInt(row, src, 'rooms_added'),
      roomsRemoved: reqInt(row, src, 'rooms_removed'),
      roomsTotal: reqInt(row, src, 'rooms_total'),
      bedsTotal: reqInt(row, src, 'beds_total'),
    );
  }

  /// A sentence for a snackbar, in the fewest words that are still exact.
  ///
  /// "Nothing changed." is a real outcome and gets said out loud: an owner who re-saves the
  /// plan they already saved has done nothing wrong and should not be shown a success message
  /// that implies four rooms just appeared. A plan that adds on one floor and removes on
  /// another says both halves — the removal is the half nobody wants to find out about later.
  String get summary {
    final added = roomsAdded > 0;
    final removed = roomsRemoved > 0;
    if (added && removed) {
      return 'Added ${_rooms(roomsAdded)} and removed ${_rooms(roomsRemoved)}.';
    }
    if (added) return 'Added ${_rooms(roomsAdded)}.';
    if (removed) return 'Removed ${_rooms(roomsRemoved)}.';
    return 'Nothing changed.';
  }

  static String _rooms(int n) => '$n ${n == 1 ? 'room' : 'rooms'}';

  @override
  String toString() => 'FloorPlanResult(floors: $floors, +$roomsAdded, -$roomsRemoved, '
      'rooms: $roomsTotal, beds: $bedsTotal)';
}
