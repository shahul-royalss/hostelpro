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
  });

  static const columns = 'id, hostel_id, floor_number, created_at, updated_at';

  final String id;
  final String hostelId;

  /// Unique per hostel. Ground floor is 0 or 1 depending on how the hostel was scaffolded —
  /// the database does not impose a convention, so never render this as "Floor ${n + 1}".
  final int floorNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Floor.fromJson(Map<String, dynamic> row) {
    const src = 'floors';
    return Floor(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      floorNumber: reqInt(row, src, 'floor_number'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}

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
