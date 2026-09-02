library;

import '../../../data/models/models.dart';

/// What the owner has typed into the compose sheet, before anything has been sent.
///
/// A VALUE, NOT THE THREE CONTROLLERS. The sheet holds `TextEditingController`s; this is the
/// snapshot the validator and the repository both work from, so "what is being validated" and
/// "what will be posted" cannot drift apart between the check and the send.
class NoticeDraft {
  const NoticeDraft({
    required this.title,
    required this.body,
    this.audience = NoticeAudience.all,
  });

  /// Exactly as typed. Trimming happens in [trimmedTitle] / [trimmedBody] so the validator and
  /// the send agree on what the stored value will be — see [validateNoticeDraft].
  final String title;
  final String body;
  final NoticeAudience audience;

  String get trimmedTitle => title.trim();
  String get trimmedBody => body.trim();
}

/// `announcements_text_len` in db/schema.sql: `length(title) <= 200 and length(body) <= 4000`.
///
/// Named here so the field counters, the validator and the constraint cannot disagree. If the
/// constraint moves, this moves with it — a client limit that is looser than the database's is
/// a write that fails at the last possible moment with a 23514 nobody can act on.
const noticeTitleMaxLength = 200;
const noticeBodyMaxLength = 4000;

/// What is wrong with this draft, keyed by field name, empty when nothing is.
///
/// THE EMPTY CHECKS ARE ON THE TRIMMED VALUE, and that is the whole point of them. A title of
/// three spaces is not a title: `announcements.title` is `not null` but it is not `check
/// (length(btrim(title)) > 0)`, so Postgres would accept it happily and every resident in the
/// hostel would get a notification for a blank line. The database cannot refuse this one, so
/// the client has to.
///
/// THE LENGTH CHECKS ARE ALSO ON THE TRIMMED VALUE, because the trimmed value is what
/// [NoticeDraft.trimmedTitle] sends — validating the untrimmed string would refuse a 200-character
/// title with a trailing newline that would in fact have stored fine.
///
/// Keys are the field names the sheet uses for `errorText`, so a message lands under the box it
/// is about rather than in a banner at the bottom.
Map<String, String> validateNoticeDraft(NoticeDraft draft) {
  final errors = <String, String>{};

  final title = draft.trimmedTitle;
  if (title.isEmpty) {
    errors['title'] = 'Give the notice a title.';
  } else if (title.length > noticeTitleMaxLength) {
    errors['title'] = 'Keep the title under $noticeTitleMaxLength characters.';
  }

  final body = draft.trimmedBody;
  if (body.isEmpty) {
    errors['body'] = 'Write what the notice says.';
  } else if (body.length > noticeBodyMaxLength) {
    errors['body'] = 'Keep the notice under $noticeBodyMaxLength characters.';
  }

  return errors;
}

/// Who a notice is addressed to, in the order the sheet offers them.
///
/// `all` FIRST AND SELECTED BY DEFAULT, because it is what the owner asked for ("send notices to
/// everyone") and what a hostel notice usually is. The other three are offered rather than
/// hidden: `announcement_audience` has had them since the first migration, the select policy
/// already enforces them row by row, and a "staff only" notice that reaches the residents is a
/// worse outcome than one extra control on a sheet.
const noticeAudienceChoices = <NoticeAudience>[
  NoticeAudience.all,
  NoticeAudience.students,
  NoticeAudience.warden,
  NoticeAudience.manager,
];

/// One line under the audience picker saying who will actually see it, in people-words.
///
/// The enum's own [NoticeAudience.label] names the group ("Everyone", "Wardens"); this says what
/// choosing it DOES, which is the part that decides the tap. It is also the honest place to say
/// that the owner is not in the audience — `app.announcements_after_insert` excludes
/// `new.author_user_id` from the fan-out, so nobody is ever notified of their own notice.
String noticeAudienceDescription(NoticeAudience audience) => switch (audience) {
      NoticeAudience.all =>
        'Residents, the warden and the manager. Everyone gets a notification.',
      NoticeAudience.students => 'Residents only. Staff will not see this notice.',
      NoticeAudience.warden => 'The warden only. Residents will not see this notice.',
      NoticeAudience.manager => 'The manager only. Residents will not see this notice.',
    };
