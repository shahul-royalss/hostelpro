library;

import '../capture.dart';
import '../models/models.dart';
import '../models/parse.dart';
import 'complaint_photos.dart';
import 'repository.dart';

/// RAISING A COMPLAINT, AS A CONTRACT RATHER THAN AS A CLASS.
///
/// [ComplaintRepository] is `final`, so nothing outside this library may implement it — which
/// is right for a class that owns a PostgREST client, and fatal for a widget test of the sheet
/// that calls it. The one method a RESIDENT invokes is named here instead, and
/// `complaintFilingProvider` is typed by this rather than by the repository, exactly as
/// `wardenRegistrationsProvider` is typed by [StudentRegistrations] for the registration form.
///
/// The staff half ([ComplaintRepository.updateStatus]) is deliberately NOT in here: it is a
/// different actor, a different policy and a different screen, and widening this interface to
/// cover it would let a fake stand in for a write this seam was never opened for.
abstract interface class ComplaintFiling {
  Future<Complaint> create({
    required String hostelId,
    required String studentId,
    required ComplaintCategory category,
    required String title,
    String? description,
    CapturedDocument? photo,
  });
}

/// WHO WROTE A LINE OF THE TIMELINE.
///
/// `complaint_events.actor_user_id` is a uuid. On its own it is unreadable, and a timeline that
/// says only "Resolved · 3 Sep" answers "what happened" while leaving "who did it" — the half an
/// owner actually asks about — unanswered.
///
/// A VIEW TYPE, NOT A MODEL, and that is why it lives beside the query instead of in
/// data/models: it is two columns of `public.users` narrowed to the one question this feature
/// asks of them, not the users row, and nothing else in the app should start reading staff
/// records through it.
///
/// NOT EVERY ACTOR RESOLVES, AND THAT IS CORRECT. `users_select` lets an owner or a warden read
/// the accounts of their own hostel and lets a resident read only their own. So the staff view
/// gets every name and the resident's view gets one — which is why the resident's sheet does not
/// ask. A missing id is drawn as no name at all; never as "Unknown", which would read as a
/// deleted account rather than as a row this reader may not see.
final class ComplaintActor {
  const ComplaintActor({required this.id, required this.fullName, required this.role});

  final String id;
  final String fullName;

  /// The wire value of `public.user_role` — 'owner', 'manager', 'warden', 'student',
  /// 'super_admin'. Kept as the server's own string: this file has no business inventing a
  /// second spelling of an enum the database already defines.
  final String role;

  /// Sentence case for a line of prose, e.g. "Warden". Empty for a role this app has no word
  /// for, so the caller prints the name alone rather than the name and a shrug.
  String get roleLabel => switch (role) {
        'owner' => 'Owner',
        'manager' => 'Manager',
        'warden' => 'Warden',
        'student' => 'Resident',
        'super_admin' => 'Nivora support',
        _ => '',
      };
}

/// Complaints and their timeline.
///
/// TABLES: public.complaints, public.complaint_events.
/// BUCKET: complaint-photos (private) — reached only through [ComplaintPhotos]; see the note
/// on [attachPhoto].
final class ComplaintRepository extends Repository implements ComplaintFiling {
  const ComplaintRepository(super.db);

  /// The photo half of the same boundary: rows here, bytes there.
  ///
  /// Built per call rather than injected, because it is a stateless wrapper around the same
  /// client this class already holds — there is nothing for a second instance to disagree
  /// about, and a constructor parameter would have to be threaded through every call site of
  /// [ComplaintRepository] for no gain.
  ComplaintPhotos get photos => ComplaintPhotos(db);

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
        // A null from here is drawn as a sentence about the reader ("not visible",
        // "belongs to another hostel", "no record for this account"). That sentence is
        // earned only when a live credential asked — a dead session makes this an
        // anonymous read whose null means nothing. See Repository.requireLiveSession.
        requireLiveSession('complaints.byId');
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

  /// A short-lived URL for one complaint's photo, or null when it has none.
  ///
  /// `complaints.photo_url` is a storage KEY into a PRIVATE bucket, so this is the only way to
  /// draw it. Who may see it is decided by `complaints_select`, re-asked on the server against
  /// the caller's own token — see [ComplaintPhotos.signedUrl]. Nothing here narrows or widens
  /// that, which is why the same method serves the resident, the warden and the owner.
  Future<Uri?> photoUrl(String complaintId) => photos.signedUrl(complaintId);

  /// The people behind a timeline's `actor_user_id`s, by id.
  ///
  /// ONE ROUND TRIP FOR THE WHOLE TIMELINE, not one per row: a complaint reopened twice has
  /// five events and at most two distinct actors, and five `.eq('id', …)` reads to draw two
  /// names would be five requests on a stairwell connection.
  ///
  /// WHAT AN ABSENT ID MEANS IS NOT DECIDED HERE. `users_select` answers this query for the
  /// staff of a hostel and refuses everyone else's row without erroring, so an id that comes
  /// back with no name may be a reader who is not entitled to it. The screens print the event
  /// without a name in that case — see the note on [ComplaintActor].
  Future<Map<String, ComplaintActor>> actors(Iterable<String> userIds) => guard(() async {
        final ids = userIds.toSet().toList(growable: false);
        if (ids.isEmpty) return const <String, ComplaintActor>{};
        final rows = await db
            .from('users')
            .select('id, full_name, role')
            .inFilter('id', ids);
        return {
          for (final row in rows)
            reqString(row, 'users', 'id'): ComplaintActor(
              id: reqString(row, 'users', 'id'),
              fullName: reqString(row, 'users', 'full_name'),
              role: reqString(row, 'users', 'role'),
            ),
        };
      });

  /// Raise a complaint, with or without a photo. Residents only.
  ///
  /// The insert policy requires `student_id = app.current_student_id()` AND
  /// `hostel_id = app.user_hostel_id()`, so passing someone else's ids fails at the server
  /// with 42501 rather than succeeding. Both are still passed explicitly because the columns
  /// are NOT NULL — the server checks them, it does not fill them in.
  ///
  /// ═══ THE PHOTO IS OPTIONAL AND THE ORDER IS DELIBERATE ═══
  /// [photo] null is the ordinary case, not a degraded one: a resident with a broken tap and a
  /// dead camera must still be able to complain, so nothing about this method changes shape
  /// when there is no attachment.
  ///
  /// When there IS one, the bytes go up FIRST and the row second, because the row needs the
  /// key. That leaves one window worth naming: an upload that succeeded followed by an insert
  /// that did not, which would strand an object in the bucket with nothing pointing at it.
  /// [ComplaintPhotos.discard] closes it — but ONLY when the failure knows the row did not
  /// land. A timed-out insert is [SideEffect.unknown]: the transaction may be committing at
  /// the instant the deadline passes, and deleting the photo of a complaint that DID land is a
  /// worse outcome than an orphan nobody sees. The server refuses to delete a referenced
  /// object anyway (the `discard` action re-checks), so this is belt and braces on a race that
  /// costs bytes either way.
  ///
  /// ═══ THE UPLOAD IS OUTSIDE THE guardWrite, ON PURPOSE ═══
  /// It has its own, longer deadline ([ComplaintPhotos.uploadDeadline]) because pushing 300 KB
  /// up a stairwell connection is a different kind of wait from an INSERT. Wrapping both in
  /// one 12s guard would report a slow photo as a failed complaint.
  @override
  Future<Complaint> create({
    required String hostelId,
    required String studentId,
    required ComplaintCategory category,
    required String title,
    String? description,
    CapturedDocument? photo,
  }) async {
    final key = photo == null ? null : await photos.upload(photo);
    try {
      return await guardWrite(() async {
        final row = await db
            .from('complaints')
            .insert({
              'hostel_id': hostelId,
              'student_id': studentId,
              'category': category.wire,
              'title': title,
              'description': ?description,
              'photo_url': ?key,
            })
            .select(Complaint.columns)
            .single();
        return Complaint.fromJson(row);
      }, unresolved: 'Check your complaints before raising it again — the first one may already '
          'be there.');
    } catch (error) {
      if (key != null && error is AppFailure && error.sideEffect == SideEffect.none) {
        await photos.discard(key);
      }
      rethrow;
    }
  }

  /// Move a complaint along. Owner and warden only.
  ///
  /// `resolved_at`, the timeline row and the resident's notification are all produced by
  /// triggers off this one update — do not write them from here.
  Future<Complaint> updateStatus({
    required String complaintId,
    required ComplaintStatus status,
    String? resolutionNote,
  }) =>
      guardWrite(() async {
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
      }, unresolved: 'Reload the complaint before moving it again; setting the same status a '
          'second time is safe — the timeline and the resident are only notified when it really '
          'changes.');
}
