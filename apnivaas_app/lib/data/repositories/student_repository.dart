library;

import '../models/models.dart';
import 'repository.dart';

/// Residents.
///
/// TABLES: public.students.
/// RPCs:   public.st_my_roommates(), public.wd_vacate_student().
///
/// VISIBILITY, restated because it is easy to get wrong: warden and owner see the hostel's
/// residents, a student sees only their own row, and the MANAGER SEES NOTHING. Every method
/// here returns an empty list or null for a manager, correctly.
final class StudentRepository extends Repository {
  const StudentRepository(super.db);

  /// One page of residents, newest joiners last.
  ///
  /// PAGINATED because this is the list that grows without limit. A 200-bed PG returns 200
  /// rows of PII — photos, guardians, addresses — to render the twenty that fit on screen.
  /// [PagedResult] fetches one row past the page to know whether a next one exists.
  ///
  /// [search] matches name or phone, case-insensitively, in Postgres. Filtering a fetched page
  /// in Dart would search only the rows already downloaded, which looks identical on a seeded
  /// demo and is wrong the moment there are more than twenty residents.
  Future<PagedResult<Student>> page({
    required String hostelId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
    String? search,
    StudentStatus? status,

    /// Default false: checked-out residents are history, not roster.
    bool includeVacated = false,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        var query = db
            .from('students')
            .select(Student.columns)
            .eq('hostel_id', hostelId)
            .isFilter('deleted_at', null);

        if (status != null) {
          query = query.eq('status', status.wire);
        } else if (!includeVacated) {
          query = query.neq('status', StudentStatus.vacated.wire);
        }

        final term = search == null ? '' : sanitizeSearch(search);
        if (term.isNotEmpty) {
          query = query.or('full_name.ilike.*$term*,phone.ilike.*$term*');
        }

        final rows = await query
            .order('full_name', ascending: true)
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rows.map(Student.fromJson).toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  /// One resident. Null when the row is not visible to this caller.
  Future<Student?> byId(String studentId) => guard(() async {
        // A null from here is drawn as a sentence about the reader ("not visible",
        // "belongs to another hostel", "no record for this account"). That sentence is
        // earned only when a live credential asked — a dead session makes this an
        // anonymous read whose null means nothing. See Repository.requireLiveSession.
        requireLiveSession('students.byId');
        final row = await db
            .from('students')
            .select(Student.columns)
            .eq('id', studentId)
            .maybeSingle();
        return row == null ? null : Student.fromJson(row);
      });

  /// The signed-in student's own record.
  ///
  /// Keyed on user_id, not on a stored student id: the student's own row is the only one their
  /// RLS policy admits, so this is exact whatever else is in the table. Returns null for staff,
  /// who have no resident row.
  Future<Student?> me() => guard(() async {
        // ═══ THE STUDENT-FACING SHAPE OF THE SUPER ADMIN'S BUG ═══
        // ResidentBuilder draws a null from here as "No resident record for this account —
        // ask your warden to check your registration." For a resident whose session died on
        // the bus that is an invented errand: the read went out as `anon`, RLS returned
        // nothing, and a young person in a strange city goes looking for a member of staff
        // over an expired token. The `userId == null` line below used to hand back exactly
        // that null, silently.
        requireLiveSession('students.me');
        final userId = db.auth.currentUser?.id;
        // Unreachable now — requireLiveSession has already refused a client with no session —
        // and kept because a null here would still be a null nobody could explain.
        if (userId == null) return null;
        final row = await db
            .from('students')
            .select(Student.columns)
            .eq('user_id', userId)
            .neq('status', StudentStatus.vacated.wire)
            .maybeSingle();
        return row == null ? null : Student.fromJson(row);
      });

  /// Everyone else in the caller's room — name, phone and bed number, nothing more.
  ///
  /// A join would return the whole student row, which §4.8 forbids between residents. This RPC
  /// is SECURITY DEFINER precisely so it can look past that policy and hand back the three
  /// fields that are permitted.
  Future<List<Roommate>> roommates() => guard(() async {
        final data = await db.rpc('st_my_roommates');
        return rpcRows(data, 'st_my_roommates')
            .map(Roommate.fromJson)
            .toList(growable: false);
      });

  /// Residents in one room. Staff only, by RLS.
  Future<List<Student>> inRoom(String roomId) => guard(() async {
        final rows = await db
            .from('students')
            .select(Student.columns)
            .eq('room_id', roomId)
            .neq('status', StudentStatus.vacated.wire)
            .isFilter('deleted_at', null)
            .order('full_name', ascending: true);
        return rows.map(Student.fromJson).toList(growable: false);
      });

  /// Check a resident out: frees the bed and deactivates the login, in one transaction.
  ///
  /// Not an UPDATE from here. Doing it client-side would take three statements — student
  /// status, bed release, user deactivation — and a dropped connection between any two leaves a
  /// bed that nobody can be assigned to and an account that can still sign in. The RPC does all
  /// three or none.
  Future<void> vacate(String studentId) => guardWrite(() async {
        await db.rpc('wd_vacate_student', params: {'p_student_id': studentId});
      }, unresolved: 'Reload the roster to see whether the resident is already checked out; if '
          'they are not, doing it again is safe.');

  /// Edit a resident's own details. Warden and owner only (RLS), and blocked once the
  /// subscription lapses.
  ///
  /// Bed moves are NOT done here: app.students_bed_guard and app.students_bed_sync own that
  /// relationship, and changing bed_id behind them is how two people end up in one bed.
  Future<Student> update({
    required String studentId,
    String? fullName,
    String? email,
    String? guardianName,
    String? guardianPhone,
    String? permanentAddress,
    double? monthlyFee,
  }) =>
      guardWrite(() async {
        final patch = <String, dynamic>{
          'full_name': ?fullName,
          'email': ?email,
          'guardian_name': ?guardianName,
          'guardian_phone': ?guardianPhone,
          'permanent_address': ?permanentAddress,
          'monthly_fee': ?monthlyFee,
        };
        if (patch.isEmpty) {
          throw const InvalidInputFailure('Nothing to change.');
        }
        final row = await db
            .from('students')
            .update(patch)
            .eq('id', studentId)
            .select(Student.columns)
            .single();
        return Student.fromJson(row);
      }, unresolved: 'Reload the resident to see which details were saved; saving the same ones '
          'again is safe.');
}
