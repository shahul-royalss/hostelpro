library;

import '../models/models.dart';
import 'repository.dart';

/// The two writes behind the owner's noticeboard, as an interface.
///
/// The list is a plain read, and a screen that reads is tested by overriding the provider that
/// holds the answer. These two are not: one FANS OUT A NOTIFICATION to every person in the
/// audience — a thing that cannot be undone by deleting the notice afterwards — and the other
/// takes a notice off every one of those people's screens. Their interesting states (a
/// validator refusing an empty body, an owner whose subscription has lapsed, a retraction RLS
/// refused) are exactly what belongs in `flutter test`, and a test needs a stand-in for them.
/// Same shape and same reasoning as `OwnerStaffWrites`.
abstract interface class NoticeWrites {
  Future<Notice> create({
    required String hostelId,
    required String title,
    required String body,
    NoticeAudience audience,
  });

  Future<void> softDelete({required String noticeId});
}

/// Announcements — the noticeboard.
///
/// TABLES: public.announcements.
final class NoticeRepository extends Repository implements NoticeWrites {
  const NoticeRepository(super.db);

  /// The noticeboard for whoever is asking, newest first.
  ///
  /// THE AUDIENCE FILTER IS ALREADY APPLIED, by RLS, before these rows exist on this device. A
  /// student's request returns 'all' and 'students' notices and nothing else. There is
  /// deliberately no `audience:` parameter to narrow it further from here — a filter the client
  /// applies on top of a policy is decoration, and the day someone "fixes" it is the day
  /// managers stop seeing their own notices.
  Future<PagedResult<Notice>> page({
    required String hostelId,
    int page = 0,
    int pageSize = PagedResult.defaultPageSize,
  }) =>
      guard(() async {
        final bounds = rangeFor(page, pageSize);
        final rows = await db
            .from('announcements')
            .select(Notice.columns)
            .eq('hostel_id', hostelId)
            // Redundant with the select policy, which already excludes soft-deleted rows.
            // Kept because it costs nothing and makes the intent legible at the call site.
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .range(bounds.from, bounds.to);
        return PagedResult.fromOverfetch(
          rows.map(Notice.fromJson).toList(growable: false),
          page: page,
          pageSize: pageSize,
        );
      });

  Future<Notice?> byId(String noticeId) => guard(() async {
        // A null from here is drawn as a sentence about the reader ("not visible",
        // "belongs to another hostel", "no record for this account"). That sentence is
        // earned only when a live credential asked — a dead session makes this an
        // anonymous read whose null means nothing. See Repository.requireLiveSession.
        requireLiveSession('announcements.byId');
        final row = await db
            .from('announcements')
            .select(Notice.columns)
            .eq('id', noticeId)
            .maybeSingle();
        return row == null ? null : Notice.fromJson(row);
      });

  /// Post a notice. Owner only.
  ///
  /// `author_user_id` must equal auth.uid() — the insert policy checks it, so a notice cannot
  /// be published under another name even by a caller who edits the request. Posting also fans
  /// Display name and role for everyone who has posted a live notice at this hostel.
  ///
  /// One call per screen rather than a join per row: the set of authors at a hostel is a handful
  /// of staff, the notice list is paged, and joining would mean re-reading the same three names
  /// on every page. The screen maps author_user_id onto this and falls back to nothing when an
  /// id is missing — a notice whose author has since been deleted still renders, without a name.
  Future<List<NoticeAuthor>> authors(String hostelId) => guard(() async {
        final data = await db.rpc('notice_authors', params: {'p_hostel_id': hostelId});
        final rows = (data as List).cast<Map<String, dynamic>>();
        return rows.map(NoticeAuthor.fromJson).toList(growable: false);
      });

  /// out a notification to every user in the audience, via app.announcements_after_insert.
  @override
  Future<Notice> create({
    required String hostelId,
    required String title,
    required String body,
    NoticeAudience audience = NoticeAudience.all,
  }) =>
      guardWrite(() async {
        final authorId = db.auth.currentUser?.id;
        if (authorId == null) {
          throw const SignedOutFailure('Sign in again to post a notice.');
        }
        final row = await db
            .from('announcements')
            .insert({
              'hostel_id': hostelId,
              'author_user_id': authorId,
              'title': title,
              'body': body,
              'audience': audience.wire,
            })
            .select(Notice.columns)
            .single();
        return Notice.fromJson(row);
      }, unresolved: 'Check the noticeboard before posting again — posting notifies everyone in '
          'the audience, and a second notice notifies them a second time.');

  /// Edit a notice already posted. Owner only.
  ///
  /// Note the notification fan-out is on INSERT only — editing does not re-notify. That is the
  /// database's decision, not an omission here.
  Future<Notice> update({
    required String noticeId,
    String? title,
    String? body,
    NoticeAudience? audience,
  }) =>
      guardWrite(() async {
        final patch = <String, dynamic>{
          'title': ?title,
          'body': ?body,
          if (audience != null) 'audience': audience.wire,
        };
        if (patch.isEmpty) {
          throw const InvalidInputFailure('Nothing to change.');
        }
        final row = await db
            .from('announcements')
            .update(patch)
            .eq('id', noticeId)
            .select(Notice.columns)
            .single();
        return Notice.fromJson(row);
      }, unresolved: 'Reload the notice to see which version was saved; editing again is safe, '
          'because an edit does not re-notify anyone.');

  /// Retract a notice. Owner only. Soft: `deleted_at` is stamped, the row survives.
  ///
  /// ═══ WHY THIS IS AN RPC AND NOT `.update({'deleted_at': ...})` ═══
  /// Because the plain update is REFUSED, and not by a policy anyone can loosen from here.
  /// `announcements_select` is `deleted_at is null and (...)`, and PostgreSQL applies a table's
  /// SELECT policy to the NEW row of an UPDATE — a row may not be updated out of the updater's
  /// own visibility. Stamping `deleted_at` makes the new row invisible under that policy, so
  /// the write comes back 42501 for the hostel's real owner, at aal2, with a WITH CHECK that
  /// provably passes. Measured against a scratch table whose UPDATE policy was literally
  /// `with check (true)`: still refused. And `announcements_delete` is service-role only, so
  /// there is no hard-delete fallback either.
  ///
  /// `ow_delete_announcement` re-checks ownership and the §4.4 read-only gate server-side and
  /// raises 42501 on either, which surfaces here as [AccessDeniedFailure] or [ReadOnlyFailure].
  /// See db/migrations/2026-09-02-announcement-soft-delete.sql.
  ///
  /// IDEMPOTENT ON THE SERVER, which is why the unresolved advice can be as calm as it is: a
  /// notice already retracted, or an id that is gone, returns quietly rather than raising.
  @override
  Future<void> softDelete({required String noticeId}) => guardWrite(() async {
        await db.rpc('ow_delete_announcement', params: {'p_announcement_id': noticeId});
      }, unresolved: 'Reload the noticeboard to see whether it went; retracting the same notice '
          'again is safe, because the server treats a second retraction as already done.');
}
