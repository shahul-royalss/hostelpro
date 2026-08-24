library;

import '../../../data/models/models.dart';
import '../../../data/repositories/repository.dart';
import 'warden_models.dart';

/// The writes and reads the warden needs that lib/data does not carry yet.
///
/// TABLES: public.students (register, bed assignment), public.leaves, public.visitors.
///
/// Everything else on the warden's screens goes through the shared repositories — residents,
/// the fee ledger, wd_record_payment, wd_vacate_student, complaints, rpc_room_occupancy,
/// rpc_hostel_stats. This class exists only for the gaps, and it extends the same [Repository]
/// base so it inherits the same anon-key client and the same `guard` conversion. When a second
/// role needs leaves or visitors, move this file into lib/data rather than copying it.
///
/// NONE OF THE FILTERS BELOW ARE SECURITY. The hostel_id predicates narrow what comes back and
/// make an accidental cross-tenant write fail loudly instead of quietly; what actually refuses
/// it is `students_update`, `leaves_update` and the visitors policies in rls-policies.sql, plus
/// app.hostel_writable() which turns every one of them off when the subscription lapses.
final class WardenRepository extends Repository {
  const WardenRepository(super.db);

  // ───────────────────────────────────────────────────────────────────────────
  // RESIDENTS
  // ───────────────────────────────────────────────────────────────────────────

  /// Register a resident. Warden only, and blocked once the subscription lapses.
  ///
  /// THIS DOES NOT CREATE A LOGIN, and that is a deliberate limit of the mobile client rather
  /// than an oversight. The web app calls public.wd_register_student, whose first argument is
  /// `p_user_id uuid — freshly created auth user id`: it expects the caller to have already
  /// minted an auth account through the Admin API, which needs the SERVICE-ROLE key. That key
  /// is server-only and must never be compiled into an APK, so this app cannot mint one and
  /// therefore cannot call that RPC honestly.
  ///
  /// What it does instead is the plain INSERT that `students_insert` admits — a resident record
  /// with user_id null. The schema explicitly allows it (students.user_id is nullable, and
  /// app.students_identity_guard only checks the link when it is non-null), and the result is
  /// the true state of affairs: the person is on the roster, in a bed, and on the fee ledger,
  /// but has no app login until one is created from the web console. The registration screen
  /// says exactly that rather than implying credentials were issued.
  ///
  /// Bed placement happens through [bedId] on this same insert: app.students_bed_guard fills in
  /// room_id from the bed and refuses one that is occupied or belongs to another hostel, and
  /// app.students_bed_sync flips the bed to occupied. That is why the bed is set here rather
  /// than by a follow-up update — an insert that succeeded and a bed update that failed would
  /// leave a resident who exists but is nowhere.
  Future<Student> registerStudent({
    required String hostelId,
    required String fullName,
    required String phone,
    required double monthlyFee,
    DateTime? dateOfJoining,
    String? bedId,
    String? email,
    String? guardianName,
    String? guardianPhone,
    String? permanentAddress,
  }) =>
      guard(() async {
        final row = await db
            .from('students')
            .insert({
              'hostel_id': hostelId,
              'full_name': fullName,
              'phone': phone,
              'monthly_fee': monthlyFee,
              // Omitted rather than defaulted to today in Dart: the column already defaults to
              // current_date, and the server's date is the one the ledger is keyed against.
              if (dateOfJoining != null) 'date_of_joining': toDateWire(dateOfJoining),
              'bed_id': ?bedId,
              'email': ?email,
              'guardian_name': ?guardianName,
              'guardian_phone': ?guardianPhone,
              'permanent_address': ?permanentAddress,
              'created_by': ?db.auth.currentUser?.id,
            })
            .select(Student.columns)
            .single();
        return Student.fromJson(row);
      });

  /// Put a resident in a bed, move them to another, or take them out of one ([bedId] null).
  ///
  /// WRITTEN AGAINST students.bed_id, NOT beds.student_id. app.beds_guard rejects the latter
  /// outright — "Assign beds by updating the student record, not the bed." — because the two
  /// columns are kept in step by a trigger, and letting a client write both is how a bed ends
  /// up holding one resident while a resident points at another bed.
  ///
  /// Every rule that matters is server-side: the bed must exist, belong to this hostel, and be
  /// free (app.students_bed_guard raises P0001 by bed number), and the partial unique index
  /// students_one_active_per_bed settles the race between two wardens assigning the same bed at
  /// the same moment. Both surface as a message written for a person.
  ///
  /// Returns the updated resident, whose room_id the trigger has already rewritten.
  ///
  /// NOT `.maybeSingle()`. On a SELECT that returns nothing, maybeSingle() hands back null as
  /// you would expect — but after an UPDATE it throws a raw HTTP 406 instead, which
  /// [AppFailure] classifies on the status code and turns into "Something did not work."
  /// Verified against the live database: an update matching zero rows came back as
  /// `code=406 msg={"code":"PGRST116","details":"The result contains 0 rows"...}`, so the null
  /// check below would never have run and the message under it was dead code. Asking for the
  /// LIST and looking at its length is the same round trip and cannot misfire.
  Future<Student> assignBed({
    required String studentId,
    required String hostelId,
    required String? bedId,
  }) =>
      guard(() async {
        final rows = await db
            .from('students')
            .update({'bed_id': bedId})
            .eq('id', studentId)
            .eq('hostel_id', hostelId)
            // A checked-out resident holds no bed (the guard nulls it), so allowing this would
            // silently do nothing. Refusing loudly is the honest outcome.
            .neq('status', StudentStatus.vacated.wire)
            .select(Student.columns);
        if (rows.isEmpty) {
          throw const NotFoundFailure('That resident is no longer on the roster.');
        }
        return Student.fromJson(rows.first);
      });

  /// Residents on the roster who are not in a bed yet.
  ///
  /// The other half of the room screen: tapping a free bed asks "who goes here?", and the
  /// honest answer is the people who are registered and have nowhere to sleep. Filtered by
  /// Postgres on `bed_id is null`, NOT by walking a fetched page — a hostel with 200 residents
  /// returns them twenty at a time, and the three without beds are rarely in the first twenty.
  ///
  /// Not paginated: this list is short by definition, and a hostel where it is not has a
  /// bigger problem than pagination. [limit] is a rail.
  Future<List<Student>> awaitingBed({required String hostelId, int limit = 100}) =>
      guard(() async {
        final rows = await db
            .from('students')
            .select(Student.columns)
            .eq('hostel_id', hostelId)
            .isFilter('bed_id', null)
            .isFilter('deleted_at', null)
            .neq('status', StudentStatus.vacated.wire)
            .order('full_name', ascending: true)
            .limit(limit);
        return rows.map(Student.fromJson).toList(growable: false);
      });

  // ───────────────────────────────────────────────────────────────────────────
  // LEAVE REQUESTS
  // ───────────────────────────────────────────────────────────────────────────

  /// Leave requests, pending ones oldest first so whoever has waited longest is answered first.
  ///
  /// Not paginated: a queue of pending requests that does not fit on a screen is a queue nobody
  /// is working. [limit] is a safety rail, not a page size.
  Future<List<LeaveRequest>> leaves({
    required String hostelId,
    LeaveStatus? status = LeaveStatus.pending,
    int limit = 100,
  }) =>
      guard(() async {
        var query =
            db.from('leaves').select(LeaveRequest.columns).eq('hostel_id', hostelId);
        if (status != null) query = query.eq('status', status.wire);
        final rows = await query
            // Pending: oldest first (a queue). Decided: newest first (a history).
            .order('created_at', ascending: status == LeaveStatus.pending)
            .limit(limit);
        return rows.map(LeaveRequest.fromJson).toList(growable: false);
      });

  /// Approve or reject a leave request.
  ///
  /// `decided_at` is sent rather than left to app.leaves_after_change. The trigger does stamp
  /// it when null, but by issuing a second UPDATE against the row it has just seen; sending the
  /// timestamp with the decision is what the web app does, so both clients write the same shape
  /// and neither depends on the recursive path. The resident's notification and the on_leave
  /// student status are the trigger's job and must not be written from here.
  Future<void> decideLeave({
    required String leaveId,
    required LeaveStatus decision,
    String? note,
  }) =>
      guard(() async {
        if (!decision.isDecided) {
          throw const InvalidInputFailure('Choose approve or reject.');
        }
        final rows = await db
            .from('leaves')
            .update({
              'status': decision.wire,
              'decided_by': ?db.auth.currentUser?.id,
              'decided_at': DateTime.now().toUtc().toIso8601String(),
              'decision_note': ?note,
            })
            .eq('id', leaveId)
            // Two wardens on two phones: whoever gets there second changes nothing and is told
            // so, rather than overwriting a decision the resident has already been notified of.
            .eq('status', LeaveStatus.pending.wire)
            // A list, not maybeSingle() — see the note on [assignBed].
            .select('id');
        if (rows.isEmpty) {
          throw const ConflictFailure('That request has already been decided.');
        }
      });

  // ───────────────────────────────────────────────────────────────────────────
  // VISITORS
  // ───────────────────────────────────────────────────────────────────────────

  /// Everyone signed in and not yet signed out, longest-standing first.
  ///
  /// This is a DIFFERENT NUMBER from rpc_hostel_stats.visitors_today, which counts check-ins
  /// against the IST calendar day whether or not the guest has left. A screen must not label
  /// one with the other's words: "3 visitors today" and "3 visitors on site" can both be true
  /// while describing different people.
  Future<List<VisitorLog>> visitorsOnSite({
    required String hostelId,
    int limit = 100,
  }) =>
      guard(() async {
        final rows = await db
            .from('visitors')
            .select(VisitorLog.columns)
            .eq('hostel_id', hostelId)
            .isFilter('check_out_at', null)
            .order('check_in_at', ascending: true)
            .limit(limit);
        return rows.map(VisitorLog.fromJson).toList(growable: false);
      });

  /// Sign a visitor out. Warden only — visitors_update names the role.
  Future<void> checkOutVisitor(String visitorId) => guard(() async {
        final rows = await db
            .from('visitors')
            .update({'check_out_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', visitorId)
            // Already signed out: leave the original time alone. The first check-out is the
            // true one, and a second tap must not rewrite the log to lengthen the visit.
            .isFilter('check_out_at', null)
            // A list, not maybeSingle() — see the note on [assignBed].
            .select('id');
        if (rows.isEmpty) {
          throw const ConflictFailure('That visitor is already checked out.');
        }
      });
}
