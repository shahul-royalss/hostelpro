library;

import '../models/models.dart';
import 'repository.dart';

/// Announcements — the noticeboard.
///
/// TABLES: public.announcements.
final class NoticeRepository extends Repository {
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
  /// out a notification to every user in the audience, via app.announcements_after_insert.
  Future<Notice> create({
    required String hostelId,
    required String title,
    required String body,
    NoticeAudience audience = NoticeAudience.all,
  }) =>
      guard(() async {
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
      });

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
      guard(() async {
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
      });
}
