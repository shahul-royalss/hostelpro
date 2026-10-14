library;

import '../../core/auth/session.dart';
import 'enums.dart';
import 'parse.dart';

/// public.announcements — called a Notice everywhere in this app's UI.
///
/// THE AUDIENCE FILTER IS NOT DONE HERE. rls-policies.sql decides which rows a caller sees: an
/// owner sees all of their hostel's, a manager sees 'all' and 'manager', a warden 'all' and
/// 'warden', a student 'all' and 'students'. [audience] is carried so a notice can be labelled
/// on screen — filtering on it in Dart would be decoration over a control that already ran,
/// and would quietly hide rows on the day the policy changes.
class Notice {
  const Notice({
    required this.id,
    required this.hostelId,
    required this.authorUserId,
    required this.title,
    required this.body,
    required this.audience,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const columns =
      'id, hostel_id, author_user_id, title, body, audience, created_at, updated_at, deleted_at';

  final String id;
  final String hostelId;

  /// Must equal auth.uid() on insert — the RLS policy checks it, so a notice cannot be posted
  /// under someone else's name.
  final String authorUserId;
  final String title;
  final String body;
  final NoticeAudience audience;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Soft delete. The select policy already excludes non-null rows, so this is effectively
  /// always null on anything read here; it is kept because the column exists.
  final DateTime? deletedAt;

  factory Notice.fromJson(Map<String, dynamic> row) {
    const src = 'announcements';
    return Notice(
      id: reqString(row, src, 'id'),
      hostelId: reqString(row, src, 'hostel_id'),
      authorUserId: reqString(row, src, 'author_user_id'),
      title: reqString(row, src, 'title'),
      body: reqString(row, src, 'body'),
      audience: wireOrThrow(NoticeAudience.values, row['audience'], src, 'audience'),
      createdAt: reqTimestamp(row, src, 'created_at'),
      updatedAt: reqTimestamp(row, src, 'updated_at'),
      deletedAt: optTimestamp(row, src, 'deleted_at'),
    );
  }
}

/// Who wrote a notice: a display name and the post they hold, and nothing else.
///
/// Comes from public.notice_authors(hostel_id), a SECURITY DEFINER read gated on the same
/// app.can_read_hostel() predicate the announcements select policy uses. It exists because a
/// resident cannot read public.users at all (§4.8), so the author_user_id already on every
/// notice was unresolvable from the client — the notice list said what was announced and never
/// who announced it.
///
/// It carries NO contact details on purpose. A name and a role is what a reader needs to know
/// who is speaking; a phone number would make this a way around the rule rather than a narrow
/// exception to it.
class NoticeAuthor {
  const NoticeAuthor({required this.userId, required this.fullName, this.role});

  final String userId;
  final String fullName;
  final UserRole? role;

  factory NoticeAuthor.fromJson(Map<String, dynamic> row) {
    const src = 'notice_authors';
    return NoticeAuthor(
      userId: reqString(row, src, 'user_id'),
      fullName: reqString(row, src, 'full_name'),
      // tryParse rather than a throwing parse: a role this build has not heard of is a
      // server that moved ahead of the app, and a notice is worth showing without a
      // subtitle rather than not at all.
      role: UserRole.tryParse(row['role'] as String?),
    );
  }
}
