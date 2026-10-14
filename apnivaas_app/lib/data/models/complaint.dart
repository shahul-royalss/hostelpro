library;

import 'enums.dart';
import 'parse.dart';

/// public.complaints.
///
/// Raised by a resident, moved along by the Owner or the Warden. The manager cannot see them
/// (rls-policies.sql) — same least-privilege line as students.
class Complaint {
  const Complaint({
    required this.id,
    required this.hostelId,
    required this.studentId,
    required this.category,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.photoUrl,
    this.resolvedAt,
    this.resolutionNote,
    this.updatedBy,
  });

  static const columns =
      'id, hostel_id, student_id, category, title, description, photo_url, status, '
      'resolved_at, resolution_note, updated_by, created_at, updated_at';

  final String id;
  final String hostelId;
  final String studentId;
  final ComplaintCategory category;
  final String title;
  final String? description;

  /// Storage key for the photo the resident attached, if any.
  final String? photoUrl;
  final ComplaintStatus status;

  /// Set by the trigger when status becomes 'resolved'.
  final DateTime? resolvedAt;
  final String? resolutionNote;

  /// The staff user who last moved it.
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOpen => status.isOpen;

  factory Complaint.fromJson(Map<String, dynamic> row) {
    const src = 'complaints';
    return Complaint(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      studentId: reqString(row, src, 'student_id'),
      category: wireOrThrow(ComplaintCategory.values, row['category'], src, 'category'),
      title: reqString(row, src, 'title'),
      description: optString(row, 'description'),
      photoUrl: optString(row, 'photo_url'),
      status: wireOrThrow(ComplaintStatus.values, row['status'], src, 'status'),
      resolvedAt: optTimestamp(row, src, 'resolved_at'),
      resolutionNote: optString(row, 'resolution_note'),
      updatedBy: optString(row, 'updated_by'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
    );
  }
}

/// public.complaint_events — the status timeline.
///
/// Rows are written by app.complaints_after_change, never by the client (the INSERT policy
/// only admits the service role). Read-only from here by construction.
class ComplaintEvent {
  const ComplaintEvent({
    required this.id,
    required this.hostelId,
    required this.complaintId,
    required this.status,
    required this.createdAt,
    this.note,
    this.actorUserId,
  });

  static const columns =
      'id, hostel_id, complaint_id, status, note, actor_user_id, created_at';

  final String id;
  final String hostelId;
  final String complaintId;

  /// The status the complaint moved TO at this point in time.
  final ComplaintStatus status;
  final String? note;
  final String? actorUserId;
  final DateTime createdAt;

  factory ComplaintEvent.fromJson(Map<String, dynamic> row) {
    const src = 'complaint_events';
    return ComplaintEvent(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      complaintId: reqString(row, src, 'complaint_id'),
      status: wireOrThrow(ComplaintStatus.values, row['status'], src, 'status'),
      note: optString(row, 'note'),
      actorUserId: optString(row, 'actor_user_id'),
      createdAt: reqTimestamp(row, src, 'created_at'),
    );
  }
}
