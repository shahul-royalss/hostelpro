library;

import '../../../data/models/models.dart';

/// THE ARITHMETIC BEHIND THE LAYOUT EDITOR, with no widget in it.
///
/// Every number this file produces is either counted from `rpc_room_occupancy` or typed by the
/// owner. Nothing is derived from `hostels.total_floors` / `hostels.total_rooms`: those two
/// columns record what a PG was SCAFFOLDED with and drift the moment a room is added, so a
/// screen seeded from them would offer to delete rooms that exist and keep ones that do not.
///
/// It lives apart from the screen because the interesting cases are all edge cases — a floor
/// whose top room is occupied, a building whose floors are numbered 0..2, a plan that adds on
/// one storey while removing on another — and none of them are reachable by tapping around a
/// seeded demo.

/// ONE STOREY AS IT STANDS, in the terms `ow_set_floor_plan` reasons about.
class FloorSnapshot {
  const FloorSnapshot({required this.floor, required this.rooms});

  final int floor;

  /// This floor's rooms in `rpc_room_occupancy`'s own order — floor number, then room number.
  ///
  /// THE ORDER IS LOAD-BEARING. Shrinking a floor removes from the TOP of that ordering, so
  /// which rooms are at risk is a question about this list's tail, not about its length.
  final List<RoomOccupancy> rooms;

  int get roomCount => rooms.length;

  int get bedCount => rooms.fold(0, (sum, r) => sum + r.capacity);

  int get occupiedBeds => rooms.fold(0, (sum, r) => sum + r.occupied);

  /// The rooms a shrink to [target] would have to remove, highest-numbered first, and empty
  /// when [target] is not below what is already here.
  List<RoomOccupancy> roomsRemovedBy(int target) => target >= roomCount
      ? const <RoomOccupancy>[]
      : rooms.sublist(target).reversed.toList(growable: false);

  /// The rooms a shrink to [target] would have to remove THAT SOMEBODY IS STILL LIVING IN.
  ///
  /// This is the refusal, computed on the phone from the very counts the room grid draws, so it
  /// can be said before the tap instead of arriving as a snackbar afterwards.
  List<RoomOccupancy> blockedBy(int target) =>
      roomsRemovedBy(target).where((r) => !r.isEmpty).toList(growable: false);

  /// Every room on this floor that still has somebody in it — what dropping the whole floor
  /// would run into.
  List<RoomOccupancy> get occupiedRooms =>
      rooms.reversed.where((r) => !r.isEmpty).toList(growable: false);

  /// The bed count most of this floor's rooms have, or null for a floor with no rooms.
  ///
  /// Offered as the starting value for NEW rooms because a floor's house style is usually its
  /// own: a storey of triples gets another triple. Ties go to the smaller room, which is the
  /// value that cannot promise beds nobody asked for.
  int? get commonCapacity => modeCapacity(rooms);
}

/// The bed count that appears most often across [rooms], or null when there are none.
int? modeCapacity(Iterable<RoomOccupancy> rooms) {
  final counts = <int, int>{};
  for (final room in rooms) {
    counts[room.capacity] = (counts[room.capacity] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final capacities = counts.keys.toList(growable: false)..sort();
  var best = capacities.first;
  for (final capacity in capacities) {
    if (counts[capacity]! > counts[best]!) best = capacity;
  }
  return best;
}

/// THE BUILDING, FLOOR BY FLOOR, from the rows the room grid already draws.
///
/// Floors come out in the order a person walks them. A floor with no rooms does not appear,
/// because `rpc_room_occupancy` returns ROOMS and has no way to mention one — which is equally
/// true of the grid this screen is opened from, so the two agree about what exists.
List<FloorSnapshot> snapshotBuilding(List<RoomOccupancy> occupancy) {
  final byFloor = <int, List<RoomOccupancy>>{};
  for (final room in occupancy) {
    byFloor.putIfAbsent(room.floorNumber, () => <RoomOccupancy>[]).add(room);
  }
  final floors = byFloor.keys.toList(growable: false)..sort();
  return [
    for (final floor in floors) FloorSnapshot(floor: floor, rooms: byFloor[floor]!),
  ];
}

/// Whether these storeys are the `1, 2, 3 … N with none missing` that ow_set_floor_plan
/// requires.
///
/// IT IS NOT A GIVEN. `public.floors.floor_number` carries no such constraint, and the model
/// says so out loud — "Ground floor is 0 or 1 depending on how the hostel was scaffolded" (see
/// [Floor]). A building numbered 0..2 is perfectly legal and simply cannot be DESCRIBED by a
/// plan, so the editor declines to open on it rather than silently renumbering somebody's
/// building underneath them.
bool planCanDescribe(List<FloorSnapshot> building) {
  for (var i = 0; i < building.length; i++) {
    if (building[i].floor != i + 1) return false;
  }
  return true;
}

/// `rooms.capacity` is `check (capacity between 1 and 12)`, and ow_set_floor_plan says the same
/// thing in words: "Floor N: a room holds between 1 and 12 beds."
const int minBedsPerRoom = 1;
const int maxBedsPerRoom = 12;

/// "Floor N must have between 1 and 200 rooms." — the RPC's own bounds, not this screen's.
const int minRoomsPerFloor = 1;
const int maxRoomsPerFloor = 200;

/// The RPC's own floor bounds — `ow_set_floor_plan` refuses an empty plan ("Send a plan with at
/// least one floor.") and more than fifty ("A hostel may have at most 50 floors.").
///
/// They are here for the same reason the room and bed bounds are: so the screen cannot compose a
/// plan the server will not read. Without the floor on [minFloors] an owner could remove every
/// storey, agree to a confirmation dialog listing the entire building, and have the wire carry
/// `[]` — a destructive-looking journey that ends in a refusal. Emptying a PG is a job for the
/// room grid, one room at a time, where each deletion is its own decision.
const int minFloors = 1;
const int maxFloors = 50;

int clampBeds(int beds) => beds < minBedsPerRoom
    ? minBedsPerRoom
    : (beds > maxBedsPerRoom ? maxBedsPerRoom : beds);

/// THE PLAN THE EDITOR OPENS ON: the building exactly as it stands.
///
/// Room counts are the real ones. The bed count offered for new rooms is this floor's own most
/// common capacity, falling back to the building's, then to the PG's scaffolding default, and
/// finally to 1 — which is not a guess about this hostel but the RPC's own lower bound, the one
/// number that cannot be wrong about any building.
List<FloorPlanEntry> seedPlan(List<FloorSnapshot> building, {int? hostelBedsDefault}) {
  final houseStyle = modeCapacity(building.expand((f) => f.rooms));
  return [
    for (final floor in building)
      FloorPlanEntry(
        floor: floor.floor,
        rooms: floor.roomCount,
        bedsPerNewRoom: clampBeds(floor.commonCapacity ?? houseStyle ?? hostelBedsDefault ?? 1),
      ),
  ];
}

/// The bed count a brand-new storey starts on: what this building mostly does, or the PG's
/// scaffolding default when there is no building yet to learn from.
int seedBedsForNewFloor(List<FloorSnapshot> building, {int? hostelBedsDefault}) =>
    clampBeds(modeCapacity(building.expand((f) => f.rooms)) ?? hostelBedsDefault ?? 1);

/// WHAT SAVING THIS PLAN WOULD DO, measured against the building it was seeded from.
///
/// Computed on the phone, and deliberately NOT the same arithmetic the server reports back in
/// [FloorPlanResult]. This one exists so an owner reads the deletion before the tap; that one
/// is what actually happened. If the two ever disagree, the one that ran inside the transaction
/// is the true one.
class FloorPlanPreview {
  const FloorPlanPreview({
    required this.lines,
    required this.blocked,
    required this.roomsAdded,
    required this.roomsRemoved,
    required this.floorsAdded,
    required this.floorsRemoved,
  });

  /// One sentence per floor that changes, in floor order. Empty when the plan is the building.
  final List<String> lines;

  /// Every room this plan would have to delete that somebody is still living in — the refusals
  /// ow_set_floor_plan would raise, named here instead. Non-empty means the save cannot work,
  /// and the button has to say so rather than find out.
  final List<RoomOccupancy> blocked;

  final int roomsAdded;
  final int roomsRemoved;
  final int floorsAdded;
  final int floorsRemoved;

  bool get changesNothing => lines.isEmpty;

  /// Whether a confirmation is owed. Adding rooms is free and needs none; taking something away
  /// is the half of this screen an owner should have to agree to out loud.
  bool get removesAnything => roomsRemoved > 0 || floorsRemoved > 0;

  /// The one line that goes beside the Save button.
  String get headline {
    if (changesNothing) return 'This is the building as it stands.';
    final parts = <String>[
      if (roomsAdded > 0) 'adding ${roomsLabel(roomsAdded)}',
      if (roomsRemoved > 0) 'removing ${roomsLabel(roomsRemoved)}',
    ];
    if (parts.isEmpty) return 'No change to the number of rooms.';
    final sentence = parts.join(' · ');
    return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
  }
}

/// Diffs [plan] against the [building] it was seeded from.
FloorPlanPreview previewPlan({
  required List<FloorSnapshot> building,
  required List<FloorPlanEntry> plan,
}) {
  final byFloor = {for (final floor in building) floor.floor: floor};
  final planned = {for (final entry in plan) entry.floor};

  final lines = <String>[];
  final blocked = <RoomOccupancy>[];
  var roomsAdded = 0;
  var roomsRemoved = 0;
  var floorsAdded = 0;
  var floorsRemoved = 0;

  for (final entry in plan) {
    final existing = byFloor[entry.floor];
    if (existing == null) {
      floorsAdded++;
      roomsAdded += entry.rooms;
      lines.add('Floor ${entry.floor} is new: ${roomsLabel(entry.rooms)} of '
          '${bedsLabel(entry.bedsPerNewRoom)} each.');
      continue;
    }
    final delta = entry.rooms - existing.roomCount;
    if (delta > 0) {
      roomsAdded += delta;
      lines.add('Floor ${entry.floor}: adding ${roomsLabel(delta)} of '
          '${bedsLabel(entry.bedsPerNewRoom)} each (${existing.roomCount} → ${entry.rooms}).');
    } else if (delta < 0) {
      roomsRemoved += -delta;
      blocked.addAll(existing.blockedBy(entry.rooms));
      lines.add('Floor ${entry.floor}: removing ${roomsLabel(-delta)} '
          '(${existing.roomCount} → ${entry.rooms}).');
    }
  }

  // Storeys the plan no longer mentions. ow_set_floor_plan removes everything above N and
  // refuses on the same terms a room shrink is refused, so their residents are blockers too.
  for (final floor in building) {
    if (planned.contains(floor.floor)) continue;
    floorsRemoved++;
    roomsRemoved += floor.roomCount;
    blocked.addAll(floor.occupiedRooms);
    lines.add('Floor ${floor.floor} goes, with its ${roomsLabel(floor.roomCount)}.');
  }

  // Floor order, so the preview reads in the order the rows above it are drawn. Sorted on the
  // NUMBER each line leads with rather than on the string: a lexical sort of "Floor 10" and
  // "Floor 2" puts the tenth storey first, which is exactly the size of building this screen
  // exists for.
  lines.sort(_byFloorNumber);
  return FloorPlanPreview(
    lines: lines,
    blocked: blocked,
    roomsAdded: roomsAdded,
    roomsRemoved: roomsRemoved,
    floorsAdded: floorsAdded,
    floorsRemoved: floorsRemoved,
  );
}

int _byFloorNumber(String a, String b) => (_leadingFloor(a) ?? 0).compareTo(_leadingFloor(b) ?? 0);

int? _leadingFloor(String line) {
  final match = RegExp(r'^Floor (\d+)').firstMatch(line);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// The refusal ow_set_floor_plan would raise, named from the counts already on this phone.
///
/// Worded differently from the server's own sentence ("Room 102 still has residents in it.
/// Move them to another bed first.") on purpose, and the difference is the tense: this one is
/// about a save that has not happened, and it must never be mistaken for a report of one that
/// did. The server's sentence is rendered verbatim when the server actually says it.
String blockedSentence(List<RoomOccupancy> blocked) {
  final names = blocked.map((r) => r.roomNumber).toList(growable: false);
  if (names.isEmpty) return '';
  if (names.length == 1) {
    return 'Room ${names.single} has residents in it, so this removal is refused. Move them to '
        'another bed first.';
  }
  final head = names.sublist(0, names.length - 1).join(', ');
  return 'Rooms $head and ${names.last} have residents in them, so this removal is refused. '
      'Move them to other beds first.';
}

String roomsLabel(int n) => '$n ${n == 1 ? 'room' : 'rooms'}';

String bedsLabel(int n) => '$n ${n == 1 ? 'bed' : 'beds'}';
