library;

import 'enums.dart';
import 'parse.dart';

/// public.floors — a storey. Created only by the SA scaffolding RPCs; the app reads it.
class Floor {
  const Floor({
    required this.id,
    required this.hostelId,
    required this.floorNumber,
    required this.createdAt,
    required this.updatedAt,
    this.name,
  });

  static const columns = 'id, hostel_id, floor_number, name, created_at, updated_at';

  final String id;
  final String hostelId;

  /// Unique per hostel. Ground floor is 0 or 1 depending on how the hostel was scaffolded —
  /// the database does not impose a convention, so never render this as "Floor ${n + 1}".
  final int floorNumber;

  /// What this floor is CALLED, when it is called anything: "Ground floor", "Terrace",
  /// "Girls' wing". Optional, trimmed, 1–40 characters, and null for the great majority of
  /// floors — [floorLabel] is what turns the pair into words, so no screen has to decide.
  final String? name;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Floor.fromJson(Map<String, dynamic> row) {
    const src = 'floors';
    return Floor(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      floorNumber: reqInt(row, src, 'floor_number'),
      name: optString(row, 'name'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}

/// WHAT TO CALL A FLOOR.
///
/// The number is the identity — ow_set_floor_plan reasons in 1..N and room numbers are derived
/// from it — and the name is a label on top. Every screen that prints a storey goes through
/// here, so a PG that calls its ground floor "Ground floor" sees that everywhere, and one that
/// has never named a floor sees exactly what it always saw.
///
/// The name is NOT decorated with the number. "Terrace (Floor 4)" is the kind of thing a
/// screen adds because it does not trust the person who typed the name; where the number
/// genuinely matters — the layout editor, which is the place floors are added and removed —
/// that screen prints both itself.
String floorLabel(int number, String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'Floor $number';
  return trimmed;
}

/// HOW MANY BEDS A SINGLE ROOM MAY HOLD.
///
/// `rooms.capacity` is `check (capacity between 1 and 12)`, and public.ow_set_floor_plan says
/// the same thing in words — "Floor N: a room holds between 1 and 12 beds." — so a bad value is
/// refused with a sentence rather than a constraint name.
///
/// ── WHY THESE LIVE HERE AND NOT IN THE SCREEN THAT FIRST NEEDED THEM ─────────────────────
///
/// They started in features/owner/rooms/floor_plan_edit.dart, which was fine while the layout
/// editor was the only thing that knew them. It is not: shared/rooms/edit_room_sheet.dart caps
/// its own stepper, and it had a bare `12` written into the widget — so the two agreed only by
/// coincidence, and a shared widget reaching into a feature folder to fix that would have been
/// the wrong direction. These describe a COLUMN, so they belong beside the model of it.
///
/// ── RAISING THE CEILING ──────────────────────────────────────────────────────────────────
///
/// db/migrations/2026-09-07-per-room-beds.sql widens both database CHECKs to 20, because twelve
/// was a number rather than a rule and Indian hostels run dormitories past it. THAT MIGRATION IS
/// NOT YET APPLIED, and this constant deliberately still says 12: a stepper that offers a value
/// the server will reject is a trap, and the whole argument of the layout editor is that the
/// refusal is said before the tap. Run the migration and this becomes 20 — it is the only place
/// the app states the bound.
const int minBedsPerRoom = 1;
const int maxBedsPerRoom = 12;

/// [beds] brought inside the bounds the server will accept.
int clampBeds(int beds) => beds < minBedsPerRoom
    ? minBedsPerRoom
    : (beds > maxBedsPerRoom ? maxBedsPerRoom : beds);

/// public.rooms.
///
/// `capacity` is kept in step with the bed rows by a trigger (app.rooms_capacity_sync), so
/// raising it creates beds and lowering it deletes free ones. Treat it as the number of beds
/// that exist, not as a target to reconcile in the client.
class Room {
  const Room({
    required this.id,
    required this.hostelId,
    required this.floorId,
    required this.roomNumber,
    required this.capacity,
    required this.createdAt,
    required this.updatedAt,
  });

  static const columns =
      'id, hostel_id, floor_id, room_number, capacity, created_at, updated_at';

  final String id;
  final String hostelId;
  final String floorId;

  /// Text, not a number: real hostels use "A-101" and "12B".
  final String roomNumber;
  final int capacity;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Room.fromJson(Map<String, dynamic> row) {
    const src = 'rooms';
    return Room(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      floorId: reqString(row, src, 'floor_id'),
      roomNumber: reqString(row, src, 'room_number'),
      capacity: reqInt(row, src, 'capacity'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}

/// public.beds.
///
/// §4.8 — a student can only select beds in their OWN room, because beds.student_id would
/// otherwise map every occupied bed in the building to another resident's user id. That
/// restriction is an RLS policy; this class simply reflects whatever rows came back.
class Bed {
  const Bed({
    required this.id,
    required this.hostelId,
    required this.roomId,
    required this.bedNumber,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.studentId,
  });

  static const columns =
      'id, hostel_id, room_id, bed_number, status, student_id, created_at, updated_at';

  final String id;
  final String hostelId;
  final String roomId;
  final int bedNumber;

  /// Kept in step with [studentId] by app.beds_guard; the two never disagree.
  final BedStatus status;

  /// The resident occupying this bed, or null when it is free.
  final String? studentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isFree => studentId == null;

  factory Bed.fromJson(Map<String, dynamic> row) {
    const src = 'beds';
    return Bed(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      roomId: reqString(row, src, 'room_id'),
      bedNumber: reqInt(row, src, 'bed_number'),
      status: wireOrThrow(BedStatus.values, row['status'], src, 'status'),
      studentId: optString(row, 'student_id'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}
