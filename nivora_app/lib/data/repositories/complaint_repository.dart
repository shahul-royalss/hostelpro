library;

import '../models/models.dart';
import 'repository.dart';

/// Complaints and their timeline.
///
/// TABLES: public.complaints, public.complaint_events.
final class ComplaintRepository extends Repository {
  const ComplaintRepository(super.db);

  /// One page of complaints, newest first.
  ///
  /// The SAME method serves the staff queue and a resident's own list. It is not two methods
  /// because it is not two queries: the complaints policy already narrows a student to
  /// `student_id = app.current_student_id()`, so a resident calling this gets their own
  /// complaints and a warden gets the hostel's. Adding a client-side `if (isStudent)` branch
  /// would duplicate a control that has already run and would drift from it.
  Future<PagedResult<Complaint>> page({
    required String hostelId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
    ComplaintStatus? status,
    ComplaintCategory? category,

    /// True on the staff queue: hides resolved complaints without hiding the ability to look.
    bool openOnly = false,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        var query = db
            .from('complaints')
            .select(Complaint.columns)
            .eq('hostel_id', hostelId);

        if (status != null) {
          query = query.eq('status', status.wire);
        } else if (openOnly) {
          query = query.neq('status', ComplaintStatus.resolved.wire);
        }
        if (category != null) query = query.eq('category', category.wire);

        final rows = await query
            .order('created_at', ascending: false)
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rows.map(Complaint.fromJson).toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  Future<Complaint?> byId(String complaintId) => guard(() async {
        final row = await db
            .from('complaints')
            .select(Complaint.columns)
            .eq('id', complaintId)
            .maybeSingle();
        return row == null ? null : Complaint.fromJson(row);
      });

  /// The status history for one complaint, oldest first.
  ///
  /// Written entirely by app.complaints_after_change; the INSERT policy admits only the service
  /// role, so this is a read-only view of what actually happened rather than a log the client
  /// contributes to. Bounded by the number of status changes, so not paginated.
  Future<List<ComplaintEvent>> timeline(String complaintId) => guard(() async {
        final rows = await db
            .from('complaint_events')
            .select(ComplaintEvent.columns)
            .eq('complaint_id', complaintId)
            .order('created_at', ascending: true);
        return rows.map(ComplaintEvent.fromJson).toList(growable: false);
      });

  /// Raise a complaint. Residents only.
  ///
  /// The insert policy requires `student_id = app.current_student_id()` AND
  /// `hostel_id = app.user_hostel_id()`, so passing someone else's ids fails at the server
  /// with 42501 rather than succeeding. Both are still passed explicitly because the columns
  /// are NOT NULL — the server checks them, it does not fill them in.
  Future<Complaint> create({
    required String hostelId,
    required String studentId,
    required ComplaintCategory category,
    required String title,
    String? description,
    String? photoUrl,
  }) =>
      guard(() async {
        final row = await db
            .from('complaints')
            .insert({
              'hostel_id': hostelId,
              'student_id': studentId,
              'category': category.wire,
              'title': title,
              'description': ?description,
              'photo_url': ?photoUrl,
            })
            .select(Complaint.columns)
            .single();
        return Complaint.fromJson(row);
      });

  /// Move a complaint along. Owner and warden only.
  ///
  /// `resolved_at`, the timeline row and the resident's notification are all produced by
  /// triggers off this one update — do not write them from here.
  Future<Complaint> updateStatus({
    required String complaintId,
    required ComplaintStatus status,
    String? resolutionNote,
  }) =>
      guard(() async {
        final row = await db
            .from('complaints')
            .update({
              'status': status.wire,
              'resolution_note': ?resolutionNote,
              // Stamped so the timeline can say who moved it; the trigger reads this column.
              'updated_by': ?db.auth.currentUser?.id,
            })
            .eq('id', complaintId)
            .select(Complaint.columns)
            .single();
        return Complaint.fromJson(row);
      });
}
