library;

import 'enums.dart';
import 'parse.dart';

/// public.hostels — one tenant.
///
/// Only Super Admin can insert or update this table (rls-policies.sql), with one exception:
/// the owner may edit `rules`, through the ow_update_hostel_rules RPC. Nothing in this class
/// enforces that; it is stated so a screen does not build an edit form that always fails.
class Hostel {
  const Hostel({
    required this.id,
    required this.name,
    required this.ownerUserId,
    required this.totalFloors,
    required this.totalRooms,
    required this.bedsPerRoomDefault,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.address,
    this.rules,
  });

  /// Kept next to [fromJson] so a column can never be added to one and not the other.
  static const columns =
      'id, name, owner_user_id, total_floors, total_rooms, beds_per_room_default, '
      'address, rules, status, created_at, updated_at';

  final String id;
  final String name;
  final String ownerUserId;
  final int totalFloors;
  final int totalRooms;
  final int bedsPerRoomDefault;
  final String? address;

  /// Free text, owner-editable, up to 20 000 characters (truncated server-side).
  final String? rules;
  final HostelStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Hostel.fromJson(Map<String, dynamic> row) {
    const src = 'hostels';
    return Hostel(
      id: reqString(row, src, 'id'),
      name: reqString(row, src, 'name'),
      ownerUserId: reqString(row, src, 'owner_user_id'),
      totalFloors: reqInt(row, src, 'total_floors'),
      totalRooms: reqInt(row, src, 'total_rooms'),
      bedsPerRoomDefault: reqInt(row, src, 'beds_per_room_default'),
      address: optString(row, 'address'),
      rules: optString(row, 'rules'),
      status: wireOrThrow(HostelStatus.values, row['status'], src, 'status'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}

/// The one row public.st_hostel_contacts() returns.
///
/// Exists because of Hard rule §4.8: students cannot read public.users at all, so "who do I
/// call about the broken geyser" cannot be answered by a join. This SECURITY DEFINER function
/// hands back exactly the four names and two numbers a resident is allowed to see, and nothing
/// else — no user ids, no emails, no other residents.
class HostelContacts {
  const HostelContacts({
    required this.hostelName,
    this.address,
    this.rules,
    this.wardenName,
    this.wardenPhone,
    this.managerName,
    this.managerPhone,
    this.ownerName,
  });

  final String hostelName;
  final String? address;
  final String? rules;
  final String? wardenName;
  final String? wardenPhone;
  final String? managerName;
  final String? managerPhone;
  final String? ownerName;

  factory HostelContacts.fromJson(Map<String, dynamic> row) {
    const src = 'st_hostel_contacts';
    return HostelContacts(
      hostelName: reqString(row, src, 'hostel_name'),
      address: optString(row, 'address'),
      rules: optString(row, 'rules'),
      wardenName: optString(row, 'warden_name'),
      wardenPhone: optString(row, 'warden_phone'),
      managerName: optString(row, 'manager_name'),
      managerPhone: optString(row, 'manager_phone'),
      ownerName: optString(row, 'owner_name'),
    );
  }
}
