library;

import 'enums.dart';
import 'parse.dart';

/// public.students — a resident.
///
/// WHO CAN READ THIS. Warden and Owner see every resident of their hostel; a student sees only
/// their own row; the MANAGER SEES NOTHING HERE. That last one is deliberate least privilege
/// (rls-policies.sql, checklist §28) — the manager's job is expenses, revenue, tasks and the
/// mess menu, none of which needs a resident's phone number, guardian or ID proof. A manager
/// screen that queries students will correctly come back empty, so do not build one.
class Student {
  const Student({
    required this.id,
    required this.hostelId,
    required this.fullName,
    required this.phone,
    required this.dateOfJoining,
    required this.monthlyFee,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.email,
    this.photoUrl,
    this.guardianName,
    this.guardianPhone,
    this.permanentAddress,
    this.idProofType,
    this.idProofUrl,
    this.roomId,
    this.bedId,
    this.vacatedAt,
    this.deletedAt,
  });

  static const columns =
      'id, hostel_id, user_id, full_name, phone, email, photo_url, guardian_name, '
      'guardian_phone, permanent_address, id_proof_type, id_proof_url, date_of_joining, '
      'room_id, bed_id, monthly_fee, status, vacated_at, created_at, updated_at, deleted_at';

  final String id;
  final String hostelId;

  /// The auth account this resident signs in with. Null for a resident registered without a
  /// login — the schema allows it, so do not assume a student row implies a user row.
  final String? userId;

  final String fullName;

  /// NOT NULL, and the student's login identifier (mapped to a synthetic email — see
  /// core/auth/auth_controller.dart). Unique among non-vacated students.
  final String phone;
  final String? email;

  /// A storage key, not a URL you can hand to Image.network without signing it.
  final String? photoUrl;
  final String? guardianName;
  final String? guardianPhone;
  final String? permanentAddress;
  final String? idProofType;
  final String? idProofUrl;

  /// Plain `date`, defaulted to the day of registration.
  final DateTime dateOfJoining;

  /// Null while a resident is registered but not yet placed in a room.
  final String? roomId;
  final String? bedId;

  /// The agreed rent. Copied onto each fee_payments row as amount_due when a payment is
  /// recorded, so changing it does not rewrite history.
  final double monthlyFee;

  final StudentStatus status;
  final DateTime? vacatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft delete (§4.10). Rows are never hard-deleted from the app.
  final DateTime? deletedAt;

  bool get isResident => status.isResident;
  bool get hasBed => bedId != null;

  factory Student.fromJson(Map<String, dynamic> row) {
    const src = 'students';
    return Student(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      userId: optString(row, 'user_id'),
      fullName: reqString(row, src, 'full_name'),
      phone: reqString(row, src, 'phone'),
      email: optString(row, 'email'),
      photoUrl: optString(row, 'photo_url'),
      guardianName: optString(row, 'guardian_name'),
      guardianPhone: optString(row, 'guardian_phone'),
      permanentAddress: optString(row, 'permanent_address'),
      idProofType: optString(row, 'id_proof_type'),
      idProofUrl: optString(row, 'id_proof_url'),
      dateOfJoining: reqDate(row, src, 'date_of_joining'),
      roomId: optString(row, 'room_id'),
      bedId: optString(row, 'bed_id'),
      monthlyFee: reqDouble(row, src, 'monthly_fee'),
      status: wireOrThrow(StudentStatus.values, row['status'], src, 'status'),
      vacatedAt: optTimestamp(row, src, 'vacated_at'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
      deletedAt: optTimestamp(row, src, 'deleted_at'),
    );
  }
}

/// One row of public.st_my_roommates().
///
/// Name, phone and bed number — that is the whole permitted set (§4.8). No photo, because the
/// storage key is itself a capability; no address; no id. A screen wanting more than this is
/// asking for something a resident is not allowed to have.
class Roommate {
  const Roommate({
    required this.studentId,
    required this.fullName,
    required this.phone,
    this.bedNumber,
  });

  final String studentId;
  final String fullName;
  final String phone;

  /// Null when that roommate has not been assigned a bed yet.
  final int? bedNumber;

  factory Roommate.fromJson(Map<String, dynamic> row) {
    const src = 'st_my_roommates';
    return Roommate(
      studentId: reqString(row, src, 'student_id'),
      fullName: reqString(row, src, 'full_name'),
      phone: reqString(row, src, 'phone'),
      bedNumber: optInt(row, src, 'bed_number'),
    );
  }
}
